"""Decode floating-point constants out of a part's code segment.

Once the emulator traps have been rewritten to real x87 (tools/fpfix.py), the
FP constants the code loads become readable operands -- `FLD extended double
ptr CS:[0x2ef]`, `FADD float ptr CS:[0x2e7]` and so on. This turns those
addresses back into numbers.

Three formats show up:

  single    4 bytes, IEEE 754        FADD/FCOMP float ptr
  double    8 bytes, IEEE 754        FADD/FCOMP double ptr
  ext80    10 bytes, x87 long double FLD extended double ptr
  real48    6 bytes, BORLAND Real    not an x87 format at all -- this is the
                                     software Real that Turbo Pascal variables
                                     live in, and it is what you find in
                                     stack slots and DGROUP

Borland's Real48 is byte 0 = exponent biased by 129 (0 means the value is
zero), bytes 1..5 = mantissa with the sign in the top bit of byte 5 and an
implied leading 1.

Usage:
    python tools/fpconst.py 001 1082 2e7 single 2eb single 2ef ext80 2f9 single
"""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mzinfo import parse

SIZES = {"single": 4, "double": 8, "ext80": 10, "real48": 6}


def ext80(b):
    m = int.from_bytes(b[0:8], "little")
    se = int.from_bytes(b[8:10], "little")
    sign = -1 if se & 0x8000 else 1
    exp = se & 0x7FFF
    if exp == 0 and m == 0:
        return 0.0
    return sign * m * 2.0 ** (exp - 16383 - 63)


def real48(b):
    exp = b[0]
    if exp == 0:
        return 0.0
    sign = -1 if b[5] & 0x80 else 1
    frac = int.from_bytes(b[1:5], "little") | ((b[5] & 0x7F) << 32)
    return sign * (1 + frac / 2.0 ** 39) * 2.0 ** (exp - 129)


def decode(b, kind):
    if kind == "single":
        return struct.unpack("<f", b)[0]
    if kind == "double":
        return struct.unpack("<d", b)[0]
    if kind == "ext80":
        return ext80(b)
    if kind == "real48":
        return real48(b)
    raise ValueError(kind)


def read(part, seg, off, kind):
    """seg is the GHIDRA segment (e.g. 0x1082); the image base is 0x1000."""
    name = f"work/split/NEUROSIS_{part}_fpu.exe"
    if not Path(name).exists():
        name = f"work/split/NEUROSIS_{part}.exe"
    h = parse(Path(name))
    base = h["hdrsize"] + (seg - 0x1000) * 16
    b = h["raw"][base + off: base + off + SIZES[kind]]
    return b, decode(b, kind)


def main(argv):
    part, seg = argv[0], int(argv[1], 16)
    rest = argv[2:]
    for i in range(0, len(rest), 2):
        off, kind = int(rest[i], 16), rest[i + 1]
        b, v = read(part, seg, off, kind)
        print(f"  {seg:04X}:${off:04X}  {kind:<7} {b.hex(' '):<30} = {v!r}")


if __name__ == "__main__":
    main(sys.argv[1:])
