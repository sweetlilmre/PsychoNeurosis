"""Hand-written assembler that appears in more than one unit must be ONE TEXT.

WHY. Part 001 scene 4's clipped sprite blit (`1107:0199`) and part 006 scene
2's (`100f:0000`) are the same routine -- instruction for instruction, part
001's addresses being part 006's plus $199. Part 006's had been transcribed
verbatim and locked for weeks while part 001 ran a Pascal rewrite of it, and
nothing in the toolkit could say so: `asmverify` checks each MARKED routine
against the binary it names, so a routine missing from one unit is invisible to
it. `tools/shapediff.py` found it on 23 Aug 2026 as a 799-byte unaligned span.

THE FIX IS AN INCLUDE, NOT A SECOND COPY. The original shared source text and
let each unit compile its own copy -- which is what the binaries show: in part
001 the blit sits between `Banner_Load` and `DrawBlobs`, inside the scene 4
unit's own code, not at the head of a segment of its own. A shared UNIT would
be wrong on the bytes (one copy in one segment turns the other callers' near
calls into far ones); a shared {$I} include is right, and is what
`src/asm/BLITCLIP.INC` is.

Two things about writing one, both learned the hard way on 23 Aug 2026:

  * the include must carry the WHOLE procedure, header and all. TP7 answers
    `Error 118: Include files are not allowed here` to a {$I} inside an `asm`
    block. At declaration level it is fine. Its own leading comment has to be
    an (* *) block if it quotes a directive, because a `}` ends a { } comment.

  * the @asm marker stays in each including unit, because the address is that
    part's, and it must NAME the routine -- `{ @asm 001 1107:0199 +170 Blit }`
    -- because the header is no longer on the line below. asmverify already
    prefers the marker's own name field, so nothing there needed changing.

WHAT THIS TOOL CHECKS. That no two marked routines in different units have the
same assembler written out. One that turns up is either a routine to move into
an include, or one of the EXEMPT groups below -- cases where the instructions
coincide but the declaration cannot be shared, which is a fact about the
routine and is recorded rather than worked around.

    python tools/asmshare.py           check
    python tools/asmshare.py --all     also print the exempt groups and why

Identifier names are part of the comparison, since the assembler references
them: a pair that differs only in what it calls the sprite pointer is a pair
waiting to drift, and is reported.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"

# Duplication that is allowed, with the reason it cannot be one text. Anything
# not listed here and not shared through an include fails the run.
EXEMPT = [
    ("SetPalette768 -- 001 1107:0000, 003 1139:0335, 004 11e3:0230. The nine "
     "instructions are the same in all three, but the DECLARATIONS are not, "
     "and cannot be: part 004's is a FAR procedure in the shared VGA unit, "
     "part 003's takes an untyped `var P`, part 001's a `P : Pointer`. An "
     "include carries the header too, so there is no one text to share.",
     ["P1S4.SetPalette768", "PART3_MORPH.SetPalette768", "VGA.SetPalette768"]),
]

# Fewer instructions than this and agreement means nothing: SetMode13h is two.
TRIVIAL = 8

MARKER = re.compile(r"@asm\s+(\d{3})\s+([0-9a-fA-F]{4}):([0-9a-fA-F]{4})"
                    r"(?:\s*\+(\d+))?(?:\s+(\w+))?")
HEADER = re.compile(r"\s*(?:procedure|function)\s+(\w+)")
INCLUDE = re.compile(r"\{\$I\s+([A-Za-z0-9_./]+)\s*\}")
COMMENT = re.compile(r"\{[^{}]*\}", re.S)


def normalise(text):
    """The instructions, with the commentary and the layout taken out."""
    text = COMMENT.sub(" ", text)
    return [" ".join(l.split()).upper() for l in text.split("\n")
            if " ".join(l.split())]


def implementations(lines):
    """Routine -> its assembler, for headers that actually open a body.

    A marker in DEMOVT.PAS sits above the INTERFACE declaration, eighty lines
    from the body, with eight other declarations in between. Taking the first
    `asm` after the header therefore gave all nine music thunks MusicDetect's
    body, and an earlier version of this check happily reported them identical.
    So bodies are found from the headers that open one -- nothing but a var or
    const block may stand between a header and its `asm` -- and are matched to
    markers by name.
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
            b = next(x for x in range(k, len(lines)) if lines[x] == "end;")
        except StopIteration:
            continue
        out.setdefault(h.group(1), normalise("\n".join(lines[k + 1:b])))
    return out


def bodies():
    """UNIT.Routine -> (address, assembler), for assembler written out in the
    .PAS itself.

    A marker followed by a {$I} is a SHARED routine and is skipped: there is
    one text, which is the state this check exists to reach, so counting each
    including unit's copy of it would report the very fix as the fault.
    """
    out = {}
    for path in sorted(SRC.glob("*.PAS")):
        lines = path.read_text(encoding="ascii").split("\n")
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


def main(argv):
    found = bodies()
    allowed = set()
    for _, members in EXEMPT:
        for a in members:
            for b in members:
                allowed.add((a, b))

    names = sorted(found)
    bad = []
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if a.split(".")[0] == b.split(".")[0]:
                continue                        # same unit, not our business
            if len(found[a][1]) < TRIVIAL:
                continue
            if found[a][1] != found[b][1] or (a, b) in allowed:
                continue
            bad.append((a, b))

    print("%d routine(s) with assembler written out in a .PAS" % len(found))
    for a, b in bad:
        print("  DUPLICATED: %s (%s) and %s (%s) are the same %d "
              "instructions." % (a, found[a][0], b, found[b][0],
                                 len(found[a][1])))
        print("              Move them into one src/asm/*.INC and include it "
              "from both -- this tool's docstring says how.")
    for why, members in EXEMPT:
        if "--all" in argv:
            print("  exempt: %s" % ", ".join(members))
            print("          %s" % why)
        gone = [m for m in members if m not in found]
        if gone:
            print("  exempt group has members with no assembler of their own "
                  "any more: %s" % ", ".join(gone))
    print("\n%d exempt group(s), %d unshared duplicate(s)"
          % (len(EXEMPT), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
