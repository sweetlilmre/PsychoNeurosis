"""Read every routine marker in a Pascal tree, and account for all of them.

This is the repaired successor to `tools/ledger.py`, which stays frozen where
it is. Nothing here is a refactor of it: the CONVENTION it reads was always
sound, and only its reader was broken.

WHAT WAS WRONG. `ledger.py` matches with a DOTALL regex whose `(.*?)` crosses
`{ }` boundaries, so it captures across comments. Consequences, both measured:
three of its eighteen rows are not routines at all -- they matched the legend
comment in a file header that DEFINES the markers -- and one row carries an
address belonging to a different routine. Meanwhile nine marker-shaped strings
that do exist in the source are never seen. It then prints "94%", which is 17
of its own 18 rows rather than of the 317 routines in the tree.

THE FIX IS NOT A BETTER REGEX. Issue #15 settled the mechanism for this class
of defect -- a measurement artefact read as a finding -- and it is: stop
counting, and classify every field until none is unexplained. That is what the
`.OBJ` fixup work did (192 word fields, 0 unexplained) and it is what this tool
does. Every marker-shaped string lands in exactly one named category, and an
unexplained one fails the run. A legend is classified AS a legend, out loud,
rather than silently becoming a row or silently vanishing.

The four shapes that actually exist, which is why one regex could never do it:

    legend       "Markers: [transcribed] read out of the binary, [inferred]
                 implied by its call sites, [stub] signature only."
    routine      "{ [transcribed] 1012:0366 -- gather the working cell ... }"
    multi        "{ [transcribed] Vector_Run's object copy, 12c5:088b and
                 12c5:098a -- integer ... }"
    no-address   "{ [transcribed] Mosaic block sampling. }"

THREE AXES, NEVER CONFLATED (issue #7):

    provenance   how the code came to exist. Hand-written. NEVER a rung: a
                 [transcribed] routine read off a mis-decoded instruction
                 stream still carries the top label.
    target       where its bytes should match. Hand-written, from `@asm`.
    achieved     what a tool measured. COMPUTED, never asserted by a person,
                 so it is read from a status file and never from a comment.

Encoding, per CLAUDE.md: DOS sources are ASCII and are read as ASCII, which is
a guard rather than a preference -- a non-ASCII byte in a .PAS file is a defect
`paslint.py` exists to catch, and decoding it silently here would hide it.

    python toolkit/pascal/markers.py src
    python toolkit/pascal/markers.py src --status status.toml
"""
import io
import pathlib
import re
import sys

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover -- 3.11+ per pyproject.toml
    tomllib = None

PROVENANCE = ("transcribed", "inferred", "stub")
ADDR = re.compile(r"\b([0-9a-fA-F]{4}):([0-9a-fA-F]{4})\b")
# An unregistered marker word: a bracketed lowercase word AT THE START of its
# comment. The anchor is what makes this sound rather than a guess -- by
# convention a marker is the first thing in its comment, so `Stars[star]` and
# `[frame]` sitting inside prose can never match. Without the anchor this
# fired on five ordinary words in the real tree (frame, offset, star, step,
# column), which under issue #15 would have demoted the whole check from a
# gate to a report. Four letters is a second floor, excluding [si] and [bx].
#
# The trailing \s matters as much as the anchor, and the case that forced it is
# `{ [frame][col][row] -- strides $90, $12 }` -- an array-index expression
# describing a data layout, sitting at the start of its comment and looking
# exactly like a marker. A real marker is ONE bracket followed by a space;
# that one is three brackets run together. The distinction is exact.
BRACKETED = re.compile(r"^\s*\[([a-z]{4,})\]\s")
TARGET = re.compile(
    r"@asm\s+(?P<part>\d{3})\s+(?P<addr>[0-9a-fA-F]{4}:[0-9a-fA-F]{4})"
    r"(?:\s+\+(?P<length>\d+)\s+(?P<name>\S+))?")


def comments(text):
    """Yield (line_number, comment_text) for every Pascal comment.

    A character walk, not a regex. Pascal brace comments do not nest -- which
    `paslint.py` separately enforces -- so a scan for the matching close is
    exact. String literals are skipped so a brace inside one cannot open a
    comment. This is the whole difference between this tool and the one it
    replaces.
    """
    i, line, n = 0, 1, len(text)
    while i < n:
        ch = text[i]
        if ch == "\n":
            line += 1
            i += 1
        elif ch == "'":                      # string literal: skip it whole
            i += 1
            while i < n and text[i] != "'":
                if text[i] == "\n":
                    line += 1
                i += 1
            i += 1
        elif ch == "{":
            start, first = i + 1, line
            while i < n and text[i] != "}":
                if text[i] == "\n":
                    line += 1
                i += 1
            yield first, text[start:i]
            i += 1
        elif ch == "(" and i + 1 < n and text[i + 1] == "*":
            start, first = i + 2, line
            end = text.find("*)", start)
            end = n if end < 0 else end
            line += text.count("\n", start, end)
            yield first, text[start:end]
            i = end + 2
        else:
            i += 1


def classify(comment):
    """Return (category, keyword, addresses) for one marker-shaped comment.

    An UNEXPLAINED category is the point of this function, not an afterthought.
    A bracketed word nobody registered -- `[partial]`, `[guessed]` -- is
    exactly what disappears silently under a tool that looks only for the three
    words it knows. Under issue #15's rule for this defect class, a marker that
    cannot be classified must fail the run rather than be skipped.
    """
    found = [k for k in PROVENANCE if "[" + k + "]" in comment]
    if not found:
        unknown = [w for w in BRACKETED.findall(comment) if w not in PROVENANCE]
        if unknown:
            return ("unexplained", "/".join(sorted(set(unknown))),
                    [m.group(0).lower() for m in ADDR.finditer(comment)])
        return None
    addrs = [m.group(0).lower() for m in ADDR.finditer(comment)]
    if len(found) > 1:
        # The comment names more than one marker word, so it is defining the
        # vocabulary rather than using it. This is the exact string that put
        # three phantom rows in the old ledger.
        return ("legend", "/".join(found), addrs)
    if len(addrs) == 0:
        return ("no-address", found[0], addrs)
    if len(addrs) == 1:
        return ("routine", found[0], addrs)
    return ("multi", found[0], addrs)


def scan(root):
    prov, targets, bare = [], [], 0
    for path in sorted(pathlib.Path(root).rglob("*")):
        if path.suffix.upper() not in (".PAS", ".INC", ".ASM") or not path.is_file():
            continue
        # ascii is a GUARD: it raises rather than quietly accepting a byte a
        # 1990s DOS tool would not have written.
        text = io.open(path, encoding="ascii", newline="").read()
        rel = path.relative_to(root).as_posix()
        bare += len(ADDR.findall(text))
        for line, body in comments(text):
            got = classify(body)
            if got:
                prov.append((rel, line, got[0], got[1], got[2]))
            for m in TARGET.finditer(body):
                targets.append((rel, line, m.group("part"),
                                m.group("addr").lower(),
                                m.group("length"), m.group("name")))
    return prov, targets, bare


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    root = args[0] if args else "src"
    status = {}
    if "--status" in argv:
        path = argv[argv.index("--status") + 1]
        if tomllib is None:
            sys.stdout.write("  tomllib unavailable; need Python 3.11+\n")
            return 2
        with io.open(path, "rb") as fh:
            status = tomllib.load(fh)

    prov, targets, bare = scan(root)

    counts = {}
    for _, _, category, keyword, _ in prov:
        counts[(category, keyword)] = counts.get((category, keyword), 0) + 1

    sys.stdout.write("PROVENANCE -- how the code came to exist. Never a rung.\n")
    for (category, keyword), n in sorted(counts.items()):
        sys.stdout.write("  %-11s %-22s %4d\n" % (category, keyword, n))
    unexplained = sum(n for (category, _), n in counts.items()
                      if category == "unexplained")
    sys.stdout.write("  %d marker(s) found, %d classified, %d unexplained\n"
                     % (len(prov), len(prov) - unexplained, unexplained))

    frag = [t for t in targets if t[4]]
    sys.stdout.write("\nTARGET -- where the bytes should match. Hand-declared.\n")
    sys.stdout.write("  %d whole-routine, %d fragment, %d total\n"
                     % (len(targets) - len(frag), len(frag), len(targets)))

    sys.stdout.write("\nACHIEVED -- what a tool measured. Never asserted by a person.\n")
    if not status:
        sys.stdout.write("  no status file given, so nothing is claimed. "
                         "This is rung R0 for every routine, stated rather than implied.\n")
    else:
        rows = status.get("routine", {})
        sys.stdout.write("  %d routine(s) with a measured rung\n" % len(rows))
        missing = [t[3] for t in targets if t[3] not in rows]
        sys.stdout.write("  %d target(s) with no measurement yet\n" % len(missing))

    sys.stdout.write("\nCOVERAGE, reported and not gated (issue #15)\n")
    sys.stdout.write("  %d bare seg:off address(es) in the tree; %d carry a target.\n"
                     % (bare, len(targets)))
    sys.stdout.write("  An address in a comment is NOT a claim that bytes match, so "
                     "the rest are candidates, not debt.\n")

    if unexplained:
        sys.stdout.write("\n%d marker(s) unexplained -- refusing.\n" % unexplained)
    return 1 if unexplained else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
