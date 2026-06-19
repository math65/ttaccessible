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

Usage: scripts/patch-sdk-portaudio.py [path/to/libTeamTalk5.dylib]
"""
import subprocess, sys, os, struct

# "return paFormatIsSupported (0)" stubs, per arch:
STUBS = {
    "arm64":  bytes([0x00,0x00,0x80,0x52, 0xc0,0x03,0x5f,0xd6]),  # mov w0,#0 ; ret
    "x86_64": bytes([0x31,0xc0, 0xc3]),                            # xor eax,eax ; ret
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
        off = slice_off + vm  # __TEXT.vmaddr is 0, fileoff 0 -> file offset = slice + vmaddr
        cur = bytes(data[off:off+len(stub)])
        if cur == stub:
            skipped.append(arch); continue
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
