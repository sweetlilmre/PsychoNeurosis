"""Compare every linked code segment against the original's, and read the
DGROUP VARIABLE layout out of the differences.

WHY A LINKED IMAGE SAYS SOMETHING A `.TPU` CANNOT. Inside a `.TPU` every DGROUP
reference is an unresolved fixup -- zeros -- which a `.TPU` comparison
deliberately excuses. That is what makes the whole VARIABLE half of DGROUP
invisible: the initialised half can be read straight out of the image, but a
plain `var` is reserved space the linker never writes, so nothing in the file
records where one went.

**The CODE records it.** In the linked image every one of those fixups is
resolved to a real address, so a variable in the wrong place shows up as a
wrong operand in every instruction that touches it. This is that measurement:
the same code, resolved addresses, both sides.

It only becomes possible once the segment ORDER and every segment SIZE match,
because until then the segments do not line up and every address is off anyway.

    python kit/tools/pascal/linkcmp.py CONFIG.toml
    python kit/tools/pascal/linkcmp.py CONFIG.toml --only VTCFG -v

READING THE OUTPUT. A difference is one of three things:

  * a DGROUP VARIABLE address -- above the boundary on BOTH sides, and within a
    plausible distance. That is the thing being measured. The pair is recorded,
    and a group of them sharing one delta is one unit's block in the wrong
    place; the delta counts tell you how many instructions say so.
  * a DGROUP CONSTANT address -- below the boundary. The initialised half is
    measured separately and exactly, so a constant-region difference here is a
    REGRESSION and is called one.
  * anything else: a real code difference, and the only one of the three that
    means the transcription is wrong.

The rule that decides which is `align.window`'s shape -- an address inside a
stated range -- and the range, the boundary and what counts as a plausible
misplacement are the TARGET's facts, in the config. So is the segment list: the
map of which unit sits where is read from the build's own `.MAP` on our side and
declared for the original, because the original has no map to read.
"""
import io
import pathlib
import re
import struct
import sys
from collections import Counter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[0]))
import project                                    # noqa: E402
from substrate import align                       # noqa: E402

try:
    import tomllib
except ModuleNotFoundError:                       # pragma: no cover -- 3.11+
    import tomli as tomllib                       # type: ignore

# A .MAP line: start, stop, length, name, CODE.
MAP_LINE = re.compile(r"\s*([0-9A-F]+)H\s+[0-9A-F]+H\s+([0-9A-F]+)H\s+(\S+)"
                      r"\s+CODE\s*$")


def our_segments(map_path, header):
    """name -> (file offset, length) for every CODE segment the linker placed."""
    out = {}
    text = io.open(map_path, encoding="ascii", errors="replace").read()
    for line in text.splitlines():
        m = MAP_LINE.match(line)
        if m:
            out[m.group(3)] = (header + int(m.group(1), 16),
                               int(m.group(2), 16))
    return out


def operand(a_bytes, b_bytes, i, lo, hi, maxdelta):
    """The 16-bit operand containing byte `i`, when BOTH sides hold something
    that looks like a DGROUP variable address and they are close enough to be
    the same variable in two places.

    Both alignments are tried, because the differing byte may be the low or the
    high half of the word.
    """
    for s in (i - 1, i):
        if s < 0 or s + 2 > min(len(a_bytes), len(b_bytes)):
            continue
        a = struct.unpack_from("<H", a_bytes, s)[0]
        b = struct.unpack_from("<H", b_bytes, s)[0]
        if lo <= a < hi and lo <= b < hi and abs(a - b) <= maxdelta:
            return s, a, b
    return None


def constant_pair(a_bytes, b_bytes, i, lo):
    """Two differing words both BELOW the boundary -- the initialised half,
    which is measured exactly elsewhere, so this is a regression."""
    for s in (i - 1, i):
        if s < 0 or s + 2 > min(len(a_bytes), len(b_bytes)):
            continue
        a = struct.unpack_from("<H", a_bytes, s)[0]
        b = struct.unpack_from("<H", b_bytes, s)[0]
        if 0 < a < lo and 0 < b < lo and a != b:
            return a, b
    return None


def main(argv):
    args = project.positionals(argv[1:], ("--only", "--build", "--original"))
    verbose = "-v" in argv or "--verbose" in argv

    def opt(name, default=None):
        flag = "--" + name
        return argv[argv.index(flag) + 1] if flag in argv else default

    if not args:
        sys.stdout.write("usage: linkcmp.py CONFIG.toml [--only NAME] [-v]\n")
        return 2
    with io.open(args[0], "rb") as fh:
        cfg = tomllib.load(fh)
    try:
        build = pathlib.Path(opt("build") or project.path("layout.build"))
        original = opt("original") or project.path("target.image")
        first = project.get("target.first_para", quiet=True)
    except project.Missing as exc:
        return project.complain(exc)

    lo = cfg["varbase"]
    hi = cfg["datalen"]
    maxdelta = cfg.get("maxdelta", 8192)
    skip = set(cfg.get("skip", ()))
    layout = [(int(s["at"], 16) if isinstance(s["at"], str) else s["at"],
               s.get("unit")) for s in cfg["segment"]]

    orig_blob = pathlib.Path(original).read_bytes()
    orig_hdr = struct.unpack_from("<H", orig_blob, 8)[0] * 16
    ours_path = build / cfg["image"]
    map_path = build / cfg["map"]
    if not ours_path.exists() or not map_path.exists():
        sys.stdout.write("  no %s and %s -- link it first\n"
                         % (ours_path.name, map_path.name))
        return 1
    ours_blob = ours_path.read_bytes()
    ours_hdr = struct.unpack_from("<H", ours_blob, 8)[0] * 16
    placed = our_segments(map_path, ours_hdr)

    only = opt("only")
    sys.stdout.write("%-14s %6s  %s\n" % ("unit", "diffs", "verdict"))
    sys.stdout.write("-" * 76 + "\n")
    deltas = Counter()
    clean = 0
    for (seg, name), (nxt, _) in zip(layout, layout[1:]):
        if name is None or name in skip or name not in placed:
            continue
        if only and only.upper() not in name.upper():
            continue
        n = (nxt - seg) * 16
        at = orig_hdr + (seg - first) * 16
        want = orig_blob[at:at + n]
        start, length = placed[name]
        got = ours_blob[start:start + length]
        m = min(len(want), len(got))
        diffs = [i for i in range(m) if want[i] != got[i]]

        pairs, code, const = [], 0, 0
        seen = set()
        for i in diffs:
            if i in seen:
                continue
            found = operand(want, got, i, lo, hi, maxdelta)
            if found:
                s, a, b = found
                seen.update((s, s + 1))
                pairs.append((a, b))
            elif constant_pair(want, got, i, lo):
                const += 1
            else:
                code += 1
        for a, b in pairs:
            deltas[b - a] += 1

        if not diffs:
            clean += 1
            sys.stdout.write("%-14s %6d  exact\n" % (name, 0))
            continue
        per_unit = Counter(b - a for a, b in pairs)
        dom = ("  delta %+d x%d" % per_unit.most_common(1)[0]) if per_unit else ""
        bits = ["%d var-address operand(s)%s" % (len(pairs), dom)]
        if const:
            bits.append("%d CONSTANT-region (REGRESSION)" % const)
        if code:
            bits.append("** %d code **" % code)
        sys.stdout.write("%-14s %6d  %s\n" % (name, len(diffs), ", ".join(bits)))
        if verbose:
            for d, k in per_unit.most_common():
                addrs = sorted(a for a, b in pairs if b - a == d)
                sys.stdout.write("        %+7d  x%-3d  orig %s\n"
                                 % (d, k, " ".join("$%04x" % a
                                                   for a in addrs[:12])
                                    + (" ..." if len(addrs) > 12 else "")))

    sys.stdout.write("-" * 76 + "\n")
    sys.stdout.write("%d unit(s) byte-identical in the linked image\n" % clean)
    if deltas:
        sys.stdout.write("\nTHE DELTAS, most operands first -- each is a run of "
                         "the VARIABLE region\nin the wrong place, and the "
                         "count is how many instructions say so:\n")
        for d, c in deltas.most_common(20):
            sys.stdout.write("   %+7d   %3d operand(s)\n" % (d, c))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
