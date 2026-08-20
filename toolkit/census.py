"""Census of every script in both repos, and where each one is in its retirement.

WHY THIS IS A TOOL AND NOT A DOCUMENT. The hand-written script classification
(issue #2) was right when it was written and is now wrong in three places: it
counted 55 files where there are 60, it lists `emit_p6text.py` as broken after
it was repaired, and it lists `pairmap.py` as importing `refpath` below the line
that uses it, which is no longer true -- the import is at line 12 and the use at
line 17. A hand-maintained inventory that drifts is issue #15's class-4 defect
exactly: a measurement read as a finding. So this counts instead.

THE LIFECYCLE THIS TRACKS. The originals in `tools/` and in the VangeliSTracker
repo are frozen and keep working; the toolkit is built beside them by copy and
adjust; and once a toolkit tool supersedes an original, the original is archived.
"Copy and adjust, never refactor the originals" is therefore TRANSITIONAL, not
permanent, and the states below are that transition:

    superseded   a toolkit tool has replaced it. Names its successor.
    carry        should be copied across, not done yet.
    decline      will not be carried, with a reason. Dead scripts, spent
                 one-shots, and project-specific drivers.
    unknown      not yet triaged. Reported loudly, because an untriaged script
                 is the thing a stale document hides.

NOTHING UNEXPLAINED, IN EITHER DIRECTION. A script on disk with no triage entry
is reported. A triage entry naming a script that no longer exists is reported.
Both fail the run. That is the mechanism issue #15 named for this defect class,
and it is the only reason this file can be trusted where the document could not.

PATHS. The sibling repo lives at a machine-specific path, so it is NEVER named
in this committed file -- it comes from the local config, per the rule that put
`docs/continuation.md` out of the index. Pass roots on the command line, or set
them in the untracked local config.

    python toolkit/census.py --root tools
    python toolkit/census.py --root tools --root D:/elsewhere/scripts
"""
import ast
import io
import os
import pathlib
import sys

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover -- 3.11+ per pyproject.toml
    tomllib = None

TABLE = pathlib.Path(__file__).with_name("census.toml")
STATES = ("superseded", "carry", "decline", "unknown")


def load_table():
    if not TABLE.exists():
        return {}
    with io.open(TABLE, "rb") as fh:
        return tomllib.load(fh).get("script", {})


def parses(path):
    try:
        ast.parse(io.open(path, encoding="utf-8", newline="").read())
        return True
    except (SyntaxError, UnicodeDecodeError):
        return False


def main(argv):
    roots = [argv[i + 1] for i, a in enumerate(argv) if a == "--root"]
    if not roots:
        sys.stdout.write("usage: census.py --root <dir> [--root <dir> ...]\n"
                         "  the sibling repo's path is machine-specific and is "
                         "never committed -- pass it here.\n")
        return 2

    found = {}
    for root in roots:
        for path in sorted(pathlib.Path(root).rglob("*.py")):
            found.setdefault(path.name, []).append(path)

    table = load_table()
    problems, rows = [], []

    for name in sorted(found):
        entry = table.get(name, {})
        state = entry.get("state", "unknown")
        if state not in STATES:
            problems.append("%s: state %r is not one of %s"
                            % (name, state, "/".join(STATES)))
        if state == "unknown":
            problems.append("%s: untriaged. Every script needs a state -- an "
                            "untriaged one is what a stale document hides." % name)
        if state == "superseded" and not entry.get("successor"):
            problems.append("%s: marked superseded but names no successor" % name)
        if state == "decline" and not entry.get("reason"):
            problems.append("%s: marked decline but gives no reason" % name)
        broken = [str(p) for p in found[name] if not parses(p)]
        if broken:
            problems.append("%s: does not parse: %s" % (name, ", ".join(broken)))
        rows.append((name, state, len(found[name]),
                     entry.get("successor") or entry.get("reason") or ""))

    for name in sorted(table):
        if name not in found:
            problems.append("%s: in the census table but not on disk. A triage "
                            "entry outliving its script is how the last "
                            "inventory went stale." % name)

    counts = {}
    for _, state, _, _ in rows:
        counts[state] = counts.get(state, 0) + 1

    sys.stdout.write("SCRIPTS, by where they are in the retirement\n")
    for state in STATES:
        if counts.get(state):
            sys.stdout.write("  %-11s %3d\n" % (state, counts[state]))
    dup = [n for n, _, c, _ in rows if c > 1]
    sys.stdout.write("  %d distinct name(s) across %d file(s); %d name(s) in "
                     "more than one repo%s\n"
                     % (len(rows), sum(c for _, _, c, _ in rows), len(dup),
                        (": " + ", ".join(dup)) if dup else ""))

    if "--list" in argv:
        sys.stdout.write("\n")
        for name, state, n, note in rows:
            sys.stdout.write("  %-22s %-11s %s%s\n"
                             % (name, state, "x%d " % n if n > 1 else "   ", note))

    if problems:
        sys.stdout.write("\n")
        for p in problems:
            sys.stdout.write("  %s\n" % p)
    sys.stdout.write("\n%d problem(s)\n" % len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
