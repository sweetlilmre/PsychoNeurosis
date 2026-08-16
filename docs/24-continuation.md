# Continuation note

Written at the end of a long session, to pick up cleanly. Read this first,
then `docs/23-deviations.md`.

---

## The rules that now govern this work

**1. Hand-written assembler is transcribed VERBATIM.** Never re-express it as
Pascal. Every such routine carries three things:

1. the assembler itself, instruction for instruction;
2. a comment on **every line** saying what that instruction does;
3. a block comment above holding the **equivalent Pascal**, labelled as
   reference only — plus a note where that Pascal could not actually work
   (register arguments, no signed shift operator, 16- vs 32-bit intermediates).

This came from Peter directly: *"that is THE RULE, it IS NOT THE RULE to change
that into pascal"*. It is also in project memory as `transcribe-asm-verbatim`.

Why it matters, concretely: rewriting `PART3_MORPH`'s inner loops as Pascal
invented four separate bug classes that do not otherwise exist — a lost
register hand-off, `shr` vs arithmetic shift, a 16-bit multiply where the
original used 32, and enough frame cost to show as flicker. All four vanished
when the assembler went back verbatim.

**2. How to tell hand assembler from compiled Pascal.** `ENTER` alone does not
settle it — a TP7 `assembler` procedure with locals still gets a frame, which is
why `Morph_TransformPoint` (`1139:0096`) has `ENTER 6` and is hand-written. The
reliable tells:

| compiled Pascal | hand assembler |
|---|---|
| `ENTER` / `[BP+n]` parameters / `PUSH`-arguments | no frame, or a frame with no `[BP+n]` reads |
| calls through the stack | arguments in registers, results in registers |
| counted loops | `REP MOVSW` / `REP STOSB` / `REP OUTSB` |
| globals via the frame | globals addressed directly, e.g. `[$BEB8]` |

Canonical examples: `Sprites_Prepare` (`125e:0550`) is compiled;
`DrawShape` (`1139:01f9`) is hand-written.

**3. Deviations are recorded.** Anything the reconstruction knowingly does
differently goes in `docs/23-deviations.md` with what the original does, what we
do instead, why, the effect on output, and what would close the gap. Anything
not listed there is meant to match the binary — if it does not, that is a bug.

---

## Where the reconstruction stands

| part | state |
|---|---|
| 001 | five scene units + `P1Intro` driver. Scenes 1–5 all tested and working. **Audit done**, five routines back to verbatim — needs a retest. |
| 002 | `P2S1`, `P2S2`, five shared units, `P2Main` driver. Both scenes tested and working. **Audit done**, twenty-two routines back to verbatim — needs a retest. |
| 003 | seven scene units + `P3Main` driver. **Audit done, and every unit now passes `tools/asmaudit.py`.** S1, S3, S4, S5 confirmed working. S2 and S7 rewritten from the binary and building, neither re-run yet. |
| 004 | `P4VGA`, `P4VT` and `PART4_LEMMINGS`, all transcribed in full — no stubs, nothing inferred. `TP4S1` builds. **Not yet run.** See `docs/25-part4-notes.md`. |
| 005–007 | single files, never run, no harnesses. The remaining stubs, inferred routines and empty bodies live here. |

All 17 harnesses build (`python tools/dosbox/dosbuild.py`).

---

## Outstanding: part 003

### S7 (`TP3S7`) — rewritten from the binary, builds, **not yet run**

`PART3_SPRITES.PAS` was rewritten wholesale. Every routine in segment `125e` has
now been read; nothing in that segment is left inferred. What it does:

`Sprites_Prepare` (`125e:0550`) is the whole per-member introduction, not a
caption routine — three phases:

1. **Fly-in.** `for X := -20 to 70`; spin angle starts at 350, `+5` a frame
   mod 360; `FadeStep` once `X > 0`; Y fixed at 160; position is `X*2`.
2. **Orbit.** `for T := 0 to 180`, so 181 frames of `T*2` degrees = one full
   turn. Radius **60.0** (`CS:$054C`) about (140, 100).
3. **Typewriter.** `Delay(1000)`, then 10 rows x 50 columns, `Delay(10)` a
   character, drawn **straight to `$A000`** at `(Col*6, Row*6)` from
   `Captions[(N-1)*10 + Row][Col]`. Then `Delay(2000)` and `FadeOut`.

`Sprites_Run` (`125e:077c`): `Prepare(1..4)`; four `Random(360)` angles;
`ClearScreen($A000,0)`; 64 x `FadeStep`; then `for Sweep := -20 to 120` drawing
all four longhand. X is fixed at 50/120/190/260, Y is `Sweep*2 + Wobble.Y`.

Everything that was outstanding is now resolved:

- **`125e:0388` `DrawRotated` is hand assembler** — the only one in the unit —
  and is in verbatim with per-line comments and an equivalent-Pascal block. It
  writes a *word* per source pixel to fill the gaps a rotated sample grid
  leaves, swapping the byte order above 180°, and brackets each store with
  `INC SI`/`DEC SI` so the source index still advances by exactly one. Its
  parameters are `(Ang, SinA, CosA, X, Y, Src)`.
- **`125e:0000` `DrawChar(X, Y, S, Segment)`** is compiled Pascal. It uses a
  **5x5 bitmap font at `DS:$DDDE`** with the glyph's row index becoming screen
  X and its column index screen Y — the font is stored transposed.
- **`125e:0406` is `FadeOut`** — 64 passes decrementing every DAC channel,
  with the single retrace wait *outside* both loops.
- **`125e:0510` (and `125e:00d3`) are two identical nested `DegToRad`** copies,
  one in `Prepare` and one in `Load`.
- **`DS:$D29C`** is `Trig[0..359]` = `(Round(sin*64), Round(cos*64))`;
  **`DS:$D83C`** is `Wobble[0..359]` = the same at amplitude **39.6**, read
  225° along. The wobble is built as
  `Round(sin(a)*39.6 + 65535.0) mod 65535` — the bias and modulo are how the
  original gets a signed result out of `Round` without handing it a negative;
  the low word of the LongInt is the answer.

**The 1,550-byte read is NOT dead — it is the font.** 62 glyphs x 25 bytes.
Earlier notes called it dead because the identical block in part 002 is, and
because it contains only 0 and `$AB` — which is exactly a one-bit font stored a
byte per pixel. `DrawChar` reads it at `[DI + $DAB8]` with
`DI = Ord*25 + Row*5 + Col`, which resolves to the same `$DDDE` the
`BlockRead` writes.

Also confirmed: `137b:029f` is `FreeMem` — Scene7 calls it four times with 3136,
Scene6 once with 36414.

**Next:** run `TP3S7` and compare against `ORIG3.EXE`.

### S2 (`TP3S2`) — four defects found and fixed, **not yet re-run**

Two earlier passes called this unit clean. It was not; the checks had been
aimed at the arithmetic and the bug was in the loading.

- **The waypoint table was never loaded.** The `BlockRead` went to a raw
  `Mem[DSeg:$B250]` — where the block sits in the *original's* data segment,
  which has nothing to do with where Turbo Pascal put our array. `Waypoints`
  stayed all zeros, so every `Hold` read as 0, the walk stepped one index a
  frame and ended after fifty, and `PanX`/`PanY` never left 0. Both reported
  symptoms — "does not move around the screen" and "ends sooner" — were this
  one bug. **Any `BlockRead` into a hard-coded `Mem[DSeg:...]` is this bug;
  the rest of the tree is worth grepping for the pattern.**
- **`ProjectAndPlot`'s bounds tests are unsigned** in the binary (`JBE`/`JNC`
  at `10b8:00dd` and `00e4`), not signed. `SX`/`SY` are `Word` now. The
  display-list pass in phase 2 genuinely *is* signed (`JLE`/`JGE` at
  `10b8:035c` on), so the two are not interchangeable.
- **The collapse loop is hand assembler** — `LODSB`/`LODSW`, `LOOP`, the row
  table indexed inline instead of a `PutPixel` call — and had been Pascal-ised.
  Back in verbatim.
- **`Generate` is the unit initialisation section**, not part of `Scene2`:
  `1000:0037` is entry 14 of the init chain and calls `10b8:05f2` directly.

Also worth knowing: `Math_DivLong` (`10b8:07f4`) is `IDIV ESI`, so scene 2
needs a 386 even though nothing else in the part does.

---

## The assembler audit: parts 001, 002 and 003 are done

All three have been swept against their binaries. Parts 004–007 have not.

Part 001 turned up five Pascal-ised routines, part 002 twenty-two, part 003
eleven. `python tools/asmaudit.py` now reports every unit in those three parts
clean; only `PART5_ROTOZOOM` is outstanding, and it has never been checked
against its binary at all.

**The 386 fixed-point maths is done too.** `SinCos`, `RotatePoint` and
`Project` are now `src/asm/DEMOMATH.ASM`, assembled by TASM and linked into
`P1S4`, `P1S5` and `P2S2` with `{$L}` -- which is what the original does. All
three are byte-identical to the binary; `python tools/asmverify.py` proves it
on every build. See `docs/23-deviations.md` for the three TASM settings that
had to be right and why.

That required converting all three scenes from `Real` to 16.16 `LongInt`
throughout -- `TVertex`/`TTrail`, the six sin/cos globals, the scale, the view
dimensions and every vertex load. **None of the three scenes has been re-run
since; they all need retesting.**

TP7's *built-in* assembler stops at the 286 -- `{$G+}` is documented as
"Generate 80286 Code Switch", the shipped help file has no mention of the 386,
and `MOV EAX, EBX` is rejected outright. 386 code comes in through `{$L}` and
`external`, and the binary shows that is what the original did: the `NOP NOP`
padding after forward conditional jumps is an assembler artifact, and
`1107:1A66 ADD EBX,8000h` is a full seven-byte 32-bit-immediate encoding.

**The toolchain now needs TASM** at `C:\TASM\BIN\TASM.EXE` inside the DOSBox
image (`tools/dosbox/dosbuild.py`, `TASM` constant). `dosbuild.py` assembles
every `src/asm/*.ASM` before compiling.

### Which parts used external 386 assembler -- the full sweep

A 386 instruction inside a 16-bit segment cannot have come from TP7's built-in
assembler, so it is an exact marker for `{$L}`-linked TASM. Scanning every
part for the `0x66` operand-size prefix and clustering the hits gives the
whole picture:

| part | user 386 code | state |
|---|---|---|
| 001 | the maths trio TWICE -- `1107:1804/18B6/1A04` (scene 4) and `12C5:192D/19DF/1B2D` (scene 5) -- plus an unreferenced 16.16 divide at `1107:09D0` and `12C5:0AF9` | transcribed |
| 002 | the trio once, `108B:342F/34E1/362F`, plus an unreferenced divide at `108B:25FB` | transcribed |
| 003 | `Math_DivLong` at `10B8:07F4` only -- a plain signed 32-bit `IDIV ESI` | **Pascal `div` in `PART3_STARS`.** Same result, just slower; the RTL helper does the work instead of one instruction |
| 004 | none at all | clean |
| **005** | **the trio once** -- `1102:11D9` SinCos (table at `CS:$03C5`), `1102:128B` RotatePoint, `1102:13D9` Project -- plus helpers at `1102:0391` and `1102:03A5` | **NOT transcribed.** `PART5_ROTOZOOM` computes sin/cos with `Sin()`/`Cos()` at run time and rotates in Pascal |
| 006 | none | clean |
| 007 | none | clean |

Everything else the scan turns up is the Turbo Pascal RTL's own LongInt
multiply and divide helpers -- byte-identical in every part, starting
`80 3E <addr> 02 / 72 1B / 66 C1 E0 10 ...`, which tests the CPU-type byte and
takes a 386 path. Not ours.

Two things worth knowing from this:

- **The unreferenced divide is evidence for `{$L}`.** `1107:09D0`, `12C5:0AF9`
  and `108B:25FB` are the same 16.16 divide and nothing calls any of them.
  TP7 links an object whole, so a PUBLIC nothing uses still lands in the
  executable. It also means the original's `.ASM` exported more than the three
  routines `DEMOMATH.ASM` currently does.
- **Part 005 is the one real gap**, and it is the same object: `1102:128B` is
  byte-for-byte `RotatePoint`. Doing it is mostly declaration changes, but
  part 005 has never been run and still has stubs, so there is nothing to
  check the result against yet.

### Resolved: there was only ever ONE VGA unit and ONE DemoVT unit

Parts 002 and 004 looked like they had their own copies -- `P2VGA`, `P2VT`,
`P4VGA`, `P4VT` -- with different routine sets. They did not. Every part links
the same two source units and **Turbo Pascal's smart linker drops whatever
that part never calls**, which is why the segments differ in size and the
addresses differ everywhere.

The proof is the ORDER: routines come out in source order with the unused ones
simply missing, so the survivors' offsets stay monotonic in all seven parts.
`SetMode13h` is six bytes at offset 0 of the VGA unit in every one of them,
and `DrawLine` sits at `1491:0048` in part 001 but `11e3:009c` in part 004
purely because 004 also links `GetPixel` and `FillRect` ahead of it.

So `FillRect` is not a part 004 peculiarity -- it is in the shared unit, and
parts 004 and 006 are the only two that call it. Their copies are
byte-identical. Likewise `GetPixel` (004, 005, 006) and `PutPixel` (003, 005,
006), which is why part 003's `PutPixel` lands at `12f8:0048`.

The four duplicates are deleted; `VGA.PAS` is now the union of all 21 routines
and `DEMOVT.PAS` of all nine, with the per-part tables in their headers.

**Still conflated:** `VGA.PAS` also carries `SetMode` and `SelectPlane`, which
belong to the MODE-X unit -- segment 1192 in part 003, 107c in part 002 (where
it is `P2ModeX`). The same order argument shows those two are one unit as
well: part 003's `SetMode` is at `1192:002a` and part 002's at `107c:006d`,
the difference being exactly the `ShowFrame` part 003 does not link. Worth
separating next.

### Resolved: the DemoVT function numbers

The old note about the two units disagreeing over dispatch function numbers is
settled. `1532:0040`, `13f9:0040` and `136b:0040` all push **2**; the `004e`
entry pushes **0** and `005c` pushes **1**. So poll is 2, start is 0, stop is
1, and `P2VT` had it right. `DEMOVT.PAS` has been rewritten as a verbatim
transcription of segment 1532 — it is the same unit as `P2VT`, only at
different DGROUP addresses — and its wrong names (`FuncStop = 3`, function 0
called `MusicPoll`) are gone rather than aliased. `P3Main` now calls
`MusicStart` where it used to call `MusicPoll`, and `PART3_TUNNEL` calls
`MusicCue` where it used to call the stubbed `MusicSync`.

`python tools/asmaudit.py` reports which units still fail rules 1.2 and 1.3 —
a comment on every assembler line, and an equivalent-Pascal block above each
routine. It is reporting only and never fails a build. As of now all seven
part 003 units pass; `VGA`, `DemoVT`, all six part 002 units and
`PART5_ROTOZOOM` do not. It cannot check rule 1.1 (that the assembler is
verbatim) — that needs the binary, so a unit passing the script is not the
same as a unit that has been audited.

The method, per program (open it in Ghidra first):

1. `search_instructions` mnemonic `ENTER`, limit 400 — every routine with a
   compiler frame.
2. `search_instructions` for `MOVSB.REP`, `MOVSW.REP`, `STOSB.REP`,
   `STOSW.REP`, `INSB.REP`, `OUTSB.REP` — every string-instruction routine.
   Ignore hits in the RTL segment and the compiler's own String-parameter copy
   at the head of routines taking a `String` by value.
3. Extract every `nnnn:nnnn` cited in that part's sources and check each entry
   point that is not in the `ENTER` set.
4. For each candidate, disassemble and apply the table above.

Known specifics:

- **`VGA.PAS` is clean** — all eight hand-written routines are already
  `assembler`, and `BuildRowTable`, `VirtScrAlloc`, `VirtScrFree` are compiled
  Pascal in the binary too. It does still need the **equivalent-Pascal comment
  blocks** adding to its eight assembler routines, which rule 1 now requires.
- **`PART3_GLOBE.RenderFrame`** and **`PART5_ROTOZOOM.RotozoomFrame`** are the
  only other `assembler` procedures in the tree. `RotozoomFrame` has never been
  checked against its binary.
- Part 002's units (`P2VGA`, `P2ModeX`, `P2View`, `P2Fix`, `P2VT`, `P2S1`,
  `P2S2`) were transcribed as Pascal throughout. `P2View.FillRect`,
  `P2S2.TriFill`, `P2S1.BlitBitmapX`, `P2VGA.CopyScreen`/`ClearSeg` and
  `P2ModeX.SetModeX` are the obvious candidates.

---

## Outstanding: parts 004–007

Never run, no harnesses, and all the remaining debt:

- `PART4_LEMMINGS` — empty bodies: `DrawChar`, `Setup`, `SetupPeriodic`
- `PART7_FLIC` — empty body `ReferenceWork`; `[inferred] PlayFlic` (`100f:0453`)
- `PART5_ROTOZOOM` — `[inferred] SetRotation` (`FUN_1102_02d1`)
(`PART3_SPRITES.Prepare` used to be on this list; it is decoded now.)

Parts 005 and 006 also want splitting into scene units the way 001–003 are; 004
and 007 are single-scene. Add rows to `tools/mktests.py` — `dosbuild.py` picks
up `src/TP*.PAS` automatically.

**`tools/ledger.py` is blind to most of part 003** — those units carry almost no
`[transcribed]`/`[inferred]`/`[stub]` markers, so its percentage never covered
them. Worth adding markers as each routine is verified.

---

## Practical notes

- **Build:** `python tools/dosbox/dosbuild.py [TARGET]`. It runs `paslint.py`
  first and refuses on failure, then installs every `.EXE` into `run/`.
  `build/` is wiped at the start of every invocation — never chain two builds
  and then copy.
- **Run:** `D:\DOSBox-X\dosbox-x.exe -conf tools\dosbox\interactive.conf`, which
  lands on `E:` = `run/`. `D:` is `build/`, `C:` is Turbo Pascal.
- **Compare against the original:** `run/ORIG0.EXE` .. `ORIG9.EXE` are copies of
  `bin/NEUROSIS.00x`, which are plain MZ executables. Use them before assuming a
  visual difference is a defect — the globe in S4 turned out to be off-centre in
  the original too.
- **`paslint.py` earns its keep.** It has caught nested `{ }` comments (TP7 does
  not nest), identifiers shadowing built-ins (`Ofs`, `Offset`, `Mem`, `Port`),
  and empty procedure bodies. It now also rejects `Mem[DSeg:$XXXX]` and
  `Ptr(DSeg, $XXXX)` — a hard-coded address in our OWN data segment, which is
  the bug that cost part 003 scene 2. Add to it when a new class of trap
  appears.
- **Two BASM traps found during the audit.** `SEG` is an operator, so a record
  field called `Seg` is a syntax error inside an `asm` block (hence `Sgmt` in
  `DemoVT`/`P2VT`); and `[SomeConst]` on an untyped const assembles as an
  absolute address, not a variable read, so anything the original reads FROM
  MEMORY has to be a typed constant.
- **`{$G+}`** is needed in any unit whose assembler uses 286 encodings such as
  `SHR reg, imm`.

### Bug classes that have actually bitten, worth checking first

1. **16-bit multiply where the original used 32.** `IMUL` leaves `DX:AX`; a
   Pascal `a * b` with two `Integer`s does not. This was the last S3 bug and the
   hardest to see.
2. **`shr` on a signed value.** TP7's is logical, so negatives become huge
   positives and get clipped away.
3. **`DS` clobbered inside an assembler loop**, then a global read by name. The
   globe's corruption.
4. **Frame layout.** Verbatim assembler reproduces instructions, not the stack
   around them.
5. **A routine reading a table the reconstruction never fills** — S3's row table
   and, separately, its shape offsets pointing at nothing.
6. **Missing loaders.** Part 001 scenes 2 and 3 drew nothing for this reason.
