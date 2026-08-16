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
| 001 | five scene units + `P1Intro` driver. Scenes 1–5 all tested and working. **Assembler audit NOT done.** |
| 002 | `P2S1`, `P2S2`, five shared units, `P2Main` driver. Both scenes tested and working. **Assembler audit NOT done.** |
| 003 | seven scene units + `P3Main` driver. **Audit done.** S1, S3, S4, S5 confirmed working. S7 rewritten from the binary and building, not yet run. S2 unverified. |
| 004–007 | single files, never run, no harnesses. All 17 stubs, 3 inferred and 4 empty bodies live here. |

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

### S2 (`TP3S2`) — "looks too fast, may be correct"

Nothing found wrong. `PART3_STARS` was checked twice and is clean: its point
record declares X and Y as `LongInt` so the `shl 8` is already 32-bit, and `-Z`
is positive by the `ZPlotFar < Z < ZPlotNear` guard above it. Compare against
`ORIG3.EXE` before touching anything.

---

## Outstanding: the assembler audit for every other part

**Only part 003 has been swept.** Parts 001, 002 and 004–007 have not, and
part 003 turned up eleven Pascal-ised routines, so expect more.

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

## One open inconsistency

`DemoVT` and `P2VT` disagree about the tracker's dispatch function numbers.
`P2VT` was read from part 002's `13f9:*` and has start = 0, stop = 1, poll = 2.
`DemoVT` names function 0 `MusicPoll` and declares `FuncStop = 3`. `P3Main`
calls the `136b:004e` slot through `DemoVT`'s name with a comment flagging this.
One of them is wrong; resolve it against the binaries rather than by picking.

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
  and empty procedure bodies. Add to it when a new class of trap appears.
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
