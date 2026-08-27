# Building the reconstruction

The reconstruction is written in Pascal but had never been through a compiler,
so "does it build" had never actually been asked. It can be asked now.

## The toolchain

`D:\DOSBox-X\Machine\HDD\TP` is a full **Turbo Pascal 7.01** install — the same
compiler family Asphyxia used. What matters here is `TPC.EXE`, the command-line
compiler, plus `TURBO.TPL` (the standard units) in `BIN\`.

The install's own `BIN\TPC.CFG` contains `/UC:\TP\UNITS`, so **C: must be
mounted as the `HDD` folder**, not as `HDD\TP` — otherwise that path does not
resolve. The config leaves the install untouched.

## Running it

```
.venv/Scripts/python.exe kit/tools/pascal/build.py build.toml --selftest
.venv/Scripts/python.exe kit/tools/pascal/build.py build.toml
.venv/Scripts/python.exe kit/tools/pascal/build.py build.toml P3MORPH
```

**`tools/dosbox/dosbuild.py` and `tools/dosbox/psycho.conf` are gone**, archived under the `archive/pre-kit-scripts` tag by [#36](https://github.com/sweetlilmre/PsychoNeurosis/issues/36), once the kit's tool had been measured to produce all 35 executables byte-identically. `build.toml` at the repository root holds what the script held -- the 8.3 name map, the switch line, what is staged alongside -- and it was generated from it rather than transcribed.

**The DOSBox config is generated per build** into the staging directory, so there is no committed `.conf` to keep in step with anything. That is not tidying: the old one carried this machine's build path and HDD path as literals in a committed file, which the standing rules forbid. Both answers live in the untracked `kit.local.toml` now, and the mount cannot disagree with the staging directory because one value writes both.

The drives it mounts:

| Drive | Host path | Contents |
|---|---|---|
| `C:` | `D:\DOSBox-X\Machine\HDD` | the TP 7.01 install |
| `D:` | `D:\source\psycho\build` | staged sources, output, `BUILD.LOG` |

DOSBox-X runs with `-silent -exit`, so it starts, runs `D:\BUILD.BAT`, and
quits without a window.

### Two things the harness has to work around

**DOSBox-X writes nothing to stdout** — it is a GUI application. So the
compiler's output is redirected to `D:\BUILD.LOG` *inside* the mounted drive
and read back from the host afterwards.

**DOS filenames are 8.3.** `P3SPRITE.PAS` cannot exist, so everything is
staged into `build/` under a short name and the `unit` declarations, `uses`
clauses and `{$I}` directives are rewritten to match:

| Source | Staged | Unit |
|---|---|---|
| `P3SPRITE.PAS` | `P3SPRITE.PAS` | `P3Sprite` |
| `P4LEMS.PAS` | `P4LEMS.PAS` | `P4Lems` |
| … | | |

`build/` is generated and disposable; `src/` stays canonical.

## What builds today

**Everything.** All fifteen units compile with real Turbo Pascal 7.01:

| Unit | Lines | Code | Data |
|---|---:|---:|---:|
| `VGA.PAS` | 399 | 953 | 1,176 |
| `DEMOVT.PAS` | 187 | 346 | 12 |
| `P1INTRO` | 617 | 2,726 | 35,622 |
| `P2GARAGE` | 452 | — | — |
| `P2SOLID` | 1,353 | — | — |
| `P3TUNNEL` | 425 | 1,457 | 2,934 |
| `P3STARS` | 256 | 1,796 | 2,816 |
| `P3MORPH` | 1,753 | 2,098 | 20,110 |
| `P3GLOBE` | 247 | 1,051 | 908 |
| `P3BLOCKS` | 141 | 620 | 13,104 |
| `P3WAVES` | 175 | 886 | 3,206 |
| `P3SPRITE` | 265 | 1,165 | 5,056 |
| `P4LEMS` | 581 | 2,666 | 1,176 |
| `P5ROTO` | 996 | 1,925 | 58,546 |
| `P6CRED` | 1,035 | 2,426 | 36,914 |
| `P7FLIC` | 189 | 904 | 22 |

8,925 lines, 23,126 bytes of code, fifteen `.TPU` files.

The self-test executable is a useful cross-check on the whole chain: `TPC`
produces a genuine MZ whose header reads `SS:SP = xxxx:4000` — **the same stack
pointer as every original NEUROSIS part**, a small confirmation that the
toolchain matches the one used in 1994.

## What "compiles" does and does not mean

It means the source is **valid Pascal that the period compiler accepts**, that
every identifier resolves, and that the transcribed logic type-checks against
the transcribed assembler. It does **not** mean the demo is reproduced — nothing
here has been run.

Every routine is marked so you can tell at a glance what it rests on:

| Marker | Count | Meaning |
|---|---:|---|
| `[transcribed]` | 30 | behaviour read out of the binary, instruction by instruction |
| `[inferred]` | 44 | behaviour established from documented analysis, written plausibly |
| `[stub]` | 26 | named and typed, body not yet written |

**Four routines still have empty bodies**, down from 36:

| Routine | Why |
|---|---|
| `ObjTransformAll` (part 001) | the per-point rotate/project at `12c5:01b0` is FP and emulator-trapped |
| `Setup` / `SetupPeriodic` (part 004) | level setup; not yet decompiled |
| `FrameStart` (part 007) | genuinely does nothing — the decoders write straight to the buffer |

The `[inferred]` count is the number that matters. Those routines do the right
*kind* of thing and will produce plausible output, but they were written from
what the analysis established rather than from the instruction stream, so their
constants and edge cases are not guaranteed.

## What filling the stubs found

**The two digging skills were the wrong way round.** Decompiling both settles it
by how they move: state 4 scans the row below and steps `X += Dir*2, Y += 1` —
**diagonal, a miner**. State 10 scans a vertical column ahead and steps
`X += Dir` with no vertical movement — **horizontal, a basher**. Every earlier
document had them swapped, which also flips the level script: lemmings 3 and 65
are bashers, lemming 5 is a miner.

**Field +4 of the lemming record is not unused.** It counts *hard landings* —
`LemState2_Faller` splats only on the **second** landing from above the splat
height, not the first.

**The faller drifts.** It moves sideways for the first two rows of a fall only,
which is what makes a lemming step off a ledge rather than drop vertically.

**`VGA_FillRect` and `VGA_FillTri` are both misnomers.** Neither draws what its
name suggests: they are one-pixel-thick spans, vertical and horizontal, and both
index the sprite blitter's row table at `DS:$CF8E`.

**The sprite banks are self-documenting.** Every frame stride is exactly `H * W`,
which pins each sprite's dimensions — and shows the walker and faller share one
bank, frames 1–4 facing one way and 5–8 the other, which is why a leftward
lemming indexes `(Frame + 4)`.

**`DrawRevealed` masks by threshold, not by key.** Source bytes of 20 or less
are skipped, so the anti-aliased edges of the glyphs drop out and only the solid
core is copied.

## Notes on specific fixes

- **`{$G+}`** is set where a unit uses `SHR reg, imm`, a 286 encoding rather
  than 8086 -- the part 002 units among them.
- **`FillChar` counts are `Word`**, so clearing 65,536 bytes takes two calls.
- **A 64,000-byte array cannot be global** — DGROUP is 64K, so `PART5`'s source
  image stays on the heap as `Screen^`.
- **`Morph_DrawMorph`'s `goto`** is kept, and its label declared, because it
  mirrors the original's jump to `LAB_1005_1791`.
- **Scene 1 and scene 3 of part 005 disagreed over `X`, `Y`, `Z`** — arrays in
  one, scalars in the other. Split into the grid arrays and `RX`/`RY`/`RZ`.

## Remaining work

The four empty bodies above, and then the real task: **running it**. Everything
to this point is static analysis that now type-checks. A linked executable
compared against the original under DOSBox-X, frame by frame, is the only thing
that will show whether any of it is *correct* — and it is where the 44
`[inferred]` routines will be tested for the first time.

One structural obstacle to note: `GetMem`'s size argument is a `Word`, so no
single allocation can exceed 64K in real mode. Part 004's 202,007 bytes of
assets therefore have to arrive in several blocks, and the reconstruction
currently loads only the first.

## Test harnesses

Two kinds, both generated by `tools/mktests.py` and both installed into `run/`
by `dosbuild.py` as soon as they compile:

| | what it runs |
|---|---|
| `TPxSy` | one scene on its own — part `x`, scene `y` |
| `TPARTx` | the whole of part `x`, through its real driver |

```
TP1S1 .. TP1S5      part 001, five scenes
TP2S1 .. TP2S2      part 002, two scenes
TP3S1 .. TP3S7      part 003, seven scenes
TPART1 TPART2 TPART3
```

A `TPARTx` calls the part's driver — `P1Intro.RunIntro`, `P2Main.RunPart2`,
`P3Main.RunPart3` — each transcribed from that part's main body, so the scene
order, the mode changes between scenes and the music handling are the
original's and not the harness's idea of them. All three drivers end in
`Halt(0)` exactly as the main body does, so nothing after the call runs.

Run them from `run/` (drive `E:` under `interactive.conf`); they need
`NEUROSIS.DAT` in the current directory and say so if it is missing.

Adding a scene is one row in `mktests.py`. `dosbuild.py` picks up anything
matching `src/TP*.PAS` on its own — the names are already 8.3 and the program
identifiers already match, so there is no second table to keep in step.

## Running the original alongside the reconstruction

The `NEUROSIS.00x` files are plain MZ executables — they begin `4D 5A` — so
each part runs directly. `run/` carries a copy of each as `ORIG0.EXE` ..
`ORIG9.EXE`:

```
ORIG1   the intro          against TPART1
ORIG2   the house          against TPART2
ORIG3   Techno Tick        against TPART3
ORIG0   setup, ORIG9 the end screen, ORIG4..8 the remaining parts
```

They read `NEUROSIS.DAT` from the current directory, which `run/` has, and they
degrade gracefully when the music player is not resident. Deviations found by
comparing the two belong in [docs/23](23-deviations.md).
