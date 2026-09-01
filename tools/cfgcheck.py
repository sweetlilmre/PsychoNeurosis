"""NEUR0.PAS's seven module offsets against everything that can contradict them.

    python tools/cfgcheck.py
    python tools/cfgcheck.py --quiet     one line per failing row, nothing else

WHAT THE HAZARD IS. NEUROSIS.CFG is an INPUT, not a saved preference: it names
the sound device and carries the byte offset of each part's ProTracker module
inside the part's own file. The setup program writes it, and the offsets are
HARDCODED in NEUR0.PAS -- seven decimal literals in seven WriteLn strings.

Those seven numbers are our load-image sizes. Nothing enforced that. If a part's
image ever changed size, NEUR0.PAS would go on writing the old number, the setup
would produce a CFG that reads the wrong bytes, and the failure would surface as
music that plays garbage or does not play -- at run time, in DOSBox, in front of
whoever happened to watch it. Every byte instrument in the tree would stay green,
because each one measures a file and this is an agreement BETWEEN files.

package.py deliberately does not generate NEUROSIS.CFG: a shipped copy would be a
saved answer masquerading as data. So the offsets cannot be checked by comparing
our CFG against the shipped one -- there is no "our CFG". This checks the number
where it actually lives instead.

## The four legs, and each measures something the others cannot

  1. **Against the 1994 CFG.** bin/NEUROSIS.CFG is what Asphyxia's own setup
     wrote, 397 bytes, and it is tracked. Its seven offsets are 1994 ground truth
     and depend on nothing we build. This leg alone would catch a transcription
     slip in NEUR0.PAS even with no compiler on the machine.
  2. **Against our load images.** run/NEUROSIS.00n's byte length must equal the
     offset, because the offset is where the image ends and the module begins.
     This is the leg the continuation note asked for.
  3. **Against the packaged file's CONTENT.** At that offset in dist/NEUROSIS.00n
     there must actually be a ProTracker module: a 20-byte title, then one of the
     known signatures at +1080. Legs 1 and 2 compare numbers to numbers; this one
     asks the bytes. It is what would catch package.py appending in a different
     order, or a .MOD carved short.
  4. **Against a leftover CFG, if one is there.** dist/NEUROSIS.CFG is whatever
     the setup last wrote during a watched run. It is untracked and usually
     absent, so it can only ever be a bonus witness -- but when it is present it
     is the only leg that has seen the compiled setup program actually run.

Legs 1 and 2 need nothing but tracked files and always run. Leg 3 needs a
packaged dist/ and leg 4 needs a run behind it; when either is missing this says
UNMEASURED in those words rather than counting it as agreement. A leg that goes
quiet when it cannot measure is how a check comes to pass on nothing.
"""
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SETUP = ROOT / "src/NEUR0.PAS"
SHIPPED_CFG = ROOT / "bin/NEUROSIS.CFG"
LEFTOVER_CFG = ROOT / "dist/NEUROSIS.CFG"
RUN = ROOT / "run"
DIST = ROOT / "dist"

# The parts that carry a module. 000 and 009 have none and are not named in the
# CFG at all, which is why this is seven rows and not ten.
PARTS = ("001", "002", "003", "004", "005", "006", "007")

# `neurosis.003 /off:72240` in a Pascal string literal or in a CFG line -- the
# same shape in both, because the first writes the second verbatim.
OFFSET_RE = re.compile(r"neurosis\.(\d{3})\s+/off:(\d+)", re.IGNORECASE)

# A ProTracker module's signature, at +1080 past the module's own start. The
# 15-instrument format has none, and if one of these ever turns up here that is a
# finding rather than a case to add: every module this demo ships is M.K.
MOD_SIGS = (b"M.K.", b"M!K!", b"M&K!", b"FLT4", b"FLT8", b"4CHN", b"6CHN",
            b"8CHN", b"CD81", b"OKTA", b"16CN", b"32CN")
SIG_AT = 1080


def offsets_from(path, what):
    """The seven part -> offset pairs in a file that names them.

    Refuses on anything but seven. A partial parse is the failure mode that
    matters: a renamed file or a reformatted line would yield six rows, and six
    rows that all agree would otherwise print as a pass.
    """
    if not path.exists():
        raise SystemExit("  %s is missing (%s) -- it is tracked, so this is not "
                         "a case to skip" % (path.relative_to(ROOT), what))
    text = path.read_text(encoding="latin-1")
    found = {}
    for part, off in OFFSET_RE.findall(text):
        if part in found:
            raise SystemExit("  %s names part %s twice -- one of them is not the "
                             "offset this reads" % (path.relative_to(ROOT), part))
        found[part] = int(off)
    missing = [p for p in PARTS if p not in found]
    extra = sorted(set(found) - set(PARTS))
    if missing or extra:
        raise SystemExit(
            "  %s yielded %d offset row(s), not %d%s%s\n"
            "  The pattern did not match what the file says. Fix the pattern or "
            "the file;\n  do not let this run on a partial parse."
            % (path.relative_to(ROOT), len(found), len(PARTS),
               "\n    never matched: %s" % ", ".join(missing) if missing else "",
               "\n    unexpected:    %s" % ", ".join(extra) if extra else ""))
    return found


def module_at(data, off):
    """What sits at `off`: the module's title and signature, or why not.

    Returns (title, signature) on a module and (None, complaint) otherwise.
    """
    if off + SIG_AT + 4 > len(data):
        return None, "offset is past the end of a %d-byte file" % len(data)
    sig = data[off + SIG_AT:off + SIG_AT + 4]
    if sig not in MOD_SIGS:
        return None, "no module signature at +%d, found %r" % (SIG_AT, sig)
    title = data[off:off + 20].split(b"\0")[0].decode("latin-1").strip()
    return title, sig.decode("ascii")


def main(argv):
    quiet = "--quiet" in argv
    ours = offsets_from(SETUP, "our setup program, the offsets' home")
    shipped = offsets_from(SHIPPED_CFG, "the 1994 CFG")

    bad = 0
    rows = []
    for part in PARTS:
        off = ours[part]
        name = "NEUROSIS.%s" % part
        note = []

        # Leg 1: the 1994 CFG.
        if shipped[part] != off:
            bad += 1
            note.append("1994 CFG says %d" % shipped[part])

        # Leg 2: our load image's length.
        image = RUN / name
        if not image.exists():
            bad += 1
            size = None
            note.append("run/%s absent -- build and install first" % name)
        else:
            size = image.stat().st_size
            if size != off:
                bad += 1
                note.append("load image is %d bytes" % size)

        # Leg 3: the packaged file's bytes at that offset.
        packaged = DIST / name
        if not packaged.exists():
            title, sig = None, None
        else:
            title, sig = module_at(packaged.read_bytes(), off)
            if title is None:
                bad += 1
                note.append(sig)
                sig = None

        rows.append((name, off, size, title, sig, note))

    if not quiet:
        print("NEUR0.PAS's seven offsets, against the 1994 CFG, our load images "
              "and the\npackaged files' bytes at that offset.\n")
        print("  part           /off:   1994   load image   module at that offset")
        for name, off, size, title, sig, note in rows:
            if sig:
                where = "%s  '%s'" % (sig, title)
            elif (DIST / name).exists():
                where = "WRONG"
            else:
                where = "UNMEASURED, no dist/"
            print("  %-14s %6d %6s %12s   %s"
                  % (name, off, "same" if shipped[name[-3:]] == off else "DIFFERS",
                     "same" if size == off else
                     ("absent" if size is None else str(size)), where))
            for n in note:
                print("      %s" % n)
    elif bad:
        for name, off, size, title, sig, note in rows:
            for n in note:
                print("  %s /off:%d -- %s" % (name, off, n))

    unmeasured = [n for n, *_ in rows if not (DIST / n).exists()]

    # Leg 4, and it is a bonus: usually there is no leftover CFG at all.
    leftover = None
    if LEFTOVER_CFG.exists():
        leftover = offsets_from(LEFTOVER_CFG, "a leftover from a watched run")
        wrong = [p for p in PARTS if leftover[p] != ours[p]]
        bad += len(wrong)
        if not quiet:
            print("\n  dist/NEUROSIS.CFG, written by the setup during a run: "
                  "%s" % ("all seven offsets agree" if not wrong
                          else "DISAGREES on %s" % ", ".join(wrong)))
        elif wrong:
            print("  dist/NEUROSIS.CFG disagrees on %s" % ", ".join(wrong))

    if not quiet:
        if unmeasured:
            print("\n  %d of %d rows UNMEASURED on the module leg -- dist/ has no "
                  "packaged file.\n  Run tools/package.py; legs 1 and 2 above are "
                  "measured either way." % (len(unmeasured), len(PARTS)))
        if leftover is None:
            print("  No dist/NEUROSIS.CFG, so nothing here has watched the "
                  "compiled setup run.")
        print("\n  %d disagreement(s) across %d offset(s) and %d leg(s)."
              % (bad, len(PARTS), 4 if leftover else 3))
        if not bad:
            # Never claim the module leg for a row that had no packaged file to
            # read. A summary that generalises past what it measured is how a
            # green line comes to stand for nothing.
            print("  Every offset NEUR0.PAS writes is where our load image ends "
                  "and is what the\n  1994 setup wrote", end="")
            if unmeasured:
                print(". The module leg holds for the %d row(s) that had a\n"
                      "  packaged file to read, and says nothing about %s."
                      % (len(PARTS) - len(unmeasured), ", ".join(unmeasured)))
            else:
                print(", and it lands on a ProTracker module in the\n  "
                      "packaged file.")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
