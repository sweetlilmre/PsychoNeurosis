"""The plan: what to fix, in what order, and where that is written down.

Issue #11 settled the shape. The plan's top level is a short ORDERED LIST OF
INVESTIGATIONS -- named findings a person saw, each with prose -- and its
order IS the priority: there is no priority number to drift out of step with
the list. Routine rows are created LAZILY, when a session localises a finding
to a routine, and each names the investigation it belongs to. A 317-row table
nobody grooms is the failed ledger again; the plan enumerates what someone
has decided ABOUT.

The seam issue #11 re-affirmed: this tool is CORE -- it holds no project
facts, reads the register it is handed, and treats row keys as opaque. The
investigations, the rows, the addresses and every other project fact live in
the project's own register (the psycho repo's `status.toml`), never here.

What is DECIDED lives in [plan] (this tool writes it); what is MEASURED lives
in [routine.*] and [observation.*] (ratchet.py and observe.py write those).
The report joins the two, and never writes.

Sound checks, per issue #15 -- each refuses rather than reports:

  * a row must name an investigation that exists;
  * an investigation's `seen_in` must name a recorded observation -- the plan
    may not cite evidence the register does not hold;
  * resolving an investigation requires prose, same as lowering a ratchet
    target: the way out is a declared decision.

    python kit/tools/pascal/plan.py status.toml --report
    python kit/tools/pascal/plan.py status.toml --investigation part3-s6-dark \\
        --finding "left half of the dot object too dark" --seen-in TPART3 --write
    python kit/tools/pascal/plan.py status.toml --row "003 1139:0365" \\
        --label PART3_MORPH.FadeStep --for part3-s6-dark --target R6 --write
    python kit/tools/pascal/plan.py status.toml --resolve part3-s6-dark \\
        --resolution "was the missing REP STOSW; fixed at <sha>" --write
"""
import sys

import register
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import project                                    # noqa: E402

STATES = ("open", "resolved")


def investigations(status):
    return status.setdefault("plan", {}).setdefault("investigation", [])


def find(status, name):
    for inv in investigations(status):
        if inv.get("name") == name:
            return inv
    return None


def add_investigation(status, name, finding, seen_in):
    if find(status, name):
        return "investigation %r already exists" % name
    if seen_in and seen_in not in status.get("observation", {}):
        return ("seen_in names observation %r, which the register does not "
                "hold. The plan may not cite evidence that is not recorded."
                % seen_in)
    investigations(status).append({
        "name": name, "finding": finding, "seen_in": seen_in or "",
        "state": "open",
    })
    return None


def add_row(status, key, label, inv_name, target, cost, note):
    if not find(status, inv_name or ""):
        return ("row %r names investigation %r, which does not exist. Create "
                "the investigation first -- a row is a step toward a finding."
                % (key, inv_name))
    rows = status.setdefault("plan", {}).setdefault("row", {})
    rows[key] = {"label": label or "", "investigation": inv_name,
                 "target": target or "", "cost": cost or "", "note": note or ""}
    return None


def resolve(status, name, resolution):
    inv = find(status, name)
    if not inv:
        return "no investigation named %r" % name
    if not resolution:
        return ("resolving needs prose. The way out is a declared decision "
                "(issue #13), not a state flip.")
    inv["state"] = "resolved"
    inv["resolution"] = resolution
    return None


def report(status):
    plan = status.get("plan", {})
    invs = plan.get("investigation", [])
    rows = plan.get("row", {})
    if not invs:
        sys.stdout.write("  no investigations. The plan is empty, stated "
                         "rather than implied.\n")
    bad_state = [i.get("name") for i in invs if i.get("state") not in STATES]
    if bad_state:
        sys.stdout.write("  FAIL: state must be one of %s: %s\n"
                         % ("/".join(STATES), ", ".join(map(str, bad_state))))
        return 1
    orphans = [k for k, r in rows.items()
               if not find(status, r.get("investigation", ""))]
    if orphans:
        sys.stdout.write("  FAIL: row(s) name a missing investigation: %s\n"
                         % ", ".join(sorted(orphans)))
        return 1

    for n, inv in enumerate(invs, 1):
        mark = "open" if inv.get("state") == "open" else "RESOLVED"
        sys.stdout.write("  %d. %-24s %-8s %s\n"
                         % (n, inv.get("name", "?"), mark,
                            inv.get("finding", "")))
        if inv.get("seen_in"):
            obs = status.get("observation", {}).get(inv["seen_in"], {})
            sys.stdout.write("       seen in %s (%s, %s, %s)\n"
                             % (inv["seen_in"], obs.get("outcome", "?"),
                                obs.get("date", "?"), obs.get("observer", "?")))
        if inv.get("resolution"):
            sys.stdout.write("       resolution: %s\n" % inv["resolution"])
        for key in sorted(rows):
            row = rows[key]
            if row.get("investigation") == inv.get("name"):
                measured = status.get("routine", {}).get(key, {})
                sys.stdout.write("       row %-20s %-24s target %-3s achieved %s\n"
                                 % (key, row.get("label", ""),
                                    row.get("target", "-"),
                                    measured.get("achieved", "R0")))

    n_open = sum(1 for i in invs if i.get("state") == "open")
    sys.stdout.write("  %d investigation(s), %d open, %d row(s). Order is "
                     "priority; rows accrue as findings are localised.\n"
                     % (len(invs), n_open, len(rows)))
    return 0


def main(argv):
    # A flag's VALUE is not a positional -- see project.positionals.
    args = project.positionals(argv[1:], ('--investigation', '--finding', '--seen-in', '--row', '--for', '--label', '--target', '--cost', '--note', '--resolution'))
    if not args and any(a.startswith("--") for a in argv[1:]):
        # A flag but no register: ask the project where its register is.
        try:
            args = [str(project.path("layout.register"))]
        except project.Missing as exc:
            return project.complain(exc)
    if not args:
        sys.stdout.write(
            "usage: plan.py <status.toml> --report\n"
            "       plan.py <status.toml> --investigation NAME --finding TEXT"
            " [--seen-in OBS] [--write]\n"
            "       plan.py <status.toml> --row KEY --for INVESTIGATION"
            " [--label L] [--target R] [--cost C] [--note N] [--write]\n"
            "       plan.py <status.toml> --resolve NAME --resolution TEXT"
            " [--write]\n")
        return 2
    path = args[0]
    status = register.load(path)

    def opt(name, default=None):
        flag = "--" + name
        return argv[argv.index(flag) + 1] if flag in argv else default

    if "--report" in argv:
        return report(status)

    err = None
    if opt("investigation"):
        err = add_investigation(status, opt("investigation"),
                                opt("finding", ""), opt("seen-in"))
    elif opt("row"):
        err = add_row(status, opt("row"), opt("label"), opt("for"),
                      opt("target"), opt("cost"), opt("note"))
    elif opt("resolve"):
        err = resolve(status, opt("resolve"), opt("resolution"))
    else:
        return main([argv[0]])  # no verb: print usage

    if err:
        sys.stdout.write("  REFUSED: %s\n" % err)
        return 1
    if "--write" in argv:
        register.write(path, status)
        sys.stdout.write("  written %s\n" % path)
    else:
        sys.stdout.write("  ok -- not written, pass --write\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
