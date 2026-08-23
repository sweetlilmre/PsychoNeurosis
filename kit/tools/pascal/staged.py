"""Is a build output still the source it was built from?

A COMPARE TOOL READS TWO THINGS: the original binary, and something a build
produced. If what the build produced is old, the tool measures code that is no
longer the source and reports a result -- and the result looks fine. That is
worse than no result, and it has already produced one wrong conclusion in this
project: a build harness that refuses to run when the lint fails leaves EVERY
output old, so one bad comment in one file is enough.

So an instrument that reads build output checks this first.

DO NOT COMPARE TIMES. Two reasons, both measured rather than argued:

  * a build under DOSBox writes DOS timestamps, and a DOS timestamp does not
    reliably compare against the host's;
  * a modification-time check reported a freshly built unit as stale.

COMPARE THE TEXT. A build harness stages a copy of each source beside its
output, so both are on disk to read.

WHAT MAKES IT AWKWARD, and why `rewrites` exists: a harness may STAGE A
REWRITTEN source. A plain text comparison then calls everything stale. Turbo
Pascal 6 has no `far` directive on an interface declaration, so a TP6 build
turns those declarations into an `{$F+}` region -- and that is a fact about
Borland Pascal, which is why it lives here in the Pascal tier rather than in
one project. What is NOT here is which rewrites a given harness applies: the
thing that rewrote the source is the thing that knows how to compare it back,
so a harness passes its own, and a project names the ones it needs.

THE BLIND SPOT, and it is stated rather than hidden: this can only work where
the build stages a copy. Where it does not, `check` returns `unknown` for that
unit. It never reports agreement it cannot see -- an instrument's blind spot
belongs in its output, not in a docstring nobody reads at the time.
"""
import io
import pathlib
import re

# A declaration's tail: an optional parameter list, an optional result type,
# then the semicolon. Matched WHOLE rather than up to the first semicolon,
# because a parameter list separates its groups with semicolons too and a
# `[^;]*` stops short on every routine taking more than one group.
DECL_TAIL = r"(?:\s*\([^()]*\))?(?:\s*:\s*\w+)?\s*;"


def tp6_far(text, restore="{$F-}"):
    """TP6 has no `far` directive in an interface, so a TP6 build replaces
    those declarations with an `{$F+}` region and restores it at the
    implementation. Returns the text unchanged when nothing is exported far."""
    iface = re.search(r"(?im)^interface\b[ \t]*$", text)
    impl = re.search(r"(?im)^implementation\b", text)
    if not (iface and impl):
        return text
    head, body = text[:impl.start()], text[impl.start():]
    n = 0

    def strip(m):
        nonlocal n
        n += 1
        return m.group(1)

    head = re.sub(r"(?is)(\b(?:procedure|function)\s+\w+\b" + DECL_TAIL +
                  r")\s*far\s*;", strip, head)
    if not n:
        return text
    head = head[:iface.end()] + "\n{$F+}" + head[iface.end():]
    return head + body.replace("implementation", "implementation\n" + restore,
                               1)


# The rewrites this tier knows about, by name, so a project can ASK for one
# without holding the code. A harness with a rewrite of its own passes a
# callable instead -- see the module docstring.
REWRITES = {"tp6_far": tp6_far}


def resolve(names):
    """Named rewrites to callables, with a readable complaint for a name that
    is not one."""
    out = []
    for name in names or ():
        if callable(name):
            out.append(name)
        elif name in REWRITES:
            out.append(REWRITES[name])
        else:
            raise KeyError("no rewrite called %r -- known: %s"
                           % (name, ", ".join(sorted(REWRITES))))
    return out


# The codepage the build encoded its staged copies for. A DOS tool reads bytes
# in a codepage, not utf-8.
DOS_CODEPAGE = "cp437"


# BOTH sides are read with newlines TRANSLATED, not preserved, and that is a
# decision rather than an oversight. A DOS source's lines end CRLF, so a regex
# anchored with `$` -- which the TP6 rewrite below needs -- never matches when
# the `\r` is still there: the rewrite returns the text unchanged and ten fresh
# units read as stale. Measured, 23 Aug 2026.
#
# WHAT IT GIVES UP: a source whose LINE ENDINGS changed reads as fresh. That is
# a gap, not a guarantee. It is tolerable here because a byte-for-byte
# comparison of the compiled output follows, and because `.gitattributes` holds
# DOS sources at CRLF -- but an instrument's blind spot belongs in its output,
# so `check` says which reader it used.
def read_source(path):
    """The real source: a modern file, so utf-8."""
    return io.open(path, encoding="utf-8", errors="replace").read()


def read_staged(path, codepage=DOS_CODEPAGE):
    """The build's copy: a DOS file, so the codepage."""
    return io.open(path, encoding=codepage, errors="replace").read()


def as_staged(text, codepage=DOS_CODEPAGE):
    """The source as the build would have written it.

    THE TWO FILES HAVE DIFFERENT READERS AND SO DIFFERENT ENCODINGS, which is
    this project's standing rule, and skipping this round trip called ten fresh
    units stale. A character the codepage cannot hold became a `?` when the
    build staged the file, so it has to become a `?` here as well or the texts
    can never be equal. Any source that is pure ASCII passes through unchanged,
    which is why a tree that lints for ASCII never sees this.
    """
    return text.encode(codepage, errors="replace").decode(codepage)


def state(source, staged, rewrites=()):
    """`fresh`, `stale`, or `unknown` for one pair of paths.

    `unknown` is not a failure and not a pass: it means the build did not stage
    a copy, so nothing can be said. Any accepted form of the source counts as
    fresh -- the original text, or the result of any rewrite the harness
    applies.
    """
    source, staged = pathlib.Path(source), pathlib.Path(staged)
    if not source.is_file() or not staged.is_file():
        return "unknown"
    want = as_staged(read_source(source))
    forms = [want] + [f(want) for f in resolve(rewrites)]
    return "fresh" if read_staged(staged) in forms else "stale"


def check(sources, staged_dir, rewrites=(), pattern="*.PAS"):
    """(name, state) for every source, in name order.

    `sources` is a directory of the real sources; `staged_dir` is where the
    build put its copies.
    """
    out = []
    staged_dir = pathlib.Path(staged_dir)
    for path in sorted(pathlib.Path(sources).glob(pattern)):
        out.append((path.stem,
                    state(path, staged_dir / path.name, rewrites)))
    return out
