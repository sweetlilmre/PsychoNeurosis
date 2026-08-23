"""The project's answers to the kit's questions.

THE KIT HOLDS NO PROJECT FACTS. That is what makes it portable, and it means
every program in it needs somewhere to look up the facts it cannot contain: the
paths of a host repository, and the things a person read out of a target's
binaries once. That somewhere is a file at the host's root, and this module is
the only reader of it.

    kit.toml           committed. Relative paths, and target facts.
    kit.local.toml     NOT committed. Machine paths, which may never appear in
                       a committed file. Overrides kit.toml key by key.

**A person does not hand-write either.** A setup wizard writes them when the
kit is installed into a project -- decided on the map's kit/record ticket -- so
this module only ever reads.

TWO RULES, both from that ticket, and both are the reason this file is small:

  * **AN EXPLICIT ARGUMENT ALWAYS WINS.** Passing a path on the command line
    stays legal for ever; the answers file is what a program falls back to. So
    every accessor here takes an `override` and returns it untouched.

  * **A MEASURED VALUE NEVER LIVES HERE.** Coverage, byte-match lengths,
    observations and rungs are measured, and they live in the status register
    where a ratchet can guard them. What belongs here is what somebody READ:
    a segment list out of a unit header, the paragraph a disassembler calls the
    start of an image, where the sources are. The test is measured-versus-read,
    not path-versus-value. It matters: a coverage number pasted into a
    documented command line sat two below the truth for days, which is exactly
    the staleness the ratchet exists to prevent.

WHY IT PRINTS. Layout knowledge held in prose has drifted three times in one
day in this project's own host repository -- an install command that never
worked, a check that could never pass, and a docstring promising a config file
that did not exist. So a program says which value it used and where it came
from, and a disagreement with the tree is visible rather than silent.
"""
import io
import os
import pathlib
import sys

try:
    import tomllib
except ModuleNotFoundError:                 # pragma: no cover -- 3.11+
    import tomli as tomllib                 # type: ignore

ANSWERS = "kit.toml"
LOCAL = "kit.local.toml"


class Missing(Exception):
    """No answers file, or no answer. Carries a line fit to print as-is."""


def find(start=None):
    """The host root: the nearest directory at or above `start` with kit.toml.

    Walking up rather than assuming the current directory means a program runs
    from anywhere inside the project, which is how these tools are used.
    """
    here = pathlib.Path(start or os.getcwd()).resolve()
    for d in [here] + list(here.parents):
        if (d / ANSWERS).is_file():
            return d
    return None


def load(start=None):
    """(answers, provenance). The local file overrides, key by key and one
    level deep, because a machine path is a leaf and nothing here nests
    deeper than a section."""
    root = find(start)
    if root is None:
        raise Missing("no %s found at or above %s -- the kit is not installed "
                      "into this project yet" % (ANSWERS, os.getcwd()))
    data, where = {}, {}
    for name in (ANSWERS, LOCAL):
        path = root / name
        if not path.is_file():
            continue
        with io.open(path, "rb") as fh:
            loaded = tomllib.load(fh)
        for section, body in loaded.items():
            if isinstance(body, dict):
                data.setdefault(section, {}).update(body)
                for k in body:
                    where["%s.%s" % (section, k)] = name
            else:
                data[section] = body
                where[section] = name
    data["_root"] = root
    return data, where


def get(key, override=None, start=None, quiet=False):
    """One answer, by dotted key -- `layout.src`, `target.first_para`.

    An explicit override is returned untouched and unannounced: the caller
    said what it wanted and does not need telling.
    """
    if override is not None:
        return override
    data, where = load(start)
    section, _, name = key.partition(".")
    try:
        value = data[section][name]
    except (KeyError, TypeError):
        raise Missing("%s does not answer `%s` -- add it, or pass the value "
                      "on the command line" % (ANSWERS, key))
    if not quiet:
        sys.stdout.write("  using    %s = %r  (%s)\n"
                         % (key, value, where.get(key, ANSWERS)))
    return value


def path(key, override=None, start=None, quiet=False):
    """An answer that is a path, resolved against the HOST ROOT rather than the
    working directory -- so a program run from a subdirectory still finds it."""
    value = get(key, override, start, quiet)
    if override is not None:
        return pathlib.Path(value)
    root = find(start)
    return (pathlib.Path(root) / value) if root else pathlib.Path(value)


def paths(key, override=None, start=None, quiet=False):
    """An answer that is a list of paths -- census roots, for instance."""
    value = get(key, override, start, quiet)
    if isinstance(value, str):
        value = [value]
    root = find(start)
    return [(pathlib.Path(root) / v) if root else pathlib.Path(v)
            for v in value]


def positionals(argv, valued=()):
    """The real positional arguments: not a flag, and not a FLAG'S VALUE.

    Every program here used to do `[a for a in argv if not a.startswith("--")]`,
    which reads the value of `--coverage 76` as a positional. That is not a
    style point: `ratchet.py --coverage 76` took "76" as the name of the status
    register, loaded nothing, and reported `coverage 0 -> 76` as a RISE -- a
    measurement invented out of a missing file, in the one tool whose whole
    purpose is refusing to let a measurement slip. With `--write` it would have
    created a file called `76`.

    So a caller names the flags that take a value, and their values are skipped.
    """
    out, skip = [], False
    for a in argv:
        if skip:
            skip = False
            continue
        if a.startswith("--"):
            skip = a in valued or a.lstrip("-") in valued
            continue
        out.append(a)
    return out


def complain(exc):
    """Print a Missing as one line and nothing else. A program pointed at
    nothing should say so, not stack-trace at somebody who has just installed
    the kit."""
    sys.stdout.write("  %s\n" % exc)
    return 2
