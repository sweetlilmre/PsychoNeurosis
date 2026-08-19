"""Report where the assembler-transcription rule is not yet met.

The rule (docs/24-continuation.md, and project memory as transcribe-asm-verbatim)
is that hand-written assembler goes in verbatim and carries three things:

  1. the assembler itself;
  2. a comment on EVERY line saying what that instruction does;
  3. a block comment above holding the equivalent Pascal, labelled as
     reference only.

This checks 2 and 3 mechanically. It cannot check 1 -- that needs the binary --
so a unit passing this is not the same as a unit that has been audited.

Reporting only: it never fails a build. Parts 001, 002 and 004-007 have not
been swept yet and are expected to show up here.

    python tools/asmaudit.py            every unit
    python tools/asmaudit.py PART3      only names containing PART3
"""
import pathlib
import re
import sys

SRC = pathlib.Path("src")
LOOKBACK = 50          # lines above `asm` to search for the equivalent-Pascal block


def audit(path):
    lines = path.read_text(encoding="ascii", errors="replace").split("\n")
    in_asm = False
    uncommented = []
    missing_equiv = []
    blocks = 0
    owner = None

    for n, line in enumerate(lines, 1):
        s = line.strip()

        if re.match(r"^(procedure|function)\s", s):
            owner = s.rstrip(";")

        if s == "asm":
            in_asm = True
            blocks += 1
            above = "\n".join(lines[max(0, n - 1 - LOOKBACK):n - 1])
            if "EQUIVALENT PASCAL" not in above:
                missing_equiv.append((n, owner))
            continue

        if not in_asm:
            continue
        if s == "end;":
            in_asm = False
            continue
        if not s or s.startswith("{"):
            continue
        if "{" not in line:
            uncommented.append((n, s))

    return blocks, uncommented, missing_equiv


def main():
    want = sys.argv[1].upper() if len(sys.argv) > 1 else ""
    clean, dirty = [], []

    for path in sorted(SRC.glob("*.PAS")):
        if want and want not in path.name.upper():
            continue
        blocks, uncommented, missing = audit(path)
        if not blocks:
            continue
        if uncommented or missing:
            dirty.append((path, blocks, uncommented, missing))
        else:
            clean.append((path, blocks))

    for path, blocks, uncommented, missing in dirty:
        print("%s  (%d asm block%s)" % (path.name, blocks, "" if blocks == 1 else "s"))
        for n, owner in missing:
            print("    line %-5d no equivalent-Pascal block   %s" % (n, owner or "?"))
        for n, text in uncommented:
            print("    line %-5d uncommented   %s" % (n, text))
        print("")

    for path, blocks in clean:
        print("%-22s clean  (%d asm block%s)"
              % (path.name, blocks, "" if blocks == 1 else "s"))

    print("\n%d unit(s) meet the rule, %d do not." % (len(clean), len(dirty)))


if __name__ == "__main__":
    main()
