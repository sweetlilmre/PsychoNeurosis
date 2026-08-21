"""Record what a person saw when they ran a harness, so it stops being prose.

Rungs R2 ("it runs") and R3 ("a viewer sees no difference") are the only nodes
on the fidelity ladder whose instrument is a person watching a screen. Issue #7
had to declare both instruments MISSING, and the measurement behind that is
blunt: 29 harnesses exist, 29 are built in run/, and there is no record of any
result anywhere in the repo. Four parts once "built" and had never been run.

Issue #15's rule is that a human observation may make a rung green, but only
once it is recorded as a dated claim naming who ran what. The observation is
the instrument; THE RECORD IS THE RATCHET. This is that record.

THREE RULES THIS TOOL ENFORCES, each from a measured failure:

  R3 REQUIRES THE PART TIER. A scene harness cannot judge palette or
  cross-scene state, and the docs enumerate why: one scene shows the wrong
  colours alone because it inherits what the previous scene left behind;
  another must reset the video mode afterwards because the PART DRIVER does
  that and not the scene. So a scene-tier observation caps at R2.

  AN OBSERVATION IS ABOUT ONE BUILD. It stores the commit it was made at and a
  hash of the sources the harness actually depends on -- its own file plus the
  units in its `uses` clause. When those change the observation goes STALE and
  is reported, never failed. Voiding it on any edit would drop every
  behavioural rung to R0 and make the ladder useless; failing on it would call
  an ordinary edit a regression.

  STALENESS IS A GAP IN KNOWLEDGE, NOT A REGRESSION IN CODE. So `achieved`
  holds the last measured rung and the ratchet reads it, while `confirmed_at`
  holds the commit and the report reads that. An unverified claim is visible as
  unverified without the ratchet failing on an edit -- which is the wedge issue
  #13 had to avoid.

`invisible` is a first-class outcome, not a synonym for `ran`. A harness that
omits a setup call can run a scene CORRECTLY AND INVISIBLY -- one ran entirely
in 80x25 text, "indistinguishable from a hang".

    python toolkit/pascal/observe.py status.toml --report
    python toolkit/pascal/observe.py status.toml --harness TPART5 --tier part \\
        --outcome matches --observer pe --date 2026-08-20 --against NEUROSIS_005.exe
"""
import hashlib
import io
import os
import pathlib
import re
import subprocess
import sys

import register

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover -- 3.11+ per pyproject.toml
    tomllib = None

TIERS = ("scene", "part")
# R2 outcomes describe whether it ran at all; R3 outcomes describe what a
# viewer saw. `invisible` belongs to R2 and is deliberately not `ran`.
OUTCOMES = {
    "ran": "R2", "hung": "R0", "crashed": "R0", "invisible": "R0",
    "matches": "R3", "differs": "R2",
}


def load(path):
    if not os.path.exists(path):
        return {}
    with io.open(path, "rb") as fh:
        return tomllib.load(fh)


def toml_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def head_commit(root="."):
    try:
        out = subprocess.run(["git", "-C", root, "rev-parse", "HEAD"],
                             capture_output=True, text=True, encoding="utf-8")
        return out.stdout.strip()[:12] if out.returncode == 0 else "unknown"
    except OSError:
        return "unknown"


def harness_sources(harness, src="src"):
    """The harness's own file plus every unit in its `uses` clause.

    Precise on purpose. Hashing all of src/ would mark every observation stale
    on any edit anywhere, which is the over-broad answer issue #16 rejected.
    """
    root = pathlib.Path(src)
    own = root / (harness.upper() + ".PAS")
    if not own.exists():
        return []
    files = [own]
    text = io.open(own, encoding="ascii", newline="").read()
    m = re.search(r"\buses\b(.*?);", text, re.S | re.I)
    if m:
        for name in re.split(r"[,\s]+", m.group(1)):
            name = name.strip()
            if not name:
                continue
            for cand in (root / (name.upper() + ".PAS"),):
                if cand.exists():
                    files.append(cand)
    return files


def fingerprint(files):
    h = hashlib.sha256()
    for path in sorted(files):
        h.update(io.open(path, "rb").read())
    return h.hexdigest()[:16] if files else ""


def dump(status):
    """Serialisation is register.py's job, one writer for every tool, so no
    tool can drop a section another tool owns."""
    return register.dump(status)


def record(status, args):
    harness = args["harness"]
    tier, outcome = args["tier"], args["outcome"]
    if tier not in TIERS:
        return "tier must be one of %s" % "/".join(TIERS)
    if outcome not in OUTCOMES:
        return "outcome must be one of %s" % "/".join(sorted(OUTCOMES))
    rung = OUTCOMES[outcome]
    if rung == "R3" and tier != "part":
        return ("%s claims R3 from the %s tier. R3 requires the PART tier: a "
                "scene harness cannot judge palette or cross-scene state."
                % (harness, tier))
    if outcome == "matches" and not args.get("against"):
        return "an R3 claim must name the original it was compared against"

    files = harness_sources(harness)
    if not files:
        return "no source found for harness %s in src/" % harness
    status.setdefault("observation", {})[harness] = {
        "harness": harness, "tier": tier, "outcome": outcome, "achieved": rung,
        "observer": args["observer"], "date": args["date"],
        "confirmed_at": head_commit(), "fingerprint": fingerprint(files),
        "against": args.get("against", ""), "note": args.get("note", ""),
    }
    return None


def report(status):
    rows = status.get("observation", {})
    if not rows:
        sys.stdout.write("  no observations recorded. Every harness is at R0, "
                         "stated rather than implied.\n")
        return 0
    stale = 0
    for key in sorted(rows):
        row = rows[key]
        now = fingerprint(harness_sources(row.get("harness", key)))
        fresh = now and now == row.get("fingerprint")
        if not fresh:
            stale += 1
        sys.stdout.write("  %-8s %-5s %-9s %-4s %s %s%s\n"
                         % (row.get("harness", key), row.get("tier", "?"),
                            row.get("outcome", "?"), row.get("achieved", "?"),
                            row.get("date", "?"), row.get("observer", "?"),
                            "" if fresh else "   STALE, source changed since "
                            + str(row.get("confirmed_at", "?"))))
    sys.stdout.write("  %d observation(s), %d stale. Stale is a gap in "
                     "KNOWLEDGE, not a regression -- reported, never failed.\n"
                     % (len(rows), stale))
    return 0


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    if not args:
        sys.stdout.write("usage: observe.py <status.toml> --report\n"
                         "       observe.py <status.toml> --harness X --tier "
                         "scene|part --outcome ... --observer who --date YYYY-MM-DD\n")
        return 2
    path = args[0]
    status = load(path)

    def opt(name, default=None):
        flag = "--" + name
        return argv[argv.index(flag) + 1] if flag in argv else default

    if "--report" in argv:
        return report(status)

    if not opt("harness"):
        return report(status)

    fields = {k: opt(k) for k in ("harness", "tier", "outcome", "observer",
                                  "date", "against", "note")}
    missing = [k for k in ("harness", "tier", "outcome", "observer", "date")
               if not fields.get(k)]
    if missing:
        sys.stdout.write("  missing: %s -- an observation is only evidence if "
                         "it is dated and says who ran what (issue #15)\n"
                         % ", ".join(missing))
        return 2

    err = record(status, fields)
    if err:
        sys.stdout.write("  REFUSED: %s\n" % err)
        return 1
    if "--write" in argv:
        io.open(path, "w", encoding="utf-8", newline="\n").write(dump(status))
        sys.stdout.write("  recorded %s in %s\n" % (fields["harness"], path))
    else:
        sys.stdout.write("  would record %s -- pass --write\n" % fields["harness"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
