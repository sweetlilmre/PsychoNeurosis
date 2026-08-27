# Deliberate deviations from the original

Everything in `src/` aims to be a faithful transcription. This file records the
places where it knowingly is **not**, and why. Anything not listed here is
intended to match the binary; if it does not, that is a bug rather than a
choice.

Each entry says what the original does, what the reconstruction does instead,
and what would have to change to close the gap.

**Some entries are headed NOT a deviation**, and they are the useful ones to
read first. Two kinds end up here: a difference somebody proposed and the
binary refused, and a defect **in the original** that the reconstruction now
faithfully reproduces. The second kind carries the recipe for fixing the bug and
what fixing it would cost, so a real out-of-bounds write does not become
invisible just because reproducing it is the right call today.

---

## Hand assembler is transcribed verbatim — but the frame is not the same

The rule for this project is that hand-written assembler is transcribed
verbatim, commented line by line, with an equivalent-Pascal block above it for
reading. That reproduces the instructions exactly. It does **not** reproduce
the surrounding stack frame: Turbo Pascal decides where locals sit, how much
space a procedure reserves, and what lies immediately above and below.

That distinction is invisible until a routine reads or writes outside its own
storage — see the next entry, which is the only known instance so far, and read
it as a correction to this one rather than as an example of it. **Once every
other byte of a part matches, the frame IS the same**, because the frame is made
by instructions that are themselves being compared. `P3MORPH.FadeStep`
writes three bytes outside its buffer; that hung the scene while part 003 still
differed from the original elsewhere, and stopped hanging when it did not.

So the rule this entry states is true of a part **under reconstruction** and
stops being true of one that has converged. Which means the distinction is worth
keeping for exactly as long as a part still differs, and no longer.

---

## NOT a deviation any more: `P3MORPH.FadeStep` runs off both ends of its buffer, and so do we

**This was the last entry in this file to be retired, on 27 Aug 2026, and it is
kept because the bug is real and somebody may want to fix it one day.** Part 003
now rebuilds byte-for-byte identical to `NEUROSIS.003`, including these two
bytes, and a watched run beside `ORIG3` confirmed it runs and exits cleanly and
looks identical to the original.

### The defect, which is the original's and is now also ours

`1139:0365`. `ENTER $300` reserves a 768-byte palette buffer at `BP-$300`. The
loop is:

```
MOV DI,$300                     ; 768 -- one PAST the last byte
@@: read/dec/write [BP+DI-$300] ; three times, DEC DI after each
    JNS @@                      ; so DI also reaches $FFFF and $FFFE
```

It touches indices **768 down to -2**: 771 bytes, of which only 0..767 are
palette.

* **Index 768 is `[BP]` -- the saved BP itself**, pushed by `ENTER`. The write
  is conditional (`OR AL,AL / JZ`) and *decrements*, so it fires only while that
  byte is non-zero. `LEAVE` is `MOV SP,BP / POP BP`, so it pops BP **from
  `[BP]`** and the decremented byte lands straight back in the register.
* **Indices -1 and -2 are two bytes below the frame**, written on the last pass.

**It is a genuine out-of-bounds write, three bytes of it, once per call.**

### Why it is harmless here, and every clause is measured

* **It self-limits.** The write only fires on a non-zero byte and decrements it,
  so after at most 255 calls the saved BP's low byte is zero and the write stops
  for good. The caller's BP drifts at most 255 bytes downward, not without
  bound. The closing segment makes 63 calls, so in practice the drift is at most
  63 bytes.
* **The caller never uses BP.** `Demo_Scene3` at `1139:03b4` is hand assembler
  end to end: between the `CALL` at `1139:0560` and its `RETF` at `1139:0583`,
  and through the whole region above the call, there is no `ENTER`, no
  `PUSH BP`, no `LEAVE`, and not one BP-relative operand. The register `LEAVE`
  restores is one nothing reads before the next Pascal frame re-establishes it.
* **The two bytes below the frame are dead stack** that nothing reads back.
* **Only `Pal[0..767]` reaches the DAC**, via `SetPalette768`, so the palette
  itself is bit-identical either way.

### Why the earlier attempt hung, which is the interesting part

An earlier pass transcribed `$0300` literally and the scene **faded to black and
hung**. That observation was real and was recorded here as proof the constant
could not be reproduced. It was proof of something else: at that time the rest
of part 003 was **not** byte-identical, so the frame these three writes landed
on was Turbo Pascal's arrangement and not the original's. The note in this file
even said so -- *"the three writes land on Turbo Pascal's frame rather than the
original's"* -- and then drew the conclusion that the constant was the problem.

**The constant was never the problem. The surrounding difference was.** Once
every other byte of the part matched, the three writes landed exactly where the
1994 code puts them and the hang did not come back. Byte-exactness fixed a
behavioural defect, which is the strongest argument for it this project has
produced.

Two claims from the old entry are corrected rather than deleted, because both
were reasoned from and both were wrong: that `LEAVE` "reads BP before popping"
so the corrupted byte is not used (it pops **from** `[BP]`, so it is), and that
an earlier widening of the array to `-2..768` was the only way to give those
writes real storage (it changes `ENTER`, so it cannot be byte-exact by
construction).

### HOW TO FIX THE BUG, IF IT EVER MATTERS

It has not been fixed, deliberately: fidelity is the goal and the write is
provably harmless in this program. Should that ever change -- a different DOS
host, a debugger that guards the frame, an emulator that faults on a write below
SP -- this is the whole change:

```
src/P3MORPH.PAS, in FadeStep's asm block:
    MOV  DI, $0300      ->      MOV  DI, $02FF
```

`$02FF` covers 767..0 in the same 256 passes, stays inside the buffer, and
produces the same palette. **What it costs:**

* **two bytes** of the load image, at `1139:0373`;
* **part 003's byte-identity**, and with it the `[artefact.NEUR3]` row -- so
  `artefact.py --check` would start reporting one failing artefact, which is a
  ratchet falling and has to be an explicit decision, not a side effect;
* and this entry would move back to being a real deviation, above.

**Do not revert it on an argument.** It was reverted once on an argument that
turned out to be wrong in two of its clauses, and it cost a session's worth of
believing the two bytes were unreachable. If it goes back, a watched run says
why.

---

## Shape and object tables are addressed by computed offset, not compiled-in ones

**Original.** Shapes and models are identified by their absolute DGROUP offset:
`P3MORPH` uses `$0636`, `$5136`, `$63F6`; part 002 scene 2's objects sit at
fixed addresses `$5A56`, `$65A7`, `$70F8`, `$7C49`.

**Reconstruction.** The data are Pascal typed constants, which also live in
DGROUP, but the compiler chooses where. `P3MORPH.BindShapes` takes `Ofs()`
of each at startup and the assembler is otherwise untouched; part 002's objects
are ordinary records.

**Why.** The compiled-in offsets cannot be reused verbatim without dictating
the whole data-segment layout.

**Effect on output: none.**

---

## Part 001 scene 4's depth sort works on a global, not a passed-in array

**Original.** `1107:03e7 BuildBlobs(var A)` takes the output array as a `var` parameter -- a far pointer, hence the `LES DI,[BP+4]` at `1107:03eb` -- and hands it to a one-line wrapper at `1107:03d7` whose only statement is `DepthSort(1, 144)`. `DepthSort` (`1107:0287`) is NESTED inside that wrapper, so every one of its element reads goes through the static link: `MOV DI,[BP+4]` then `LES DI,SS:[DI+4]` then `ADD DI,AX` then `MOV AX,ES:[DI-3]`, fourteen bytes to fetch one depth key. It is a Hoare quicksort over 144 seven-byte records, so that happens on the order of a thousand times a frame.

**Reconstruction.** `DepthSort` is a top-level procedure and reads the unit's `Outp` global directly; `BuildBlobs` takes no parameter and the wrapper does not exist.

**Why.** The nesting is only reachable through the parameter, and the parameter is only ever the one global: the wrapper's single call site passes it. Matching the shape would mean declaring the array type 1-based -- the original addresses `A[I]` as `base + I*7 - 3`, so the array it receives starts at index 1 -- while entry 0 of our `Outp` is the translation the transform writes, which would need a typecast to hand over the tail of the array. A cast to force the compiler to emit a slower access path is not a transcription.

**Effect on output: none, but the reconstruction's sort is FASTER than the original's.** It is a per-frame cost, so it belongs on the record of the pacing investigation: this is one of the few places where our code does less work than the binary's, and any pacing comparison for scene 4 should expect it. Found by the coverage walk -- `kit/tools/pascal/spans.py spans.toml 001`, then `tools/shapediff.py`, which is archived under the `archive/pre-kit-scripts` tag -- which lists the span as `1107:0287..039a`.

---

## `{$G+}` is enabled where the assembler needs 286 instructions

The original targets 286 and above — `1139:01d9` is `SHR DI,2`, and a shift by
an immediate other than 1 is a 286 encoding. Units carrying that assembler set
`{$G+}`. This is faithful, not a shortcut, but it is worth knowing the
reconstruction will not run on an 8086. As of 22 Aug 2026 the switch is also
set where the original's *compiled* code proves it — every framed routine in
every original segment opens with `ENTER`, a 286 instruction TP7 emits only
under `$G+` — with the evidence address cited in each unit header. `DETECT`
stays `$G-`: its byte-identical artefact proves that is what the original was.

---

## NOT a deviation: the x87 emulator traps, and the `_fpu` files' provenance

Recorded because a session on 22 Aug 2026 built an elaborate wrong theory
here — that the `work/split/*_fpu.exe` binaries were 1994 release variants
someone had patched to raw x87, making our `$E+` builds a deviation. **They
are not.** The author had no x87 in 1994; the real release is the base
binaries only, carrying TP7's `CD 34..3D` emulator traps exactly as our
builds do, and the `_fpu` files were derived IN THIS PROJECT as disassembly
aids — `docs/02-fpu-emulator.md` documents the trap encoding and how to undo
it, and is the file to read before theorising. At run time Borland's RTL
patches the traps back to real FP opcodes at startup when an FPU is present,
so ours and the originals run identical x87 paths under DOSBox. No
deviation, no speed difference from this mechanism.

One measured detail worth keeping: byte comparisons against the `_fpu`
files show 2-byte `CD 3x` vs `9B Dx` holes at every FPU instruction — that
is the readability patch, not a transcription error. `kit/tools/pascal/spans.py`
compares against the BASE binaries for exactly this reason, and says so in its
own docstring; the `tools/shapediff.py` this paragraph used to name is archived
under `archive/pre-kit-scripts`.

### And the corollary that keeps being missed: no raw x87 opcode is evidence of nothing

**There is not one raw 80x87 opcode in any shipped 1994 binary, and that is not an argument that the demo was built `$N-`.** The maintainer raised exactly that on 24 Aug 2026, and it is the strongest form of the confusion: what is in the file is traps, because `$E+` overwrote every instruction's `WAIT ESC` prefix. `$N-` emits no 80x87 instructions at all, so it leaves **no traps either** — floating point becomes far calls into the software six-byte-`Real` library, and there is nothing for an emulator to emulate. **A trap is therefore positive evidence of `$N+`.** `$N` decides which code is emitted; `$E` decides how it ships; the demo is `$N+` `$E+` and never had a coprocessor.

Settled without anyone having to read a trap correctly, on 24 Aug 2026: P5ROTO was built both ways and every byte of part 005 walked against `bin/NEUROSIS.005`. `$N+` aligns **80.4%**, `$N-` aligns **79.2%** — so `$N-` moves the rebuild 137 bytes *further* from the 1994 file. Had the original been `$N-`, that number would have gone the other way. `kit/wiki/observations/n-and-e-are-different/` carries the general form.

Two figures in the older record are corrected there and in `status.toml`: the motion-table loop body at `1096:051a..0591` carries **12** traps, not 14 — 14 is the count for the whole of `Demo_Scene2`, `1096:03d7..06b7` — and the loop makes **4,002** trig calls, not 3,424, since the counter at `DS:$63ca` is seeded at `1096:050f` and tested against `$7D0` at `1096:0592`, so it turns 2001 times at two calls a turn.

---

## Test harnesses are not part of the demo

`TPxSy` and `TPARTx` (`tools/mktests.py`) exist only to run a scene or a part in
isolation. Where a scene relies on state its neighbours left behind, the harness
has to stand in for the driver, and that is a deviation in the harness rather
than in the scene:

- **`TP3S3`** calls `SetMode13h` after the scene, because scene 3 leaves
  unchained 320x400 and the part's driver — not the scene — resets it at
  `1000:0097`.
- **`TP3S6`** shows the wrong colours run on its own. `P3WAVES` sets no
  palette and neither does the binary: the scene inherits the blue ramp scene 5
  leaves behind. It looks right under `TPART3`.
- **RETIRED, and kept because the fix is the interesting part.** Harnesses used to cost two bytes of DGROUP — `0D 0A` at the end of the initialised region — and those two bytes moved every variable in the part under test, because the uninitialised region begins where the initialised one *ends* rather than where its paragraph padding ends. Worth 752 bytes of the coverage walk on part 003 alone. `Write(s, #13, #10)` did not avoid it; the same two bytes landed at the same address. **BIOS teletype does**: `INT $10` function `$0E` writes a character and touches no runtime, and the string literal lives in the code segment where literals passed to `Write` already live. `tools/mktests.py` generates a `Say` helper that does this, so every harness keeps its prompt *and* leaves the data segment alone. Across the ten parts that was +479 aligned bytes and took the count of parts with byte-identical initialised data from four to seven.
- **Every harness installs an `ExitProc`** that puts the adapter back into
  80x25 text (BIOS mode 3). The scenes and the part drivers are left exactly as
  the binaries have them — several of them do not restore text mode, and each
  part driver ends in `Halt(0)` so nothing written after the call can run. That
  is correct inside the demo chain, where `PSYCHO.EXE` runs the next part, but a
  standalone harness has to hand the machine back usable. Part 002 is the one
  that shows it: it exits in unchained 320x400 with the Miscellaneous Output
  register reprogrammed for 400 lines, and DOS then writes text nobody can read.
  An `ExitProc` is the only hook that catches all three exits — `Halt`, a
  run-time error, and a normal end.

---

## Stack checking is OFF, and it has to be

`tools/dosbox/dosbuild.py` passes `/$S-` to TPC. Turbo Pascal 7 defaults stack
checking ON, and with it on every procedure that has a frame -- **including an
`assembler` one** -- opens with a seven-byte `XOR AX,AX` / `CALLF <check>`
before its first real instruction. The demo was built with it off: its routines
go straight from `PUSH BP` / `MOV BP,SP` into the body.

This was not noticed until `tools/asmverify.py` started diffing whole routines
against the binary, at which point every single transcription differed in its
opening bytes for the same reason. Turning it off dropped about 940 bytes from
each built executable and made 47 routines line up.

---

## Every transcribed assembler routine is byte-checked

`tools/asmverify.py` is the mechanical form of THE RULE. Each routine that is
assembler end to end carries a marker naming where it came from:

    { @asm 004 1005:0328 }
    procedure VLine(...); assembler;

The tool finds that routine in a built harness, walks it against the original
byte for byte to the return, and skips only what cannot match -- one- and
two-byte displacements, since Turbo Pascal put our variables at different
DGROUP offsets. Three or more differing bytes in a row is an opcode change and
fails. Lengths are locked in the tool, so a change that shortens a match is a
regression.

    74 routine(s): 71 locked, 3 not locked, 0 unconfirmed, 0 failing.

A marker may also declare a **fragment** -- `{ @asm 003 11f3:0105 +32 BlockUp }`
-- meaning "compare exactly 32 bytes from here and do not expect a return".
Some of the demo's assembler is inline inside a compiled Pascal routine, so
there is no routine to walk to the end of.

**Nothing is unconfirmed.** The `?` suffix exists for an address that has not
been verified, and no marker currently carries one. The three "not locked"
are `DETECT.PAS`'s probes, matched end to end but not yet in the tool's
frozen `EXPECTED` table -- the committed lock for them is `status.toml`,
where the ratchet holds coverage at 74.

Routines whose Pascal body merely *contains* an `asm` block carry no marker
unless the assembler is declared as a fragment -- there is no whole-routine
comparison to make when most of the routine is compiled code.

### What it found

- **Part 007's four chunk handlers matched end to end on the first pass**, with
  zero displacement holes: `FliCopy` 25 bytes, `FliSS2` 98, `FliLC` 99,
  `FliBrun` 75. Nothing in them touches an absolute address, so there was
  nothing that had to differ -- the transcriptions are the 1994 bytes exactly.
  `RestoreTimer` in the same unit carries no marker: the original opens
  `PUSH BP` / `MOV BP,SP`, and Turbo Pascal gives a procedure with no
  parameters and no locals no frame at all, so the walk has nothing to anchor
  on.

- **`DemoVT.MusicDetect` was missing two instructions.** `1532:0011` clears DL
  and `1532:0023` sets it once the signature has checked out. Nothing reads DL
  and Turbo Pascal returns a Boolean in AL, so the omission changed no
  behaviour -- but it shifted every conditional jump below it by four bytes.
  Now transcribed.

- **`P1LOGO.ScrollLeft` was declared `assembler` and should not have been.** The
  original (`1012:03bd`) opens `PUSH BP` / `MOV BP,SP` and closes `LEAVE`, a
  stack frame it neither needs nor uses -- which is what a plain Pascal
  procedure whose body happens to be one `asm` block compiles to. Declared
  `assembler`, Turbo Pascal drops the frame for a routine with no parameters
  and no locals, so the transcription differed at both ends while being
  identical in between. Now a plain procedure, and it matches.

- **`P3MORPH.TransformPoint` declared two locals that are globals.** The
  original is `ENTER 0006` -- three words, `LX`, `LY`, `LZ`. Ours was
  `ENTER 000A`, because `T1` and `T2` were in the `var` list; `1139:00b8` is
  `MOV [BEAA],DX`, a store to DGROUP, not to a frame slot. Moved to unit
  variables, and the routine now matches for all **293** bytes of it, which is
  its exact length (`1139:0096`..`01bb`).

- **`P1BALLS.SetPalette768` is at `1107:0000`,** not `1107:0446`. Found by
  searching the binary for its own `MOV DX,3C8 / MOV AL,0 / OUT DX,AL /
  INC DX / MOV CX,0300 / REP OUTSB`, which also turned up part 001's VGA copy
  at `1491:01c2` and confirmed that one.

- **Part 003's globe scene had its structure wrong.** `Globe_LoadTables`,
  `Palette_FadeIn` and `Globe_RenderFrame` are all **nested inside
  `Demo_Scene4`** in the original -- each ends `RET 2` and reaches the scene's
  own locals through a static link at `[BP+4]`. `119d:019a` is
  `MOV DI,[BP+4]` / `LES DI,SS:[DI-$0A]`, and `119d:00a9` reads the target
  palette as `SS:[DI+$FCF6]`. Ours had the tables and the palette as unit
  variables, which turned every one of those into a DGROUP read. Now nested,
  and `RenderFrame` matches for all **121** bytes of it, ending on its real
  `LEAVE` / `RET 2`.

  Two smaller things came out of the same routine. `MOV CX,[SI]` /
  `MOV DS,AX` / `MOV SI,CX` / `MOV CX,SrcSeg` had been shortened to
  `MOV SI,[SI]` under a note calling it "one small liberty" -- it is now
  transcribed as written. And the two `Seg()` fetches at the top **have to be
  Pascal, not assembler**: written as `LES DI, SrcOfs` inside an `asm` block
  Turbo Pascal emits `LES DI,[BP-6]`, resolving the enclosing procedure's
  variable against the *nested* procedure's own frame. That compiles cleanly
  and is silently wrong at run time.

- **Part 003's block scene stepped blocks through a procedure that does not
  exist.** Segment `11f3` holds two functions, `Blocks_Run` at `0017` and
  `Demo_Scene5` at `01ac`; both halves of the effect are inline assembler in
  `Blocks_Run`'s loop bodies at `0105` and `0178`, reading `[BP-6]` -- a local
  the Pascal above has just loaded from the order table. They had been split
  into `assembler` procedures taking the offset as a parameter, which made it
  `[BP+4]` and added a prologue and a return. Now inline, and both verify at
  their full 32 bytes.

  Declaration order turned out to matter: behind the 128-byte file record
  `BlockAt` needed `[BP-8E]` and a 16-bit displacement, one byte longer than
  the original's `[BP-6]`, which shifted every instruction after it. The
  scalars are declared first and the file last, as in the original.

- **`VGA.SetMode13h` calls `BuildRowTable` and the original does not.** The
  original is six bytes at `11e3:0000` -- `B8 13 00 CD 10 CB`, mode set and
  return -- with `VirtScrAlloc` starting at `11e3:0006`. Ours sets the mode and
  then calls `BuildRowTable`. This is recorded rather than changed: something
  has to build the row table, and which routine does it in the original has not
  been established.

---

## Part 007 keeps its two video routines in the shared VGA unit

The original part 007 has no VGA unit. Its segment `100b` is a unit of exactly
two routines -- `SetMode13h` at `100b:0000` and `SetTextMode` at `100b:0006` --
and everything else in the part writes straight to `$A000`. Reconstructing a
unit for six instructions was not worth it, so `P7MAIN` takes both from the
shared `VGA` unit. They are the same three instructions each.

## Part 007 is compiled `{$I-}`, and that is not a convenience

`100f:0453` has no `CheckIO` call after any of its `Assign`, `Reset`, `Seek` or
`BlockRead`, so the original unit was compiled with I/O checking off. That
matters, because `100f:054d` seeks a `file` record that was never assigned and
never opened -- a local at `BP-$182`, where every other operation in the
routine uses the global at `DS:$341d`.

It is a bug in the original, and it is invisible: under `{$I-}` the RTL sets
`InOutRes` and returns, the seek does nothing, and reading carries on from the
end of the 128-byte header -- which for this animation is where frame 1 begins
anyway, so the seek was never doing anything useful. It is reproduced as it
stands, with `{$I-}` on the unit. Turn I/O checking back on and the demo dies
there.

## The 386 maths is a TASM object, and it is byte-exact

`src/asm/DEMOMATH.ASM` holds `SinCos`, `RotatePoint` and `Project` -- the three
routines the 3-D scenes share -- plus the 901-entry 16.16 cosine table they
read. It is assembled by TASM and linked into `P1BALLS`, `P1VECTOR` and `P2SOLID` with
`{$L DEMOMATH.OBJ}`, which is what the original does: the same code appears
three times, once per unit's code segment, and all three copies in the two
binaries are byte-identical to each other.

This is **not** a deviation. `.venv/Scripts/python.exe kit/tools/pascal/routines.py` finds each
routine in a freshly built executable and diffs it against the binary it was
read from. (It replaced `tools/asmverify.py`, which is archived under the
`archive/pre-kit-scripts` tag; the two agreed on all 77 rows, and the
`--probe` flag was ported and checked against it.)

```
SinCos       177 bytes, 8 masked displacement(s) -- IDENTICAL
RotatePoint  334 bytes, 12 masked displacement(s) -- IDENTICAL
Project      167 bytes, 4 masked displacement(s) -- IDENTICAL
```

The masked bytes are the only ones that *cannot* match: 16-bit displacements
into DGROUP (the six sin/cos values, the scale, the two view dimensions) and
into the cosine table, because Turbo Pascal chooses where its data lands. Every
other byte, including all the branch displacements, is the original's.

Three things had to be got right for that, and each was caught by the diff
rather than by reading:

- **`USE16` on the segments.** After `.386` TASM defaults to `USE32`, which
  emits 32-bit OMF records; TP7 answers those with "Error 47: Invalid object
  file record".
- **The EXTRNs must sit in a `DATA` segment inside `DGROUP`, with
  `ASSUME DS:DGROUP`.** Declared at the top level instead, TASM assumes they
  live in `CODE` and puts a `CS:` override in front of every reference -- five
  bytes where the original has four, reading the wrong segment.
- **The NOPs in `SinCos` are the original assembler's forward-jump padding**,
  and TASM 4.1 pads in *almost* the same places. Every jump is therefore
  written `short` explicitly and the padding written out as `nop`, so the
  layout is deterministic rather than a function of the assembler's pass count.

## Comparing against the original

The `NEUROSIS.00x` files are plain MZ executables, so each part can be run
directly. `run/` carries a copy of each as `ORIG0.EXE` .. `ORIG9.EXE`
alongside the reconstruction's `TPART1` .. `TPART3`, so the two can be compared
back to back in the same DOSBox session. They need `NEUROSIS.DAT` in the
current directory, which `run/` has.

Findings from that comparison belong here. The first one:

- **The globe in part 003 scene 4 is not horizontally centred in the original
  either.** Not a defect in the reconstruction.

## Tri_Fill's two bridged conditionals, `108b:04b6` and `108b:04ce`

**Two single bytes, and the behaviour is identical.** `TriFill` is transcribed verbatim as a Borland `assembler` procedure and rebuilds 1,250 of its 1,360 bytes identical. Fifty-four of the 56 differing runs are DGROUP addresses, which is the reconstruction's data layout rather than its code. The other two are one byte each, at `108b:04b6` and `108b:04ce`, and they are the same construct in the flat-top and flat-bottom cases:

    original   JGE  <bridge>      ; bridge jumps to the exit
               JMP  <flat walk>
    ours       JL   <bridge>      ; bridge jumps to the flat walk
               JMP  <exit>

A conditional jump can only reach +/-127 bytes, and both targets here are over a thousand away, so the assembler must invert one branch and bridge it with a near `JMP`. Borland's assembler picks the opposite sense to the original's producer. The two forms take the same branch on the same comparison and arrive at the same place; only which of the two destinations gets the short hop differs.

**Not worth fixing.** Matching it exactly means writing an artificial label so the `JGE` is the bridged one, which buys two bytes the coverage walk already forgives -- its default rule excuses isolated runs shorter than three -- at the cost of a construct in the source that exists only to satisfy a byte comparison.
