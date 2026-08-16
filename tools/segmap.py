"""Derive the real-mode segment layout of a 16-bit MZ image from its fixups.

Borland Pascal emits one code segment per unit. Every far call/pointer in the
image is relocated, so the set of segment values appearing in the relocation
table (and in the words those fixups point at) approximates the segment map --
which is exactly what Ghidra needs in order to disassemble past the first unit.
"""
import struct
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mzinfo import parse


def relocations(h):
    raw, out = h["raw"], []
    for i in range(h["nreloc"]):
        off, seg = struct.unpack_from("<HH", raw, h["reloff"] + i * 4)
        out.append((seg, off))
    return out


def main(paths):
    for p in paths:
        h = parse(Path(p))
        raw = h["raw"]
        relocs = relocations(h)
        image_start = h["hdrsize"]

        # The word each fixup patches holds the target segment, relative to the
        # program's load segment. Distinct values ~= distinct code segments.
        targets = Counter()
        for seg, off in relocs:
            fa = image_start + seg * 16 + off
            if fa + 2 <= len(raw):
                targets[struct.unpack_from("<H", raw, fa)[0]] += 1

        print(f"\n=== {h['file']} ===")
        print(f"  header {h['hdrsize']}  image {h['imagesize']}  "
              f"code+data {h['imagesize'] - image_start} bytes")
        print(f"  entry CS:IP {h['cs']:04X}:{h['ip']:04X}   "
              f"stack SS:SP {h['ss']:04X}:{h['sp']:04X}   "
              f"extra heap {h['minalloc']*16} bytes")
        print(f"  {len(relocs)} fixups -> {len(targets)} distinct target segments")
        for segv, n in sorted(targets.items()):
            fileoff = image_start + segv * 16
            note = "" if fileoff < h["imagesize"] else "  (beyond image: stack/heap/DGROUP)"
            print(f"    seg {segv:04X}  file offset {fileoff:#08x}  {n:>4} refs{note}")


if __name__ == "__main__":
    main(sys.argv[1:])
