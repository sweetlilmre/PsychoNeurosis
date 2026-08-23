"""Rewrite Borland x87-emulator traps back into real x87 instructions.

Encoding (derived empirically from NEUROSIS.003, see ANALYSIS.md):

    CD n        n in 34..3B   ->  9B  D8+(n-0x34)        ESC, reg/BP operand
    CD 3C b                   ->  9B  2E  b+0x40         CS-relative ESC
    CD 3D                     ->  90  9B                 standalone FWAIT
    CD 3E                     ->  (left alone)           RTL emulator entry

INT 3Ch is the vector for an FP instruction whose memory operand lives in the
CODE segment -- Borland parks floating-point literals next to the procedures
that use them. The original is `9B 2E <esc> <modrm>` (WAIT, CS:, ESC) and the
emulated form `CD 3C <esc-0x40> <modrm>` is the same length, so the CS override
must be restored or the operand silently resolves against DS instead. That was
wrong in the first version of this tool and produced garbage constants.

Every rule is length-preserving, so all addresses, relocations and function
boundaries stay exactly where they were.

Sites must be supplied as Ghidra-confirmed instruction addresses (seg:off). A
flat byte scan produces false positives, so we never patch on byte match alone.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
# mzinfo is the kit's now (#50). These scripts are the record's, or are
# waiting their turn to move, and they keep working meanwhile -- which is
# the standing rule: the originals go on working until their successor has
# landed AND every caller has been repointed.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
                      "kit" / "tools"))
from substrate.mzinfo import parse

LOAD_SEG = 0x1000  # Ghidra's MZ loader places the image here


def file_offset(h, seg, off):
    return h["hdrsize"] + (seg * 16 + off) - LOAD_SEG * 16


def patch(raw, pos):
    """Return (newbytes, description) for the trap at pos, or None."""
    if raw[pos] != 0xCD:
        return None
    n = raw[pos + 1]
    if 0x34 <= n <= 0x3B:
        return bytes([0x9B, 0xD8 + (n - 0x34)]), f"ESC {0xD8 + n - 0x34:02X}"
    if n == 0x3C:
        b = raw[pos + 2]
        if not (0x98 <= b <= 0x9F):
            return None
        # WAIT, CS: override, ESC -- the operand is a code-segment literal.
        return bytes([0x9B, 0x2E, b + 0x40]), f"ESC {b + 0x40:02X} CS-relative"
    if n == 0x3D:
        return bytes([0x90, 0x9B]), "FWAIT"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("exe")
    ap.add_argument("-s", "--sites", required=True,
                    help="JSON list of 'seg:off' strings from Ghidra")
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    h = parse(Path(args.exe))
    raw = bytearray(h["raw"])
    sites = json.loads(Path(args.sites).read_text(encoding="utf-8"))

    applied, skipped = 0, []
    for s in sites:
        seg, off = (int(x, 16) for x in s.split(":"))
        pos = file_offset(h, seg, off)
        res = patch(raw, pos)
        if res is None:
            skipped.append(s)
            continue
        new, what = res
        raw[pos:pos + len(new)] = new
        applied += 1

    Path(args.out).write_bytes(bytes(raw))
    print(f"{Path(args.exe).name}: patched {applied}/{len(sites)} sites -> {args.out}")
    if skipped:
        print(f"  skipped (not a recognised trap): {', '.join(skipped)}")


if __name__ == "__main__":
    main()
