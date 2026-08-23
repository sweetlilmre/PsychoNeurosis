"""Which bytes of an original do NOT line up against a rebuild of it.

The complement of a per-routine byte check. That kind of check answers "does
each routine I declared match?" and therefore cannot see a routine nobody
declared -- absence has no row to appear in. This walks EVERY byte of the
original's code and reports the spans that will not align, so the measurement
is coverage rather than a sample. See the wiki observation `Every declared
routine matches, and the rebuild still behaves differently`.

Copied and adapted from `tools/asmverify.py` and `tools/shapediff.py` in the
psycho repository, per the map's rule: the originals keep working, untouched.
What changed in the copy is the toolkit's own rule from `kit/tools/README.md` --
**the allowed-difference rule is passed in, never built in**, because baking it
in hides how strict a measurement was. `holes()` is the default rule those two
scripts use; a caller with a `.TPU`'s pending fixups or an `.OBJ`'s relocations
to forgive passes its own.

    from substrate import align          # with kit/tools on sys.path
    for seg, start, end in align.spans(original, ours, segments):
        ...

Two comparison shapes live here, and conflating them is why four compare
tools existed. `walk()` answers "how far do these agree before a difference
that cannot be forgiven?" and its rule is about a RUN. `compare()` answers
"how many bytes of these two equal-length blocks disagree?" and its rule is
about ONE BYTE, sometimes about where that byte is. The four rules the old
tools each hard-coded are `holes`, `zeros`, `relocations` and `window`.

Nothing here needs a disassembler, and nothing here knows anything about
Pascal: a segment list and two images is the whole input.
"""
import struct
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import project                                    # noqa: E402

# How much of the original to pull in when looking for a routine. Long enough
# to hold any hand-written routine in this corpus.
WINDOW = 0x400

# Length of the run used to align the rebuild against the original. It has to
# be long enough to be unique in a 30KB image and short enough to fall between
# two displacements.
ANCHOR = 10

# A believed alignment has to be at least this long. Six-byte routines exist.
MINIMUM = 4

# A run of differing bytes this long is an opcode change, not an address.
OPCODE_CHANGE = 3

# The gate that stops a walk which has wandered into unrelated code and is
# staying alive on one- and two-byte holes. Eight in sixteen is deliberately
# loose: a routine that is mostly memory moves is half displacement bytes by
# nature, and a tighter gate cut a real 64-byte match off at 37.
DENSITY_WINDOW = 16
DENSITY_LIMIT = 8


def holes(run):
    """The default allowed-difference rule: an isolated run of one or two
    differing bytes is an address the rebuild put somewhere else -- two bytes
    for an absolute address, one for a frame-relative local. Three or more is
    an opcode change and ends the comparison.

    A rule is a function of the differing run's length, so a caller can forgive
    more (a fixup, a relocation, a known window) by passing its own.
    """
    return run < OPCODE_CHANGE


def walk(orig, mine, allow=holes):
    """How far two byte strings agree, forgiving what `allow` forgives.

    Returns the number of bytes that lined up. Differences are gathered into
    runs and each run is offered to `allow`; the first run it refuses ends the
    walk, and so does too dense a scatter of forgiven ones.
    """
    n = min(len(orig), len(mine))
    i = matched = 0
    recent = []
    while i < n:
        if orig[i] == mine[i]:
            matched += 1
            recent.append(0)
            i += 1
        else:
            run = 0
            while i + run < n and orig[i + run] != mine[i + run]:
                run += 1
            if not allow(run):
                break
            recent.extend([1] * run)
            i += run
            matched += run
        if len(recent) > DENSITY_WINDOW:
            recent = recent[-DENSITY_WINDOW:]
        if sum(recent) > DENSITY_LIMIT:
            break
    return matched


def locate(orig, image, allow=holes):
    """Where `orig` sits in `image` -- BEST fit, not first.

    Anchoring on the first unique run is not good enough: a run from the middle
    of a routine can also occur inside an unrelated one, and the alignment it
    suggests then scores zero and looks like a transcription defect. So every
    alignment suggested by any anchor-length run near the start is scored by how
    far the comparison actually gets, and the winner is kept.

    Returns (offset, bytes that lined up), or (-1, 0).
    """
    best = (-1, 0)
    tried = set()
    for d in range(0, max(1, min(len(orig) - ANCHOR, 0x60))):
        probe = orig[d:d + ANCHOR]
        if len(probe) < ANCHOR:
            break
        at = image.find(probe)
        while at >= 0:
            start = at - d
            if start >= 0 and start not in tried:
                tried.add(start)
                got = walk(orig, image[start:start + len(orig)], allow)
                if got > best[1]:
                    best = (start, got)
            at = image.find(probe, at + 1)
        if len(tried) > 64:
            break
    return best if best[1] >= MINIMUM else (-1, 0)


# ---------------------------------------------------------------------------
# THE ALLOWED-DIFFERENCE RULES, one per artefact, all passed in rather than
# built in. Issue #9's finding was that four compare tools differed ONLY in
# this, so here they are, side by side, where the difference is readable.


def zeros(offset, want, got):
    """A .TPU's pending fixup: OUR side is zero where the original has a value.

    Turbo Pascal leaves an unresolved reference as zeros plus a fixup record,
    so a zero on our side is the linker's job, not a defect. Note what that
    covers: an INTRA-UNIT NEAR CALL is one of them, so a call inside the unit
    agreeing is not evidence that its target sits in the right place.
    """
    return got == 0


def relocations(fixups):
    """An assembled .OBJ: exactly the bytes the module's own FIXUPP records
    name, and no others.

    TASM does not leave an unresolved reference as zeros the way Turbo Pascal
    does -- it writes the offset RELATIVE TO THE MODULE and lets the linker add
    the base -- so every self-reference differs by the segment base in bytes
    that are NOT zero. Forgiving them by value would forgive real defects; the
    .OBJ says exactly which offsets are relocated, so that is the rule.
    """
    fixups = set(fixups)
    return lambda offset, want, got: offset in fixups


def window(lo, hi):
    """A linked image: a difference is forgiven when OUR byte could be the low
    or high half of an address inside a known DGROUP range.

    The loosest of the four, and the reason it is named: the caller states the
    range, so a reader of the call site can see how much was excused.
    """
    return lambda offset, want, got: lo <= got <= hi


def compare(want, got, forgive=None):
    """Positional difference count between two equal-length blocks.

    Returns (real, forgiven). `forgive(offset, want_byte, got_byte)` decides;
    with no rule, every difference is real.
    """
    real = excused = 0
    for i, (a, b) in enumerate(zip(want, got)):
        if a == b:
            continue
        if forgive is not None and forgive(i, a, b):
            excused += 1
        else:
            real += 1
    return real, excused


def best_shift(want, image, nominal, span, forgive=None):
    """Where a block really sits, and how well it agrees there.

    A block inside a half-written unit is displaced by the ACCUMULATED
    shortfall of every placeholder above it, so the shift is searched for and
    never assumed -- a single global shift once reported 73 mismatches where
    there were none. The window is clamped at BOTH ends, because a block's
    nominal offset can fall past the end of an unfinished image entirely, and
    an unclamped range then searches nothing.

    Returns (real, forgiven, drift, position), lowest real first -- so the
    result is the alignment that the rule says is best, not the nearest one.
    """
    hi = min(len(image) - len(want), nominal + span)
    lo = max(0, min(nominal - span, hi))
    best = None
    for pos in range(lo, hi + 1):
        real, excused = compare(want, image[pos:pos + len(want)], forgive)
        cand = (real, excused, abs(pos - nominal), pos)
        if best is None or cand < best:
            best = cand
    return best


def load_image(blob):
    """(image bytes, header size) for an MZ file, from its own header."""
    hdr = struct.unpack_from("<H", blob, 8)[0] * 16
    return blob[hdr:], hdr


def spans(orig_blob, our_blob, segments, first_para=None, min_span=16,
          allow=holes):
    """The stretches of the original's code that will not align at all.

    `segments` is the ascending list of code segment paragraphs, with ONE extra
    entry at the end bounding the last one -- usually the first library segment.
    Each is taken relative to `first_para`, the paragraph the disassembly calls
    the start of the image -- which comes from the project's answers when the
    caller does not say, because it is a fact about the target and not about
    this code.

    Yields (segment, start, end) offsets within each segment, and returns the
    (aligned, total) byte counts through StopIteration's value.
    """
    if first_para is None:
        # Which paragraph the disassembly calls the start of the image is a
        # fact about the TARGET, read out of it once, so it comes from the
        # project rather than from a default baked in here.
        first_para = project.get("target.first_para", quiet=True)
    orig, _ = load_image(orig_blob)
    ours, _ = load_image(our_blob)
    total = aligned = 0
    for k, seg in enumerate(segments[:-1]):
        base = (seg - first_para) * 16
        size = (segments[k + 1] - seg) * 16
        data = orig[base:base + size]
        total += size
        pos = 0
        gap = None
        while pos < len(data):
            chunk = data[pos:pos + WINDOW]
            if len(chunk) < ANCHOR:
                break
            _, got = locate(chunk, ours, allow)
            if got >= MINIMUM:
                if gap is not None:
                    if pos - gap >= min_span:
                        yield (seg, gap, pos)
                    gap = None
                aligned += got
                pos += got
            else:
                if gap is None:
                    gap = pos
                pos += 1
        if gap is not None and len(data) - gap >= min_span:
            yield (seg, gap, len(data))
    return aligned, total
