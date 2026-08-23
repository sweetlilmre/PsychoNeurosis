"""Turn the glossary's `_Avoid_` lists into a check, because writing a term
down has twice failed to stop the wrong one being used.

WHY THIS EXISTS. The user halted two grillings in a row over undefined and
inconsistent vocabulary. A glossary was written after the first halt and did
not prevent the second, because the offending words were freshly invented.
That is the corpus's own finding arriving in the process rather than the code:
a lesson recorded only in prose does not prevent its next instance. So the
glossary gets a mechanism.

WHAT IT CHECKS, and the split matters -- see issue #15:

  GATE (fails, exit 1)   A page uses a MULTI-WORD term from an `_Avoid_` list.
                         "excuse rule", "maturity model", "evidence class" are
                         unambiguous: nobody writes them by accident, and each
                         has an agreed replacement. This check is SOUND, so it
                         is allowed to fail the build.

  REPORT (exit 0)        A page uses a SINGLE-WORD avoid term. Those lists hold
                         common English -- tool, test, index, manual -- which
                         appear in ordinary prose constantly. A gate here would
                         cry wolf, and #15 settled that a heuristic may only
                         report. So it prints a count and passes.

OVERRIDE. A page may carry `glossary_allow` in its frontmatter, listing terms
it is permitted to use, with the reason in prose nearby. #15's rule is that an
overridable gate beats a warning, because a warning gets ignored -- but it must
never pass silently, so every override is printed.

Encoding, per CLAUDE.md: utf-8 explicitly. The locale here is cp1252.

    python kit/tools/wikitools/glossary.py kit/wiki CONTEXT.md
"""
import io
import pathlib
import re
import sys

import yaml

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import project                                    # noqa: E402

RESERVED = ("log.md",)


def parse_glossary(paths):
    """Return {avoid_term: canonical_term} from every `_Avoid_:` line.

    A word that is ITSELF a defined term is never an avoid-word, even when it
    appears on another term's list. "section" is on Scene's list and is also a
    term in its own right; "tier" is on Rung's list and is a term. Flagging
    their legitimate use is noise, and noise is how a check gets ignored.
    """
    avoid = {}
    defined = set()
    for path in paths:
        text = io.open(path, encoding="utf-8", newline="").read()
        term = None
        for line in text.split("\n"):
            m = re.match(r"^\*\*(.+?)\*\*:\s*$", line)
            if m:
                term = m.group(1)
                defined.add(term.lower())
                continue
            m = re.match(r"^_Avoid_:\s*(.+?)\s*$", line)
            if m and term:
                # Strip parenthetical caveats BEFORE splitting on commas. A
                # caveat can contain a comma -- "knowledge base (fine in
                # conversation, but the wiki is the readable thing)" -- and
                # splitting first turned the tail into its own avoid-term.
                cleaned = re.sub(r"\([^)]*\)", "", m.group(1))
                for raw in cleaned.split(","):
                    word = raw.strip().strip(".")
                    if word:
                        avoid.setdefault(word.lower(), term)
    for word in defined:
        avoid.pop(word, None)
    return avoid


def split_doc(path):
    text = io.open(path, encoding="utf-8", newline="").read()
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}, text
    return yaml.safe_load(parts[1]) or {}, parts[2]


def scan(root, avoid):
    gated, reported, overridden = [], [], []
    for path in sorted(pathlib.Path(root).rglob("*.md")):
        if path.name in RESERVED or path.name == "CONTEXT.md":
            continue
        rel = path.relative_to(root).as_posix()
        fm, body = split_doc(path)
        allowed = {str(a).lower() for a in (fm.get("glossary_allow") or [])}
        low = body.lower()
        for word, canonical in sorted(avoid.items()):
            if not re.search(r"\b" + re.escape(word) + r"\b", low):
                continue
            if word in allowed:
                overridden.append((rel, word, canonical))
            elif " " in word:
                gated.append((rel, word, canonical))
            else:
                reported.append((rel, word, canonical))
    return gated, reported, overridden


def main(argv):
    if len(argv) >= 3:
        root, glossaries = argv[1], argv[2:]
    else:
        # The wiki carries its own glossary; a host repository's own is found
        # beside its answers file, because the split between them IS the point.
        try:
            root = str(project.path("layout.wiki"))
            host = project.find() / "CONTEXT.md"
        except project.Missing as exc:
            return project.complain(exc)
        glossaries = [str(host)] if host.is_file() else []
        if not glossaries and len(argv) < 2:
            sys.stdout.write("usage: glossary.py <wiki-root> <glossary.md> "
                             "[more.md]\n")
            return 2
    # the wiki's own glossary counts too, if it has one
    local = pathlib.Path(root) / "CONTEXT.md"
    if local.exists() and str(local) not in glossaries:
        glossaries = glossaries + [str(local)]

    avoid = parse_glossary(glossaries)
    gated, reported, overridden = scan(root, avoid)

    for rel, word, canonical in gated:
        sys.stdout.write("  %s: says %r -- the agreed word is %r\n"
                         % (rel, word, canonical))
    for rel, word, canonical in overridden:
        sys.stdout.write("  %s: %r allowed by glossary_allow (agreed word: %r)\n"
                         % (rel, word, canonical))
    if reported:
        seen = sorted({w for _, w, _ in reported})
        sys.stdout.write("  reported only, single common words: %s\n"
                         % ", ".join(seen))
    sys.stdout.write(
        "%d gated, %d reported, %d overridden, from %d avoid-terms in %d glossar%s\n"
        % (len(gated), len(reported), len(overridden), len(avoid),
           len(glossaries), "y" if len(glossaries) == 1 else "ies"))
    return 1 if gated else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
