"""List identifiers each reconstruction unit uses but never declares.

Compiling one error at a time is slow when the whole file is full of them.
This is a crude but effective Pascal scan: strip comments and strings, collect
every identifier, subtract everything declared in the file, everything exported
by VGA/DemoVT, and the Turbo Pascal 7 built-ins.

Crude on purpose -- it over-reports rather than parsing Pascal properly. The
point is a work list, not a compiler.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Turbo Pascal 7 System + Crt + Dos, plus keywords.
BUILTIN = set("""
and array asm begin case const constructor destructor div do downto else end
file for function goto if implementation in inherited inline interface label
mod nil not object of or packed procedure program record repeat set shl shr
string then to type unit until uses var while with xor absolute assembler far
near forward external private public virtual
integer byte word longint shortint boolean char real single double extended
comp pointer text pchar cardinal
true false maxint nil result
write writeln read readln assign reset rewrite close blockread blockwrite seek
filesize filepos erase rename flush append settextbuf ioresult eof eoln
new dispose getmem freemem mark release maxavail memavail sizeof
abs sqr sqrt sin cos arctan ln exp round trunc int frac pi random randomize
odd ord chr pred succ inc dec length copy pos delete insert concat val str
upcase fillchar move addr ptr seg ofs cseg dseg sseg sptr swap hi lo
exit halt runerror break continue paramcount paramstr
mem memw meml port portw
textcolor textbackground clrscr gotoxy wherex wherey delay sound nosound
keypressed readkey window clreol insline delline lowvideo highvideo normvideo
textmode assigncrt crtsetmode checkbreak checkeof directvideo lastmode
windmin windmax
getdate gettime setdate settime intr msdos registers dosversion
getintvec setintvec swapvectors exec keep diskfree disksize fsearch fsplit
fexpand getfattr setfattr getftime setftime findfirst findnext getenv
""".split())

COMMENT = re.compile(r"\{[^}]*\}|\(\*.*?\*\)", re.S)
STRING = re.compile(r"'[^'\n]*'")
# $A000 etc: strip the whole literal, or "A000" reads as an identifier
HEX = re.compile(r"[$][0-9A-Fa-f]+")
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def declared_in(text):
    """Every identifier this file defines: routines, params, vars, consts,
    types, record fields, labels."""
    out = set()
    for m in re.finditer(r"(?im)^\s*(?:procedure|function)\s+([A-Za-z_]\w*)", text):
        out.add(m.group(1).lower())
    # parameter lists and any `a, b, c : Type` declaration line
    for m in re.finditer(r"(?m)^[^:\n]*?([A-Za-z_][\w, ]*?)\s*:\s*[A-Za-z_^]", text):
        for ident in IDENT.findall(m.group(1)):
            out.add(ident.lower())
    for m in re.finditer(r"\(([^)]*)\)", text):          # params inside ( )
        for part in m.group(1).split(";"):
            if ":" in part:
                for ident in IDENT.findall(part.split(":")[0]):
                    out.add(ident.lower())
    for m in re.finditer(r"(?m)^\s*([A-Za-z_]\w*)\s*=", text):   # const/type
        out.add(m.group(1).lower())
    for m in re.finditer(r"(?im)^\s*unit\s+([A-Za-z_]\w*)", text):
        out.add(m.group(1).lower())
    return out


def exported(path):
    """Identifiers a unit's interface section exports."""
    text = COMMENT.sub(" ", Path(path).read_text(errors="replace"))
    i = text.lower().find("interface")
    j = text.lower().find("implementation")
    return declared_in(text[i:j if j > 0 else len(text)])


def scan(path, extra):
    raw = Path(path).read_text(errors="replace")
    text = HEX.sub(" ", STRING.sub(" ", COMMENT.sub(" ", raw)))
    # asm blocks use register names and labels; skip them wholesale
    text = re.sub(r"(?is)\basm\b.*?\bend\b", " ", text)
    known = declared_in(text) | extra | BUILTIN
    used, seen = [], set()
    for m in IDENT.finditer(text):
        w = m.group(0)
        lw = w.lower()
        if lw in known or lw in seen:
            continue
        seen.add(lw)
        line = raw[:m.start()].count("\n") + 1
        used.append((w, line))
    return used


def main(argv):
    shared = exported(ROOT / "src" / "VGA.PAS") | exported(ROOT / "src" / "DEMOVT.PAS")
    files = argv or sorted(p.name for p in (ROOT / "src").glob("PART*.PAS"))
    grand = {}
    for name in files:
        p = ROOT / "src" / name
        miss = scan(p, shared)
        if miss:
            print(f"\n=== {name}  ({len(miss)} undeclared) ===")
            for w, ln in miss:
                print(f"   {ln:>4}  {w}")
        for w, _ in miss:
            grand.setdefault(w.lower(), [0, w])[0] += 1
    print("\n=== shared across parts (used in 2+) ===")
    for _, (n, w) in sorted(grand.items(), key=lambda kv: -kv[1][0]):
        if n > 1:
            print(f"   {n:>2}x  {w}")


if __name__ == "__main__":
    main(sys.argv[1:])
