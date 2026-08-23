# The tool disposition

Where every script goes, and why. The working document behind [Consolidate and prune the tools](https://github.com/sweetlilmre/PsychoNeurosis/issues/17) and the four execution tickets that read from it: [one compare tool](https://github.com/sweetlilmre/PsychoNeurosis/issues/33), [the blocks family](https://github.com/sweetlilmre/PsychoNeurosis/issues/34), [one build harness](https://github.com/sweetlilmre/PsychoNeurosis/issues/35), [the archive](https://github.com/sweetlilmre/PsychoNeurosis/issues/36).

**This file is generated and PROVEN complete.** The generator refuses to write it if any script on disk has no disposition, or any disposition names a script that is not there -- the same both-directions rule `census.py` enforces, because a migration table that quietly omits a script is how the last inventory went stale.

**The test for which side a script falls on** is the map's: would it have to be edited to serve a different binary? Then it is the record's. A tool that is generic in shape but knows one target's facts moves to the kit and the facts move to the answers file -- it does not stay behind for being impure.


## Into the kit, beside the tiers

| script | where | why |
|---|---|---|
| `census.py`  **(both repos)** | kit/tools/ | the retirement census itself; retires with the migration |
| `encaudit.py`  **(both repos)** | kit/tools/ | text I/O that leaves the encoding to the locale; ONE copy |
| `project.py` | kit/tools/ | the answers reader; arrived 23 Aug |
| `repairdoc.py` | kit/tools/ | multiplied line breaks; nothing project-specific |

## Into the kit, substrate tier -- DOS and 16-bit binaries

| script | where | why |
|---|---|---|
| `align.py` | kit/tools/substrate/ | the coverage differ; the compare tools merge INTO it |
| `modex.py` | kit/tools/substrate/ | de-interleave Mode-X planes; VGA, not Pascal |
| `mzinfo.py` | kit/tools/substrate/ | MZ headers; says nothing about Pascal |
| `probe.py`  **(both repos)** | kit/tools/substrate/fingerprint.py | RENAMED. Packers and appended payloads. The other probe.py is a different tool entirely |
| `segmap.py` | kit/tools/substrate/ | real-mode segment layout from the fixups |
| `split.py` | kit/tools/substrate/ | MZ image plus appended payload |
| `strings.py` | kit/tools/substrate/ | printable strings, image-restricted |
| `symbols.py` | kit/tools/substrate/ | the 0x52FB name pools |
| `tddump.py` | kit/tools/substrate/ | Borland debug info, decoded whole |
| `unlzexe.py`  **(both repos)** | kit/tools/substrate/ | LZEXE 0.91; ONE copy, both repos have it |

## Into the kit, Pascal tier -- true only of Borland Pascal

| script | where | why |
|---|---|---|
| `artefact.py` | kit/tools/pascal/ | the artefact tier |
| `asmaudit.py` | kit/tools/pascal/ | two of the three transcription rules |
| `coverage.py` | kit/tools/pascal/ | byte-exact coverage from the tree |
| `dgroup.py` | kit/tools/pascal/ | compare the initialised DGROUP image |
| `linkorder.py` | kit/tools/pascal/ | predict link order from the `uses` graph |
| `mapcmp.py` | kit/tools/pascal/ | compare .MAP segment lengths |
| `markers.py` | kit/tools/pascal/ | reads the markers, measures coverage |
| `observe.py` | kit/tools/pascal/ | records a run somebody made |
| `paslint.py`  **(both repos)** | kit/tools/pascal/ | Pascal source defects; ONE copy |
| `plan.py` | kit/tools/pascal/ | the plan |
| `ratchet.py` | kit/tools/pascal/ | the ratchet |
| `register.py` | kit/tools/pascal/ | the register's one serializer |
| `shared_asm.py` | kit/tools/pascal/ | assembler duplicated between units |
| `undeclared.py` | kit/tools/pascal/ | identifiers a unit uses but never declares |

## Into the kit, wikitools -- looking after the wiki

| script | where | why |
|---|---|---|
| `glossary.py` | kit/tools/wikitools/ | the _Avoid_ lists as a check |
| `kbprofile.py` | kit/tools/wikitools/ | our profile, and the generators |
| `okfcheck.py` | kit/tools/wikitools/ | OKF conformance, no project facts |

## Merges: 23 scripts become 6 tools

| script | where | why |
|---|---|---|
| `asmcheck.py` | MERGE -> substrate/align.py | rule: what the .OBJ records as a relocation |
| `asmverify.py` | MERGE -> substrate/align.py | rule: an isolated 1-2 byte run. Its EXPECTED lock moves to the register |
| `block14b9.py` | MERGE -> pascal/blockcmp.py | one of four copies differing only in constants |
| `block154d.py` | MERGE -> pascal/blockcmp.py | one of four copies differing only in constants |
| `block193a.py` | MERGE -> pascal/blockcmp.py | one of four copies differing only in constants |
| `block19a0.py` | MERGE -> pascal/blockcmp.py | one of four copies differing only in constants |
| `blocks.py` | MERGE -> pascal/blockcmp.py | the base; segment and block list become configuration |
| `build.py` | MERGE -> pascal/dosbuild.py | TP6; the compiler and switches become configuration |
| `dosbuild.py` | MERGE -> pascal/dosbuild.py | the base harness; TP7 under DOSBox-X |
| `emit_pascal_data.py` | MERGE -> pascal/emit.py | the typed-constant emitter; the nested-parenthesis rule lives here |
| `emit_pascal_data2.py` | MERGE -> pascal/emit.py | the second copy of the same fmt/fmt_array |
| `fpconst.py` | MERGE -> pascal/x87.py | decode the constants those sites load |
| `fpfix.py` | MERGE -> pascal/x87.py | rewrite emulator traps back to real x87 |
| `fpsurvey.py` | MERGE -> pascal/x87.py | survey the trap sites |
| `linkcmp.py` | MERGE -> substrate/align.py | rule: an address inside a known DGROUP window |
| `omf.py` | MERGE -> substrate/align.py | the OMF fixup reader asmcheck.py needs |
| `progcmp.py` | MERGE -> substrate/align.py | same rule, one segment |
| `rtlfind.py` | MERGE -> pascal/rtl.py | RTL routines by masked byte pattern |
| `rtlmatch.py` | MERGE -> pascal/rtl.py | the RTL segment, and how far it matches |
| `scan_funcs.py` | MERGE -> pascal/rtl.py | entry points by prologue shape; neither subsumes the other |
| `shapediff.py` | MERGE -> substrate/align.py | already copied; the SEGMENTS table moves to the answers file |
| `verify.py` | MERGE -> substrate/align.py | rule: a zero on our side, a .TPU's pending fixup |
| `vtbuild.py` | MERGE -> pascal/dosbuild.py | TP7 for the other target; same shape |

## Stays the record's -- this target's own

| script | where | why |
|---|---|---|
| `build_assets.py` | RECORD | builds assets/ from NEUROSIS.DAT and DGROUP |
| `datcarve.py` | RECORD | carves NEUROSIS.DAT by the recovered read map |
| `datmap.py` | RECORD | the read map itself |
| `emit_gain.py` | RECORD | DemoVT's gain ladder; spent, see the prune gate |
| `mktests.py` | RECORD | generates THIS demo's harnesses; wants a scene inventory in the answers file before it can move. A known future move, not a rename |
| `refpath.py` | RECORD | where DemoVT's reference image is; a fact about that checkout |
| `relmatch.py` | RECORD | how far 1.39b's code matches 1.31's; a fact about that pair of releases |

## Spent one-shots, under the provenance gate

| script | where | why |
|---|---|---|
| `emit_byebye.py` | PRUNE | output committed as src/gen/P9IMG.INC |
| `emit_costab.py` | PRUNE | output committed as src/asm/COSTAB.INC |
| `emit_p6shape.py` | PRUNE | output committed as src/gen/P6SHAPE.INC |
| `emit_p6text.py` | PRUNE | output committed as src/gen/P6TEXT.INC |
| `p2obj.py` | PRUNE | output committed as src/gen/P2OBJ.INC |
| `vecobj.py` | PRUNE | output committed as src/gen/P1VECT.INC |

## Goes

| script | where | why |
|---|---|---|
| `ledger.py` | DELETE | already marked superseded; 18 of 317 routines, three rows regex artifacts |
| `pairmap.py` | DELETE | NameError on `refpath`; it cannot run |
| `repair_map.py` | DELETE | spent, and honest enough to detect the repaired file and refuse |
| `split_part1.py` | DELETE | its input no longer exists and its outputs do; the same split was later done three times WITHOUT a tool |

## The policies, decided on #17

**Spent one-shots go, but only once their output states its provenance.** Twelve scripts extracted data that is now committed under `src/gen/` or `src/asm/`. The tool is the only record of which binary the data came from and at which offset, so before an emitter is deleted, the generated file itself must say what produced it and from where. A per-file gate, not a blanket amnesty: where the generated file does not say, the emitter stays until it does.

**Both `probe.py` files are renamed, not one.** They share nothing -- one fingerprints packers and appended payloads, one compiles a probe unit with every installed compiler and diffs the codegen. Renaming only one would leave a reader wondering which `probe` the older documents meant.

**The build harness is Pascal tier.** What it knows is Turbo Pascal's command line, its switches and its 8.3 unit-name rules. A fourth folder would re-open the three-folder decision for one tool.

**A generic instrument written against one target still moves.** `linkorder`, `mapcmp`, `dgroup` and `coverage` were written for the DemoVT rebuild, and every Borland Pascal rebuild wants exactly those four measurements. They move; their target facts go to the answers file. `relmatch` is the exception: comparing one release against another is a fact about that pair.

**`mktests.py` is named as a future move rather than moved.** It generates this demo's harnesses and needs a scene inventory in the answers file first. That is real work, and half-moving it would be worse than leaving it named.

