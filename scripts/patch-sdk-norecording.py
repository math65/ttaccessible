#!/usr/bin/env python3
"""
Patch libTeamTalk5.dylib so a channel's CHANNEL_NO_RECORDING flag no longer
suppresses per-user audio-block delivery.

WHY: In a channel with CHANNEL_NO_RECORDING set, the SDK decodes and *plays* each
remote user's voice through its own output device, but refuses to expose the decoded
PCM via TT_AcquireUserAudioBlock / CLIENTEVENT_USER_AUDIOBLOCK — it treats raw-block
access as "recording". The Qt/iOS clients are unaffected because they let the SDK play
the audio. tt-Accessible, by design, points the SDK at the TeamTalk *virtual* output
device (never a real one — that is the connect-speed / device-switch-deadlock cure) and
sources 100% of its playback from those audio blocks (OutputAudioRenderEngine, per-user
mix). So in a NO_RECORDING channel the app is simply SILENT: packets arrive, the SDK
sees the user talking, but zero blocks are delivered. Confirmed in the field on a server
whose main channel carries the flag (issue #25 "random loss of audio" is very likely
this: an op toggles the flag, or a user enters such a channel, and audio "disappears").

The gate lives in teamtalk::AudioPlayer::StreamPlayerCb (StreamPlayers.cpp):

    // store in AudioMuxer before resampling
    if (!m_no_recording) {
        if (stopped_talking || new_stream)
            m_audio_callback(...);   // end-of-stream frame
        m_audio_callback(...);       // normal frame  <-- our only source of playback
    }

Compiled, that is two guards per arch that branch *over* the callback block when the
m_no_recording member is set:
  arm64 : ldrb w8,[x21,#0xa9] ; tbnz w8,#0,<skip>
  x86_64: cmpb $0,0xb9(%r15)  ; jne   <skip>

THE PATCH: NOP the two branch instructions per arch. The member is still loaded/compared
(harmless) but the branch is never taken, so the callback block always runs and audio
blocks are delivered exactly as in a normal channel. This does NOT make the app record
anything — it only restores *playback*. The app enforces the channel's recording policy
itself: the ⌘R / ⌘⇧R recording actions are disabled in a NO_RECORDING channel (see
AppDelegate recording guards), matching the Qt client's UI behaviour.

Symbol-driven (finds StreamPlayerCb via nm per arch); the two guards sit at fixed
offsets inside the function, verified against an allowlist of the known-good branch bytes
before overwriting. Idempotent (re-running is a no-op). Patches every arch slice
(arm64 + x86_64) in the universal dylib, then re-signs adhoc.

FAILS LOUDLY: if the bytes at a guard are neither the known branch nor the NOP stub, the
script aborts (exit 1) rather than clobber an unknown instruction stream. A future SDK
that moves the guards or changes the member offset will mismatch here — update
GUARDS / BRANCH_BYTES below after verifying the new instructions by hand.

Usage: scripts/patch-sdk-norecording.py [path/to/libTeamTalk5.dylib]
"""
import subprocess, sys, os

SYMBOL = "__ZN8teamtalk11AudioPlayer14StreamPlayerCbERKN11soundsystem14OutputStreamerEPsi"

# NOP that replaces each branch, per arch.
NOP = {
    "arm64":  bytes([0x1f, 0x20, 0x03, 0xd5]),              # nop
    "x86_64": bytes([0x66, 0x0f, 0x1f, 0x44, 0x00, 0x00]),  # 6-byte nop
}
# Guard branch instructions to NOP: offset relative to the StreamPlayerCb symbol, and
# the exact branch bytes there in the known-good (v5.22a) build. Two per arch: the guard
# on the end-of-stream callback and the guard on the normal per-frame callback. Both
# branch over the m_audio_callback block when m_no_recording is set.
GUARDS = {
    "arm64": [
        (0xf8,  bytes([0x28, 0x09, 0x00, 0x37])),   # tbnz w8,#0,+0x124
        (0x16c, bytes([0x88, 0x05, 0x00, 0x37])),   # tbnz w8,#0,+0xb0
    ],
    "x86_64": [
        (0xfe,  bytes([0x0f, 0x85, 0x80, 0x01, 0x00, 0x00])),  # jne +0x186
        (0x1a8, bytes([0x0f, 0x85, 0xd6, 0x00, 0x00, 0x00])),  # jne +0xdc
    ],
}
# The instruction immediately preceding each guard must be the m_no_recording test —
# asserted so we never NOP an unrelated branch that happens to land at the offset.
PRECEDING = {
    "arm64":  (0x4, bytes([0xa8, 0xa6, 0x42, 0x39])),                          # ldrb w8,[x21,#0xa9]
    "x86_64": (0x8, bytes([0x41, 0x80, 0xbf, 0xb9, 0x00, 0x00, 0x00, 0x00])),  # cmpb $0,0xb9(%r15)
}

def fat_slice_offsets(path):
    """arch -> file offset of its Mach-O slice (0 if thin)."""
    out = subprocess.check_output(["otool", "-f", path], text=True, stderr=subprocess.DEVNULL)
    offs, cur = {}, None
    cputype_to_arch = {16777223: "x86_64", 16777228: "arm64"}
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("cputype"):
            cur = cputype_to_arch.get(int(s.split()[1]))
        elif s.startswith("offset") and cur:
            offs[cur] = int(s.split()[1]); cur = None
    if not offs:  # thin binary
        a = subprocess.check_output(["lipo", "-info", path], text=True).split(":")[-1].strip()
        offs[a] = 0
    return offs

def symbol_vmaddr(path, arch):
    out = subprocess.check_output(["nm", "-arch", arch, path], text=True, stderr=subprocess.DEVNULL)
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2] == SYMBOL:
            return int(parts[0], 16)
    return None

def text_segment_origin(path, arch):
    """(__TEXT.vmaddr, __TEXT.fileoff); offset math needs both == 0 (see portaudio patch)."""
    out = subprocess.check_output(["otool", "-arch", arch, "-l", path], text=True, stderr=subprocess.DEVNULL)
    in_text, vmaddr, fileoff = False, None, None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("segname "):
            in_text = (s.split()[1] == "__TEXT")
        elif in_text and s.startswith("vmaddr ") and vmaddr is None:
            vmaddr = int(s.split()[1], 16)
        elif in_text and s.startswith("fileoff ") and fileoff is None:
            fileoff = int(s.split()[1]); break
    return vmaddr, fileoff

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(__file__), "..", "Vendor", "TeamTalk", "libTeamTalk5.dylib")
    path = os.path.abspath(path)
    if not os.path.exists(path):
        print(f"error: {path} not found", file=sys.stderr); sys.exit(1)

    slices = fat_slice_offsets(path)
    data = bytearray(open(path, "rb").read())
    patched, skipped = [], []
    for arch, slice_off in slices.items():
        guards = GUARDS.get(arch)
        if not guards:
            print(f"  {arch}: no guards defined, skipping"); continue
        vm = symbol_vmaddr(path, arch)
        if vm is None:
            print(f"  {arch}: {SYMBOL} not found, skipping"); continue
        tvm, tfo = text_segment_origin(path, arch)
        if tvm != 0 or tfo != 0:
            print(f"error: {arch} __TEXT vmaddr=0x{tvm:X} fileoff={tfo}, expected 0/0 — "
                  f"offset math invalid. Aborting.", file=sys.stderr)
            sys.exit(1)
        stub = NOP[arch]
        pre_delta, pre_bytes = PRECEDING[arch]
        for reloff, branch in guards:
            off = slice_off + vm + reloff
            cur = bytes(data[off:off + len(stub)])
            if cur == stub:
                skipped.append(f"{arch}@0x{off:X}"); continue
            if cur != branch:
                print(f"error: {arch} guard at 0x{off:X} is {cur.hex()}, neither the known "
                      f"branch ({branch.hex()}) nor the NOP stub. SDK build likely changed — "
                      f"refusing to patch. Re-verify the StreamPlayerCb guards by hand and "
                      f"update GUARDS['{arch}'].", file=sys.stderr)
                sys.exit(1)
            # Guard the guard: the m_no_recording test must sit right before the branch.
            pre_off = off - pre_delta
            pre_cur = bytes(data[pre_off:pre_off + len(pre_bytes)])
            if pre_cur != pre_bytes:
                print(f"error: {arch} instruction before guard at 0x{off:X} is {pre_cur.hex()}, "
                      f"expected the m_no_recording test ({pre_bytes.hex()}). Aborting.",
                      file=sys.stderr)
                sys.exit(1)
            data[off:off + len(stub)] = stub
            patched.append(f"{arch}@0x{off:X}")

    if not patched:
        print(f"Already patched ({', '.join(skipped) or 'no slices'}). No change."); return

    open(path, "wb").write(data)
    print("Patched StreamPlayerCb no_recording guards -> NOP in:", ", ".join(patched))
    if skipped: print("  (already patched:", ", ".join(skipped) + ")")
    subprocess.check_call(["codesign", "--force", "--sign", "-", path])
    subprocess.check_call(["codesign", "--verify", path])
    print("Re-signed adhoc and verified.")

if __name__ == "__main__":
    main()
