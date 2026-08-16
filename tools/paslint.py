"""Catch the Pascal defects that cost the most time to diagnose from a compiler
error, because the compiler reports them somewhere other than where they are.

  nested braces   TP7 does NOT nest { } comments -- the first } closes it, so a
                  {?} or { blank } written INSIDE a block comment silently ends
                  it and the rest of the comment is parsed as code. The error
                  then appears dozens of lines later and looks unrelated.

  stray close     more } than {, usually a } used decoratively inside a comment.

  reserved words  identifiers that collide with something TP7 already means.
                  OFFSET is an assembler operator, so a parameter called Offset
                  produces "Syntax error" inside an asm block; Text is a
                  built-in type.

  DSeg addresses  Mem[DSeg:$XXXX] or Ptr(DSeg, $XXXX) reaching into our OWN
                  data segment at an address copied out of the original. This
                  one compiles, runs, and silently does nothing useful: the
                  address is where the data sits in the ORIGINAL's DGROUP, and
                  Turbo Pascal decides where ours goes. It cost a whole scene
                  -- part 003 scene 2 loaded its waypoint table to $B250, the
                  array it should have filled stayed zero, and the star tube
                  neither moved nor ran to length. Name the variable instead.
                  Mem[$A000:...] and Mem[VirtScrSeg:...] are fine; those are
                  addresses we do not own and cannot name.

Run it before reaching for the compiler:

    python tools/paslint.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Identifiers that are fine in Pascal generally but bite in specific contexts.
RESERVED = {
    "offset": "OFFSET is an operator in TP7's inline assembler",
    "text":   "Text is a built-in file type",
    "seg":    "Seg is a built-in function",
    "ofs":    "Ofs is a built-in function",
    "ptr":    "Ptr is a built-in function",
    "addr":   "Addr is a built-in function",
    "mem":    "Mem is a built-in array",
    "port":   "Port is a built-in array",
}

DECL = re.compile(r"(?im)^\s*(?:procedure|function)\s+\w+\s*\(([^)]*)\)")

# Mem[DSeg : $B250]  /  MemW[DSeg:X]  /  Ptr(DSeg, $B250)
DSEG = re.compile(r"(?i)\b(Mem[WL]?\s*\[\s*DSeg\s*:|Ptr\s*\(\s*DSeg\s*,)")


def strip_comments(src):
    """Blank out { } and (* *) comments, keeping line numbering intact."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        if src[i] == "{":
            j = src.find("}", i)
            j = n if j < 0 else j + 1
        elif src.startswith("(*", i):
            j = src.find("*)", i)
            j = n if j < 0 else j + 2
        else:
            i += 1
            continue
        for k in range(i, j):
            if out[k] != "\n":
                out[k] = " "
        i = j
    return "".join(out)


def check(path):
    src = path.read_text(errors="replace")
    problems = []

    # ---- comment nesting
    depth, line = 0, 1
    for ch in src:
        if ch == "\n":
            line += 1
        elif ch == "{":
            if depth == 0:
                depth = 1
            else:
                problems.append((line, "nested '{' inside a { } comment -- "
                                       "TP7 does not nest, the comment ended early"))
        elif ch == "}":
            if depth == 1:
                depth = 0
            else:
                problems.append((line, "stray '}' -- more closes than opens"))
    if depth:
        problems.append((line, "unterminated { } comment at end of file"))

    # ---- parameter names that collide
    for m in DECL.finditer(src):
        ln = src[:m.start()].count("\n") + 1
        for part in m.group(1).split(";"):
            names = part.split(":")[0]
            for ident in re.findall(r"[A-Za-z_]\w*", names):
                why = RESERVED.get(ident.lower())
                if why:
                    problems.append((ln, "parameter '%s': %s" % (ident, why)))

    # ---- hard-coded addresses in our own data segment
    code = strip_comments(src)
    for m in DSEG.finditer(code):
        ln = code[:m.start()].count("\n") + 1
        problems.append((ln, "%s... addresses our own DGROUP at an offset "
                             "taken from the original -- Turbo Pascal decides "
                             "that layout, so this writes to the wrong place. "
                             "Name the variable and use it."
                         % m.group(1).replace(" ", "")))

    return problems


def main(argv):
    files = [ROOT / "src" / a for a in argv] if argv else sorted(
        (ROOT / "src").glob("*.PAS"))
    total = 0
    for f in files:
        probs = check(f)
        if probs:
            print("\n=== %s ===" % f.name)
            for ln, msg in probs:
                print("  line %4d  %s" % (ln, msg))
            total += len(probs)
    print("\n%d problem(s) in %d file(s)" % (total, len(files)))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
