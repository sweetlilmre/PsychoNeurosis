"""Verification ledger: every routine, its binary address, and its status.

The point of this is to make "inferred" impossible to hide behind. A routine
marked [inferred] with no address recorded is a claim with nothing behind it;
this prints exactly those so they cannot be quietly left alone.

    python tools/ledger.py            summary + everything unverified
    python tools/ledger.py --all      the full table
"""
import collections
import pathlib
import re
import sys

ROOT = Path = pathlib.Path(__file__).resolve().parents[1]

MARK = re.compile(
    r'(?ms)\{[^{}]*?\[(transcribed|inferred|stub)\](.*?)\}\s*\n'
    r'((?:procedure|function)\s+\w+)')
ADDR = re.compile(r'\b[0-9a-f]{3,4}:[0-9a-f]{4}\b|FUN_[0-9a-f]{4}_[0-9a-f]{4}')

# An empty body is a routine that compiles and does nothing. It has to match
# BOTH layouts -- multi-line, and `procedure X; begin end;` on one line --
# because the one-liners were invisible to an earlier version of this, which
# is exactly how two scenes came to draw nothing with a clean report.
EMPTY = re.compile(
    r"(?m)^((?:procedure|function)\s+\w+[^;)]*(?:\([^)]*\))?[^;]*;)"
    r"\s*(?:\{[^}]*\}\s*)?begin\s*end;")


def scan():
    rows = []
    for p in sorted((ROOT / "src").glob("*.PAS")):
        for kind, note, decl in MARK.findall(p.read_text(errors="replace")):
            m = ADDR.search(note)
            rows.append({
                "unit": p.name.replace(".PAS", ""),
                "kind": kind,
                "addr": m.group(0) if m else "",
                "name": decl.split()[-1],
            })
    return rows


def main(argv):
    rows = scan()
    counts = collections.Counter(r["kind"] for r in rows)
    total = len(rows)
    print("VERIFICATION LEDGER")
    print("-" * 62)
    for k in ("transcribed", "inferred", "stub"):
        n = counts.get(k, 0)
        print(f"  {k:<14} {n:>3}   {n * 100 // max(1, total):>3}%")
    print(f"  {'TOTAL':<14} {total:>3}")

    if "--all" in argv:
        print("\nFULL TABLE")
        print("-" * 62)
        for r in rows:
            print(f"  {r['unit']:<18} {r['kind']:<13} "
                  f"{r['addr'] or '-':<14} {r['name']}")
        return 0

    bad = [r for r in rows if r["kind"] == "inferred"]
    if bad:
        print(f"\nUNVERIFIED -- inferred, not yet checked against the binary ({len(bad)}):")
        for r in bad:
            print(f"  {r['unit']:<18} {r['addr'] or 'NO ADDRESS':<14} {r['name']}")

    empties = []
    for f in sorted((ROOT / "src").glob("*.PAS")):
        for m in EMPTY.finditer(f.read_text(errors="replace")):
            name = m.group(1).split("(")[0].split()[-1]
            empties.append((f.stem, name))
    if empties:
        print("")
        print("EMPTY BODIES (%d) -- these compile and do nothing:" % len(empties))
        for unit, name in empties:
            print(f"  {unit:<18} {name}")

    noaddr = [r for r in rows if not r["addr"] and r["kind"] != "stub"]
    if noaddr:
        print(f"\nNO ADDRESS RECORDED ({len(noaddr)}) -- cannot be re-checked:")
        for r in noaddr:
            print(f"  {r['unit']:<18} {r['kind']:<13} {r['name']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
