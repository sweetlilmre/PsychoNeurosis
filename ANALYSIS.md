# Psycho Neurosis — analysis

The detailed write-ups now live in **[`docs/`](docs/README.md)**.

| Document | Covers |
|---|---|
| [Binaries and loading](docs/01-binaries-and-loading.md) | What the ten files are, how they fit together, getting them into Ghidra |
| [The x87 emulator traps](docs/02-fpu-emulator.md) | Why FP code disassembles as `INT 34h`–`3Eh`, and how to undo it |
| [Borland RTL signatures](docs/03-borland-rtl.md) | Naming the runtime across all parts |
| [NEUROSIS.DAT](docs/04-neurosis-dat.md) | Recovering the asset map; the tiling proof |
| [The VGA unit](docs/05-vga-unit.md) | The shared hand-assembler graphics unit |
| [Part 3 Scene 1 — tunnel](docs/06-part3-scene1-tunnel.md) | Mode-X 640×400, hardware panning, palette cycling |
| [Part 3 Scene 2 — star tube](docs/07-part3-scene2-stars.md) | Mode 13h, integer 3-D, depth shading |
| [Part 3 Scene 3 — morph](docs/08-part3-scene3-morph.md) | Mode-X 320×400, fixed-point 3-D, morphing |
| [Part 3 Scene 4 — globe](docs/10-part3-scene4-globe.md) | Precomputed sphere map, scatter blit, cross-fades |
| [Part 3 Scene 5 — blocks](docs/11-part3-scene5-blocks.md) | Block dissolve by incrementing pixel values against a ramp |
| [Part 3 Scene 6 — waves](docs/12-part3-scene6-waves.md) | 800 particles on precomputed curves, erase-then-draw |
| [Part 3 Scene 7 — portraits](docs/13-part3-scene7-sprites.md) | Four spinning 56x56 sprites, incremental rotation |
| [Part 001 — intro](docs/14-part001-intro.md) | Logo, title, mosaic, 3-D text from ASCII art, vector objects |
| [Part 002 — house and solid 3-D](docs/15-part002.md) | 1280x200 Mode-X panorama, garage door starfield, depth-sorted solid polygons |
| [Part 004 — the Lemmings game](docs/16-part004-lemmings.md) | A working Lemmings engine |
| [Part 005 — rotozoomer](docs/17-part005.md) | Segment:offset texture addressing |
| [Part 006 — credits](docs/18-part006-credits.md) | Line wipes and the 4000-dot whooshtext |
| [Part 007 — FLIC player](docs/19-part007-flic.md) | Full Autodesk FLIC chunk decoder |
| [Parts 000 and 009](docs/20-parts000-009-setup-and-end.md) | Setup program; end screen |
| [Spotting hand assembler](docs/09-hand-assembler.md) | Telling compiled Pascal from hand-written asm |

Extracted artwork and data: **[`assets/README.md`](assets/README.md)**.

Reconstructed Pascal: **[`src/`](src/)**.

## Rebuilding everything from `bin/`

```sh
.venv/Scripts/python.exe kit/tools/substrate/split.py -o work/split bin/PSYCHO.EXE bin/NEUROSIS.00*
python tools/build_assets.py
```

Ghidra import and the FP fixup are described in
[docs/01](docs/01-binaries-and-loading.md) and
[docs/02](docs/02-fpu-emulator.md).

## Tools

**Almost all of them are the kit's now**, and `kit/WORKING.md` section 3 groups
all 47 by the question you have -- which is the useful way in, and the reason
this file no longer lists them. `docs/32-tool-disposition.md` says where each of
the 49 archived scripts went and what measurement justified deleting it.

What stayed here is this demo's own, and it stayed because it would have to be
rewritten for a different binary:

| script | purpose |
|---|---|
| `tools/datmap.py` | `NEUROSIS.DAT`'s region map, and the tiling proof |
| `tools/datcarve.py` | the low-level carve and PNG writer that map feeds |
| `tools/build_assets.py` | build the `assets/` tree from the map and from DGROUP |
| `tools/mktests.py` | generate this demo's per-scene and per-part harnesses |
| `tools/emit_pascal_data2.py` | the remaining compiled-in data for parts 001, 002, 005, 006 and part 003's captions |
| `tools/fpround.sh` | one convergence round of the FP fixup |
| `tools/dosbox/vtbuild.py` | compile the 1.39b release tree; declined, because the tree is held out of source control and it cannot be exercised |
| `tools/ghidra/*.java` | seven Ghidra scripts: name the RTL from a table, recover the `Seek`/`BlockRead` constants, restore `CS:` on recovered x87 operands, list surviving traps, and the layout and FP reports |

The ones a session reaches for most, in the kit:

| question | tool |
|---|---|
| build it | `kit/tools/pascal/build.py build.toml` |
| which bytes do NOT line up? | `kit/tools/pascal/spans.py spans.toml 001` |
| does each declared routine match? | `kit/tools/pascal/routines.py` |
| is our whole build the original's bytes? | `kit/tools/pascal/artefact.py --check` |
| what is the next piece of work? | `kit/tools/pascal/plan.py --report` |

## Compiled-in data

Anything in DGROUP's *initialised* region was a typed constant in the original
source — plain `var` lands in BSS and is not stored in the executable at all. So
data readable out of the file image must have carried an initialiser, and the
reconstruction is not faithful without it.

DGROUP is always the highest segment in the relocation map: part 001 `$18F8`,
002 `$1866`, 003 `$1761`, 004 `$1373`, 005 `$166C`, 006 `$164E`.

| Include | Contents | Values |
|---|---|---:|
| `src/gen/P1VECT.INC` | part 001's two vector objects — the circled "A" and the wireframe globe | 252 |
| `src/gen/P2OBJ.INC` | part 002's four models — Enterprise, revolver, sailboat, quad — vertices and face streams | 1,363 |
| `src/gen/P3PAL.INC` | part 003's tunnel palette, three 225-byte channel tables | 675 |
| `src/gen/P3SINE.INC` | part 003's 450-entry sine table, 16.14 fixed point | 450 |
| `src/gen/P3SHAPE.INC` | part 003's three morph shapes, 765 points each | 6,885 |
| `src/gen/P3CAPT.INC` | part 003's 40 member-caption lines | 40 |
| `src/gen/P5MESH.INC` | part 005's 1,922-triangle mesh over a 32×32 grid | 5,766 |
| `src/gen/P6TEXT.INC` | part 006's 99 credit lines | 99 |
| `src/gen/P6CELL.INC` | part 006's whoosh board — "ASPHYXIA RULZ", plus the unused "0,000 DOTS" | 3,328 |

Part 004 has almost no initialised DGROUP (384 bytes); its two terrain colour
sets are 32-byte constants in the **code** segment, reached with a `CS:`
override — see [docs/16](docs/16-part004-lemmings.md).

## Building it

`docs/21-building.md`. There is a working Turbo Pascal 7.01 toolchain now:

```
.venv/Scripts/python.exe kit/tools/pascal/build.py build.toml --selftest
.venv/Scripts/python.exe kit/tools/pascal/build.py build.toml
```

**All fifteen units compile.** That means valid Pascal the period compiler
accepts, not a working demo. Routines are marked `[transcribed]` (30, read out
of the binary), `[inferred]` (44, written from established analysis) or `[stub]`
(26). Four bodies are still empty. Nothing has been run.
