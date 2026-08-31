# The documentation transform, as it actually ran

The companion to [`33-documentation-transform.md`](33-documentation-transform.md), which is the design. This is the record of carrying it out: what it cost, what the design got wrong, and what the next target should inherit instead of the estimates.

Twenty tickets, [#52](https://github.com/sweetlilmre/PsychoNeurosis/issues/52)'s map and #53–#72 beneath it, 1 Sep 2026. Every hand-written unit, all the shared assembler, the generated tables and the twenty-four harnesses.

## The destination, stated as a command and then run

    kit/tools/pascal/clean.py src src-clean --exclude asm/shared-exempt.txt
    kit/tools/pascal/build.py cleanbuild.toml
    kit/tools/pascal/artefact.py status.toml --check

**All ten artefacts hold at R7 from a build out of `src-clean` alone**, with `run/` emptied first so no stale executable could pass. That last part matters: building into a populated `run/` and then comparing has produced a clean-looking pass over the previous build's output twice in this project's history, so the run that counts is the one that starts with nothing there.

**`src-clean` is derived and regenerable.** Generated fresh into a scratch directory and compared file by file against what is committed: 85 files, 85 files, zero differing bytes. Nobody has hand-edited it, which was the standing question the effort was told not to close quietly.

## The count

Tree-wide `tagcheck` over all 84 source files: **0 problems in the stripped copy.**

The trend is worth more than the endpoint, and it needs one caveat stated first: **the number moves when the instruments move, not only when work is done.** `tagcheck` gained two checks during this effort and `clean.py` gained two rules, so every figure below is re-measured with the finished tools rather than quoted from the ticket that reported it.

| point | 48 files (`src/*.PAS`, `src/asm/*`) | all 84 (adds `src/gen`, `src/test`, `src/dos`) |
|---|---|---|
| before the pilot | 1,297 | 1,380 |
| after pilot #53 | 1,291 | 1,374 |
| after #59 (part 001 half done) | 938 | 1,021 |
| after #64 | 388 | 472 |
| after #67 | 160 | 244 |
| after #70 | 0 | 67 |
| after #71 | **0** | **0** |

**The design document's day-one figure of 1,388 across 48 files was measured with instruments that could not see part of the tree**, and the map's corrected 1,400 was measured before four later tool fixes. Both are superseded by the 1,297 above. The lesson is not that anybody miscounted — it is that a progress measure taken against a moving instrument has to be re-taken from the same starting point each time it is quoted, and that is cheap to do and easy to forget.

A second count ran alongside it and reached zero on the same schedule: `clean.py`'s own **"N comment(s) still mention an address — those need a person"**, which is the stripper's tally of what it could not decide alone. 58 → 47 → 34 → 20 → 8 → **0**. That one is the better health check of the two, because it counts judgements outstanding rather than paragraphs.

## Every expired premise, by name

The highest-value output of the transform, and the reason for logging them as they were found rather than reconstructing them from commit messages afterwards. **Eleven**, against the sibling target's fourteen.

Two classes, and the distinction is worth keeping. The first eight are claims in the project's own **documentation** that had stopped being true. The last three are claims in **this document's design** or in a ticket body — the effort's own paperwork going stale while the effort ran.

### In the project's documentation

1. **`CLAUDE.md`'s job table said the reconstruction was behavioural fidelity, not byte-exact.** Byte-exactness landed 27 Aug 2026 and is recorded in `status.toml`. Fixed in the pilot. *True when written.*
2. **`CLAUDE.md`'s state block said `main` was behind `vangelistracker-build`** and that the work lived on the branch. `main` was fast-forwarded 451 commits on 28 Aug. Fixed in the pilot. *True when written.*
3. **`CLAUDE.md` said "the Pascal sources are LF on disk"** — half the story. The hand-written sources are LF; the **generated includes under `src/gen` and `src/asm/COSTAB.INC` are CRLF**, because the emitters write them that way. Found in #70 by losing eight edits to it. Now recorded with its failure mode.
4. **`docs/22-part002-scene2.md` named `P2MODEX.PAS`** — the unit is `MODEX.PAS`.
5. **`docs/22-part002-scene2.md` named `P2FIX.PAS`** — the unit is `FIXMATH.PAS`.
6. **`docs/33` estimated `src/asm` at ~450 lines.** It is 1,146.
7. **`docs/33` estimated the part drivers at ~800 lines.** They are 1,199.
8. **`docs/33` said DemoVT's inputs are CRLF.** They are LF — the sibling's own `clean.py` defect had converted seven of them, which is how the claim came to be believed.

### In the effort's own paperwork

9. **The map's day-one baseline of 1,400** and **`docs/33`'s 1,388**, both superseded — see the table above.
10. **#66's ticket body warned that `P4LEMS` "had no `{$I-}` at all".** It has one, at line 54, and that directive's own comment records the defect being found and fixed. Read as written, the ticket sends the next session looking for a directive to add.
11. **The per-ticket tree-wide counts were measured over a narrower file set** (48 files) than the tickets covered (84), so the series was not comparable with its own baseline. Corrected on the map in #65, with both columns and a note on which one #72 had to drive to zero.

## The `[reading]` count

**Zero. The mark was never used.**

The design predicted the opposite — *"`[reading]` becomes the dominant mark, not a minor one"* — on the sound reasoning that this tree has no prior source and most explanatory claims rest on somebody's reading of the instructions. The reasoning was right and the prediction was wrong, for a reason nobody looked for: **this tree already had its own inference mark.** The reconstruction had been writing `[inferred]` (4 occurrences) and `[transcribed]` (13) since long before the transform, and a unit's author reaching for a way to flag an inference found one already in the file.

So the honest summary of the finished work is not "mostly inference, counted". It is: 1,025 paragraphs tagged `[re]` and removed, seventeen paragraphs carrying the tree's pre-existing inference marks, and no separate count of inference at all.

**That is a finding about marks, not about this tree.** Two marks were proposed at the pilot. `[demovt]` was rejected there, before use. `[reading]` was accepted and then never used — which is the same outcome, reached a thousand paragraphs later and without anybody noticing. A mark's cost is paid at the pilot; its value is only visible at the end.

## Did `[demovt]` earn its place?

**No, and rejecting it at the pilot was right.** The judgement is now available after the fact, which is what the ticket asked for.

The case for it was real: `src/DEMOVT.PAS` documents this demo's side of a seam whose other side is a *reconstruction*, and citing a reconstruction is not citing a source — those claims inherit the sibling tree's confidence, including its fourteen expired premises. A mark would let a reader tell.

What the finished unit shows is that the case never arose in volume. `DEMOVT.PAS` carries **one** citation of the sibling repository in 418 lines. The shipped artefacts — `DEMOVT.DOC`, `README.1ST`, the language bindings — are the author's own words and are primary, so nearly everything in that unit rests on a published document rather than on somebody else's reconstruction. One site does not earn a mark: a mark that fires once is a footnote with extra machinery, and every future reader has to learn what it means to discover it means "see that one paragraph".

**The general rule this suggests:** propose a mark only when you can point at the paragraphs it will cover, and count them. Both marks proposed here failed that test in opposite directions — one was rejected on it, one was not tested against it at all.

## The hazard table, with this run's hit counts

The design carried the sibling's table. This is the same table with what each item actually cost here, plus what is new.

| hazard | design's account | this run |
|---|---|---|
| **Rewriting a comment block** | the most expensive item; four times on the sibling, once destroying 52 measured addresses | **1**, caught before commit. A batch helper rewrote a comment on the *first* line matching its anchor, and the anchor was not unique — so it silently retexted a different routine's comment. Reverted and redone with every anchor asserting exactly one match. |
| **A comment edit that lands on a directive** | silent, both times | **3**, all caught by `braces.py`, none by anything else. The last was in #69: a header reading *"which is what the `{$F+}` below is for"* ended the comment at that directive's own closing brace, and the directive set dropped from seven to five — `{$F+}` and an include both gone. A build from that source compiles the whole unit **near**. It compiles clean, it links, and every address in the unit is wrong. |
| **Comments that do not nest** | three times on the sibling | same three events as the row above; on this tree the two hazards are one hazard. |
| **Shell heredocs and backslashes** | four times, once silently | **3**, and the last was inside the fix for the second. `\r\n` in a heredoc arrives as a real carriage return and line feed. The rule in the design — *any script containing a regex goes through a file, never a heredoc* — is right and is not enough: it needs to be **any script containing a backslash**. |
| **Editing a generated file** | `src/gen` exists in this tree | **0**, because the check was made first. #71's twenty-two harnesses are written by `tools/mktests.py` and were fixed **in the generator**; #70's tables were confirmed to be output-only before their headers were touched. This is the one row where the design's warning did its whole job. |
| **Bulk line-ending change** | new here: sources are LF, preserve what you found | **0** of the bulk kind, but the row was incomplete — see the new hazards below. |
| **Changing the kit** | two acts, never one; expect the pin to move several times | **4 pin moves** in the closing stretch alone, each with the sibling verified at 0 differing bytes *before* the pin moved. The two-act rule held every time and cost nothing but the discipline. |

### New hazards, found here

| hazard | how it showed |
|---|---|
| **A trim that cuts into a sentence** | The stripper removes a leading citation, which is right almost always — but prose wraps, and a citation can begin a line while sitting *inside* a sentence. `ColOfs is at` / `and 402 bytes long` shipped in the deliverable. **Nothing in the gate could see it**: no tell survives for the leak check, the stripper's self-check compares code and not comments, and the build passes. 11 cases in 9 files. Now a `tagcheck` check. |
| **An inert tag** | A tag is read at a paragraph *start*. One on a continuation line does nothing at all — the apparatus stays **and** the marker ships, reading as a typo in the documentation. 3 found, one of which had survived a closed ticket's gate. Now a `tagcheck` check. |
| **An anchor that matches a continuation line** | The two hazards above in one move: an edit inserted `[re]` mid-paragraph, making it inert and cutting the sentence. Both new checks reported it on the same run, one ticket after they landed. |
| **Two line-ending conventions in one tree** | Hand-written sources LF, generated includes CRLF. A multi-line anchor simply does not match, and fails **silently, one file at a time**. Eight edits lost in one batch, and the give-away was that the single-line anchors in the same batch all worked — a one-line anchor has no newline in it. |
| **All-or-nothing batch scripts** | An `assert` plus a single write at the end throws away every good edit in the run when one anchor misses. Cost three batches before the helpers were changed to warn and continue. |
| **An address list with the segment written once** | `{ DS:$BE90, $BE92 }` — the drop rule missed it, the prefix trim took the qualified half, and `{ $BE92 }` shipped as apparatus with the one token identifying it as apparatus removed. 11 in 4 files, and the residual-address report counted none of them. Fixed in `clean.py`. |

## What I would tell the next run

**Build the two silent-failure checks before the first unit, not after the sixth.** The design already says to write the brace-depth scan first, and that was done and paid for itself three times. The two checks written *during* this run — the inert tag and the cut sentence — each found damage that had already shipped past a closed gate. Both are about twenty lines. There is no reason they cannot be written on day one alongside the brace scan, and the day-one instrument set should be: brace depth, leak, inert tag, cut sentence.

**Do not build the automatic splitter.** I built it twice, on two different tickets, with different guards each time, and discarded it both times. The paragraph shape in some units is regular enough to tempt — claim, then address evidence — and the second attempt guarded against all three ways the first had failed. It still lost the case that matters: where the claim is a bare label and the *evidence half carries the documentation*, the split strips the useful sentence into the tagged part. `{ The two screens. VirtScrSeg (VGA, DS:$CF8C here) holds the hillside and is what GetPixel reads }` is the example. That judgement is not mechanisable and getting it wrong deletes prose from the deliverable.

**What is worth scripting is the shape pass**, and it should be the first act on every unit rather than something discovered mid-way. Six exact shapes — a routine headline with a citation in it, a section marker, a banner, a bare headline, a leading headline, an assembler trailing note — accounted for a fifth of some units and are pure rewording. Running it first turned a hundred-paragraph file into a twenty-paragraph one.

**Read the stripped copy.** Three defects in `clean.py` were found that way and by nothing else, including one it was silently reporting zero for. The instruments now cover two of the three classes; the third — a paragraph that is simply worse after stripping, with no tell to catch it — has no instrument and will not get one.

## The two standing questions

**Should `src-clean` stay?** Yes, and it should stay derived. It is regenerable to the byte, it builds, and it produces all ten artefacts. The moment somebody hand-edits it, it stops being a documentation copy and becomes a second source to keep in step — which is the arrangement the whole design exists to avoid.

**Should `clean.py` and `tagcheck.py` live on as gate tools, or was this a one-off?** They should live on, and the argument is not the tree-wide zero — it is that **three of this run's own defects were caught by an instrument and would have shipped otherwise**, and all three were mine, made during this effort, not inherited. A stale claim compiles; a leaked address compiles; a cut sentence compiles. Prose is the only part of a reconstruction no compiler reads, and these are the only two things that read it.

The narrower recommendation: `tagcheck` belongs in any target's day-one check list, because keep-by-default tagging is only safe while something watches for the new untagged comment. `clean.py` is worth running from the first unit for a different reason — its **"needs a person"** count is a live worklist of judgements outstanding, and watching that reach zero is a better signal of the effort finishing than the paragraph count is.

## See also

* [`33-documentation-transform.md`](33-documentation-transform.md) — the design this ran from
* [`kit/WORKING.md`](../kit/WORKING.md) — the method, and the session loop the gate sits inside
* [#52](https://github.com/sweetlilmre/PsychoNeurosis/issues/52) — the map, with the per-ticket record
