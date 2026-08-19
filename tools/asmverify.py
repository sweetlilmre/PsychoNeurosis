"""Byte-diff every transcribed assembler routine against the original binary.

THE RULE for this project is that hand-written assembler is transcribed
verbatim rather than re-expressed. That is a claim about BYTES, so it can be
checked mechanically: build the reconstruction, find each routine in the built
executable, and compare it against the same routine in the 1994 binary.

Routines declare themselves in the source. One marker line goes immediately
above the procedure or function header:

    { @asm 004 1005:0328 }
    procedure VLine(...); ...

  004         which NEUROSIS_00x.exe the routine was read out of
  1005:0328   where it starts in that binary
  +32         optional -- compare exactly this many bytes and do not go
              looking for a return. Two things need it: assembler that is
              inline inside a compiled Pascal routine, where there is no
              routine to walk to the end of; and any routine whose extent is
              known from the function table, where declaring it beats letting
              the walk guess. The walk stops at the first byte that LOOKS like
              a return, and in 1,254 bytes of scan converter a C2 preceded by
              a C9 turns up long before the real one. A name may follow.
  ?           optional -- the address has NOT been confirmed. Marked routines
              are listed on their own and do not fail the run, so a guess is
              never mistaken for a verified transcription.

A routine whose Pascal body merely CONTAINS an asm block gets no marker: there
is no whole-routine byte comparison to make when most of the routine is
compiled code. Only routines that are assembler end to end are declared.

The end address is NOT declared and does not need to be: the comparison walks
forward until the code stops matching, which is the routine's end.

WHAT CANNOT MATCH, AND WHY IT IS SKIPPED

Relative jumps and calls are self-relative, so they DO match and are compared.
What cannot match is any absolute 16-bit address, because Turbo Pascal put our
variables at different DGROUP offsets than the original's:

    A1 dd dd        MOV AX,[disp16]
    BE dd dd        MOV SI,OFFSET Something
    26 8B 05 ...    a segment-overridden load

    83 7E FB 00     CMP BYTE PTR [BP-5],0

The differ treats an isolated run of ONE or TWO differing bytes as one such
displacement -- two for an absolute address, one for a BP-relative local --
records it, and carries on. Three or more differing bytes in a row is an
opcode change, i.e. a real divergence, and stops the walk.

That heuristic is deliberately tight. A transcription error nearly always
changes an opcode, a register field or an instruction length, and any of those
shifts every byte after it, so it shows up as a long run rather than hiding in
a hole.

LOCKING IN A RESULT

A routine passes on length. `expect` in EXPECTED below is the number of bytes
that matched last time the routine was checked by hand; if a change makes the
match shorter, that is a regression and the run fails. A routine with no entry
is reported but does not fail the run, so a newly marked routine can be looked
at before it is locked.

    python tools/dosbox/dosbuild.py        build everything first
    python tools/asmverify.py              then check it
    python tools/asmverify.py --learn      print the table entries to paste
"""
import pathlib
import re
import struct
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
RUN = ROOT / "run"
SPLIT = ROOT / "work" / "split"

# The FPU variants are the ones the rest of the tooling reads, where both
# exist. Header size comes out of the MZ header, so nothing is hard-coded.
ORIGINALS = {
    "001": "NEUROSIS_001_fpu.exe",
    "002": "NEUROSIS_002_fpu.exe",
    "003": "NEUROSIS_003_fpu.exe",
    "004": "NEUROSIS_004.exe",
    "005": "NEUROSIS_005_fpu.exe",
    "006": "NEUROSIS_006_fpu.exe",
    "007": "NEUROSIS_007_fpu.exe",
}

# The marker need not be alone on its line or open the comment -- a routine
# that needs a paragraph of explanation puts the @asm last, inside it.
MARKER = re.compile(
    r"@asm\s+(\d{3})\s+([0-9a-fA-F]{4}):([0-9a-fA-F]{4})"
    r"(?:\s*\+(\d+))?(?:\s+(\w+))?\s*(\?)?\s*\}")
HEADER = re.compile(r"\s*(?:procedure|function)\s+(\w+)")

# How much of the original to pull in when looking for a routine. Nothing in
# the demo's hand assembler comes close to this.
WINDOW = 0x400

# Length of the run used to align the built code against the original. It has
# to be long enough to be unique in a 30KB executable and short enough to fall
# between two displacements.
ANCHOR = 10

# A believed alignment has to reach an agreed RET and be at least this long.
# SetMode13h is six bytes, so the floor is low; the RET is what does the work.
MINIMUM = 4

# routine -> bytes that lined up when it was last checked. A change that makes
# any of these SHORTER is a regression and fails the run.
EXPECTED = {
    "DEMOVT.GetVolume": 21,
    "DEMOVT.MusicDetect": 64,
    "DEMOVT.MusicFunc3": 14,
    "DEMOVT.MusicPoll": 14,
    "DEMOVT.MusicPos": 27,
    "DEMOVT.MusicStart": 14,
    "DEMOVT.MusicStop": 14,
    "DEMOVT.SetVolume": 28,
    "MODEX.SelectPlane": 20,
    "P7S1.FliBrun": 75,
    "P7S1.FliCopy": 25,
    "P7S1.FliLC": 99,
    "P7S1.FliSS2": 98,
    "MODEX.SetModeX": 93,
    "MODEX.ShowFrame": 67,
    "P1S1.BlitSprite": 20,
    "P1S1.SaveUnder": 20,
    "P1S1.whose": 38,
    "P1S4.SetPalette768": 24,
    "P2S1.BlitBitmapX": 56,
    "P2S1.DoorRaiseOneRow": 38,
    "P2VIEW.FillRect": 145,
    "P2VIEW.FlipPage": 42,
    "P2VIEW.Plot": 67,
    "P2VIEW.SetMode": 26,
    "P5S1.DrawMesh": 132,
    "P5S1.FillTriangle": 1254,
    "P5S1.Project": 87,
    "P5S2.RotozoomFrame": 64,
    "P5S3.FixDiv": 32,
    "P5S3.FixMul": 19,
    "P5S3.Project5": 166,
    "P5S3.RotatePoint5": 334,
    "P5S3.SinCos5": 178,
    "P6S2.Blit": 170,
    "P6S3.Overlay": 33,
    "P6S3.ScrollOut": 37,
    "PART3_BLOCKS.BlockDown": 32,
    "PART3_BLOCKS.BlockUp": 32,
    "PART3_GLOBE.RenderFrame": 121,
    "PART3_MORPH.ClearPage": 62,
    "PART3_MORPH.DrawMorph": 56,
    "PART3_MORPH.DrawShape": 92,
    "PART3_MORPH.FlipPage": 29,
    "PART3_MORPH.GetPalette768": 24,
    "PART3_MORPH.PlotPixel": 62,
    "PART3_MORPH.Set400Lines": 12,
    "PART3_MORPH.SetAngles": 18,
    "PART3_MORPH.SetPalette768": 40,
    "PART3_MORPH.StepAngles": 390,
    "PART3_MORPH.TransformPoint": 293,
    "PART3_SPRITES.DrawRotated": 103,
    "PART4_LEMMINGS.Blit": 63,
    "PART4_LEMMINGS.ColumnSlideIn": 112,
    "PART4_LEMMINGS.CopyScreen": 30,
    "PART4_LEMMINGS.HLine": 38,
    "PART4_LEMMINGS.ScrollRender": 60,
    "PART4_LEMMINGS.VLine": 44,
    "VGA.ClearScreen": 22,
    "VGA.CopyScreen": 28,
    "VGA.FillRect": 37,
    "VGA.GetPalette768": 24,
    "VGA.GetPixel": 27,
    "VGA.GetRGB": 32,
    "VGA.GetRGBTo": 26,
    "VGA.PaletteDim": 19,
    "VGA.PutPixel": 28,
    "VGA.SetPalette768": 24,
    "VGA.SetRGB": 27,
    "VGA.SetRGBFrom": 32,
    "VGA.WaitRetrace": 14,
}


def load_original(part):
    blob = (SPLIT / ORIGINALS[part]).read_bytes()
    hdr = struct.unpack_from("<H", blob, 8)[0] * 16
    return blob, hdr


def markers():
    """Every declared routine, in source order."""
    out = []
    for path in sorted(SRC.glob("*.PAS")):
        lines = path.read_text(encoding="utf-8", errors="replace").split("\n")
        for i, line in enumerate(lines):
            m = MARKER.search(line)
            if not m:
                continue
            name = m.group(5)
            if name is None:
                for j in range(i + 1, min(i + 6, len(lines))):
                    h = HEADER.match(lines[j])
                    if h:
                        name = h.group(1)
                        break
            if name is None:
                print("%s:%d  @asm marker with no procedure under it and no "
                      "name of its own" % (path.name, i + 1))
                continue
            out.append((name, path.name, m.group(1),
                        int(m.group(2), 16), int(m.group(3), 16),
                        m.group(6) == "?",
                        int(m.group(4)) if m.group(4) else 0))
    return out


def built_images():
    """OUR harnesses only.

    run/ also holds ORIG0..ORIG9.EXE -- copies of the 1994 binaries kept there
    so the demo can be run side by side. Comparing an original against itself
    passes trivially and proves nothing, so only TP*.EXE is searched.
    """
    return [(p.name, p.read_bytes()) for p in sorted(RUN.glob("TP*.EXE"))]


def locate(orig, images, fragment=False):
    """Where the routine sits in a built executable -- BEST fit, not first.

    Anchoring on the first run that happens to be unique is not good enough:
    a run from the middle of the routine can also occur inside an unrelated
    one, and the resulting alignment then scores zero and looks like a
    transcription error. So this collects every alignment suggested by any
    unique ANCHOR-length run near the start, scores each by how far the
    comparison actually gets, and keeps the winner.
    """
    best = (0, None, None, -1)
    for image_name, image in images:
        tried = set()
        for d in range(0, min(len(orig) - ANCHOR, 0x60)):
            probe = orig[d:d + ANCHOR]
            at = image.find(probe)
            while at >= 0:
                start = at - d
                if start >= 0 and start not in tried:
                    tried.add(start)
                    got, _, ret = walk(orig, image[start:start + len(orig)],
                                       not fragment)
                    score = got if (ret or fragment) else 0
                    if score > best[0]:
                        best = (score, image_name, image, start)
                at = image.find(probe, at + 1)
            if len(tried) > 64:
                break
    if best[0] < MINIMUM:
        return None, None, -1
    return best[1], best[2], best[3]


# The routine is over at its RETF. Stopping there removes the need to declare
# an end address, and doubles as the correctness signal: a genuine match runs
# to a RETF that BOTH copies agree on, and a walk that dribbles out without
# reaching one has drifted into neighbouring code and is not believed.
#
# Both near and far returns occur -- the shared units are far procedures ending
# CB / CA, part 004's primitives are near ones ending C9 C2 nn nn.
# A one-byte hole behind one of these is NOT a displacement, it is a different
# BRANCH TARGET -- a real change of control flow. Part 006's picture overlay
# got through the byte check with a JZ landing one instruction late, because
# the single differing byte looked like an ordinary displacement.
BRANCH = set(range(0x70, 0x80)) | {0xE0, 0xE1, 0xE2, 0xE3, 0xEB}

RETS = {0xCB: 1, 0xCA: 3, 0xC3: 1, 0xC2: 3}

# C3 and C2 are near returns and both turn up constantly as operand bytes, so
# they only count as a terminator when they follow the LEAVE or POP BP that
# ends a framed procedure. Without that guard the C2 in `FE C2` (INC DL) cut
# MusicDetect off at 37 of its 64 bytes. CB and CA need no guard.
FRAME_END = (0xC9, 0x5D)

# The gate stops a walk that has wandered into unrelated code and is only
# staying alive on one- and two-byte "holes". Eight in sixteen is deliberately
# loose: routines that are mostly memory moves are half displacement bytes by
# nature -- Morph_SetAngles is six loads and six stores and nothing else -- and
# a tighter gate cut MusicDetect off at 37 of its real 64 bytes.
DENSITY_WINDOW = 16
DENSITY_LIMIT = 8


def walk(orig, mine, find_ret=True):
    """Compare forward to the routine's return.

    Returns (length, holes, ended_on_ret). A run of one or two differing bytes
    is taken as a displacement -- one byte for a BP-relative local, two for an
    absolute address -- and skipped; three or more is an opcode change and
    stops the walk.

    CB and CA end it outright. C3 and C2 only end it when they follow the LEAVE
    or POP BP that closes a framed procedure, because both turn up constantly
    as operand bytes. If the walk runs out without a return of either kind, the
    last unguarded return-shaped byte it passed is used instead -- that is what
    the frameless `assembler` procedures need, since they close with a bare C3.
    """
    holes = []
    diffs = []
    fallback = 0
    i = 0
    n = min(len(orig), len(mine))
    while i < n:
        if orig[i] == mine[i]:
            size = RETS.get(orig[i]) if find_ret else None
            if size and orig[i:i + size] == mine[i:i + size]:
                if orig[i] in (0xCB, 0xCA) or (
                        i > 0 and orig[i - 1] in FRAME_END):
                    return i + size, holes, True
                fallback = i + size
            i += 1
            continue
        run = 0
        while i + run < n and orig[i + run] != mine[i + run]:
            run += 1
        if run > 2:
            break
        holes.append(i)
        diffs.extend(range(i, i + run))
        if len([d for d in diffs if d > i - DENSITY_WINDOW]) > DENSITY_LIMIT:
            break
        i += run
    if fallback:
        return fallback, [h for h in holes if h < fallback], True
    return i, holes, not find_ret and i >= n


def main(argv):
    learn = "--learn" in argv
    probe = "--probe" in argv
    images = built_images()
    if not images:
        print("nothing built -- run tools/dosbox/dosbuild.py first")
        return 1

    rows = markers()
    if not rows:
        print("no @asm markers found in src/*.PAS")
        return 1

    bad = 0
    new = 0
    unconfirmed = 0
    learned = []
    print("%-18s %-16s %-10s %6s %5s" %
          ("routine", "source", "original", "bytes", "holes"))
    print("-" * 66)

    for name, source, part, seg, ofs, unsure, span in rows:
        key = "%s.%s" % (source.rsplit(".", 1)[0], name)
        blob, hdr = load_original(part)
        base = hdr + (seg - 0x1000) * 16 + ofs
        orig = blob[base:base + (span or WINDOW)]

        image_name, image, at = locate(orig, images, bool(span))
        if at < 0:
            if unsure:
                print("%-18s %-16s %s %04x:%04x   address unconfirmed"
                      % (name, source, part, seg, ofs))
                unconfirmed += 1
            else:
                print("%-18s %-16s %s %04x:%04x   NOT FOUND in any built .EXE"
                      % (name, source, part, seg, ofs))
                bad += 1
            if probe:
                for cand, got in candidates(blob, hdr, seg, images):
                    print("        try %04x:%04x -- %d bytes line up"
                          % (seg, cand, got))
            continue

        matched, holes, ret = walk(orig, image[at:at + len(orig)], not span)
        if span:
            ret = matched >= span      # a fragment is judged on length alone
        want = EXPECTED.get(key)
        learned.append((key, matched))

        note = "" if ret else ("  SHORT -- %d of %d declared" % (matched, span)
                               if span else
                               "  NO RET -- alignment not believed")
        if not ret:
            bad += 1
        elif want is None:
            note = "  (not locked)"
            new += 1
        elif matched < want:
            note = "  SHORTER than the locked %d -- REGRESSION" % want
            bad += 1
        elif matched > want:
            note = "  longer than the locked %d" % want

        print("%-18s %-16s %s %04x:%04x %6d %5d  %-11s%s"
              % (name, source, part, seg, ofs, matched, len(holes),
                 image_name, note))

        if want is not None and matched < want:
            k = matched
            print("      diverges at +%03X:  orig %s" %
                  (k, orig[k:k + 8].hex()))
            print("      %18s built %s" %
                  ("", image[at + k:at + k + 8].hex()))

    print("-" * 66)
    print("%d routine(s): %d locked, %d not locked, %d unconfirmed, "
          "%d failing."
          % (len(rows), len(rows) - new - bad - unconfirmed, new,
             unconfirmed, bad))

    if learn:
        print("\nEXPECTED = {")
        for key, matched in sorted(learned):
            print('    "%s": %d,' % (key, matched))
        print("}")

    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
