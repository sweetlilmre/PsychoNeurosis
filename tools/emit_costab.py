"""Emit the 16.16 cosine table the three fixed-point maths units share.

The table is 901 entries of 4 bytes -- cos(0.0 degrees) through cos(90.0), a
tenth of a degree apart -- and it lives in the CODE segment right next to the
routines that read it. It appears THREE times in the demo, once per unit that
links the maths object:

    NEUROSIS.001  1107:09F0   part 001 scene 4
    NEUROSIS.001  12C5:0B19   part 001 scene 5
    NEUROSIS.002  108B:261B   part 002 scene 2

All three are byte-identical, and every entry is exactly

    Round(cos(i / 10 degrees) * 65536)

with entry 0 = 65536 (1.0) and entry 900 = 0. This script reads the real bytes
out of the binary rather than recomputing them, checks the three copies agree
and checks them against that formula, then writes the DD table the assembler
module includes.

    python tools/emit_costab.py
"""
import math
import pathlib
import struct

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "src" / "asm" / "COSTAB.INC"

ENTRIES = 901

# (label, executable, file offset). The offset is header + (seg - $1000) * 16 +
# ofs, which is how the split executables map to Ghidra's 1000:0000 image base.
COPIES = [
    ("part 001 scene 4, 1107:09F0", "work/split/NEUROSIS_001_fpu.exe", 0x1E70),
    ("part 001 scene 5, 12C5:0B19", "work/split/NEUROSIS_001_fpu.exe", 0x3B79),
    ("part 002 scene 2, 108B:261B", "work/split/NEUROSIS_002_fpu.exe", 0x32CB),
]


def grab(path, offset):
    data = (ROOT / path).read_bytes()
    return data[offset:offset + ENTRIES * 4]


def main():
    copies = [(name, grab(p, o)) for name, p, o in COPIES]

    for name, raw in copies:
        if len(raw) != ENTRIES * 4:
            raise SystemExit("%s: short read (%d bytes)" % (name, len(raw)))

    base_name, base = copies[0]
    for name, raw in copies[1:]:
        if raw != base:
            raise SystemExit("%s differs from %s" % (name, base_name))
    print("  all %d copies byte-identical" % len(copies))

    value = [struct.unpack_from("<i", base, i * 4)[0] for i in range(ENTRIES)]

    wrong = [i for i in range(ENTRIES)
             if value[i] != round(math.cos(i * math.pi / 1800) * 65536)]
    if wrong:
        print("  %d entr(ies) differ from Round(cos * 65536): %s"
              % (len(wrong), wrong[:8]))
    else:
        print("  every entry is exactly Round(cos(i/10 deg) * 65536)")

    lines = [
        "; ==========================================================================",
        "; COSTAB.INC -- the 16.16 cosine table, 901 entries at a tenth of a degree.",
        ";",
        "; Extracted from the binary by tools/emit_costab.py -- do not edit.",
        "; The same table appears three times in the demo, once per unit that links",
        "; the maths object, and all three copies are byte-identical:",
        ";",
    ]
    for name, _ in copies:
        lines.append(";     %s" % name)
    lines += [
        ";",
        "; Entry i is Round(cos(i / 10 degrees) * 65536): entry 0 is 65536 = 1.0 and",
        "; entry 900 is 0. SinCos reads it forwards for the cosine and backwards from",
        "; entry 900 for the sine, which is the quarter-turn identity sin(a) =",
        "; cos(90 - a), so one quadrant of one table serves both functions.",
        "; ==========================================================================",
        "",
        "CosTab  LABEL   DWORD",
    ]

    for start in range(0, ENTRIES, 6):
        chunk = value[start:start + 6]
        lines.append("        DD      %-52s ; %d"
                     % (",".join("%d" % v for v in chunk), start))

    lines.append("")
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text("\n".join(lines), encoding="ascii", newline="\r\n")
    print("  wrote %s (%d entries)" % (OUT.relative_to(ROOT), ENTRIES))


if __name__ == "__main__":
    main()
