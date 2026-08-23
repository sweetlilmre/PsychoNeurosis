"""Assembler that appears in more than one unit should be ONE TEXT.

Borland Pascal duplicates an included procedure into every unit that includes
it, and that is how a 1990s author shared a routine between units without
exporting it: `{$I}`, not a shared unit. A shared unit would change the emitted
code at every call site -- an imported routine is reached with a far call --
so the rebuild of a duplicated routine has to duplicate it too, from one text.

Which means a rebuild can quietly hold two copies of one routine, and a
per-routine byte check cannot notice: it compares each DECLARED routine against
the binary it names, so a routine written out twice is two passing rows, and a
routine re-expressed in Pascal in one of the two units is no row at all. This
reads the source instead and reports assembler bodies that are duplicated
between units rather than shared.

    python toolkit/pascal/shared_asm.py SRCDIR
    python toolkit/pascal/shared_asm.py SRCDIR --exempt exempt.txt

It REPORTS and exits 0 unless --gate is passed, because whether a duplicate can
become one text is a fact about the routine and not something a tool can see:
three copies of one routine in the psycho corpus have three different
declarations -- `far` in a shared unit, an untyped `var` parameter, a typed
pointer -- so there is no single text to share. Cases like that go in the
exempt file, one `UNIT.Routine` per line with `#` comments, and a project that
wants the rule enforced passes --gate.

This one was WRITTEN HERE, not copied. The map's copy-and-adjust rule protects
tools that already existed; a new generic tool has no original to freeze, so
writing it in `tools/` first and copying it here would duplicate it from birth
-- which is what happened on the first attempt, complete with two rows in the
census for one tool. Project facts stay out of it: the psycho repository keeps
its exemptions in `src/asm/shared-exempt.txt` and passes them in.

Two mechanics of writing the include, both measured 23 Aug 2026 and recorded
here because the tool exists to push people towards it:

  * the include must carry the WHOLE procedure, header and all. Turbo Pascal 7
    answers `Error 118: Include files are not allowed here` to a `{$I}` inside
    an `asm` block. At declaration level it compiles.
  * a `}` closes a `{ }` comment, so an include whose own header comment quotes
    a directive needs `(* *)` delimiters, or the block ends at the first quoted
    directive and the prose after it is parsed as code.
"""
import io
import pathlib
import re
import sys

MARKER = re.compile(r"@asm\s+(\d{3})\s+([0-9a-fA-F]{4}):([0-9a-fA-F]{4})"
                    r"(?:\s*\+(\d+))?(?:\s+(\w+))?")
HEADER = re.compile(r"\s*(?:procedure|function)\s+(\w+)")
INCLUDE = re.compile(r"\{\$I\s+([A-Za-z0-9_./]+)\s*\}")
COMMENT = re.compile(r"\{[^{}]*\}", re.S)

# Fewer instructions than this and agreement means nothing: a routine that sets
# a video mode is two instructions and every program has one.
TRIVIAL = 8


def normalise(text):
    """The instructions, with the commentary and the layout taken out.

    Identifier names are KEPT, because the assembler references them: two
    bodies that differ only in what they call the source pointer are two bodies
    waiting to drift apart, and that is worth a line of output.
    """
    text = COMMENT.sub(" ", text)
    return [" ".join(l.split()).upper() for l in text.split("\n")
            if " ".join(l.split())]


def implementations(lines):
    """Routine -> its assembler, for headers that actually open a body.

    A marker may sit above an INTERFACE declaration, a long way from the body,
    with other declarations in between -- so taking the first `asm` after the
    header a marker points at can hand nine routines the same body, and did.
    Bodies are found from the headers that open one: nothing but a var or const
    block may stand between a header and its `asm`.
    """
    out = {}
    for j, line in enumerate(lines):
        h = HEADER.match(line)
        if not h:
            continue
        k = j + 1
        while k < len(lines) and not HEADER.match(lines[k]):
            if lines[k] == "asm":
                break
            k += 1
        if k >= len(lines) or lines[k] != "asm":
            continue                      # a declaration, not a body
        try:
            end = next(x for x in range(k, len(lines)) if lines[x] == "end;")
        except StopIteration:
            continue
        out.setdefault(h.group(1), normalise("\n".join(lines[k + 1:end])))
    return out


def bodies(src, pattern="*.PAS"):
    """UNIT.Routine -> (address, assembler) for assembler written out in a unit.

    A marker followed by a `{$I}` is a SHARED routine and is skipped: there is
    one text, which is the state this check exists to reach, so counting each
    including unit's copy would report the fix as the fault.

    Pascal sources are read as ASCII on purpose -- they are read by a 1990s DOS
    tool, so a byte above 127 in one is a defect, not an encoding to guess at.
    """
    out = {}
    for path in sorted(pathlib.Path(src).glob(pattern)):
        lines = io.open(path, encoding="ascii", newline="").read().split("\n")
        impl = implementations(lines)
        for i, line in enumerate(lines):
            m = MARKER.search(line)
            if not m:
                continue
            name = m.group(5)
            shared = False
            for j in range(i + 1, min(i + 6, len(lines))):
                if INCLUDE.search(lines[j]):
                    shared = True
                    break
                h = HEADER.match(lines[j])
                if h:
                    name = name or h.group(1)
                    break
            if shared or name is None or name not in impl:
                continue
            out["%s.%s" % (path.stem, name)] = (
                "%s:%s" % (m.group(2), m.group(3)), impl[name])
    return out


def duplicates(found, exempt=()):
    """Pairs in different units whose assembler is the same text."""
    exempt = set(exempt)
    names = sorted(found)
    out = []
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if a.split(".")[0] == b.split(".")[0]:
                continue                  # same unit, not this tool's business
            if a in exempt and b in exempt:
                continue
            if len(found[a][1]) < TRIVIAL:
                continue
            if found[a][1] == found[b][1]:
                out.append((a, b))
    return out


def read_exempt(path):
    names = []
    for line in io.open(path, encoding="utf-8", newline="").read().split("\n"):
        line = line.split("#")[0].strip()
        if line:
            names.append(line)
    return names


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if not args:
        print(__doc__.strip().split("\n\n")[0])
        return 2
    exempt = []
    for a in argv:
        if a.startswith("--exempt="):
            exempt = read_exempt(a.split("=", 1)[1])
    found = bodies(args[0])
    dups = duplicates(found, exempt)
    print("%d routine(s) with assembler written out in a unit" % len(found))
    for a, b in dups:
        print("  DUPLICATED: %s (%s) and %s (%s) are the same %d instructions"
              % (a, found[a][0], b, found[b][0], len(found[a][1])))
        print("              one text in an include, included by both, unless "
              "their declarations cannot be shared")
    if exempt:
        print("  %d name(s) exempt" % len(exempt))
    print("\n%d duplicate(s)" % len(dups))
    return 1 if (dups and "--gate" in argv) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
