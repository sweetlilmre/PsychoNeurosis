"""One reader for the routine markers in a Pascal tree.

A marker is a comment a tool reads, naming the address in the original binary
that a routine's bytes must match:

    { @asm 003 11f3:0105 }
    { @asm 001 1107:0199 +170 Blit }
    { @asm 006 100f:0000 ? }

    part          which original binary the routine was read out of
    seg:off       where it starts in that binary
    +n            optional -- compare exactly n bytes and do not go looking for
                  a return. Two things need it: assembler INLINE inside a
                  compiled routine, where there is no routine to walk to the
                  end of, and any routine whose extent is known from a function
                  table. The walk otherwise stops at the first byte that LOOKS
                  like a return, and in 1,254 bytes of scan converter a C2
                  preceded by a C9 turns up long before the real one.
    name          optional -- and REQUIRED when the marker does not sit
                  immediately above a procedure header, which is the case when
                  the routine lives in a shared {$I} include.
    ?             optional -- the address is NOT confirmed. Marked routines are
                  reported separately and never fail a run, so a guess is never
                  mistaken for a verified transcription.

WHY THIS FILE EXISTS. Three programs in the kit read these markers and each had
its own regex and its own idea of how to find the routine a marker refers to.
That is the same duplication the kit exists to remove, and it had already
diverged: one of the three looked for the first `asm` block after the header a
marker named, which in a unit whose markers sit above INTERFACE declarations
handed nine routines the same body -- and the check that used it happily
reported all nine as identical.

So: one regex, one rule for pairing a marker with its routine, and one place to
fix when the convention grows.
"""
import io
import pathlib
import re

# The marker need not be alone on its line or open the comment: a routine that
# needs a paragraph of explanation puts the @asm last, inside it.
MARKER = re.compile(
    r"@asm\s+(?P<part>\d{3})\s+(?P<seg>[0-9a-fA-F]{4}):(?P<off>[0-9a-fA-F]{4})"
    r"(?:\s*\+(?P<span>\d+))?(?:\s+(?P<name>\w+))?\s*(?P<unsure>\?)?\s*\}")
HEADER = re.compile(r"\s*(?:procedure|function)\s+(\w+)")
INCLUDE = re.compile(r"\{\$I\s+([A-Za-z0-9_./]+)\s*\}")

# How far below a marker to look for the routine it names. A marker sits
# immediately above its header by convention; more than a few lines means the
# convention was not followed and the marker should name the routine itself.
REACH = 6


class Marker(object):
    """One declared routine. `unit` is the file's stem, so a key reads
    `P1S4.Blit` -- which is what the register locks against."""

    def __init__(self, name, path, part, seg, off, span, unsure, line,
                 shared):
        self.name = name
        self.path = path
        self.unit = pathlib.Path(path).stem
        self.part = part
        self.seg = seg
        self.off = off
        self.span = span
        self.unsure = unsure
        self.line = line
        self.shared = shared

    @property
    def key(self):
        return "%s.%s" % (self.unit, self.name)

    @property
    def where(self):
        return "%04x:%04x" % (self.seg, self.off)

    def __repr__(self):
        return "<%s %s %s%s>" % (self.key, self.part, self.where,
                                 " +%d" % self.span if self.span else "")


def read(src, pattern="*.PAS"):
    """Every marker in a tree, in source order.

    A marker's routine name comes from its own `name` field when it has one --
    which is how a routine in a shared include is named -- and otherwise from
    the procedure header below it. A marker with neither is reported by
    `problems()` rather than silently skipped.
    """
    out, bad = [], []
    for path in sorted(pathlib.Path(src).glob(pattern)):
        lines = io.open(path, encoding="ascii", newline="").read().split("\n")
        for i, line in enumerate(lines):
            m = MARKER.search(line)
            if not m:
                continue
            name = m.group("name")
            shared = False
            for j in range(i + 1, min(i + REACH, len(lines))):
                if INCLUDE.search(lines[j]):
                    shared = True
                    break
                h = HEADER.match(lines[j])
                if h:
                    name = name or h.group(1)
                    break
            if name is None:
                bad.append((path.name, i + 1,
                            "a marker with no procedure under it and no name "
                            "of its own"))
                continue
            out.append(Marker(
                name=name, path=str(path), part=m.group("part"),
                seg=int(m.group("seg"), 16), off=int(m.group("off"), 16),
                span=int(m.group("span")) if m.group("span") else 0,
                unsure=bool(m.group("unsure")), line=i + 1, shared=shared))
    return out, bad


def bodies(src, pattern="*.PAS"):
    """key -> the routine's assembler, for markers whose body is written out in
    the unit rather than pulled in from a shared include.

    The body is found from the header that OPENS one -- nothing but a var or
    const block may stand between a header and its `asm` -- and not from the
    first `asm` after the marker. A marker may sit above an INTERFACE
    declaration, a long way from the body, with other declarations in between.
    """
    out = {}
    for path in sorted(pathlib.Path(src).glob(pattern)):
        lines = io.open(path, encoding="ascii", newline="").read().split("\n")
        impl = {}
        for j, line in enumerate(lines):
            h = HEADER.match(line)
            if not h:
                continue
            k = j + 1
            while k < len(lines) and not HEADER.match(lines[k]):
                if lines[k] == "asm":
                    break
                k += 1
            if k >= len(lines) or lines[k] != "asm":
                continue
            try:
                end = next(x for x in range(k, len(lines))
                           if lines[x] == "end;")
            except StopIteration:
                continue
            impl.setdefault(h.group(1), lines[k + 1:end])
        for mk in [m for m in read(src, pattern)[0]
                   if m.path == str(path) and not m.shared]:
            if mk.name in impl:
                out[mk.key] = impl[mk.name]
    return out
