"""OKF v0.1 conformance check -- and NOTHING more than conformance.

The spec (https://okf.md/spec/ section 9) says a bundle is conformant if:

  1. every non-reserved .md file contains parseable YAML frontmatter
  2. every frontmatter block contains a non-empty `type` field
  3. reserved filenames (index.md, log.md) follow their defined structure

and that consumers MUST NOT reject a bundle for missing optional fields,
unknown `type` values, unknown additional keys, broken cross-links, or a
missing index.md. This tool therefore checks three things and deliberately
declines to check anything else. The stricter house rules live in
kbprofile.py, and keeping the two apart is the point: if this file ever
starts rejecting a document our own template happens to dislike, we have
silently redefined the portable format as ours.

The spec observes that a linter for rules 1 and 2 is "about 10 lines of
bash". That is true, and most of what follows is the error reporting.

Encoding, per CLAUDE.md: documents are read as utf-8 explicitly. The
locale here is cp1252 and a bare open() would decode utf-8 as cp1252.

    python kit/tools/wikitools/okfcheck.py kit/wiki
"""
import io
import pathlib
import sys

import yaml

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import project                                    # noqa: E402

RESERVED = ("index.md", "log.md")


def read_frontmatter(path):
    """Return (frontmatter_dict, error_string). Exactly one is None."""
    text = io.open(path, encoding="utf-8", newline="").read()
    if not text.startswith("---"):
        return None, "no frontmatter block (file does not begin with ---)"
    parts = text.split("---", 2)
    if len(parts) < 3:
        return None, "frontmatter block is not closed by a second ---"
    try:
        data = yaml.safe_load(parts[1])
    except yaml.YAMLError as exc:
        first = str(exc).split("\n")[0]
        return None, "frontmatter is not parseable YAML: " + first
    if data is None:
        return {}, None
    if not isinstance(data, dict):
        return None, "frontmatter is not a mapping"
    return data, None


def check(root):
    root = pathlib.Path(root)
    problems = []
    docs = 0
    for path in sorted(root.rglob("*.md")):
        rel = path.relative_to(root).as_posix()
        if path.name in RESERVED:
            # rule 3. The root index.md is the one reserved file the spec
            # lets carry frontmatter, for okf_version -- section 11 says so
            # while section 6 says index files have none. We accept either
            # and report the tension rather than pretending it is settled.
            continue
        docs += 1
        data, err = read_frontmatter(path)
        if err:
            problems.append((rel, err))
            continue
        if not str(data.get("type", "")).strip():
            problems.append((rel, "frontmatter has no non-empty `type`"))
    return docs, problems


def main(argv):
    if len(argv) > 1:
        root = argv[1]
    else:
        try:
            root = str(project.path("layout.wiki"))
        except project.Missing as exc:
            return project.complain(exc)
    docs, problems = check(root)
    for rel, err in problems:
        sys.stdout.write("  " + rel + ": " + err + "\n")
    sys.stdout.write(
        "%d problem(s) in %d concept document(s) -- OKF v0.1 conformance only\n"
        % (len(problems), docs)
    )
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
