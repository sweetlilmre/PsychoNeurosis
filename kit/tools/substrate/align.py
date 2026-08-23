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


# A walk's rule is called with the run's LENGTH, both byte strings and the
# offset the run starts at -- so it can look at the bytes when it needs to and
# ignore them when it does not -- and it returns HOW MANY bytes it forgives.
# Zero stops the walk. A count short of the run forgives that much and then
# stops, which is the only honest reading of a mixed run.
def holes(run, orig=None, mine=None, at=0):
    """The default allowed-difference rule: an isolated run of one or two
    differing bytes is an address the rebuild put somewhere else -- two bytes
    for an absolute address, one for a frame-relative local. Three or more is
    an opcode change and ends the comparison.

    Returns how many bytes it forgives, which for this rule is all of them or
    none: an address is a whole operand.
    """
    return run if run < OPCODE_CHANGE else 0


# The longest thing a linker fixup can zero out is a far pointer: four bytes.
MAX_FIXUP = 4


def pending(run, orig=None, mine=None, at=0):
    """A .TPU's unresolved references, as a WALK rule rather than a per-byte
    one -- and capped.

    Turbo Pascal leaves an unresolved reference as zeros plus a fixup record,
    so a short run of zeros on our side is the linker's job. A LONG run is not:
    anything past four bytes is a region the compiler did not fill because the
    code is simply different, or padding past the end of the unit. Without the
    cap a long run of zeros swallows the real divergence and the unit reports
    far better agreement than it has -- which is why the tool this came from
    caps it, and why `zeros` (the per-byte form, for `compare`) is not the same
    rule and must not be substituted for it.
    """
    if mine is None:
        return 0
    # Count the LEADING zeros only. A run is not necessarily homogeneous:
    # `00 00 3C` is two pending fixups and then a real difference, and
    # forgiving the pair while stopping at the 3C is the only honest reading.
    # Answering yes-or-no about the whole run costs two bytes of prefix on one
    # unit in this corpus and would cost more on another.
    n = 0
    while n < run and mine[at + n] == 0:
        n += 1
    return n if n <= MAX_FIXUP else 0


def walk(orig, mine, allow=holes, stop=None, density=True):
    """How far two byte strings agree, forgiving what `allow` forgives.

    Differences are gathered into runs and each run is offered to `allow`,
    which returns HOW MANY of its bytes it forgives. Zero ends the walk; fewer
    than the whole run forgives that many and then ends it, which is what a
    mixed run like `00 00 3C` needs -- two pending fixups and then a real
    difference. Too dense a scatter of forgiven bytes ends it too, unless the
    caller turns that gate off.

    `stop(orig, mine, i)` optionally recognises a TERMINATOR at an agreed
    position, returning `(size, definite)` or None. A definite terminator ends
    the walk there; a provisional one is remembered, and if the walk runs out
    without a definite one the last provisional is used instead. That is the
    shape a routine-end rule needs, with none of the rule itself: what counts
    as a return is the caller's fact, not this module's.

    `density` is the gate that stops a walk staying alive on forgiven bytes
    alone -- and it belongs to the ARTEFACT, so it can be turned off. For a
    routine inside an executable it is essential: a scatter of holes that dense
    means the alignment wandered into unrelated code. For a unit's code inside a
    .TPU it is simply wrong, because dense pending fixups are normal there --
    one unit in this corpus has 569 -- and the gate silently shortens every
    measurement. Measured: with it on, fourteen of twenty-six units reported a
    prefix shorter than the truth, one of them 38 bytes instead of 1,617, while
    the offset was right every time.

    Returns (length, holes, ended_on_terminator). `holes` is the offset of each
    forgiven run, which is what a caller reports as "5 holes" -- the bytes the
    rule excused, so a reader can see how much was excused and where.
    """
    n = min(len(orig), len(mine))
    i = 0
    holes_at = []
    recent = []
    fallback = None
    while i < n:
        if orig[i] == mine[i]:
            if stop is not None:
                found = stop(orig, mine, i)
                if found:
                    size, definite = found
                    if definite:
                        return i + size, holes_at, True
                    fallback = (i + size, list(holes_at))
            recent.append(0)
            i += 1
        else:
            run = 0
            while i + run < n and orig[i + run] != mine[i + run]:
                run += 1
            forgiven = allow(run, orig, mine, i)
            if not forgiven:
                break
            holes_at.append(i)
            recent.extend([1] * forgiven)
            i += forgiven
            if forgiven < run:
                break            # the rule forgave a prefix of the run only
        if density:
            if len(recent) > DENSITY_WINDOW:
                recent = recent[-DENSITY_WINDOW:]
            if sum(recent) > DENSITY_LIMIT:
                break
    if fallback is not None:
        end, hs = fallback
        return end, [h for h in hs if h < end], True
    return i, holes_at, stop is None and i >= n


def locate(orig, image, allow=holes, stop=None):
    """Where `orig` sits in `image` -- BEST fit, not first.

    Anchoring on the first unique run is not good enough: a run from the middle
    of a routine can also occur inside an unrelated one, and the alignment it
    suggests then scores zero and looks like a transcription defect. So every
    alignment suggested by any anchor-length run near the start is scored by how
    far the comparison actually gets, and the winner is kept.

    `stop` is the walk's terminator and is passed through, because the search
    and the comparison have to agree: scoring by a rule the caller will not
    then use picks an alignment whose reported length means something else.

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
                got, _, ended = walk(orig, image[start:start + len(orig)],
                                     allow, stop)
                # Score by how far the comparison gets, and -- when there is a
                # terminator -- only believe an alignment that reached one. An
                # alignment that dribbles out mid-routine scores zero, because
                # a run from the middle of one routine can occur inside an
                # unrelated one and the length it reports there means nothing.
                got = got if (ended or stop is None) else 0
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
#
# They come in the two shapes the two comparisons need: a WALK rule sees a
# run -- `holes`, `pending` -- and a COMPARE rule sees one byte -- `zeros`,
# `relocations`, `window`. `pending` and `zeros` both forgive a zero on our
# side and are NOT interchangeable: only the walk form can cap the run, and
# the cap is what stops a field of zeros reading as agreement.


def zeros(offset, want, got, a=None, b=None):
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
    return lambda offset, want, got, a=None, b=None: offset in fixups


def window(lo, hi):
    """A linked image: a difference is forgiven when OUR byte could be the low
    or high half of an address inside a known DGROUP range.

    The loosest of the four, and the reason it is named: the caller states the
    range, so a reader of the call site can see how much was excused.
    """
    return lambda offset, want, got, a=None, b=None: lo <= got <= hi


def linked(varbase, delta=None, top=0x10000):
    """A LINKED image's two known fixup classes, and nothing else.

    Both need context a single byte does not carry, which is why a positional
    rule is handed the buffers:

      * **a segment word a fixed number of paragraphs off.** Our image loads its
        segments at slightly different paragraphs than the original's, so a
        segment-valued byte differs by exactly that delta everywhere. A fixed
        delta is safe to forgive; a variable one would forgive real differences.
      * **a DGROUP VARIABLE offset**, judged on the WORD at `offset - 1` being at
        or above `varbase` on BOTH sides. Below `varbase` is the initialised
        half, which is measured exactly elsewhere, so a difference there is a
        regression and is NOT forgiven here.

    `delta` of None forgives no segment words.
    """
    def rule(offset, want, got, a=None, b=None):
        if delta is not None and want - got == delta:
            return True
        if a is None or b is None or offset < 1 or offset + 1 >= min(len(a),
                                                                    len(b)):
            return False
        wa = a[offset - 1] | (a[offset] << 8)
        wb = b[offset - 1] | (b[offset] << 8)
        return varbase <= wa < top and varbase <= wb < top
    return rule


def compare(want, got, forgive=None):
    """Positional difference count between two equal-length blocks.

    Returns (real, forgiven). `forgive(offset, want_byte, got_byte, want, got)`
    decides -- the buffers come last because most rules ignore them, and the
    linked-image rule cannot: it forgives a byte because of the word it belongs
    to. With no rule, every difference is real.
    """
    real = excused = 0
    for i, (a, b) in enumerate(zip(want, got)):
        if a == b:
            continue
        if forgive is not None and forgive(i, a, b, want, got):
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


# How much of a segment has to be present at a candidate position for it to be
# worth considering. Enough that a run of coincidence cannot win, small enough
# that a partially transcribed unit is still measurable.
MIN_OVERLAP = 64


def anchor_first(orig, image, allow=holes, stop=None, min_overlap=None,
                 density=False):
    """Where `orig` starts in `image`, anchored on its FIRST BYTE.

    The other strategy in this module -- `locate` -- anchors on a unique run and
    scores by how far the walk gets, which is right for finding a routine inside
    a whole executable. This one is for finding the head of something whose
    START is known to be the start: a unit's code at the top of a .TPU.

    Candidates are positions whose first byte matches exactly. That single
    constraint is what keeps the search out of a .TPU's symbol table and off its
    runs of zeros, both of which have scored well enough to be chosen before --
    one of them reporting a match sitting in the middle of a string.

    The winner is the candidate whose forgiving prefix reaches FURTHEST, which
    is alignment-independent and makes the reported divergence the real one.

    A PARTIAL UNIT COMPILES MUCH SHORTER THAN ITS SEGMENT, so requiring the
    whole segment to fit from the candidate onwards rejects every candidate and
    reports "not located" for a unit whose opening is perfect. Requiring
    `min(MIN_OVERLAP, len(orig))` instead is load-bearing in BOTH halves:
    without the cap a partial unit has no valid candidate at all; without the
    `len(orig)` floor a segment SHORTER than the overlap gets a harder test than
    before, which once took a 29-byte unit from 93% to not-located.

    Returns (offset, prefix length), or (-1, 0).
    """
    need = min(MIN_OVERLAP if min_overlap is None else min_overlap, len(orig))
    best, at = 0, -1
    i = image.find(orig[:1])
    while i >= 0:
        if len(image) - i >= need:
            # Compare only what is actually there: the whole segment for a
            # complete unit, however much has been written for a partial one.
            head = orig[:min(len(orig), len(image) - i)]
            got, _, _ = walk(head, image[i:i + len(head)], allow, stop,
                             density)
            if got > best:
                best, at = got, i
        i = image.find(orig[:1], i + 1)
    # Too short to be the thing: its first instruction differs, so there is
    # nothing to align against and no offset worth reporting.
    return (at, best) if best >= MINIMUM else (-1, 0)


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
