"""Locate known Borland RTL routines in each part by byte pattern, not by offset.

An earlier assumption -- that smart-linking preserves offsets across parts --
holds only for a stable core (Halt, GetMem, FreeMem). Everything above that
shifts, so naming by offset mislabels routines in most parts.

Instead: take each routine's body from the reference part and search for it in
the target's RTL segment. Relocated words are masked in both, since they hold
load-time segment values that legitimately differ.

Emits `offset=name,...` per part, ready to pass to ApplyRtlNames.java.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mzinfo import parse
from rtlmatch import masked_image, seg_file_offset

BASES = {
    "000": 0x1213, "001": 0x1543, "002": 0x14b1, "003": 0x137b, "004": 0x1288,
    "005": 0x12d9, "006": 0x128a, "007": 0x110c, "009": 0x1069,
}
REF = "003"

# Reference offsets in part 003, each confirmed by decompiling the routine.
KNOWN = {
    0x0000: "RTL_SystemInit",
    0x0116: "RTL_Halt",
    0x028a: "RTL_GetMem",
    0x029f: "RTL_FreeMem",
    0x0cd3: "RTL_Random",
    0x0e7c: "RTL_FillChar",
    0x320d: "RTL_RoundToInt",
    0x3420: "RTL_FileAssign",
    0x345b: "RTL_FileReset",
    0x34dc: "RTL_FileClose",
    0x3501: "RTL_FileCheckOpen",
    0x3546: "RTL_FileBlockRead",
    0x35ae: "RTL_FileSeek",
}

SIG = 24  # bytes of body used as the search pattern


def load(part):
    h = parse(Path(f"work/split/NEUROSIS_{part}.exe"))
    return masked_image(h), seg_file_offset(h, BASES[part]), h["imagesize"]


def main():
    rmask, roff, _ = load(REF)
    sigs = {name: rmask[roff + off:roff + off + SIG] for off, name in KNOWN.items()}

    out = {}
    for part in BASES:
        mask, base, size = load(part)
        rtl = mask[base:size]
        found = {}
        for name, sig in sigs.items():
            if len(set(sig)) <= 2:          # too bland to identify anything
                continue
            hits = []
            i = rtl.find(sig)
            while i >= 0 and len(hits) < 3:
                hits.append(i)
                i = rtl.find(sig, i + 1)
            if len(hits) == 1:
                found[hits[0]] = name
        # Two anchors the pattern search cannot confirm on its own:
        #  - offset 0 is the System init by construction (the RTL block starts there)
        #  - Halt sits at 0x116 in every part; verified separately on a 10-byte
        #    prefix, but its 24-byte body diverges on near-call displacements.
        found.setdefault(0x0000, "RTL_SystemInit")
        if base + 0x116 + 10 <= size:
            ref_halt = rmask[roff + 0x116:roff + 0x116 + 10]
            if mask[base + 0x116:base + 0x116 + 10] == ref_halt:
                found.setdefault(0x0116, "RTL_Halt")

        out[part] = found
        pairs = ",".join(f"{o:x}={n}" for o, n in sorted(found.items()))
        print(f"{part}: {len(found):>2} routines located")
        print(f"    {pairs}")

    Path("work/sites/rtlnames.json").write_text(
        json.dumps({k: {f"{o:x}": n for o, n in v.items()} for k, v in out.items()},
                   indent=1), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
