# Psycho Neurosis — orientation

Asphyxia's first megademo, 1994. Borland Pascal 7 plus hand-written assembler, real-mode DOS, VGA. The user is an original author. **This file is a router, not a manual** — read the entry point for whichever job you are on, and nothing else.

## Four separate jobs live here. Do not confuse them.

| job | entry point | state |
|---|---|---|
| **Reconstruct the demo** — recover Pascal source for parts 001–007 that behaves like the 1994 binaries | `docs/continuation.md` (untracked local marker), then `docs/23-deviations.md` | in progress; **behavioural** fidelity, not byte-exact |
| **Make the kit the RE driver** — every generic tool into `kit/tools`, the way of working written where it travels | [The toolkit and wiki become the RE drivers](https://github.com/sweetlilmre/PsychoNeurosis/issues/29) — **the map IS that effort's continuation document** | **COMPLETE, 22 of 22 tickets, 23 Aug 2026** — kept open for the maintainer to close. Every generic tool is in `kit/tools` (47 of them), the 49 scripts they superseded are gone and recoverable from the `archive/pre-kit-scripts` tag, both repositories drive their work from the kit, and the way of working is in `kit/WORKING.md`, which travels with it. `docs/32-tool-disposition.md` is the permanent record of where each script went and the measurement that made deleting it safe |
| **The knowledge base's own map** — CLOSED, kept for its resolutions, which carry the measurements behind several of today's decisions | [The Pascal RE knowledge base](https://github.com/sweetlilmre/PsychoNeurosis/issues/1) | **complete, closed 21 Aug 2026** — `wiki/`, `kit/tools/`, and the plan in `status.toml`. **Its acceptance test also complete, closed 22 Aug 2026** ([The acceptance test](https://github.com/sweetlilmre/PsychoNeurosis/issues/19)): the three never-decompiled binaries — the launcher, setup and end screen — **all rebuild byte-identical** (`src/PSYCHO.PAS`, `STARTUP.PAS`+`DETECT`, `BYEBYE.PAS`; guarded as `[artefact.*]` rows). Verdict: survived, with reservations — easy subjects; the toolkit meets the hard parts in the cleanup plan. **Next work anywhere: `plan.py --report`'s table, top investigation first** |
| **Read the wiki, or add to it** — the Pascal/DOS field manual the knowledge-base effort is producing | `kit/wiki/index.md`, and `kit/tools/README.md` for the tools | one observation written as the pattern; grows every time a binary is read |
| **DemoVT byte-exact rebuild** | `docs/CONTINUATION.md` in the sibling `VangeliSTracker` checkout (`v1.31b/`) | **a different repo.** Complete: byte-identical load image, blocked only on LZEXE |

**The vocabulary is split by what travels.** [`kit/wiki/CONTEXT.md`](kit/wiki/CONTEXT.md) holds the METHOD's words -- artefact, instrument, blind spot, toolkit, core, driver, compare tool, allowed-difference rule, scratch folder, harness, marker, fragment, ratchet, plus gate, rung, strand, stance, provenance and the rest of the wiki's own terms -- and it goes wherever `kit/` goes. [`CONTEXT.md`](CONTEXT.md) at the root keeps only THIS target's words: part, scene, plan, investigation, plan row. Read both before arguing about any of them; the split was made under [#42](https://github.com/sweetlilmre/PsychoNeurosis/issues/42) and the test for which side a word belongs on is whether a different binary would need it rewritten.

## The kit

`kit/` is a submodule on [re-kit](https://github.com/sweetlilmre/re-kit) -- the reusable programs and the field manual. **Run `git submodule update --init kit` before anything else**: without it `kit/` is empty and every command below fails on a missing file without naming the cause.

**Read [`kit/WORKING.md`](kit/WORKING.md) first, and its section 2a is the loop** -- pick up work, walk the coverage, read the segment, edit, rebuild one target, check BOTH instruments, run it, record it. Sections 1, 2, 2a and 4 are the session and are about a page; 3 and 8 are reference, consulted when you have a question. It also holds when a finding becomes a wiki observation, and how to change the kit from inside this project -- which is two acts, never one. This file holds only what is true of THIS target.

`kit.toml` answers what the kit needs to know about this project; `kit.local.toml`, which git ignores, holds the machine paths. Neither is hand-written -- the kit's setup wizard writes them.

    git submodule update --init kit
    uv venv .venv
    uv pip install --python .venv/Scripts/python.exe pyyaml

**This target has no checks of its own any more.** `paslint` and `encaudit` were the last two and they are the kit's, on its list in [`kit/WORKING.md`](kit/WORKING.md) -- neither says anything about this demo, and both had a constant where a project's answer belonged. Moving `paslint` fixed a check that could not fail: its source directory was hardcoded, so in the sibling repository it reported *0 problems in 0 files* and passed. Run the kit's list and nothing else.

**The Pascal sources are LF on disk** despite the CRLF rule, because `.gitattributes` marks them `-text` and they were authored that way; Turbo Pascal reads them regardless. Do not "fix" this in bulk -- it would rewrite every source file for no measured gain.

## The state of this working tree, as of 23 Aug 2026

**Everything is committed and pushed on `vangelistracker-build`, the only open ticket is the finished kit map itself, and the one queue of work is the plan**: `.venv/Scripts/python.exe kit/tools/pascal/plan.py status.toml --report` — five investigations seeded defect-first, of which two are RESOLVED against watched live runs (22 Aug) and three remain: part5-386-trio (fixed in code, needs a TPART5 run), **pacing (the main line — `kit/tools/pascal/spans.py spans.toml 001` lists the divergent spans to work top-down)**, and part6-confirm-r3 (a careful run, no code). `docs/continuation.md`'s dated block has the full state.

The remote is private `sweetlilmre/PsychoNeurosis`, default branch `main`. **`main` is behind `vangelistracker-build`** and everything lives on the branch. History contains third-party bytes — `bin/NEUROSIS.008` and `work/split/NEUROSIS_008.exe` are DemoVT — acceptable only while the repo stays private, and a blocker on ever making it public. A lesson kept from an earlier version of this section: treat a "not mine" claim about tree contents as needing a check against the diff, not as fact.

**`docs/continuation.md` is the marker file for where to go next, and it is deliberately NOT tracked** — `.gitignore` excludes it. It is a local working register, it carries real local paths, and its content is nobody's deliverable. Read it first for the reconstruction job; its dated block at the top is current. Its tracked history to 19 Aug 2026 is in the log under its old name, `docs/24-continuation.md`.

**The old note about unaudited docs is retired**: `docs/README.md`'s index and status table were brought current and `docs/23-deviations.md`'s conflicting `asmverify` counts fixed on 22 Aug 2026. `docs/research/` remains inputs-not-conclusions per its own README, and the ledger audit ([#4](https://github.com/sweetlilmre/PsychoNeurosis/issues/4)) still says what to distrust in the older material.

## Working the knowledge base

It was a wayfinder map on GitHub Issues, and it is **finished**: 22 tickets, all closed, 23 Aug 2026.

**Its governing rule has expired, and that is worth knowing rather than deleting.** For most of the effort it was *copy and adjust, never refactor the originals* -- `tools/*` and the sibling repository's scripts kept working, untouched, while anything generic was copied into the kit and adapted there. That rule existed to make the migration safe, and it ended when the migration did: the originals it protected are archived under `archive/pre-kit-scripts`, and `docs/32-tool-disposition.md` says where each one went and what measurement justified deleting it. What is left in `tools/` is ten scripts kept deliberately -- this demo's data carvers, its harness generator -- and they are the record's, not candidates.

**What replaces it, for anything new:** a generic tool is BORN in `kit/tools`. Writing one beside the record and copying it later duplicates it from birth, which happened once and is why the rule is stated this way round.

## Standing rules for this target

**The method's rules are in [`kit/WORKING.md`](kit/WORKING.md)** -- the verbatim stance, *a measurement beats an argument*, *distrust the verifier before the transcription*, the encoding and line-ending table, prose never hard-wrapped, and the commit trailer. They moved there under [#30](https://github.com/sweetlilmre/PsychoNeurosis/issues/30) because a new target would carry every one of them unchanged. Read that file, not this section, for how to work.

What is left here is this demo's own:

- **Do not fetch period third-party binaries** (LZEXE and friends). That is the user's call.
- **`NEUROSIS.008` is not Asphyxia code.** It is DemoVT, third-party, and its reconstruction lives in the sibling repository. History here contains its bytes, which is acceptable only while this repo stays private and is a blocker on ever making it public.
- **A "not mine" claim about tree contents needs a check against the diff**, not agreement. That has been wrong before.

## This machine's toolchain

The traps that come with the tools a session is driven with -- the backslash halving, the slash-to-path rewriting, the multiplied line breaks -- are in [`kit/WORKING.md`](kit/WORKING.md) section 9, because a new project inherits every one of them.

**Where this machine keeps DOSBox-X, the drive C: image and each Turbo Pascal is answered by `kit.local.toml`, and this file no longer says.** It used to list all three and then assert in the next sentence that none of them may appear in a committed file, which was a contradiction anybody could read. Under [#35](https://github.com/sweetlilmre/PsychoNeurosis/issues/35) the last holders were emptied out: `dosbuild.py` carried them as constants and `tools/dosbox/psycho.conf` carried two of them as literals in a **committed** file. The DOSBox config is generated now, so the mount and the staging directory cannot disagree either.

    .venv/Scripts/python.exe kit/tools/pascal/build.py build.toml          everything
    .venv/Scripts/python.exe kit/tools/pascal/build.py build.toml TPART3   one harness and its units
    .venv/Scripts/python.exe kit/tools/pascal/build.py build.toml --selftest

`build.toml` is this target's build data -- the 8.3 name map, the switch line, what is staged alongside -- and it was GENERATED from `dosbuild.py` rather than transcribed. The switch line is the part to be careful with: `/$S-` does not fail when it is missing, it produces a build that measures wrong.
