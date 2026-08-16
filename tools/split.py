"""Split each demo part into a clean MZ image plus its appended payload.

Ghidra's MZ loader only reads the image described by the header, but stripping
the payload keeps the imported file honest and gives us the MODs for free.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mzinfo import parse

MOD_TAG_OFFSET = 1080


def payload_ext(blob):
    if blob[MOD_TAG_OFFSET:MOD_TAG_OFFSET + 4] in (b"M.K.", b"M!K!", b"FLT4", b"FLT8"):
        return ".mod"
    if blob[:2] == b"\xfb\x52":
        return ".tdb"  # Borland symbolic debug info
    return ".bin"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("-o", "--outdir", required=True)
    args = ap.parse_args()

    out = Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)

    for f in args.files:
        h = parse(Path(f))
        stem = Path(f).stem + "_" + Path(f).suffix.lstrip(".")
        raw = h["raw"]

        exe = out / f"{stem}.exe"
        exe.write_bytes(raw[:h["imagesize"]])
        line = f"{h['file']:<14} -> {exe.name} ({h['imagesize']} bytes)"

        if h["overlay_bytes"] > 0:
            blob = raw[h["imagesize"]:]
            pay = out / f"{stem}{payload_ext(blob)}"
            pay.write_bytes(blob)
            line += f" + {pay.name} ({len(blob)} bytes)"
        print(line)


if __name__ == "__main__":
    main()
