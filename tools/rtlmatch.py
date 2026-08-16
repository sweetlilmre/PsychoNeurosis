"""Locate the Borland RTL segment in each part and measure how far it matches.

Borland smart-links the System unit, so each part keeps a different subset --
but retained routines land at identical offsets from the segment base. If that
holds, one offset->name table names the runtime in every binary at once.

Relocated words hold load-time segment values that differ per part, so they are
masked to zero before comparing; otherwise every far pointer looks like a diff.
"""
import argparse
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mzinfo import parse

LOAD_SEG = 0x1000
PROBE = 256


def masked_image(h):
    """Image bytes with every relocation target zeroed."""
    raw = bytearray(h["raw"])
    base = h["hdrsize"]
    for i in range(h["nreloc"]):
        off, seg = struct.unpack_from("<HH", raw, h["reloff"] + i * 4)
        fa = base + seg * 16 + off
        if fa + 2 <= len(raw):
            raw[fa:fa + 2] = b"\0\0"
    return bytes(raw)


def seg_file_offset(h, seg):
    return h["hdrsize"] + (seg * 16) - LOAD_SEG * 16


def common_prefix(a, b):
    n = min(len(a), len(b))
    i = 0
    while i < n and a[i] == b[i]:
        i += 1
    return i


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("ref")
    ap.add_argument("ref_seg", help="RTL segment base of reference, hex")
    ap.add_argument("ref_len", help="RTL segment length, hex")
    ap.add_argument("others", nargs="+")
    args = ap.parse_args()

    rh = parse(Path(args.ref))
    rmask = masked_image(rh)
    roff = seg_file_offset(rh, int(args.ref_seg, 16))
    rlen = int(args.ref_len, 16)
    rtl = rmask[roff:roff + rlen]
    probe = rtl[:PROBE]

    print(f"reference {Path(args.ref).name} seg {args.ref_seg} "
          f"file+{roff:#x} len {rlen:#x}")

    for p in args.others:
        h = parse(Path(p))
        mask = masked_image(h)
        idx = mask.find(probe, 0, h["imagesize"])
        name = Path(p).name
        if idx < 0:
            print(f"  {name:<22} RTL prologue NOT FOUND")
            continue
        seg = (idx - h["hdrsize"] + LOAD_SEG * 16) // 16
        other = mask[idx:h["imagesize"]]
        cp = common_prefix(rtl, other)
        n = min(len(rtl), len(other))
        same = sum(1 for i in range(n) if rtl[i] == other[i])
        print(f"  {name:<22} seg {seg:04x} file+{idx:#08x} "
              f"avail {len(other):<6} identical prefix {cp:<6} "
              f"overall {same / n:.1%} of {n}")


if __name__ == "__main__":
    main()
