"""Compare each compiled unit's code against the original segment it rebuilds.

    python kit/tools/pascal/units.py CONFIG.toml
    python kit/tools/pascal/units.py CONFIG.toml --only VTCFG

WHAT IS MEASURED is the PREFIX: how far our compiled code agrees with the
original's before the first difference that cannot be forgiven. A prefix rather
than a count of matching bytes, because a count is not falsifiable -- two
unrelated images share plenty of bytes -- while a prefix says "from the first
instruction to here, these are the same code".

WHAT IS FORGIVEN is a short run of zeros on our side: an unresolved reference
the linker has not filled yet. Capped at four bytes, because a far pointer is
the longest thing a fixup can zero and a longer run is a region the compiler
did not fill for some other reason -- see `align.pending`, which is where the
cap and its reason live.

WHERE THE UNIT SITS IS FOUND BY ANCHORING ON ITS FIRST BYTE, not by scoring
alignments. `align.anchor_first` carries the two strategies that failed before
that one, and why.

A UNIT THAT LINKS AN OBJECT MODULE cannot be measured by this rule alone: TASM
leaves an ADDEND where the compiler leaves a zero, so the assembler half reads
as a wall of differences. Those units are named in the config and measured by
`objcheck.py` instead, which reads the relocations out of the object file and is
stricter, not looser.

A STALE BUILD IS REFUSED, not measured. A comparison against code that is no
longer the source reports a number that looks like an answer -- see
`staged.py`.

VERDICTS, and the distinction between the first two is the point:

    IDENTICAL                  agrees the whole way with nothing outstanding
    identical, N pending       agrees the whole way, N fixups the linker owes
    PARTIAL                    all of what is written agrees; some is not
                               written. Measured over what it has, because
                               counting the unwritten part as divergent buries
                               the part that is done
    agrees to +XXXX of YYYY    the honest failure: where it stops, and how far
"""
import io
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[0]))
import project                                    # noqa: E402
import staged                                     # noqa: E402
from substrate import align, omf                  # noqa: E402

try:
    import tomllib
except ModuleNotFoundError:                       # pragma: no cover -- 3.11+
    import tomli as tomllib                       # type: ignore


def segment_bytes(blob, seg, length, first_para):
    image, _ = align.load_image(blob)
    base = (seg - first_para) * 16
    return image[base:base + length]


def relocation_mask(obj, ours):
    """Byte positions in OUR code that an assembled module left as relocations.

    Turbo Pascal appends object-module code AFTER all of the unit's own code, so
    the module sits at the end -- but it is FOUND by its opening bytes rather
    than assumed, because those are code and not a fixup. Returns an empty set
    where the unit links no module, which leaves every other unit measured
    exactly as it was.
    """
    if not pathlib.Path(obj).exists():
        return set()
    code, fixups = omf.code_and_fixups(obj)
    at = ours.find(code[:24])
    return {at + f for f in fixups} if at >= 0 else set()


def rule_for(mask):
    """`align.pending`, widened by a relocation mask.

    A masked byte is forgiven WHATEVER its value, because the assembler left an
    addend there rather than a zero -- and there is no way to tell that from the
    bytes, which is why the mask is read from the object file instead of guessed.
    """
    if not mask:
        return align.pending

    def rule(run, orig=None, mine=None, at=0):
        n = 0
        while n < run and (at + n in mask
                           or (mine is not None and mine[at + n] == 0
                               and n < align.MAX_FIXUP)):
            n += 1
        return n
    return rule


def measure(orig, image, mask=frozenset()):
    """(offset, prefix, pending bytes, short) for one unit, or None.

    A PARTIAL UNIT COMPILES MUCH SHORTER THAN ITS SEGMENT. Comparing our 1.6KB
    against a 4,303-byte segment says nothing about the 2.7KB not written yet,
    and counting those as divergent would bury the part that IS done. So the
    comparison is clipped to what exists and the shortfall reported separately.

    `pending` is a count of BYTES, not of forgiven runs: it is what the linker
    still owes, and a run is not one debt.
    """
    # LOCATE ON THE PLAIN RULE, always. A mask forgives bytes whatever their
    # value, so searching with it makes late positions score better and slides
    # the match down the image -- one unit located near the end of itself and
    # reported a plausible number about the wrong place.
    at, _ = align.anchor_first(orig, image, align.pending)
    if at < 0:
        return None
    full = len(orig)
    orig = orig[:min(full, len(image) - at)]
    mine = image[at:at + len(orig)]

    pre, _, _ = align.walk(orig, mine, align.pending, None, False)
    if mask:
        # Re-measure with the module's relocations forgiven, and keep it only
        # if it reaches further. It cannot reach less, but saying so out loud
        # is cheaper than assuming it.
        # The mask holds offsets in the WHOLE image; the walk sees a slice
        # starting at `at`, so it has to be shifted or every masked byte lands
        # outside the run being judged and nothing is forgiven.
        shifted = {m - at for m in mask}
        masked, _, _ = align.walk(orig, mine, rule_for(shifted), None, False)
        if masked > pre:
            pre = masked

    # PENDING IS WHAT THE LINKER STILL OWES, counted in bytes over everything
    # compared: a zero on our side, or a byte the object module recorded as a
    # relocation.
    pending = sum(1 for k in range(len(orig))
                  if mine[k] != orig[k]
                  and (mine[k] == 0 or (at + k) in mask))
    return at, pre, pending, full - len(orig)


def main(argv):
    args = project.positionals(argv[1:], ("--only", "--build", "--original",
                                          "--sources"))

    def opt(name, default=None):
        flag = "--" + name
        return argv[argv.index(flag) + 1] if flag in argv else default

    if not args:
        sys.stdout.write("usage: units.py CONFIG.toml [--only NAME] "
                         "[--build DIR] [--original FILE]\n")
        return 2
    with io.open(args[0], "rb") as fh:
        cfg = tomllib.load(fh)
    try:
        build = pathlib.Path(opt("build") or project.path("layout.build"))
        original = opt("original") or project.path("target.image")
        first = project.get("target.first_para", quiet=True)
    except project.Missing as exc:
        return project.complain(exc)

    blob = pathlib.Path(original).read_bytes()
    sources = opt("sources") or cfg.get("sources")
    only = opt("only")
    rows = []
    exact = ok = failed = missing = 0

    for name, spec in sorted(cfg.get("unit", {}).items()):
        if only and only.upper() not in name.upper():
            continue
        seg, length = spec["segment"], spec["length"]
        unit = build / (spec.get("file") or (name + ".TPU"))
        if not unit.exists():
            rows.append((name, seg, length, "no %s -- build it first"
                         % unit.name))
            missing += 1
            continue
        if sources:
            state = staged.state(pathlib.Path(sources) / (name + ".PAS"),
                                 build / (name + ".PAS"),
                                 cfg.get("rewrites", ()))
            if state == "stale":
                rows.append((name, seg, length,
                             "STALE -- source changed since the build; rebuild"))
                missing += 1
                continue
        orig = segment_bytes(blob, seg, length, first)
        image = unit.read_bytes()
        # A unit linking an object module needs the module's own relocations
        # before any figure here means anything. objcheck.py judges those
        # fields strictly; this row says how far the unit agrees at all.
        mask = (relocation_mask(build / spec["object"], image)
                if spec.get("object") else frozenset())
        got = measure(orig, image, mask)
        if got is None:
            rows.append((name, seg, length,
                         "NOT LOCATED -- first instruction differs"))
            failed += 1
            continue
        at, pre, pending, short = got
        have = length - short
        if short and pre >= have:
            rows.append((name, seg, length,
                         "PARTIAL: %04x of %04x transcribed, all of it %s"
                         % (have, length,
                            "identical" if pending == 0
                            else "identical bar %d fixup(s)" % pending)))
            ok += 1
        elif pre >= have:
            if pending == 0:
                rows.append((name, seg, length, "IDENTICAL"))
                exact += 1
            else:
                rows.append((name, seg, length,
                             "identical, %d pending fixup%s"
                             % (pending, "" if pending == 1 else "s")))
                ok += 1
        else:
            rows.append((name, seg, length,
                         "agrees to +%04x of %04x  (%d%%)"
                         % (pre, have, 100 * pre // max(1, have))))
            failed += 1

    w = max([len(r[0]) for r in rows] + [8])
    sys.stdout.write("%-*s  %-6s %6s  %s\n" % (w, "unit", "seg", "bytes",
                                               "result"))
    sys.stdout.write("-" * (w + 40) + "\n")
    for name, seg, length, note in rows:
        sys.stdout.write("%-*s  %04x   %6d  %s\n" % (w, name, seg, length,
                                                     note))
    sys.stdout.write("-" * (w + 40) + "\n")
    sys.stdout.write("%d byte-identical, %d identical but for fixups, "
                     "%d mismatched, %d missing\n"
                     % (exact, ok, failed, missing))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
