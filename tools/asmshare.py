"""The demo compiles the same hand-written routine into more than one part.
Keep those transcriptions from drifting apart.

WHY THIS EXISTS. Part 001 scene 4's clipped sprite blit (`1107:0199`) and part
006 scene 2's (`100f:0000`) are the same routine -- instruction for
instruction, part 001's addresses being part 006's plus $199. Part 006's had
been transcribed verbatim and locked for weeks while part 001 ran a Pascal
rewrite of it, and nothing in the toolkit could say so: `asmverify` checks each
marked routine against the binary it names, so a routine that is MISSING from
one unit is invisible to it. `tools/shapediff.py` found it on 23 Aug 2026 as a
799-byte unaligned span.

WHY NOT ONE SHARED FILE INSTEAD. Two reasons, one of them measured:

  * a shared UNIT is wrong on the bytes. Each original part compiles its own
    copy into its own segment; one copy in one unit would turn the others'
    near calls into far ones and move the code out of the segment the
    disassembly reads it from.

  * a shared {$I} INCLUDE of the assembler body does not compile. TP7 answers
    `Error 118: Include files are not allowed here` for a {$I} inside an `asm`
    block -- measured 23 Aug 2026, and the reason this tool exists rather than
    src/asm/BLITCLIP.INC. An include of the whole procedure would compile, but
    the @asm marker has to sit immediately above a procedure header in a .PAS
    for asmverify to find it, and the marker's part and address differ per
    part, so the routine would drop out of the byte check altogether.

So the duplication stays, as it is in the binaries, and this check is what
makes it safe: the copies are declared here, and the run fails if their
assembler stops agreeing.

    python tools/asmshare.py               check the declared groups
    python tools/asmshare.py --discover    look for groups nobody declared

--discover compares every marked routine's assembler against every other's and
prints the ones that agree. A pair it finds that is NOT declared below is
either a group to add or two routines that happen to be the same few
instructions; the byte counts asmverify locked are the tie-breaker.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"

# Routines the demo compiles into more than one part. Each group is one
# original routine, named UNIT.Routine, and every member's assembler must be
# the same text. The names of parameters and locals are therefore part of the
# agreement: a group whose members disagree only in what they call a register's
# contents is a group waiting to drift, so the transcriptions use one set of
# names and the differing ADDRESSES live in each unit's own comment.
GROUPS = [
    ("the clipped transparent sprite blit -- 001 1107:0199, 006 100f:0000",
     ["P1S4.BlitBlob", "P6S2.Blit"]),
    # Found by --discover. The three locked byte counts differ (24, 40, 24)
    # because the walks stop at different holes, not because the code does:
    # REP OUTSB at the DAC is REP OUTSB in every part that has it.
    ("SetPalette768 -- 001 1107:0000, 003 1139:0335, 004 11e3:0230",
     ["P1S4.SetPalette768", "PART3_MORPH.SetPalette768", "VGA.SetPalette768"]),
]

MARKER = re.compile(r"@asm\s+(\d{3})\s+([0-9a-fA-F]{4}):([0-9a-fA-F]{4})")
HEADER = re.compile(r"\s*(?:procedure|function)\s+(\w+)")
COMMENT = re.compile(r"\{[^{}]*\}", re.S)

# Fewer instructions than this and agreement means nothing: SetMode13h is two.
TRIVIAL = 8


def implementations(lines):
    """Routine -> its assembler, for headers that actually open a body.

    A marker in DEMOVT.PAS sits above the INTERFACE declaration, eighty lines
    from the body, with eight other declarations in between. Taking the first
    `asm` after the header therefore gave all nine music thunks MusicDetect's
    body and the check happily reported them identical. So the bodies are found
    from the headers that open one -- nothing but a var or const block may
    stand between the header and its `asm` -- and matched to markers by name.
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
    """UNIT.Routine -> (address, normalised assembler).

    The unit name is the file's stem, which is what asmverify's EXPECTED keys
    use, so a name here can be looked up there.
    """
    out = {}
    for path in sorted(SRC.glob("*.PAS")):
        lines = path.read_text(encoding="ascii").split("\n")
        impl = implementations(lines)
        for i, line in enumerate(lines):
            m = MARKER.search(line)
            if not m:
                continue
            name = None
            for j in range(i + 1, min(i + 8, len(lines))):
                h = HEADER.match(lines[j])
                if h:
                    name = h.group(1)
                    break
            if name is None or name not in impl:
                continue
            out["%s.%s" % (path.stem, name)] = (
                "%s:%s" % (m.group(2), m.group(3)), impl[name])
    return out


def normalise(text):
    """The instructions, with the commentary and the layout taken out."""
    text = COMMENT.sub(" ", text)
    kept = []
    for line in text.split("\n"):
        line = " ".join(line.split()).upper()
        if line:
            kept.append(line)
    return kept


def check(found):
    bad = 0
    for why, members in GROUPS:
        print("%s" % why)
        missing = [m for m in members if m not in found]
        if missing:
            print("  MISSING: %s -- the marker or the asm block is gone"
                  % ", ".join(missing))
            bad += 1
            continue
        first = found[members[0]][1]
        for m in members:
            addr, body = found[m]
            same = body == first
            print("  %-24s %-12s %3d instruction(s)  %s"
                  % (m, addr, len(body), "agrees" if same else "DIFFERS"))
            if not same:
                bad += 1
                for k, (x, y) in enumerate(zip(first, body)):
                    if x != y:
                        print("      first difference at instruction %d:" % k)
                        print("        %s has  %s" % (members[0], x))
                        print("        %s has  %s" % (m, y))
                        break
                else:
                    print("      same prefix, different length: %d vs %d"
                          % (len(first), len(body)))
    return bad


def discover(found):
    declared = set()
    for _, members in GROUPS:
        for a in members:
            for b in members:
                declared.add((a, b))
    names = sorted(found)
    seen = 0
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if (a, b) in declared:
                continue
            if len(found[a][1]) < TRIVIAL:
                continue
            if found[a][1] == found[b][1]:
                print("  undeclared: %s == %s  (%d instructions)"
                      % (a, b, len(found[a][1])))
                seen += 1
    if not seen:
        print("  nothing undeclared agrees")
    return 0


def main(argv):
    found = bodies()
    if "--discover" in argv:
        print("%d marked routine(s) read" % len(found))
        return discover(found)
    bad = check(found)
    print("\n%d group(s), %d problem(s)" % (len(GROUPS), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
