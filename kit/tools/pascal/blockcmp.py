"""Verify a segment BLOCK BY BLOCK, which is the only honest measure of a
half-written unit.

WHY THIS EXISTS, in the words of the five scripts it replaces: a prefix
comparison stops at the first byte that disagrees, and inside a unit that is
only partly transcribed that byte is always the same thing -- the first
placeholder. The routines after it are correct but sit at the wrong offset, so
the prefix freezes at the placeholder and says nothing about the hundreds of
bytes below it that ARE right.

So each block is compared AT ITS OWN POSITION, searching for the shift that
minimises real differences. Never a single global shift: the record says that
mistake once reported 73 mismatches where there were none.

WHAT COUNTS AS A DIFFERENCE IS THE CONFIG'S CHOICE, because it depends on what
is being compared:

  * `pending` -- our side is zero. Turbo Pascal leaves an unresolved reference
    as zeros plus a fixup record, so a zero is the linker's job. Note what that
    covers: an INTRA-UNIT NEAR CALL is a pending fixup too, so a call inside the
    unit agreeing is not evidence that its target sits in the right place.
  * `linked` -- for a LINKED image, where nothing is left as zeros because the
    linker already ran. A segment word off by a fixed number of paragraphs, or a
    DGROUP variable offset, and nothing else. See `align.linked`.

    python kit/tools/pascal/blockcmp.py CONFIG.toml
    python kit/tools/pascal/blockcmp.py CONFIG.toml --only PlayStart
    python kit/tools/pascal/blockcmp.py CONFIG.toml --build DIR --original FILE

FIVE SCRIPTS, ONE TOOL. `blocks.py` and four `blockXXXX.py` files were the same
program five times over, parameterised only by the segment, its length, the
search window and a block list -- the classification called it the clearest
single split in either repository. Those four values are now a config file per
segment, generated from the five scripts by parsing them rather than by hand
(psycho issue #34). What is left here is the measurement, which was identical
in all five.

THE CONFIG, one file per segment:

    segment = 0x14B9        where it is in the original image
    length  = 2224          how long, so coverage can be reported
    unit    = 'SONGUNIT.TPU'  which compiled unit should contain it
    window  = 2400          how far to search for a block's real position

    [[block]]
    name        = 'GetInstrument'
    from        = 0x0187
    to          = 0x0202
    transcribed = true      false marks a placeholder, expected not to agree

`window` is optional and defaults to WINDOW below. It has to cover the
ACCUMULATED shortfall of every placeholder above a block: 600 was once too
small and reported a wrong shift with a plausible-looking difference count. A
too-narrow window does not fail loudly.
"""
import io
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[0]))
import project                                    # noqa: E402
from substrate import align                       # noqa: E402

try:
    import tomllib
except ModuleNotFoundError:                       # pragma: no cover -- 3.11+
    import tomli as tomllib                       # type: ignore

# Wide enough for a mostly-placeholder unit. The five scripts all used 2400
# after 600 proved too small.
WINDOW = 2400


def read_config(path):
    with io.open(path, "rb") as fh:
        cfg = tomllib.load(fh)
    for key in ("segment", "length", "unit"):
        if key not in cfg:
            raise SystemExit("  %s does not say `%s`" % (path, key))
    cfg.setdefault("window", WINDOW)
    cfg.setdefault("block", [])
    cfg.setdefault("rule", "pending")
    return cfg


def rule_from(cfg):
    """The allowed-difference rule this segment is measured by, by NAME.

    A `.TPU`'s unresolved references are zeros, so `pending` is the default and
    is what four of the five segments here use. A LINKED image's are not zeros
    at all -- see `align.linked` -- so it says so, and says what its two
    parameters are, because both are facts about the target rather than about
    the comparison.
    """
    name = cfg["rule"]
    if name == "pending":
        return align.zeros
    if name == "linked":
        if "varbase" not in cfg:
            raise SystemExit("  the `linked` rule needs `varbase`: the "
                             "initialised/uninitialised DGROUP boundary")
        return align.linked(cfg["varbase"], cfg.get("segment_delta"))
    raise SystemExit("  no rule called %r -- `pending` or `linked`" % name)


def segment_bytes(original, seg, length, first_para):
    """The segment's bytes out of the original image."""
    blob = pathlib.Path(original).read_bytes()
    image, _ = align.load_image(blob)
    base = (seg - first_para) * 16
    return image[base:base + length]


def main(argv):
    args = project.positionals(argv[1:], ("--only", "--build",
                                          "--original", "--limit"))
    if not args:
        sys.stdout.write("usage: blockcmp.py CONFIG.toml [--only NAME] "
                         "[--build DIR] [--original FILE]\n")
        return 2

    def opt(name, default=None):
        flag = "--" + name
        return argv[argv.index(flag) + 1] if flag in argv else default

    cfg = read_config(args[0])
    try:
        build = pathlib.Path(opt("build") or project.path("layout.build"))
        original = opt("original") or project.path("target.image")
        first_para = project.get("target.first_para", quiet=True)
    except project.Missing as exc:
        return project.complain(exc)

    unit = build / cfg["unit"]
    if not unit.exists():
        sys.stdout.write("  no %s -- build it first\n" % unit)
        return 1
    image = unit.read_bytes()
    if cfg.get("strip_header"):
        # A linked .EXE carries an MZ header and the segment sits at the start
        # of the LOAD IMAGE past it. A .TPU has no header at all.
        image, _ = align.load_image(image)
    orig = segment_bytes(original, cfg["segment"], cfg["length"], first_para)

    if "at" in cfg:
        # The position is KNOWN, so it is not searched for. Searching for
        # something known to be at offset 0 is not merely wasted work: it is a
        # chance to find a better-scoring coincidence somewhere else.
        at = cfg["at"]
        sys.stdout.write("segment %04x, at %s offset 0x%04x as declared\n\n"
                         % (cfg["segment"], cfg["unit"], at))
    else:
        at, _ = align.locate(orig, image)
        if at < 0:
            sys.stdout.write("  NOT LOCATED -- the unit's first instruction "
                             "differs, so nothing below can be positioned\n")
            return 1
        sys.stdout.write("segment %04x, unit code located at %s offset "
                         "0x%04x\n\n" % (cfg["segment"], cfg["unit"], at))
    sys.stdout.write("block                 addr         len  shift  real  "
                     "pending\n")
    sys.stdout.write("-" * 62 + "\n")

    only = opt("only")
    rule = rule_from(cfg)
    # How much of the image is OURS. Measured -- our segment's length, out of
    # the build's own map -- so it is passed in and never stored in a config.
    limit = int(opt("limit"), 0) if opt("limit") else None
    done = clean = covered = bad = short = 0
    for b in cfg["block"]:
        name, lo, hi = b["name"], b["from"], b["to"]
        transcribed = b.get("transcribed", True)
        if only and only.lower() not in name.lower():
            continue
        want = orig[lo:hi]
        if limit is not None and at + hi > at + limit:
            # The block runs past the end of OUR segment, so part of it has
            # nothing to be compared against. Reported, not clipped and not
            # searched: clipping and searching produces a plausible shift for
            # a block that simply is not all there.
            sys.stdout.write("%-20s %04x..%04x %5d      -     -      -  "
                             "%d byte(s) past the end of our %d\n"
                             % (name, lo, hi, hi - lo, hi - limit, limit))
            short += 1
            continue
        found = align.best_shift(want, image, at + lo, cfg["window"], rule)
        if found is None:
            # The window found nothing to compare: the block's nominal offset
            # is past the end of the image. That is a property of measuring an
            # unfinished unit, not an error, and it is said rather than
            # crashed on.
            sys.stdout.write("%-20s %04x..%04x %5d      -     -      -  "
                             "past the end of %s\n"
                             % (name, lo, hi, hi - lo, cfg["unit"]))
            continue
        real, pending, _, pos = found
        shift = pos - (at + lo)
        if not transcribed:
            note = "placeholder"
        elif real == 0:
            note = "OK"
            clean += 1
        else:
            note = "** %d real" % real
        if transcribed:
            done += 1
            covered += hi - lo
            bad += real
        sys.stdout.write("%-20s %04x..%04x %5d  %+5d  %4d  %5d  %s\n"
                         % (name, lo, hi, hi - lo, shift, real, pending, note))

    sys.stdout.write("-" * 62 + "\n")
    sys.stdout.write("%d of %d transcribed block(s) agree\n" % (clean, done))
    if short:
        sys.stdout.write("%d block(s) run past the end of our segment and were "
                         "NOT compared\n" % short)
    sys.stdout.write("%d of %d byte(s) of segment %04x transcribed (%d%%)\n"
                     % (covered, cfg["length"], cfg["segment"],
                        100 * covered // max(1, cfg["length"])))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
