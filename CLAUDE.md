# Psycho Neurosis — orientation

Asphyxia's first megademo, 1994. Borland Pascal 7 plus hand-written assembler, real-mode DOS, VGA. The user is an original author. **This file is a router, not a manual** — read the entry point for whichever job you are on, and nothing else.

## Three separate jobs live here. Do not confuse them.

| job | entry point | state |
|---|---|---|
| **Reconstruct the demo** — recover Pascal source for parts 001–007 that behaves like the 1994 binaries | `docs/continuation.md` (untracked local marker), then `docs/23-deviations.md` | in progress; **behavioural** fidelity, not byte-exact |
| **Build the RE knowledge base** — a Pascal/DOS field manual and a reusable toolkit, extracted from what both efforts learnt | [The Pascal RE knowledge base](https://github.com/sweetlilmre/PsychoNeurosis/issues/1) | **complete, closed 21 Aug 2026** — `wiki/`, `kit/tools/`, and the plan in `status.toml`. **Its acceptance test also complete, closed 22 Aug 2026** ([The acceptance test](https://github.com/sweetlilmre/PsychoNeurosis/issues/19)): the three never-decompiled binaries — the launcher, setup and end screen — **all rebuild byte-identical** (`src/PSYCHO.PAS`, `STARTUP.PAS`+`DETECT`, `BYEBYE.PAS`; guarded as `[artefact.*]` rows). Verdict: survived, with reservations — easy subjects; the toolkit meets the hard parts in the cleanup plan. **Next work anywhere: `plan.py --report`'s table, top investigation first** |
| **Read the wiki, or add to it** — the Pascal/DOS field manual the knowledge-base effort is producing | `kit/wiki/index.md`, and `kit/tools/README.md` for the tools | one observation written as the pattern; grows every time a binary is read |
| **DemoVT byte-exact rebuild** | `docs/CONTINUATION.md` in the sibling `VangeliSTracker` checkout (`v1.31b/`) | **a different repo.** Complete: byte-identical load image, blocked only on LZEXE |

**The vocabulary is split by what travels.** [`kit/wiki/CONTEXT.md`](kit/wiki/CONTEXT.md) holds the METHOD's words -- artefact, instrument, blind spot, toolkit, core, driver, compare tool, allowed-difference rule, scratch folder, harness, marker, fragment, ratchet, plus gate, rung, strand, stance, provenance and the rest of the wiki's own terms -- and it goes wherever `kit/` goes. [`CONTEXT.md`](CONTEXT.md) at the root keeps only THIS target's words: part, scene, plan, investigation, plan row. Read both before arguing about any of them; the split was made under [#42](https://github.com/sweetlilmre/PsychoNeurosis/issues/42) and the test for which side a word belongs on is whether a different binary would need it rewritten.

## Running the toolkit — read this before touching anything, as of 20 Aug 2026

**It needs a virtual environment.** `pyyaml` is the only third-party dependency; TOML is read with stdlib `tomllib`, so Python 3.11+ is required.

    uv venv .venv
    uv pip install --python .venv/Scripts/python.exe -e kit/tools

**The install works and the kit still runs without it.** Both are deliberate: `python kit/tools/pascal/plan.py --report` works on a fresh clone with nothing installed, which is how a first session starts, so there are no console entry points to require an install before the first command. The install exists so a consumer can `import`: `from substrate import align`, `import project`. It failed silently for as long as it was documented -- `pyproject.toml` declared no `[build-system]` and no packages, so setuptools refused the flat layout of `substrate`/`pascal`/`wikitools` -- and nobody noticed because every command below runs a script by path. Fixed under [#39](https://github.com/sweetlilmre/PsychoNeurosis/issues/39) by declaring the three packages rather than moving any file.

Then all the checks. **They all pass, and the list is run in full at the end of any session that touches the kit** -- a commit hash here would go stale, and this file has been wrong three times in one day already.

    V=.venv/Scripts/python.exe

    $V kit/tools/wikitools/okfcheck.py
    $V kit/tools/wikitools/kbprofile.py          # --write regenerates
    $V kit/tools/wikitools/glossary.py
    $V kit/tools/pascal/markers.py --emit build/measured.toml
    $V kit/tools/pascal/ratchet.py --measured build/measured.toml
    $V kit/tools/pascal/observe.py --report
    $V kit/tools/pascal/artefact.py --check
    $V kit/tools/pascal/plan.py --report
    $V kit/tools/census.py
    $V kit/tools/pascal/shared_asm.py --gate    # asm duplicated between units instead of shared as an .INC
    $V kit/tools/pascal/routines.py     # the per-routine byte check; --emit feeds the ratchet
    python tools/paslint.py
    python tools/encaudit.py                    # add a dir argument for kit/tools/*, it does not scan it

**No paths and no numbers in that list, and both absences are the point.** Every program in the kit asks [`kit.toml`](kit.toml) where this repository keeps things -- the sources, the wiki, the register, the exempt list, the script roots -- and prints which answer it used and where it came from, so a disagreement with the tree is visible. An explicit path on the command line still wins; it is now the exception. Machine-specific paths, which may never be committed, live in the untracked `kit.local.toml` and override `kit.toml` key by key: that is how the sibling repository's root reaches the census. Neither file is hand-written -- the kit's setup wizard writes them ([#40](https://github.com/sweetlilmre/PsychoNeurosis/issues/40)).

**The routine lock lives in the register too, not in a tool.** `kit/tools/pascal/routines.py` is the successor to `tools/asmverify.py` and reads its locked lengths from `status.toml`'s `[routine.*]`, where a rise happens by itself and a lowering is a visible data change. The two agree on all 77 routines -- name, source, part, address, matched bytes, holes and which built image -- and the frozen one keeps working until [#36](https://github.com/sweetlilmre/PsychoNeurosis/issues/36) deletes it.

**The coverage number comes from the scan that measures it.** `markers.py --emit` writes what it counted and `ratchet.py --measured` reads it. It used to be typed into the command above as `--coverage 76` while the scan measured 78, so the ratchet sat two below the truth and could not have noticed a real fall -- which is the ratchet's own hole number one, *the lock sits stale-low*, surviving in the one number a person still typed.

**`status.toml` at the root is the status register**, and it is the ratchet: coverage may only rise, a byte match may not shorten, and an achieved rung may not fall unless the *target* is lowered with a reason. `achieved`, `matched` and every `[observation.*]` are **measured** and must never be hand-edited; `[plan]` is **decided** — an ordered list of investigations whose order is the priority, written only through `plan.py`. All three writers serialise through `kit/tools/pascal/register.py`, which refuses on a section it does not know rather than dropping it.

**The first observations were recorded on 21 Aug 2026** ([#18](https://github.com/sweetlilmre/PsychoNeurosis/issues/18)): seven runs by pe, six `differs` at R2 and one R3 — `TPART7` matches its original. The 22 scene harnesses remain at R0. Recording an observation nobody made is the one thing `observe.py` exists to prevent.

**The census needs the sibling repo's path on the command line**, because a machine path may never appear in a committed file.

## The state of this working tree, as of 22 Aug 2026

**Everything is committed and pushed on `vangelistracker-build`, the issue tracker is empty, and the one queue of work is the plan**: `.venv/Scripts/python.exe kit/tools/pascal/plan.py status.toml --report` — five investigations seeded defect-first, of which two are RESOLVED against pe's live runs (22 Aug) and three remain: part5-386-trio (fixed in code, needs a TPART5 run), **pacing (the main line — `tools/shapediff.py` lists the divergent spans to work top-down)**, and part6-confirm-r3 (a careful run, no code). `docs/continuation.md`'s dated block has the full state.

The remote is private `sweetlilmre/PsychoNeurosis`, default branch `main`. **`main` is behind `vangelistracker-build`** and everything lives on the branch. History contains third-party bytes — `bin/NEUROSIS.008` and `work/split/NEUROSIS_008.exe` are DemoVT — acceptable only while the repo stays private, and a blocker on ever making it public. A lesson kept from an earlier version of this section: treat a "not mine" claim about tree contents as needing a check against the diff, not as fact.

**`docs/continuation.md` is the marker file for where to go next, and it is deliberately NOT tracked** — `.gitignore` excludes it. It is a local working register, it carries real local paths, and its content is nobody's deliverable. Read it first for the reconstruction job; its dated block at the top is current. Its tracked history to 19 Aug 2026 is in the log under its old name, `docs/24-continuation.md`.

**The old note about unaudited docs is retired**: `docs/README.md`'s index and status table were brought current and `docs/23-deviations.md`'s conflicting `asmverify` counts fixed on 22 Aug 2026. `docs/research/` remains inputs-not-conclusions per its own README, and the ledger audit ([#4](https://github.com/sweetlilmre/PsychoNeurosis/issues/4)) still says what to distrust in the older material.

## Working the knowledge base

It is a wayfinder map on GitHub Issues: tickets are sub-issues, blocking is native, and the frontier is the open, unblocked, unassigned ones. **Its governing rule is copy and adjust, never refactor the originals** — `tools/*`, `docs/*` and the VangeliSTracker scripts stay exactly as they are; anything generic gets *copied* into the knowledge base and adapted there. Refactoring the originals to consume it is a later, separate effort, and executing the demo cleanup is out of scope for that map.

## Standing rules

- **Never re-express hand-written assembler as Pascal.** Transcribe it verbatim, comment every line, and put equivalent Pascal above it as a comment.
- **A measurement beats an argument.** Every confident claim about the compiler in this project's history has a roughly one-in-six survival rate; put the claimed difference in a probe and let a build settle it.
- **Distrust the verifier before the transcription.** The verify tooling has been wrong more often than the code it judged. Check a surprising measurement a second way.
- Prose in markdown is never hard-wrapped. Commits carry `Co-authored-by: Claude <noreply@anthropic.com>`.
- **Encoding and line endings split by who reads the file, and every script must say which it means.** Never rely on the locale: Windows' is cp1252, so a bare `open`/`read_text`/`write_text`, or a `subprocess` with `text=True`, silently decodes UTF-8 as cp1252. That has already mojibaked two documents and produced two false comparisons.

| the file is read by | encoding | line ending |
|---|---|---|
| humans and modern tools — `.md` | `utf-8` | LF, so pass `newline='\n'`; Python defaults to CRLF on Windows |
| a 1990s DOS tool — `.PAS` `.ASM` `.INC` `.MAP` `.BAT` `.CFG` | **`ascii`**, and strictly on write | CRLF |
| our own scripts' stdout via `subprocess` | `utf-8` | — |

  `ascii` on a DOS file is a **guard**, not a codec preference: it raises rather than quietly encoding an em dash as two bytes into a file Turbo Pascal will read. `paslint.py` checks for non-ASCII bytes and `build.py` refuses to compile when lint fails, so **write `--` not `—`, and `"` not `“`, in any `.PAS` comment.** `.gitattributes` in both repos enforces the line-ending half.
- Do not fetch period third-party binaries (LZEXE and friends). That is the user's call.

## Environment traps that have each cost real time

- Git Bash rewrites an argument starting with a slash into a Windows path, so `--sw=/GS` silently compiles **nothing** and reports `0 unit(s) compiled`. Prefix with `MSYS_NO_PATHCONV=1`, or use PowerShell. The same happens to `gh api /repos/...` — call `gh` from Python's `subprocess`, or use the `gh issue` / `gh label` subcommands.
- **A DOUBLED backslash in a Bash command is halved before bash sees it.** The `command` parameter carries one level of backslash escaping whose only known escape is the backslash itself: `\\` becomes `\`, every other `\x` passes through. Measured — N backslashes arrive as ceil(N/2) (2→1, 3→2, 4→2), while `\'`, `\"`, `\t`, `\n` are untouched. **A lone backslash is safe, so raw Windows paths are fine**; only doubling breaks, and doubling is what a Python literal needs for one backslash. Two failures follow, and they look unrelated: generated scripts get broken string literals (`'\\n'` arrives as `'\n'` — hence the endless `SyntaxWarning: invalid escape sequence '\s'`), and a `\\` next to a quote becomes `\` + quote, which bash reads as an *escaped* quote, unbalancing the command and reporting `unexpected EOF while looking for matching ''` at the wrong line. **So: write scripts with the Write tool and run them**, build backslashes as `chr(92)`, and pass prose via `--body-file` rather than inline.
- **Something in this environment has twice multiplied every line break in a markdown file** — `VangeliSTracker`'s `00-map.md` (91% blank lines) and this repo's `docs/README.md` (58%). The cause was never found. `tools/repairdoc.py` diagnoses and repairs it, and proves content preservation before writing.

**Two of those traps now have mechanisms rather than warnings**, which is the only thing that has ever stopped a blind spot recurring here:

    python tools/encaudit.py     any text I/O that leaves the encoding to the locale
    python tools/paslint.py      non-ASCII bytes in a DOS source, and four other defects
    python tools/repairdoc.py    diagnose or repair multiplied line breaks in a document

`encaudit.py` parses rather than pattern-matches, and the reason is worth reading in its docstring: a line-based regex reported 32 sites of which 16 were artifacts while missing 4 real ones, and parenthesis-matching then flagged the tool's own docstring. Both trees are currently clean.

**The backslash trap has already cost this project a file.** `tools/emit_p6text.py` sat with a literal newline inside a string literal — written by an earlier session's heredoc, where the intended `\n` was collapsed — so it never compiled and never produced its output. Found by `encaudit.py` refusing to parse it, and repaired on 19 Aug 2026.
