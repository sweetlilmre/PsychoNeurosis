"""Assemble the runnable demo: the parts as they SHIPPED, into dist/.

    python tools/package.py            build dist/ and check it against bin/
    python tools/package.py --check    check an existing dist/, write nothing

WHY THIS IS A SEPARATE STEP FROM THE BUILD. What the compiler produces is a load
image; what Asphyxia shipped is that image with a ProTracker module appended past
it. bin/NEUROSIS.001 is 135,991 bytes where the image is 38,528. Appending is not
compilation and has nothing to say about whether the code is right, so it sits
here rather than inside build.py -- and the code-identity checks keep measuring
the load images in run/, untouched by anything below.

THE ORDER MATTERS AND IT IS ONE DIRECTION: the build installs load images under
the originals' names into run/, then this takes them and produces the shipped
files in dist/. Nothing here ever writes into run/, so an artefact row pointing
at run/NEUROSIS.001 cannot be invalidated by a packaging run.

WHAT IS BUILT, AND WHAT IS COPIED. Everything is built from this repository
except one file:

    NEUROSIS.000, .009      our load image. Differs from the shipped file by an
                            appended Borland debug tail (4,546 and 3,044 bytes)
                            that this reconstruction does not produce.
    NEUROSIS.001 .. .007    our load image + assets/partNNN/*.MOD. Byte-identical
                            to the shipped files, all seven.
    NEUROSIS.008            COPIED from bin/. This is DemoVT, third-party, and
                            its reconstruction lives in another repository.
    NEUROSIS.DAT            BUILT, from assets/NEUROSIS.MAN through mkdat.py --
                            never copied, though it comes out byte-identical to
                            the shipped blob, all 1,718,189 bytes.
    PSYCHO.EXE              our build. Byte-identical to the shipped launcher.
    LOADPART, VIDMODE       ours, and NOT shipped by anybody: a part cannot be
    RUNPART.BAT             typed at a DOS prompt because COMMAND.COM decides
                            what is executable by extension, so LOADPART EXECs
                            it the way PSYCHO.EXE does.

NEUROSIS.CFG is deliberately absent. The shipped copy is 397 bytes and the one
this demo leaves behind after a run is 451, so it is written by the setup program
at run time rather than being an input -- copying either would be shipping a
saved answer as though it were data.

THE CHECK IS THE POINT, not the copying. Every packaged file is compared against
its shipped counterpart, whole where that is the claim and load-image where the
difference is a tail we know about. A packaging step that cannot say whether its
output matches the original is just a directory of files.
"""
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
BIN = ROOT / "bin"
RUN = ROOT / "run"
DIST = ROOT / "dist"

# part -> how its shipped file is made. `image` means ours alone; `module` means
# ours with the part's own .MOD appended; `copy` means it is not ours to build.
PARTS = {
    "000": "image",
    "001": "module",
    "002": "module",
    "003": "module",
    "004": "module",
    "005": "module",
    "006": "module",
    "007": "module",
    "008": "copy",
    "009": "image",
}

# Ours, installed under their own names, and how each is compared to the shipped
# file. `file` is whole-file identity; `load-image` forgives an appended tail.
COMPARE = {
    "NEUROSIS.000": "load-image",
    "NEUROSIS.001": "file",
    "NEUROSIS.002": "file",
    "NEUROSIS.003": "file",
    "NEUROSIS.004": "file",
    "NEUROSIS.005": "file",
    "NEUROSIS.006": "file",
    "NEUROSIS.007": "file",
    "NEUROSIS.008": "file",
    "NEUROSIS.009": "load-image",
    "NEUROSIS.DAT": "file",
    "PSYCHO.EXE": "file",
}

# Ours, needed to run one part on its own, and shipped by nobody.
TOOLS = ("LOADPART.EXE", "VIDMODE.EXE", "RUNPART.BAT")


def load_image(data):
    """The MZ load image: the header's own arithmetic, not the file length."""
    if data[:2] not in (b"MZ", b"ZM"):
        return data
    cblp = int.from_bytes(data[2:4], "little")
    cp = int.from_bytes(data[4:6], "little")
    return data[:(cp - 1) * 512 + (cblp or 512)]


def module_for(part):
    """The one .MOD in a part's asset folder, or None.

    Exactly one, and it refuses on more: parts 004 and 007 share a module and
    each folder holds its own copy, so a second file here would mean something
    had gone wrong in carving rather than a choice to make.
    """
    d = ROOT / ("assets/part%s" % part)
    if not d.is_dir():
        return None
    mods = sorted(d.glob("*.MOD"))
    if not mods:
        return None
    if len(mods) > 1:
        raise SystemExit("  assets/part%s holds %d .MOD files -- one is the "
                         "assumption every offset here rests on" % (part, len(mods)))
    return mods[0]


def build_dat():
    """NEUROSIS.DAT, built from the manifest into dist/. Never copied."""
    r = subprocess.run([sys.executable, str(ROOT / "tools/mkdat.py"),
                        "--out", str(DIST)],
                       capture_output=True, text=True, encoding="utf-8",
                       cwd=str(ROOT))
    sys.stdout.write("".join("    %s\n" % l
                             for l in r.stdout.strip().split("\n") if l))
    if r.returncode:
        raise SystemExit("  mkdat.py refused -- see above")


def assemble():
    DIST.mkdir(parents=True, exist_ok=True)
    made = []
    for part, how in sorted(PARTS.items()):
        name = "NEUROSIS.%s" % part
        if how == "copy":
            src = BIN / name
            if not src.exists():
                print("  %-14s MISSING from bin/ -- third-party, cannot be built"
                      % name)
                continue
            shutil.copy(src, DIST / name)
            made.append((name, src.stat().st_size, "copied from bin/"))
            continue
        ours = RUN / name
        if not ours.exists():
            print("  %-14s not in run/ -- build and install first" % name)
            continue
        data = ours.read_bytes()
        note = "our load image"
        if how == "module":
            mod = module_for(part)
            if mod is None:
                raise SystemExit("  no .MOD for part %s" % part)
            data += mod.read_bytes()
            note = "image + %s" % mod.name
        (DIST / name).write_bytes(data)
        made.append((name, len(data), note))

    for name in ("PSYCHO.EXE",) + TOOLS:
        src = RUN / name
        if not src.exists():
            print("  %-14s not in run/ -- build and install first" % name)
            continue
        shutil.copy(src, DIST / name)
        made.append((name, src.stat().st_size, "ours"))
    build_dat()
    return made


def verify():
    """Every packaged file against the one Asphyxia shipped."""
    bad = 0
    print("\n  file           packaged   shipped    compare     result")
    for name in sorted(COMPARE):
        ours = DIST / name
        ship = BIN / name
        if not ours.exists():
            print("  %-14s ABSENT from dist/" % name)
            bad += 1
            continue
        if not ship.exists():
            print("  %-14s no shipped counterpart in bin/" % name)
            continue
        a, b = ours.read_bytes(), ship.read_bytes()
        how = COMPARE[name]
        if how == "load-image":
            b = load_image(b)
        ok = a == b
        if not ok:
            bad += 1
        print("  %-14s %-10d %-10d %-11s %s"
              % (name, len(a), ship.stat().st_size, how,
                 "IDENTICAL" if ok else "DIFFERS"))
    for name in TOOLS:
        if (DIST / name).exists():
            print("  %-14s %-10d %-10s %-11s ours, shipped by nobody"
                  % (name, (DIST / name).stat().st_size, "-", "-"))
    return bad


def main(argv):
    check = "--check" in argv
    if not check:
        print("packaging into dist/")
        for name, size, note in assemble():
            print("  %-14s %-9d %s" % (name, size, note))
    bad = verify()
    print("\n  %d file(s) differ from the shipped originals." % bad)
    if bad == 0:
        print("  Every packaged file is either byte-identical to what Asphyxia "
              "shipped or\n  differs only in a tail this reconstruction does "
              "not produce.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
