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
reconstruction will not run on an 8086.

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

---

## Comparing against the original

The `NEUROSIS.00x` files are plain MZ executables, so each part can be run
directly. `run/` carries a copy of each as `ORIG0.EXE` .. `ORIG9.EXE`
alongside the reconstruction's `TPART1` .. `TPART3`, so the two can be compared
back to back in the same DOSBox session. They need `NEUROSIS.DAT` in the
current directory, which `run/` has.

Findings from that comparison belong here. The first one:

- **The globe in part 003 scene 4 is not horizontally centred in the original
  either.** Not a defect in the reconstruction.
