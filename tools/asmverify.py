"""Compare the assembled 386 maths routines against the original's bytes.

The three routines in src/asm/DEMOMATH.ASM are meant to be a transcription,
not an approximation, so the check that matters is whether TASM emits the same
instruction bytes the 1994 build did. This finds each routine in a freshly
built executable and diffs it against the binary it was read from.

Bytes that CANNOT match are masked out before the comparison:

  * memory displacements into DGROUP -- the six sin/cos values, the scale and
    the two view dimensions sit wherever Turbo Pascal put them;
  * the two displacements into the cosine table, for the same reason;
  * the call/jump targets are all internal and relative, so those DO match.

Anything else differing is a real divergence and gets printed.

    python tools/dosbox/dosbuild.py TP1S5     build something that links it
    python tools/asmverify.py                 then check it
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

# Header sizes of the split executables, so a seg:ofs maps to a file offset:
# header + (seg - $1000) * 16 + ofs.
ORIGINALS = {
    "001": ("work/split/NEUROSIS_001_fpu.exe", 0x410),
    "002": ("work/split/NEUROSIS_002_fpu.exe", 0x400),
}

# name, part, segment, start, end (exclusive)
ROUTINES = [
    ("SinCos",      "001", 0x1107, 0x1804, 0x18B5),
    ("RotatePoint", "001", 0x1107, 0x18B6, 0x1A04),
    ("Project",     "001", 0x1107, 0x1A04, 0x1AAB),
]

# Where a built harness that links DEMOMATH.OBJ can be found.
BUILT = "run/TP1S5.EXE"

# How many leading bytes to match on when locating the routine. The prologue
# is fixed-length and fixup-free, so ten is plenty and unambiguous.
PROBE = 10


def masked(data, holes):
    out = bytearray(data)
    for start, length in holes:
        for i in range(start, start + length):
            out[i] = 0
    return bytes(out)


def find_holes(code):
    """Offsets of the 16-bit displacements that cannot match, and their length.

    Two shapes appear:
      66 F7 2E dd dd        IMUL DWORD PTR [disp16]   -- a DGROUP variable
      66 2E 8B 87 dd dd     MOV EAX, CS:[BX+disp16]   -- the cosine table
      66 2E 8B 97 dd dd     MOV EDX, CS:[BX+disp16]
      A1 dd dd / 8B 16 dd dd  MOV AX,[disp16]         -- MViewW / MViewH
    """
    holes = []
    i = 0
    n = len(code)
    while i < n:
        if code[i:i + 3] == b"\x66\xF7\x2E":
            holes.append((i + 3, 2)); i += 5; continue
        if code[i:i + 4] in (b"\x66\x2E\x8B\x87", b"\x66\x2E\x8B\x97"):
            holes.append((i + 4, 2)); i += 6; continue
        if code[i:i + 1] == b"\xA1":
            holes.append((i + 1, 2)); i += 3; continue
        if code[i:i + 2] == b"\x8B\x16":
            holes.append((i + 2, 2)); i += 4; continue
        i += 1
    return holes


def main():
    built_path = ROOT / BUILT
    if not built_path.exists():
        print("%s not built -- run tools/dosbox/dosbuild.py TP1S5 first" % BUILT)
        return 1
    built = built_path.read_bytes()

    bad = 0
    for name, part, seg, start, end in ROUTINES:
        rel, hdr = ORIGINALS[part]
        blob = (ROOT / rel).read_bytes()
        base = hdr + (seg - 0x1000) * 16
        orig = blob[base + start:base + end]

        at = built.find(orig[:PROBE])
        if at < 0:
            print("%-12s NOT FOUND in %s" % (name, BUILT))
            bad += 1
            continue
        mine = built[at:at + len(orig)]

        holes = find_holes(orig)
        a = masked(orig, holes)
        b = masked(mine, find_holes(mine))
        diff = [k for k in range(len(a)) if a[k] != b[k]]

        if not diff:
            print("%-12s %3d bytes, %d masked displacement(s) -- IDENTICAL"
                  % (name, len(orig), len(holes)))
        else:
            bad += 1
            print("%-12s %3d bytes -- %d DIFFER" % (name, len(orig), len(diff)))
            for k in diff[:24]:
                print("      +%03X  orig %02X  built %02X" % (k, orig[k], mine[k]))
            if len(diff) > 24:
                print("      ... and %d more" % (len(diff) - 24))

    print("\n%d of %d routine(s) differ." % (bad, len(ROUTINES)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
