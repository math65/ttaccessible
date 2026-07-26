#!/usr/bin/env python3
"""
Patch libTeamTalk5.dylib so PortAudio's startup device probe is skipped.

WHY: TT_InitTeamTalkPoll (SDK instance creation) makes the bundled PortAudio probe
every audio device's supported sample rates by actually opening+closing a CoreAudio
stream for each device x each standard rate (~956 stream opens on a large rig). That
is the ~13 s "slow connect" on Rocco's machine. The probe lives in PortAudio's
IsFormatSupported() (pa_mac_core.c), which calls OpenStream just to test a format.

THE PATCH: overwrite IsFormatSupported's prologue so it returns paFormatIsSupported (0)
immediately, before opening anything. This is safe for ttAccessible because the app
never uses a real PortAudio device — input and output both go through the TeamTalk
virtual device (TT_SOUNDDEVICE_ID_TEAMTALK_VIRTUAL) feeding our own CoreAudio engines.
Verified: device enumeration (TT_GetSoundDevices) and virtual-device init are byte-for-
byte identical to the unpatched dylib; first TT_InitTeamTalkPoll drops 13.3 s -> 0.2 s.

Symbol-driven (finds _IsFormatSupported via nm per arch) so it survives SDK version
bumps where the offset moves. Idempotent: re-running is a no-op. Patches every arch
slice (arm64 + x86_64) in the universal dylib, then re-signs adhoc.

FAILS LOUDLY: before overwriting, the bytes at the symbol are checked against an
allowlist of the known-good unpatched prologue (per arch). If a future SDK keeps the
symbol but emits a different prologue, those bytes won't match -> the script aborts
(exit 1) instead of clobbering an unknown instruction stream and shipping a corrupt
dylib. The file-offset math (off = slice_off + symbol_vmaddr) is only valid when the
__TEXT segment has vmaddr==0 and fileoff==0, so that is asserted explicitly per arch.

Usage: scripts/patch-sdk-portaudio.py [path/to/libTeamTalk5.dylib]
"""
import subprocess, sys, os, struct

# "return paFormatIsSupported (0)" stubs, per arch:
STUBS = {
    "arm64":  bytes([0x00,0x00,0x80,0x52, 0xc0,0x03,0x5f,0xd6]),  # mov w0,#0 ; ret
    "x86_64": bytes([0x31,0xc0, 0xc3]),                            # xor eax,eax ; ret
}
# Allowlist of the known-good UNPATCHED prologue bytes the stub overwrites (same length
# as the stub, per arch). Captured from the BearWare v5.22a universal build. A new SDK
# may legitimately add entries here, but a SILENT mismatch must never be patched over.
ORIGINAL_PROLOGUES = {
    "arm64":  [bytes([0xff,0x43,0x01,0xd1, 0xe9,0x23,0x02,0x6d])],  # sub sp,sp,#0x50 ; stp d9,d8,[sp,#0x20]
    "x86_64": [bytes([0x55, 0x48,0x89])],                           # push rbp ; (mov rbp,rsp)
}
SYMBOL = "_IsFormatSupported"

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
    """(__TEXT.vmaddr, __TEXT.fileoff) for the given arch slice.

    The offset math `off = slice_off + symbol_vmaddr` is only correct when both are 0
    (so a symbol's vmaddr equals its offset inside the slice). Returns them so the
    caller can assert that assumption rather than trusting it blindly."""
    out = subprocess.check_output(["otool", "-arch", arch, "-l", path], text=True, stderr=subprocess.DEVNULL)
    in_text, vmaddr, fileoff = False, None, None
    for line in out.splitlines():
        s = line.strip()
        if s.startswith("segname "):
            in_text = (s.split()[1] == "__TEXT")
        elif in_text and s.startswith("vmaddr ") and vmaddr is None:
            vmaddr = int(s.split()[1], 16)
        elif in_text and s.startswith("fileoff ") and fileoff is None:
            fileoff = int(s.split()[1])
            break
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
        stub = STUBS.get(arch)
        if not stub:
            print(f"  {arch}: no stub defined, skipping"); continue
        vm = symbol_vmaddr(path, arch)
        if vm is None:
            print(f"  {arch}: {SYMBOL} not found, skipping"); continue
        # off = slice_off + symbol_vmaddr is only valid when __TEXT is mapped at vmaddr 0
        # with fileoff 0. Assert it instead of assuming it.
        tvm, tfo = text_segment_origin(path, arch)
        if tvm != 0 or tfo != 0:
            print(f"error: {arch} __TEXT vmaddr=0x{tvm:X} fileoff={tfo}, expected 0/0 — "
                  f"offset math is invalid for this layout. Aborting.", file=sys.stderr)
            sys.exit(1)
        off = slice_off + vm  # __TEXT.vmaddr==0, fileoff==0 -> file offset = slice + vmaddr
        cur = bytes(data[off:off+len(stub)])
        if cur == stub:
            skipped.append(arch); continue
        # Fail loudly rather than clobber an unknown prologue (e.g. a future SDK whose
        # IsFormatSupported keeps its symbol but changes its instructions).
        if cur not in ORIGINAL_PROLOGUES.get(arch, []):
            print(f"error: {arch} {SYMBOL} prologue at 0x{off:X} is {cur.hex()}, which is "
                  f"neither the patched stub nor a known unpatched prologue. The SDK build "
                  f"likely changed — refusing to patch (would corrupt the dylib). Update "
                  f"ORIGINAL_PROLOGUES['{arch}'] after verifying the new prologue by hand.",
                  file=sys.stderr)
            sys.exit(1)
        data[off:off+len(stub)] = stub
        patched.append(f"{arch}@0x{off:X}")

    if not patched:
        print(f"Already patched ({', '.join(skipped) or 'no slices'}). No change."); return

    open(path, "wb").write(data)
    print("Patched IsFormatSupported -> return-supported in:", ", ".join(patched))
    if skipped: print("  (already patched:", ", ".join(skipped) + ")")
    subprocess.check_call(["codesign", "--force", "--sign", "-", path])
    subprocess.check_call(["codesign", "--verify", path])
    print("Re-signed adhoc and verified.")

if __name__ == "__main__":
    main()
