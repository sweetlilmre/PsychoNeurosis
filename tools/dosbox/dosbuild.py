"""Compile the reconstruction with the real Turbo Pascal 7.01, under DOSBox-X.

The reconstruction is written in Pascal but has never been through a compiler,
so "does it build" has never been asked. This asks it.

    python tools/dosbox/dosbuild.py --selftest    prove the toolchain works
    python tools/dosbox/dosbuild.py               stage + compile the real source
    python tools/dosbox/dosbuild.py VGA           compile one unit

Everything is staged into build/ with 8.3 names because TP7 is a real-mode DOS
tool: DOS filenames are 8.3, so PART3_SPRITES.PAS has to become P3SPRITE.PAS,
and the `uses` clauses and {$I} directives are rewritten to match.

DOSBox-X is a GUI application and writes nothing to stdout, so the compiler's
output is redirected to a file INSIDE the mounted drive and read back from the
host afterwards.
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build"
CONF = ROOT / "tools" / "dosbox" / "psycho.conf"
# Where TASM lives inside the DOSBox image. TP7's built-in assembler is 286
# only ({$G+} is documented as "Generate 80286 Code Switch"), so the demo's
# 386 fixed-point maths comes in through {$L DEMOMATH.OBJ}, and that object
# has to be assembled first.
TASM = r"C:\TASM\BIN\TASM.EXE"
DOSBOX = Path(r"D:\DOSBox-X\dosbox-x.exe")

# Reconstruction source -> 8.3 DOS name. The unit name inside each file is the
# Pascal identifier and is independent of the filename, but TP7 finds units BY
# FILENAME, so `uses Part3Sprites` must become `uses P3Sprite`.
NAMES = {
    # The whole-program reconstructions build under harness names: TPSYCHO
    # is the launcher, TPART0 the setup (STARTUP.PAS) and TPART9 the end
    # screen (BYEBYE.PAS), consistent with TPART1..7. The sources keep the
    # names the originals carried or their debug info recovered.
    "PSYCHO.PAS":     ("TPSYCHO.PAS",  "Psycho",        "Psycho"),
    "BYEBYE.PAS":     ("TPART9.PAS",   "ByeBye",        "ByeBye"),
    "STARTUP.PAS":    ("TPART0.PAS",   "Startup",       "Startup"),
    "DETECT.PAS":     ("DETECT.PAS",   "Detect",        "Detect"),
    "VGA.PAS":        ("VGA.PAS",      "VGA",           "VGA"),
    "DEMOVT.PAS":     ("DEMOVT.PAS",   "DemoVT",        "DemoVT"),
    "MODEX.PAS":      ("MODEX.PAS",    "ModeX",         "ModeX"),
    "FIXMATH.PAS":    ("FIXMATH.PAS",  "FixMath",       "FixMath"),

    # part 001 -- one unit per scene, plus a driver
    "P1S1.PAS":       ("P1S1.PAS",     "P1S1",          "P1S1"),
    "P1S2.PAS":       ("P1S2.PAS",     "P1S2",          "P1S2"),
    "P1S3.PAS":       ("P1S3.PAS",     "P1S3",          "P1S3"),
    "P1S4.PAS":       ("P1S4.PAS",     "P1S4",          "P1S4"),
    "P1S5.PAS":       ("P1S5.PAS",     "P1S5",          "P1S5"),
    "P1INTRO.PAS":    ("P1INTRO.PAS",  "P1Intro",       "P1Intro"),

    # part 002 -- one unit per scene, plus the three units they share.
    # Every one of these is transcribed from NEUROSIS_002_fpu.exe; the
    # segment each came from is in its header comment.
    "P2VIEW.PAS":     ("P2VIEW.PAS",   "P2View",        "P2View"),
    "P2S1.PAS":       ("P2S1.PAS",     "P2S1",          "P2S1"),
    "P2S2.PAS":       ("P2S2.PAS",     "P2S2",          "P2S2"),
    "P2MAIN.PAS":     ("P2MAIN.PAS",   "P2Main",        "P2Main"),

    # part 003 -- already one unit per scene
    "PART3_TUNNEL.PAS":  ("P3TUNNEL.PAS", "Part3Tunnel",  "P3Tunnel"),
    "PART3_STARS.PAS":   ("P3STARS.PAS",  "Part3Stars",   "P3Stars"),
    "PART3_MORPH.PAS":   ("P3MORPH.PAS",  "Part3Morph",   "P3Morph"),
    "PART3_GLOBE.PAS":   ("P3GLOBE.PAS",  "Part3Globe",   "P3Globe"),
    "PART3_BLOCKS.PAS":  ("P3BLOCKS.PAS", "Part3Blocks",  "P3Blocks"),
    "PART3_WAVES.PAS":   ("P3WAVES.PAS",  "Part3Waves",   "P3Waves"),
    "PART3_SPRITES.PAS": ("P3SPRITE.PAS", "Part3Sprites", "P3Sprite"),
    "P3MAIN.PAS":        ("P3MAIN.PAS",   "P3Main",       "P3Main"),

    # part 004 -- one scene, on the shared VGA and DemoVT units.
    "PART4_LEMMINGS.PAS": ("P4LEMS.PAS",  "Part4Lemmings", "P4Lems"),
    # part 005 -- one unit per scene the way the binary has it (segments 100e,
    # 1096, 1102) plus the main body. Read from NEUROSIS_005_fpu.exe from
    # scratch; the earlier single-unit PART5_ROTOZOOM pass, which carried
    # inference and stubs, is gone.
    "P5S1.PAS":           ("P5S1.PAS",    "P5S1",          "P5S1"),
    "P5S2.PAS":           ("P5S2.PAS",    "P5S2",          "P5S2"),
    "P5S3.PAS":           ("P5S3.PAS",    "P5S3",          "P5S3"),
    "P5MAIN.PAS":         ("P5MAIN.PAS",  "P5Main",        "P5Main"),
    # part 006 -- one unit per scene the way the binary has it, plus the main
    # body. The scenes RUN in the order 1095, 100f, 1118, 11bb, which is not
    # the segment order. Read from NEUROSIS_006_fpu.exe from scratch; the
    # earlier single-unit PART6_CREDITS pass has been deleted.
    "P6S1.PAS":           ("P6S1.PAS",    "P6S1",          "P6S1"),
    "P6S2.PAS":           ("P6S2.PAS",    "P6S2",          "P6S2"),
    "P6S3.PAS":           ("P6S3.PAS",    "P6S3",          "P6S3"),
    "P6S4.PAS":           ("P6S4.PAS",    "P6S4",          "P6S4"),
    "P6MAIN.PAS":         ("P6MAIN.PAS",  "P6Main",        "P6Main"),
    "P7S1.PAS":           ("P7S1.PAS",    "P7S1",          "P7S1"),
    "P7MAIN.PAS":         ("P7MAIN.PAS",  "P7Main",        "P7Main"),

}


# Test harnesses are generated by tools/mktests.py with names that are
# already 8.3 and program identifiers that already match, so their NAMES rows
# are the identity and there is nothing to keep in sync by hand. Adding a row
# to mktests.py is the only step needed to get a new harness building.
for _h in sorted((ROOT / "src").glob("TP*.PAS")):
    NAMES.setdefault(_h.name, (_h.name, _h.stem, _h.stem))


HELLO = """program Hello;
{ Toolchain self-test: proves TPC.EXE runs and produces an executable. }
var
  I : Integer;
begin
  WriteLn('TP7 self-test OK');
  for I := 1 to 3 do WriteLn('  line ', I);
end.
"""


def stage_source(text, name83):
    """Rewrite unit name, uses clauses and include paths for the 8.3 world."""
    _, unit_old, unit_new = NAMES[name83]
    # `unit Part3Sprites;` -> `unit P3Sprite;`
    text = re.sub(r"(?im)^(\s*unit\s+)%s(\s*;)" % re.escape(unit_old),
                  r"\g<1>%s\g<2>" % unit_new, text)
    # every other unit referenced in a uses clause
    for _, (_, old, new) in NAMES.items():
        text = re.sub(r"(?i)\b%s\b" % re.escape(old), new, text)
    # {$I gen/P3PAL.INC} -> {$I GEN\P3PAL.INC}
    text = re.sub(r"(?i)\{\$I\s+gen/([A-Z0-9_]+\.INC)\s*\}",
                  r"{$I GEN\\\1}", text)
    return text


def prepare(selftest=False):
    BUILD.mkdir(exist_ok=True)
    for f in BUILD.glob("*"):
        if f.is_file():
            f.unlink()
    if selftest:
        (BUILD / "HELLO.PAS").write_text(HELLO, encoding="ascii")
        return ["HELLO.PAS"]

    gen = BUILD / "GEN"
    gen.mkdir(exist_ok=True)
    for f in gen.glob("*"):
        f.unlink()
    for inc in (ROOT / "src" / "gen").glob("*.INC"):
        shutil.copy(inc, gen / inc.name)

    # The 386 maths module and its table. Both go in the build ROOT, not GEN:
    # TASM resolves INCLUDE relative to the current directory, and TPC looks
    # for the .OBJ next to the unit that links it.
    for f in sorted((ROOT / "src" / "asm").glob("*")):
        if f.suffix.upper() in (".ASM", ".INC"):
            shutil.copy(f, BUILD / f.name.upper())

    staged = []
    for src, (name83, _, _) in NAMES.items():
        p = ROOT / "src" / src
        if not p.exists():
            continue
        # Pascal sources are 7-bit; anything else is a mistake worth seeing.
        text = p.read_text(encoding="utf-8", errors="replace")
        (BUILD / name83).write_text(stage_source(text, src), encoding="ascii",
                                    errors="replace")
        staged.append(name83)
    return staged


USES = re.compile(r"(?is)\buses\b(.*?);")


def unit_deps(name83):
    """The 8.3 names a staged source depends on, from its `uses` clauses.

    Reads the STAGED copy in build/, so the names have already been rewritten
    to their 8.3 form and match the filenames on disk. Units TP7 ships with
    (Crt, Dos, System, ...) simply do not exist in build/ and drop out.
    """
    p = BUILD / name83
    if not p.exists():
        return []
    text = p.read_text(encoding="latin1", errors="replace")
    # strip comments so a `uses` inside one cannot pull in a phantom
    text = re.sub(r"(?s)\{.*?\}|\(\*.*?\*\)", " ", text)
    out = []
    for clause in USES.findall(text):
        for word in re.split(r"[,\s]+", clause):
            cand = word.strip().upper()
            if cand and (BUILD / (cand + ".PAS")).exists():
                out.append(cand + ".PAS")
    return out


def deps_first(sel):
    """`sel` plus everything it needs, units before the things that use them."""
    order, seen = [], set()

    def visit(name):
        if name in seen:
            return
        seen.add(name)
        for d in unit_deps(name):
            visit(d)
        order.append(name)

    for t in sel:
        visit(t)
    return order


def write_batch(targets):
    """TPC switches that matter here:
         /E<dir>   where the .EXE goes
         /U<dirs>  where to LOOK for units (semicolon separated)
         /I<dirs>  where to look for {$I} includes
         /M        make -- only recompile what changed
         /$S-      STACK CHECKING OFF. Turbo Pascal 7 defaults it ON, and with
                   it on every procedure that has a frame -- INCLUDING an
                   `assembler` one -- opens with a seven-byte
                   XOR AX,AX / CALLF <stack check> before the body. The demo
                   was built with it off: its routines go straight from
                   PUSH BP / MOV BP,SP into the first real instruction. Leaving
                   the default alone made every hand-transcribed routine differ
                   from the binary in its opening bytes, which is how
                   tools/asmverify.py turned it up.
       There is no /D output switch: /D is conditional DEFINES, and passing a
       path to it is what produced "Error 130: Error in initial conditional
       defines" on the first attempt. .TPU files land next to the source.
    """
    lines = ["@echo off", "echo === build > D:\\BUILD.LOG"]
    # TASM first: TP7's built-in assembler stops at the 286, so the demo's 386
    # fixed-point maths is a .ASM linked with {$L}. /ML keeps the PUBLIC names
    # case-sensitive, which is how TPC matches them to the Pascal identifiers.
    for asm in sorted(p.name for p in BUILD.glob("*.ASM")):
        lines.append("echo. >> D:\\BUILD.LOG")
        lines.append(f"echo ---- {asm} >> D:\\BUILD.LOG")
        lines.append(f"{TASM} /ML /Z {asm} >> D:\\BUILD.LOG")
        lines.append("if errorlevel 1 echo ** FAILED >> D:\\BUILD.LOG")
        lines.append("if not errorlevel 1 echo ** OK >> D:\\BUILD.LOG")
    for t in targets:
        lines.append("echo. >> D:\\BUILD.LOG")
        lines.append(f"echo ---- {t} >> D:\\BUILD.LOG")
        lines.append(f"C:\\TP\\BIN\\TPC.EXE {t} /ED: /UD:;C:\\TP\\UNITS /ID:;D:\\GEN "
                     f"/$S- >> D:\\BUILD.LOG")
        lines.append("if errorlevel 1 echo ** FAILED >> D:\\BUILD.LOG")
        lines.append("if not errorlevel 1 echo ** OK >> D:\\BUILD.LOG")
    (BUILD / "BUILD.BAT").write_text("\r\n".join(lines) + "\r\n", encoding="ascii")


def run_dosbox(timeout=180):
    log = BUILD / "BUILD.LOG"
    if log.exists():
        log.unlink()
    cmd = [str(DOSBOX), "-conf", str(CONF), "-silent", "-exit"]
    try:
        subprocess.run(cmd, cwd=str(ROOT), timeout=timeout,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, "TIMEOUT - dosbox-x did not exit"
    if not log.exists():
        return None, "no BUILD.LOG produced - autoexec did not run"
    return log.read_text(encoding="latin1"), None


def main(argv):
    selftest = "--selftest" in argv
    only = [a.upper() for a in argv if not a.startswith("-")]

    # Lint FIRST. TP7 reports a nested-comment defect dozens of lines away
    # from its cause, so catching it here saves a wild goose chase -- this has
    # bitten three times already.
    if not selftest:
        lint = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "paslint.py")],
            capture_output=True, text=True, encoding="utf-8")
        if lint.returncode:
            print(lint.stdout)
            print("build refused: fix the above first")
            return 2

    targets = prepare(selftest)
    if only and not selftest:
        # match on the 8.3 stem, e.g. "VGA" or "P3TUNNEL"
        sel = [t for t in targets if t.split(".")[0] in only]
        if not sel:
            print(f"no target matches {only}; known: "
                  f"{', '.join(t.split('.')[0] for t in targets)}")
            return 2
        # prepare() wipes build/, so everything a target depends on has to be
        # rebuilt even when only that target was asked for. The dependencies
        # are read out of the staged sources' own `uses` clauses rather than
        # listed here -- a hardcoded ["VGA.PAS", "DEMOVT.PAS"] silently gave
        # "Error 15: File not found (P2VGA.TPU)" the moment a part arrived
        # that uses anything else.
        targets = deps_first(sel)
    write_batch(targets)

    print(f"staged {len(targets)} file(s) into build/: {', '.join(targets)}")
    out, err = run_dosbox()
    if err:
        print("FAILED:", err)
        return 1
    # Show the source around each failure -- TPC prints the offending line but
    # not its context, and context is usually what identifies the fix.
    shown = 0
    pat = re.compile(r"^([A-Z0-9_\\]+\.(?:PAS|INC))\((\d+)\): (Error .+)$", re.M)
    for m in pat.finditer(out):
        fname, line, msg = m.group(1), int(m.group(2)), m.group(3)
        print("")
        print(fname + "(" + str(line) + "): " + msg)
        f = BUILD / fname
        if f.exists():
            src = f.read_text(encoding="latin1", errors="replace").splitlines()
            lo, hi = max(1, line - 4), min(len(src), line + 2)
            for n in range(lo, hi + 1):
                mark = ">>" if n == line else "  "
                print("  %s %4d %s" % (mark, n, src[n - 1].rstrip()))
        shown += 1
    if not shown:
        ok = re.findall(r"^(\d+) lines,", out, re.M)
        if ok:
            print("all %d target(s) compiled: %s"
                  % (len(ok), ", ".join(n + " lines" for n in ok)))
        else:
            print(out)
        install(targets)
    return 0


def install(targets):
    """Copy every .EXE just built into run/, where the harnesses are run from.

    prepare() wipes build/ at the start of each invocation, so an .EXE only
    survives until the next build of anything else. Copying it by hand
    afterwards is a step that is easy to forget and, worse, easy to get away
    with: run/ still holds the PREVIOUS build under the same name, so the
    harness launches, behaves like the old code, and the change looks like it
    did nothing. That happened once already. Do it here instead.
    """
    run = ROOT / "run"
    if not run.is_dir():
        return
    for t in targets:
        exe = BUILD / (t.split(".")[0] + ".EXE")
        if exe.exists():
            shutil.copy(exe, run / exe.name)
            print("  installed run/%s  (%d bytes)" % (exe.name, exe.stat().st_size))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
