"""Survey Borland x87-emulator trap sites (INT 34h..3Eh) in the demo parts.

Borland compiles `$E+` floating point by emitting the real x87 encoding and
letting the linker overwrite the two-byte `WAIT ESC` prefix with a two-byte
`INT n`. That keeps instruction lengths identical, which is what lets the RTL
patch the traps back to real FP opcodes at startup when a 387 is present.

If that theory holds, the byte following each `CD 3x` must be a valid modrm
for the corresponding ESC opcode. This script tabulates the evidence.
"""
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mzinfo import parse

LO, HI = 0x34, 0x3E


def modrm_len(op, modrm):
    """Extra bytes consumed by a 16-bit modrm after the opcode."""
    mod, rm = modrm >> 6, modrm & 7
    if mod == 3:
        return 0
    if mod == 0:
        return 2 if rm == 6 else 0
    return 1 if mod == 1 else 2


def main(paths):
    for p in paths:
        h = parse(Path(p))
        raw, base = h["raw"], h["hdrsize"]
        code = raw[base:h["imagesize"]]

        vec = Counter()
        follow = {v: Counter() for v in range(LO, HI + 1)}
        mod3 = Counter()
        sites = []

        i = 0
        while i < len(code) - 2:
            if code[i] == 0xCD and LO <= code[i + 1] <= HI:
                v = code[i + 1]
                nxt = code[i + 2]
                vec[v] += 1
                follow[v][nxt] += 1
                mod3[(v, nxt >> 6)] += 1
                if len(sites) < 3:
                    sites.append((base + i, code[i:i + 8]))
                i += 2
                continue
            i += 1

        print(f"\n=== {h['file']} ===  {sum(vec.values())} trap sites")
        for v in sorted(vec):
            esc = 0xD8 + (v - LO)
            top = follow[v].most_common(3)
            tops = " ".join(f"{b:02x}x{n}" for b, n in top)
            print(f"  INT {v:02X} -> ESC {esc:02X}?  {vec[v]:>4} sites   "
                  f"common next: {tops}")
        print("  sample sites:")
        for off, b in sites:
            print(f"    file+{off:#07x}  {b.hex(' ')}")


if __name__ == "__main__":
    main(sys.argv[1:])
