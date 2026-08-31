# The documentation transform: `src` into `src-clean`

**Read [`kit/WORKING.md`](../kit/WORKING.md) first.** This document assumes it and does not repeat it — not the verbatim-assembler stance, not *a measurement beats an argument*, not the encoding table, not the commit trailer, not the two-act rule for changing the kit. What is here is only the shape of this one job on this one tree.

**The evidence base is the sibling repository.** The method was built and run to completion on DemoVT — 34 units, 30 commits, `VangeliSTracker/v1.51/docs/09-documentation-transform.md`. That document records what it cost and what it found; this one records how it lands here. Where the two disagree, this one is about this target and wins.

## The destination

**`src-clean` is a documented source, not a stripped one.**

The reconstruction's source answers *how do we know this byte is right* — segment addresses, frame sizes, which instrument caught what, what was measured against the original. A reader wants to know *what the demo does*: what a scene is, why a routine exists, why the arithmetic is shaped that way. Both answers live in the same comments today, and no single copy serves both audiences.

So `src-clean` is `src` with the reverse-engineering apparatus removed and explanatory documentation put in its place. It is **derived and regenerable**, never hand-edited, and it must still build byte-identical.

What that means concretely, per `kit/WORKING.md`'s own audience test:

* **Every routine gets a header** whose first sentence says what it is *for*. No routine left bare, so a missing header never reads as "not done yet". Trivial ones get one obvious line and are allowed to be obvious.
* **Inline notes where the mechanism is genuinely non-obvious** — a fixed-point convention, a plane-select order, a table's units.
* **Every assembler block gets an equivalent-Pascal block above it, labelled reference only, and per-line documentation.** That is the standing rule and it is not relaxed here. The transform does not re-express hand-written assembler; it explains it.
* Written for a competent DOS/Pascal programmer meeting this demo for the first time. Nothing explains what `PUSH` does. The reconstruction's history stays in `src`.

## What this tree brings to it

### The gate already exists, and it is stronger than DemoVT's

Ten `[artefact.*]` rows hold at **R7 — byte-identical, 301,328 of 301,328 bytes**, tagged `milestone/all-ten-byte-identical` on 27 Aug 2026. `ratchet.py` refuses to let any of them fall.

That is the load-bearing check for this whole job, and it is worth being explicit about why: **four of the transform's recorded hazards are code changes made while editing a comment.** Two of those produced no diagnostic of any kind, because both were comment edits that accidentally created or destroyed a **compiler directive** — `{ [re] $G+}` is 286 codegen silently off; a trimmed prefix leaving `{$FFFF ... }` is far calls silently on. Both compile clean and change every byte downstream.

So the rule for this tree is: **a unit is not done until the ratchet still reports R7 on every artefact that unit is linked into.** Not at the end of the effort — per unit, in the gate below.

### And the ratchet's own blind spot is the reason the checker exists

The ratchet compares products. It says nothing about whether a comment still means what it says, because nothing does: **prose is the only part of a reconstruction no instrument reads.** Fourteen claims inside DemoVT's `src` had stopped being true, and every one was found by rewriting a header — never by a tool, because a stale claim compiles.

**Two are already visible in this tree, before a single unit is touched.** `CLAUDE.md`'s job table says the reconstruction is *"behavioural fidelity, not byte-exact"*, and its state block is dated 23 Aug; byte-exactness landed on the 27th and is recorded in `status.toml`. The same block says `main` is behind `vangelistracker-build`; `main` is current and clean. Neither is a mistake anybody made — both were true when written. That is exactly the failure mode, and it is sitting in the file a fresh session reads first.

Fixing those two is the pilot ticket's first act, not a separate errand.

### What this tree lacks, and what stands in for it

**There is no prior source.** DemoVT had the 1.39b release: it supplied routine names, field names, types, and 397 of the author's own comments, which turned out to be the best explanatory content in that tree — all of it free. None of that exists here.

Consequences, and they change how the work reads rather than how it runs:

* **`[reading]` becomes the dominant mark, not a minor one.** Most explanatory claims here rest on somebody's reading of the instructions plus the behaviour of a live run. That is fine — it is what the mark is for — but it means the honest summary of a finished unit is "mostly inference, counted", and the count belongs in the commit message from the first unit onward.
* **Names are provisional for longer.** They come from call sites, string literals, the asset map in `docs/04-neurosis-dat.md`, the scene documents `06`–`20`, hardware and format conventions, and behaviour. Not from a source.
* **The scene documents are the richest source this tree has.** Thirteen of them describe what each effect *is* — Mode-X panning, integer 3-D, precomputed sphere maps, block dissolve against a ramp. That is exactly the material a purpose-first header needs, and it is already written. Read the scene document before writing headers for its unit; do not re-derive what `docs/12-part3-scene6-waves.md` already says.

**The one exception is the player interface.** `src/DEMOVT.PAS` (418 lines) is this demo's side of a seam whose other side is now fully documented in the sibling repository — the INT 2Fh control block, the semaphores, the `8xx` ring-event channel by which the music drives the visuals. For that unit and only that unit:

* `DEMOVT15/DEMOVT.DOC`, `README.1ST` and the `ASM`/`C`/`BCC4`/`PMODE` bindings are **shipped artefacts** — the author's own words about the published interface, and primary.
* The sibling repository's `v1.51/src/PLAYMOD.PAS` and `VTCTRL` document the player's side. **Citing a reconstruction is not citing a source**: those claims inherit that tree's confidence, including its fourteen expired premises. Mark them so a reader can tell — see the marks below.

Nothing else in this tree needs the player at all.

## The marks

Three, and the third is a decision this effort has to make in its first ticket rather than drift into.

| mark | means | fate |
|---|---|---|
| `[re]` | Reconstruction apparatus: an address, a frame size, an instrument's verdict, a comparison against the original, transcription history. | **Stripped** |
| `[reading]` | A claim resting only on a reading of the instructions or a watched run. | **Kept** — so a reader tells a measured fact from an inference at a glance, and so inferences stay countable |
| `[demovt]` | A claim about the player interface resting on the sibling *reconstruction* rather than on `DEMOVT.DOC`. | **Kept**, and visibly one step less firm |

`[demovt]` is proposed, not settled. The alternative is to allow only `DEMOVT.DOC` and the bindings as sources for `DEMOVT.PAS` and to tag anything beyond them `[reading]` like everything else. Decide it in the pilot ticket; retrofitting the distinction later is not possible.

### The grain

**The stripper and the checker must agree on where a paragraph begins and ends**, or the checker reports something the stripper will not remove. This tree has both grains DemoVT had:

| | grain | a tag carries |
|---|---|---|
| Pascal `{ }` | blank-line separated paragraphs | its own *indented* continuations |
| Assembler `;` | a run of comment lines | until a bare `;` ends the run |

**Enumerate where this tree's comment syntax overlaps its directive syntax before writing a single tag.** That overlap is where the silent failures live. `{$I ...}`, `{$G+}`, `{$L ...}`, `{$F+}` and the `$IFDEF` family all begin with a brace this transform is about to edit; in the `.ASM` files it is the `;` comment against TASM's conditional and macro directives.

## The gate, run once per ticket

`kit/WORKING.md` section 2a is the session loop; this is the extra gate the transform adds inside it. Every step is mechanical except the first two, and those two are where the value is.

1. **Rewrite every header in the batch purpose-first.** First sentence says what the thing is *for*. Read the unit's scene document first.
2. **Tag the apparatus — extend, never replace.** Carry the text you found into a tagged paragraph **verbatim**. Rewriting a block is how measurements get deleted; that happened four times on DemoVT, once destroying 52 measured addresses at a stroke.
3. **Scan for comment syntax the compiler will not warn about.** Pascal `{ }` do not nest. A brace-depth pass over the file, not a careful read.
4. **Regenerate the derived tree** — `clean.py src src-clean`, which verifies not one line of code differs.
5. **`tagcheck.py` clean on the batch** — 0 untagged paragraphs carrying apparatus.
6. **Build both trees** — `build.toml` and `cleanbuild.toml`, separately.
7. **`ratchet.py` reports R7 on every affected artefact, from both builds.** This is the check that reads what the compiler read.
8. **Commit the batch, push, and close the ticket with what you learned** — including any expired premise the pass turned up, by name.

    .venv/Scripts/python.exe kit/tools/pascal/clean.py src src-clean
    .venv/Scripts/python.exe kit/tools/pascal/tagcheck.py src-clean/<unit>
    .venv/Scripts/python.exe kit/tools/pascal/build.py build.toml
    .venv/Scripts/python.exe kit/tools/pascal/build.py cleanbuild.toml
    .venv/Scripts/python.exe kit/tools/pascal/ratchet.py status.toml

### Four things to settle before the first unit, not during it

Measured 31 Aug 2026. The first two are **kit defects and block everything**; both are backward-safe to fix, because this tree's shape is the one the kit has not met before.

**1. `clean.py` is flat, and silently so.** Its loop is `for f in sorted(src.iterdir())` with `if not f.is_file(): continue` — so `src/asm`, `src/gen`, `src/dos` and `src/test` are not copied at all, and nothing says so. A clean build from today's `src-clean` would have no assembler and no includes. DemoVT's `src` is flat, which is why this has never shown. Recursing with relative paths preserved is a no-op there.

**2. `clean.py` forces CRLF on output** — its final write is `new.replace(chr(10), chr(13) + chr(10))`, applied unconditionally. These sources are **LF** on disk, because `.gitattributes` marks them `-text`. So `src-clean` would differ from `src` by line ending in every file, making every diff between the two trees noise. Preserving what each input had is again a no-op for DemoVT, whose inputs are CRLF.

Both are `re-kit` changes, so both are **two acts** per `kit/WORKING.md`: commit in the submodule, then move this repo's pin — and re-verify the sibling tree still regenerates and still builds byte-identical before the pin moves.

**3. The three non-source subdirectories need three different answers.** This is a decision, not a lookup, and it wants a `wayfinder:grilling` ticket before any batching:

| | | |
|---|---|---|
| `src/asm` | 4 `.ASM`, 4 `.INC`, ~450 lines | **In scope.** Hand-written assembler, so the verbatim rule and the equivalent-Pascal requirement apply in full. Ticket 2. |
| `src/gen` | 12 `.INC`, **4,622 lines** | Generated data tables — vector objects, shapes, sine tables, cell maps. Almost certainly **copied verbatim with one header each** saying what the table is and which carver in `tools/` writes it. Documenting 4,622 lines of coordinates per line would be absurd; leaving them undocumented and unexplained would not. |
| `src/test` | 24 `.PAS`, **2,504 lines** | The per-scene harnesses. Not part of any of the ten artefacts, so **out of scope for the destination** — but they are the thing a reader runs to see one scene, which is an argument for a final low-priority ticket rather than exclusion. |
| `src/dos` | 1 `.BAT` | Verbatim. |

**4. `cleanbuild.toml` does not exist yet**, and cannot be written until 3 is decided. It is `build.toml` with `src = "src-clean"` — *and every other path that names `src` rewritten*: `[stage] alongside`, `verbatim = ["src/asm"]`, and `[stage.subdirs] GEN = "src/gen"`. Miss one and the clean build silently stages the **original** sources for that group and passes.

### The day-one number

    tagcheck src/*.PAS src/asm/*.ASM src/asm/*.INC
    → 1388 untagged paragraph(s) carry apparatus across 48 file(s)

**1,388, measured 31 Aug 2026, before any unit was touched.** Put it in the map. DemoVT's equivalent was 885 across 34 files and going 885 → 0 was the only honest progress measure in that whole effort.

## The work is a wayfinder map and its tickets

This effort is run the way every effort in this repository is run: **one map issue, and sub-issues beneath it, worked one per session until the frontier is empty.** The map is the continuation document — a fresh session reads the map, not this file, to find out where the work has got to.

### 1. Write the map first

Open one issue labelled `wayfinder:map`, titled for the destination rather than the activity — *"`src-clean` becomes a documented source"*. Its body carries, in this order:

* **Destination.** One paragraph a person can test the effort against. Suggested: *`src-clean` builds byte-identical from every one of the ten artefacts, `tagcheck` reports zero untagged paragraphs carrying apparatus across the whole tree, and every routine in it has a header whose first sentence says what the routine is for.*
* **Notes — the standing ground this map does not revisit.** The marks and their fates; the grain; `[demovt]`'s resolution once taken; the decision that `src-clean` stays derived; the three pre-flight items above once settled. Anything relitigated twice belongs here.
* **The decision index.** One line per settled call, linking the ticket that holds its measurements. This is what stops a later session reopening a closed argument.
* **The frontier.** The open, unblocked children. Kept current as tickets close.
* **What a fresh session cannot see from the map** — the pre-flight state, which units are done, the current tree-wide `tagcheck` count.

**Record the tree-wide `tagcheck` count in the map before the first unit.** On DemoVT it went 885 → 0, and it was the only honest progress measure in the whole exercise; every other signal was self-reported. Without a day-one number there is nothing to measure against.

### 2. Write up every ticket before working any of them

Write the whole set up front, not one at a time. The batching is a design decision — it decides how much rework a wrong convention costs — and it wants to be visible and arguable in one place before anybody starts.

Label by kind, as this repository already does: `wayfinder:task` for the unit batches, `wayfinder:grilling` for anything needing a decision with the maintainer, `wayfinder:research` for a fact somebody must go and find.

Each ticket body states: the units in the batch, their scene documents, which artefacts they are linked into (so the gate knows what to check), and its own acceptance test — which for a unit batch is always the gate above.

    gh issue create --label wayfinder:map \
      --title "src-clean becomes a documented source" --body-file <path>

    gh issue create --label wayfinder:task \
      --title "Pilot: DETECT and PSYCHO, and the convention they settle" --body-file <path>

Attach each ticket to the map as a **native sub-issue**, which is what this repository uses — `gh issue view 50 --json parent` resolves to #29 today. `gh` has no first-class command, so:

    gh api graphql -f query='
      mutation($map:ID!,$child:ID!){
        addSubIssue(input:{issueId:$map, subIssueId:$child}){ issue { number } }
      }' -f map=<map node id> -f child=<child node id>

Node ids come from `gh issue view <n> --json id -q .id`. If the mutation is unavailable, fall back to a task list in the map body — but prefer the real relationship, because it is what the frontier is read from.

### 3. Then work them, one per session, until the frontier is empty

**Order is the one thing that matters here.** Two small self-contained units *first*, to settle the tag convention and the header voice against something cheap — then **stop and review with the maintainer before touching anything large.** Getting the convention wrong on `P2SOLID` costs 2,668 lines of rework. On DemoVT both pilots took under an hour and the largest unit took three passes and two commits.

Suggested batching, 14 tickets:

| # | ticket | units | lines |
|---|---|---|---|
| 1 | **Pilot**, then review | `DETECT`, `PSYCHO` | 99 |
| 2 | The shared assembler | `src/asm` — 4 `.ASM`, 4 `.INC` | ~450 |
| 3 | The graphics and maths substrate | `VGA`, `MODEX`, `FIXMATH` | — |
| 4 | The player interface | `DEMOVT` | 418 |
| 5 | The part drivers | `NEUR0`–`NEUR9` | ~800 |
| 6 | Part 001 | `P1BALLS`, `P1LOGO`, `P1MOSAIC`, `P1STAR`, `P1TITLE`, `P1VECTOR` | — |
| 7 | Part 002 | `P2GARAGE`, `P2VIEW` | — |
| 8 | Part 002 — solid 3-D | `P2SOLID` | 2,668 |
| 9 | Part 003 | `P3BLOCKS`, `P3GLOBE`, `P3SPRITE`, `P3STARS`, `P3TUNNEL`, `P3WAVES` | — |
| 10 | Part 003 — morph | `P3MORPH` | 1,378 |
| 11 | Part 004 | `P4LEMS` | 1,998 |
| 12 | Part 005 | `P5MESH`, `P5PATCH`, `P5ROTO` | — |
| 13 | Parts 006 and 007 | `P6*` ×4, `P7FLIC` | — |
| 14 | Close-out | tree-wide `tagcheck` 0, all ten artefacts R7 from both trees, the write-up | — |

The three largest units get their own tickets because a ticket is meant to be one session.

**Ticket 14 is not bookkeeping.** It is where the tree-wide count is driven to zero, where the whole-tree build is run from `src-clean` alone, and where the effort's own write-up is added to `docs/` — the equivalent of the document you are reading, for whoever runs this on the next target.

## Hazards

The full table with hit counts is in the sibling document. These are the ones that apply here, plus the ones that are new to this tree.

| hazard | how it showed, and the fix |
|---|---|
| **Rewriting a comment block** | Deleted 52 measured addresses at a stroke by replacing prose instead of extending it; then three more times. **Fix:** append; carry found text verbatim into a tagged paragraph. The most expensive item on the list, and language-independent. |
| **A comment edit that lands on a directive** | Silent, both times. **Fix:** any tool that inserts into a comment refuses a line opening `{$`, and requires its insertion point to be inside a comment by *brace depth*, not by "the line contains a brace". |
| **Comments that do not nest** | A `{ }` inside a `{ }` in an equivalent-Pascal block, three times. Caught by a brace-depth scan; never by reading. |
| **Shell heredocs and backslashes** | Four times, once **silently**: `\b` became a literal `\x08`, the pattern compiled, and matched nothing forever. **Fix:** any script containing a regex goes through a file, never a heredoc. |
| **Editing a generated file** | `src/gen` exists in this tree. Find out what writes it *before* editing anything under it, and edit the generator and its outputs in one commit. |
| **Bulk line-ending change** | New here: sources are LF by `.gitattributes`, and a careless tool will rewrite every source in the tree. Preserve what you found. |
| **Changing the kit** | The kit is a submodule. Per `kit/WORKING.md` that is **two acts, never one** — commit in `re-kit`, then move this repo's pin. `clean.py` and `tagcheck.py` will both need work during this effort; expect the pin to move several times. |

## What to do differently, from the last run

* **Write the two guards before the first unit.** The brace-depth scan and the insertion guard each exist because something broke first. Both are twenty lines.
* **Record the tree-wide `tagcheck` count on day one**, in the map.
* **Log expired premises as a deliverable, from the first ticket.** Counting began at four last time and the earlier ones had to be reconstructed from commit messages. They are the highest-value output of the transform — this tree already has two, in `CLAUDE.md` — and they deserve a list in the map, not a mention in a commit body.
* **Keep the pilot-then-review rule.** It was written down in advance, it felt like a delay, and it is why the large units went through in one pass each.

## See also

* [`kit/WORKING.md`](../kit/WORKING.md) — the method, and the session loop this gate sits inside
* `VangeliSTracker/v1.51/docs/09-documentation-transform.md` — the completed run: what it cost, all fourteen expired premises, the full hazard table
* `VangeliSTracker/v1.51/docs/adr/0001-documented-source.md` — the design, as first proposed
* [`kit/wiki/observations/comments-are-unchecked-claims`](../kit/wiki/observations/comments-are-unchecked-claims/observation.md) — why prose rots, and what can be checked mechanically
* [`docs/README.md`](README.md) — the scene documents, which are what a purpose-first header is built from
