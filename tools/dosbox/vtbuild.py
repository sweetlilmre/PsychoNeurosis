r"""Compile VangeliSTracker 1.39b with the real Turbo Pascal 7.01, under DOSBox-X.

This is the RELEASE source, not our reconstruction -- JCAB / VangeliSTeam's own
tracker, the later version of the codebase `demovt/` is rebuilding. Compiling it
is worth doing for two reasons: it proves the release tree is complete and
buildable, and it gives a running VT.EXE to compare behaviour against.

    python tools/dosbox/vtbuild.py           stage + compile VT, SHELLVT, MAKESTR
    python tools/dosbox/vtbuild.py VT.PAS    one program

Whatever builds is installed into run/ alongside the demo, the same way
dosbuild.py does it, so `run.bat` reaches it as E:\VT.EXE.

NOTHING IS RENAMED. Turbo Pascal 7 finds a unit by the first EIGHT characters
of its identifier, which is why the release's filenames are already truncations
-- `UNIT SoundDevices` lives in SOUNDDEV.PAS and `uses SoundDevices` finds it.
So unlike dosbuild.py, which has to map PART3_SPRITES.PAS onto P3SPRITE.PAS,
this stages the tree by straight binary copy. The sources are latin-1 with
Spanish text in the comments and string constants; copying bytes keeps them
intact.

THE SOURCE IT COMPILES IS NOT IN SOURCE CONTROL. `VangeliSTracker/` is held
out by .gitignore until the licensing position has been checked, along with
`demovt/` and `work/unpack/`, so this script will not run for anyone who does
not already have the 1.39b release on disk. It is kept here for the same reason
`tools/unlzexe.py` is: it is original code that contains nothing of the
release's, and it is how the reading in `demovt/docs/` was corroborated.

THE ONE EDIT IS TPC.CFG. The release's says

    /U.\LIB;D:\LENG\TP\TVISION

which is the author's own Turbo Vision path. Everything else in it -- the
switches, /O.\LIB, /M -- is the original's and is left exactly as found.
"""
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "VangeliSTracker"
BUILD = ROOT / "build" / "vt"
# Generated, so they live with the build rather than beside the hand-written
# psycho.conf -- build/ is gitignored and these are not worth tracking.
CONF = BUILD / "DOSBUILD.CFG"
DOSBOX = Path(r"D:\DOSBox-X\dosbox-x.exe")

# The three PROGRAMs, in MAKE.BAT's order. MAKESTR is built first there because
# running it regenerates VT_ESP.LNG and VT_ENG.LNG from VTSTRCON/STRCONST; both
# files already ship, so building it is a check on the string units rather than
# a necessity.
#
# MAKE.BAT also calls FONT\MAKE first, which runs GETFONT.EXE over FONT.CEL and
# BINOBJ over the result to make FONT.OBJ. LIB\FONT.OBJ is already there, so
# that step is skipped -- as are tdstrip and lzexe, which only strip debug info
# and pack the result. Neither changes what the program does.
PROGRAMS = ["MAKESTR.PAS", "VT.PAS", "SHELLVT.PAS"]

# Copied so a built VT.EXE can actually start: its config, the two language
# files MAKESTR produces, and the three bundled modules.
#
# NOT *.MAP. The release ships VT.MAP and SHELLVT.MAP and VTSRC.LST lists them
# next to VT.CFG as though they were data, but they are linker maps -- TPC.CFG
# has /GD, so the compiler writes VT.MAP itself and would overwrite a staged
# copy anyway. They are build output and belong nowhere near run/.
DATA = ["*.CFG", "*.LNG", "*.VTO"]


def stage():
    """Binary-copy the release tree into build/vt, then fix TPC.CFG's /U path."""
    if BUILD.exists():
        shutil.rmtree(BUILD)
    (BUILD / "LIB").mkdir(parents=True)

    n = 0
    for pat in ("*.PAS", "*.EXE"):
        for f in sorted(SRC.glob(pat)):
            shutil.copy(f, BUILD / f.name.upper())
            n += 1
    for pat in ("*.PAS", "*.ASM", "*.OBJ", "*.INC"):
        for f in sorted((SRC / "LIB").glob(pat)):
            shutil.copy(f, BUILD / "LIB" / f.name.upper())
            n += 1
    for pat in DATA:
        for f in sorted(SRC.glob(pat)):
            shutil.copy(f, BUILD / f.name.upper())

    # The author's Turbo Vision path becomes this install's. Read and written
    # as latin-1 bytes so nothing else in the file is disturbed.
    cfg = (SRC / "TPC.CFG").read_text(encoding="latin-1")
    fixed = re.sub(r"(?im)^/U.*$", r"/U.\\LIB;C:\\TP\\UNITS", cfg)
    if fixed == cfg:
        raise SystemExit("TPC.CFG: no /U line found -- refusing to guess")
    (BUILD / "TPC.CFG").write_text(fixed, encoding="latin-1")
    return n


def write_batch(targets):
    """TPC picks up the STAGED TPC.CFG because it sits in the current directory.

    That matters: a TPC.CFG in the current directory REPLACES the one beside
    TPC.EXE rather than adding to it, so C:\\TP\\BIN\\TPC.CFG's own
    /UC:\\TP\\UNITS does not apply and the staged file has to carry it. This is
    why stage() rewrites the /U line instead of appending a second one.
    """
    lines = ["@echo off", "echo === VangeliSTracker 1.39b > D:\\BUILD.LOG"]
    for t in targets:
        lines += [
            "echo. >> D:\\BUILD.LOG",
            f"echo ---- {t} >> D:\\BUILD.LOG",
            f"C:\\TP\\BIN\\TPC.EXE {t} >> D:\\BUILD.LOG",
            "if errorlevel 1 echo ** FAILED >> D:\\BUILD.LOG",
            "if not errorlevel 1 echo ** OK >> D:\\BUILD.LOG",
        ]
    (BUILD / "BUILD.BAT").write_text("\r\n".join(lines) + "\r\n", encoding="ascii")


CONF_TEMPLATE = """\
# DOSBox-X configuration for building VangeliSTracker 1.39b with TP 7.01.
# GENERATED by tools/dosbox/vtbuild.py -- edit that, not this.
#
# Drives:
#     C:  D:\\DOSBox-X\\Machine\\HDD    the TP 7.01 install (C:\\TP\\BIN, C:\\TP\\UNITS)
#     D:  {build}    the staged release source

[sdl]
autolock    = false
waitonerror = false

[dosbox]
machine  = svga_s3
memsize  = 16
captures = capture
title    = {title}

[cpu]
core    = auto
cputype = pentium_ii
cycles  = max

[render]
frameskip = 0
aspect    = false

[mixer]
nosound = {nosound}

[dos]
xms = true
ems = true
umb = true
lfn = false

[autoexec]
mount C D:\\DOSBox-X\\Machine\\HDD
mount D {build}
set PATH=%PATH%;C:\\TP\\BIN
D:
{tail}
"""


def write_conf():
    CONF.write_text(CONF_TEMPLATE.format(
        build=BUILD, title="VangeliSTracker build", nosound="true",
        tail="call D:\\BUILD.BAT\nexit"), encoding="ascii")


def run_dosbox(conf, timeout):
    cmd = [str(DOSBOX), "-conf", str(conf), "-silent", "-exit"]
    try:
        subprocess.run(cmd, cwd=str(ROOT), timeout=timeout,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return "TIMEOUT - dosbox-x did not exit"
    return None


def report(log):
    """Print the log and summarise. TPC writes one line per unit it compiles."""
    print(log.rstrip())
    ok = log.count("** OK")
    bad = log.count("** FAILED")
    errs = re.findall(r"(?im)^(.*\(\d+\):\s*(?:Error|Fatal).*)$", log)
    print("\n" + "-" * 62)
    for e in dict.fromkeys(errs):
        print("  " + e.strip())
    exes = sorted(p.name for p in BUILD.glob("*.EXE")
                  if p.name not in ("MAKESTR.EXE", "GETFONT.EXE"))
    print("  %d program(s) OK, %d failed" % (ok, bad))
    print("  executables in build/vt: %s" % (", ".join(exes) or "none"))
    return bad == 0


def install(targets):
    """Copy what just built into run/, where the demo is launched from.

    Same reasoning as dosbuild.py's install: stage() wipes build/vt at the
    start of every invocation, so an .EXE there only survives until the next
    build. Copying by hand afterwards is easy to forget and easy to GET AWAY
    with, because run/ still holds the previous build under the same name --
    the program launches, behaves like the old code, and the change looks like
    it did nothing.

    The data files go too, or VT.EXE starts and finds no language file. They
    are the release's own, not built here, but they belong beside the .EXE and
    stage() has already gathered them.
    """
    run = ROOT / "run"
    if not run.is_dir():
        print("  no run/ -- nothing installed")
        return
    for t in targets:
        exe = BUILD / (t.split(".")[0] + ".EXE")
        if exe.exists():
            shutil.copy(exe, run / exe.name)
            print("  installed run/%s  (%d bytes)" % (exe.name, exe.stat().st_size))
    for pat in DATA:
        for f in sorted(BUILD.glob(pat)):
            # TPC.CFG is the compiler's, not the tracker's. It would sit in
            # run/ doing nothing and inviting the question of which build used
            # it, so it stays in build/vt.
            if f.name == "TPC.CFG":
                continue
            shutil.copy(f, run / f.name)
    print("  installed the release's .CFG, .LNG and .VTO files beside them")


def main(argv):
    targets = [a.upper() for a in argv if not a.startswith("-")] or PROGRAMS
    for t in targets:
        if not (SRC / t).exists():
            raise SystemExit("no such source: VangeliSTracker/%s" % t)

    if not DOSBOX.exists():
        raise SystemExit("DOSBox-X not found at %s" % DOSBOX)

    print("staging %s -> %s" % (SRC.name, BUILD))
    print("  %d source file(s)" % stage())
    write_batch(targets)
    write_conf()

    print("compiling %s ..." % ", ".join(targets))
    err = run_dosbox(CONF, timeout=600)
    if err:
        raise SystemExit(err)
    log = BUILD / "BUILD.LOG"
    if not log.exists():
        raise SystemExit("no BUILD.LOG -- the autoexec did not run")
    good = report(log.read_text(encoding="latin-1"))
    if good:
        install(targets)
        print("\n  run.bat, then VT at the E: prompt")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
