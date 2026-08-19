"""Our stricter profile on top of OKF, plus the generators that stop drift.

Three jobs, and the third is the one that earns this file:

  CHECK    the fields our template settled on in issue #8 are present, and
           `example: none yet` is written out rather than left blank.

  REFUSE   a hub that states an unqualified rule. This is the failure mode
           issue #14 exists to prevent: if the hub says "forgive zeros"
           without naming an artefact, it has stated ONE artefact's rule as
           a general truth and demoted the others to footnotes nobody
           reads. The zero rule was re-implemented wrongly "within an hour
           of reading" the header documenting that exact failure twice, so
           one hop away is not far enough. This check is the mechanism that
           replaces the advice.

  GENERATE the hub's discriminator table and each index.md, from the
           children's frontmatter. A hand-written summary beside a child's
           full rule is a second copy and it WILL drift; generating it is
           the same principle OKF already applies to index.md.

Encoding, per CLAUDE.md: utf-8 explicitly on read and write, and newline
'\n' on write, because Python defaults to CRLF on Windows and documents in
this repo are LF (.gitattributes enforces it).

    python kb-prototype/tools/kbprofile.py kb-prototype
    python kb-prototype/tools/kbprofile.py kb-prototype --write
"""
import io
import pathlib
import re
import sys

import yaml

BEGIN = "<!-- generated:discriminator -->"
END = "<!-- /generated:discriminator -->"

# Frontmatter keys, by document type.
REQUIRED_FRONTMATTER = {
    "Observation": ("type", "title", "description", "tags", "timestamp"),
    "Procedure": ("type", "title", "description", "tags", "timestamp"),
    "Artefact Answer": ("type", "title", "description", "identify", "holding",
                        "order", "artefact", "tier", "ladder_node", "tags",
                        "timestamp"),
}

# Body headings an artefact answer must carry. `Decides` is retired and
# `Disasm` folded into Cost -- see issue #8.
REQUIRED_SECTIONS = {
    "Artefact Answer": ("What to do", "Why it works", "Blind spot", "Cost",
                        "Example", "Withdrawn", "Citations"),
    "Observation": (),
    "Procedure": (),
}

TIERS = ("substrate", "pascal")

# A hub must not state a rule. These are the imperative openings that turn a
# discriminator into a rule; they are only a defect OUTSIDE the generated
# table and outside a sentence that names an artefact.
RULE_VERBS = ("forgive", "excuse", "ignore", "skip", "mask", "accept")
ARTEFACT_WORDS = ("`.tpu`", "`.obj`", "linked image", "artefact", "which",
                  "depend", "invert", "tasm", "turbo pascal")


def split_doc(path):
    text = io.open(path, encoding="utf-8", newline="").read()
    parts = text.split("---", 2)
    if len(parts) < 3:
        return {}, text
    return yaml.safe_load(parts[1]) or {}, parts[2]


def headings(body):
    return [m.group(1).strip() for m in re.finditer(r"^#+\s+(.*)$", body, re.M)]


def check_doc(path, rel):
    fm, body = split_doc(path)
    kind = str(fm.get("type", "")).strip()
    problems = []
    if kind not in REQUIRED_FRONTMATTER:
        return ["%s: unknown type %r for our profile" % (rel, kind)]

    for key in REQUIRED_FRONTMATTER[kind]:
        val = fm.get(key)
        if val is None or (isinstance(val, str) and not val.strip()):
            problems.append("%s: missing frontmatter key `%s`" % (rel, key))

    have = headings(body)
    for want in REQUIRED_SECTIONS[kind]:
        if not any(h.lower() == want.lower() for h in have):
            problems.append("%s: missing section `%s`" % (rel, want))

    if kind == "Artefact Answer":
        tier = str(fm.get("tier", "")).strip()
        if tier and tier not in TIERS:
            problems.append("%s: tier %r is not one of %s"
                            % (rel, tier, "/".join(TIERS)))
        # The example field is mandatory but `none yet` is legal -- what is
        # NOT legal is leaving it blank, because a silent blank reads as
        # fine while `none yet` reads as what it is.
        block = section_text(body, "Example")
        if block is not None and not block.strip():
            problems.append("%s: `Example` is blank -- write `none yet` if there is none"
                            % rel)

    if kind == "Observation":
        problems.extend(check_hub_states_no_rule(rel, body))

    if kind == "Artefact Answer":
        # The hub's table is GENERATED from these two keys, so a rule verb
        # here reaches the hub and bypasses check_hub_states_no_rule, which
        # deliberately skips the generated block. That was a real hole: the
        # one place rules ended up was the one place exempt from the check.
        for key in ("identify", "description"):
            val = str(fm.get(key, "")).lower()
            if any(v in val for v in RULE_VERBS):
                problems.append(
                    "%s: `%s` feeds the hub's table and states a rule -- it must "
                    "say how to RECOGNISE this artefact, not what to do about it"
                    % (rel, key))
    return problems


def section_text(body, name):
    m = re.search(r"^#+\s+" + re.escape(name) + r"\s*$(.*?)(?=^#+\s|\Z)",
                  body, re.M | re.S)
    return None if m is None else m.group(1)


def check_hub_states_no_rule(rel, body):
    """Refuse a hub sentence that gives an instruction without an artefact."""
    outside = body
    if BEGIN in outside and END in outside:
        head, rest = outside.split(BEGIN, 1)
        outside = head + rest.split(END, 1)[1]
    problems = []
    for raw in re.split(r"(?<=[.!?])\s+|\n", outside):
        s = raw.strip()
        if not s or s.startswith(("|", "#", "-", ">")):
            continue
        low = s.lower()
        # A rule verb inside quotation marks is a rule being DISCUSSED, not
        # stated -- '"forgive zeros" silently assumes the first case' is the
        # hub doing its job. Strip quoted spans before looking.
        unquoted = re.sub(r'"[^"]*"', " ", low)
        if not any(v in unquoted for v in RULE_VERBS):
            continue
        if any(w in low for w in ARTEFACT_WORDS):
            continue
        problems.append(
            "%s: the hub states a rule without naming an artefact -- %r"
            % (rel, s[:70]))
    return problems


def render_discriminator(children):
    rows = ["| if you are looking at | how to tell | detail |",
            "|---|---|---|"]
    for fm, stem in children:
        # `holding` and `summary` are explicit keys. An earlier version derived
        # the first column by stripping a prefix off the title, which was both
        # brittle and LOSSY -- it silently dropped the backticks around `.TPU`.
        rows.append("| %s | %s | [%s](./%s.md) |"
                    % (fm.get("holding", stem), fm.get("identify", ""),
                       stem, stem))
    return "\n".join(rows)


def generate(root, write):
    root = pathlib.Path(root)
    changed = []
    for hub in sorted(root.rglob("observation.md")):
        children = []
        for path in sorted(hub.parent.glob("*.md")):
            if path.name in ("observation.md", "index.md"):
                continue
            fm, _ = split_doc(path)
            if str(fm.get("type", "")).strip() == "Artefact Answer":
                children.append((fm, path.stem))
        # Explicit order. Alphabetical put the linked image FIRST, which is
        # backwards: the three artefacts sit at three points of one pipeline
        # and reading them in that order is what explains the inversion.
        children.sort(key=lambda c: (int(c[0].get("order", 99)), c[1]))
        table = render_discriminator(children)
        text = io.open(hub, encoding="utf-8", newline="").read()
        if BEGIN not in text or END not in text:
            changed.append((hub, "hub has no generated:discriminator markers"))
            continue
        head, rest = text.split(BEGIN, 1)
        _, tail = rest.split(END, 1)
        new = head + BEGIN + "\n" + table + "\n" + END + tail
        if new != text:
            changed.append((hub, "discriminator table is stale"))
            if write:
                io.open(hub, "w", encoding="utf-8", newline="\n").write(new)

        # index.md for the observation directory
        idx = hub.parent / "index.md"
        lines = ["# " + str(split_doc(hub)[0].get("title", hub.parent.name)), ""]
        lines.append("* [%s](observation.md) - the discriminator: which artefact are you holding?"
                     % split_doc(hub)[0].get("title", "observation"))
        for fm, stem in children:
            lines.append("* [%s](%s.md) - %s" % (fm.get("title", stem), stem,
                                                 fm.get("identify", "")))
        body = "\n".join(lines) + "\n"
        if not idx.exists() or io.open(idx, encoding="utf-8", newline="").read() != body:
            changed.append((idx, "index.md is stale or missing"))
            if write:
                io.open(idx, "w", encoding="utf-8", newline="\n").write(body)
    return changed


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    write = "--write" in argv
    root = pathlib.Path(args[0] if args else ".")

    problems = []
    docs = 0
    for path in sorted(root.rglob("*.md")):
        if path.name in ("index.md", "log.md", "README.md"):
            continue
        docs += 1
        problems.extend(check_doc(path, path.relative_to(root).as_posix()))

    changed = generate(root, write)

    for p in problems:
        sys.stdout.write("  " + p + "\n")
    for path, why in changed:
        verb = "regenerated" if write else "STALE"
        sys.stdout.write("  %s: %s (%s)\n"
                         % (path.relative_to(root).as_posix(), why, verb))
    sys.stdout.write("%d profile problem(s) in %d document(s); %d generated file(s) %s\n"
                     % (len(problems), docs, len(changed),
                        "rewritten" if write else "out of date"))
    return 1 if problems or (changed and not write) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
