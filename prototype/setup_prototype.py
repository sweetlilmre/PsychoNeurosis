"""PROTOTYPE -- throwaway. The kit's setup wizard, rough, to react to.

Wayfinder #40. The question it answers is NOT "how do I write a config file";
it is **what does the wizard ASK, and what should it work out for itself?** The
ticket's own warning is the design brief: *every question it asks is a chance to
record a wrong answer, and the tree can answer most of them.*

So this prints three things and nothing else matters:

    FOUND     what it worked out from the tree, and how confident it is
    ASK       what it cannot know, with a proposed default
    WRITE     exactly what would land, before anything lands

It is a plain script with prompts -- the cheapest of the three mechanisms the
ticket lists -- deliberately, because that makes the QUESTION LIST the thing
under discussion rather than the delivery. If the list is right, an agent-driven
version discovers the same things and asks the same questions with better
manners; if the list is wrong, no amount of manners helps.

Prototype shortcuts, all deliberate: no error handling, nothing written without
--write, and it does not touch git.

    python setup_prototype.py <project-dir>
    python setup_prototype.py <project-dir> --write
"""
import io
import os
import pathlib
import re
import sys

# Where a Borland Pascal build tool tends to live on Windows. Guessing beats
# asking when the guess can be CHECKED -- and if none of these exist the
# question gets asked instead of a wrong answer recorded.
COMPILER_HINTS = ["C:/TP", "C:/TP7", "C:/BP", "C:/TASM"]
DOSBOX_HINTS = ["D:/DOSBox-X/dosbox-x.exe", "C:/DOSBox-X/dosbox-x.exe",
                "C:/Program Files/DOSBox-X/dosbox-x.exe"]


class Answers(object):
    def __init__(self):
        self.found = []          # (key, value, why)
        self.asked = []          # (key, value, question)
        self.local = []          # (key, value, why)  -- machine paths

    def find(self, key, value, why):
        self.found.append((key, value, why))
        return value

    def ask(self, key, question, default):
        # A prototype asks on stdin. The point is the QUESTION, not the reader.
        sys.stdout.write("\n  ? %s\n    [%s] " % (question, default))
        sys.stdout.flush()
        try:
            got = sys.stdin.readline().strip()
        except Exception:
            got = ""
        value = got or default
        self.asked.append((key, value, question))
        return value


def count_ext(d, ext):
    return sum(1 for _ in d.rglob("*" + ext))


def discover(root, a):
    """Everything the tree can answer for itself."""
    # --- is the kit even here? ------------------------------------------
    kit = root / "kit"
    if (kit / "tools").is_dir() and (kit / "wiki").is_dir():
        a.find("kit", "kit/", "tools/ and wiki/ are both there")
    elif kit.exists():
        a.find("kit", "kit/ EMPTY",
               "the submodule is not initialised -- git submodule update --init kit")
    else:
        a.find("kit", "MISSING", "no kit/ at all; add the submodule first")

    # --- the sources ----------------------------------------------------
    pas = sorted(((count_ext(d, ".PAS"), d) for d in root.rglob("*")
                  if d.is_dir() and "kit" not in d.parts
                  and ".git" not in d.parts and count_ext(d, ".PAS")),
                 reverse=True)
    if len(pas) == 1 or (pas and pas[0][0] > 2 * pas[1][0]):
        n, d = pas[0]
        a.find("layout.src", d.relative_to(root).as_posix(),
               "%d .PAS file(s), %s than anywhere else"
               % (n, "more" if len(pas) > 1 else "the only directory with any"))
    elif pas:
        a.ask("layout.src",
              "which directory holds the sources? (%s)"
              % ", ".join("%s:%d" % (d.relative_to(root).as_posix(), n)
                          for n, d in pas[:4]),
              pas[0][1].relative_to(root).as_posix())

    # --- the register, the build, the wiki ------------------------------
    if (root / "status.toml").is_file():
        a.find("layout.register", "status.toml", "it is there")
    else:
        a.find("layout.register", "(none)",
               "no register yet -- a tool that needs one will say so")
    for name in ("build", "out", "obj"):
        if (root / name).is_dir():
            a.find("layout.build", name, "it is there")
            break
    if (root / "kit" / "wiki").is_dir():
        a.find("layout.wiki", "kit/wiki", "the kit brought it")

    # --- the target's binaries ------------------------------------------
    cands = []
    for pat in ("*.bin", "*.exe", "*.EXE", "*.[0-9][0-9][0-9]"):
        for p in root.rglob(pat):
            if "kit" in p.parts or ".git" in p.parts or "build" in p.parts:
                continue
            if p.stat().st_size > 4096:
                cands.append(p)
    if cands:
        pick = sorted(cands, key=lambda p: (len(p.parts), p.name))[0]
        a.find("target.image", pick.relative_to(root).as_posix(),
               "%d candidate binar%s; smallest path wins in a prototype"
               % (len(cands), "y" if len(cands) == 1 else "ies"))

    # --- script folders, for the census --------------------------------
    py = [d.relative_to(root).as_posix() for d in root.rglob("*")
          if d.is_dir() and ".git" not in d.parts
          and any(f.suffix == ".py" for f in d.iterdir() if f.is_file())]
    if py:
        a.find("census.roots", py, "directories holding .py files")

    # --- the agent file -------------------------------------------------
    for name in ("CLAUDE.md", "AGENTS.md"):
        if (root / name).is_file():
            t = io.open(root / name, encoding="utf-8").read()
            a.find("agent file", name,
                   "exists, %d lines -- the stanza is APPENDED, never a rewrite"
                   % t.count("\n"))
            break
    else:
        a.find("agent file", "CLAUDE.md", "none yet; one would be created")


def ask_what_cannot_be_known(root, a):
    """The short list. Everything here is either a fact about the TARGET that
    no directory listing implies, or a path on THIS machine."""
    a.ask("target.first_para",
          "what paragraph does your disassembly call the start of the load "
          "image? (0x1000 if you used Ghidra's default for a 16-bit MZ)",
          "0x1000")

    dosbox = next((p for p in DOSBOX_HINTS if pathlib.Path(p).exists()), None)
    if dosbox:
        a.local.append(("dosbox", dosbox, "found on disk, not asked"))
    else:
        a.local.append(("dosbox",
                        a.ask("local.dosbox", "where is dosbox-x.exe?",
                              "D:/DOSBox-X/dosbox-x.exe"), "asked"))
    comp = next((p for p in COMPILER_HINTS if pathlib.Path(p).exists()), None)
    if comp:
        a.local.append(("compiler", comp, "found on disk, not asked"))
    else:
        a.local.append(("compiler",
                        a.ask("local.compiler",
                              "where is the Turbo Pascal install?", "C:/TP"),
                        "asked"))


STANZA = """
## The kit

`kit/` is a submodule on [re-kit](https://github.com/sweetlilmre/re-kit) -- the reusable programs and the field manual. **Run `git submodule update --init kit` before anything else**: without it `kit/` is empty and every command below fails on a missing file without naming the cause.

**Read [`kit/WORKING.md`](kit/WORKING.md) first.** It holds how to pick up the next piece of work, which instrument answers which question, the checks and when to run them, and the standing rules. This file holds only what is true of THIS target.

`kit.toml` answers what the kit needs to know about this project; `kit.local.toml`, which git ignores, holds the machine paths. Neither is hand-written -- the kit's setup wizard writes them.
"""


def render(a):
    """kit.toml, as it would be written."""
    layout, target, census = {}, {}, None
    for key, value, _ in a.found + [(k, v, "") for k, v, _ in a.asked]:
        if key.startswith("layout.") and value != "(none)":
            layout[key.split(".", 1)[1]] = value
        elif key.startswith("target."):
            target[key.split(".", 1)[1]] = value
        elif key == "census.roots":
            census = value
    out = ["# Written by the kit's setup wizard. What somebody READ, never what",
           "# something MEASURED.", "", "[layout]"]
    for k in sorted(layout):
        out.append("%-8s = %r" % (k, layout[k]))
    out += ["", "[target]"]
    for k in sorted(target):
        out.append("%-10s = %s" % (k, target[k] if k == "first_para"
                                  else repr(target[k])))
    if census:
        out += ["", "[census]", "roots = [%s]"
                % ", ".join(repr(r) for r in census)]
    return "\n".join(out) + "\n"


def main(argv):
    root = pathlib.Path(argv[0] if argv else os.getcwd()).resolve()
    write = "--write" in argv
    print("PROTOTYPE setup wizard -- %s" % root)
    a = Answers()
    discover(root, a)

    print("\nFOUND, from the tree -- %d thing(s) not asked about:" % len(a.found))
    for key, value, why in a.found:
        print("  %-18s %-34s %s" % (key, value if isinstance(value, str)
                                    else "%d entr%s" % (len(value), "y" if len(value) == 1 else "ies"), why))

    ask_what_cannot_be_known(root, a)

    print("\nASKED -- %d question(s):" % len(a.asked))
    for key, value, q in a.asked:
        print("  %-18s %-34s %s" % (key, value, q[:52]))
    print("\nMACHINE PATHS, for kit.local.toml (never committed):")
    for key, value, why in a.local:
        print("  %-18s %-34s %s" % (key, value, why))

    print("\nWOULD WRITE kit.toml:")
    print("".join("    " + l + "\n" for l in render(a).split("\n") if l))
    print("WOULD APPEND to %s: the stanza, %d lines"
          % (next((v for k, v, _ in a.found if k == "agent file"), "CLAUDE.md"),
             STANZA.count("\n")))
    if write:
        io.open(root / "kit.toml", "w", encoding="utf-8",
                newline="\n").write(render(a))
        print("\n  written kit.toml")
    else:
        print("\n  (nothing written -- pass --write)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
