# Deliberate deviations from the original

Everything in `src/` aims to be a faithful transcription. This file records the
places where it knowingly is **not**, and why. Anything not listed here is
intended to match the binary; if it does not, that is a bug rather than a
choice.

Each entry says what the original does, what the reconstruction does instead,
and what would have to change to close the gap.

---

## Hand assembler is transcribed verbatim — but the frame is not the same

The rule for this project is that hand-written assembler is transcribed
verbatim, commented line by line, with an equivalent-Pascal block above it for
reading. That reproduces the instructions exactly. It does **not** reproduce
the surrounding stack frame: Turbo Pascal decides where locals sit, how much
space a procedure reserves, and what lies immediately above and below.

That distinction is invisible until a routine reads or writes outside its own
storage — see the next entry, which is the only known instance so far.

---

## `PART3_MORPH.FadeStep` -- the fade loop runs off both ends of its buffer

**Original** (`1139:0365`). `ENTER $300` reserves a 768-byte palette buffer at
`BP-$300`. The loop then does:

```
MOV DI,$300                     ; 768 -- one PAST the last byte
@@: read/dec/write [BP+DI-$300] ; three times, DEC DI after each
    JNS @@                      ; so DI also takes -1 and -2
```

It touches indices **768 down to -2**: 771 bytes, of which only 0..767 are
palette. Index 768 is `[BP]` -- the saved BP itself. Indices -1 and -2 are dead
stack below the frame. The original survives it because `LEAVE` is
`MOV SP,BP / POP BP`, so it reads BP before popping, and `Demo_Scene3` keeps
nothing in BP.

**Reconstruction.** A plain `for I := 767 downto 0`.

**Effect on output: none, and provable rather than assumed.** Only
`Pal[0..767]` is written to the DAC by `SetPalette768`. The three extra indices
are stack bytes that nothing reads back, so the palette is bit-identical.

**Why not reproduce the overrun.** Transcribing it literally reproduces the
original's *arithmetic* but not its *behaviour*: the three writes land on Turbo
Pascal's frame rather than the original's, and across the closing segment's 63
calls they corrupted something that mattered -- the scene faded to black and
hung. An earlier fix widened the array to `-2..768` so those writes had real
storage; it worked, but left a strange declaration in the source purely to
reproduce side effects that cannot be observed. The bounded loop is simpler and
closer to what the routine is for.

The general point is worth stating once: transcribing assembler verbatim
reproduces the instructions but **not** the stack frame. Turbo Pascal decides
where locals sit and what lies above and below them, which is invisible until a
routine reads or writes outside its own storage.

---

## Shape and object tables are addressed by computed offset, not compiled-in ones

**Original.** Shapes and models are identified by their absolute DGROUP offset:
`PART3_MORPH` uses `$0636`, `$5136`, `$63F6`; part 002 scene 2's objects sit at
fixed addresses `$5A56`, `$65A7`, `$70F8`, `$7C49`.

**Reconstruction.** The data are Pascal typed constants, which also live in
DGROUP, but the compiler chooses where. `PART3_MORPH.BindShapes` takes `Ofs()`
of each at startup and the assembler is otherwise untouched; part 002's objects
are ordinary records.

**Why.** The compiled-in offsets cannot be reused verbatim without dictating
the whole data-segment layout.

**Effect on output: none.**

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

## The x87 code runs through TP7's emulator interrupts; the originals were patched to raw opcodes

**What the original does:** the `_fpu` binaries carry raw `9B`+ESC x87
encodings. Measured on 22 Aug 2026, they are a **post-build patch** of the
base variants: `NEUROSIS_003.exe` and `NEUROSIS_003_fpu.exe` are the same
size and differ exactly by TP7's `CD 34..3D` emulator-interrupt pairs
rewritten in place (`CD 34+n` → `9B D8+n`, `CD 3C 98+n` → `9B 2E D8+n`,
`CD 3D` → `90 9B`).

**What we do instead:** ship the unpatched form TP7 always emits — `$E` only
controls linking the emulator, not the encoding, so every FPU instruction in
a `{$N+}` unit costs an INT/IRET dispatch at run time even with an FPU
present.

**Why:** replicating the patch safely needs the patcher's site knowledge. A
byte-scanning reimplementation was written and validated against all six
original variant pairs, and it FAILED the byte-identity test both ways: the
real tool left alone coincidental `CD 3x` pairs inside ordinary integer code
(`FE CD 3A` at file offset `0x3747` of `NEUROSIS_003.exe` is `DEC CH` + a
`CMP` — patching it corrupts the code) and the emulator RTL's own interior,
and neither class is distinguishable by scanning bytes. The MZ relocation
table does not mark the sites either (checked: 22 of 61 patched runs have a
reloc within two bytes, 39 do not).

**Effect on output:** none on pixels; a bounded per-FPU-op time cost in the
`{$N+}` scenes, largest where trig runs per frame.

**What would close it:** the period patch tool itself, or an exact site list
per executable (e.g. derived by disassembly from each segment's entry), fed
to a patcher that refuses everything else.

---

## Test harnesses are not part of the demo

`TPxSy` and `TPARTx` (`tools/mktests.py`) exist only to run a scene or a part in
isolation. Where a scene relies on state its neighbours left behind, the harness
has to stand in for the driver, and that is a deviation in the harness rather
than in the scene:

- **`TP3S3`** calls `SetMode13h` after the scene, because scene 3 leaves
  unchained 320x400 and the part's driver — not the scene — resets it at
  `1000:0097`.
- **`TP3S6`** shows the wrong colours run on its own. `PART3_WAVES` sets no
  palette and neither does the binary: the scene inherits the blue ramp scene 5
  leaves behind. It looks right under `TPART3`.
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

- **`P1S1.ScrollLeft` was declared `assembler` and should not have been.** The
  original (`1012:03bd`) opens `PUSH BP` / `MOV BP,SP` and closes `LEAVE`, a
  stack frame it neither needs nor uses -- which is what a plain Pascal
  procedure whose body happens to be one `asm` block compiles to. Declared
  `assembler`, Turbo Pascal drops the frame for a routine with no parameters
  and no locals, so the transcription differed at both ends while being
  identical in between. Now a plain procedure, and it matches.

- **`PART3_MORPH.TransformPoint` declared two locals that are globals.** The
  original is `ENTER 0006` -- three words, `LX`, `LY`, `LZ`. Ours was
  `ENTER 000A`, because `T1` and `T2` were in the `var` list; `1139:00b8` is
  `MOV [BEAA],DX`, a store to DGROUP, not to a frame slot. Moved to unit
  variables, and the routine now matches for all **293** bytes of it, which is
  its exact length (`1139:0096`..`01bb`).

- **`P1S4.SetPalette768` is at `1107:0000`,** not `1107:0446`. Found by
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
read. It is assembled by TASM and linked into `P1S4`, `P1S5` and `P2S2` with
`{$L DEMOMATH.OBJ}`, which is what the original does: the same code appears
three times, once per unit's code segment, and all three copies in the two
binaries are byte-identical to each other.

This is **not** a deviation. `python tools/asmverify.py` finds each routine in a
freshly built executable and diffs it against the binary it was read from:

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
