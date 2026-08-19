# Audit: what `tools/ledger.py` records today

Fact-finding only. No files were modified, no git commands run, no build started. Everything below was read from source or produced by running the tool.

## 1. What it is

`tools/ledger.py` (3.3 KB, last touched 16 Aug) is a **regex scraper over `src/*.PAS` comments**. It has no database, no config file, no build dependency and no contact with any binary. Its entire data model is derived, at run time, from three literal tags written by hand into Pascal comments:

```
{ [transcribed] 1012:0366 -- gather the working cell for bouncer N ... }
procedure BuildCell;
```

The scrape rule (`MARK`) is: a `{ ... }` comment containing `[transcribed]`, `[inferred]` or `[stub]`, whose closing brace is immediately followed by a `procedure` or `function` header. Anything not shaped like that is invisible to it.

### Fields per row — the complete data model

| field | source | notes |
|---|---|---|
| `unit` | filename, `.PAS` stripped | |
| `kind` | the tag: `transcribed` \| `inferred` \| `stub` | the only status axis; three values, mutually exclusive |
| `addr` | first `seg:off` or `FUN_xxxx_xxxx` found in the comment text | free text, never validated |
| `name` | last word of the routine header | not qualified, not unique |

That is all four fields. There is **no** evidence field, no date, no "checked by what means", no reference to a test, no reference to a binary, no per-part or per-scene grouping, no notion of behaviour vs. bytes.

Three derived reports are computed on top: `inferred` rows (called "UNVERIFIED"), routines with an empty body (`begin end;`, matched by a separate regex over the same files), and rows with no address recorded.

**Data provenance: 100% hand-maintained prose.** Nothing is derived from source structure, from the build, or from the original executables.

## 2. Actual output

`python tools/ledger.py` from `D:\source\psycho` — no arguments needed, no build artifact needed:

```
VERIFICATION LEDGER
--------------------------------------------------------------
  transcribed     17    94%
  inferred         0     0%
  stub             1     5%
  TOTAL           18
```

That is the whole output. The three follow-up sections printed nothing: **0 inferred rows, 0 empty bodies, 0 rows missing an address.** (The empty bodies the handover doc still lists — `PART4_LEMMINGS.DrawChar/Setup/SetupPeriodic`, `PART7_FLIC.ReferenceWork` — are genuinely gone; the only `begin end;` left anywhere in `src/` is inside a comment in `PART3_GLOBE.PAS`.)

`python tools/ledger.py --all` adds the full 18-row table:

```
  P1S1               transcribed   1012:0311      LoadLogo
  P1S1               transcribed   1012:0366      BuildCell
  P1S2               transcribed   1082:0000      Load
  P1S2               transcribed   1082:01d0      DrawRevealed
  P1S2               stub          1082:0200      DrawChar
  P1S3               transcribed   10e3:0206      MosaicRun
  P1S3               transcribed   10e3:0206      Scene3
  P1S4               transcribed   12b2:00c0      StarStep
  P1S4               transcribed   12b2:00f1      StarDraw
  P1S4               transcribed   1107:0245      DrawBlobs
  P1S4               transcribed   1107:0562      FrameStep
  P1S4               transcribed   1107:076e      BannerRun
  P1S5               transcribed   12c5:088b      LoadObject
  P1S5               transcribed   12c5:052a      DrawPoint
  P1S5               transcribed   12c5:061d      RenderObject
  P2S2               transcribed   108b:0b42      DrawStars
  PART3_BLOCKS       transcribed   11f3:0085      Ramp
  PART3_MORPH        transcribed   1139:034d      GetPalette768
```

## 3. Coverage, in numbers

- **317** routines are implemented across the **34** non-test units in `src/` (implementation-section `procedure`/`function` headers; 398 headers total including interface re-declarations).
- **18** ledger rows → **5.7%** of implemented routines. The "94% transcribed" figure is a percentage *of the 18 rows it found*, not of the reconstruction.
- **8** of 34 units carry any tag at all: `P1S1`, `P1S2`, `P1S3`, `P1S4`, `P1S5`, `P2S2`, `PART3_BLOCKS`, `PART3_MORPH`.
- **26** of 34 units carry **zero** ledger rows, including every shared unit (`VGA` 26 routines, `DEMOVT` 12, `MODEX` 4, `FIXMATH` 4, `P2VIEW` 8) and every unit of parts 004, 005, 006, 007.

### Coverage by part

| part | units | implemented routines | ledger rows |
|---|---|---|---|
| 000 | none — not reconstructed | 0 | 0 |
| 001 | P1S1–P1S5, P1INTRO | 56 | **15** |
| 002 | P2S1, P2S2, P2VIEW, P2MAIN (+MODEX, FIXMATH shared) | 52+8 | **1** (`P2S2.DrawStars`) |
| 003 | PART3_TUNNEL/STARS/MORPH/GLOBE/BLOCKS/WAVES/SPRITES, P3MAIN | 63 | **2** |
| 004 | PART4_LEMMINGS | 32 | **0** |
| 005 | P5S1–P5S3, P5MAIN | 23 | **0** |
| 006 | P6S1–P6S4, P6MAIN | 29 | **0** |
| 007 | P7S1, P7MAIN | 16 | **0** |
| 009 | none — not reconstructed | 0 | 0 |
| shared | VGA, DEMOVT | 38 | **0** |

The handover doc already states this: *"`tools/ledger.py` is blind to most of part 003 — those units carry almost no `[transcribed]`/`[inferred]`/`[stub]` markers, so its percentage never covered them"* (`docs/24-continuation.md`, l.383). The audit confirms the blindness is far wider than part 003: the ledger is effectively a part-001 artifact.

Parts **000** and **009** have no source files whatsoever, so they are not a ledger gap so much as absent from the repo (`docs/20-parts000-009-setup-and-end.md` is the only material).

## 4. Data quality of the 18 rows it does have

Three defects, all verified by re-running the regex directly:

1. **3 of the 18 rows are spurious.** `MARK`'s note group is `(.*?)` under DOTALL and may cross brace boundaries, so the *legend comment* in each of the P1S1/P1S2/P1S3 file headers ("Markers: `[transcribed]` read out of the binary, `[inferred]` implied by its call sites, `[stub]` signature only") matches, and is attributed to whatever routine happens to be declared next. Captured note lengths: **1030, 2427 and 1909 characters**. The address is then scavenged from unrelated intervening text.
   - `P1S1 LoadLogo 1012:0311` is wrong — `1012:0311` is `P1S1.SaveUnder`'s address per `asmverify`'s own marker.
   - `P1S2 Load 1082:0000` and `P1S3 MosaicRun 10e3:0206` come from the same over-capture. `10e3:0206` is then reported for *two* rows (`MosaicRun` and `Scene3`), which is the correct address for only one.
2. **The one remaining `[stub]` is stale.** `P1S2.DrawChar` is marked "signature only", but `src/P1S2.PAS:171` is a fully implemented two-loop glyph blitter with a 25-line derivation comment above it. So the headline "1 stub" is a false positive, and "0 inferred / 0 stubs / 0 empty bodies" is the true state of the tagged subset.
3. **Nothing cross-checks the address.** `addr` is free text lifted from prose; there is no validation that it exists in a binary, that it is unique, or that it belongs to the routine it is printed against. Defects 1 and 2 both survived because nothing does.

Net: **15 real rows, 3 spurious, 1 of the 15 mislabelled.** After correction the ledger records "transcribed" for 15 of 317 routines and nothing else.

## 5. Can it carry a graded per-routine fidelity rung as-is?

**No.** Precisely what is missing:

| requirement of a graded rung | ledger today |
|---|---|
| an ordered scale | absent — `kind` is a 3-value *nominal* set describing **how the code was produced** (read from binary / inferred from call sites / signature only), not how well it is *known to behave*. `transcribed` and `stub` are not two ends of one axis. |
| an evidence field | absent — no field records what was done to check the routine |
| a means-of-verification field | absent — the docstring calls `transcribed` "read out of the binary", but nothing distinguishes read-by-eye from byte-diffed |
| a link to a test | absent — no reference to any `TP*` harness |
| stable identity | weak — `name` only, unqualified; `PART4_LEMMINGS.Blit` and `P6S2.Blit`, and four separate `SetPalette768`/`GetPalette768`, collide on name |
| a regression lock | absent — nothing fails, nothing is compared to a previous run; the only "regression" concept in the repo lives in `asmverify.py` |
| completeness | absent — a routine with no tag is not "unknown", it is *not in the ledger at all*. 299 of 317 routines are silently outside it. |
| grouping by part/scene | absent — `unit` is the only grouping, and it is a filename |

Extending it to carry graded status would require, as fact: (a) an ordered rung enumeration replacing or layering over `kind`; (b) an evidence/means field per routine; (c) qualified `unit.name` keys; (d) an enumeration of *all* routines so untagged ones appear at rung zero rather than vanishing; (e) validated addresses; (f) fixing the DOTALL over-capture in `MARK` and the stale-tag problem, or moving off comment-scraping entirely. A comment-scrape source can supply (a)–(c) with a richer marker syntax, but (d) needs a routine enumerator (which the scan loop does not currently have — it only looks at tagged comments) and (e) needs the binaries.

## 6. The other acceptance machinery, and how each relates

All read-only tools were run. `run/` already contains built harnesses (43 `.EXE`, `TP1S1`…`TPART7` plus `ORIG0..9.EXE` copies of the 1994 binaries) and `work/split/` contains the unpacked `NEUROSIS_00x.exe`, so **no build was needed**.

### `tools/asmverify.py` — **the strongest artifact in the repo; overlaps the ledger and dominates it**

Ran clean, ~1s:

```
71 routine(s): 71 locked, 0 not locked, 0 unconfirmed, 0 failing.
```

Independent marker convention — `{ @asm 004 1005:0328 }` above the header, optional `+len` for a fragment, optional `?` for an unconfirmed address. **73 markers** across **18 units**; 3 carry `?`. It loads the original from `work/split/`, finds the routine in a built `TP*.EXE`, walks it byte for byte to the return, tolerates 1–2-byte runs as DGROUP displacement holes, and treats 3+ differing bytes as divergence. Matched lengths are locked in an `EXPECTED` dict (71 entries) so a shortened match **fails the run** — the only regression gate in the project.

Coverage: **71 routines = 22.4% of the 317**, spanning parts 001–007 and the shared units — i.e. four times the ledger's reach and far better distributed. Its evidence is a byte count and a hole count per routine, which is exactly the kind of graded evidence the ledger lacks. Its scope limit is real and stated: it only covers routines that are **assembler end to end** (or declared fragments). Routines that are compiled Pascal — the majority — have no byte comparison to make and are outside it by construction.

Where the two overlap they **disagree**: `asmverify` puts `1012:0311` at `P1S1.SaveUnder`; the ledger prints it against `LoadLogo`. `asmverify` is right (its marker is machine-parsed and address-checked against the binary).

### `tools/asmaudit.py` — complementary, style-rule only

```
12 unit(s) meet the rule, 39 do not.
```

Checks two of the three transcription rules mechanically (a comment on every asm line; an `EQUIVALENT PASCAL` block within 50 lines above). Its own docstring is explicit that it cannot check rule 1 and that "a unit passing this is not the same as a unit that has been audited". Unit-level, not routine-level, so it cannot host a per-routine rung. Two caveats on the 39: (i) 12 of them are generated test harnesses (`TP*.PAS`, all flagged for the same `RestoreTextMode` line 22 — an artifact of `mktests.py`, not reconstruction debt), leaving **10 real units failing**: `P5S1`, `P5S2`, `P6S1`, `P6S2`, `P6S3`, `P6S4`, `P7MAIN`, `P7S1`, `PART3_BLOCKS`, `PART4_LEMMINGS`; (ii) most of its "uncommented" hits are asm **labels** (`@Sort:`, `@LeftTop:`) rather than instructions, so its counts overstate. Note `PART3_BLOCKS` now fails, which contradicts `docs/24-continuation.md` l.56 ("every unit [in part 003] now passes `tools/asmaudit.py`").

### `tools/undeclared.py` — unrelated to fidelity

Crude compile-error work list: identifiers used but never declared, per unit. Over-reports by design (it flags unit names like `VGA`, `Crt`, `DemoVT` as undeclared). Says nothing about whether a routine matches the original.

### `tools/paslint.py` — unrelated to fidelity, currently clean

`0 problem(s) in 63 file(s)`. Catches TP7 traps (non-nesting braces, reserved words, `Mem[DSeg:$XXXX]`). `dosbuild.py` runs it as a gate.

### `tools/mktests.py` — complementary, and the only *behavioural* axis

Generates 29 harnesses: 23 scene programs (`TP1S1`–`TP1S5`, `TP2S1`–`TP2S2`, `TP3S1`–`TP3S7`, `TP4S1`, `TP5S1`–`TP5S3`, `TP6S1`–`TP6S4`, `TP7S1`) and 6 part programs (`TPART1,2,3,5,6,7` — no `TPART4` by design, part 004 is single-scene and its harness stands in for the driver). Every one of the 29 is present in `src/` and 29 corresponding `.EXE` are in `run/`. Not run in this audit — they require DOSBox and a human eye. **Granularity is the scene, not the routine**, and pass/fail is a human watching the screen; there is no recorded result anywhere in the repo, so a scene's behavioural status lives only in the prose of `docs/24-continuation.md`.

### `docs/23-deviations.md` — complementary; the qualitative counterpart

16 KB, 13 sections, prose. Records deliberate divergences (verbatim-asm framing, `PART3_MORPH.FadeStep` running off both ends of its buffer, computed shape offsets, `{$G+}`, stack checking off, part 007 `{$I-}`, the TASM 386 object). Section "Every transcribed assembler routine is byte-checked" is the human narrative of `asmverify`, and it is **already stale in one number** — it quotes `56 routine(s): 55 locked … 1 unconfirmed` in one paragraph and the current `71 routines, 71 locked, 0 failing` two paragraphs later. Deviations are indexed by topic, not by routine, so you cannot ask it "is routine X's difference intended?" without reading all of it.

### `docs/24-continuation.md` — the actual state of record, at part granularity

23 KB. Its state table is the closest thing to a status register the project has, and it is **per part**, not per routine:

- 001 — scenes 1–5 tested and working; audit done, 5 routines back to verbatim, **needs a retest**
- 002 — both scenes tested and working; audit done, 22 routines back to verbatim, **needs a retest**
- 003 — **audit done**, every unit passes `asmaudit`; S1, S3, S4, S5 confirmed working; S2 and S7 rewritten from the binary, building, **neither re-run**
- 004 — fully transcribed, no stubs, nothing inferred; `TP4S1` builds, **not yet run**
- 005–007 — "single files, never run, no harnesses. The remaining stubs, inferred routines and empty bodies live here."

Two of those statements are now out of date: 005–007 **do** have harnesses and scene splits (`P5S1`–`P5S3`, `P6S1`–`P6S4`, `P7S1` with `TP5S*`, `TP6S*`, `TP7S1` built in `run/`), and the stubs/inferred/empty bodies it lists there are gone — the ledger, `asmverify` and a direct search all report zero. So the doc's "part 003 is audited, the rest are not" framing predates the 005–007 work now in the tree.

## 7. Is there any single artifact that answers "for routine X, how confident are we, and on what evidence?"

**No.** Confidence for any given routine is assembled by hand from four disjoint sources, each at a different granularity, none of which cites the others:

| source | granularity | axis | coverage |
|---|---|---|---|
| `asmverify.py` | routine | **bytes** identical to original | 71 / 317 (asm-only) |
| `ledger.py` | routine | how it was *produced* | 18 / 317 (part 001 mostly), 3 rows spurious |
| `docs/24-continuation.md` | part / scene | **observed behaviour** | all parts, prose, partly stale |
| `docs/23-deviations.md` | topic | intended divergence | 13 topics, prose |

The closest single thing is **`asmverify.py`**: it is routine-level, machine-checked against the 1994 bytes, carries quantitative evidence (bytes matched, displacement holes, which harness it was found in), and regresses loudly. What it lacks: it covers only end-to-end assembler (78% of routines are out of scope by construction), it says nothing about *behaviour* — a byte-identical routine fed the wrong arguments still looks perfect — it has one boolean outcome (locked/not/unconfirmed/failing) rather than a rung, and its `EXPECTED` numbers are the *only* recorded verification result in the repo, with no equivalent for compiled Pascal.

For the 246 routines outside `asmverify`'s scope there is **no per-routine record of any kind** — the best available evidence is a sentence about the scene they live in, in a handover doc.

## 8. Facts a routine-level plan would need to account for

- 317 implemented routines, 34 non-test units, parts 001–007; parts 000 and 009 have no source at all.
- Ledger reach: 18 rows / 8 units / 5.7% — and 3 rows are regex artifacts, 1 tag is stale.
- `asmverify` reach: 71 routines / 18 units / 22.4%, all green, all locked.
- 246 routines (77.6%) have no machine-checkable status of any kind today.
- Address annotations, unlike ledger tags, are **already everywhere**: ~3,000 `seg:off` references across all 34 units, every unit carrying some. The per-routine address data a fuller ledger would need largely exists in the comments; it is the *status* vocabulary that is confined to part 001.
- Two independent marker conventions coexist in the same files (`[transcribed]` for the ledger, `{ @asm … }` for `asmverify`) and they disagree about at least one address.
- Behavioural evidence exists only as 29 build-and-watch harnesses with no recorded outcomes.
