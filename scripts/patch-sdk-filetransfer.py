#!/usr/bin/env python3
"""
Patch libTeamTalk5.dylib so file transfers are no longer capped at 64 KiB per round trip.

WHY: When the SDK opens the TCP connection of a file transfer (upload or download), its
teamtalk::FileNode::OnOpened (FileNode.cpp) pins the socket's buffers:

    int size = FILEBUFFERSIZE;   // 0x10000
    handler.peer().set_option(SOL_SOCKET, SO_SNDBUF, &size, ...);
    handler.peer().set_option(SOL_SOCKET, SO_RCVBUF, &size, ...);

Setting SO_RCVBUF / SO_SNDBUF explicitly turns off macOS's TCP buffer autotuning, so at
most 64 KiB can be in flight: throughput <= 64 KiB / RTT, whatever the bandwidth. That is
~500 kB/s to a server 130 ms away, in both directions. Measured on a Mac, same HTTPS
download, socket options set exactly as the SDK sets them:
  RTT 100 ms: 642 kB/s pinned vs 20274 kB/s autotuned
  RTT 183 ms: 353 kB/s pinned vs  7600 kB/s autotuned
The server sets no buffer size and throttles nothing (ServerUser.cpp); the Qt client has
the same cap, since it uses the same SDK.

THE PATCH: overwrite the first instruction of both OnOpened variants (plain TCP and TLS)
with `ret`. They do nothing else: two setsockopt calls and the TTASSERTs on their result.
The sockets then keep the system's autotuned buffers. The SDK's own 64 KiB send queue
stays; it is refilled every time the socket becomes writable, so it does not cap the rate.

Symbol-driven (finds the two OnOpened symbols via nm per arch). Before patching, checks
the known-good prologue and that the function loads the 0x10000 buffer size at a fixed
offset, so an unrelated function is never patched. Idempotent (re-running is a no-op).
Patches every arch slice (arm64 + x86_64) in the universal dylib, then re-signs adhoc.

FAILS LOUDLY: if the bytes at a symbol are neither the known prologue nor the patched
one, or the buffer-size load is not where expected, the script aborts (exit 1) rather
than clobber an unknown instruction stream. Update PROLOGUES / SIZE_LOAD below after
verifying a new SDK's instructions by hand.

Usage: scripts/patch-sdk-filetransfer.py [path/to/libTeamTalk5.dylib]
"""
import subprocess, sys, os

SYMBOLS = [
    "__ZN8teamtalk8FileNode8OnOpenedER13StreamHandlerI15ACE_SOCK_StreamE",
    "__ZN8teamtalk8FileNode8OnOpenedER13StreamHandlerI15MySSLSockStreamE",
]
# (unpatched, patched) bytes at the start of each symbol, per arch. Only the first
# instruction changes; the x86_64 window includes the next one so the check is not a
# single byte.
PROLOGUES = {
    "arm64":  (bytes([0xff, 0xc3, 0x00, 0xd1]),          # sub sp,sp,#0x30
               bytes([0xc0, 0x03, 0x5f, 0xd6])),         # ret
    "x86_64": (bytes([0x55, 0x48, 0x89, 0xe5]),          # push rbp ; mov rbp,rsp
               bytes([0xc3, 0x48, 0x89, 0xe5])),         # ret      ; (unreached)
}
# The FILEBUFFERSIZE (0x10000) load, at a fixed offset from the symbol. Asserted before
# patching so we only ever touch the function that pins the buffers.
SIZE_LOAD = {
    "arm64":  (0x14, bytes([0x28, 0x00, 0xa0, 0x52])),                         # mov w8,#0x10000
    "x86_64": (0x09, bytes([0xc7, 0x45, 0xf4, 0x00, 0x00, 0x01, 0x00])),       # movl $0x10000,-0xc(%rbp)
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

def symbol_vmaddrs(path, arch):
    out = subprocess.check_output(["nm", "-arch", arch, path], text=True, stderr=subprocess.DEVNULL)
    found = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2] in SYMBOLS:
            found[parts[2]] = int(parts[0], 16)
    return found

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
        if arch not in PROLOGUES:
            print(f"  {arch}: no prologue defined, skipping"); continue
        tvm, tfo = text_segment_origin(path, arch)
        if tvm != 0 or tfo != 0:
            print(f"error: {arch} __TEXT vmaddr=0x{tvm:X} fileoff={tfo}, expected 0/0 — "
                  f"offset math invalid. Aborting.", file=sys.stderr)
            sys.exit(1)
        original, stub = PROLOGUES[arch]
        size_delta, size_bytes = SIZE_LOAD[arch]
        addrs = symbol_vmaddrs(path, arch)
        for symbol in SYMBOLS:
            vm = addrs.get(symbol)
            if vm is None:
                print(f"error: {arch} {symbol} not found. SDK build likely changed — "
                      f"refusing to patch.", file=sys.stderr)
                sys.exit(1)
            off = slice_off + vm
            size_cur = bytes(data[off + size_delta:off + size_delta + len(size_bytes)])
            if size_cur != size_bytes:
                print(f"error: {arch} {symbol}: bytes at +0x{size_delta:X} are {size_cur.hex()}, "
                      f"expected the 0x10000 buffer-size load ({size_bytes.hex()}). Aborting.",
                      file=sys.stderr)
                sys.exit(1)
            cur = bytes(data[off:off + len(stub)])
            if cur == stub:
                skipped.append(f"{arch}@0x{off:X}"); continue
            if cur != original:
                print(f"error: {arch} {symbol} prologue at 0x{off:X} is {cur.hex()}, neither the "
                      f"known prologue ({original.hex()}) nor the patched one. SDK build likely "
                      f"changed — refusing to patch. Update PROLOGUES['{arch}'] after verifying "
                      f"by hand.", file=sys.stderr)
                sys.exit(1)
            data[off:off + len(stub)] = stub
            patched.append(f"{arch}@0x{off:X}")

    if not patched:
        print(f"Already patched ({', '.join(skipped) or 'no slices'}). No change."); return

    open(path, "wb").write(data)
    print("Patched FileNode::OnOpened -> ret (no pinned socket buffers) in:", ", ".join(patched))
    if skipped: print("  (already patched:", ", ".join(skipped) + ")")
    subprocess.check_call(["codesign", "--force", "--sign", "-", path])
    subprocess.check_call(["codesign", "--verify", path])
    print("Re-signed adhoc and verified.")

if __name__ == "__main__":
    main()
