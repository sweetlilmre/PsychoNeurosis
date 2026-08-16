"""Extract Borland Pascal symbolic debug info (magic 0x52FB) name pools.

The name pool is a run of NUL-terminated uppercase identifiers holding unit
names, source filenames, procedures, types and variables -- gold for RE.
"""
import re
import sys
from collections import OrderedDict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mzinfo import parse

MAGIC = b"\xfb\x52"
IDENT = re.compile(rb"[A-Z_][A-Z0-9_]{2,62}(?:\.(?:PAS|TPU|INC|OBJ|ASM))?")
SOURCE = re.compile(r"\.(PAS|TPU|INC|OBJ|ASM)$")


def blocks(raw):
    """Yield (offset, length) for each plausible debug-info block."""
    for m in re.finditer(re.escape(MAGIC), raw):
        off = m.start()
        # A real block is followed by a version byte and sane section counts.
        if off + 32 < len(raw) and raw[off + 2] < 0x20:
            yield off


def names(raw, start):
    """Pull NUL-terminated identifiers out of the pool following `start`."""
    found = OrderedDict()
    for m in IDENT.finditer(raw, start):
        tok = m.group().decode("ascii")
        # Require NUL termination so we skip code bytes that happen to be ASCII.
        if m.end() < len(raw) and raw[m.end()] == 0:
            found.setdefault(tok, m.start())
    return found


def main(paths):
    for p in paths:
        h = parse(Path(p))
        raw = h["raw"]
        offs = list(blocks(raw))
        print(f"\n=== {h['file']} ===  debug blocks at {[hex(o) for o in offs] or 'none'}")
        if not offs:
            continue
        pool = names(raw, offs[0])
        srcs = [n for n in pool if SOURCE.search(n)]
        others = [n for n in pool if not SOURCE.search(n)]
        print(f"  {len(pool)} identifiers, {len(srcs)} source/unit files")
        if srcs:
            print("  sources: " + ", ".join(sorted(srcs)))
        print("  symbols: " + ", ".join(others))


if __name__ == "__main__":
    main(sys.argv[1:])
