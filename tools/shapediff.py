"""Where does our compiled code stop matching the original's shape?

asmverify answers this for DECLARED hand-assembler targets. This tool asks
the opposite, coverage question: walk EVERY byte of every user segment of an
original part and report the spans that cannot be aligned against our built
part at all. A big unaligned span in the middle of a scene unit is nearly
always one of two things:

  * hand assembler that got re-expressed as Pascal -- the class the old
    audit could not see (an inline BASM block inside a compiled routine has
    no ENTER of its own and often no REP), which is how part 001's mosaic
    block sampling crawled for a week; or
  * a structural transcription divergence in compiled code (different
    statement shape, different locals), which may be behaviourally fine but
    is where any pacing gap hides; or

  * a routine WE ALREADY HAVE, transcribed under another part's name. The
    demo reuses whole routines across parts, so a span missing from this
    part can be sitting verbatim in another unit -- part 001's blitter at
    1107:0199 is part 006's 100f:0000, instruction for instruction, and had
    been locked in P6S2.PAS for weeks while this part ran a Pascal rewrite of
    it. Every span is therefore also looked for in EVERY other built harness,
    and one that turns up there is a copy job, not a disassembly job.

The alignment reuses asmverify's tolerant differ: 1-2 byte holes are
displacements, three or more is a real divergence. Spans shorter than
--min (default 16) are noise from data between routines and are not shown.

    python tools/shapediff.py 001            one part
    python tools/shapediff.py all            every part with a harness
    python tools/shapediff.py 001 --same     also say which other harness
                                             already has each span

--same costs a search of every built image per span, so it is off by default.

Output lines are  seg:from..to  size  -- read them with the part's unit
headers: the ADDRESS MAP in each unit says which routine owns the range.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import importlib.util

_spec = importlib.util.spec_from_file_location(
    "asmverify", pathlib.Path(__file__).resolve().parent / "asmverify.py")
asmverify = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(asmverify)

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUN = ROOT / "run"

# User-code segments per part, from the unit headers, in ascending order.
# The extent of each is the next entry's base; the last user segment is
# capped by the first RTL segment, listed as the final sentinel entry.
SEGMENTS = {
    "001": {"exe": "TPART1.EXE",
            "segs": [0x1012, 0x1082, 0x10e3, 0x1107, 0x12b2, 0x12c5,
                     0x1483, 0x1491, 0x1532],
            "rtl": 0x1546},
    "002": {"exe": "TPART2.EXE",
            "segs": [0x1008, 0x107c, 0x108b, 0x13f9, 0x140c, 0x142a, 0x1436],
            "rtl": 0x1444},
    "003": {"exe": "TPART3.EXE",
            "segs": [0x1015, 0x10b8, 0x1139, 0x1192, 0x119d, 0x11f3,
                     0x120f, 0x125e, 0x12f8, 0x136b],
            "rtl": 0x137b},
    "005": {"exe": "TPART5.EXE",
            "segs": [0x100e, 0x1096, 0x1102, 0x124a, 0x1252, 0x12c8],
            "rtl": 0x12d8},
}

MIN_SPAN = 16


def load_base(part):
    """The BASE binary -- the actual 1994 release -- not the _fpu file
    asmverify reads. The _fpu files are this project's own disassembly aids
    (docs/02-fpu-emulator.md): the CD 3x emulator traps rewritten to raw
    9B+ESC so Ghidra can decode them. Our builds carry the traps exactly as
    the release does, so comparing against the _fpu form would show a run of
    2-byte holes at every FPU op and drown x87-heavy regions in noise."""
    p = ROOT / "work" / "split" / ("NEUROSIS_%s.exe" % part)
    blob = p.read_bytes()
    hdr = int.from_bytes(blob[8:10], "little") * 16
    return blob, hdr


# A span found in another harness has to be long enough that the match is the
# routine rather than a shared prologue. Twenty-four bytes is three or four
# instructions past any ENTER/PUSH DS/LDS opening.
ELSEWHERE = 24


def elsewhere(chunk, own_exe):
    """Which OTHER built harness already contains this original code.

    Returns (image name, bytes that line up) or (None, 0). Our own part is
    skipped: by construction the span did not align there, and a partial hit
    inside it is the divergence we are already reporting.
    """
    images = [(n, b) for n, b in asmverify.built_images() if n != own_exe]
    name, image, at = asmverify.locate(chunk, images, fragment=True)
    if at < 0:
        return None, 0
    got, _, _ = asmverify.walk(chunk, image[at:at + len(chunk)], False)
    return (name, got) if got >= ELSEWHERE else (None, 0)


def part_report(part, min_span, same=False):
    info = SEGMENTS[part]
    blob, hdr = load_base(part)
    ours = (RUN / info["exe"]).read_bytes()
    images = [(info["exe"], ours)]
    bounds = info["segs"] + [info["rtl"]]
    total = matched_total = 0
    spans = []
    for k, seg in enumerate(info["segs"]):
        base = hdr + (seg - 0x1000) * 16
        size = (bounds[k + 1] - seg) * 16
        data = blob[base:base + size]
        total += size
        pos = 0
        gap_start = None
        while pos < len(data):
            chunk = data[pos:pos + asmverify.WINDOW]
            if len(chunk) < asmverify.ANCHOR:
                break
            _, image, at = asmverify.locate(chunk, images, fragment=True)
            got = 0
            if at >= 0:
                got, _, _ = asmverify.walk(
                    chunk, image[at:at + len(chunk)], False)
            if got >= asmverify.MINIMUM:
                if gap_start is not None:
                    spans.append((seg, gap_start, pos))
                    gap_start = None
                matched_total += got
                pos += got
            else:
                if gap_start is None:
                    gap_start = pos
                pos += 1
        if gap_start is not None and len(data) - gap_start >= min_span:
            spans.append((seg, gap_start, len(data)))
    print("part %s vs %s: %d of %d segment byte(s) aligned (%.1f%%)"
          % (part, info["exe"], matched_total, total,
             100.0 * matched_total / max(1, total)))
    shown = 0
    for seg, a, b in sorted(spans, key=lambda s: s[1] - s[2]):
        if b - a < min_span:
            continue
        note = ""
        if same:
            base = hdr + (seg - 0x1000) * 16
            chunk = blob[base + a:base + min(b, a + asmverify.WINDOW)]
            where, got = elsewhere(chunk, info["exe"])
            if where:
                note = "  -- %d byte(s) of it are already in %s" % (got, where)
        print("  %04x:%04x..%04x  %5d byte(s) unaligned%s"
              % (seg, a, b, b - a, note))
        shown += 1
    if not shown:
        print("  no unaligned span >= %d bytes" % min_span)


def main(argv):
    min_span = MIN_SPAN
    same = "--same" in argv
    parts = [a for a in argv if not a.startswith("-")]
    for a in argv:
        if a.startswith("--min="):
            min_span = int(a.split("=")[1])
    if parts == ["all"] or not parts:
        parts = sorted(SEGMENTS)
    for p in parts:
        part_report(p, min_span, same)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
