# Where every script went

**The permanent record of the toolkit migration, and the last word on it.** It
replaces the disposition table that planned the migration -- that document named
71 scripts and 46 of them are now archived, so it had become a snapshot of an
intention rather than a description of anything.

This file is GENERATED from the retirement census and then the census retires,
which is the whole point: a census exists to catch drift between a table and a
tree, and there is no drift left to catch once nothing moves again. What is
below cannot go stale, because every row describes something that already
happened.

**Recover any archived script from the tag**, which exists in both repositories:

    git show archive/pre-kit-scripts:tools/asmverify.py
    git show archive/pre-kit-scripts:v1.31b/verify.py

## Archived -- 49 scripts, deleted and recoverable

Each row names its successor and the measurement that made the deletion safe. A
successor's name on its own does not say anybody checked.

| script | successor | why it was safe |
|---|---|---|
| `asmaudit.py` | `kit/tools/pascal/asmaudit.py` | checks two of the three transcription rules mechanically -- a comment on every assembler line, and the equivalent Pascal above it. VERIFIED: output identical bar the provenance line every kit program prints, 12 units meeting the rule and 43 not. Its source directory was a constant and is now layout.src |
| `asmcheck.py` | `kit/tools/pascal/objcheck.py` | byte-identical output including the implied DGROUP symbol and both padding lines (#33); no flags of its own to lose |
| `asmverify.py` | `kit/tools/pascal/routines.py` | all 77 rows identical (#33), the lock moved into the register, and --probe ported under #36 and verified to return the identical candidate list [(409,238),(447,200),(470,177)] on segment 1107 |
| `block14b9.py` | `kit/tools/pascal/blockcmp.py` | one of four copies differing only in constants; now blocks/14b9.toml |
| `block154d.py` | `kit/tools/pascal/blockcmp.py` | one of four copies differing only in constants; now blocks/154d.toml |
| `block193a.py` | `kit/tools/pascal/blockcmp.py` | one of four copies differing only in constants; now blocks/193a.toml |
| `block19a0.py` | `kit/tools/pascal/blockcmp.py` | one of four copies differing only in constants; now blocks/19a0.toml |
| `blocks.py` | `kit/tools/pascal/blockcmp.py` | every row reproduced against real build output (#34); the segment, length, window and block list became a config |
| `build.py` | `kit/tools/pascal/build.py` | the second consumer's build harness. It donated the compiler-as-a-variable shape, the TP6 dialect rewrite and the SongUnit bootstrap prepass; its data is build.toml. VERIFIED at #35: all 26 unit rows identical. It outlived that by two tickets because probe.py and verify.py imported tp6_dialect from it -- probe.py is now the kit's codegen.py and verify.py imports the kit's copy, so the last hold on it is gone. THE KIT'S OWN build.py CARRIES THIS NAME, which is why archived means 'no ORIGINAL on disk' rather than 'no file of that name' |
| `codegen.py` | `kit/tools/pascal/codegen.py` | RENAMED from the second consumer's probe.py -- the other tool of that name, sharing nothing with the fingerprinter. It compiles a probe unit with every installed compiler and diffs the code, which turns a claimed compiler difference from an assertion into a measurement; five of six such claims in that target were wrong. VERIFIED: identical output, all 40 lines. IT COULD NOT RUN AS IT STOOD -- #36 deleted the committed vt131.conf it took from build.py, and the differential needed that file restored from the archive tag to get an honest comparison. Its successor writes the config AFTER wiping the staging directory, which is what the original could not do |
| `coverage.py` | `kit/tools/pascal/coverage.py` | how much of the target is accounted for -- the complement of the per-unit table, because that table says nothing about a segment nobody has started. IT HAD BEEN READING ZERO FOR THE PROGRAM: it shelled out to progcmp.py, archived under #36, and its regex found no match, so `n` fell back to 0 and 1,616 verified bytes dropped out of the total with nothing said. A regex returning None on a MISSING TOOL is indistinguishable from a tool that measured nothing, so it refuses now. Repointed at blockcmp: 99.8% restored, and 12 bytes higher than the figure on record because #45 fixed progcmp's clipping |
| `dgroup.py` | `kit/tools/pascal/dgroup.py` | compares the initialised DGROUP image. The reference image, the map, the executable and the DGROUP segment number all moved out -- and the segment number turned out to be the same 0x1caa that two other tools carried as a boundary marker. VERIFIED: identical output, the layout agrees for the first 3184 bytes |
| `dosbuild.py` | `kit/tools/pascal/build.py` | all 35 executables byte-identical (#35); its data is build.toml, generated from it by parsing |
| `emit_byebye.py` | `none -- spent, output committed` | src/gen/P9IMG.INC states its provenance: read out of bin/NEUROSIS.009 at DGROUP+2, 00C3:0002 in the debug info, named IMAGEDATA, 4,000 bytes -- and it names this emitter |
| `emit_costab.py` | `none -- spent, output committed` | src/asm/COSTAB.INC states its provenance and names this emitter |
| `emit_p6shape.py` | `none -- spent, output committed` | src/gen/P6SHAPE.INC states its provenance: NEUROSIS_006_fpu.exe at DS:$000A, 2,048 bytes -- and it names this emitter |
| `emit_p6text.py` | `none -- spent, output committed` | src/gen/P6TEXT.INC states its provenance: NEUROSIS_006_fpu.exe at DS:$0C8A, 113 lines -- and it names this emitter |
| `emit_pascal_data.py` | `kit/tools/pascal/emit.py` | the typed-constant emitter. WHAT MOVED is the formatter and the reading; what stayed is every offset, length, type name and line of prose, all of it in emit.toml. VERIFIED: all three generated files' CONST BODIES are byte-identical, 8,010 values -- and a full rebuild leaves all 35 executables byte-identical, which is the test that matters since these are {$I} includes. The HEADERS deliberately changed: each now names the binary AND the offset it came from, which is what #17's provenance gate asks of a generated file before its emitter can be retired. It also confirmed something worth knowing: the bodies are identical although the source is now the trap-rewritten variant rather than the plain file, so that patching leaves this DGROUP data alone |
| `encaudit.py` | `kit/tools/encaudit.py` | text I/O that leaves the encoding to the locale. Its DEFAULT_DIRS was a constant naming one repository's two folders -- so the KIT'S OWN SCRIPTS were never audited by it unless somebody passed them by hand, and the folders it named have since been emptied by this migration. Reading encaudit.dirs it now covers 53 files against 19. Both repositories had a copy and now neither does |
| `fingerprint.py` | `kit/tools/substrate/fingerprint.py` | RENAMED from this repository's probe.py, per #17: there were TWO unrelated tools called probe.py, one in each consumer, and both are renamed rather than one -- renaming only one would leave an older document's mention of 'probe' ambiguous for ever. This one answers what is appended past the load image and what wrote it. VERIFIED: identical output on the packed file and on a part with an overlay |
| `fpconst.py` | `kit/tools/pascal/x87.py` | decodes the constants the rewritten code turns out to load. VERIFIED identical on all four formats -- AND IT COULD NOT DECODE ONE OF THEM: its own docstring described the 4-byte operand as 'FADD/FCOMP float ptr', which is what a disassembler prints, while its table keyed it as `single`, so asking for `float` raised KeyError. Both names work now. Its part-to-file lookup was a hardcoded work/split path with a fallback and is target.original |
| `fpfix.py` | `kit/tools/pascal/x87.py` | rewrites confirmed traps back to real x87. VERIFIED both paths: the PATCHED IMAGE IS BYTE-IDENTICAL on four real trap sites, 4 of 4 applied, and identical again on three offsets that are not traps, 0 of 3 applied with all three named |
| `fpsurvey.py` | `kit/tools/pascal/x87.py` | surveys the trap sites and is what keeps the encoding table honest -- the table is empirical, from one 1994 binary, so a new target runs this before trusting the rewriter. VERIFIED: identical output on two parts |
| `ledger.py` | `kit/tools/pascal/markers.py` | the repaired successor: ledger's DOTALL regex crossed comment boundaries, giving 18 of 317 routines with three rows that were not routines at all |
| `linkcmp.py` | `kit/tools/pascal/linkcmp.py` | identical line for line, all 31 lines (#33); no flags of its own |
| `linkorder.py` | `kit/tools/pascal/linkorder.py` | predicts the link order from the uses graph and diffs it against the original's. Its unit-name map, its no-segment set and the original's order all moved into link.toml. VERIFIED: identical output, 30 of 30 positions agree |
| `mapcmp.py` | `kit/tools/pascal/mapcmp.py` | compares linked segment lengths on the same footing. ITS OUTPUT CHANGED, and both changes are repairs: its copy of the segment list was missing VTSHELL at 0x1931, so that unit was never compared -- and because each length is the NEXT segment's address minus its own, the gap also inflated OBJECTS by exactly VTSHELL's 144 padded bytes and the tool reported it as 'short -- 144 byte(s) of routines nothing references'. That was an artefact of the missing row, not an observation. Now 30 of 30 exact |
| `modex.py` | `kit/tools/substrate/modex.py` | de-interleaves four Mode-X planes; unchained VGA, nothing about Pascal. VERIFIED: deinterleave() returns an identical 256,000-byte image from both copies. build_assets.py -- which stays with the record -- was repointed at substrate.modex, because it was the one caller that survives |
| `mzinfo.py` | `kit/tools/substrate/mzinfo.py` | MZ headers, and whether the file is bigger than its image. VERIFIED: identical output on bin/NEUROSIS.000. Its opening line named this demo and now states the question instead |
| `omf.py` | `kit/tools/substrate/omf.py` | the OMF fixup reader. Its only importer was verify.py, so it went with it. VERIFIED: identical code length and identical fixup sets on both object modules in that target -- PLAYMOD 695 bytes with 36 fixups, SOUNDDEV 2,430 with 384 |
| `p2obj.py` | `none -- spent, output committed` | src/gen/P2OBJ.INC states its provenance and names this emitter |
| `paslint.py` | `kit/tools/pascal/paslint.py` | VERIFIED identical on this repository, 0 problems in 67 files -- AND THE MOVE FIXED A CHECK THAT COULD NOT FAIL. Its source directory was the constant ROOT/'src'; the second consumer keeps its sources under v1.31b/src, so running it there reported '0 problem(s) in 0 file(s)' and passed. Reading layout.src instead, it lints 29 files there. Both repositories had a copy and now neither does |
| `progcmp.py` | `kit/tools/pascal/blockcmp.py` | a blockcmp case rather than a fourth instrument (#45); its headline figure was wrong -- it clipped a block running past the end of our segment and reported 149 real differences for 368 identical bytes |
| `repair_map.py` | `none -- spent` | verified spent under #36: run today it answers '00-map.md looks already repaired (317 blank lines of 1289) -- nothing to do' |
| `repairdoc.py` | `kit/tools/repairdoc.py` | repairs a markdown file whose line breaks have been multiplied -- a fact about the tools a session is driven with, which every project inherits on day one. VERIFIED: identical report on docs/README.md |
| `rtlfind.py` | `kit/tools/pascal/rtl.py` | names RTL routines by pattern rather than by offset -- the corrected assumption at the heart of this tool, since smart-linking preserves offsets only for a stable core. VERIFIED identical on all nine parts, and the JSON it writes is content-identical. Its per-part RTL bases, its reference part and its thirteen confirmed offsets are rtl.toml. THE MOVE FOUND A GAP IN THE ANSWERS FILE: this tool covered nine parts from its own hardcoded path while target.original listed eight -- 009 was missing, and is there now |
| `rtlmatch.py` | `kit/tools/pascal/rtl.py` | finds the runtime block in a binary and measures how far it agrees with a reference. VERIFIED: identical output. Its masking and offset arithmetic were already imported by rtlfind, so the two were one tool in two files |
| `scan_funcs.py` | `kit/tools/pascal/rtl.py` | enumerates likely procedure entry points by prologue shape. ITS OUTPUT CHANGED AND THE CHANGE IS A REPAIR: it carried its own segment-length table, and for three segments the declared length EXCEEDED the space before the next segment begins -- 1000 by 5 bytes, 1931 by 14, 19a0 by 1 -- so those scans ran into the neighbour and attributed 4 entry points to the wrong segment. Deriving each extent from the next segment's base cannot do that: 350 becomes 346. It also no longer scans the DGROUP segment, which is data and had 0 anyway |
| `segmap.py` | `kit/tools/substrate/segmap.py` | real-mode segment layout derived from the relocation table. VERIFIED: identical 9-line output |
| `shapediff.py` | `kit/tools/pascal/spans.py` | the coverage walk, and the instrument the top open investigation runs on. IT WAS BROKEN BY THIS MIGRATION: it imported asmverify, archived under #36, so it had stopped running entirely -- the fourth time a deletion here caught a surviving script. What was missing from the kit was not the measurement, which align.spans() has held since #33, but a way to RUN it and an equivalent of --same. VERIFIED against the original restored from the archive tag: parts 001, 002 and 003 identical in every figure including the recorded 66.6% and 49.9%, --same identical, and part 005 aligns 24 bytes MORE -- 80.4% against 80.2%, the SAME 20 spans, two of them starting 14 bytes later and ending 10 earlier. That is the two density gates being formulated differently, measured back to back on a byte-identical TPART5.EXE: not a source change and not a stale figure. The kit's gate is the one #33 measured against all 77 routines. No span is lost, so no work is hidden. It also reads target.release rather than target.original, which is a distinction the answers file did not carry until now |
| `split.py` | `kit/tools/substrate/split.py` | an MZ image plus its appended payload. VERIFIED: identical output splitting bin/NEUROSIS.008 |
| `split_part1.py` | `none -- spent` | verified spent under #36: its input src/PART1_INTRO.PAS no longer exists, so it cannot run. The same split was later done three times without a tool |
| `strings.py` | `kit/tools/substrate/strings.py` | printable strings, restricted to the load image. VERIFIED: identical 160-line output |
| `survey.py` | `kit/tools/pascal/survey.py` | RENAMED from the second consumer's census.py, which collided with the kit's. VERIFIED on four segments -- 17cf, 116e, 1a17 and 12ba -- output identical line for line, 108, 41, 45 and 43 lines. It could not be run as it stood: its image path still pointed at work/unpack/ from when it lived in the other repository, so it crashed on every invocation, and its census row said carry. Its 27-entry segment table, whose own comment asked somebody to keep it in step with verify.py's UNITS, is gone -- the unit config already held it |
| `symbols.py` | `kit/tools/substrate/symbols.py` | the 0x52FB name pools. VERIFIED: identical output |
| `undeclared.py` | `kit/tools/pascal/undeclared.py` | identifiers a unit uses but never declares. THREE project facts came out of it -- the source directory, which units export the names anything may use without declaring, and which files are worth scanning, the last of which was the glob PART*.PAS and is a naming convention no other target has. VERIFIED: identical output, all 51 lines |
| `unlzexe.py` | `kit/tools/substrate/unlzexe.py` | LZEXE 0.91. VERIFIED: the unpacked image is BYTE-IDENTICAL, sha256 0177fce7ba1080b1..., from both copies of the unpacker -- the only difference in the run was the output path each was told to write. Both repositories had a copy and now neither does. Its docstring named one file in one demo; it now carries the SHAPE that finding has -- a single packed file in an otherwise unpacked release is often somebody else's code |
| `vecobj.py` | `tools/build_assets.py` | THE DISPOSITION'S REASON WAS WRONG and the decision was right. It said 'output committed as src/gen/P1VECT.INC'; that file names emit_pascal_data2.py, and vecobj.py never wrote it -- it writes into assets/. Checked instead: build_assets.py carries its own EMBEDDED table producing the same vector_globe and vector_logo_a, assets/ is committed (163 files), and assets/README.md names build_assets.py as the producer with the DGROUP offsets in its table. So it is spent, superseded by a tool that STAYS with the record |
| `verify.py` | `kit/tools/pascal/units.py` | kept twice under #33 and #36 because units.py reproduced every ROW while dropping its two diagnostic views. Those are ported: align.regions() lists every divergent region and align.hexpair() renders one with a mark line, behind units.py --all and --detail. VERIFIED on a build made to FAIL on purpose (/$R+ turned 0 mismatched into 19): all 566 printed regions identical across all 19 units, per-unit counts identical on every one, and the hex dump identical byte for byte. Two callers repointed first -- coverage.py, whose answer is unchanged at 96.1%, and relmatch.py, which cannot be exercised here because its input tree is held out of source control |

## Still here -- 25, and they are the kit's own

These are the programs the migration produced. They are not going anywhere, and
they need no table to say so; the row survives here only because the census
carried one.

| tool | what it is |
|---|---|
| `align.py` | the coverage question -- which bytes of an original do not line up against a rebuild, allowed-difference rule passed in |
| `artefact.py` | guards the byte-identical rebuilds |
| `blockcmp.py` | one segment, block by block; the five blocks*.py scripts merged into it, their segment lists now config |
| `census.py` | the kit's script-retirement census, and the row now means only that. THE SECOND CONSUMER HAD A COMPLETELY DIFFERENT TOOL UNDER THIS NAME -- four cheap measurements on one segment: far returns as a routine signature, string absence as evidence, far calls out, and CALLF [DI+nn] sites giving the VMT layout. A table keyed by basename cannot hold both, and this row very nearly archived a live tool on the strength of a successor that is an unrelated program. It is kit/tools/pascal/survey.py now |
| `emit.py` | THE KIT'S, born there: the typed-constant formatter with the nested-parenthesis rule, and the reading that feeds it. A multidimensional typed constant needs ((x, y, z), ...) and Turbo Pascal rejects a flat list of the same numbers, which fails a long way from its cause |
| `glossary.py` | turns the glossary's Avoid lists into a check |
| `kbprofile.py` | our stricter wiki profile, and the generators for what is generated |
| `marker.py` | the one reader for @asm markers; three programs had their own and one had already diverged |
| `markers.py` | reads the @asm markers out of the source tree |
| `objcheck.py` | a {$L} object module against the object's OWN relocations, which is stricter than the zero rule rather than looser; supersedes asmcheck.py |
| `observe.py` | records a run somebody actually made, and nothing else |
| `okfcheck.py` | OKF v0.1 conformance only; no project facts, deliberately |
| `plan.py` | the ordered queue of investigations |
| `project.py` | the only reader of a project's answers file; every other program in the kit asks it where things are |
| `ratchet.py` | the ratchet: coverage may only rise |
| `register.py` | the one writer for status.toml; refuses a section it does not know |
| `routines.py` | per-routine byte check, the successor to asmverify.py; its lock lives in the register rather than in a source dict |
| `rtl.py` | THE KIT'S, born there: the runtime in three steps -- find the block and measure it, name routines inside it by pattern, and enumerate likely procedure starts anywhere by prologue shape. Two of the three already shared code, so they were one tool in two files |
| `shared_asm.py` | assembler duplicated between units instead of shared as one include; written here, project exemptions passed in |
| `spans.py` | THE KIT'S: the coverage walk made runnable, plus --same, which asks whether an unaligned span is code already transcribed in ANOTHER harness -- turning the job from write this into share what exists |
| `staged.py` | is a build output still the source it was built from; text not timestamps, and it says unknown where no copy was staged |
| `tddump.py` | Borland debug info, decoded whole |
| `units.py` | each compiled unit's code against the segment it rebuilds, by prefix; supersedes verify.py |
| `wizard.py` | installs the kit into a project: proposes with its evidence, asks what no listing implies, and --check diffs against a kit.toml already there |
| `x87.py` | THE KIT'S, born there: the three-step x87 job -- survey the emulator traps, rewrite the confirmed ones, read the constants the rewritten code loads. Three scripts merged into one tool because they are three steps of ONE job, and doing the third without the first is how a wrong theory becomes a table of plausible constants |

## Deliberately kept behind -- 10

The record's own: this target's data carvers, its harness generator, a
reference-path helper, and two that could not be exercised on this machine.

| script | why it stayed |
|---|---|
| `build_assets.py` | project driver: builds assets/ from NEUROSIS.DAT |
| `datcarve.py` | project driver; but png_indexed() is a dependency-free indexed PNG writer worth carrying separately |
| `datmap.py` | project driver: NEUROSIS.DAT region map |
| `emit_gain.py` | spent one-shot, output committed. Its VALUE is a property, not code: it reassembles and byte-compares before printing, and fails rather than emitting something plausible |
| `emit_pascal_data2.py` | second copy of emit_pascal_data's formatter; carry that one instead |
| `mktests.py` | THE RECORD'S. It generates THIS demo's harnesses and would need a scene inventory in the answers file before it could move -- a known future move, named rather than half-done (#17). Its row said `carry`, which read as work outstanding when the decision was to keep it |
| `pairmap.py` | the PUSH CS literal-scoring idea is sound and one-way, but it is a project-specific driver; carry the idea if it proves needed |
| `refpath.py` | THE RECORD'S: where DemoVT's reference image is, a fact about that checkout. Its row said `carry` |
| `relmatch.py` | THE RECORD'S: how far 1.39b's code matches 1.31's, a fact about that pair of releases rather than about Borland Pascal. Its row said `carry`, and it is the stated exception to the rule that a generic instrument written against one target still moves |
| `vtbuild.py` | dosbuild.py with renaming removed, and it cannot run without the held-out 1.39b release. #35 confirmed the decline rather than porting it: the release tree is absent on this machine, so a config for it could not be exercised, and an unexercised path in the kit's highest-risk tool is what #49 argued against. Its one unique feature -- rewriting a staged TPC.CFG's /U line -- is recorded here and nowhere else |

## What the migration cost, honestly

**Four surviving scripts were broken by its own deletions** -- nine importers of
one module, and three tools that depended on a config or another tool rather
than on an import, so nothing about the import graph would have caught them. Each
was found and repaired, and each is recorded on the row that caused it.

**Five moved tools' answers changed**, and every one was a repair: a segment list
that had drifted and was manufacturing a finding; a coverage total silently
missing 1,616 bytes; entry points attributed to the wrong segment; generated
headers that now name their source; and one part's coverage walk aligning 24
bytes further under a differently-formulated density gate.

**Five claims in the planning documents did not survive checking** -- a script
said to be unrunnable that runs, an emitter credited with a file it never wrote,
a successor that was an unrelated program of the same name, a docstring naming a
format its own table rejected, and a table of segment lengths that ran past the
segments it described.

`kit/WORKING.md` section 8 carries the general lessons, which is where they are
useful; this file carries the specifics, which is where they are auditable.
