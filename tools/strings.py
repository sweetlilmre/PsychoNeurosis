"""Dump printable strings, optionally restricted to the EXE load image."""
import argparse
import re
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).parent))
from mzinfo import parse

# Borland Pascal stores ShortStrings as a length byte followed by the text,
# so a length byte matching the run length is a strong signal of real data.
RUN = re.compile(rb"[\x20-\x7e]{%d,}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("-n", "--minlen", type=int, default=6)
    ap.add_argument("--image-only", action="store_true", help="skip appended payload")
    ap.add_argument("--pascal", action="store_true", help="only length-prefixed strings")
    args = ap.parse_args()

    pat = re.compile(rb"[\x20-\x7e]{%d,}" % args.minlen)
    for f in args.files:
        h = parse(Path(f))
        raw = h["raw"]
        end = h["imagesize"] if args.image_only else len(raw)
        print(f"\n=== {h['file']} (0..{end}) ===")
        for m in pat.finditer(raw, 0, end):
            s = m.group()
            if args.pascal and (m.start() == 0 or raw[m.start() - 1] != len(s)):
                continue
            print(f"  {m.start():08X}  {s.decode('ascii')}")


if __name__ == "__main__":
    main()
