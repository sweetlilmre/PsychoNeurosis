# Transferable technique inventory — Psycho Neurosis and DemoVT v1.31b

Research ticket: [#3](https://github.com/sweetlilmre/PsychoNeurosis/issues/3). This is an **inventory, not a design** — no catalogue structure, page template or fidelity ladder is proposed here. Nothing was modified; no git commands were run.

## What was mined

| source | size | coverage |
|---|---|---|
| `psycho/docs/*.md` | 29 files, ~230 KB | all read in full |
| `VangeliSTracker/v1.31b/docs/*.md` | 7 files, ~487 KB | all read in full (`CONTINUATION.md` alone is 292 KB / 2,705 lines) |
| `~/.claude/projects/D--source-psycho/memory/*.md` | 12 files, ~34 KB | all read in full |

Two efforts feed this. **Psycho Neurosis** is a 1994 DOS megademo (Borland Pascal 7 + hand asm, real-mode VGA) reconstructed for **behavioural** fidelity — in progress. **DemoVT v1.31b** is a third-party Turbo Pascal 6 MOD player rebuilt to **byte-exact** fidelity from a packed `.EXE` — complete at 44,171 of 44,272 in-scope bytes, blocked only on LZEXE. The two fidelity targets are what make the pair valuable: the same technique is load-bearing in both, but the *acceptance test* differs, and several techniques exist only because byte-exactness demanded them.

**Counts.** **209 techniques** — 76 substrate, 133 Borland-Pascal. **88** have a worked example in the material. **91** need no disassembler at all (26 substrate, 65 Pascal), which is a deliberate property of both projects rather than an accident. **79 withdrawn conclusions**, grouped into nine lesson classes.

Entries are deduplicated across sources and given stable IDs (`S-nn`, `P-nn`, `W-nn`). Where several documents record the same technique the entry cites the two best instances and, for the Psycho scene docs, the number of documents it recurs in — that recurrence count is itself evidence of generality.

---

## THE MODEL ENTRY — the blind-spot table this inventory is built around

`CONTINUATION.md` L101–125, quoted verbatim. Everything below inherits its discipline. Framing sentence: *"no single tool here measures the whole thing, and each one is blind to something the next one catches. Every defect class this project found late was found because a new tool could see what the old one could not."*

| tool | what it compares | what it CANNOT see |
|---|---|---|
| `verify.py` | a `.TPU`'s CODE against its segment | every DGROUP address and inter-unit call — they are pending fixups it excuses. Also cannot see whether a routine is an init section or a named procedure |
| `asmcheck.py` | a `{$L}` module's relocations against its `.OBJ` | anything outside the assembled run |
| `linkorder.py` | the `uses` graph against the original's segment ADDRESSES | nothing about contents; it is a constraint check |
| `mapcmp.py` | linked segment LENGTHS, both padded to a paragraph | contents. A unit can be the right length and wrong throughout |
| `dgroup.py` | the INITIALISED DGROUP image, byte for byte | plain `var`s, which are never written to the EXE. **And a boundary inside a run of zeros** — it read 100% identical while `SelfName` was six bytes too long |
| `progcmp.py` | segment `1000`'s code, per routine, shift searched | it is the program only |
| `linkcmp.py` | ALL twenty-seven linked segments, with fixups resolved | needs the order and every size already right, or nothing lines up |

Two properties of this table generalise beyond its seven rows and are the most transferable single idea in either project:

1. **The order the measures can be used in is forced.** `linkcmp.py` was useless until `mapcmp.py` and `linkorder.py` had aligned the segments; the variable half of DGROUP could not be touched until the constant half was exact; the constant half could not be measured until the program linked at all. Hence the standing rule: *"If a measurement here looks impossible, check whether something upstream of it is still wrong."*
2. **A tool's idea of an acceptable difference is part of the measurement.** `verify.py` excuses a differing byte where our side is `00` — exactly right for a `.TPU`, exactly wrong for an assembled module, where TASM leaves an *addend*.

---
# TIER 1 — SUBSTRATE (DOS / 16-bit / linked image)

Legend: **Disasm** = needs a disassembler. Sources: `P` = `psycho/docs`, `V` = `VangeliSTracker/v1.31b/docs`, `M` = memory files.

## A. Getting at the binary

### S-01 · Split an MZ from its appended payload by the header's declared image size
**Decides:** where the executable ends and tacked-on data begins. Cross-checked because the `/off:n` values in the external config equal each part's MZ image size exactly — two independent sources agreeing pins the boundary.
**Blind spot:** the header is only nominally authoritative — a packer or hand-edited header makes the split wrong with no symptom but a truncated tail. Assumes exactly one payload per file, so a second payload, or one *inside* the image as an overlay, is invisible. Says nothing about what the tail is.
**Disasm:** no · **Source:** `P 01-binaries-and-loading.md` "How it fits together" / "Loading into Ghidra" L23–64 · **Example:** yes, the ten-file table L9–21.

### S-02 · Unpack LZEXE, using the relocation table as the unpack's own checksum
**Decides:** whether the expansion is correct. `LZ91` at `0x1C`, 32-byte header, no relocations, entry near the image end identify the packer; afterwards all 772 relocation sites land inside the image and every stored value is a small segment number, which is what an unrelocated far reference looks like.
**Blind spot:** structural, not content-addressed — a systematically corrupt code region with a valid table passes. And the unpacker *manufactures* two header fields: it writes `maxalloc` as `$FFFF` itself and recomputes `minalloc` from `SS:SP` because LZEXE preserves neither, so `minalloc` agreeing is partly circular. It re-encodes relocations, so only the set of **linear** targets is comparable, never the order. A reconstructed artefact can validate against your own reconstruction of it.
**Disasm:** no · **Source:** `V 00-map.md` "Getting at it" L9–35; `V CONTINUATION.md` L40–55, L650s; `M demovt-byte-exact` · **Example:** yes.

### S-03 · Read the packer stub's bit-refill sequence rather than assuming lazy refill
**Decides:** the exact moment an LZ bit-stream reloads. `SHR BP,1 / DEC DX / JNZ + / LODSW / MOV BP,AX / MOV DL,10h` means taking the 16th bit pulls the next bit-word immediately, and a literal belonging to that bit is read from after it.
**Blind spot:** the failure signature is deceptive and delayed — "It decodes perfectly for about seventy bytes and then walks off the front of the buffer." Generalises: **any decompressor validated on a short prefix is unvalidated.**
**Disasm:** yes, for ~6 instructions · **Source:** `V 00-map.md` "Getting at it" L20–35 · **Example:** yes.

### S-04 · Reproduce the whole shipping pipeline, not just the compile
**Decides:** what byte-exactness has to mean. `MAKE.BAT` is `tpc` → `tdstrip` → `lzexe`, so shipped binaries carry no debug info and are packed.
**Blind spot:** says nothing about the *version* of each stage, and the strip step destroys the symbol table you most want — it explains an absence rather than recovering it. `TDSTRIP` here looks like a no-op by arithmetic (58,176 = 3,120 header + 55,056 image, nothing after) but "that is arithmetic, not a run."
**Disasm:** no · **Source:** `V 06-transcription.md` L1455–65; `V CONTINUATION.md` Risk 3, L2586–2606.

### S-05 · Recover the `{$M}` stack size from two agreeing header fields
**Decides:** the memory directive. Initial `SP $4E20` plus MINALLOC 226 paragraphs = 3,616 bytes above a default build = 20000 − 16384 exactly, giving `{$M 20000,0,655360}`.
**Blind spot:** only works where the packer preserved `SS:SP` — and S-02 shows `minalloc` is *not* preserved, so half the evidence is the unpacker's own. One arithmetic coincidence from over-reading.
**Disasm:** no · **Source:** `V CONTINUATION.md` L88–92.

### S-06 · Harvest Borland debug blocks for a free symbol seed
**Decides:** original source filenames and identifier names; magic `0x52FB` on an appended block. Also a build-configuration signal — parts *with* debug info were built differently from those without.
**Blind spot:** present in only 2 of 10 binaries here, so it never reaches the seven interesting parts. Gives names without semantics, and exists only where the author left it.
**Disasm:** no · **Source:** `P 01-binaries-and-loading.md` "Recovered symbols" L42–49 · **Example:** yes, L46–47.

### S-07 · Derive the segment map from the relocation table, independently of the loader
**Decides:** one memory block per Pascal unit, confirming the loader's split rather than trusting the tool.
**Blind spot:** relocations mark only segments referenced *by a fixup* — a unit with no inter-segment references, or one reached by a computed value, is absent. Says a boundary exists, never which unit it is.
**Disasm:** no · **Source:** `P 01-binaries-and-loading.md` L66–68 (`tools/segmap.py`).

## B. Locating structure without a disassembler

### S-08 · Run four cheap scans before writing anything (`census.py`)
**Decides:** a segment's structure in one command — far returns (a routine census whose stack-cleanup counts are signatures: `RETF 4` = Self alone, `RETF 6` = Self + hidden VMT word, which **only** constructors and destructors carry, `RETF 10` = Self + Word + pointer), printable strings, far calls out with counts, and virtual call sites. "It did nearly all of `165a` without a disassembler."
**Blind spot:** counts **far** returns only — a near routine ends in `RET`, an interrupt handler in `IRET`, and it sees neither (a one-line search for `CF` found `193a`'s handler; `SetVars` as a near helper stayed invisible). Frameless `assembler` routines are missed. Nested `far` closures inflate the frame count above the true routine count (`17cf`: 46 frames vs ~41 routines). Identical stack footprints are indistinguishable — a `Pointer` and two `Word`s both clean 4 bytes. No control flow, no statement shapes.
**Disasm:** **no** · **Source:** `V CONTINUATION.md` L700s, L1222–45; `M demovt-byte-exact` · **Example:** yes — 21 release routines − 5 absent = 16 = exact far-return count in `14b9`.

### S-09 · Scan for compiler prologue byte patterns to enumerate entry points
**Decides:** a **lower bound** on routines per segment. Patterns `55 89 E5`, `55 8B EC`, `C8 nn nn 00`; 350 entry points found.
**Blind spot:** stated explicitly — "a routine that builds no frame at all will not appear." It hid the filter kernels in `1544`, the chain stubs, the mixing kernels at `1a17:0d7c`/`0dfc`, `12ba`'s kernel, two frameless routines in `142f`, and two more in `154d` (five prologues, at least seven routines). All had to be reached by **following the calls**, which is the paired technique.
**Disasm:** no · **Source:** `V 02-functions.md` L1–30; `V CONTINUATION.md` L1718–22, L1770 · **Example:** yes, plus the counter-example at `V 04-units.md` L1961.

### S-10 · Use the prologue *encoding* as a per-segment build-provenance fingerprint
**Decides:** which segments the author compiled versus received prebuilt. Every segment uses one encoding, never both: `89E5` for 24 segments, `8BEC` for exactly `1b6f` and `1ba1` — `Dos` and `System`, shipped by Borland as prebuilt `.TPU`.
**Blind spot:** cannot separate "prebuilt by the vendor" from "compiled by a different compiler in the same project". The doc flags its own limit on `1891`, which falls on the `89E5` side because `OBJECTS.PAS` shipped as source: "the alternative, that `1891` is JCAB's own work-alike, is not ruled out by the encoding alone."
**Disasm:** no · **Source:** `V 02-functions.md` L18–30 · **Example:** yes.

### S-11 · Treat a desync at `:0000` as positive evidence of leading data
**Decides:** that a segment opens with a constant or table (`154d`, `165a`, `1caa`). Confirmed causally later: `11bb`'s segment head *is* the `set of Char` its trim routine uses.
**Blind spot:** the nonsense is "convincing", so a reader who does not suspect data documents instructions that do not exist. Cannot separate leading data from a mid-segment realignment — and `disassemble_bytes` sometimes starts one byte late and produces the same symptom for an unrelated reason.
**Disasm:** yes, as the failing instrument · **Source:** `V 02-functions.md` L23–26; `V 00-map.md` L727–744 · **Example:** yes, both.

### S-12 · Prove a segment holds no code by combining a failed disassembly with a failed prologue scan
**Decides:** that `1caa` is constants only — nonsense at `:0000`, and the prologue scan finds nothing in 3,184 bytes. Corollary: a tool's segment naming is positional, not semantic — "Ghidra calls it `CODE_30` because of where it sits, not because there is code in it."
**Blind spot:** two negative instruments agreeing is still negative evidence, and frameless code satisfies both (S-09). Confidence came from a third leg — every byte independently accounted for as a catalogued string or table.
**Disasm:** partly · **Source:** `V 00-map.md` L1185–95.

### S-13 · Fingerprint a segment against a release source file by its string literals (`relmatch.py`)
**Decides:** which release unit to start from. TP puts untyped string constants in the CODE segment, so a segment carries its unit's literals verbatim. `11bb` = 41 of 52 of `VTCFG.PAS`. A companion score covers each segment by 8- or 16-byte windows found anywhere in the compiled `.TPU`, robust to reordering. Calibrated: `1642` = 100.0% on a known byte-identical unit; ~40% is the floor for "transcribe the release's body verbatim and it works".
**Blind spot:** **explicitly one-way, and in two different ways.** The literal score: "a high score is strong evidence of a pairing; a low score is no evidence at all" — 8 of 10 segments have no literals to share. The window score measures **divergence between versions, not whether the pairing is genuine** — `12ba`/`PLAYMOD` scores 16.1% and is one of the best-established pairings, while `154d` scores respectably against `MODLOADE` and its bodies still do not transfer. **Read it as a ranking, never a verdict.** It also needs the release to compile.
**Disasm:** no · **Source:** `V CONTINUATION.md` "WHY THIS WORKS AS A TEST, AND WHAT IT CANNOT DO" L1870, "EVERY PAIRING IS NOW MEASURED RATHER THAN ARGUED" L1740–90; `V relmatch-output.txt` · **Example:** yes — `1642 → ASCIIZ.TPU 100.0%`, `1b24 → HARDWARE.TPU 83.7%`, `1650 → SONGUTIL 71.1%`.

### S-14 · Match declaration and literal ORDER, not just names
**Decides:** a pairing, more cheaply and more strongly than name matching. Literals are emitted immediately before their routine in source order (`GetBool`'s sixteen in the release's declaration order); globals arrive in declaration order at consecutive addresses. "Order matching is far stronger evidence than sixteen names matching, and it is free."
**Blind spot:** a statistical argument about the set, not proof about any member; presumes neither version reordered its declarations.
**Disasm:** no · **Source:** `V CONTINUATION.md` L1870s.

### S-15 · A missing call proves a missing routine — cheaper than searching for the routine
**Decides:** absence. `ChangeSystemHeap` has three callers in 1.39b and one here, so `InitTempHeap`/`DoneTempHeap` are absent; no `CALLF [DI+3c]` anywhere means `RemoveHeap`'s caller is absent.
**Blind spot:** proves absence only for routines whose sole reachability is that call; silent about routines with external callers, and **cannot distinguish "absent from source" from "smart-linked out"**.
**Disasm:** no, byte scan · **Source:** `V CONTINUATION.md` L2370–95.

### S-16 · Zero printable strings in a segment is positive evidence of absent code
**Decides:** which literal-bearing statements are missing — no strings in 2,832 bytes means `HFreeMem`'s `WriteLn` is absent; "not one printable string in 1,905 bytes" says `SbGetCopyrightString` and `USES Debugging` are absent from `19a0`; no string but `.MOD` in 2,224 bytes says `GetErrorString`, which is nothing but message literals, is absent.
**Blind spot:** strictly one-way, and only works for routines whose whole substance is literals. Says nothing about DGROUP-resident typed string constants, and a low count is no evidence about anything else — `NoteStr` holding no data is consistent with the same reading.
**Disasm:** no · **Source:** `V CONTINUATION.md` L1246, L1642, L2340s.

### S-17 · Filter a byte-pattern scan by 16-bit ModRM form — and validate the new scan against a known answer
**Decides:** the one true referent of an address. Searching `$06c2` raw gave dozens of hits; ModRM-filtered left one, which decoded as the tail of another instruction; scanning only for `MOV r16,imm16` gave the single correct hit.
**Blind spot:** an encoding-aware scan still misses references through a computed or indexed base. And **an empty result from a new scan is not evidence of an absence** — `census.py`'s virtual-call regex looked for `ff 5f` as `CALLF [DI+d8]`, wrong because in 16-bit ModRM the rm field is an addressing *mode*, not a register (`FF /3` gives `0x58 + rm`; `100=[SI] 101=[DI] 110=[BP] 111=[BX]`, so `[DI]` is `ff 5d`). Validate against a segment whose answer is known, and check what precedes each hit — all 22 of `165a`'s shared one five-byte preamble, which is what ruled out false positives.
**Disasm:** decoding-grade · **Source:** `V CONTINUATION.md` L430s, "A SCANNER'S OWN BUG READ AS A FINDING" L2146 · **Example:** yes, both directions.

### S-18 · Treat every byte-pattern hit as a candidate, never a finding
**Decides:** the false-positive rate of an opcode scan. Six of `census.py`'s 21 far-call targets in `154d` decode to nonsense segments (`3bc0:31fb`, `8936:77fb`, `e903:76fb`, …) because the `9A` byte occurs in data and inside other instructions.
**Blind spot:** the scan itself cannot discriminate; only decoding from a known-correct instruction boundary can. Recorded as violated three times, the third of which "cost two wrong leads in a row".
**Disasm:** the verification step needs one · **Source:** `V CONTINUATION.md` L1725–30, L430s.

### S-19 · Check a span against the FOLLOWING segment's paragraph address
**Decides:** whether trailing "routines" belong to the unit at all. `VTSHELL`'s three stubs at `1931:0090/0095/009a`: `0x1931*16 + 0x90 = 0x193a0` = `193a:0000`, another unit entirely — and there was a fourth the original scan stopped short of. Used positively too: `11bb` begins at `116e:04d0`, so the two are contiguous and `116e`'s 1,232 bytes is exact.
**Blind spot:** none for the arithmetic — it simply has to be done, and it needs the segment map. Says nothing about anything not near a boundary. "A SEGMENT BOUNDARY IS NOT A SUGGESTION."
**Disasm:** no · **Source:** `V CONTINUATION.md` L1466–78, L2200s · **Example:** yes, both directions.

### S-20 · Segment size is not code size
**Decides:** how many trailing bytes are padding. `142f` = 2,175 code + 1 pad; `12ba` = 5,958 of 5,968; `1931` = 138 + 3; the project's last 101 "missing" bytes are all padding. `VTSHELL` passed only once its size was corrected 141 → 138.
**Blind spot:** the figure is derived from where *your* reproduction stops, so it is trustworthy only once the body matches; used earlier it silently absolves a real tail divergence. Cannot separate inter-segment padding from a small routine you have not found. Corollary rule: `verify.py`'s CODE sizes and the map's SEGMENT lengths are not the same footing — **everything under ~15 bytes in that comparison is padding, not missing code.**
**Disasm:** no · **Source:** `V 06-transcription.md` L1174–78; `V CONTINUATION.md` L1497–1502, Risk 4.

### S-21 · Read the initialisation-call chain as a readout of the dependency graph
**Decides:** the order units were linked, and semantics with it. Nine units initialise, in order `1ba1 → 193a → 1931 → 17cf → 14b7 → 12ba → 11bb → 1084 → 1065`. Load-bearing: `RegisterDriver` pushes onto the front but selects only when nothing is selected, so **the first registered wins**. TP emits one far call per unit that *has* an init section, in dependency-resolved order, so the chain is a hard measurable constraint on the `uses` clause.
**Blind spot:** lists only units *with* an init section — nine of thirty-one — so it is a partial order over a subset, silent about the link position of every unit that initialises nothing. It fixes order, not membership. And it misled once: a two-member comparison concluded the GUS registers first; the chain calls DevSB at `04b8` before DevGus at `04d6` (W-40).
**Disasm:** light · **Source:** `V 00-map.md` "The initialisation chain" L95–110; `V CONTINUATION.md` L1520–35.

### S-22 · Bracket a byte-pattern sweep for handlers the census misses
**Decides:** a layout question the far-return census cannot answer — one search for `CF` (`IRET`) settled that `193a` has exactly one interrupt handler, `DMAIrq` at `0030..007d`, 78 bytes.
**Blind spot:** the opcode byte occurs inside data and other instructions (S-18), and private near helpers still stay invisible.
**Disasm:** no · **Source:** `V CONTINUATION.md` L1566–68.

### S-23 · Negative search: prove data is initialised by finding no writer anywhere
**Decides:** that a table is linker-laid initialised data. Every segment was scanned for a store to `DS:$03c4..$03ca` in all its forms — `MOV [addr],AX`, `MOV word [addr],imm`, DX and high-word forms — and **not one exists anywhere in the program.** Therefore the original named both loaders in a typed constant, therefore the shape must be expressible.
**Blind spot:** exhaustiveness depends entirely on enumerating every store encoding; a form you did not think of makes the negative result false. Proves only "not written at run time", never the contents. This is the search that overturned the tree's one deliberate data deviation.
**Disasm:** no · **Source:** `V CONTINUATION.md` L1425–35, L1479–90; `M demovt-link-layout` · **Example:** yes.

## C. Data, tables and assets

### S-24 · Recover an index-free asset blob from Seek/BlockRead immediates
**Decides:** the asset map with no index in the file. Sweep the named file-I/O RTL call sites and read back the immediates pushed before each `CALLF`. Key convention: Borland pushes left-to-right, so `Seek(f,n)` puts `n`'s high word then low word immediately before the call — **that ordering is what makes the constant readable.**
**Blind spot:** only *immediate* arguments are recoverable. A computed offset, a loop-varying seek, or a value from a variable yields nothing, and the sweep cannot tell a missing region from a computed one. Assumes `Assign`/`Seek`/`BlockRead` are the only path, so raw INT 21h access is invisible. Never says what the bytes mean.
**Disasm:** yes · **Source:** `P 04-neurosis-dat.md` "Recovering the map" L10–19 · **Example:** yes, L34–36.

### S-25 · The tiling proof — validate an extraction by exhaustion
**Decides:** completeness, globally rather than per region. Sort all seek targets; check each region's declared read sizes against the distance to the next seek. 26 of 26 regions tile exactly, 1,718,189 of 1,718,189 bytes declared, final region ends precisely at EOF. Because any single error breaks the tiling it is also **generative** — it settled three ambiguities because only one arrangement tiles.
**Blind spot:** proves the *partition*, never contents, order or interpretation — two adjacent regions swapped in meaning still tile perfectly, and **compensating errors** (one size over, its neighbour under) also tile. 100% coverage is only achievable where the blob has no slack; a padded or sparse container makes the proof unavailable rather than failing loudly.
**Disasm:** only for its inputs · **Source:** `P 04-neurosis-dat.md` "The map is provably complete" L21–41 · **Example:** yes.

### S-26 · Factorise the byte count to recover dimensions and strides
**Decides:** geometry and record stride from size plus the reading loop's bounds. **Recurs in 13 of 15 Psycho scene docs** — 3136 = 56×56, 13,104 = 91×8×9×2, 36,414 = 51×714, 256,000 = 1280×200, 59,904 = 72×26×16×2.
**Blind spot:** factorisations are ambiguous (3136 = 56×56 *or* 64×49; 1024 = 32×32 *or* 16×64), so it needs a loop bound, a stride constant, or a render to confirm. Says nothing about orientation, sign or bit depth, and silently accepts a header — 12,412 resolves only once you posit a 2-byte header (146×85+2). **Fixes stride and count, never semantics** (W-31 is exactly this failure).
**Disasm:** the factorisation is not · **Source:** `P 11-part3-scene5-blocks.md` "Assets" L13–20; `P 16-part004-lemmings.md` "The sprite banks" L200–215 · **Example:** yes, both.

### S-27 · Anchor an extraction on the address where the next known thing begins
**Decides:** that a table's extent is right, because it terminates exactly at a known boundary. Three R/G/B tables run `$0002 + 225 = $00E3` … straight into the sine table at `$02A8`; the 450-entry sine table ends exactly where shape data begins at `$0636`; the Enterprise's face table ends at `$046A`, which *is* `ScreenWidth`, the next known global.
**Blind spot:** adjacency is a consistency check, not proof of semantics — two tables can abut correctly and both be misidentified. Defeated by padding and alignment gaps, and it cannot detect an extraction off by a whole record when the count errs in the compensating direction. **Says nothing about a file-offset error** — a carve 256 bytes too far in produced "meaningless 0/`$AB` soup" that survived a whole revision (W-30).
**Disasm:** no, given the address map · **Source:** `P 22-part002-scene2.md` "Object data" L400–412; `P 06-part3-scene1-tunnel.md` L28–40 · **Example:** yes, both.

### S-28 · Size a missing datum from the arithmetic between two known addresses
**Decides:** existence, size and position of something nothing names. `DevStack` = `$4302 − $3b32` = 2,000 bytes; `NoteStr` = 340 = 85×4, so `array[0..84] of String[3]`; `SbPort` at `$0b14` because 28 ports run `$0adc..$0b13` and `$0adc + 27*2 = $0b12`, contiguous with nothing left over. "The arithmetic is the only reason to believe it exists, and it is enough."
**Blind spot:** gives size and position, never contents or name — and **cannot see a boundary inside a run of identical or zero bytes** (S-36). A count is data, so the release's constant is worthless: `DevStkSize` 1000 against 1.31's 2000.
**Disasm:** no · **Source:** `V CONTINUATION.md` L235–45, L400s; `V 00-map.md` (`19a0` ports).

### S-29 · Plot a table's coverage map to recover its generator's geometry
**Decides:** what a baked offset table means. The globe's destination coverage draws a filled disc, its source coverage a 300×150 band dense at both ends; 22,996 destinations from 16,316 distinct sources, the many-to-one compression at the limb being sphere foreshortening.
**Blind spot:** recovers the *shape* of the mapping, never the parameters — radius, tilt and the exact projection are not recoverable, only "it is a sphere". Blind to anything the table does not enumerate, and cannot distinguish a sphere from any surface with the same silhouette and edge compression.
**Disasm:** no, once element size and base are known · **Source:** `P 10-part3-scene4-globe.md` "Why we know it is a sphere" L40–55 · **Example:** yes, two generated coverage maps.

### S-30 · Render raw table data as an image to confirm the record layout
**Decides:** base address, record size, component order, signedness and scale *simultaneously*, because only the correct combination produces a recognisable picture. Recurs in 7 Psycho docs.
**Blind spot:** recognisability is a human judgement and **directionally biased** — a wrong reading that looks plausible passes (four "near-identical houses differing 29–48%" were the planes of one panorama). Validates nothing outside the drawn projection, which is why a model needs **five axis pairs** (W-28). Clean symmetric ranges (±400, ±1000) are corroboration, not proof.
**Disasm:** no · **Source:** `P 08-part3-scene3-morph.md` "Assets" L20–35; `P 15-part002.md` L110–130 (`tools/vecobj.py`) · **Example:** yes, both.

### S-31 · Pair a carved screen with its own palette before believing it
**Decides:** whether a bitmap has been decoded at all. The tunnel texture under a grey ramp shows featureless rings; under its true 225-colour banded palette it is a red tiled tunnel with a repeated letter "A". Pairing is confirmed by matching the bitmap's colour *range* to the range the loader writes.
**Blind spot:** the palette is often loaded by a *different* region, so carve order does not imply pairing and an explicit override map is required. Cannot detect a **run-time modified** palette — fades and band rotations mean the "true" palette is only the frame-0 state. Plausibility is the failure mode, not the safeguard: a wrong palette yields a wrong-but-convincing picture.
**Disasm:** the pairing evidence is in the loader · **Source:** `P 06-part3-scene1-tunnel.md` L28–46; `P 10-part3-scene4-globe.md` L60–72 · **Example:** yes, both.

### S-32 · Distinguish loaded table from generated table by the allocator
**Decides:** asset versus computation. `GetMem` then a fill loop means generated (the two 59,904-byte whooshtext path tables, the 2,001-entry rotozoom sin/cos, the 500-point star cloud). `BlockRead` means asset.
**Blind spot:** a generated table is only as recoverable as its generator loop is readable, and the reverse case is invisible — a table read from disk *and then modified* looks like a pure asset. Cannot say whether a generator's formula is the author's or a simplification of one.
**Disasm:** yes · **Source:** `P 18-part006-credits.md` L48–75; `P 07-part3-scene2-stars.md` L15–35 · **Example:** yes, both.

### S-33 · Treat absence from the asset map as a pointer to DGROUP
**Decides:** where content actually lives. Part 003 scene 3's shape data is missing from the DAT map because it is compiled in as typed constants. **Absence from the asset map is a signal to search the data segment, not evidence that content is procedural.**
**Blind spot:** the genuinely-generated case looks identical until the DGROUP search comes back empty. Gives a place to look, never a verdict.
**Disasm:** no, once DGROUP is located · **Source:** `P 04-neurosis-dat.md` "Not everything is in the blob" L58–63.

### S-34 · Reconstruct a table's identity from an exact numeric relation, not from adjacency
**Decides:** what a table *is*. `NoteBounds[i] = round(sqrt(NotePeriods[i] * NotePeriods[i+1]))` — the geometric midpoint between adjacent semitones, 83 of 83 pairs, no exceptions, which is exactly what a "first entry not exceeded" search needs because pitch is logarithmic.
**Blind spot:** nothing in the code names a table; only the values do, so a table with no closed form is untouchable this way. And the relation must be *exact* — being 168 bytes from a known period table was the argument that produced the wrong answer (W-33).
**Disasm:** no, once extracted · **Source:** `V CONTINUATION.md` L860–880 · **Example:** yes.

### S-35 · Scan a declared array for its non-zero extent
**Decides:** how much of a generously declared table is authored. 500 six-byte star waypoint records, only 56 non-zero; the walk runs 50 down to 1, so 51–57 are authored-but-unreachable and 443 are padding.
**Blind spot:** a zero-valued record can be legitimate data (a zero offset, a zero dwell), so the boundary is a heuristic; and non-zero data outside the walked range proves nothing about intent. Prefer the deflationary reading (W-32).
**Disasm:** no for the scan · **Source:** `P 07-part3-scene2-stars.md` "Resolved — the unwalked tail" L60–72 · **Example:** yes.

### S-36 · Read a base-1 array as one element low
**Decides:** stride, base and bound origin. `IMUL DI,[idx],$26 / ADD DI,$123a` with the array at `$1260` is `array[1..8]` of a 38-byte record. Ten in the DemoVT tree; six in `12ba`; five in `PLAYMOD`'s variable block alone.
**Blind spot:** gives stride and base, not element count. **A base-1 array declared at its own base-1 base is invisible to byte comparison** — `array[0..8]` at `$02e1` and `array[1..8]` at `$02e2` produce an identical displacement; only the neighbour's address settled it. And the bias creates address collisions: a displacement matching a known variable exactly can be the compiler's index subtraction, not a reference (W-36). **An unexamined `+1` is a symptom.**
**Disasm:** yes · **Source:** `V CONTINUATION.md` L127–150, L1275–80, L2100s.

### S-37 · Recognise ASCII-art-derived and transposed character data
**Decides:** that geometry was authored as text. Part 001 fills eight 256-byte line buffers with `$FF`, loads text, compares each character against **two marker characters**, and emits a 3-D point per match at `x := (col−1)*10 − 90`, `y := (row−1)*−8 + 32`, capped at 144 points. Part 006's board is `array[1..26,1..16,1..8]` storing letters **on their side**, because the renderer maps board row to screen X.
**Blind spot:** the marker comparison is what proves ASCII-art origin, and it disappears if a build step baked the points. Transposition is invisible until you find the renderer's axis mapping — read straight, the letters are noise. Recovers neither the source text nor the points the markers and the cap discarded.
**Disasm:** yes · **Source:** `P 14-part001-intro.md` "Scene 4 — 3-D text banner" L110–130; `P 18-part006-credits.md` "The board" L28–46 · **Example:** yes, both.

### S-38 · Mine strings, captions and debug symbols as first-class evidence
**Decides:** identity and intent, cheaply. Portrait captions in DGROUP name all four faces outright; a scene announces its own parameter (`THIS WHOOSHTEXT HAS 4000 DOTS!!!`); an error string documents an enforced constraint; the setup program's menu strings reconstruct the whole config grammar.
**Blind spot:** **strings state claims, not facts — dead data reads exactly like live data.** Bands 17–26 of the whooshtext board spell `0,000 DOTS` and are never copied onto the board: an abandoned earlier take left in the binary. The docs handle this well, flagging a four-member identification from `PSYCHO.NFO` as "context, not proof" until the captions confirmed it.
**Disasm:** no · **Source:** `P 13-part3-scene7-sprites.md` L48–75; `P 20-parts000-009` L50–70 · **Example:** yes, both.

### S-39 · Catalogue the constants segment first; it names most of the system
**Decides:** identities program-wide from one segment. `1caa:0000..0c6f` yields the published name, eight `String[4]` extensions on stride 5, seven `String[18]` driver names on stride 19, `'M.K.FLT46CHN8CHN'`, `'JMPLAY'` (six raw characters, no length byte), and the period table as 7×12 words on a 24-byte stride.
**Blind spot:** strings name *capabilities*, not the code implementing them — eight module formats means the recogniser you found is one among several still unread. A string can be dead: `'inconexi'` is compared and nothing reads the flag. Stride and length-byte structure must be measured, not assumed.
**Disasm:** no · **Source:** `V 00-map.md` "What the constant area says" L265–299.

### S-40 · Derive a format constant from arithmetic that could not land there by accident
**Decides:** file-format identity. `154d:0bf7` compares four bytes at buffer offset `$438` = 1080, which is exactly `20 + 930 + 1 + 1 + 128` — the ProTracker signature position. "The arithmetic is not a coincidence and nothing else lands on 1080." Same method for `$258`/`$3b6` as 15- vs 31-sample header sizes, and GUS timer 2's 320 µs behind `2_000_000 div (Rate*320)`.
**Blind spot:** an argument from the absence of alternatives, only as good as your knowledge of the format space; a constant coincidentally equal to a well-known offset will be over-read. And it proves the layout the *code assumes*, not the layout the data has.
**Disasm:** yes · **Source:** `V 00-map.md` L904–27; `V 04-units.md` L1410–39 · **Example:** yes.

### S-41 · Recover a structure from its allocator's size formula, cross-checked against the deallocator
**Decides:** record layouts. A pattern block is `Chans*2 + 4` — two header bytes, one word per channel, and an unused word at `+2` that exists only because the channel index is one-based; `165a:0c53` frees it with the same formula read back from the stored `Chans` byte. A track's streams are freed using the size recomputed from the stream's own `Count`, so the size is never stored.
**Blind spot:** two classes built from one template share `+2`/`+6` layout and have *different* size formulas — "Reading one of them with the other's formula makes it look like an allocation bug, and it is not." So the formula identifies a class only once you know which class you are looking at.
**Disasm:** yes · **Source:** `V 04-units.md` L1318–47, L1259–97.

### S-42 · Recover a record's layout from two producers writing consecutive slots
**Decides:** a whole driver record. Two unrelated units each write eight far pointers into consecutive slots and hand `RegisterDriver` a pointer exactly `$16` below the first — in both. So: `$16`-byte header, eight far method pointers at `+$16..+$35`, `Next` at `+$36`. Confirmed from a third direction by DGROUP spacing: four device records 58 bytes apart fixes `SizeOf(TSoundDevice)`.
**Blind spot:** the delta fixes the header *size*, not its contents — the release later revealed a one-byte `DMA` field this tree had swallowed into the ID string. Consecutive-slot writing cannot distinguish a method table from any other pointer array; slot semantics came separately from call sites. Only the *stride* is measurable, never field names or values.
**Disasm:** yes · **Source:** `V 00-map.md` L457–88; `V CONTINUATION.md` L1580–86 · **Example:** yes, the two-column table.

## D. Hardware, devices and interrupts

### S-43 · Identify the video mode from the specific CRTC/Sequencer/AC registers written
**Decides:** resolution and memory layout. CRTC Offset := 80 gives a 640-pixel logical line, which is what makes hardware panning possible; clearing the low five bits of CRTC 9 turns double-scanning off, giving 320×400; Sequencer 2 is Mode-X planar; CRTC `$0C`/`$0D` give a coarse start address in 4-pixel steps with AC `$13` supplying the remainder; `INT 10h` alone with no port I/O is a plain BIOS mode.
**Blind spot:** registers reveal *display* geometry, never how the program addresses memory — the two 320-wide pages side by side at byte offsets 0 and 80 of a 160-byte row are visible only in the clear and flip routines. Cannot see refresh rate, and cannot separate unchained 320×240 from 320×200 without the row table. Recurs in 6 docs.
**Disasm:** yes · **Source:** `P 08-part3-scene3-morph.md` L60–80; `P 15-part002.md` L30–45 · **Example:** yes, both.

### S-44 · Read the plane-select to tell four planes of one image from four frames
**Decides:** whether N same-sized reads are animation frames or the Mode-X planes of one larger image — settled by a `VGA_SelectPlane` (Sequencer 2, Map Mask) call **before each read**.
**Blind spot:** tells you the data is planar but not the logical width; a wrong de-interleave stride still yields a plausible image (the tunnel's "twin ring centres" were purely a stride artefact). Cannot distinguish planar interleave from a legitimate 4-frame set if the loader sets the mask once outside the loop. **This produced the same withdrawn conclusion independently in two different parts** (W-29).
**Disasm:** yes, needs the loader's port writes · **Source:** `P 06-part3-scene1-tunnel.md` "How we know it is 640×400" L48–70; `P 15-part002.md` L25–50 · **Example:** yes, both.

### S-45 · Distinguish co-existing row tables before believing any address arithmetic
**Decides:** which screen a table addresses. Two tables coexist with different multipliers — `y*320` for the mode-13h software screen and `y*160` for Mode-X per-plane stride. Conflating them produces nonsense. Identify a table by its multiplier and its consumers, never by a role-sounding name.
**Blind spot:** two tables with the same stride and different purposes are indistinguishable by this test. Deliberately oversized tables (800 entries for a 400-row screen, so indexing needs no bounds check) mean table length carries no reliable geometry information.
**Disasm:** yes · **Source:** `P 05-vga-unit.md` "Row tables" L142–49; `P 21-building.md` L379–81.

### S-46 · Identify hardware by a triple — port-scan table, register numbers, arithmetic constant
**Decides:** which card a layer drives. The GUS was identified on three independent pieces of evidence: a 12-entry base-port scan (`$220 $240 $200 …`), register numbers `$45/$46/$47` plus Adlib `base+8/9`, and the 320 µs timer arithmetic; plus a softer fourth, `(X shl 9) and $1FFFFE00` as a DRAM voice address. The Sound Blaster was identified by the `$AA` handshake after a 1/0 reset pulse — "and nothing else does it."
**Blind spot:** identifies the card the code *targets*, not the card present, and cannot distinguish a clone or a compatible mode. Gives nothing for devices with no distinctive protocol — the docs correctly refuse to name `1065`, which writes `$3F8` on IRQ 4: "What card this is has not been established." It later proved to be a UART used purely as a *clock*, not a sound device, which is the cautionary case.
**Disasm:** yes · **Source:** `V 00-map.md` L510–62, L745–78, L928–52; `V 04-units.md` L9–66 · **Example:** yes, all three.

### S-47 · Read a device detection routine as a specification of the device
**Decides:** canonical detection idioms. Write two different patterns into two different registers, read back masked, restore both, all under `CLI` — "using two voices and two values is what distinguishes real independent registers from a floating bus that returns the last thing written". Write-and-read-back on the SB Pro mixer register `$22`; a DSP version compared against `$200`.
**Blind spot:** detection code encodes the author's *beliefs* about the hardware, including his bugs and his era's cards. The register widths it masks to (`$1FFF` = 13 bits) are the code's assumption, not necessarily the chip's.
**Disasm:** yes · **Source:** `V 00-map.md` L1148–73; `V 04-units.md` L146–57, L346–61, L391–405.

### S-48 · Identify an INT hook by its chain stub, reading the displaced vector out of the instruction's operand
**Decides:** how a hook installs and uninstalls. DemoVT stores neither displaced vector in a variable: both INT 1Ch and INT 2Fh chain through a five-byte `JMP FAR` whose **operand** is patched, both assembled pointing at themselves, which is why the uninstall paths read `ES:[DI+1]` and `ES:[DI+3]` — they are reading the jump's own address bytes. Idempotence is free: the stub's operand doubles as the "are we hooked" flag.
**Blind spot:** because there is no variable, a *variable-oriented* search for the saved vector finds nothing and can wrongly conclude the hook never chains. Invisible to any data-flow tool that does not model self-modifying code. And searching by "who calls SetIntVec" misses these entirely — the doc records the inconsistency: one hook uses `Dos.GetIntVec`/`SetIntVec` while "the hand-rolled ones are the two that need a chain."
**Disasm:** yes · **Source:** `V 00-map.md` L197–204, L969–1005; `V 01-int2f.md` L12–75 · **Example:** yes, `1b54:0000` + `1b54:0088`.

### S-49 · Reconstruct an INT-2Fh handshake from computed replies
**Decides:** the resident-detection protocol. Request `AX=5654h 'VT' / BX=5472h 'Tr' / CX=6163h 'ac'`; the reply is computed, not stored — `XOR AX,AX`, `XOR BX,6b65h`, `XOR CX,7220h` — with `ES:DI` the resident's own name and the control-block far pointer at `ES:[DI-4]`.
**Blind spot:** because the reply is XOR-computed, **a string search for the magic reply values finds nothing** — you must read the handler. The request constants *are* searchable, and that asymmetry is the thing to exploit.
**Disasm:** yes · **Source:** `V 01-int2f.md` "The handler — `1b54:0006`" L16–45 · **Example:** yes, cross-checked against the client side in `psycho/src/DEMOVT.PAS` — a direct cross-project confirmation.

### S-50 · Find the published control block by following what Install was handed
**Decides:** the exported shared-state block and its size. `Install(DS:$0004, DS:$22C6)` puts the block at `1caa:22c6`; `FillChar(DS:$22c6, $300, 0)` fixes its size at 768 bytes; the dispatcher far pointer the client fetches at `CB+$121` therefore sits inside it.
**Blind spot:** does not enumerate the block's *fields* — those were found one at a time by noticing writes that fell inside the range. Anything the program never writes and no client is observed reading stays unknown, and read-only clients leave no trace at all.
**Disasm:** yes · **Source:** `V 01-int2f.md` L77–103; `V 04-units.md` L1870–97, L2143–82.

### S-51 · Distinguish client-writable from program-owned fields by finding fields nothing inside writes
**Decides:** the direction of an interface. `12ba:0693` reads three bytes nothing inside DemoVT ever writes, so it is a seek request — "the only part of the control block written by the client rather than read." It even derives the required write *order*: position and row first, flag last, because the sequencer tests only the flag.
**Blind spot:** "nothing writes it" is a statement about the completeness of your transcription, not about the program. And it can never prove a field is *intended* as an interface rather than dead — the doc is careful that Psycho Neurosis never uses it.
**Disasm:** yes · **Source:** `V 01-int2f.md` L163–95.

### S-52 · Recognise a real-mode pointer-normalisation cluster as a segment-crossing marker
**Decides:** where the program deliberately handles more than 64 KB. Three routines add the delta in 32 bits, push the overflow into the segment, and keep the offset in 0..15; everything that walks past a segment boundary goes through them. Related: `Seg(Buf) shl 4 + Ofs(Buf)` compared against `$10000` is 8-bit DMA boundary handling, and `SHR CL,1 / RCR BX,1` halving a 32-bit quantity across `CL:BX` is the 16-bit DMA word-count conversion.
**Blind spot:** marks *intent* to cross a boundary; cannot tell you whether the arithmetic is correct, nor find the places that should have used it and did not.
**Disasm:** yes · **Source:** `V 04-units.md` L513–32; `V 00-map.md` L428–46, L988–1005.

### S-53 · Read an interrupt handler's stack switch and guard placement as structural evidence
**Decides:** that a routine runs at interrupt time. `1a17:1008` stashes `SS:SP`, switches to a private stack, and holds its re-entrancy guard **in the code segment**, "so it is correct before `DS` has been set up and regardless of who is calling."
**Blind spot:** a `CS:`-resident guard is invisible to any DGROUP-partitioning pass and will look like a code byte that mysteriously changes. Conversely, a handler that *omits* the switch is not thereby non-interrupt code.
**Disasm:** yes · **Source:** `V 00-map.md` L857–81; `V 04-units.md` L72–92.

### S-54 · Read CLI/STI brackets as a concurrency contract
**Decides:** which state is shared with an interrupt. `14b9:0687`'s teardown is `CLI`-bracketed because "the INT 1Ch hook is reading these same fields four times a tick, so the teardown has to be atomic against it — there is no 'stop the player first' step."
**Blind spot:** absence of `CLI` proves nothing — the author may simply have had a race. And the bracket shows *that* something concurrent exists, not what.
**Disasm:** yes · **Source:** `V 04-units.md` L969–90, L1812–30.

### S-55 · Profile hardware usage per binary as a triage table
**Decides:** where to look first. Counts of functions, instructions, INT 10h/21h/2Fh and `OUT DX` per binary; `OUT DX` count proxies graphics weight, and the profile flags the odd one out — part 007 reprogramming the PIT, part 006 writing the PIC at `0x20`/`0xA0`, part 008 at 1 function and 17 instructions being still packed.
**Blind spot:** purely a proxy. A part doing its VGA work through a helper, or via `OUT imm8`/`OUTSB`, under-counts. Measured on the *current* disassembly, so counts move as recovery improves. Ranks binaries; never says what an effect is.
**Disasm:** yes · **Source:** `P 01-binaries-and-loading.md` "Per-part hardware profile" L82–97 · **Example:** yes.

## E. Behaviour and algorithm recovery

### S-56 · Ask first whether there is any per-frame pixel work at all
**Decides:** the class of the effect, before any maths is attempted — and the answer is repeatedly "none". The tunnel is a preloaded image moved by hardware panning plus palette rotation; the globe is a table-driven scatter blit; the block dissolve never draws anything and just adds 1 to existing pixel values through a ramp; the waves walk 51 precomputed curves. Companion heuristic: **cost accounting distinguishes designs** — 800 particles erasing their own previous pixel is 1,600 writes against 64,000 for a screen clear, which explains the absence of a clear.
**Blind spot:** decides *where* the computation happened, not what it computed — a baked table hides its generator completely, and S-29 recovers shape rather than parameters. Cannot see build-time authoring intent, and mis-frames scenes whose effect really is arithmetic on pixel values. Recurs in 6 docs.
**Disasm:** partly · **Source:** `P 06-part3-scene1-tunnel.md` "What it actually is" L5–25; `P 11-part3-scene5-blocks.md` L5–15, L38–46 · **Example:** yes, both.

### S-57 · Read the shift count to recover the fixed-point format and scale
**Decides:** the binary point position, directly from the arithmetic — a 32-bit multiply then `>>14` is 16.14 (table entries ×16384); `(a*b)>>16` is 16.16; `shr 6` on screen coords is a 6-bit fraction; `shl 8` before a perspective divide is a ×256 projection scale. `CWD` before each `IMUL` marks a 16-bit value widened for a 32-bit intermediate, the tell for integer-only lerp.
**Blind spot:** gives the *scale*, never the *units* — whether a 16.14 value is a sine, a pixel coordinate or a world unit is invisible. Cannot see overflow behaviour or intended range, and a table's ×16384 scaling is only trustworthy once its values are checked against a known function. Recurs in 6 docs.
**Disasm:** yes · **Source:** `P 08-part3-scene3-morph.md` L100–125; `P 22-part002-scene2.md` L150–70 · **Example:** yes, both.

### S-58 · Identify a shared sine/cosine table from the offset gap
**Decides:** that one table serves both functions, and by how much. Sin at `$02A8` and cos at `$035C`: a gap of 180 bytes is 90 word entries, so `cos(a) = sin(a+90)` from a single 450-entry table. Part 002's is a 901-entry quadrant-folded **cosine** table in tenths of a degree, whose *first* var parameter receives the cosine.
**Blind spot:** the gap proves the phase relationship, not the domain — entry count and angle unit must come separately. Cannot tell which parameter is sin and which is cos without reading the stores, and getting that backwards mirrors every rotation silently. Recurs in 5 docs.
**Disasm:** yes · **Source:** `P 08-part3-scene3-morph.md` L48–58; `P 22-part002-scene2.md` L143–50 · **Example:** yes, both.

### S-59 · Recover the angle unit from the wrap constant
**Decides:** whether angles are whole degrees, tenths, or table indices. A `360.0` wrap plus a π multiply proves degrees; wraps of `$E10` = 3600 and `$E06` = 3590 with steps 60 and 20 prove tenths of a degree; a 72-entry table at 5° per step spans 360° in 72 frames.
**Blind spot:** **the wrap constant looks exactly like a table size** — flagged explicitly as "easy to misread a 3600 wrap as a sine-table size". And units are not uniform across parts of the same program: part 001 uses tenths where part 003 uses whole degrees, so the finding never generalises beyond the segment it was measured in.
**Disasm:** yes · **Source:** `P 14-part001-intro.md` opening callout L5–10; `P 06-part3-scene1-tunnel.md` L74–95 · **Example:** yes, both.

### S-60 · Recover 3-D projection and depth sort from integer arithmetic
**Decides:** the camera model, from the divide. `SX := XOfs + ((X shl 8) div Z)` is a perspective divide at scale 256; `D := 2500 - Z'` names the view distance and `if D >= 0` the near clip; the initialised values `$046A`=320 and `$046C`=240 fix the projection centre at **(160,120), not (160,100)**. Depth order is a selection sort on average Z per face — painter's algorithm — and solidity comes from a fill routine issuing `N−2` triangle calls, so a fan, so filled not wireframe. Depth shading falls out of Z directly.
**Blind spot:** gives the transform but not the **handedness or axis assignment**, which is why models were unrecognisable from the obvious view (W-28) and why a translation written onto the wrong axis leaves Z at zero and sprays the object across the screen — diagnosable only by running it. Nor does it reveal culling semantics: the emitted face count here is never written back, so the tail of the array holds last frame's data, readable only from the *absence* of a store. Recurs in 6 docs.
**Disasm:** yes · **Source:** `P 22-part002-scene2.md` L175–200; `P 07-part3-scene2-stars.md` L38–55 · **Example:** yes, both.

### S-61 · Classify the frame pacing by what ends the loop
**Decides:** whether a scene is self-timed, retrace-paced, music-gated or timer-driven — four mechanisms found and separated. A loop tail `FCOMP float ptr CS:[0989]` then `JNC` is `while Radius >= 1.0`; a fade called 64 times is one step per frame across the full 6-bit DAC range, so 640 frames is about 9 s at 70 Hz; `DemoVT_SyncPattern(1,n)` waits for the MOD to reach a pattern, "the only place in the demo where the music drives the structure"; PIT reprogramming appears in exactly one part.
**Blind spot:** none of these give wall-clock duration without an assumed refresh rate — 70 Hz is an assumption about the mode, not a measurement. Cannot see pacing that *fails*: a frame overrunning the retrace budget looks identical in the code. Recurs in 7 docs.
**Disasm:** yes · **Source:** `P 06-part3-scene1-tunnel.md` L96–104; `P 15-part002.md` L165–75 · **Example:** yes, both.

### S-62 · Recover the choreography by tabulating call-site constants
**Decides:** the scene's script, reduced to a table of (phase, frame count, object, rotation deltas, renderer) read purely from the immediates at each call site — 14 phases for part 002 scene 2, eight 45-frame morph segments, four wave passes, the lemming release script.
**Blind spot:** gives the *nominal* script, not what a viewer sees — cannot detect a skipped phase, a `KeyPressed` guard aborting a fade mid-way, or a data-dependent exit. Tabulates cleanly only because the script *is* straight-line; any data-driven branch defeats it. Recurs in 6 docs.
**Disasm:** yes · **Source:** `P 22-part002-scene2.md` L205–50; `P 12-part3-scene6-waves.md` L55–70 · **Example:** yes, the 14-row table.

### S-63 · Read the palette-fade loop's shape and call count
**Decides:** fade direction, rate and duration. A fade **in** reads each DAC entry back and steps any channel below a target table up by one; a fade **out** is the same shape stepping every non-zero channel toward black and therefore **needs no target table** — the absence of a target is the tell for direction. Rates read off the increment: +3 to brighten, −5 to fade, −1 for a slow close.
**Blind spot:** cannot see whether the fade completes — every loop here is `KeyPressed`-guarded, so the nominal 64 steps is an upper bound. Says nothing about palette state established elsewhere, so "fades to black" is silent about what the DAC held at entry. Recurs in 5 docs.
**Disasm:** yes · **Source:** `P 10-part3-scene4-globe.md` "The fades" L74–88; `P 13-part3-scene7-sprites.md` L88–96 · **Example:** yes, both.

### S-64 · Recover a game state machine by enumerating the dispatch chain, then look for the gap
**Decides:** the full behaviour set *and its holes*. Ten states recovered from the dispatch on a state byte; the record layout (25 slots × 21 bytes) derived from the routine that writes every field at spawn plus the one that resets a subset. The countdown field works in **both directions** — positive ticks down and arms a state, negative ticks up and frees the slot. And **there is no state 9**: the walker puts a lemming into state 9 on colour `$12`, and it then falls through every branch, so it is drawn forever but never moves, ages, or frees its slot.
**Blind spot:** shows reachable behaviour, never intent — the doc is explicit that whether state 9 was meant as the level exit or is an oversight "cannot be told from the code". Does not show which states the shipped level exercises, and gives no field semantics for slots nothing writes (offset +4 read as "unused" until it turned out to count second landings, W-38).
**Disasm:** yes · **Source:** `P 16-part004-lemmings.md` "The state machine" L60–100, "The lemming record" L20–45 · **Example:** yes.

### S-65 · Recognise collision-against-the-framebuffer with set-literal terrain classes
**Decides:** that there is no collision map at all — a `GetPixel` reads the virtual screen and solidity is a Pascal **set membership test** on the pixel colour, so the level artwork *is* the collision data and digging is destructible terrain for free. The two 32-byte set literals live in the **code segment** behind a `CS:` override. The *difference* between the ground and wall sets is exactly the `$20..$29` band — one byte of set difference encoding a hazard stripe that blocks and kills but cannot be stood on; `$4D` is in both, which is why laid bricks become walkable the instant they are drawn.
**Blind spot:** the sets say which colours mean what, never where they are — topology is only in the artwork. And the semantics of a colour in *neither* set are visible only in the walker's trigger branches, so reading the sets alone misses three behaviours.
**Disasm:** yes — the `CS:`-override literal is easily missed and the set test appears as an RTL call · **Source:** `P 16-part004-lemmings.md` L46–72 · **Example:** yes.

### S-66 · Recognise segment:offset-as-fixed-point texture addressing
**Decides:** an idiom that otherwise reads as nonsense. A 320×200 image is copied into a **256-wide** buffer allocated as a full 64K segment so that `Dest[X] := Mem[Hi(V):Hi(U)]` uses the high bytes of two 16-bit fixed-point coordinates directly as a segment:offset pair. Wrapping is free because both wrap at 256 by construction: no masking, no bounds check, no multiply, one `MOV` per pixel.
**Blind spot:** conceals the fixed-point *format* — the 8.8 split is implied by `Hi`, not stated, and the fractional bits are simply discarded, so there is no interpolation, a visual property the code never advertises. It depends on real-mode segment arithmetic with no analogue in a modern target, so fidelity here is a re-implementation decision rather than a transcription.
**Disasm:** yes · **Source:** `P 17-part005.md` L5–40 · **Example:** yes ("the best trick in the demo").

### S-67 · Read a computed jump into an unrolled body, and recover N from the entry arithmetic
**Decides:** the shape of a self-patching unrolled loop. `NEG AL / AND AL,7 / MOV AH,$0F / MUL AH / ADD AX,$14D8 / JMP AX` is eight copies of a fifteen-byte body, entered so a run of N starts N-mod-8 bodies from the end; the body's instruction lengths are checked to total exactly fifteen. Deeper case: the configurator writes `3 * (32 - Channels) - 70h` into a `LOOP` displacement, so **the loop's own branch target is the channel count.**
**Blind spot:** a computed-goto body has no symbol and no prologue, so it is invisible to S-09 *and* to any call-graph tool. And because absent channels are skipped by moving a *branch target*, **no data value anywhere records the channel count** — the configuration lives in the instruction stream, and a dataflow analysis finds no variable to read.
**Disasm:** yes · **Source:** `V 00-map.md` L714–26, L821–56; `V 06-transcription.md` L295–318 · **Example:** yes.

### S-68 · Locate self-patch sites by stores into `CS:` at a fixed stride
**Decides:** presence and count of patch targets — four instructions writing the same register into four addresses in their own code segment, fifteen bytes apart. "Four patch sites at a fixed stride is an unrolled loop having a constant poked into it."
**Blind spot:** it found only four of the eight bodies, because "the rest of the patcher runs on past where the init disassembly stopped" — **a stride scan bounded by where you stopped reading under-reports.** Says nothing about what the patched immediate means.
**Disasm:** yes · **Source:** `V 00-map.md` L714–26.

### S-69 · Read a run-time-installed jump table to find frameless routines
**Decides:** the frameless code the prologue scan missed, and the control flow between blocks — following four installed pointers yielded the whole direct-DAC chain, which then imposed a work order: one block "has to follow" another, not precede it.
**Blind spot:** the table reveals only the *entries*, not the internal jumps back into other blocks — which is exactly what made two blocks mutually undecidable: "neither can be verified without the other." Nothing in the table shows that dependency.
**Disasm:** yes · **Source:** `V 04-units.md` L716–36; `V 06-transcription.md` L259–75, L362–90.

### S-70 · Read a `Jcc` with a zero displacement as a deleted source block
**Decides:** that source was commented out — `75 00` is a `JNZ` to the next instruction, and the release has five lines commented out at exactly that point. Explicitly generalised on its second instance: "a general reading, not a one-off".
**Blind spot:** shows a block was removed, never what it was — and the surviving condition looks meaningful when it is inert. The release's commented-out source is the obvious place to look and is itself untrustworthy (P-42).
**Disasm:** minimal, a two-byte pattern · **Source:** `V CONTINUATION.md` L1630–34.

### S-71 · Match a file-format decoder to a published spec by magic word and chunk-type numbers
**Decides:** that a routine reads a known format, and which variant. Magic `$AF12` is FLC (`$AF11` FLI); the handled chunk types 4/7/11/12/15/16/18 map one-to-one onto the standard set. Header sizes corroborate (128-byte file, 16-byte frame, 6-byte chunk), and the error string documents the enforced constraint.
**Blind spot:** matching type numbers to a spec does not verify the decoders are correct or complete — a subtly wrong decoder still dispatches from its slot, and off-spec fixups hide here (one chunk's size is fixed up by +2). Because dispatch is through a **table of procedure pointers**, the type-to-routine mapping is data, not code, so a static read can pair them wrongly.
**Disasm:** partly · **Source:** `P 19-part007-flic.md` L5–35 · **Example:** yes — the extracted asset plays in any FLIC viewer, an external validation of the match.

### S-72 · Chase a bitmap indexed off a different base than it was loaded to
**Decides:** whether an apparently unreferenced buffer is dead. A 1,550-byte block loads to `DS:$5448` and nothing else mentions `$5448`, because the glyph index is computed off `DS:$5122` and `$5448 − $5122 = 806 = 32·25 + 6` — a 5×5 font biased by 32.
**Blind spot:** **"no reference to the load address" is worthless as evidence of deadness** — this is the technique's whole point, and it was learned by being wrong twice over (W-30). Conversely the bias resolves only if you can guess the glyph dimensions to divide by, and it cannot see a bias applied in a register rather than as a constant base.
**Disasm:** yes · **Source:** `P 15-part002.md` L200–35; `P 22-part002-scene2.md` L330–45 · **Example:** yes, with the recovered glyphs dumped as ASCII art.

### S-73 · Take the base address from the instruction, never from block order
**Decides:** which record a run of stores belongs to. Each object's angle/translation/pivot block sits *after* its own face loop and *before* the next object's vertex loop, so a block "looks like it introduces object 3 when its addresses are object 2's". Recovered by subtracting the known field offset from the store address.
**Blind spot:** requires the record layout to be known already — the offset you subtract *is* the assumption. And it cannot flag its own failure: a translation on the wrong axis leaves Z at zero, diagnosable only by running it.
**Disasm:** yes · **Source:** `P 22-part002-scene2.md` L95–135 ("**Do not read those blocks positionally**") · **Example:** yes.

### S-74 · Validate index base by range-checking against the element count
**Decides:** whether a stored index array is 0- or 1-based, by trying both biases and rejecting the one that produces out-of-range indices. One object's bias 1 puts 3 indices outside `1..68`.
**Blind spot:** **cannot disambiguate when both biases fit** — the Enterprise's 1..74 and 2..75 are both inside 1..75, and it took a separate argument (which vertex is never referenced) to settle. It also silently assumes a single convention across the file, which is exactly what was false here: the four objects are not built the same way (W-27). Encoded into tooling afterwards so the class cannot pass silently.
**Disasm:** the range check is not · **Source:** `P 22-part002-scene2.md` L360–400 · **Example:** yes, the four-way loop table.

### S-75 · Diff the same unit across parts to find what each copy carries
**Decides:** which shared units are genuinely shared and where they diverge. The VGA unit is 1,002 bytes in one part against 266 in another, because one copy also carries a Bresenham line drawer. Conversely three maths routines are identical across parts, so recovering one recovers all three; and a 1,550-byte font is byte-identical between two parts.
**Blind spot:** size and shape equality do not prove behavioural equality — a routine can be the same shape with a different constant table. Cannot say which variant is the original, and identical bytes across parts say nothing about whether both parts *use* them (which is how the font was assumed dead, W-30).
**Disasm:** partly · **Source:** `P 14-part001-intro.md` L35–42; `P 22-part002-scene2.md` L143–200 · **Example:** yes, both.

### S-76 · Rank remaining work by how much of a segment is hardware
**Decides:** effort per byte. A unit talking to a Sound Blaster has no version drift to find, because the hardware did not change between versions, so release bodies transfer verbatim including `ASSEMBLER` routines — fourteen of seventeen blocks exact on the first build. Compare the mixer and the effects unit, which drifted heavily.
**Blind spot:** a heuristic about drift, not difficulty — and the *device* unit sitting above the hardware unit still drifted in six places.
**Disasm:** no · **Source:** `V CONTINUATION.md` L1602–06.
# TIER 2 — BORLAND PASCAL

## F. Compiler and toolchain identity

### P-01 · Settle a compiler-identity claim by installing the other compiler
**Decides:** which compiler emitted the binary. "The evidence is not an argument, it is a measurement." Same sources, two compilers, tabulated: byte-identical units 1→2, mismatched 4→3, `FILEUTIL` 3 regions→identical, `SOUNDDEV` 10→6, `VTRESID` 24→21. **"No unit got worse"** — every unit that agreed under TP7 agrees under TP6 with the same pending-fixup count, to the byte.
**Blind spot:** **explicitly bounded by the docs.** One divergence survived every compiler in the image, so "the original's toolchain is TP6-like and is not this exact TP6 — the compiler-identity question is narrowed, not closed." Agreement across two versions cannot rule out a third. And it later turned out that surviving divergence was not the compiler at all but hand-written asm (W-13).
**Disasm:** no · **Source:** `V 06-transcription.md` "THE COMPILER IS TURBO PASCAL 6" L556–605; `V CONTINUATION.md` L560–600 · **Example:** yes, the comparison table.

### P-02 · Nominate a discriminator construct in advance, then test it
**Decides:** compiler identity with one measurement. A value-`String` parameter's frame copy was registered in advance as the best single test, "on the reasoning that it is a compiler decision no source shape can reach and that it recurs program-wide." TP6 makes the runtime call the original makes. Kept afterwards as a **regression check**: a compiler that inlines it is not the original's.
**Blind spot:** decisive only if the construct really is unreachable from source, which is a judgement; and it narrows the field to "compilers that agree on it", as P-01's residual shows.
**Disasm:** no · **Source:** `V 06-transcription.md` L578–91, L1141–49.

### P-03 · Build a compiler probe — one tiny routine per claimed difference, compiled by every available compiler
**Decides:** whether a "the compiler did it" claim survives. `probe/PROBE.PAS` holds one routine per divergence the docs recorded as a compiler difference, **with the original's bytes quoted above each one**; `probe.py` compiles with every `TPC.EXE` in the image, locates the code by its first prologue, and diffs. The compiled probe is ~256 bytes, so a claim is settled in one build of a few seconds against the 10 KB of context a real unit drags in. **"It has been the cheapest instrument in this project and it found more in its first run than the previous three sessions of byte-chasing."**
**Blind spot:** a probe measures the construct *as you wrote it*, which is why it kept finding the source rather than the compiler at fault — it cannot distinguish "the compiler differs" from "I have not found the right source shape". It only tests the compilers you have. And the sharpest limit: **a probe can answer a question about the wrong STAGE** — the smart-linking probe correctly showed TP6 emits both empty bodies, which was irrelevant because the `.TPU` keeps every routine and the *linker* removes them. Ask whether the question is about the compiler, the `.TPU`, or the EXE. Its own confounders are real: a directive list takes one dollar sign for the whole list, and switches must come from the harness because `$G+` decides whether 286 instructions are emitted at all.
**Disasm:** no · **Source:** `V 06-transcription.md` "The compiler probe" L733–826; `M demovt-compiler-probe` · **Example:** yes — six probe routines with verdicts, of which five overturned a parked claim.

### P-04 · Take the release's `TPC.CFG` as ground truth for switches — then check each switch per unit
**Decides:** the build switch set. Adopting it moved every figure in the size table: before that "every unit except one was being compiled as plain 8086 — `$G+` was never set." Two units then landed on the original's byte count exactly, "the first hard evidence that the target is reachable at all."
**Blind spot:** a config from a *later* release is not necessarily the original's, and **one switch turned out to need to be per-unit, not global** — `$G-` makes one unit byte-identical but "building the whole tree `$G-` wrecks twelve of the fifteen." A global config file can never settle a local switch, and a whole-tree test of a local switch looks like a refutation.
**Disasm:** no · **Source:** `V 06-transcription.md` L1254–68, L1204–19.

### P-05 · Turn stack checking off before believing any prologue diff
**Decides:** whether a prologue mismatch is real. TP7 defaults `{$S+}`, and with it on *every* framed procedure — **including an `assembler` one** — opens with seven bytes of `XOR AX,AX` / `CALLF <check>`. Passing `/$S-` dropped ~940 bytes per EXE and made 47 routines line up.
**Blind spot:** it is a **global** switch, so it cannot tell you one particular original unit was built the other way — and part 005 **was** built `{$S+}`, needing an explicit per-unit override against the global `/$S-`. Invisible in routines with no frame. Same lesson as P-04: switches are per-unit facts, not project facts.
**Disasm:** no · **Source:** `P 23-deviations.md` "Stack checking is OFF, and it has to be" L118–32; `P 26-part5-notes.md` L24–29 · **Example:** yes, "47 routines line up".

### P-06 · Read the compiler switches off the ABSENCE of RTL check calls
**Decides:** switch state from what is missing. A routine with no `CheckIO` call after any `Assign`/`Reset`/`Seek`/`BlockRead` was compiled `{$I-}` — load-bearing here, because the code seeks a `file` record that was never assigned or opened, and only `{$I-}` makes that survive (the RTL sets `InOutRes` and returns). Turn checking on and the demo dies there. Generalises to `{$R-}`, `{$Q-}`, `{$S-}`.
**Blind spot:** tells you the switch state only for code paths that *would* have emitted a check — a unit with no I/O gives no signal. And it cannot distinguish "the author chose `{$I-}`" from "the author's bug was masked by it"; separating those needs reading what the failing call actually does.
**Disasm:** yes · **Source:** `P 23-deviations.md` L250–64; `P 28-part7-notes.md` L131–41 · **Example:** yes, that is the example.

### P-07 · Date the target CPU off instruction encodings, and set `{$G+}` accordingly
**Decides:** the CPU floor. `SHR DI,2` — a shift by an immediate other than 1 — is a 286 encoding, so the unit needs `{$G+}`; `PUSHA`/`POPA` are 186. Recorded as a knowing non-deviation: the reconstruction will not run on an 8086.
**Blind spot:** gives a *lower* bound only for code paths that happen to use a wide encoding — a 286-targeted unit written in 8086-safe encodings looks like 8086 code. And it tells you which units of *ours* must carry the switch, never which of the original's did.
**Disasm:** byte patterns suffice; a disassembler makes it practical · **Source:** `P 23-deviations.md` L83–91; `P 24-continuation.md` L415–17.

### P-08 · Scan for the `0x66` operand-size prefix to find `{$L}`-linked external TASM code
**Decides:** which parts linked external assembler. TP7's *built-in* assembler stops at the 286 — `{$G+}` is documented as "Generate 80286 Code", the help file never mentions the 386, `MOV EAX,EBX` is rejected — therefore **any 386 instruction inside a 16-bit segment is an exact marker for `{$L}`-linked TASM.** Scanning every part for `0x66` and clustering the hits produced a whole-project table. Corroborating tells: `NOP NOP` padding after forward conditional jumps, and full 7-byte 32-bit-immediate encodings.
**Blind spot:** **a large false-positive class you must subtract by hand** — the TP7 RTL's own LongInt multiply/divide helpers are 386-pathed and byte-identical in every part (a CPU-type test), and they are not yours. It cannot find external asm containing no 386 instruction, so a 286-only `{$L}` object is invisible. And it cannot say what the module *exported*, only what got called.
**Disasm:** the scan is byte-level; clustering wants disassembly · **Source:** `P 24-continuation.md` "Which parts used external 386 assembler — the full sweep" L184–217 · **Example:** yes, the seven-part table, which identified the one real gap.

### P-09 · Use the unreferenced exported routine as evidence for whole-object linking
**Decides:** that a module was `{$L}`-linked, and that the original `.ASM` exported more than you knew. The same 16.16 divide appears in three parts and nothing calls any copy — TP7 links an object **whole**, so a PUBLIC nobody uses still lands in the EXE. The same argument later found two more routines missing from the reconstruction's `.ASM`, taking the module from three routines to five.
**Blind spot:** cannot say what the dead routine was *for*, nor whether it was dead in the author's own source or merely in this part. And it cannot detect exports the linker discarded — TP's *unit* smart-linker does discard, so the argument is specific to `{$L}` objects. **Membership of an external object is established by its whole extent, not by its call graph** (W-24).
**Disasm:** yes, needs absence of xrefs · **Source:** `P 24-continuation.md` L206–17; `P 26-part5-notes.md` L308–30.

### P-10 · Use assembler ENCODING differences as a fingerprint for which tool produced a region
**Decides:** hand-asm versus compiled versus externally-assembled, from a five-row table: `AND AL,AL` is `22 C0` in TASM and `20 C0` in TP's inline asm; `XOR AL,AL` `32 C0` vs `30 C0`; `ADD AX,AX` `03 C0` vs `01 C0`; `RETF 4` expressible in TASM and not in TP; and for `SUB BX,AX` **it reverses** — `29 C3` in TP's inline asm, `2B D8` in TASM — while TP's **code generator emits neither**, because it forces AX as the accumulator. That three-way split identified a whole run as an external TASM module. Used positively too: `31 C0` and `33 C0` for `XOR AX,AX` in the same segment mean two tools.
**Blind spot:** the available assembler is **not the original's** — TASM 4.1 is a 1996 build, "close on the encodings it explains, open on anything it does not." Encodings discriminate only where the two tools disagree; identical encodings prove nothing. And **the table can be wrong entry by entry**: `09 C0` (`OR AX,AX`) was listed as an inline-asm tell and is compiled Pascal, the code generator's own way of testing the sign of the low word after an `Integer(...)` cast. Each tell needs its own counter-example hunt.
**Disasm:** no — assemble a probe and read the bytes · **Source:** `V 06-transcription.md` L606–53; `V CONTINUATION.md` L820s, L1078–86; `M tp7-encoding-traps`, `M demovt-handwritten-asm-tells` · **Example:** yes, the encoding table and the six-instruction probe.

### P-11 · The TP7 encoding traps — same instruction, different bytes
**Decides:** why perfect-looking source produces wrong bytes. `RET` inside a FAR `assembler` proc emits `CB` where originals have `C3`; `SUB AX,BX` gives `29 D8` vs `2B C3`; `ADD AX,AX` `01` vs `03`; `AND AL,AL` `20 C0` vs `22 C0`; `XOR AL,AL` `30 C0` vs `32 C0`. Shift forms **do** agree, "which is why the style survives review — the shifts are the visible majority of most routines."
**Blind spot:** invisible to code-size checks and to reading, and **systematic** — one occurrence means every occurrence of that mnemonic in the tree is wrong. So the fix is to grep the whole tree for the mnemonic, never the instance: the `SUB`/`RET` pair was fixed in one file and left in three others, hit eight times across three files in one session.
**Disasm:** no · **Source:** `M tp7-encoding-traps` · **Example:** yes, the table.

### P-12 · The 66h-prefix traps for 386 code in a 16-bit assembler
**Decides:** how to spell 386 instructions. **A `66h` prefix widens the immediate**, so `DB 66h; MOV BX,-1` gives four bytes where `MOV EBX,imm32` needs six "and the next two get eaten as the rest of the immediate". Register-only forms are safe. Fix: opcode as `DB`, value as `DD`/`DW`, which also puts the patch label exactly on the immediate. Also: `CWDE` is not a TP7 mnemonic (`DB 66h; CBW`, both opcode `98`), and the two `CS:`-override forms do not carry the same prefixes — "do not assume the prefix pattern carries across a block."
**Blind spot:** the failure is a **silent length change that swallows following bytes**, so the error surfaces as a cascade of unrelated-looking divergences downstream, never at the offending line.
**Disasm:** no · **Source:** `V 06-transcription.md` L337–61; `M tp7-encoding-traps`.

### P-13 · Cross-dialect traps when moving asm between TP inline and TASM
**Decides:** why a converted module diverges. Four, each having cost a build: **"Turbo Pascal's statement separator is TASM's comment"** — `DB 66h; SAR BX,3` lost every shift, **188 divergent regions from one character**; Pascal hex is not TASM hex (`$00` is undefined; `Ch` is an identifier, `0Ch` is not); the pad is `DB 0`, not `EVEN`, because TASM's `EVEN` fills with `90h`; and the harness reported a clean build as a failure because TASM prints "Error messages: None" on success and the check was a substring test.
**Blind spot:** all four are silent in the sense that the build succeeds — only byte comparison finds them. And one character producing 188 regions means **region counts mislead about the number of causes.**
**Disasm:** no · **Source:** `V 06-transcription.md` L680–709.

### P-14 · Prove a TASM `{$L}` object byte-exact, and the three settings that must be right
**Decides:** that an external module reproduces the original. Three settings were caught by the diff, not by reading: **`USE16` on the segments** (after `.386` TASM defaults `USE32` and TP7 answers "Error 47: Invalid object file record"); **EXTRNs must sit in a `DATA` segment inside `DGROUP` with `ASSUME DS:DGROUP`**, or TASM assumes `CODE` and prefixes every reference with `CS:` — five bytes where the original has four, reading the wrong segment; and **forward-jump `NOP` padding is the original assembler's**, so write every jump `short` explicitly and emit the padding as literal `nop`, making layout deterministic rather than a function of the assembler's pass count.
**Blind spot:** a code diff sees only emitted bytes — not the original module's segment names, macros or ordering; not routines the object exported that no part calls (P-09); and **not the linked-in data table**, which needed separate numeric verification. The masked DGROUP holes also hide any wrong-variable binding.
**Disasm:** no for the diff · **Source:** `P 23-deviations.md` "The 386 maths is a TASM object, and it is byte-exact" L265–302; `P 26-part5-notes.md` L308–30 · **Example:** yes, the three-routine table.

### P-15 · Explain runs of NOPs as the assembler's `JUMPS` padding
**Decides:** that a NOP run is an artefact, not dead code and not alignment. TASM reserves the long form of a forward jump on pass one and fills what it did not need: 3 NOPs after a `Jcc` (5 reserved, 2 used), 1 after a `JMP`, 2 after `MOV reg8,<forward equate>`. **The test that confirms it: every padded jump is a FORWARD reference and every unpadded one is not** — and the two unpadded forward jumps are the two the release writes with explicit `SHORT`, which suppresses `JUMPS`. Eleven such runs in one object module, all consistent.
**Blind spot:** it explains padding only for the assembler you have — reproduce the runs as explicit `NOP`s rather than relying on a modern TASM's own padding decisions, which is the same reasoning as P-14's third setting.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L840s; `M demovt-handwritten-asm-tells` · **Example:** yes, eleven runs.

### P-16 · Handle dialect differences by rewriting the STAGED copy, not the source of truth
**Decides:** how one tree builds under two compilers. TP6 has **no `far` directive on a unit's exported routines at all** — it rejects one on the interface declaration (error 73) and on the implementation header of a routine the interface already declared (error 36); the calling model comes from `{$F}` at the point of declaration and nowhere else. So the harness rewrites the staged copy into an `{$F+}` region from `interface` to `implementation`. **Whole-unit `{$F+}` is wrong** — it promotes the private routines the interface never mentions.
**Blind spot:** a regex-based rewrite has its own failure mode — the declaration must be matched **whole**, because a parameter list separates its groups with semicolons too and `[^;]*` stops short on every routine taking more than one group. It also collides with the staleness check, which must accept the rewritten form or the whole tree reports STALE. And harness keying is fragile: the rewrite was keyed on the compiler name and a new version string broke it.
**Disasm:** no · **Source:** `V 06-transcription.md` L871–95; `V CONTINUATION.md` L601–12.

### P-17 · Bootstrap-compile to break a circular unit reference the compiler rejects
**Decides:** how to build a `uses` cycle TP6 refuses from scratch. Compile the unit once with a conditional that removes the implementation `uses` and the table's initialiser while **leaving the INTERFACE byte-for-byte identical**, compile the dependants against that `.TPU`, then recompile for real — emitted inside the per-unit loop, because the unit needs its own dependencies first.
**Blind spot:** **the whole class of bug is invisible in an incremental build** — `.TPU`s accumulate and only a CLEAN build deadlocks, "which is almost certainly what the 1992 author hit and never noticed." And the harness had **two separate erasures**, the Python-side wipe and the batch file's own `del *.TPU`; the first fix missed the second, so **anything measured under `--keep` is suspect until a clean build agrees.**
**Disasm:** no · **Source:** `V CONTINUATION.md` "~~THE `SongLoaders` DEVIATION~~ — GONE" L1418–45 · **Example:** yes.

## G. Reading source shape off the bytes

### P-18 · Read the frame to recover the parameter list — offsets in order, never the total
**Decides:** parameter order, count and widths, because TP puts the first declared parameter at the **highest** `[BP+n]`. Two hard cases make the case for byte verification outright: a filter's `Apply` had the order wrong and "would have read the sample count out of the filter strength at run time — this is the strongest argument for byte verification in the whole file: it was a real bug, not a cosmetic difference, and nothing else would have found it." And **a reversed parameter list can pass every size check** — a reversal totalling the same 22 bytes still emitted the right `RETF $16` and the right unit length, while every `[BP+n]` inside was wrong.
**Blind spot:** **the total will not tell you** — and two errors can cancel, as when an invented extra `Word` parameter compensated for a missing `far` and left the frame identical either way. The frame cannot reveal a parameter the body never reads (a `RETF 2` with the value taken from DGROUP), findable only from the `RET n` or the release. And it cannot reveal **widths**: a Byte argument still occupies a word on the stack, so a wrong declaration survives until something calls it — check widths from the **call site**.
**Disasm:** yes · **Source:** `V 06-transcription.md` patterns 5, 6, 16, 22 (L934–1069), L1113–25; `V CONTINUATION.md` L2690 · **Example:** yes, both.

### P-19 · Argument and result widths come from the call site — but a variable's width is settled by its widest access
**Decides:** declared types. `MOV AL,x / XOR AH,AH / PUSH AX` is a `Word` parameter; without the zero-extension it is a `Byte`. `09 C0` on a result is a Word-returning function even when stored into a Byte (`08 C0` is the Byte form). Three signatures corrected this way.
**Blind spot:** **and it caused a real error** — a field was declared `Byte` from one caller's `MOV AL / PUSH AX`, and another segment does a six-byte **WORD** compare on it. The truncation was at the call, not in the storage. **"One unit's call site is not evidence about another's."**
**Disasm:** yes · **Source:** `V CONTINUATION.md` L2600s.

### P-20 · Cross-segment caller audit of a finished unit's interface
**Decides:** signatures, by re-reading a unit against every new call site. **Seven interfaces were wrong in units that already measured byte-perfect**: two Words that were one `Pointer`, five invented names, a `Pointer` that was an untyped `var`, three value parameters that were `var`s, a signedness, a `Word` that was a `Byte`, and a routine not exported at all.
**Blind spot:** **this is the technique's whole point — a unit measuring perfect says its BODIES are right, not its declarations.** A `Pointer` parameter and an untyped `var` are the same four bytes inside the routine and `LDS SI,Src` loads the same address from either; they differ only where the argument is *pushed*. A `Pointer` and two `Word`s occupy the same four bytes of stack, so **nothing inside the unit could ever catch it.** It only works once a caller exists — so **treat every new caller as a test of what it calls.** Distinguish from the self-evident case, where the routine's own `RETF` disagrees with its declaration.
**Disasm:** yes, the call-site push pattern · **Source:** `V CONTINUATION.md` "A PARAMETER LIST CAN BE WRONG IN A WAY ONLY A CALLER IN ANOTHER SEGMENT REVEALS" L1180–1200, L2127 · **Example:** yes, all seven.

### P-21 · Read locals off `[BP-n]` — order, count, alignment and result slots
**Decides:** the local declaration block. Do not declare locals the original did not have (an invented `Char` local makes the compiler spill to `[BP-1]`); declaration **order** sets the frame (thirty single-byte differences "that looked like noise and were not"); **TP never reuses a dead local's slot, so the same offset means the same variable** — which revealed that the original reuses a `FOR` counter it has finished with; a `Word` local is word-aligned, so three preceding bytes become four and `[BP-4]` is padding, not a variable; and **assign to the function identifier, not to a local** — `[BP-1]` is an odd offset TP will not give a declared variable, so that byte is the function **result**, which lives at the *top* of the frame above the parameter copies.
**Blind spot:** **the frame size will not tell you.** Stated outright: a fix that kept a spurious fourth byte still gave `ENTER 8,0`, "so the frame size went on agreeing while eleven references stayed one slot out." Four bytes plus a word and three bytes plus a word both give `ENTER 8,0`. **Getting the local COUNT right matters as much as the order.** And a larger `ENTER` than the locals explain is a **compiler temporary** before it is a missing variable — a 256-byte surplus is a string concatenation temporary, and inventing a local to explain it manufactures a second error on top of the first (three units made this error).
**Disasm:** yes · **Source:** `V 06-transcription.md` patterns 3, 14, 18, 21, 23 (L925–1077); `V CONTINUATION.md` L1120–35, L1305–20.

### P-22 · Read a stack-frame overshoot as a compiler temporary, and count `Write` groups to recover the statement
**Decides:** what created the surplus. `WriteLn(A+B+C)` gives one `Output` push, one temporary, copy/append/append/write/break; three separate `Write`s give three push-and-call groups and no temporary. A bare `WriteLn` after `WriteLn(X)` costs ten bytes and prints a blank line the original does not.
**Blind spot:** only sizes and shapes are visible — it cannot say which expression was concatenated. Distinguishing needs a second observation: a value `String` parameter is already copied to `[BP-$100]`, so a second copy would be visible.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L1120–39.

### P-23 · Read control-flow shape — `for`, `while`, `Exit` and `goto` are distinguishable
**Decides:** which statement produced a branch. Borland's `FOR` opens `MOV var,0 / JMP past / INC var / body`; a `WHILE` puts the test at the top with no jump past an increment. An early `Exit` gives `JNZ +2 / JMP end`, a conditional jump around an unconditional one, where wrapping the body gives a single `JZ end` — "fixing this one line took `1065` from 57% to 99%." A `goto` gives `CMP / 74 02 / EB 06`, where a nested `if...then begin...end` folds to one `JNZ +16`, two bytes shorter.
**Blind spot:** misattributes when two constructs coincide, and this was the tree's biggest single misread — a `for` read as a nested `if`, where "the `INC` that looked like an `else` branch is the loop increment", which propagated into three wrong facts (variable role, nesting, guard placement). Also blind to **equivalent conditions with different bytes**: `<= 0` and `= 0` are the same test on a Word and different bytes, so "when a comparison against zero is one byte out, try the other spellings before looking for anything structural."
**Disasm:** yes · **Source:** `V 06-transcription.md` patterns 2, 11, 24; `V CONTINUATION.md` L461–70.

### P-24 · Read the jump TARGET before deciding what a branch encloses
**Decides:** statement shape when the bytes nearly match. **The single most productive habit in one segment — six statement shapes came from it and nothing else**: a guarded `mod` that was not nested; a volume clamp landing *on* the clamp, so common to both arms rather than inside one; an `else` landing past three statements, so it covers all three; an early `Exit` where a wrapped `if` had been written; and the grouping `(True and A) or B` rather than `True and (A or B)`. It works in reverse too: one jump goes **backwards**, turning an apparent tautology into a `while` head — "a note calling it dead code had to be withdrawn one iteration after being written."
**Blind spot:** these are all same-behaviour source forms that compile to different bytes, so **reading cannot separate them and neither can testing** — only the target can. Conversely nothing static distinguishes a right from a wrong landing: the wrong one compiles and often runs. **Before writing "dead code", "redundant" or "tautology", find every branch that lands there.**
**Disasm:** yes · **Source:** `M demovt-jump-targets`; `V CONTINUATION.md` L2047; `P 27-part6-notes.md` L292–320 · **Example:** yes, six in one segment plus three in Psycho part 006.

### P-25 · Read the loop guard's comparison, and where the loop variable is initialised
**Decides:** signedness, edge behaviour and cross-pass state. Bounds tests that are **unsigned** (`JBE`/`JNC`) mean the coordinates are `Word`, while a later display-list pass genuinely *is* signed (`JLE`/`JGE`) — the two are not interchangeable; one routine uses `IDIV 32` for a remainder and `SHR 5` for the quotient, signed and unsigned in the same expression. Separately, whether the loop variable is initialised **inside or outside** the loop decides whether a later pass carries on from where the last ran out.
**Blind spot:** for values that never go negative in practice, signed and unsigned behave identically, so the bug hides until an edge case. A guard tells you the comparison, never the intent. And init-placement produces cosmetically identical output for the *first* iteration — the difference only shows from pass two onward.
**Disasm:** yes · **Source:** `P 24-continuation.md` L135–40; `P 26-part5-notes.md` L126–47, L242–67.

### P-26 · Read a "skip" versus an "end" off the control flow, not the sense of the value
**Decides:** `continue` against `break`. **A black pixel is skipped, not an end** — a `JNZ` to the recording code and a `JMP` straight to the increment mean the scan carries on either way. Read as `while GetPixel <> 0` the whole effect stops on the first pixel and **produces nothing at all**, which reads as the scene skipping ahead. Same family: an overlay that advances its destination pointer on **every** byte shifts the rest of the picture left rather than leaving a gap, so whether `INC DI` sits inside or outside the store *is* the semantics of a transparent blit.
**Blind spot:** both readings produce a running program, and the difference is a blank screen you may attribute to something else entirely. This is the **invisible correct-looking failure** class — `continue` and `break` differ by one branch.
**Disasm:** yes · **Source:** `P 26-part5-notes.md` L242–67; `P 27-part6-notes.md` L225–31.

### P-27 · Recognise the `with` statement by its hidden frame slot
**Decides:** that a routine used `with`. The original stores the accumulated offset beside DS — `ADD DI,OFFSET Base / MOV [BP-4],DI / MOV [BP-2],DS` — then does `LES DI,[BP-4]` at every field access. "That store shape is TP's `with`: it computes an indexed record's address once into a hidden frame slot. Which also means the `ENTER 4,0` is the compiler's slot and **the routine declares no local.**"
**Blind spot:** confusable with an explicit pointer local — `Ptr(Seg(X), Ofs(X[i,j]))` emits exactly what `@X[i,j]` does, so neither is the answer. Only the *hidden* nature of the slot distinguishes it, which means you must already have the local count right (P-21). A written pointer local gives `LEA AX,[DI+Base] / MOV DX,DS` instead, because an assignment needs a pointer **value** and a `with` never forms one.
**Disasm:** yes · **Source:** `V 06-transcription.md` L461–70; `V CONTINUATION.md` L2100s.

### P-28 · Read expression-level detail — operand order, integer width, forced widening, evaluation order
**Decides:** the exact expression text. Operand order: `Port[$3f8] + (Port[$3f9] shl 8)` written the natural way round emits the two `IN`s in the wrong order. Integer width: `IMUL AX,[Rate],$140` is one 286 instruction on a WORD where `LongInt(Rate) * $140` widens first and calls the 32-bit runtime multiply — "it also settles what the variable is: a 16-bit product only stays in range for a tick rate, not a sample rate." A constant can exist purely **to force a wider type**: a 32-bit `SUB AX,0 / SBB DX,1` whose borrow is thrown away looks like decoration, but writing `- $10000` is what makes the expression LongInt, and without it TP emits two bytes where the original has fourteen. And **TP evaluates the RIGHT operand of a 32-bit add first**, so a mixed expression's two halves swap if written the other way.
**Blind spot:** an expression that is **arithmetically identical** under two spellings can only be separated by the bytes — two fields were read as a position rather than a step, and "the arithmetic is identical either way, which is exactly why reading alone could not separate them." A call site or the release is needed. Evaluation order is invisible except as a byte difference and cost a build to find.
**Disasm:** yes · **Source:** `V 06-transcription.md` patterns 4, 8, 15; `V CONTINUATION.md` L1070–76.

### P-29 · Port pseudo-array — constant index is Pascal, computed index is assembler
**Decides:** whether `IN`/`OUT` code is faithfully Pascal. TP's port pseudo-array compiles to a bare `MOV DX,imm / OUT DX,AL` **only when the index is constant**; with `GUSPort + $102` it evaluates the address as an ordinary expression through AX. **`Port[X + $00]` is not `Port[X]`** — the written zero forces an address expression, three bytes and a different instruction order, from a `+ 0` that reads as harmless; four occurrences in one unit. Rule: **constant port → Pascal, computed port → assembler.**
**Blind spot:** **identical length, so every size-based check missed it** — this class is invisible to anything short of byte comparison. And the reverse direction was wrong for three routines declared inexpressible in Pascal: they were expressible, and the hand-written versions had the right instructions with the **wrong encodings**.
**Disasm:** yes · **Source:** `V 06-transcription.md` patterns 1, 13, 17 (L898–1004).

### P-30 · `Seg(P^)` versus `Seg(P)`, and casts that get the same value from the wrong instructions
**Decides:** which of two equivalent-looking forms was used. `LES DI,[BP+8] / MOV AX,ES` is what `Seg`/`Ofs` compile to when applied to what a pointer **points at**; reading the halves through a `TPtrRec` cast fetches them off the frame instead — same values, different instructions.
**Blind spot:** value-equivalence means testing cannot distinguish them; only bytes can.
**Disasm:** yes · **Source:** `V 06-transcription.md` pattern 12.

### P-31 · `assembler` procedure versus `asm` block in a normal procedure — and the epilogue is not suppressible
**Decides:** the declaration form, which is visible and decidable. An `assembler` procedure that names no parameter gets **no frame**; a routine opening `PUSH BP / MOV BP,SP` and closing `LEAVE` that neither needs nor uses the frame is a plain Pascal procedure whose body happens to be one `asm` block. And **an `assembler` procedure always gets an epilogue**, so a written `RET` emits a second one — "that alone was the whole of one unit's and part of another's divergence." Probed exhaustively: an epilogue appears after a trailing internal `JMP`, after a written `RET`, after a written `RETF 4` and after pure `DB` data — always. Mirror case: an `ENTER 000A` against the original's `ENTER 0006` meant two supposed locals were actually globals, proved by a store to DGROUP.
**Blind spot:** behaviourally identical either way, so **only a byte diff distinguishes them.** The rule set is small and its exceptions are discoverable only by probing — the "no frame" rule looked general and does **not** extend to a far `assembler` procedure with unnamed parameters, which still gets prologue and all. And the same evidence has a second reading: a *parameterless* original with a frame may simply be a plain procedure, which is why one routine cannot be verified at all.
**Disasm:** yes for the prologue; no for the probe · **Source:** `V 06-transcription.md` pattern 7, L796–815; `P 23-deviations.md` L184–203 · **Example:** yes, both directions.

### P-32 · Near versus far, and the entry/exit-count mismatch as the tell for an external module
**Decides:** whether a contiguous frameless run was ever Pascal. A handler chains with `E9 D2FF`, a **near** jump back to offset 0000, where `JMP FAR PTR` assembles five bytes and misses the idiom. And on a run's last byte: an interface procedure is far, so the epilogue emits `CB` where the original has a near `C3` — **if a frameless run's last byte is a near RET, the Pascal procedure wrapping it has to be near too.** Escalated: eight structural bytes in four places were all one thing, a frameless run wrapped in Pascal procedures each of which must have exactly one entry and one exit that the original does not have — so the run was an external TASM module all along.
**Blind spot:** for a long time this read as an **unavoidable deviation** rather than as evidence: "that is true of a Pascal procedure and false of the original, which did not use one." **A constraint of your reconstruction can masquerade as a property of the target** (W-11). Also, two entry points into one tail are invisible from the module that defines them — only the outside caller's target address reveals the second, and a `PUBLIC` label emits no bytes, so adding one and re-verifying is free.
**Disasm:** no · **Source:** `V 06-transcription.md` pattern 9, L328–36, L606–53; `V CONTINUATION.md` L1554–60.

### P-33 · Read a nested-procedure static link off the `RET n` and the `SS:` addressing
**Decides:** that a routine is nested rather than unit-level. Three routines all end `RET 2` and reach the enclosing scene's locals through a static link at `[BP+4]` — `MOV DI,[BP+4] / LES DI,SS:[DI-$0A]`. Making them unit variables turned every one of those into a DGROUP read; re-nested, one matches all 121 bytes. TP passes the enclosing frame's BP as an extra hidden parameter, which is why an iterator is `RETF 6` and not `RETF 4`.
**Blind spot:** the `SS:` addressing is the tell, but **a nested routine that touches none of the parent's locals looks exactly like a unit-level one.** The extra 4 bytes are indistinguishable from a genuine extra parameter unless you can see the enclosing frame being indexed — and if the enclosing routine is untranscribed you cannot. Two identical nested copies look like accidental duplication until you notice each has its own enclosing scope.
**Disasm:** yes · **Source:** `P 23-deviations.md` L205–24; `P 24-continuation.md` L98–110; `V 04-units.md` L550–75 · **Example:** yes.

### P-34 · Do not let the inline assembler resolve an enclosing scope's variable
**Decides:** a silent-wrongness trap. Written as `LES DI, SrcOfs` inside an `asm` block in a **nested** procedure, TP emits `LES DI,[BP-6]` — resolving the *enclosing* procedure's variable against the *nested* procedure's own frame.
**Blind spot:** **it compiles cleanly and nothing warns.** Only a byte diff or a crash finds it. Generalises: inline-assembler name resolution across scopes is not to be trusted for anything but the current frame.
**Disasm:** no · **Source:** `P 23-deviations.md` L230–41.

### P-35 · Declaration order changes displacement width, which shifts every later instruction
**Decides:** why a byte match breaks for no semantic reason. Behind a 128-byte `file` record a local needed `[BP-8E]` — a 16-bit displacement, one byte longer than the original's `[BP-6]` — which shifted every instruction after it. Fix: declare the scalars first and the file last, as the original does.
**Blind spot:** surfaces only under a byte diff; behaviourally the code is fine. Says nothing about the original's *reason* for that order.
**Disasm:** no for the fix · **Source:** `P 23-deviations.md` L224–29.

### P-36 · Recover a `String` field's declared size from a lone zero length byte plus the gap
**Decides:** field extents. `MOV byte ES:[DI+16],0` is `S := ''` — TP writes only the length byte — and the gap to the next touched offset gives the declared size.
**Blind spot:** only fields the initialiser actually touches appear; anything untouched stays filler, and the **contents** of an initialised string are never visible this way.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L1352–58.

### P-37 · Read a `CWD` as a type-width and signedness measurement
**Decides:** `Integer` against `Word`, and `ShortInt` against `Byte`. A `Count` sign-extended to LongInt forces a 32-bit compare 14 bytes bigger; `JLE` rather than `JBE` settles a byte field as `ShortInt`.
**Blind spot:** **visible only where the value is compared or mixed-width arithmetic is done.** Equality tests and plain stores are sign-independent, so units that only store or compare for equality can never see it — two units both missed the same field's signedness for exactly that reason.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L1372, L1690.

### P-38 · Use `SizeOf` immediates and pushed VMT-offset constants to name types and calls
**Decides:** which type is being constructed. `PUSH 000a`/`PUSH 000e` name two record types; `$03d0` = 16*61 pins a field; `MOV AX,0566 / PUSH AX` is the VMT offset naming *which* object is constructed, and a pushed **zero** there means an **inherited** constructor call that must not re-stamp the VMT.
**Blind spot:** a size can be coincidentally shared between two types, and it says nothing about field *names* — only extents.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L1345, L1367–80.

### P-39 · Recover VMT and object layout from the constructor's helper and slot arithmetic
**Decides:** that a type is an object and what it descends from. `XOR DI,DI / CALLF <ctor helper>` with a `JZ` over the whole body means "do not allocate / failure path"; both constructor and destructor are `RETF 6` (the hidden VMT word); `[DI+04]` is the first virtual slot because TP's VMT holds positive and negative size words at `+$00`/`+$02`. Ancestry is *measured*: `MOV DI,[DI]` with the link at `+0` proves `OBJECT(TObject)`, where a base with four Pointer fields would give the one-byte-longer `MOV DI,[DI+10]` — and that extra byte put every downstream block at shift +1.
**Blind spot:** **a record's free function and an object's static method call are byte-for-byte identical at the call site — only the constructor can tell them apart.** So layout is unrecoverable from any segment that merely calls the type's methods, and the constructor was in the segment nobody had read (W-06). Worse, the conversion is *free* — `TObject` has no fields so the link lands on two bytes already carried as filler — which is exactly **why nothing ever contradicted the wrong "plain record" reading for the whole project.**
**Disasm:** yes · **Source:** `V CONTINUATION.md` L1220–58, L1396–1402 · **Example:** yes, corroborated five independent ways.

### P-40 · Read a VMT's size word to name a type
**Decides:** an object's class, from the data rather than the code. A VMT is DGROUP data laid down where the type is declared, as `[size][-size][far pointers]`, **and its size word NAMES the type**: sizes 8/12/13 distinguished `TCollection` (VMT 2 + Items 4 + Count 2 + Limit 2 + Delta 2 = 12) from `TStringCollection` (13, adding `Duplicates`). **"A call site cannot name a type and a VMT can"** — a new instrument, and it came from the data rather than the code.
**Blind spot:** **an unreferenced VMT is smart-linked away entirely, so absence proves nothing** — and identical sizes cannot distinguish two types. This is the instrument that overturned the `SongColl` reading a *call site* had settled (W-01).
**Disasm:** no, once DGROUP is readable · **Source:** `V CONTINUATION.md` L127–50, L364, L380s; `M demovt-link-layout` · **Example:** yes, the 8/12/13 argument recovering 48 bytes.

### P-41 · Find a dead code region by the VMT that reaches it
**Decides:** that a large map gap is one missing *reference*, not missing code. With nothing calling a virtual method on one object, its VMT is dead, so the smart linker dropped every method of two units whose bodies are only reachable through it — 3,328 bytes for one statement.
**Blind spot:** gives no clue **which** statement supplies the reference.
**Disasm:** no · **Source:** `V CONTINUATION.md` "HOW `CMDLINE` AND `VTCMD` CAME BACK" L152–60.

### P-42 · Read the release for SHAPES, ORDER and NAMES — and never for DATA
**Decides:** what may be lifted from a later version. The stated method: find the routine in the release, **read it first**, rewrite to that shape, compile, measure, and only then chase what is left against the disassembly. Every shape in one unit was recoverable from the release's source in one read — `assembler` versus Pascal for all five register routines, the `FOR` bounds, all four writes inside the `IF`, the inverted gotos — where chasing them one divergence at a time cost several rounds each and found the same answers. Rule as hardened: **"take a layout only when the binary confirms it field by field."** One record type was adopted because all eighteen fields landed on already-measured offsets and it closed two open questions; another was rejected because the release's own history block records a February 1993 remodelling and its fields do not fit.
**Blind spot:** **the release is corroboration, never truth, and it is worth nothing for data.** Counts differ (`DevStkSize` 1000 vs 2000, `NumBuffers` 3 vs 1, `MaxOutputFreq` 45000 vs 44000, `MaxChannels` 8 vs 32); a volume table differs in every entry but the first; the tracker split one kernel into two after this version. It also invites the tree's strongest failure mode, plausible-mechanism reasoning. **And a commented-out line in the release is not a record of what the older version did** — "it means the author was editing that spot, and nothing more. Read the bytes." That trap caught the project **four times in two segments**, with five release source comments contradicted by the bytes in one unit alone. The documented exception: a *file format* fixed outside both versions does transfer — and even then the arithmetic was checked.
**Disasm:** no · **Source:** `V 06-transcription.md` L471–503, L1439–66, patterns 19–20; `V CONTINUATION.md` L1156–60, L1544–52, L1682–88; `M adopt-release-names` · **Example:** yes, many.

### P-43 · Do NOT take a TYPE from the release — and decline a rename that creates ambiguity
**Decides:** where corroboration stops. Two fields stay `Byte` against the release's `BOOLEAN` because the code tests `<> 0` and only ever stores a zero byte; a DOS link state stays a `Byte` because the code stores a number and hands the previous value back. Separately, a rename was **declined and logged**: the release's `Tempo` is also a *field* other code reads eleven times as `NoteProcessed^.Tempo`, and a word-boundary rename cannot tell `Tempo` from `.Tempo`.
**Blind spot:** for a value only ever 0 or 1 the bytes genuinely cannot distinguish, so this is a least-claim policy rather than a measurement. The rename judgement has no measurable content at all — which is why it is recorded rather than done. And **never take a record layout**: "rewriting those is a codegen change wearing a rename's clothes."
**Disasm:** no · **Source:** `V CONTINUATION.md` L1016–22, L1188–92, L1364–68; `M adopt-release-names`.

### P-44 · Adopt the release's names, and let the pass pay for itself
**Decides:** naming, since the original carries no debug information and every name in the reconstruction was invented. The release is a later version of the same codebase, so its names are the closest thing that exists — and they are **better** names (`ProbeDram` did not probe DRAM; `StopTimers` stopped only timer 1). Confirm each pairing by **reading both bodies**, never by position or a plausible-sounding name.
**Blind spot:** nothing proves the older version spelled anything the way the later one does — all names remain provisional in that respect. But the pass paid for itself in ways `verify.py` **could not see**: it found 26 bytes of code the original never had (an exported `Register` that was really a unit initialisation section), three globals one unit had duplicated from others — one of them standing in for two different addresses at once — and the meaning of a numeric selector. **Every one of those was invisible to the byte comparison**, because a reference to a global is a linker fixup and an extra init block sits past the compared range.
**Disasm:** no · **Source:** `M adopt-release-names`; `V CONTINUATION.md` L2478, L2500s · **Example:** yes, all nine units.

## H. Link, segment and DGROUP layout

### P-45 · Derive segment order by simulating candidate rules against a real map
**Decides:** the emit order and hence every segment address. **Segment order is reverse DFS post-order over the `uses` graph**, clauses walked in declaration order, interface clause before implementation, `SYSTEM` appended last. Reverse **pre**-order is the plausible wrong answer and transposes three units, "which is the cheapest way to tell them apart".
**Blind spot:** units that emit no segment — declarations-only — are invisible to it, and any unit already finished when the walk reaches it has an unobservable position.
**Disasm:** no, needs a map · **Source:** `V CONTINUATION.md` "THE LAYOUT RULES, all measured and none documented anywhere else" L127–90; `M demovt-link-layout`.

### P-46 · Read the original's segment addresses backwards as the link finish order, then test every `uses` edge against it
**Decides:** dependency truth. "**The constraint check is worth more than the prediction.** Every `uses` edge can be tested: if U uses V then V must finish first" — and an edge that fails is a dependency the original cannot have had. Two edges failed and each was a real defect.
**Blind spot:** proves an edge **impossible**, never names the correct owner — that took a separate address argument. And it is silent about units with no segment (P-47).
**Disasm:** no · **Source:** `V CONTINUATION.md` L175–90; `M demovt-link-layout` · **Example:** yes, both edges.

### P-47 · Locate a declarations-only unit by its DGROUP block, not by the map
**Decides:** the link position of a unit that emits no code. Its data block sat between two known units' blocks, fixing its place in the `uses` clause. **"A declarations-only unit is not invisible; it is invisible to the wrong instrument."**
**Blind spot:** needs the unit to own **initialised** data — a var-only declarations unit stays invisible.
**Disasm:** no · **Source:** `V CONTINUATION.md` L400s.

### P-48 · The DGROUP layout rules
**Decides:** where every datum lands. **DGROUP is two regions, each in link order** — every unit's TYPED CONSTANTS first, then every unit's plain VARIABLES, with declaration order inside each unit's block; each typed constant word-aligned and each unit's block starting on a word boundary. Consequences that keep mattering: a `var` where the original has a typed constant is not harmless, it moves the datum to the other region and shifts everything below it; **anything between two known typed constants must itself be one**, which settles the ones whose value is zero where the bytes cannot; two units' blocks cannot interleave, so **interleaved addresses prove a declaration is in the wrong unit**; and **an unreferenced typed constant is smart-linked away**, so every constant in the original's DGROUP is referenced by surviving code — **a gap is a search for a reference, never a place to invent filler.**
**Blind spot:** the **intra-unit** rule is not settled — typed constants appear to precede variables regardless of source section order (measured: moving a `var` section above a `const` moved nothing), but that is one observation and two bytes remain unexplained.
**Disasm:** no · **Source:** `V CONTINUATION.md` L127–50, L2500s; `M demovt-link-layout`.

### P-49 · Recover the variable (uninitialised) half of DGROUP from resolved fixups in the linked image
**Decides:** the layout of data that is not in the EXE at all. "The variable half is not in the EXE — **but the CODE records it**: in the LINKED image every DGROUP fixup is resolved, so a variable in the wrong place shows up as a wrong operand in every instruction that touches it." Each difference is then classified as a variable address, a constant address (a regression), or real code.
**Blind spot:** **a variable nothing references has no operand anywhere and cannot be placed or sized this way.** Requires order and every size already correct — the forced-ordering property of the model table.
**Disasm:** operand decoding, tool-internal · **Source:** `V CONTINUATION.md` "HOW THE VARIABLE HALF OF DGROUP WAS SORTED" L196–230.

### P-50 · Use `PUSH DS` versus `PUSH CS` to decide where a constant lives
**Decides:** typed constant (initialised DGROUP) against untyped literal (laid in the CODE segment immediately before the routine that uses it). The rule extends past strings: a segment head proved to be an untyped **`set of Char`** constant in the code segment, loaded `MOV DI,0 / PUSH CS / PUSH DI`.
**Blind spot:** does not give length — that came from the neighbour's address. Cannot see the constant's *value* when it lives in DGROUP. And a typed constant whose address is taken is forced DS-relative for an unrelated reason, so `PUSH DS` alone does not prove intent. **The rule was already written down and still got missed once**, putting a variable at an address belonging to something else: when a scan turns up a DGROUP address, check which segment register is pushed with it before believing it.
**Disasm:** two instructions' worth · **Source:** `V CONTINUATION.md` L470s, L1140–50, L2500s; `M demovt-byte-exact`.

### P-51 · An immediate where you expected a memory read means an UNTYPED const
**Decides:** typed against untyped. `MOV AL,1` where a sibling flag eight bytes later is `CMP [02c9],0`: untyped folds to a literal, typed stays in DGROUP.
**Blind spot:** cannot recover the constant's **name**. And an unreferenced typed constant is smart-linked away entirely — adding 64 bytes of filler grew the `.TPU` by 64 and the linked image by 0.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L2500s.

### P-52 · Prefer the routine that touches many fields or globals at once as the layout instrument
**Decides:** record field order and DGROUP block layout. An initialiser or a `Free` that passes eight field addresses is the declaration read off the binary; a detection routine rewriting 28 ports names them all; an init section filling four device records named eleven routines before a line was written; a dispatch table named seventeen at once.
**Blind spot:** fixes ORDER and SPACING, never the **values** (every DGROUP address is a fixup), and cannot name a field the routine skips. **One accessor is never enough** — a field named `Name` from a single accessor was wrong, and the routine touching seven fields in the release's order corrected it. Order-based naming also inherits any reordering between versions.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L1348–80, L1570–78, L1608–20 · **Example:** yes, four separate instances.

### P-53 · Cross-check ownership by structural (compiler-enforced) reasoning where the address cannot say
**Decides:** which unit owns a global. Unit A `uses` unit B, so B cannot use A, and the effect routines write the sequencer position directly — **the compiler simply refuses the wrong answer.** Five globals moved. Recorded as the first DGROUP ownership question in the project settled by a structural reason rather than an address. Third mechanism: two units' blocks cannot interleave, so interleaved addresses reassign ownership (nine globals moved that way).
**Blind spot:** **only works where a cycle would result** — compare the unit where three globals sat in the wrong place and nothing could see it. And **where a global is declared cannot change a byte, which is what makes the choice dangerous**: the byte comparison cannot tell a right home from a wrong one. Hence the discipline of recording, at every declaration, how well the address is known, and writing "no measured address" rather than quoting one that belongs to something else. Four globals are knowingly declared in two units each, all flagged.
**Disasm:** no · **Source:** `V CONTINUATION.md` L1000–20, L410s, L2478–2507.

### P-54 · Decline to export rather than create a shadowing bug
**Decides:** where a duplicate-named variable goes. Two same-named variables genuinely exist; exporting the second would put it in scope wherever the first unit is compiled and Pascal would silently bind every reference to the wrong one.
**Blind spot:** **a shadowing bug no byte comparison could ever see.** Nor can the bytes answer whether the original *meant* one variable and ended up with two. Keeping it in the implementation section is the least-claim fix.
**Disasm:** no · **Source:** `V CONTINUATION.md` L1022–32.

### P-55 · Prove a rename, export or re-home byte-neutral by requiring identical region AND fixup counts
**Decides:** that a refactor moved nothing. **This is the only proof available**, and it was run after each of nine pairings: one unit identical with the same 1,187 pending fixups after 37 renames and a five-global move; another with the same 1,024 after a signature change and a widened field; fourteen globals moved into two new declaration-only units with the same 871 fixups. A `PUBLIC` label emits no bytes, so adding one and re-verifying is free.
**Blind spot:** **a half-applied rename inside a routine below a placeholder is buried by a whole-unit prefix** — only the per-block measure caught one going 0→2 real differences. Rename hygiene is broad: it touches the build order, the verify list, every `uses` clause and qualified reference, and the docs; and the stale `.TPU` must be deleted or it lingers. A rename must be its own pass, changing nothing else.
**Disasm:** no · **Source:** `V CONTINUATION.md` L1290, L1360, L1385, L2478s; `M adopt-release-names`.

### P-56 · Sweep for orphaned comments after any bulk declaration move
**Decides:** documentation integrity. 39 declarations lifted into one address-ordered block left their notes behind, so an address note sat above the wrong variable. Two throwaway scripts found them faster than the compiler: one listing declarations no longer under a `const`/`var` header, one listing comment blocks whose leading address disagrees with the declaration below.
**Blind spot:** **beware the reverse** — a de-orphaning pass that deletes a `const`/`var` header whenever the next line is a comment removed five correct headers, because a note above a section's first declaration is the normal shape.
**Disasm:** no · **Source:** `V CONTINUATION.md` L2400s.

### P-57 · Exploit the smart linker: routines come out in source order with unused ones missing
**Decides:** whether several binaries have *different* copies of a unit or the **same** unit smart-linked differently. **Proof is the order**: survivors' offsets stay monotonic across all seven parts, and a missing routine shifts everything after it by exactly its own length. One case is pure arithmetic — a part that never pans lacks one routine, and `$6D − $2A = $43` is exactly the offset by which the next routine sits lower. This collapsed four "separate" units into two shared ones.
**Blind spot:** **cannot distinguish "same unit, different subset" from "two genuinely distinct units with identical bodies"** — which is exactly what one pair turned out to be, two distinct routines at different linear addresses with identical bodies. That needs a body-level comparison. It also cannot say *which* absent routine is missing without a candidate source order to test against, and it assumes the compiler does not reorder.
**Disasm:** needs a segment listing · **Source:** `P 24-continuation.md` "Resolved: there was only ever ONE VGA unit and ONE DemoVT unit" L218–88 · **Example:** yes — four duplicate units deleted, one unit became the union of 21 routines.

### P-58 · Transcribe strictly top-down, because TP lays procedures out in source order
**Decides:** work order and file order. A routine written out of order displaces everything below it and the prefix stops dead. Cheap tell: **a backward call to a misplaced routine gives `Unknown identifier`; a forward one compiles and silently misplaces 300 bytes.** Used positively: the release's implementation order with the absent bodies removed is exactly the original's address order — one agreement checking all fifteen routines at once.
**Blind spot:** presumes the segment layout **is** source order, which is true for Pascal code and **false for `{$L}` object code**, which lands after all Pascal code wherever the directive sits. Applied naively to a mixed unit it puts the module in the wrong place. It is also about source order, **not** about how much to write per build — misreading it as one-routine-per-build cost several slow sessions, where a whole 3,920-byte unit went in cleanly in a single pass.
**Disasm:** no · **Source:** `V 06-transcription.md` L456–70, pattern 10, L654–79; `V CONTINUATION.md` L1650–60, L1720.

### P-59 · Find the Pascal / `{$L}` boundary from the unit's init block plus a one-instruction test
**Decides:** where compiled code stops and the assembled module begins. TP emits a unit's initialisation block as the **last** Pascal code in the segment, so everything after it came from the `{$L}`. Confirmed by a self-patching store no Pascal statement produces, and independently by a `MUL WORD PTR [BP+0Dh]` reading **across two parameters**, which is inexpressible in Pascal.
**Blind spot:** a hand-asm run sitting *before* the init block would not be caught this way.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L810s.

### P-60 · Use `XLAT` / `MOV BX,imm` to prove a number is a DGROUP offset
**Decides:** that an immediate is a **data** offset even when the same value is a valid code address in the segment, because `XLAT` reads `DS:BX+AL`.
**Blind spot:** proves the segment, not **which unit** owns the offset, and nothing about the table's contents — which are initialised data invisible to a `.TPU` comparison.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L1058–63.

### P-61 · Link the whole program and diff segment sizes — the only instrument that sees the KIND of a construct
**Decides:** whether your program *references* the same set of routines the original's does. Three verdicts at once: segments at exactly the original's size prove the **references**, not just the bodies; absent segments; and smart-linked-down segments, each gap being a work list naming a missing reference.
**Blind spot:** **what only the link sees, and what it cannot.** It sees that an initialisation section transcribed as a named procedure is discarded — three units verified byte-identical for their whole lives and linked at zero, because "procedure nobody calls" versus "initialisation section" **is not a byte distinction**. Conversely the link cannot see DGROUP layout, and it forfeits the `.TPU`'s slack by fixing variable order and segment numbers. And its measurement hygiene matters: code sizes and segment lengths are not the same footing (S-20).
**Disasm:** no · **Source:** `V CONTINUATION.md` "THE FIRST MEASUREMENT OF THE LINKED IMAGE" L1400–1500 · **Example:** yes — three units recovered by one fix, 0→25, 0→138, 30→489.

### P-62 · Rebind compiled-in DGROUP offsets at startup instead of dictating data layout
**Decides:** how to keep hand asm untouched when the original identifies tables by absolute DGROUP offset. Make them Pascal typed constants and have a bind routine take `Ofs()` of each at startup. Effect on output: none.
**Blind spot:** **hides all offset arithmetic the original did *between* those addresses** — any code relying on two tables being adjacent, or on a stride between them, is not reproduced and nothing will say so.
**Disasm:** yes, to read the offsets · **Source:** `P 23-deviations.md` L65–82.

### P-63 · Recover the array base from how the binary indexes it, and index the same way
**Decides:** where a variable really starts. One grid was indexed **one element in** — the binary writes `[$73b9 + I*80 + J]`, so `[1,1]` is 81 bytes into the variable, not at its start; declaring `array[1..100,1..80]` and writing `Grid[I,J]` shifts everything by 81 bytes. Fix: **a flat array indexed exactly as the binary indexes it.** Sprite bank bases only resolve once you account for a one-based frame index, because the compiler folds `base − stride` into the instruction.
**Blind spot:** off-by-one bases produce plausible output; and the folded `base − stride` means **the nominal base address in the instruction is not a real object address**, so a naive address-to-variable map is wrong. Pascal's index bases and the binary's base arithmetic are independent: reproduce the arithmetic, not the notation.
**Disasm:** yes · **Source:** `P 27-part6-notes.md` L344–57; `P 25-part4-notes.md` L71–80, L415–24.

### P-64 · Read `var` versus typed constant off the file image to decide what is real source
**Decides:** what the original source said. `var X : T` lands in BSS and is **not** in the EXE; `const X : T = (...)` lands in initialised data and **is**. So anything readable out of the file image was a typed constant. Corollary used as a consistency check: BP7 typed constants are writable by default, which is *necessary* for the tunnel's in-place per-frame palette rotation.
**Blind spot:** the inference runs one way only — data absent from the image might be a `var`, heap-allocated, or computed, and the test cannot distinguish. It says nothing about type or dimensions, so a packed block still has to be segmented by hand. And it cannot see **data past the end of the file image**, which reads as blank at run time.
**Disasm:** no for the presence test · **Source:** `P 03-borland-rtl.md` "Aside: `var` vs typed constants" L327–47; `P 27-part6-notes.md` L245–70.

### P-65 · Transcribed DGROUP tables must hold REAL DATA, because bytes cannot see that they do not
**Decides:** a functional-correctness rule the byte comparison is structurally blind to. Two note tables were declared as uninitialised `var`s, so the table-building routine was reading zeros — **a functional gap the byte comparison could never see, because initialised DGROUP data is not in a `.TPU`'s code.** Transcribed out of the image instead: 168 bytes of data changed no code and the unit still verified identical with the same six pending fixups.
**Blind spot:** by construction — only the *link* can move on this. The related trap: the same data indexed two ways (flat, and by octave row via an `IMUL`) is why a table keeps its 2-D shape; a flat declaration would lose the `IMUL`. **Byte-exactness of code is not correctness of the program.**
**Disasm:** no · **Source:** `V CONTINUATION.md` L900–15.

### P-66 · Never transcribe an absolute address out of the original's data segment
**Decides:** the **dominant recurring bug class** in the Psycho work. The binary is full of `MOV AX,[6]`, `MOV DI,[BX+96DAh]`, `MOV AX,164Eh` — offsets and segments in the *original's* DGROUP. Transcribed literally they compile cleanly and read whatever our build happens to have there. Five instances of one mistake in different clothes in a single part. Three countermeasures actually deployed: a lint rule rejecting the pattern outright; **initialised data at those addresses extracted from the image into generated includes**; and a whole-tree grep once one is found.
**Blind spot:** **the compiler accepts it, the byte checker masks exactly these bytes as "displacements that must differ", and the program often runs.** Nothing but a wrong screen or the lint catches it. Symptom-to-cause mapping is many-to-one, which is why two reported symptoms were chased as two bugs and were one (W-42).
**Disasm:** yes to read the addresses; the countermeasure is disassembler-free · **Source:** `P 24-continuation.md` L126–34, L403–08; `P 27-part6-notes.md` L322–52.

### P-67 · Two inline-assembler syntax traps that silently change meaning
**Decides:** two silent-wrongness classes. `SEG` is an **operator**, so a record field named `Seg` is a syntax error inside an `asm` block. And **`[SomeConst]` on an untyped const assembles as an absolute address, not a variable read** — so anything the original reads *from memory* must be declared a **typed** constant.
**Blind spot:** the second **compiles cleanly and nothing warns.** Only a byte diff or a wrong-looking screen surfaces it — and the symptom class is the hardest of all, *silent absence*: DAC data declared as a plain `var` gave zeros, wrote black, and a whole conveyor belt simply was not on screen (W-45).
**Disasm:** no · **Source:** `P 24-continuation.md` L409–14; `P 25-part4-notes.md` L376–90.

## I. RTL and library identification

### P-68 · Locate the RTL segment by wildcarded prologue signature
**Decides:** where the runtime lives, plus DGROUP for free. Two patterns — one at segment+0 and `Halt` at segment+0x116, the latter being the discriminator because the first is not unique. **Relocated DGROUP words must be wildcards.** Bonus: the relocated word at RTL+1 *is* the DGROUP base, which is also how a mislabelled data segment gets corrected.
**Blind spot:** two anchor points from one compiler version — a different RTL build, memory model or patched prologue defeats it, and **it cannot tell you it has found the wrong RTL**, only that a match was unique. Finds the segment, not the routines inside it.
**Disasm:** no · **Source:** `P 03-borland-rtl.md` "Finding the RTL segment" L224–56 · **Example:** yes, 1,018 functions named across 16 programs.

### P-69 · Signature-match RTL routines per binary by masked-body search
**Decides:** which routine is which, **per binary**. Locate each routine by byte pattern rather than by offset: mask relocated words in both reference and target, search the target's RTL segment for the reference body, **accept only unique hits**, and create a function at any address the disassembler never turned into one. Effect: about 40% of each listing stops competing with demo code.
**Blind spot:** uniqueness as the acceptance criterion **systematically drops short routines and families of near-identical stubs** — exactly the 5-byte math stubs that then need P-70's ordering argument. Cannot find a routine whose body genuinely differs between builds, and a routine present in the reference but absent from the target reads as "not found" rather than "not there".
**Disasm:** no for the matching · **Source:** `P 03-borland-rtl.md` L262–86.

### P-70 · Anchor an indistinguishable stub run by one identifiable member plus declaration order
**Decides:** the identity of a contiguous run of mutually indistinguishable 5-byte stubs. `Sqrt` is independently identifiable by `D9 FA` (`FSQRT`), which anchors the run; the order then follows the System unit's declaration grouping. **Confirmed independently by usage** — the point generator calls one for X and the other for Y, i.e. `x = r·cos, y = r·sin`. The same 4/5/5/5-byte layout transfers between binaries.
**Blind spot:** depends entirely on the anchor being right and on source order holding for that compiler version; **a linker free to reorder breaks it silently, with every downstream name shifted by one and no local symptom.** That is precisely why the usage cross-check matters — the ordering argument alone is unfalsifiable.
**Disasm:** yes for the cross-check · **Source:** `P 03-borland-rtl.md` "Sin vs Cos" L312–20; `P 26-part5-notes.md` L290–98.

### P-71 · Recognise Borland RTL and library units and take them out of scope early
**Decides:** how much of the image is not the target's code. One segment is `Dos` because a routine is `SwapVectors` verbatim — nineteen vector numbers in a table, "exactly the interrupts Turbo Pascal saves, the 8087 emulator range included"; "worth catching early, because it takes 800 bytes off the surface." Another is `Objects` because its allocate reads the size **out of the VMT's first word** and zeroes everything past the VMT pointer, "which is what `New(T, Init)` does and nothing else does", plus a constructor call shape read right-to-left and confirmed field offsets. Running total: about 7.6 KB that does not get reconstructed.
**Blind spot:** identification by **idiom** leaves the work-alike possibility open, and the docs say so twice — the prologue encoding "is not ruled out by the encoding alone", and later evidence is called "the firmest evidence yet", not proof. The question stayed on the open list.
**Disasm:** yes · **Source:** `P 03-borland-rtl.md`; `V 00-map.md` L353–82, L563–84 · **Example:** yes, both.

### P-72 · Distinguish two RTL helpers eleven bytes apart — `Move` versus a whole-array assignment
**Decides:** which source statement was written. One helper compares pointers and copies **backwards** on overlap — that is `Move`; the other is the same loop with **no overlap check**, which is what the compiler emits for a whole-array **assignment**, where it knows the operands are distinct. Reproducing it needs a **named type on both operands**, because TP only allows whole-array assignment between operands of the same named type — "which is exactly why both sites read as `Move` for as long as they did." Same method separates a 32-bit shift left from a shift right twelve bytes earlier, and `MOV CX,4` in front multiplies by sixteen where the source had `div 4`.
**Blind spot:** **with a different RTL build the helper addresses carry no meaning** — the whole technique rests on the prerequisite that "our RTL is the author's", which was itself a withdrawn-then-established claim (W-02).
**Disasm:** yes · **Source:** `V CONTINUATION.md` L62–86.

### P-73 · Note where an RTL helper call replaces an inline operation, and use the cost difference
**Decides:** operand width. An 8086 has no 32-bit shift, so a `LongInt shr 4` costs a far call while a `Word shr 4` is inline `SHR AX,4` — which is why one one-line function is 50 bytes and its near-twin is 20 bytes shorter.
**Blind spot:** requires knowing the RTL helper addresses, and the size difference alone does not say **which** variable is wide.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L1201–18.

### P-74 · Read a `String` function's result pointer as the next call's argument
**Decides:** why a string assignment appears to be missing an argument. **A `String` function does not pop its own hidden result pointer — the caller does** — so the pointer still on the stack IS the next call's argument. That fused two statements into one, and a `String`-returning function is `RETF 4`, not `RETF 8`. Third instance of the same rule in one file.
**Blind spot:** looks like a mis-read, and only the `RETF` rule disambiguates. Visible only where the temporary's fate is on the stack; nothing distinguishes source formatting.
**Disasm:** yes · **Source:** `V CONTINUATION.md` L156–58, L1320–24.

### P-75 · Recognise the x87 emulator patch table by its `INT 3Eh` stubs
**Decides:** which FP call is which. `Sin` and `Cos` are five-byte `INT 3Eh` patch points in a table beginning with `CD 35 FA CB` — `INT 35h,FAh`, the emulator's form of `D9 FA`, **FSQRT**. The Sqrt/Sin/Cos/ArcTan 4/5/5/5-byte layout is the same one another binary shows, so **the layout transfers**.
**Blind spot:** you cannot tell which call is which without the layout convention, and it says nothing about non-emulated x87 builds — the `_fpu` filenames hint both variants of the binaries exist.
**Disasm:** yes · **Source:** `P 26-part5-notes.md` L290–98.

### P-76 · Recognise and undo Borland's `$E+` x87 emulator traps
**Decides:** how to make FP code readable at all. `INT 34h`–`3Eh` scattered through ordinary code, each followed by garbage, means the linker overwrote every `WAIT ESC` prefix with a 2-byte `INT n` — same length, so patchable back. Substitution: `CD n` (n=34–3B) → `9B D8+(n−0x34)`; `CD 3C <b>` → `9B 2E <b+0x40>` (**CS-relative**); `CD 3D` → `90 9B`; `CD 3E <b>` is emulator **dispatch**, `<b>` an index not an opcode. Acceptance test is the resulting *idiom*: after decoding, the instruction mix looks like real Pascal float code.
**Blind spot:** **cannot distinguish a genuine `INT 3x` from a trap by bytes alone** — one part shows 7 raw `CD 3x` hits and zero real traps — so it needs disassembler-confirmed sites and is blind on data-adjacent or never-disassembled bytes. Traps hidden inside still-misdecoded regions are invisible until an earlier fix re-syncs the stream, which is why the process must iterate. And it says nothing about which emulator entry the dispatch reaches. **Convergence means "no newly visible sites", not "no sites"** — a region that never becomes reachable code stays permanently dark, so the fixed point can be a local one.
**Disasm:** yes, essentially — byte matching alone is explicitly rejected · **Source:** `P 02-fpu-emulator.md` L100–98 · **Example:** yes, the six-byte CS-relative pair and the convergence table.

### P-77 · Read the FP distribution as a design fact
**Decides:** the build's shape. Every recovered FP site sits in setup or table-building code; render loops are integer; one part has no FP at all. The signature idiom is integer-in/integer-out around an FP core, with a 6-byte `PUSH AX; PUSH 0; PUSH 0` marking a Borland `Real`.
**Blind spot:** a distribution measured **after an imperfect recovery** — FP in a still-misdecoded region counts as absent, so "no FP in the render loops" is only as strong as P-76's convergence. And `INT 34h` never appearing is read as 64-bit `Real`, but absence of single-precision ops is equally consistent with the compiler never choosing that encoding.
**Disasm:** yes · **Source:** `P 02-fpu-emulator.md` L203–19.

### P-78 · Decode floating-point literals parked in the code segment
**Decides:** an effect's actual parameters. Borland parks FP literals in `CS:` beside the procedure that uses them, so a small run at a known offset, decoded per format — 4-byte single, 10-byte extended, **6-byte Borland Real48 with exponent biased by 129** — yields radius decay 0.1, angle step 3.0, a projection scale of 144.0.
**Blind spot:** **the byte pattern does not announce its format** — a 10-byte extended and a 4-byte single starting at the same address decode to different numbers, and choosing wrong gives a value that is merely *implausible* rather than obviously invalid. **Real48 is not an x87 format** and decodes as garbage under x87 assumptions. The constant's *role* is invisible; that needs the instruction stream.
**Disasm:** decoding is not; locating is · **Source:** `P 14-part001-intro.md` L150–85; `P 11-part3-scene5-blocks.md` L58–90 · **Example:** yes, both.

### P-79 · A register cannot be relied on to survive a Pascal call — and a `Move`'s exit value may be load-bearing
**Decides:** a dependency the reconstruction cannot inherit. One loop keeps its running index in **SI** across the whole lane loop *including across the `Move` that shifts each lane*, and never reloads it — so the next lane's start is `Move`'s own side effect: source one below destination, so TP's `Move` takes its **backward** path and exits at `Source − 1`. That is why lane L+1 walks lane L's stretch of the tables. Resolution: an explicit variable, and **the value `Move` leaves is written down rather than assumed.**
**Blind spot:** nothing in the toolchain enforces this — the RTL's register discipline is a version- and path-dependent implementation detail, so the reconstruction records an observed value it cannot guarantee. And the effect is only visible from lane 2 onward.
**Disasm:** yes, both the loop and the RTL path · **Source:** `P 27-part6-notes.md` L365–81.

## J. Telling hand assembler from compiled Pascal

### P-80 · The tell-table for hand-versus-compiled — and `ENTER` does not settle it
**Decides:** whether a routine must be transcribed verbatim or may be written as Pascal. **`ENTER` alone does not settle it** — a TP7 `assembler` procedure with locals still gets a frame. Compiled: `ENTER` + `[BP+n]` parameters + `PUSH` arguments, calls through the stack, counted loops, globals via the frame, an RTL helper where a lookup would do, a multiply where a table would do. Hand: no frame, or a frame with no `[BP+n]` reads; arguments and results in **registers**; `REP MOVSW`/`STOSB`/`OUTSB`; globals addressed directly; `PUSH DS`/`POP DS` bracketing; `MOV ES` from an immediate; `LOOP`; **fully unrolled bodies, because BP7 does not unroll loops**. Secondary tell: a caller pushing DI and SI around per-point calls specifically so callees may use them.
**Blind spot:** **mixed routines.** One routine is half compiled and half hand-written — the `Random` fill must be Pascal because it calls the RTL, and everything after a given offset is hand asm. A single verdict per routine is wrong there, which is what the *fragment* marker exists for. It also cannot spot hand asm that happens to obey the Pascal convention, cannot separate hand asm from a *different compiler's* output, and the prior failed in **both directions** in the DemoVT tree — three routines assumed inexpressible in Pascal were expressible, while an adjacent divergence assumed to be compiler output was hand asm. **Only an encoding test settles it** (P-10).
**Disasm:** yes · **Source:** `P 09-hand-assembler.md` L172–252; `P 24-continuation.md` L12–53; `P 25-part4-notes.md` L399–414; `M transcribe-asm-verbatim` · **Example:** yes, both directions.

### P-81 · The pointer register, the direction bit, and impossible instructions
**Decides:** hand asm inside a compiled routine, in the byte-exact setting. **TP's code generator uses DI for every dereference it makes**, so `LES SI,...` mid-routine is somebody's hand. `21 C9` (`AND CX,CX`), `20 C0` and `21 C0` are the **inline assembler's** encodings and the code generator emits the other direction — two blocks twelve instructions apart in one routine were separated this way. Instructions the compiler never emits: `LOOP`, an 8-bit `MUL BL` whose high byte is taken as a shift, and rounding division (`ADD DX,DX / CMP DX,BX / JC / INC AX`). And `MOV DI, WORD PTR Raw` on a `var` parameter loads the offset half, so stores through it are DS-relative — the bare `MOV DI,Raw` is Error 155.
**Blind spot:** **the table can be wrong entry by entry** — `09 C0` (`OR AX,AX`) was listed here as an inline-asm form and does **not** discriminate: it is the code generator's own way of testing the sign of the low word after an `Integer(...)` cast. Each tell needs its own counter-example hunt. And the tells identify hand asm, never its *intent*.
**Disasm:** yes · **Source:** `M demovt-handwritten-asm-tells`; `V CONTINUATION.md` L1078–86 · **Example:** yes, ten blocks in one segment.

### P-82 · The hand-assembler audit sweep — a four-step per-program procedure
**Decides:** which routines are hand asm. Per program: search for `ENTER` to get every framed routine; search for `MOVSB.REP`/`MOVSW.REP`/`STOSB.REP`/`STOSW.REP`/`INSB.REP`/`OUTSB.REP` to get every string-instruction routine, **ignoring hits in the RTL segment and the compiler's own String-parameter copy**; extract every `nnnn:nnnn` cited in that part's sources and check each entry point not in the `ENTER` set; then apply the tell-table.
**Blind spot:** misses hand asm that has neither a frame nor a `REP` string instruction **and** is not cited anywhere in the sources — i.e. anything you have not already found. **Step 3 makes the sweep's completeness a function of your own source comments, so it audits what you wrote, not what exists.**
**Disasm:** yes, explicitly · **Source:** `P 24-continuation.md` L152–83, L341–55 · **Example:** yes — 5, 22 and 11 Pascal-ised routines found in three parts.

### P-83 · Transcribe hand assembler verbatim, and justify it by the bug classes Pascal-isation invents
**Decides:** the standing rule. Three things are required every time: the assembler verbatim; **a comment on every line**; and a block comment above holding the equivalent Pascal, labelled reference-only, plus a note where that Pascal could not work (register arguments, no signed shift operator, 16- vs 32-bit intermediates). The justification is measured, not asserted: rewriting one scene's inner loops **invented four bug classes that do not otherwise exist** — a lost register hand-off, `shr` versus arithmetic shift, a 16-bit multiply where the original used 32, and enough frame cost to show as **flicker**. All four vanished when the asm went back verbatim. Conversely, **where the binary is plainly compiler output, Pascal is the faithful transcription and inventing assembler would be the deviation.** Even dead code is transcribed verbatim rather than dropped, because dropping it shifts every byte after it.
**Blind spot:** the rule turns on a judgement — "plainly compiler output" — that was wrong in both directions in the DemoVT tree. **The rule is a discipline, not a discriminator.** And it is prose: nothing checks that the reference Pascal is actually equivalent, so a plausible-but-wrong reference block actively misleads the next reader, which is exactly how the four bug classes got in.
**Disasm:** no · **Source:** `M transcribe-asm-verbatim`; `P 24-continuation.md` rule 1, L14–33, L419–32; `V 06-transcription.md` L1501–14.

### P-84 · Understand that verbatim asm reproduces instructions but NOT the frame
**Decides:** the single most important limit on the verbatim rule. TP decides where locals sit, how much a procedure reserves, and what lies immediately above and below.
**Blind spot:** **nothing detects this statically — it manifests as corruption far away.** One routine's fade loop touches indices 768 down to −2; index 768 is `[BP]` itself and −1/−2 are dead stack. The original survives because `LEAVE` reads BP before popping and the caller keeps nothing in BP; the reconstruction's three writes land on TP's frame instead, and across 63 calls "the scene faded to black and hung." **Where a routine writes outside its own storage, "verbatim" is not "faithful"** — and the right test is whether any *observable* output differs, which requires naming the observer (W-46).
**Disasm:** yes, to read the `ENTER` and the index arithmetic · **Source:** `P 23-deviations.md` L13–63 · **Example:** yes.

### P-85 · Emit prefixed and register-to-register forms as explicit `DB`, keeping only self-relative displacements symbolic
**Decides:** how to get a hand-asm region byte-exact. Emit every prefixed and every register-to-register form as `DB` with the mnemonic in the comment; only jumps and near calls keep their labels, because those displacements are self-relative and therefore the assembler's to compute; absolute operands are `DW OFFSET` per the standing rule.
**Blind spot:** `DB`-spelling a byte **freezes it against relocation**, so it is safe only for operands that genuinely never move, and it defeats the verification benefit of symbols — a hand-computed displacement "is not a fixup, so it had to come out right on its own." Also: TASM turns a `CALL` of a far external in the same module into `PUSH CS / CALL near`, so a site needing `9A` wants `CALL FAR PTR`.
**Disasm:** no · **Source:** `V 06-transcription.md` L319–36, L1394–1400.

### P-86 · Catalogue the syntax spellings that produce the same instruction
**Decides:** how to say a thing at all. `CALLF [mem]` is spelled `CALL DWORD PTR [mem]`; sized operands are required on `CS:` self-patches because the target is a code label rather than a typed variable; `PByte` does not exist in TP7 (it is a Delphi type); TP7 rejects an include directive inside an `asm` block, so the include must carry a whole procedure.
**Blind spot:** "same instruction, same bytes" is a claim requiring verification per case — **a spelling that assembles is not thereby the same encoding** (P-10, P-29).
**Disasm:** no · **Source:** `V 06-transcription.md` L1417–38.

### P-87 · `LDS` in a hot loop means every subsequent global needs `SS:`
**Decides:** why a region is full of segment overrides. `LDS SI,Sounding` points DS at the sample data so the output loops can walk it with plain `[SI]` — but DGROUP is then unreachable through DS, so every global touched after that line is read through `SS:`. SS and DS are the same segment in a Pascal program, so the override is free. **"Miss one and it reads the sample buffer as if it were the data segment."**
**Blind spot:** the SS=DS equivalence holds only inside a Pascal program's own stack context — a routine reached from an interrupt with a switched stack breaks it, and nothing in the bytes flags which regime a given `SS:` reference assumes. Related recorded bug class: "DS clobbered in an asm loop, then a global read by name."
**Disasm:** yes · **Source:** `V 06-transcription.md` L236–58; `P 24-continuation.md` L425–27.

### P-88 · Read the addressing trick, not the arithmetic
**Decides:** what the original *does not* compute. "The whole trick is the addressing": a 256-wide texture means the offset is the two high bytes of two 8.8 coordinates stuck together — no shift, no mask, no multiply, **no bounds test**, because the coordinates wrap in eight bits by themselves.
**Blind spot:** a Pascal reimplementation that adds the mask and the bounds test is **behaviourally different at the edges and looks correct in the middle**. And the "no bounds test" only works because the scene separately blanks the rows past the bottom of the texture so an overrunning coordinate reads black — **a dependency spanning two routines that neither routine alone reveals.**
**Disasm:** yes · **Source:** `P 26-part5-notes.md` L225–301; `P 25-part4-notes.md` L117–43.

### P-89 · Prefer the disassembly over the decompiler for segment loads and pointer walks
**Decides:** which of the tool's two views to trust. Read from the decompiler, one routine "looked like a copy *within* the virtual screen, which shows nothing at all"; the disassembly has `ES := $A000` and `DS := VirtScrSeg` plainly, so the `MOVSB` writes to the **display**. Two further details only the disassembly gives: the walk advances the *source* alone, which is what makes a strip appear to slide down, and the guard is `CMP AX,1 / JGE`. Same rule for CS-relative constants: the decompiler mis-resolves them, substituting the image base for the owning segment, while the listing is correct.
**Blind spot:** **the failure is silent** — a wrong-but-plausible address with no error, so you must know the bug class to avoid it. The segment loads are also far from the `MOVSB`, so you have to be looking for them. And one thing is invisible in *both* views: the speed argument for loading segment registers once per column rather than per byte.
**Disasm:** yes — that is the point · **Source:** `P 01-binaries-and-loading.md` L78–80; `P 25-part4-notes.md` L293–320.

## K. Verification tooling and measurement discipline

### P-90 · Compare the compiled `.TPU`'s code against the original segment byte for byte, and reject size equality
**Decides:** whether a unit reproduces its segment. **"Size equality is a weak check — two different routines can be the same length — and this file relied on it for too long."**
**Blind spot:** alignment-fragile: "a single two-byte codegen difference early on displaces everything after it, so the first-divergence figure says nothing about the remaining 2,600 bytes."
**Disasm:** no · **Source:** `V 06-transcription.md` L504–55.

### P-91 · Report agreement from the start as the only alignment-independent measure — then use the region list as the work list
**Decides:** honest progress, and what to fix. The prefix "is the only alignment-independent measure: once the code diverges, everything after it shifts and any overall percentage is noise." But it under-reports a unit that is 99% right with an early two-byte difference, so the difflib-aligned region list is the actual work list, with regions before the verified prefix dropped because difflib produces alignment noise around the fixup zeros there. **Read the region COUNT, not the prefix percentage.**
**Blind spot:** **difflib invents plausible correspondences** — several "artefacts" appeared and vanished when an upstream cause was fixed, so region *counts* are not a metric (one character produced 188 regions from one cause). A one- or two-byte region next to a fixup run is probably not real. And mid-transcription the prefix freezes at the half-written routine and says nothing about hundreds of correct bytes after it — neither a regression nor a plateau.
**Disasm:** no · **Source:** `V 06-transcription.md` L504–55; `V CONTINUATION.md` L630–40, L740s.

### P-92 · The zero rule — a differing byte is acceptable only where YOUR byte is `0x00`
**Decides:** which differences are pending linker fixups. A `.TPU` is not linked, so every reference the linker must resolve sits there as **zero** where the original has the resolved value. "A wrong branch direction, a swapped operand or a different instruction will not coincidentally emit zero."
**Blind spot:** **the rule's own hole, found the hard way — a zero is only evidence of a pending fixup if something is actually pending.** A near call to a local label is not, and one that comes out zero is "a bug wearing a fixup's clothes": a poll called a one-byte stub for the unit's whole life and read as agreement. Also blind to `DW OFFSET` fixups, which sit as zeros — four gain-table pointers were three bytes short **invisibly, for as long as the offending `JMP` existed**. And the cap needed for long runs cuts both ways (P-93). **Distinguish the two kinds of intra-segment reference:** a same-unit near CALL is left as zeros and excused, so **a call inside the unit is NOT evidence its target is right** — the exact opposite of the jump-displacement rule.
**Disasm:** no · **Source:** `V 06-transcription.md` L136–54, L206–35, L513–21; `V CONTINUATION.md` L1394–96; `M distrust-the-verify-tool`.

### P-93 · Cap a pending-fixup run — but exempt an all-zero gap matching the original's length
**Decides:** whether a long zero run is data-with-fixups or a unit that simply stopped. A fixup is at most four bytes, so longer runs end the comparison — except that a pointer **table** of sixteen consecutive `DW OFFSET` entries is a 32-byte run of zeros, and the cap counted all of it as real. "The docs recorded 132 differences on that basis, and the tables were correct the whole time."
**Blind spot:** the exemption **re-opens P-92's hole at table scale** — a genuinely missing table also produces zeros of the right length. The surviving test with its caveat: "the test that settles it is not the run length, it is whether OUR byte is zero — with the caveat the poll stub just taught."
**Disasm:** no · **Source:** `V 06-transcription.md` L155–78.

### P-94 · For an assembled `.OBJ`, read the FIXUPP records — do not use the zero heuristic
**Decides:** the exact set of relocated positions in an external module. TASM resolves what it can and leaves an **addend**: `DW OFFSET Label` becomes the offset from the module's own start, `Volumes[2]` becomes the displacement `2`. "Against a linked binary both are flat mismatches, and no rule about the bytes can tell them from real ones." **"That is stricter than the zeros heuristic, not looser — a byte is excused because the assembler recorded a relocation there, not because it happens to be zero."**
**Blind spot:** only as good as the assembler's own record — it excuses whatever TASM chose to relocate and says nothing about the correctness of the **addend**; it can print the implied offset for a human to recognise but cannot validate the *symbol* half. Blind to anything outside the assembled run, and to DGROUP contents. Which is why the mask was **checked a second way**: all 192 word fields classified — 112 code self-references off by exactly the module base, 7 DGROUP symbols with an addend, 73 zeros, **0 unexplained**. The first measurement of a correct module had reported 65 divergent regions; another gave 27 phantom differences for 36 relocation bytes, the heuristic wrong in both directions at once.
**Disasm:** no, OMF record parsing · **Source:** `V 06-transcription.md` L710–32; `V CONTINUATION.md` L1090–1118; `M demovt-obj-fixups` · **Example:** yes, the four-line classification.

### P-95 · Byte-diff a transcribed `assembler` routine against the binary, masking only displacements
**Decides:** whether a transcription is opcode-identical. Each routine carries an address marker; the tool locates it in a **freshly built** harness, walks it byte-for-byte to the return, and skips only 1- and 2-byte displacements because TP puts our variables at different DGROUP offsets. **Three or more differing bytes in a row is an opcode change and fails.** Lengths are locked, so a change that *shortens* a match is a regression. Reports 71 routines, 71 locked, 0 failing.
**Blind spot:** **branch targets.** A short-jump or `LOOP` target is one byte and is indistinguishable from an ordinary masked displacement — **this let four real bugs through in one part**: three jump destinations read one instruction out, and an inverted `JNZ`. Only afterwards did the tool learn to refuse a one-byte hole sitting immediately behind a short jump or `LOOP`. It is also blind to the stack frame and everything around the routine (P-84); to **semantics of masked bytes**, so a masked displacement pointing at the wrong variable still passes — which is exactly P-66's bug class; to any routine without a frame to anchor on; to routines that are mostly compiled Pascal; and to **coverage** — it says nothing about the 246 routines carrying no marker.
**Disasm:** no — a raw binary plus a built EXE is enough · **Source:** `P 23-deviations.md` "Every transcribed assembler routine is byte-checked" L133–241; `P 27-part6-notes.md` L271–83 · **Example:** yes — four chunk handlers matched end-to-end first pass with zero holes.

### P-96 · Declare a FRAGMENT marker for inline asm inside compiled Pascal
**Decides:** how to verify hand asm with no routine boundary to walk to — "compare exactly N bytes from here, expect no `RET`".
**Blind spot:** **the byte count is asserted by the human**, so a fragment actually longer than declared is silently half-checked; and the boundary between compiled and hand code is a judgement the tool cannot verify. It cannot see the surrounding compiled Pascal, which is where the frame offsets that shift the fragment come from.
**Disasm:** no for the check · **Source:** `P 23-deviations.md` L151–61 · **Example:** yes, both inline halves verifying at their full 32 bytes.

### P-97 · Compare per-routine blocks with the shift SEARCHED, never assumed
**Decides:** progress on a half-written segment, where a whole-unit prefix stops dead at the first placeholder. The recipe: take each contiguous transcribed block, **search** for the byte shift that minimises differences — never hardcode it, an edit anywhere earlier moves it — then compare positionally at that shift and count only differences where our byte is non-zero. Retargeting takes about two minutes. Corroboration trick: **eight independent blocks agreeing on ONE shift proves both their order and that only the placeholders above them are short.**
**Blind spot:** **the search WINDOW is part of the measurement, and a too-narrow window does not fail loudly — it returns the best shift it could reach plus a plausible-looking difference count.** One block reported 5 real differences at ±600 and its true shift was −1,228. Second trap: **a block must END where the next routine's LITERALS begin, not at its `ENTER`**, because TP emits a routine's literals immediately before its code — twice in two segments, each producing a small plausible difference count. And comparing each region at its own shift **makes displacement invisible**, which is what hid the three-byte pointer error. Hardcoded shifts go stale after an edit: 73 phantom mismatches.
**Disasm:** no · **Source:** `V CONTINUATION.md` L262–70, L640s, L1381–90, L1620–36; `V 06-transcription.md` L418–55.

### P-98 · A jump displacement that disagrees is a LENGTH, not an error
**Decides:** how to diagnose a routine whose length is wrong. The displacement encodes everything downstream, so it is the first thing to differ however far away the cause is — and the tool then reports a catastrophic-looking percentage for a nearly-finished unit (one read "9%" when the tail was already exact). Procedure: **subtract the two displacements to get a byte count**, which tells you how much code is missing without locating it; then **diff the routine BACKWARDS from its return** using that difference as the alignment — forwards, the prefix stops at the displacement and shows nothing. One tail agreed for 189 bytes, pinning the insertion point to one byte.
**Blind spot:** the displacement gives the size of the delta and **nothing about its location or nature**. Collect ALL differences in a routine rather than stopping at the first: pure-displacement ones are noise, the first that is not is the answer.
**Disasm:** yes · **Source:** `V CONTINUATION.md` "A DISPLACEMENT THAT DISAGREES IS A LENGTH" L2135–50; `M demovt-byte-exact` · **Example:** yes.

### P-99 · `verify.py` compares a `.TPU` against a LINKED segment, so the two need not hold the same routines
**Decides:** how to read a unit that is *longer* than its segment. TP smart-links **at the routine level at EXE build time**, so a routine nothing references is in our `.TPU` and absent from the original's segment. One case: a base class never instantiated, so its VMT is dead and dropped, and it was the last thing referring to two empty overrides — 1,282 bytes of `.TPU` against a 1,232-byte segment, the 50 being exactly those two bodies.
**Blind spot:** **our code being longer is a signal to read, not a failure** — ask which routine nothing references before assuming a transcription error. Two consequences: a dropped routine must be written **last** in the unit, because TP lays `.TPU` code out in source order; and that is **a property of the measurement, not source-fitting** — the project's own self-accusation of "arranging the source to fit the measurement" was itself withdrawn (W-08).
**Disasm:** no · **Source:** `V CONTINUATION.md` L2173–2202; `M demovt-byte-exact`.

### P-100 · Refuse to report on a stale artefact
**Decides:** whether the measurement is of the current source. The build refuses to compile when the lint fails, "so one bad comment left the whole tree stale while `verify.py` cheerfully reported on the previous build. **That produced a wrong conclusion — an operand-order fix was recorded as having no effect when it had in fact worked.**"
**Blind spot:** a staleness check comparing staged source to original source breaks when the harness legitimately **rewrites** the staged copy (P-16) — it must accept the rewritten form or the whole tree reports STALE. And the erasure itself had two sites; the first fix missed the second, so anything measured under a keep-artefacts flag is suspect until a clean build agrees. Building one unit only works for a leaf, and it deletes the stale `.TPU` on the way, so the tool then reports the unit missing.
**Disasm:** no · **Source:** `V 06-transcription.md` L1190–96; `V CONTINUATION.md` L590s.

### P-101 · Prefer errors of pessimism, and record which direction each tool fails in
**Decides:** how much to trust a passing result. Five separate bugs in one verification tool, "each of which made the work look **better** than it was, **which is the direction of error that matters here**": two bad candidate-ranking schemes (ranking by "fewest real differences" scores a run of zeros as perfect, so two units passed that should not have; ranking by "most exact matches" drifts when sizes differ and reports a meaningless divergence offset); an over-strict fixup cap that swallowed real divergence (one unit read 68% and was actually 6%); a rule that made a good partial unit report `NOT LOCATED`; and that same cap then reporting a 32-byte zero table as 132 real differences, carried in the docs for sessions.
**Blind spot:** **a tool can only be audited for the failure directions you think to test** — all of these were found by accident or by a second instrument, never by design. A percentage is a property of the tool as much as of the code.
**Disasm:** no · **Source:** `V 06-transcription.md` L1179–1203; `M distrust-the-verify-tool`.

### P-102 · Distrust the tool before the transcription
**Decides:** what to do with a surprising number. **"The transcriptions have been more reliable than the tool measuring them. A surprising number is more likely to be a measurement artefact than a code defect, and a confident wrong number in a handover doc gets believed for sessions."** Check a surprising measurement a second way before acting: compare positionally at a **searched** (never hardcoded) shift and count only differences where our byte is non-zero.
**Blind spot:** the inverse failure is equally real — distrusting a *correct* measurement wastes the same time. The discriminator offered is upstream-first: "if a measurement looks impossible, check whether something upstream of it is still wrong rather than distrusting the measurement." And **mark predictions in handover docs AS predictions**: two logged cases were believed for six iterations and were wrong.
**Disasm:** no · **Source:** `M distrust-the-verify-tool`; `M demovt-link-layout`.

### P-103 · When a doc records that a tool cannot measure something, build the tool that can
**Decides:** how a blind spot gets closed. The zero-rule lesson was written down for an assembled module, the block checker **inherited the bug anyway**, and only the purpose-built relocation checker — the lesson made executable — ended it. Every defect class this project found late was found because a NEW tool could see what the old one could not: three units whose init section was a named procedure, an object's type, a wrongly-bounded array, two one-byte data errors.
**Blind spot:** **the meta-finding of the whole corpus.** Twice in one file range a lesson already written down was re-learned anyway — a zero rule re-implemented wrongly "within an hour of reading" the header that records that exact failure twice, and the invented-`String`-local trap made in a third unit. **A blind spot stated only in a retrospective does not prevent the next instance; it has to be stated at the point of tool use, or enforced by a tool.**
**Disasm:** no · **Source:** `V CONTINUATION.md` L2600s, L1770–80.

### P-104 · Lint before compiling, and grow the lint from traps already paid for
**Decides:** build-blocking and known-class defects cheaply. TP7 reports a nested-comment defect **dozens of lines from its cause**, and it cost time twice. Related trap: do not write a directive-shaped thing inside a comment, because `{ ... {$A+,B-} ... }` ends the comment at the inner `}` and the error lands on the prose. The Psycho lint refuses the build on: nested comments, identifiers shadowing built-ins (`Ofs`, `Offset`, `Mem`, `Port`), empty procedure bodies, and — added after a specific bug — `Mem[DSeg:$XXXX]` and `Ptr(DSeg, $XXXX)`, a hard-coded address in our own data segment.
**Blind spot:** **only the patterns already added — it is a ratchet, not a proof**, and the standing instruction is to add to it when a new class appears. It cannot see semantically-equivalent forms of the same bug (an address computed rather than literal), and a lint tuned to one dialect's comment rules will not catch the other's. It cannot see semantic defects at all, which is where every real divergence lived.
**Disasm:** no · **Source:** `P 24-continuation.md` L403–08; `V 06-transcription.md` L40–46, L816–26.

### P-105 · Generate mechanical source rather than typing it, and make the generator refuse what it cannot account for
**Decides:** correctness of a large hand-decoded region. A 48-routine gain ladder "typed out of a hex dump is a hundred chances to be quietly wrong, and one wrong entry sends the mixer into the middle of an instruction." Four self-checks: every byte decodes or it stops — **"there is no best-effort path"**; all 48 gains computed as exact fractions and checked against closed forms; all 48 table entries checked to land on decoded cell boundaries; and the patcher's instruction lengths accumulated and checked to land on the expected offset. Same principle in Psycho: initialised data extracted from the image into generated includes.
**Blind spot:** the checks validate **internal consistency against a hypothesised model** — if the closed form were wrong, all 48 would agree with it and be wrong together. The insight that made the closed form credible was reasoning, not measurement.
**Disasm:** yes, the generator embeds a decoder · **Source:** `V 06-transcription.md` L1333–81 · **Example:** yes.

### P-106 · Verify a numeric table by recomputing it and checking exactness
**Decides:** that a table is what you think. A 901-entry table checked against `Round(cos(i/10°) * 65536)` — **exact**. The method also recovers generators: one table is `Round(sin*39.6 + 65535.0) mod 65535`, where **the bias and modulo are how the original gets a signed result out of `Round` without handing it a negative** — the low word of the LongInt is the answer.
**Blind spot:** **an exact match proves the values, not the formula** — several generators produce the same rounded table, and the bias/modulo trick is discoverable only by matching the arithmetic, not the outputs. It cannot verify a table whose generator you have not guessed. Where a builder is *compiled* code no byte diff applies at all, and the fallback — checking endpoints — does not validate the interior, the step distribution, or rounding.
**Disasm:** no for the recomputation · **Source:** `P 26-part5-notes.md` L315–18, L279–90; `P 27-part6-notes.md` L378–87.

### P-107 · Cross-check every measure, and compute status rather than tabulating it
**Decides:** the project's own state. **"The current state is computed, never tabulated."** Run all eight commands; "a table in a document goes stale within a session; those do not." Superseded tables are kept, banner-marked, "as a record of the order things landed in", and per-segment sections quote figures true when written — "records of how a segment was taken, not statements about today".
**Blind spot:** each tool is blind to something the next catches, so **a computed status is only as honest as its most permissive tool.** And a kept-but-stale table still misleads a reader who skips the banner. The Psycho side measured this directly: the marker-based ledger covers **18 of 317** implemented routines (three rows regex artefacts), the byte checker covers **71 routines / 22.4%**, and **246 routines have no machine-checkable status of any kind** — so a percentage from a marker-based tool measures *marker density*, not verification. **Establish a tool's coverage by running it, not by reading it.**
**Disasm:** no · **Source:** `V 06-transcription.md` L47–94; `P 24-continuation.md` L1–10, L387–91.

### P-108 · Track deviations in one file with a fixed schema, and rely on the negative invariant
**Decides:** what counts as a bug. Every knowing difference records: what the original does, what we do instead, why, **the effect on output**, and what would have to change to close the gap. The load-bearing part is the negative invariant: **"Anything not listed here is intended to match the binary; if it does not, that is a bug rather than a choice."** That converts an unlisted difference from ambiguous into a defect.
**Blind spot:** **it goes stale and nothing measures its staleness** — the deviations file quotes **two different verification counts in the same section**, and the continuation file carries claims its own audit falsified. It also cannot distinguish "effect on output: none, and provable" from "none, assumed" unless the author is disciplined about saying which. **Prefer numbers a tool prints on every build over numbers a human maintains in prose.**
**Disasm:** no · **Source:** `P 23-deviations.md` L1–11; `P 24-continuation.md` L46–53, L8–10.

### P-109 · Mark every routine with its evidence class, and track debt in named categories
**Decides:** provenance. Three markers — `[transcribed]` (read out of the binary instruction by instruction), `[inferred]` (established from documented analysis, written plausibly), `[stub]` (named and typed, body unwritten). Explicitly: **"the `[inferred]` count is the number that matters"** — those do the right kind of thing but their constants and edge cases are not guaranteed. Empty bodies are tracked *with reasons*, and items are struck off explicitly.
**Blind spot:** **self-assigned confidence.** A `[transcribed]` routine transcribed from a mis-decoded instruction stream still carries the highest label; the marker does not record which evidence or when. **It measures provenance, never correctness** — and it cannot see a routine that is *wrong* rather than absent, which is why everything in four parts was fully listed while never having been run.
**Disasm:** no · **Source:** `P 21-building.md` L335–61; `P 24-continuation.md` L374–92.

### P-110 · Transcribe the original's bugs, redundancies and disabled machinery as found — and name the mechanism
**Decides:** fidelity to defects. Reproduced and labelled: a phantom seek surviving only because of `{$I-}`; a `FillChar` with a count of **zero**, "the intent was presumably 65536, which does not fit the Word the count is"; a redundant flag test; a dead `ADD DX,AX`; a 32-bit counter nothing reads, "kept anyway"; a state with no handler, "left in"; a scroller advancing by **two**, so every other column of every glyph is never written and the message is drawn at half horizontal resolution — "that is the original, not a slip"; and two rotations disabled by `INC AX / AND AX,0`, "transcribed as found — tidying either changes the bytes."
**Blind spot:** **it cannot distinguish an author's bug from your misreading of correct code — that is the whole risk.** The discipline that makes the claim supportable is to **name the mechanism by which the bug is harmless** (the RTL sets `InOutRes` and returns; DX is popped back on the next instruction). Without that mechanism the "bug" claim is unsupported. And "disabled" is itself a reading — an `AND AX,0` could be a patch site, a debug hook, or a compiler-rendered constant expression; nothing in the bytes distinguishes intent.
**Disasm:** yes · **Source:** `P 23-deviations.md` L250–64; `P 26-part5-notes.md` L299–301, L356–60; `V 06-transcription.md` L440–55.

### P-111 · Note disagreeing call sites rather than normalising them
**Decides:** what to do when two calls of the same routine disagree. Two calls take a term at different indices with different biases; two callers of a fixed-point conversion pick **deliberately** different routines, one that truncates and one that rounds.
**Blind spot:** cannot say whether the disagreement is intentional or an author slip. The recorded discipline is to preserve and flag it, not resolve it. **Two near-identical routines at adjacent addresses are probably two deliberately different routines** — check every caller's target, not just the routine's shape (W-19).
**Disasm:** yes · **Source:** `P 26-part5-notes.md` L299–301; `P 24-continuation.md` L272–88.

### P-112 · Record an open contradiction rather than resolving it by guess
**Decides:** how to hold an unresolved conflict. A recorded call has its arguments one way and the routine tests the other, "so either that reading has the arguments the wrong way round, or the routine does. **Not resolved.**" Same treatment elsewhere: "either the instruction stream is not what it looks like or the routine is entered with a value already in AX. Left alone rather than guessed at." And two routines are "almost certainly X and Y by the source order the unit is known to have, but neither has been reached from a call yet and so neither is written down as fact."
**Blind spot:** none measurable — this is the corpus's model for handling ambiguity, and the counter-case shows its value: a driver's identity was left open with the contradiction recorded, and resolved later **the other way from the guess** (W-39).
**Disasm:** n/a · **Source:** `V 06-transcription.md` L374–90; `V 00-map.md` L326–34; `P 27-part6-notes.md` L78–85.

## L. Build harness and project hygiene

### P-113 · Build with the period compiler, and use header artefacts to confirm the toolchain
**Decides:** whether the source is valid period Pascal at all. A real TP 7.01 under DOSBox answers that. Independent corroboration: the compiler's own self-test MZ header reads `SS:SP = xxxx:4000`, **the same stack pointer as every original part**. Per-unit code and data byte counts give a comparable measurement against the original's segment sizes.
**Blind spot:** **stated bluntly in the docs** — compiling proves the source is valid period Pascal, that identifiers resolve, and that transcribed logic type-checks; it does **not** mean the demo is reproduced, and nothing had been run. The `SS:SP` match is one weak bit (many TP versions would produce it), and code-size agreement can be reached by wrong code of the right length.
**Disasm:** no · **Source:** `P 21-building.md` L255–333.

### P-114 · Drive a GUI DOS emulator headlessly by log file
**Decides:** how to get compiler output off the guest. DOSBox-X is a GUI app that **writes nothing to stdout**, so output is redirected to a log *inside the mounted drive* and read back from the host; run with `-silent -exit` so it starts, runs a batch file, and quits windowless. Mount-point subtlety worth generalising: the install's own config contains an absolute path, so **the drive must be mounted at the parent of the install directory**, not the install directory, or baked-in paths do not resolve.
**Blind spot:** **only captures what the guest redirects.** A crash, a hang, an emulator-level failure, or anything written to the screen rather than the handle leaves an empty or truncated log **indistinguishable from silence-on-success**. Exit codes do not cross the boundary — and the docs show the capture is lossy in practice, with two units' figures coming back as replacement characters.
**Disasm:** no · **Source:** `P 21-building.md` L269–303.

### P-115 · Stage sources into 8.3 names and rewrite identifiers mechanically
**Decides:** how a long-named tree builds under DOS. Everything is staged under a short name with `unit` declarations, `uses` clauses and include directives rewritten to match; the staging directory is generated and disposable, and the canonical tree stays untouched.
**Blind spot:** a purely **lexical** rewrite — any name appearing in a form the rewriter does not model (a string literal, an unusual directive spelling) is missed, and the error surfaces as a confusing compile failure in a file that is not the one you edit. Two long names colliding in their 8.3 truncation is silent unless the mapping is checked.
**Disasm:** no · **Source:** `P 21-building.md` L290–303.

### P-116 · Generate two harness tiers — per-scene, and whole-part through the real driver
**Decides:** what can be run. A per-scene harness runs one scene in isolation; a per-part harness runs a whole part **through its real driver**, transcribed from that part's main body, so scene order, inter-scene mode changes and music handling are the *original's* and not the harness's invention. Cheap to extend by design: one row per scene, and the build auto-discovers the harnesses because the names are already 8.3.
**Blind spot:** **a harness is itself a deviation, and the docs enumerate exactly how.** One scene shows the wrong colours on its own, because it sets no palette and neither does the binary — it inherits what the previous scene leaves behind, and "it looks right" only under the part harness: **a harness cannot judge palette or VRAM state.** Another must reset the video mode *after* the scene, because the **part's driver**, not the scene, does that. Every harness needs an `ExitProc` to restore text mode, because the scenes are left exactly as the binaries have them and **each part driver ends in `Halt(0)`, so nothing written after the call can run** — an `ExitProc` is the only hook catching all three exits. And most sharply: **a harness that omits a setup call can produce a scene that runs correctly and invisibly** — one ran entirely in 80×25 text, "indistinguishable from a hang" (W-47). An isolated harness also cannot see cross-scene state carry-over, precisely the class it is most tempting to use it for; and a transcribed driver is itself a transcription, so if the main body was read wrong both tiers agree on the wrong answer. It proves nothing at all until actually **run** — four parts "build" and were never run.
**Disasm:** no, but the main body must be disassembled to know which setup calls to stand in for · **Source:** `P 23-deviations.md` L92–117; `P 21-building.md` L417–45; `P 25-part4-notes.md` L293–320.

### P-117 · A/B against the original executable before calling a visual difference a defect
**Decides:** whether an observed difference is yours. The original parts are plain MZ, so each runs directly; copies are installed alongside the harnesses so the two run back-to-back in the same session. Standing instruction: **"Use them before assuming a visual difference is a defect."** Enabling property: they degrade gracefully when the music player is absent, so a part can be run without reconstructing the TSR.
**Blind spot:** **only differences you can see.** Blind to internal state, off-screen writes, anything masked by emulator timing, and any scene whose harness inherits different neighbour state. Graceful degradation without the resident player means the comparison runs a **different configuration from the real demo**, so anything timing- or music-synchronised is out of scope — and a scene's behaviour can be *supplied* by the absent TSR (W-48). Emulator behaviour stands in for hardware for both sides equally, so a shared emulator artefact cancels out and stays invisible.
**Disasm:** no · **Source:** `P 23-deviations.md` "Comparing against the original" L303–14; `P 24-continuation.md` L400–03 · **Example:** yes — "the globe in part 003 scene 4 is not horizontally centred in the original either. Not a defect in the reconstruction."

### P-118 · Let the compiler surface latent 16-bit constraints
**Decides:** constraints only a real 16-bit compile exposes. `{$G+}` is needed where a unit uses `SHR reg, imm`, **so the directive itself becomes evidence about the original's target CPU**; `FillChar` counts are `Word`, so clearing 65,536 bytes takes two calls; a 64,000-byte array cannot be global because DGROUP is 64K, forcing it onto the heap; `GetMem`'s size is a `Word`, so 202,007 bytes of assets must arrive in several blocks. A preserved `goto` with a declared label mirrors the original's jump.
**Blind spot:** **the compiler reports what is illegal, never what is wrong.** It has nothing to say about semantics, and constraints it enforces on the reconstruction may have been solved differently in the original — the multi-block allocation is an inference from a limit, not an observation of the original's strategy.
**Disasm:** no · **Source:** `P 21-building.md` L392–415.

### P-119 · Project hygiene for a byte-exactness effort
**Decides:** the things that silently invalidate every measurement. **Disable line-ending conversion outright** — "in a project premised on the bytes matching, do not let git rewrite a CRLF." Track the reference image with the measurements, "since every figure is a claim about that exact 58,176-byte file", and let **one module own the reference path**, honour an override variable, check the size, and fail with a diagnosis rather than a traceback. Run every script from the repo root. Two harness scripts that both wipe the build directory cannot run concurrently. **MSYS path-mangling**: a `--sw=/GS` argument becomes a Windows path and the build "silently compiles nothing, reporting `0 unit(s) compiled`" — same family as `gh api` with a leading-slash path.
**Blind spot:** each of these fails **silently and globally**, invalidating every number taken afterwards rather than producing an error. The path-mangling case is the sharpest: a successful-looking run that compiled nothing.
**Disasm:** no · **Source:** `V CONTINUATION.md` L520s, L545, L598; `M demovt-byte-exact`.

### P-120 · Prefer headless import; use the interactive bridge afterwards
**Decides:** import quality. Importing via the interactive bridge gives **weaker** analysis than headless — fewer functions found — so headless for the initial import, the bridge for interactive work.
**Blind spot:** "fewer functions found" is a measurement **of the tool**, and there is no guarantee headless is complete either; both counts are lower bounds, and neither tells you which functions were missed.
**Disasm:** it is a disassembler-usage pattern · **Source:** `P 01-binaries-and-loading.md` L70–80.

### P-121 · Convert every address to LINEAR before believing two things differ or duplicate
**Decides:** whether a "duplicate" is real. A unit's real extent is `(next base − this base) × 16`, and the disassembler **lists a routine under two segment bases when the ranges overlap**, so the second listing looks like a second routine — two address pairs proved to be the same six bytes at one linear address. Reusable sweep: *is any routine at or past `(next base − base) × 16`?* Run over every transcribed unit, it found four such artefacts.
**Blind spot:** the sweep finds **artefacts, not the real content behind them** — one of the four was hiding a genuine error that only follow-up reading exposed. It depends on having a correct next-base, i.e. a complete segment table. Standing rule: **"a Ghidra segment listing is derived, not authoritative."**
**Disasm:** yes — it is specifically a defence against the disassembler's own output · **Source:** `P 24-continuation.md` "Ghidra's segment ranges OVERLAP" L289–325 · **Example:** yes, both pairs plus the four-artefact sweep.

### P-122 · Convert a printed flat-segment address back to the real segment via the instruction bytes
**Decides:** a branch target you can trust. Where the tool prints `0x1000:XXXX` the real segment is in the instruction bytes — for one segment the conversion is `offset = 0xXXXX − 0xF0`, and every branch was rechecked against it. The general form: `offset = 0x10000 + printed − segment*16`, and for a far call read the segment out of the `9A off off seg seg` bytes rather than trusting the printed one. **"Getting this wrong by one instruction was the dominant error class in the Psycho Neurosis work."**
**Blind spot:** **an off-by-one-instruction landing is plausible code at the wrong place** — nothing flags it, and the byte checker masks the one-byte target (P-95). The only defence is to recompute the conversion **per segment** and check every branch.
**Disasm:** yes · **Source:** `P 28-part7-notes.md` L5–12; `P 27-part6-notes.md` L292–320; `V CONTINUATION.md` L660–70 · **Example:** yes, three bugs from one conversion error.

### P-123 · Follow calls when auto-analysis finds no functions
**Decides:** how to proceed with no function table. Two parts had to be imported and the auto-analysis finds **no functions**, so "every address below was found by following calls" — including indirect dispatch, where a scene stores four far pointers and the frame loop dispatches by chunk type.
**Blind spot:** **anything never called from a path you reached is invisible** — dead or data-driven code — and **routine boundaries are unknown**, so you cannot tell a routine's length or know you have enumerated them all. The docs pair this with the right discipline (P-112): two routines are "almost certainly" identified by source order "but neither has been reached from a call yet and so neither is written down as fact."
**Disasm:** yes · **Source:** `P 27-part6-notes.md` L11–16, L66–85; `P 28-part7-notes.md` L5–12, L142–82.

### P-124 · Segment census first — and link order is not run order
**Decides:** where to start on a new binary. Every part's notes open with a segment → linear → contents table: scene units, maths, the shared VGA unit, the player client, the RTL, DGROUP.
**Blind spot:** **link order is not run order.** In one part "the unit initialisation chain runs `1095` LAST of the four scene units, but the main body calls `1095` FIRST — so the segment numbers do not tell you the scene order." It also does not identify RTL routine offsets, which **differ per part** because each links a different subset (P-69/W-04). Related: one routine turned out to be a **unit initialisation section**, not part of the scene it was filed under.
**Disasm:** yes · **Source:** `P 26-part5-notes.md` L9–30; `P 27-part6-notes.md` L17–37; `P 28-part7-notes.md` L20–38.

### P-125 · Reconstruct the main body as a linear call list, then compare across parts
**Decides:** the driver, cheaply. Each part's main body is written out as an ordered call list with addresses; three parts turn out to be "byte for byte the same shape", including the closing volume-fade loop and a particular player call — which cheaply establishes an unknown routine's ubiquity. It also exposes what a part does **not** do.
**Blind spot:** semantics of an unknown call stay unknown — one is still named by its number, and what it asks the tracker to do "is not established". **Template matching also invites reasoning by analogy, which is the source of two withdrawn conclusions** (W-05, W-06).
**Disasm:** yes · **Source:** `P 26-part5-notes.md` L31–61; `P 28-part7-notes.md` L39–61.

### P-126 · Read the exit condition, not the obvious one
**Decides:** what actually terminates a loop — repeatedly not what it looks like. One part's main loop ends when the **volume** reaches zero, not on a key; with no tracker resident the volume query answers zero, so the first ending frame stops the scene after a single fade step, while in the demo chain it fades over as many frames as the music was loud. **"There is no fade-out without a tracker, and that is the original."** Elsewhere a `Stop` flag is cleared and never set and the drained key is stored to a slot nothing reads, so **a keypress does not end that part at all**; in another a keypress sets the frame count straight to 500, so **a key buys the fade-out rather than an exit**.
**Blind spot:** **the behaviour is environment-dependent, so a harness run and an in-chain run legitimately differ** — meaning a "wrong" observed ending may be correct. Static reading cannot tell you which environment the author tested in. And `KeyPressed` appearing in a loop says nothing about what it does: trace where the key's effect is *stored* and who reads it.
**Disasm:** yes · **Source:** `P 25-part4-notes.md` L180–218, L362–75; `P 28-part7-notes.md` L142–82; `P 26-part5-notes.md` L347–60.

### P-127 · Distrust a "dead read" until you have found its consumer
**Decides:** whether data is really unused. **"The 1,550-byte read is NOT dead — it is the font"** — 62 glyphs × 25 bytes, and the fact it contains only `0` and `$AB` "is exactly a one-bit font stored a byte per pixel". Contrast with the genuinely dead things, **each proved individually**: two filenames copied into a local and never looked at again; a third whose player ignores its parameter and opens the data file by name; two `MemAvail` results stored where nothing reads; an `ADD DX,AX` dead because DX is popped back on the next instruction.
**Blind spot:** **absence of a reader in *your* reading is not absence of a reader**, and the failure mode here was directional — "dead by analogy with another part", compounded by "low entropy therefore meaningless" when **low entropy is a format clue**. Resolve the address arithmetic to the reader before declaring data dead. Corollary: **a string constant is not evidence of a file dependency** — trace the parameter to a use.
**Disasm:** yes · **Source:** `P 24-continuation.md` L112–23; `P 27-part6-notes.md` L198–204; `P 28-part7-notes.md` L84–92.

### P-128 · Read a per-handler sign convention — they disagree between chunk types
**Decides:** a decoder's actual semantics. In one FLIC player: one chunk type copies words on a positive count and repeats on negative; a second copies bytes positive and repeats negative; a third is **the opposite way round from both**. One handler reads its per-line packet count and **throws it away**, the loop being driven by the width remaining; one chunk gets `+2` on its size as a workaround for encoders that understate it; an unknown type halts. Two handlers are compiled Pascal and are the same routine but for an in-place 8-bit-to-6-bit shift, "which is why it winds the offset back over the triples and forward again."
**Blind spot:** published documentation gives the **nominal** convention; only the binary gives this encoder's actual one and the `+2` workaround. **Conversely, reading the binary alone will not tell you the convention is unusual — you need the spec to know you have found a quirk.**
**Disasm:** yes · **Source:** `P 28-part7-notes.md` L142–211.

### P-129 · Read a hand-written PIT timing scheme rather than reimplementing it
**Decides:** how a part paces itself without `Delay`. A calibration routine puts PIT counter 0 into mode 2 with reload 0 — the same 65536 the BIOS uses, **so the BIOS tick keeps running at 18.2 Hz** — then times its own arithmetic a hundred times and keeps the average. The read routine latches counter 0 and reads the BIOS tick with interrupts off and the PIC masked, **bumping the tick by one if the IRR says a timer interrupt is pending while the counter has just wrapped**; the answer is a `LongInt` with the tick in the high word and the counter in the low, 1,193,182/second. The wait routine computes an **absolute** target, so decode time is free until it exceeds the frame delay and the animation runs at authored speed rather than decode-speed-plus-delay.
**Blind spot:** cannot tell you whether the calibration constant is right on any given host — it is measured at run time, so **a reconstruction inherits the emulator's timing, not 1994's.** A static reading also cannot tell whether the IRR fix-up ever fires in practice.
**Disasm:** yes · **Source:** `P 28-part7-notes.md` "Timing" L212–37.

### P-130 · Cluster references to a code-segment constant to reduce N sets to M
**Decides:** how many distinct constants there really are — "five references, two distinct constants", where one set is the other plus a hazard band, so one constant covers three call sites. The dedup also **yielded semantics**: the band blocks movement, cannot be stood on, and kills; a colour in both sets is the builder's brick, which is why laid bricks are walkable.
**Blind spot:** **identical current contents do not prove the author intended one constant** — they may be three tables that happened to coincide, and a faithful rebuild that merges them loses that. It cannot distinguish a copy from a shared reference in the original source.
**Disasm:** yes · **Source:** `P 25-part4-notes.md` L425–40.

### P-131 · Locate a routine by searching the binary for its own instruction signature
**Decides:** an address you cannot otherwise place. One routine was found by searching for `MOV DX,3C8 / MOV AL,0 / OUT DX,AL / INC DX / MOV CX,0300 / REP OUTSB`; the same search turned up a copy elsewhere and confirmed it.
**Blind spot:** **it finds bodies, not identities.** One routine "matches in five parts" only because it is byte-for-byte identical to another unit's routine, so the signature was finding *that* copy elsewhere. **A signature hit is evidence of an identical body, never of the same routine** — confirm identity by linear address and containing unit.
**Disasm:** no — byte-pattern search · **Source:** `P 23-deviations.md` L204–05; `P 24-continuation.md` L261–72.

### P-132 · Use a downstream tool's impossible null as a detector for wrong names
**Decides:** that a symbol table is wrong. A tool reporting "no data-file access" for two parts that certainly read the file was the give-away that a shared offset table had mislabelled routines. **A tool that depends on names becomes an oracle for the names.**
**Blind spot:** **fires only on *impossible* nulls, i.e. where you already know the ground truth.** A subtly wrong name that still produces plausible output passes undetected, so this catches gross errors and nothing else.
**Disasm:** no · **Source:** `P 03-borland-rtl.md` L283–86.

### P-133 · Provable document repair by separating independent corruptions
**Decides:** how to repair a damaged document and prove it. Two corruptions at once: 22 double-encoded characters (cp1252 read as UTF-8 — **every one reverses exactly**), and a variable run of blank lines, 9,759 of 10,736, that **looks uniform and is not** — "no arithmetic inverts it." What worked: within a run of consecutive **prose** lines the padding *is* constant (70 of 71 runs are exact multiples of the run's own minimum), so integer division recovers those, while tables, fenced blocks and indented code need no multiplier at all because markdown forbids a blank line inside a table. Proof standard: all 978 non-blank lines identical in content and order, all 39,773 non-whitespace characters identical. The repair script refuses to run twice.
**Blind spot:** **the cause was never found, so another document could be damaged the same way** — the repair is verified but the mechanism is not. And the "looks uniform" property is the trap: a uniform-multiplication assumption produces a plausible, wrong document.
**Disasm:** n/a · **Source:** `V CONTINUATION.md` "`00-map.md` WAS CORRUPTED AND HAS BEEN REPAIRED" L452–66, L490–510; `M demovt-byte-exact`.
# WITHDRAWN CONCLUSIONS

**70 entries**, grouped by the lesson each teaches. Every one is a claim made confidently in the project's own documentation and later disproved by measurement. Fields: **Claimed / Drove it / Disproved by / Lesson.**

Two things make this section the most valuable part of the corpus. First, several projects' worth of confident errors are recorded *with their evidence*, so the reasoning that produced them is inspectable. Second, the docs keep a **running tally of one error class**, which is the single most quotable fact in either tree:

> **"Every 'unfixable' thing this document has ever recorded turned out to be ours: five compiler differences, three structural deviations and a patch level."**
> **"Seventh time 'it is the toolchain' has been concluded here, and it has been true twice."**

---

## Class 1 — "It is the toolchain" (concluded 7 times, true twice)

### W-01 · The author's `SYSTEM` unit differs from ours
**Claimed:** two `Move` call sites go to a different RTL address than ours — "the first thing in the whole tree to suggest a different `SYSTEM`". The wider standing claim (carried for many sessions as "risk 2") was that the author's RTL was not this install's.
**Drove it:** a real, correctly-measured address difference; plus the 1.39b release's own linker map showing the author's RTL segment sizes differing from this install's.
**Disproved by:** two separate measurements. (a) The two addresses are **two different routines in the same library** — one is `Move` (compares pointers, copies backwards on overlap), the other, eleven bytes away in behaviour, is the compiler's **whole-array-assignment** copy with no overlap check. The original was making an *assignment* where our source called `Move`. Reproducing it needs a **named type on both operands**, because TP only permits whole-array assignment between operands of the same named type — "which is exactly why both sites read as `Move` for as long as they did." (b) The wider claim died outright when **`OBJECTS`, `DOS` and `SYSTEM` all three proved byte-identical to the original's**, so this install's RTL *is* what the author linked. Counter-evidence had been available all along: `SYSTEM`'s and `DOS`'s segment lengths already matched exactly.
**Lesson:** *"Read the two routines before concluding."* And the release-map finding "was about 1.39b's toolchain and does not carry to 1.31, exactly as the note there warned" — **scope a toolchain finding to the version it was measured on.** The withdrawal was made *within the hour*, and is logged as the seventh instance of the same class.

### W-02 · Six divergences are compiler differences
**Claimed:** six separate divergences were parked as properties of the code generator, each with a plausible mechanism, each sitting unexamined for sessions "because the note explaining it sounded checked".
**Drove it:** regions surviving both recorded compilers.
**Disproved by:** the compiler probe and the encoding tables. **Two were real** (the TP6/TP7 gap). One was the `$G` switch. Three were **our own source** — including the one called "the strongest divergence in the tree".
**Lesson:** *"Parking something as a compiler difference has been the single most reliable way to leave a source bug in place, and it takes one probe routine to check."* Prior on "it is the RTL or the compiler" should be low until a probe says otherwise. **Assume the same of the next one before parking it.**

### W-03 · `1a17:070f`'s register allocation is a code-generator difference
**Claimed:** the tree's oldest and strongest surviving divergence — TP insists on AX as accumulator, producing `MOV DX,AX / MOV AX,mem / SUB AX,DX` where the original has something else.
**Drove it:** it survived TP6, TP 6.01 **and** TP 7.01 — all three emit the same ten bytes. That is genuinely strong evidence.
**Disproved by:** the encoding fingerprint. `SUB BX,AX` is `29 C3` in TP's **inline assembler** and `2B D8` in TASM, and **the code generator emits neither** because it forces AX as the accumulator. The original has `29 C3`, so this is four instructions of **hand-written asm**, continuing a dead block already transcribed as `asm`.
**Lesson:** *"A divergence held for several sessions as a property of a code generator was three lines of assembler nobody had recognised."* An encoding fingerprint can reclassify a divergence from "compiler" to **not compiled at all**. And: **treat the last one as ours until a probe says otherwise.**

### W-04 · `188f:001b`'s `POP BP` vs `LEAVE` is a compiler difference — and separately, "`$G-` changes nothing"
**Claimed:** first a TP6-vs-TP7 codegen difference; then, in a work list, that trying `$G-` changed nothing.
**Drove it:** the first was plausible; the second was a note that "sat in a source file for sessions, was repeated in a handover and believed".
**Disproved by:** **it is the `$G` switch after all.** `LEAVE` is an 80286 instruction, so `$G-` cannot emit it, and with `{$G-}` at the top of that unit it is byte-identical on TP6 and TP7 alike. It changed exactly the one byte the unit was short. **But it has to stay local to that unit — a whole-tree `$G-` wrecks twelve of the fifteen.**
**Lesson:** check the **switch** space before the compiler space, and check switches **per unit**. A whole-tree test of a local switch looks like a refutation. And **re-run a cheap test rather than trusting a note about it.**

### W-05 · `1723:04b5` — the compiler folds `if C then goto L`, and our source already matches the release
**Claimed:** both halves, on the strength of a doc note asserting it had been confirmed against the release.
**Drove it:** the note *sounded* checked, and the adjacent divergence was genuinely real, which lent it credibility.
**Disproved by:** the probe. **Both halves were wrong.** TP6 does **not** fold it — the probe compiles to `CMP / 74 02 / EB 06`, the original's shape exactly. And the transcription did **not** use the release's `LABEL`/`GOTO`: it had a nested `if ... then begin ... end`, with an unused `label` declaration left in the file from a previous attempt.
**Lesson:** *"The doc asserted a source shape that the source did not have."* **When a note says "confirmed against the release", re-open the file and check it still says what the note says it says.** A corroborating release reading does not validate a compiler claim.

### W-06 · `1723`'s `Port[]` operand order differs by context
**Claimed:** an instruction-scheduling effect in the original's compiler — value-first in one place, port-first in another.
**Drove it:** an earlier measurement at two sites.
**Disproved by:** the probe emits the same sequence **in all three contexts** — after nothing, after an `OUT`, after a `CALL` — and the unit then compared clean at both addresses. "There is no scheduling effect here."
**Lesson:** **a one-site case that the compiler differs is a weak case.**

### W-07 · TP 6.01 is the missing patch level
**Claimed:** one of three candidates for the remaining toolchain gap.
**Drove it:** entirely plausible — 6.01's compiler is 69,278 bytes dated June 1991 against 6.0's 69,214 of October 1990.
**Disproved by:** building with it. The same units, the same region counts, **the same offsets to the byte**, and the probe shows the two emit byte-identical code.
**Lesson:** closed by build-and-measure, not by argument. A version difference in the *tool binary* is not evidence of a difference in its *output*.

### W-08 · `164b`'s 40 extra bytes are BP6-vs-TP7 codegen, therefore unreachable
**Claimed:** `String := array of Char` costs 18 bytes in the original and 41 in TP7, and the cost does not depend on the array length (a 60-element source compiles to the same 41 bytes as a 6-element one) — so it is a code-generator gap and the source should not be fitted to the byte count.
**Drove it:** a careful, correct measurement **plus a plausible mechanism**.
**Disproved by:** two units compiling to the original's exact size under TP7 ("so TP7 *can* reproduce this binary"), and then the unit itself compiling exactly — **the 40 bytes were two invented `String` locals, not the compiler.**
**Lesson:** the awkward postscript is kept deliberately: the mechanism named in the withdrawal **turned out to be real elsewhere** — it is exactly what two other divergences were, and TP6 closed them. So: **a plausible mechanism is not evidence even when it later proves true**, and what settled it was running the other compiler rather than arguing. Flagged in the docs as the second conclusion to fall to this same mistake.

### W-09 · The four remaining bytes in `1a17` are structural and unfixable from the source
**Claimed:** four places where the reconstruction must differ, written up as forced deviations on the reasoning that "a Pascal procedure must have one entry and one exit".
**Drove it:** correct reasoning from a false premise. Two units had both been on the "finished" line on this basis and both were wrong.
**Disproved by:** three independent lines. The release builds this very unit with `{$L}` and seven `EXTERNAL` routines whose entry points are **bare `PUBLIC` labels** — no `PROC`, no prologue, no epilogue, nothing forcing one entry or one exit. The encodings in the run are **TASM's**, not TP's. And the probe confirmed the epilogue cannot be suppressed any other way. The run was an external TASM module all along, 2,430 bytes, every difference a recorded relocation.
**Lesson:** *"That is true of a Pascal procedure and false of the original, which did not use one."* **A constraint of your own reconstruction can masquerade as a property of the target.** And the corollary: when something cannot be fixed from the source, ask whether it should be **in** that source at all. Also — "the split itself is an artefact of the transcription, not of the original."

### W-10 · `IN` and `OUT` are not expressible in Pascal
**Claimed:** three routines carried this note and were hand-written.
**Drove it:** a reasonable-sounding language limitation.
**Disproved by:** they are expressible — and the hand-written versions had **the right instructions with the wrong encodings** (TP7's assembler picks `89 C2` for `MOV DX,AX` and `21 D0` for `AND AX,DX` where the compiler emits `8B D0` and `23 C2`).
**Lesson:** the corrected rule is **conditional**: constant port → Pascal, computed port → assembler. And choosing asm where Pascal was used loses on **encodings**, which no amount of correct instruction selection recovers.

### W-11 · `ASCIIZ` must build its result in a local, because Pascal will not let a function alias its own result
**Claimed:** a forced deviation.
**Drove it:** an assumed language limitation, never tested.
**Disproved by:** **it will** — inside the body the function identifier denotes the result variable and can be indexed, so `ZToStr[I + 1] := ...` is ordinary Pascal and is what the original does. With the local removed the unit is **byte-identical with no fixups at all — the first exact match in the tree.**
**Lesson:** **a claimed language limitation is a testable claim; test it.** The other half of the same rule cost bytes in the opposite direction: `X := X;` on a function identifier compiles to a **recursive call**, because "nothing in Pascal reads a function's own result back."

### W-12 · `HEAPS.PAS` must declare its own `TObject`/`TCollection` stand-ins to stay independent of whichever Turbo Vision is installed
**Claimed:** a justification carried in a source-file header.
**Drove it:** reasoning about robustness. Never tested.
**Disproved by:** a one-file probe compiles under this TP6 in five bytes. **And it mattered**: locally-declared `TObject` method *bodies* would have been compiled into this unit's code segment, displacing everything after them, so fifteen methods could not have gone in cleanly.
**Lesson:** *"Never tested and it was wrong."* **A "keeps us independent" justification is worth one probe before it goes in a header.**

## Class 2 — a type or layout argued from a call site, corrected by the data

### W-13 · `SongColl` is a plain `TCollection`, not a `TStringCollection`
**Claimed:** confidently, and logged as the "eighth interface detail settled by a caller in another segment".
**Drove it:** a genuinely good argument. `1000:05cd` far-calls `1891:03a7`, which this tree had independently established as `TCollection.Init` from three `Init(n,n)` calls elsewhere; a `TStringCollection`'s constructor is `TSortedCollection`'s, a different routine. Everything else agreed too — `AtInsert(Count, NewStr(Token))` is the unsorted idiom, and the reader goes through an explicit `PString(...)^`.
**Disproved by:** an experiment on the **data** side. **TP6's `Objects` gives `TSortedCollection` no `Init` of its own**, so a `TStringCollection` *inherits* `TCollection.Init` and that call is exactly what one produces. The original's image holds **three** `Objects` VMTs of sizes 8, 12 and 13 where ours held two: 12 is `TCollection` (VMT 2 + Items 4 + Count 2 + Limit 2 + Delta 2) and **13 is that plus `Duplicates`**. Declaring it a `TStringCollection` recovered all 48 bytes at once.
**Lesson:** stated by the docs as a new instrument: **"A call site cannot name a type and a VMT can"** — a VMT is DGROUP data laid down where the type is declared, and its size word *names* the type. The corpus keeps both directions: a conclusion "settled by a caller in another segment" was overturned from the data side. *"The entry above got that wrong, and the refutation is worth more than the error."*

### W-14 · `TSong` is a plain record
**Claimed:** held since the reading pass, and load-bearing — it was the stated reason a 3,920-byte segment was deferred, because "every `Song.X(...)` in the release is a free function here".
**Drove it:** a call site pushing the Song as a parameter, which is what a free function looks like.
**Disproved by:** the constructor, in a segment nobody had read: `XOR DI,DI / CALLF <ctor helper>` with a `JZ` over the body, `TObject.Init`/`Done` calls, and both routines `RETF 6` — the hidden VMT word that **only constructors and destructors carry**. It is `OBJECT(TObject)`.
**Lesson:** **a record's free function and an object's static method call are byte-for-byte identical at the call site — only the constructor can tell them apart.** Worse, the conversion moved **zero bytes**, because `TObject` has no fields so the VMT link lands on two bytes already carried as filler — "which is exactly why nothing ever contradicted the wrong reading for the whole project." And the downstream deferral inherited the error: once corrected, the segment went in **in a single pass**. **When a premise falls, re-check every deferral built on it.**

### W-15 · `TSong+$0a` is `Name`
**Claimed:** a field name.
**Drove it:** real evidence — a routine disposes and re-news that field.
**Disproved by:** the routine that touches **eight** fields at once, each passing a field address with the offset in the instruction, plus `$03d0` = 16×61 pinning a different field as a comment block. With that fixed, the release's three-statement order puts `Name` two fields earlier, so `+$0a` is something else entirely.
**Lesson:** **one accessor is not enough to name a field, and this is the second time.** *"Prefer the routine that touches many fields at once; its ORDER is the evidence, not any single store."*

### W-16 · `TSong+$02`/`+$04` are a speed and a tempo, **not** the release's `SongStart`/`SongLen`
**Claimed:** the docs argued *against* the release's mapping.
**Drove it:** the values 1 and `$100` read naturally as a speed and a tempo.
**Disproved by:** the initialiser opens by writing exactly `0001` and `0100` into those two fields; the release's opens `SongStart := 1; SongLen := MaxSequence;` and **`MaxSequence` is 256 = `$100`**. First two statements, first two fields, both values exact.
**Lesson:** **a constant refuted a reading of the values** — a tempo of 256 is not a tempo, since a MOD's BPM runs 32..255. Check a plausible-value reading against the type's real range.

### W-17 · `Samples` is an 8-byte collection with 4 bytes of unexplained filler after each of three fields
**Claimed:** a record layout from the reading pass.
**Drove it:** the observed 8-byte groups, with the remainder named "filler".
**Disproved by:** they are real library collections — TP6's is **12 bytes** (`Items`, `Count`, `Limit`, `Delta`), and 8 + 4 = 12 three times over, so the "filler" *is* `Limit` and `Delta`. Five independent confirmations followed.
**Lesson:** **named filler is a hypothesis.** A size that closes exactly against a library type's real layout refutes it.

### W-18 · `RawChannels` is at `$1384`
**Claimed:** an address.
**Drove it:** `$1384` is what the instructions show.
**Disproved by:** `$1384` is the **base-1 base** — the compiler's subtracted index origin, not the array. A `FillChar` passes `$13a6` with a length of 272 = 8 × 34.
**Lesson:** a base-1 array's "address" in an instruction is one element low; **an unexamined `+1` or a suspiciously round base is a symptom.**

### W-19 · There is one Integer conversion in the fixed-point unit
**Claimed:** by omission — one conversion routine, with both scenes carrying a local rounding copy.
**Disproved by:** there are **two, twelve bytes apart, and they differ** — one truncates, one rounds, and callers pick **deliberately**. One scene's depth-sort key was off by up to one as a result.
**Lesson:** **two near-identical routines at adjacent addresses are probably two deliberately different routines.** Check every caller's target, not just the routine's shape.

### W-20 · `CmdList` is `array[0..255] of Byte`, and the asm reads `OFFSET CmdList+1`
**Claimed:** in a source comment which honestly flagged itself as "a guess that will have to be revisited".
**Disproved by:** a `MOV SI,imm` scan. The address is just past a known table and the next unit's first VMT is 64 bytes later, so it is 64 bytes — two per voice for 32 voices — and **local to one routine**. With the right bounds the `+1` comes off.
**Lesson:** the `+1` only reached the observed address if the array started **inside the previous table's last byte** — an impossibility that should have been the tell. And a `.TPU` holds zeros for `OFFSET`, so neither form was measurable earlier.

## Class 3 — the release led us wrong

### W-21 · `Buffers` is `array[1..3]`, and there are three disabled rotations
**Claimed:** copied from the release's `NumBuffers = 3`.
**Drove it:** the release, treated as authoritative for a count.
**Disproved by:** three independent measurements saying **1**: a `SIZEOF` passed as immediate `$0b`, one 11-byte record; an allocation loop closing with `CMP [BP-2],1`; and three buffers would run over three known variables' addresses. With one buffer **the clamp *is* the arithmetic**, so two of the three long-recorded "disabled rotations" were never disabled.
**Lesson:** **the release settles shapes and names; a COUNT is data.** Same class: `MaxChannels` is 8 here and 32 there, `DevStkSize` 1000 against 2000, `MaxOutputFreq` 45000 against 44000, and a volume table differs in **every entry but the first** — "the release settles shapes; it is worth nothing for data."

### W-22 · `SONGUNIT`'s record layout can be taken from the release
**Claimed:** nearly adopted wholesale.
**Drove it:** the release's first two fields map plausibly onto our measured offsets.
**Disproved by:** the release's own history block — *"06-Feb-1993 Remodelling. Made the memory-optimized, object-oriented interface."* Its layout does not fit the older version's offsets at all. Names and constants adopted; **layout taken from the disassembly.**
**Lesson:** the rule as hardened is not "never take a layout from the release" but **"take it only when the binary confirms it field by field."** The counter-case proves the edge: a different record type landed on **every one of eighteen already-measured offsets, 34 bytes**, and adopting it closed two open questions — so it was adopted, and said so where it was.

### W-23 · Five release source comments describe what the older version did
**Claimed:** five behaviours, read off 1.39b's commented-out lines sitting at exactly the divergent spots.
**Drove it:** commented-out code at precisely the right place is extremely suggestive.
**Disproved by:** **five of six differences contradict them.** The detectors *do* set a flag where the release's do not — "the detectors configure as well as detect"; one routine is guarded in its entirety with the release's inner guard kept where it can never fail; another routine does not exist and two calls are ordered the other way; one is called with a variable where the release has a literal commented beside it; and one has **no** wait loop but **does** call the reset the release comments out.
**Lesson:** **"A commented-out line in the release is evidence that the author was editing that spot, and nothing more. Read the bytes."** This caught the project **four times in two segments**. The one exception that keeps it honest: a dead line in the release *was* the answer once — "a commented-out line is not a record of what 1.31 did — **except when it is the line 1.31 still has**."

### W-24 · `DEMOMATH.ASM` holds three routines
**Claimed:** the shared external object exports three.
**Drove it:** three were called; three were transcribed.
**Disproved by:** reading one more binary — **the module has five.** Two more sit ahead of the table in both binaries and were missing. Neither is called from Pascal in any part read; they survive the link because an external object is linked **whole**.
**Lesson:** **membership of an external object is established by its whole extent, not by its call graph.** Reading one more part changed the module's boundary. (Bonus finding recorded there: the 16.16 multiply needs **no shift pair**, because `IMUL` leaves the product in `EDX:EAX` while TP returns a LongInt in the *separate* registers `DX:AX`.)

### W-25 · 1.39b and this version share the object module's source
**Claimed:** the release's `.ASM` is the same code.
**Drove it:** it *is* the same code.
**Disproved by:** same code, **not the same source** — one routine is 8-way unrolled here and 16-way there; this version advances the source position inside the loop where the later one pre-multiplies; the computed jump ends differently; there is **one** Pascal entry with a trailing Boolean argument where the release has two procedures; and the frame is hand-written, so bare `PUBLIC` labels are right.
**Lesson:** **same-code assumptions hide design-generation differences.** This is the earlier, simpler design.

### W-26 · `1880`/`1650`/`1b54` have no counterpart in the release — an "eight units with no counterpart" list
**Claimed:** after four sessions of hand-matching found none, and all three carried **invented names** on that basis.
**Drove it:** repeated negative search, plus one specific file checked once and written up as a caution, which "quietly hardened into 'the root does not pair'".
**Disproved by:** the automated pairing scores — 71.1%, 65.5% and 44.3% respectively, with one confirmed three independent ways (score, all five signatures matching one for one, and two of them called from outside). One directory listing and one string comparison overturned the "root does not pair" claim: a segment is 41 of 52 literals of a root-level file.
**Lesson:** **a negative result about one FILE is not a result about its DIRECTORY.** And the tool also confirms the true negatives — two segments scoring 13% and 6% are consistent with genuinely having none.

### W-27 · One index-bias rule applies to all four objects
**Claimed:** the first object's loader semantics (index +1, word colour halved) hold for the whole table.
**Drove it:** four structurally similar loops, assumed identical.
**Disproved by:** there are **four separate copies of the loop and the first differs** — the others leave indices unchanged and read a **byte** colour. Applying the first's rule to all four "put the pistol's faces in the top-left corner and made the sailboat cover the screen"; the index range proves it. The first object needs the bias for the opposite reason: without it one vertex is never referenced, with it the dummy origin never is.
**Lesson:** **four copies of a loop are four loops.** Encoded into tooling afterwards so the class cannot pass silently: the extractor now flags any index outside range.

### W-28 · Three part-002 models identified from one view
**Claimed:** a 75-vertex flying saucer, a 68-vertex street lamp, a 32-vertex telegraph pole.
**Drove it:** each rendered from a single axis pair and confidently recognisable.
**Disproved by:** re-rendering on other axes — the saucer is the **USS Enterprise** seen from above; the lamp is a **revolver** and the pole a **sailboat**, both modelled along Y and unreadable until Y is horizontal. "From the front all three are ambiguous." Independently confirmed by an original author, and by the soundtrack being *StarTrek Samples* with a banner reading "WRONG UNIVERSE" — which is the joke, and why the objects are unrelated.
**Lesson:** **one projection is one hypothesis**, and the wrong reading is *confidently recognisable*, which is what makes it stick. Render every view before naming anything. The tool now renders five axis pairs.

## Class 4 — a measurement artefact read as a finding

### W-29 · Four 320×200 images — twice, independently, in two different parts
**Claimed:** four 64,000-byte reads are four separate screens. In one part they "first appeared as four 320×200 images each with **two** ring centres"; in another as "four near-identical houses that differed by 29–48%, which looked like animation frames".
**Drove it:** 64,000 bytes is exactly a mode-13h screen, the carved images looked like plausible pictures, and the 29–48% inter-frame difference **actively supported** the animation reading.
**Disproved by:** the loader calls the plane-select **before each read** — they are planes, not screens. De-interleaved: one centred 640×400 tunnel, one 1280×200 panorama. Corroborated by CRTC Offset := 80, 64,000 ÷ 160 bytes per plane-line = 400 lines, a 640-entry plane table, and an initial radius of exactly 100.0 = (400−200)÷2.
**Lesson:** **a plausible image is not a correct image** — the twin ring centres were a *stride artefact*, not content. The tell is always in the loader, never in the pixels. And this same trap was fallen into **independently in two different parts**, which is why it is the strongest argument in the corpus for writing a blind spot down where the technique is used.

### W-30 · The 1,550-byte block is dead, provably — wrong twice over
**Claimed:** with an explicit claim of proof, **in two documents**: the block contains only `0` and `$AB`, the same bytes appear byte-identically in two parts, and "in both parts the only instruction that mentions the destination buffer is the `BlockRead`".
**Drove it:** absence of any reference to the load address, content that looked like noise, and **dead-by-analogy** with another part where the identical block genuinely is dead.
**Disproved by:** it is a **5×5 bitmap font**, indexed off a *different base* — the difference between load address and index base is `806 = 32·25 + 6`, giving a 62-glyph table biased by 32. The `0`/`$AB` values are exactly right, because the renderer only tests `<> 0`. **And the extraction offset was also wrong**, 256 bytes too far in, which is *why* it looked like soup.
**Lesson:** **"nothing references the load address" is not evidence of deadness** — Pascal indexes bitmaps off biased bases as a matter of course. Two bad reasons compounded: dead-by-analogy, and low-entropy-therefore-meaningless when **low entropy is a format clue**. And **two independent errors can reinforce each other into a confident conclusion.** The bad carve is still on disk, marked to be ignored.

### W-31 · The 51 curves are signed X offsets
**Claimed:** 36,414 bytes = 51 curves × 357 signed 16-bit X **offsets**.
**Drove it:** the size factorisation and stride were both right; only the interpretation of the values was assumed.
**Disproved by:** plotting them. Every value lies in 0..317 and every curve starts at x = 160, the centre of the screen — they are **absolute X coordinates**. And the 51 curves are one shape at 51 amplitudes, growing monotonically with the index, so **the curve index is an amplitude dial**, which is what makes the four passes work.
**Lesson:** factorisation fixes stride and count but **never semantics**. Plotting all 51 overlaid settles in one image what the size cannot say at all.

### W-32 · The star waypoint tail implies a second consumer
**Claimed:** implicitly, as an open question — 500 declared records with authored data past the walked range.
**Disproved by:** only 56 records are non-zero, 1..57 hold real data, and the walk runs 50 down to 1. So a few are authored-but-unreachable and 443 are padding — "not a second consumer, just a generous bound."
**Lesson:** **unused authored data is usually authoring slack, not a hidden code path.** Prefer the deflationary explanation until a second reader is actually found.

### W-33 · `DS:$04bc` is a second period table
**Claimed:** `Periods_`, a sibling table.
**Drove it:** it sat 168 bytes from a known period table and looked like one.
**Disproved by:** an exact numeric relation — each entry is `round(sqrt(P[i] * P[i+1]))`, the **geometric midpoint** between adjacent semitones, for 83 of 83 pairs, which is exactly what a "first entry not exceeded" search needs because pitch is logarithmic. They are search thresholds.
**Lesson:** *"The reading pass had the mechanism right and the table's identity wrong."* **An exact numeric relation beats adjacency.**

### W-34 · The gain ladder has 132 divergences — and they will close when the preceding routine lands
**Claimed:** 132 real differences, plus a prediction in a handover doc that they were displacement artefacts.
**Drove it:** a fixup cap counting a 32-byte run of unresolved `DW OFFSET` table entries as real.
**Disproved by:** **the tables were correct the whole time** — 132 phantom regions became ten real ones. And the prediction "was tested when the routine landed and was wrong. They were never displaced."
**Lesson:** when a long run of zeros lines up against plausible data, **check for zero before believing the cap**; and **a prediction derived from a known-suspect measurement inherits its fault.** Mark predictions in handover docs *as* predictions — they get believed anyway; two logged cases were believed for six iterations.

### W-35 · The poll is non-functional, but byte comparison says the unit agrees
**Claimed:** the docs said the poll was non-functional (correct) while the tool reported agreement (incorrect).
**Disproved by:** a `CALL` to a **one-byte local stub**, whose displacement TP emitted as **zero** in the `.TPU`, so the tool filed it as a pending fixup and it read as agreement — for the unit's whole life.
**Lesson:** *"The general lesson is about the tool, not the poll: a zero is only evidence of a pending fixup if something is actually pending. A near call to a local label is not, and one that comes out zero is **a bug wearing a fixup's clothes**."*

### W-36 · The gain-ladder pointers are correct
**Claimed:** implicitly, by the tool reporting no divergence.
**Disproved by:** `OFFSET SetGains` was the address of a `JMP` opening the procedure, while every delta was measured from the first gain cell — so **all four pointers aimed three bytes before their targets, invisibly, for as long as that `JMP` existed**, because a `DW OFFSET` sits in the `.TPU` as zeros.
**Lesson:** **anything the verifier excuses is unmeasured**, so it must be derived from a symbol whose base you can prove. Removing the `JMP` fixed three code bytes and four wrong pointers at once and only the code bytes were measurable. *"A deviation is not just its own bytes; it is everything measured from them."*

### W-37 · Four tool-ranking and accounting failures, every one flattering
**Claimed:** various passing results.
**Disproved by:** five separate bugs in one tool — ranking by "fewest real differences" scores a run of zeros as perfect, so **two units passed that should not have**; ranking by "most exact matches" drifts when sizes differ and reports a meaningless offset; counting any zero as a fixup let one unit read **68% when it was 6%**; a rule made a good partial unit report `NOT LOCATED`; and reporting on a **stale** artefact recorded an operand-order fix as having no effect when it had worked. Plus a hardcoded per-block shift going stale after an edit: **73 phantom mismatches.**
**Lesson:** *"Each one made the reconstruction look better than it was, which is the direction of error that matters here."* A percentage is a property of the tool as much as of the code. **Search for the shift; never hardcode it.**

### W-38 · One block reports five real differences / another reports four
**Claimed:** small, plausible difference counts.
**Disproved by:** two distinct measurement faults. One block's **true alignment was −1,228, outside the tool's ±600 search window** — widened, it is clean. The other's block **ended at the next routine's `ENTER` instead of at its literals**, swallowing four bytes of the next routine's literal, because TP emits a routine's literals immediately *before* its code. Twice in two segments.
**Lesson:** **a too-narrow search window does not fail loudly — it returns the best shift it could reach and a plausible-looking difference count.** And check the block boundary before believing a small count.

### W-39 · `census.py` reports zero virtual-call sites in two segments
**Claimed:** nearly read as a finding about the binary.
**Disproved by:** the regex's own 32-bit assumption — **in 16-bit ModRM the rm field is an addressing mode, not a register**, so the byte pair it searched for meant `[BX]` rather than `[DI]`.
**Lesson:** **an empty result from a new scan is not evidence of an absence.** Validate a new scan against a segment whose answer you already know.

### W-40 · Six of 21 far-call targets are real
**Claimed:** from an opcode scan.
**Disproved by:** they decode to nonsense segments — the `9A` byte occurs in data and inside other instructions. Same family: a ModRM-filtered hit that decoded as the **tail of another instruction**, and a `DEC word [addr]` that was really `PUSH -1 / PUSH CS / CALL`.
**Lesson:** **a byte-pattern hit is a candidate, not a finding** — recorded as violated three times, the third of which "cost two wrong leads in a row".

### W-41 · The 88 remaining DGROUP bytes and the 63 differing bytes are separate open problems
**Claimed:** two independent residuals.
**Disproved by:** all 88 are segment bytes **exactly 7 paragraphs low** — the one remaining code gap seen from the data side; and all 63 were DGROUP **variable addresses**, closed at a stroke by the link comparison.
**Lesson:** **a residual difference can be a single upstream defect projected into another view — count the runs before theorising.**

### W-42 · Part 003 scene 2 is clean
**Claimed:** by two earlier passes.
**Drove it:** both passes had aimed their checks at the **arithmetic**, and the arithmetic was fine.
**Disproved by:** four defects, the real one in the **loading** — a `BlockRead` into a raw hard-coded address in *our* data segment, so the waypoint table stayed all zeros. **Both** reported symptoms, "does not move around the screen" and "ends sooner", were that one bug. Plus unsigned-not-signed bounds tests, a Pascal-ised hand-asm loop, and a routine that is the **unit initialisation section** rather than part of the scene.
**Lesson:** **"clean" is only as broad as where you looked — record what a pass *checked*.** Two symptoms are not two bugs. And the generalisation became a lint rule: "any `BlockRead` into a hard-coded address is this bug; the rest of the tree is worth grepping for the pattern."

## Class 5 — reasoning by analogy across binaries

### W-43 · Part 001's player-client unit is like part 002's
**Claimed:** addresses derived from a sibling binary rather than read.
**Disproved by:** reading part 001. It has a **fourth** dispatch call part 002 lacks, and **lacks** one part 002 has — so everything after them was off, and two routines were missing entirely.
**Lesson:** **do not derive one binary's layout from another's by analogy. Read each.**

### W-44 · Function 3 is a part-001-only call
**Claimed:** a scope claim.
**Drove it:** found in one part, absent from the one other part then read.
**Disproved by:** two more parts call it.
**Lesson:** **"only part X does Y" from a two-part sample is a sampling artefact.** Withdraw scope claims as the survey widens.

### W-45 · Parts 002 and 004 have their own VGA and player units; one primitive is a part-004 peculiarity
**Claimed:** four separate units with different routine sets.
**Drove it:** the segments differ in size and the addresses differ everywhere — which is genuinely suggestive.
**Disproved by:** **"They did not."** Every part links the same two source units and the smart linker drops what the part never calls. Proof is the **monotonic order** of survivors' offsets across all seven parts, with a missing routine shifting everything after it by exactly its own length. One case is pure arithmetic. Four duplicate units deleted.
**Lesson:** **differing addresses and sizes are the expected signature of subset linking, not of distinct code.** Test order before concluding difference.

### W-46 · One routine is shared across five parts
**Claimed:** on a signature search hitting five binaries.
**Disproved by:** it is byte-for-byte identical to a *different unit's* routine, so the signature was finding that copy elsewhere. Seven of the unit's eight routines appear in no other part. The one genuine duplication is those two — two distinct routines at different linear addresses with identical bodies.
**Lesson:** **a byte-signature hit proves an identical body, never the same routine.** Confirm identity by linear address and containing unit. (Sibling case: another unit assumed part-002-only turned out to be part 001's, identical but for two far-call fixups — so run the cross-part scan over *every* unit, not just the ones you suspect.)

### W-47 · This part's mode-set deliberately omits the VRAM clear
**Claimed:** in a source comment, with an invented rationale for the deliberate difference.
**Drove it:** our own transcription of the routine, plus a plausible story.
**Disproved by:** comparing two parts' copies — 93 bytes, byte-for-byte identical but for one address. **"It does not; the bytes plainly contain it."** Three errors in that transcription: two immediate reloads that should be decrements, and the missing `REP STOSW` that clears all 64K. Consequence: a scene was starting in whatever the previous scene left in VRAM. The same sweep found another routine missing its `FillChar`.
**Lesson:** **a comment asserting a *deliberate difference* is a claim requiring the same evidence as any other.** Duplicate copies across binaries are a free audit of your own transcription — and here it found errors in *ours*, not in the original.

### W-48 · The whole build is `{$S-}`
**Claimed:** established across four parts and passed globally.
**Disproved by:** **one part was built `{$S+}`** — its procedures open with the stack-check call where the others do not, "the opposite of every other part read so far".
**Lesson:** **compiler switches are per-unit facts, not project facts.** Re-measure the prologue in each new binary. (Same shape as W-04's per-unit `$G`.)

## Class 6 — the tool's output taken as authoritative

### W-49 · A routine appears in two units, so the original duplicated small routines
**Claimed:** duplication.
**Drove it:** the disassembler listing a routine under two segment bases.
**Disproved by:** linear arithmetic. A unit's real extent is `(next base − this base) × 16`, and both "duplicates" sit exactly one byte past the end — two address pairs proved to be the **same six bytes** at one linear address. The tool lists a routine under two bases when ranges overlap. Written as **"That was wrong."**
**Lesson:** **"A Ghidra segment listing is derived, not authoritative."** Convert to LINEAR before believing two things differ or duplicate. Sweeping for the same artefact class found four more — **and one was hiding a real error** (W-43).

### W-50 · A segment labelled `CODE_13` is code
**Claimed:** by the tool, and initially accepted.
**Disproved by:** it is the **initialised data segment** — DGROUP — found by reading the relocated word in the RTL prologue, which for that part gives exactly the block the tool labels as code.
**Lesson:** **loader-assigned block *kinds* are guesses.** Recover DGROUP from the program's own prologue, which states it authoritatively.

### W-51 · Ghidra's names for two graphics primitives, and its two digging-skill labels
**Claimed:** by the tool: a rect fill and a triangle fill; and two named skills.
**Disproved by:** reading them. Both "fills" are **one-pixel-thick spans**, one vertical and one horizontal. And **the two skill labels are the wrong way round** — one is diagonal, two pixels along and one down every sixth frame; the other is horizontal and never changes Y. That also flipped the level script.
**Lesson:** **auto-generated names are hypotheses, sometimes inverted ones.** Rename from behaviour. (Honest counter-note: an existing plate comment *was* independently corroborated elsewhere — auto annotation can be right.)

### W-52 · One routine copies within the virtual screen
**Claimed:** from the decompiler — "which shows nothing at all".
**Disproved by:** the disassembly, which loads `ES := $A000` and `DS := VirtScrSeg`, so the copy writes to the **display**. Two further details only the disassembly gives: the walk advances the *source* alone, which is what makes a strip appear to slide down, and the guard means a finished column is never copied again.
**Lesson:** **the decompiler loses segment register loads.** For any 16-bit routine touching video memory, read the disassembly. (Same class: the decompiler mis-resolves CS-relative constants, substituting the image base for the owning segment, and renders x87 traps as argument-less calls.)

### W-53 · One offset→name table serves every binary
**Claimed:** RTL routine offsets are stable across ten programs.
**Drove it:** **a stable core really does exist** — four routines hold their offsets everywhere, which made the assumption look confirmed.
**Disproved by:** everything above that core shifts; there are at least **four distinct RTL layouts**. The give-away was a *downstream* tool reporting "no data-file access" for two parts that certainly read the file.
**Lesson:** **a partially-confirmed invariant is the dangerous kind** — the stable core validated an assumption false everywhere else, and the result was mislabelled routines in *most* parts. Verify an invariant at the range you intend to use it over, and **watch for downstream tools returning impossible nulls.**

### W-54 · The RTL prologue signature can be written with literal bytes
**Claimed:** a pattern read straight out of one image would match every part.
**Disproved by:** the bytes had been read from a **relocation-masked** image, so the zeros were baked into the pattern; the real segment values differ per part and a literal match finds nothing.
**Lesson:** **any byte pattern taken from a relocatable image is contaminated by fixups.** Mask relocated words before using bytes as a signature — and **a zero in a candidate pattern is a prime suspect for being a fixup slot rather than real data.**

### W-55 · A flat byte scan finds the FP emulator trap sites
**Claimed:** implicitly, by patching on byte match.
**Disproved by:** one part shows **7 raw `CD 3x` hits and zero real traps.**
**Lesson:** a byte pattern that also occurs in data or mid-instruction needs a disassembly-level filter. **Pick the one binary you have independent reason to believe is clean and use it as a false-positive control.**

### W-56 · `INT 3Ch` is ESC with a direct disp16 operand
**Claimed:** the trap could be undone as NOP + WAIT + ESC — correct **length**, so it looked right.
**Drove it:** the operand byte is always one of four values, which correctly identified the trap; length preservation then made the simple form look sufficient.
**Disproved by:** the `CS:` prefix was gone, so every code-segment FP literal silently resolved against **DS** and decoded as garbage. The tell was the target address holding what looked like coordinate pairs instead of floats — which it genuinely was, belonging to something else.
**Lesson:** **matching instruction *length* is not matching instruction *meaning*** — a dropped segment prefix reassembles cleanly and fails silently. And **when a patch produces plausible-looking data at the target, that plausibility is not confirmation**: ask whether the data belongs to the thing you think you are reading.

### W-57 · `INT 3Eh`'s operand byte is an x87 sub-opcode
**Claimed:** by uniformity with the rest of the trap range.
**Disproved by:** the same byte value appears under two different trap numbers meaning two different things, so the second must be a **dispatch index** into the emulator, not an opcode.
**Lesson:** a decoding table extrapolated across a range will over-generalise. **A collision between two entries is the cheapest available disproof** — look for the same byte in two contexts.

## Class 7 — read one instruction out

### W-58 · Three loop re-entry points (one part, one audit round)
**Claimed:** three loop shapes.
**Drove it:** converting the disassembler's printed flat-segment addresses to segment offsets and **landing on the wrong instruction**.
**Disproved by:** reading the targets. One jumps to the **DS reload**, not the following increment — so re-entering one instruction later reads path entries out of the wrong table and the dots fly in a straight line. One **does** land on the increment; reading it as landing after held the pointer back on every transparent pixel and slid the picture apart. One returns *before* an `XOR AX,AX`, so a high byte is **not** cleared per cell and four carries accumulate across cells — clearing it inside the loop **puts the fire out**.
**Lesson:** two lessons, both stated. Recompute the segment conversion **per segment** and check every branch. And: **"the byte check did not catch any of these, because a branch target is one byte and looked like an ordinary displacement"** — after which the tool was changed to refuse a one-byte hole sitting immediately behind a short jump or `LOOP`. **A verification tool's masking rule is part of the measurement.**

### W-59 · One branch's polarity, inverted
**Claimed:** a glyph feed guarded the other way up.
**Disproved by:** the branch is a `JNZ` **into** the feed; the wrong reading feeds only one row of every glyph — "which is exactly 'single lines, not fonts'."
**Lesson:** **branch polarity is a coin flip you must actually read**, and the symptom is diagnostic once you know the shape.

### W-60 · A black pixel ends the scan
**Claimed:** `while GetPixel <> 0`.
**Disproved by:** the branch goes to the recording code and the fall-through jumps straight to the increment — **the scan carries on either way. A black pixel is skipped, not an end.** The wrong reading stops on the first pixel, and because the renderer only draws 195 rows while the scan starts on row 199, **the effect produces nothing at all** and reads as the scene skipping ahead.
**Lesson:** **`continue` and `break` differ by one branch**, and the resulting failure — an entire effect producing nothing — is easy to misattribute to a missing call.

### W-61 · The picture overlay skips transparent pixels
**Claimed:** plot-if-non-zero at the same offset.
**Disproved by:** the destination pointer advances on **every** byte, so a run of zeroes **shifts the rest of the picture left** rather than leaving a gap.
**Lesson:** whether the destination advances on a skipped pixel **is** the semantics of a transparent blit. Read the increment's placement.

### W-62 · The climb loop continues after finding a wall pixel
**Claimed:** the row loop carries on.
**Disproved by:** an unconditional `JMP` leaving **both** loops. "That JMP is load-bearing. The new Y is one LESS than the row just tested, so a row loop that carried on would step back onto the row it came from and never advance — which is exactly what an earlier transcription did, and **it froze the frame loop at the first lemming that met a step.**"
**Lesson:** **an unconditional `JMP` out of nested loops encodes a break-out-of-two that Pascal has no direct form for.** Read the target; do not assume fall-through.

### W-63 · A rotation's Y term is an addition
**Claimed:** `X*Sin − Y*Cos` the wrong way round.
**Disproved by:** the instruction **subtracts** the `X*Sin` term from `Y*Cos`. The wrong sign order mirrors the mesh about the wrong axis.
**Lesson:** read which operand is the subtrahend **at the instruction**, not from the algebra you expect.

### W-64 · A middle section is a nested `if`
**Claimed:** a nested `if` with an `else` branch containing an increment.
**Disproved by:** Borland's `FOR` shape — `MOV var,0 / JMP past / INC var / body`. **The `INC` that looked like an `else` branch is the loop increment.**
**Lesson:** one misread loop shape propagated into **three** wrong facts — the variable's role, the nesting, and where a guard sits. (Note in the same paragraph: a `CLD` there is hand-written, because the `FillChar` is a runtime call and nothing in the body asks the compiler for one.)

### W-65 · A register serves as both loop counter and frame base
**Claimed:** one register, two roles.
**Disproved by:** the register is the outer loop counter; the frame base lives in a local. Conflated, "every tile was built from the wrong bytes".
**Lesson:** **track register lifetimes explicitly** — a register reused for two roles reads as one.

## Class 8 — frames, locals and invented storage

### W-66 · Various invented locals and misread frames (five instances, one class)
**Claimed:** (a) `PlayModule`'s parameters are `String` with two locals; (b) `Ok` is a separate local; (c) `Install` declares a local `S` opening with `S := Name`; (d) `TransformPoint` has two locals; (e) five differences in `PlayStart` "will come right".
**Drove it:** in (a) the compiler's parameter-copy groups read as assignments — "reading them as assignments is what invented the two locals". In (c) eleven isolated single-byte differences at a four-byte stride, each off by exactly `$01`, plus a frame 256 bytes deeper than the original's. In (e) a mechanism that **had genuinely worked four times before**.
**Disproved by:** (a) the `ENTER` immediate fixes the parameters as a shorter string type — 162 bytes = 80 + 80 + result + pad, where full `String`s would give 676; −514 bytes. (b) the tail reads the result byte at an **odd** offset TP will not give a declared variable; −10 bytes. (c) **there was no `S`** — the 256 bytes are a `WriteLn(A+B+C)` concatenation temporary, and two observations separated them: the parameter is already copied to its own slot, so a second copy would be visible, and a later instruction copies the parameter's own slot to the destination with nothing between. (d) the original's `ENTER` is two words smaller and a store goes to DGROUP, so the two "locals" are **globals**; moved, the routine matches all 293 bytes. (e) both explanations were wrong: an invented `Word` parameter **and** a routine left near when it is far — two errors that **cancel in the frame size and nowhere else**.
**Lesson:** **a frame larger than the locals explain is a compiler temporary or a `with` slot before it is a missing variable**, and inventing a variable to explain frame size manufactures a second error on top of the first. This is the **third unit** to make that error, and one of them was a real divergence with the wrong cause attached. Also: **"a mechanism that has worked four times is still not evidence about the fifth"**; and the frame *size* proves nothing — four bytes plus a word and three bytes plus a word both give `ENTER 8,0`, so **get the local count right, and read the offsets one at a time.**

### W-67 · Two structural transcription errors that changed addressing
**Claimed:** (a) a scene's two effect halves are separate `assembler` procedures taking the block offset as a parameter; (b) three routines are unit-level with unit-variable tables; (c) one routine is an `assembler` procedure; (d) "one small liberty" shortening a four-instruction sequence to one.
**Disproved by:** (a) the segment holds only two functions, and **both halves are inline assembler inside one loop body**, reading a local at `[BP-6]` that the Pascal above has just loaded. Splitting them into procedures made it `[BP+4]` and added a prologue and a return. (b) all three are **nested**, each ending `RET 2` and reaching the enclosing scene's locals through a static link — our version turned every one of those into a DGROUP read; re-nested, one matches all 121 bytes. (c) the original opens `PUSH BP / MOV BP,SP` and closes `LEAVE`, a frame it neither needs nor uses — the signature of a **plain** Pascal procedure whose body happens to be one `asm` block. (d) the byte diff.
**Lesson:** **a procedure boundary is a real, checkable fact — inventing one changes the addressing mode of every local it touches.** `SS:`-relative reads through the static link are the signature of nesting. An unused frame is evidence about the **declaration form**, not noise. And **a self-declared "small liberty" in hand asm is a deviation that should have gone in the ledger** — the byte check is what surfaces liberties you have talked yourself into.

### W-68 · The fade loop, three positions, two withdrawn
**Position 1 (withdrawn):** transcribe the overrun literally — the original touches indices 768 down to −2, where 768 is `[BP]` itself and −1/−2 are dead stack below the frame. **Disproved by running it:** verbatim transcription "reproduces the original's *arithmetic* but not its *behaviour*" — the three writes land on TP's frame instead, and across 63 calls corrupted something that mattered: **the scene faded to black and hung.** The original survives because `LEAVE` reads BP before popping and the caller keeps nothing in BP.
**Position 2 (withdrawn):** widen the array so the writes have real storage. It worked, but "left a strange declaration in the source purely to reproduce side effects that cannot be observed."
**Position 3 (current):** a bounded loop. Effect on output **none, and provable rather than assumed** — only the first 768 entries are ever written to the DAC, so the palette is bit-identical.
**Lesson:** **the verbatim rule has a hard boundary at the stack frame.** Where a routine writes outside its own storage, "verbatim" is not "faithful" — and the right test is whether any **observable** output differs, which requires *naming the observer*.

### W-69 · Two empty method bodies are a construction, not a finding — the project's own self-accusation, withdrawn
**Claimed:** writing two empty overrides so their 50 bytes fall past the segment's end was written up as "arranging the source to fit the measurement, which is the one thing this project does not do", and flagged as such in the source.
**Drove it:** honest scruple. Two alternatives had been eliminated by measurement, and **a probe appeared to settle it against us** — the compiler does emit both empty bodies, 27 bytes each, "the sixth such claim tested and the sixth to fail".
**Disproved by:** a caller in another segment. The compiler smart-links **at the routine level at EXE build time**; the base class is never instantiated, so its VMT is dead and dropped, and it was the last thing referring to those two bodies. Every other base method survives because a live descendant's VMT names it. **The probe had been testing the wrong stage** — the `.TPU` keeps every routine and the *linker* removes them.
**Lesson:** **a probe can answer a question about the wrong stage.** Ask whether the question is about the compiler, the intermediate artefact, or the final image. The note calling the arrangement a construction is now itself wrong, and corrected — a withdrawn *self-criticism*, which is a genuinely unusual entry.

### W-70 · A deviation forced by the compiler, and an "invisible" one
**Claimed:** (a) a table's initialiser cannot be written because the compiler rejects the circular unit reference the original must have had, and "the obvious repairs are all worse"; (b) that deviation "cannot move a byte of any measurement this project makes".
**Drove it:** (a) real compiler errors, with and without switches, and no linear compile order that helps — whichever of the three compiles first needs another's artefact. (b) correct reasoning about the intermediate artefact: a typed constant is initialised data absent from the compared range, and the call is a fixup.
**Disproved by:** (a) a **negative search** — every segment scanned for a store to that address range in every encoding, and **not one exists anywhere in the program** — proving it is linker-laid initialised data, so the source must name both loaders, so the shape must be expressible. It is: the compiler accepts the cycle on a **second** pass, via a bootstrap compile. (b) **the LINK is the measurement it can move.** Nothing referenced either loader, so the smart linker discarded both units and a third with them: **4,141 bytes missing.** "Flagged as invisible and has now become the single largest thing wrong with the image."
**Lesson:** **"When a deviation looks forced, check whether the ORIGINAL could have had it"** — that turned "we cannot do this" into "we are doing it wrong" in one search, and it is what overturned the tree's only deliberate data deviation. And: **an "invisible" deviation is only invisible to the instruments you currently have; adding an instrument reclassifies it.** (The author almost certainly hit the same compiler error and never noticed, because intermediate artefacts accumulate and only a *clean* build deadlocks.)

## Class 9 — behaviour, environment and naming

### W-71 · Three environment-dependent behaviours read as defects
**Claimed:** (a) a part's abrupt single-frame ending is a bug; (b) a keypress ends a part; (c) a scene "runs but hangs".
**Disproved by:** (a) the loop ends on **volume**, not on a key — with no tracker resident the volume query answers zero, so the first ending frame stops the scene after one fade step. **"There is no fade-out without a tracker, and that is the original."** (b) in one part a stop flag is cleared and never set and the drained key is stored where nothing reads, so a keypress **does not end it**; in another a keypress sets the frame count straight to its maximum, so **a key buys the fade-out rather than an exit**. (c) nothing inside the scene sets a video mode and the harness omitted the call, "so the whole scene ran correctly and invisibly in 80×25 text — **indistinguishable from a hang**".
**Lesson:** **a scene's observable behaviour can be supplied by something absent** (a resident TSR) or by something the harness forgot. `KeyPressed` in a loop says nothing about what it does — trace where the key's effect is *stored* and who reads it. And **"hang" and "running correctly with no visible output" are the same observation.**

### W-72 · Six behaviours misdescribed, each corrected by reading one more thing
**Claimed:** (a) a scene "scrolls upward, lifting the fire off the bottom"; (b) a routine is a caption routine; (c) a routine named for a lemming is a lemming; (d) a scene reads 210 bytes and never uses them; (e) filenames in the binary matter; (f) a scroller is drawn at full resolution and its double step is a slip.
**Disproved by:** (a) two separate motions conflated — heat rises **by construction**, because the neighbour average is written one row *up*, while at the end of the scene the whole picture slides **down** as a wipe-out. The original description "described neither correctly". (b) it is the whole per-member introduction in three phases, not a caption routine. (c) it is a 43×24 **background** animation — which also resolved an unidentified asset block. (d) the 210 bytes **are** the scene's title bitmap, closed arithmetically: the index base plus one row is exactly where they land, and 7 × 30 = 210. (e) one filename is copied into a local and **never looked at again**; another's player ignores its parameter and opens the data file by name. (f) the column counter advances by **two** because the bitmap slides two pixels a frame, so every other column is never written — **"that is the original, not a slip."**
**Lesson:** when two motions coexist, describe each by its own write pattern — a single summary sentence covering both will usually be wrong about both. A routine named for the smallest thing you can see it doing **under-describes** it; read the whole segment before naming. **An "unused read" and an "unsourced table" in the same scene are the same object until proven otherwise.** A string constant is not evidence of a file dependency. And **half-resolution output can be an authored consequence of a step size.**

### W-73 · Inference from output over-modelled a scene
**Claimed:** would naturally be inferred — a 3-D height-mapped mesh.
**Disproved by:** three readings. It is **900 loose pixels — no mesh, no interpolation.** One coordinate is used **twice and differently**, both to pick the source pixel and *as* the 3-D X. And **the height is not applied in three dimensions at all**: one axis goes in as a constant and the pixel value is added to the **projected** coordinate *after* the divide. Only one axis turns.
**Lesson:** flagged in the docs as "two things inference would get wrong". **Output-driven inference over-models** — it invents interpolation, a mesh, and a proper 3-D height where the original has a post-projection offset.

### W-74 · The player's own function numbers, and two units disagreeing
**Claimed:** a named function-number mapping carried in our own source, with the two client units disagreeing about it.
**Disproved by:** the pushed immediates — the mapping is different from the one recorded, and **the unit that had been treated as wrong had it right.**
**Lesson:** when two of your own transcriptions disagree, the binary settles it — and **the loser's names should be deleted, not aliased**, or the wrong name survives in the reader's head.

### W-75 · The two digging skills, and a field that is unused
**Claimed:** two skills the wrong way round in **every earlier document**; and record field `+4` unused.
**Drove it:** naming from plausibility rather than measured motion; and no understood reader for the field.
**Disproved by:** the movement per cycle — one scans the row below and steps diagonally, the other scans a column ahead and never changes Y. That also **flipped the level script**. And `+4` counts **hard landings**: the faller splats only on the *second* landing from height.
**Lesson:** **name a behaviour from its mechanics — the increment, the scan direction — not from what the domain suggests.** A single mislabelling propagates into data interpretation far from where it was made, and **a confident claim repeated across documents is not corroborated; it is copied.** "Unused" is almost always "use not yet found", especially for a counter whose effect shows only on a second occurrence.

### W-76 · A driver is almost certainly the null driver
**Claimed:** 384 bytes for eight routines and a poll that only increments a counter — "almost certainly the null one, **but that is an inference and not yet read**."
**Contradicting evidence recorded at the time:** "its start and stop both call into another unit, which a null driver would not. **Its identity is left open rather than guessed at.**"
**Resolved by:** three-legged hardware identification — "the contradiction noted earlier resolves **the other way from the guess**: it is not a null driver, it is a card that does not need the host."
**Lesson:** the transferable part is the **discipline**: record the contradiction and refuse to name the thing. The corpus does this repeatedly and it keeps paying — including a device the docs still refuse to name, and two routines "almost certainly X and Y by source order, but neither has been reached from a call yet and so neither is written down as fact."

### W-77 · Two globals' homes, and a shadowing non-deviation
**Claimed:** (a) a global is declared in one unit, and unit A `uses` unit B; (b) another unit carries a `uses` entry; (c) 1.31 invented a duplicated variable; (d) a variable has a known address.
**Disproved by:** (a) the owning unit finishes **last**, so the edge is impossible, and a different unit already owns the neighbouring addresses. (b) the named unit finishes *after* the user, and nothing from it is named in the source — **a `uses` entry that references nothing is a real phenomenon**, and it cuts both ways: another unit turned out to **need** two such entries. (c) the release has **the same duplication**, in the same two positions. (d) the address came from a `MOV DI,imm / PUSH CS` — a **code** offset, not a DGROUP address at all, and the real occupant of that address is something else; the entry now records "no measured address".
**Lesson:** a link-order constraint can refute a declaration's home. **Check the release for the *same* duplication before calling it a deviation.** A `uses` clause changes the link and never the code. And on (d): **the rule was already written down in this document and still got missed once** — when a scan turns up a DGROUP address, check which segment register is pushed with it. A *withdrawn* address is not the same as *no* address; re-derive from the arithmetic.

### W-78 · Status prose that its own audit falsified
**Claimed:** in one project's status tables — that three parts have no scene splits and no harnesses, and that a named unit meets the assembler rule.
**Disproved by:** an audit conducted **"by running the tools rather than reading them"**: those parts *do* have splits and harnesses, and the named unit does **not** meet the rule. The deviations file is internally stale too, quoting **two different verification counts in the same section**.
**Lesson:** **status prose decays faster than code.** The measured reality: the marker-based ledger covers 18 of 317 implemented routines (three rows regex artefacts); the byte checker covers 71 routines, 22.4%; **246 routines have no machine-checkable status of any kind.** So a percentage from a marker-based tool measures **marker density, not verification**. *Establish a tool's coverage by running it, not by reading it* — and **prefer numbers a tool prints on every build over numbers a human maintains in prose.** Corollary observed independently: **two documents disagreeing with themselves is itself a measurement.**

### W-79 · Miscellaneous single-fact corrections worth keeping
Each small, each a different instrument:
- **A note called a code region dead**, and it "had to be withdrawn one iteration after being written" — the jump goes **backwards**, so an apparent tautology is a `while` head.
- **An accessor "gets channel N"** — following its callers through shows it is the pattern list, and its twin handles tracks; the record sizes (10 vs 14 bytes) settle it. Plus a one-address correction in the same note.
- **A conditioning routine "handles 16-bit samples, taking the high byte"** — it is a **downsampler**: both bytes are used and **`CBW` appears twice because both are sign-extended** before being added, and the `IDIV` by 2 rather than a shift means it rounds toward zero.
- **A field "not determined by its accessor"** — true of the accessor read alone; closed from the **consumer** side. The same reading corrected two adjacent fields from "sample position" to the **step**, where "the arithmetic is identical either way, which is exactly why reading alone could not separate them."
- **A driver default** — "a machine with both cards ends up on the GUS", concluded from a two-member comparison, **now contradicted twice**: the device ID string and the registration order both say otherwise. *Two independent directions agreeing is the standard for reinstating a claim.*
- **A units-of-measure change** — "this version works in whole periods and the release in quarters", written after **two** routines agreed; the third kept the release's scaling. **Two instances is a pattern and not a rule.**
- **A dispatch arm named by position** — contradicted three ways, and it is a different command entirely; **an arm added last to an existing `case` looks exactly like this.** Position alone is the weakest kind of evidence.
- **A record invented rather than found** — 11-byte records transcribed as a new type with every offset right and every name wrong; they were an **already-declared** type in another unit. **Before inventing a record, grep the tree for its size and offsets.**
- **A leak** — the release clears a flag where this version does not, read as a leak; this version clears it **elsewhere**, when the mixer has finished with the block. "Not the leak it looked like."
- **A one-byte table error** — one entry read 255 where the original and the published standard table both say 254. Findable only once the block existed in the linked image.
- **A record field assumed from its sibling** — one driver's flag inferred from another's default; the two records are **not copies of one default**.
- **A "fine as declared" table** — two tables declared as uninitialised `var`s, so the builder read zeros: **a functional gap the byte comparison could never see.** *Byte-exactness of code is not correctness of the program.*
- **A comment asserting an effect it does not have** — a `var` section moved above a `const` section to move it earlier in memory; the measurement reported identical either way, and the negative result was written into the source.
- **A de-orphaning pass** — deleting a `const`/`var` header whenever the next line is a comment removed **five correct headers**, because a note above a section's first declaration is the normal shape. The clean-up's own inverse is a bug.
- **A known-wrong difference deliberately left open** — our mode-set calls a table builder; the original is **six bytes**, mode set and return. Recorded rather than changed, because "something has to build the row table, and which routine does it in the original has not been established."
# CROSS-APPLICATION — the evidence that these techniques are genuinely transferable

The ticket asks for techniques stated in one project's docs but visibly applicable to the other. That cross-application is the strongest available evidence a technique is general rather than incidental, because the two projects differ in almost every dimension that could matter: **compiler** (TP7 vs TP6), **fidelity target** (behavioural vs byte-exact), **provenance** (own code vs third-party), **completeness** (in progress vs complete), and **available ground truth** (ten sibling binaries vs one binary plus a later source release).

## A. Tooling that physically exists in both trees

The clearest evidence: four analysis scripts appear in **both** repositories, and one is explicitly cross-cited.

| script | role | note |
|---|---|---|
| `unlzexe.py` | LZEXE unpacker | in `psycho/tools/` **and** `VangeliSTracker/tools/` |
| `paslint.py` | pre-build Pascal lint | in both, same trap-ratchet role (P-104) |
| `probe.py` | compiler probe | `psycho/tools/probe.py` and `v1.31b/probe.py` — the DemoVT one is the mature version (P-03) |
| `dosbox/` harness | headless DOSBox build driver | both; `psycho/tools/dosbox/vtbuild.py` builds DemoVT *from the Psycho tree* |

`psycho/tools/` also holds the ancestors of several DemoVT instruments: `rtlfind.py`/`rtlmatch.py` (P-68/P-69), `mzinfo.py`/`segmap.py` (S-01/S-07), `asmverify.py` (P-95, the behavioural-fidelity cousin of `verify.py`), and `symbols.py`/`strings.py` (S-38). **The DemoVT tooling is visibly a second generation of the Psycho tooling**, which is why the blind spots rhyme.

## B. Techniques stated in one project and demonstrably needed in the other

### Stated in DemoVT, applicable to Psycho
- **P-11 the TP7 encoding traps** — the memory note says so outright: *"Relevant to the demo reconstruction too, where hand asm is everywhere; `tools/asmverify.py` would catch it there."* The trap table was measured on DemoVT and the demo is the tree with more hand asm.
- **P-24 read the jump target first** — derived on DemoVT (six statement shapes in one segment) and independently the fix for **three** Psycho part-006 bugs (W-58). Two projects, same technique, arrived at separately.
- **P-03 the compiler probe** — DemoVT's mature form would settle Psycho's `{$S+}`-in-one-part anomaly (W-48) and its `{$G+}` decisions (P-07) the same way it settled six parked claims.
- **P-94 read the `.OBJ`'s FIXUPP records** — DemoVT's strict replacement for the zero heuristic. Psycho's `asmverify.py` masks 1–2 byte displacements *by heuristic* and that masking hid four real bugs (W-58). The OMF-record approach is the fix, and it is already built next door.
- **P-98 a displacement that disagrees is a length** — DemoVT's diagnostic. Psycho's W-19 (a behaviourally-null omission that "shifted every conditional jump below it by four bytes") is exactly the symptom this technique reads.
- **P-40 read a VMT's size word to name a type** — the instrument that overturned `SongColl` (W-13). Psycho has Borland `Objects` in scope (P-71) and no equivalent technique recorded.
- **P-55 prove a refactor byte-neutral by requiring identical fixup counts** — DemoVT's discipline. Psycho has no equivalent, and its deviations ledger is stale in ways this would have caught (W-78).

### Stated in Psycho, applicable to DemoVT
- **S-49 / the INT 2Fh handshake** is the sharpest single case: the protocol was reconstructed from **DemoVT's** resident side and cross-checked against **Psycho's** client side in `psycho/src/DEMOVT.PAS`. One protocol, two binaries, two projects, each validating the other. This is not analogy — it is the same interface read from both ends.
- **P-121 linearise before believing a duplicate** — Psycho's hard-won rule against the disassembler's overlapping segment ranges. DemoVT works in a single binary with 31 segments and the same overlap hazard; its own `V CONTINUATION.md` records the sibling rule (S-19) but arrived at it independently and later.
- **P-76 undo the x87 emulator traps** — Psycho's `fpfix.py` pipeline. DemoVT's `Dos` unit identification (P-71) turns on recognising *"exactly the interrupts Turbo Pascal saves, the 8087 emulator range included"* — the same emulator, and the same range.
- **P-117 A/B against the original executable** — Psycho's ground-truth discipline. DemoVT has no runtime comparison at all; its acceptance test is entirely static, which is a gap the Psycho side names.
- **S-26 factorise the byte count** and **S-30 render raw table data** — Psycho's asset techniques, recurring in 13 and 7 documents. DemoVT reached the same place with S-34 (recover a table's identity from an exact numeric relation) and P-106 (recompute and compare), and both trees independently learned that **an exact match proves the values, not the formula.**
- **P-82 the hand-assembler audit sweep** — Psycho's four-step per-program procedure. DemoVT's equivalent (S-08/S-09) is per-segment and shares the same blind spot: frameless code.

## C. The same blind spot discovered twice, independently

This is the strongest form of evidence in the inventory, because it shows the limit is a property of the *technique* rather than of one project's execution.

| blind spot | in Psycho | in DemoVT |
|---|---|---|
| **A prologue scan misses frameless routines** | P-82's sweep audits "what you wrote, not what exists" | S-09 hid five separate kernels and stubs |
| **A byte check masks exactly the bytes that carry the bug** | `asmverify.py` masks displacements → four branch-target bugs (W-58) | the zero rule excused a stub call and four `DW OFFSET`s (W-35, W-36) |
| **Size or length equality proves nothing** | a dimension pair whose product matches is not evidence (W-21) | "two different routines can be the same length" (P-90) |
| **A tool's status number measures the tool** | ledger covers 18 of 317 routines (W-78) | `verify.py` had five flattering bugs (W-37) |
| **Status prose decays faster than code** | two verification counts in one section (W-78) | superseded tables kept, banner-marked (P-107) |
| **"Nothing references it" is not deadness** | the font block, wrong twice over (W-30) | an unreferenced typed constant is smart-linked away (P-48, P-51) |
| **Plausible output is the failure mode, not the safeguard** | a wrong palette gives a convincing picture (S-31); a plausible image is not a correct image (W-29) | a "convincing nonsense" disassembly at `:0000` (S-11) |
| **Reasoning by analogy across binaries** | part 001 derived from part 002 (W-43) | the release's commented-out lines, four times (W-23) |

## D. Where the two projects genuinely diverge — and why that matters for the catalogue

Several techniques exist **only** because of the fidelity target, and are not transferable as stated:

- **Byte-exactness creates whole technique families** that behavioural fidelity has no use for: the DGROUP layout rules (P-48), segment order as reverse DFS post-order (P-45), link-order constraint checking (P-46), and the entire "which of eight tools can see this" apparatus. Psycho has none of these because it does not need them.
- **Behavioural fidelity creates techniques byte-exactness has no use for**: A/B running the original (P-117), harness tiers (P-116), the deviation ledger with a closing-the-gap field (P-108), and evidence-class markers (P-109). DemoVT has none of these because its acceptance test is a byte comparison.
- **The verbatim-asm rule reverses direction.** In Psycho it is the *primary* rule, asserted by an original author, and justified by four bug classes Pascal-isation invents (P-83). In DemoVT the same rule has a **hard counter-clause**: *"where the binary is plainly compiler output, Pascal is the faithful transcription and inventing assembler would be the deviation."* Psycho's own docs record the identical tension from the other side (P-84: verbatim reproduces instructions but not the frame, and one routine had to stop being verbatim to stop hanging).
- **Two techniques are in direct tension and the corpus knows it.** P-92's zero rule versus P-94's FIXUPP records: the *same* excuse-a-zero heuristic is "exactly right for a `.TPU` and exactly wrong for a TASM module". The correct rule depends on which artefact you are measuring — which is the model table's lesson (a tool's idea of an acceptable difference is part of the measurement) restated as a concrete collision.

## E. The one finding that spans both and is not a technique

Both trees independently converged on the same meta-observation, and it is the most load-bearing single fact for anything built from this inventory:

> **A blind spot recorded only in a retrospective does not prevent the next instance.**

DemoVT: a zero rule was re-implemented wrongly *"within an hour of reading"* the header that records that exact failure twice; the invented-`String`-local trap was made in a **third** unit after being written up twice; a lesson written for one module was inherited as a bug by the next tool, and only *"the lesson made executable"* ended it (P-103). Psycho: the four-plane misreading happened **independently in two different parts** (W-29); the absolute-address bug class recurred **five times in one part** and was only stopped by a lint rule (P-66, W-42); the two digging skills were wrong in **every earlier document**, because *"a confident claim repeated across documents is not corroborated; it is copied"* (W-75).

The corpus's own answer, in both trees, is the same: **state the blind spot at the point of tool use, or enforce it with a tool.** Every blind spot that stopped recurring did so because it became a lint rule, a refusing generator, a search-not-hardcode requirement, or a new instrument — never because it was written down more emphatically.
