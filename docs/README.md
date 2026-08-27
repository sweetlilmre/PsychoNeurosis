# Psycho Neurosis — reverse engineering notes

Asphyxia's first megademo, 1994. Borland Pascal 7 + hand-written assembler,
real-mode DOS, VGA.

Goal: understand every effect, then reconstruct the original source.

## Documents

| # | Document | Covers |
|---|---|---|
| 01 | [Binaries and loading](01-binaries-and-loading.md) | What the ten files are, how they fit together, getting them into Ghidra |
| 02 | [The x87 emulator traps](02-fpu-emulator.md) | Why FP code disassembles as `INT 34h`–`3Eh`, and how to undo it |
| 03 | [Borland RTL signatures](03-borland-rtl.md) | Naming the runtime across all parts so library noise stops competing with demo code |
| 04 | [NEUROSIS.DAT](04-neurosis-dat.md) | Recovering the asset map from Seek/BlockRead constants; the tiling proof |
| 05 | [The VGA unit](05-vga-unit.md) | The shared hand-assembler graphics unit |
| 06 | [Part 3, Scene 1 — tunnel](06-part3-scene1-tunnel.md) | Mode-X 640×400, hardware panning, palette cycling |
| 07 | [Part 3, Scene 2 — star tube](07-part3-scene2-stars.md) | Mode 13h, integer 3-D, depth shading |
| 08 | [Part 3, Scene 3 — morph](08-part3-scene3-morph.md) | Mode-X 320×400, fixed-point 3-D, shape morphing |
| 10 | [Part 3, Scene 4 — globe](10-part3-scene4-globe.md) | Precomputed sphere map, scatter blit, cross-fades |
| 11 | [Part 3, Scene 5 — blocks](11-part3-scene5-blocks.md) | Block dissolve by incrementing pixel values against a ramp |
| 12 | [Part 3, Scene 6 — waves](12-part3-scene6-waves.md) | 800 particles on precomputed curves, erase-then-draw |
| 13 | [Part 3, Scene 7 — portraits](13-part3-scene7-sprites.md) | Four spinning 56x56 sprites, incremental rotation |
| 14 | [Part 001 — intro](14-part001-intro.md) | Logo, title, mosaic, 3-D text from ASCII art, vector objects |
| 15 | [Part 002 — house and solid 3-D](15-part002.md) | 1280x200 Mode-X panorama, garage door starfield, depth-sorted solid polygons |
| 16 | [Part 004 — the Lemmings game](16-part004-lemmings.md) | A working Lemmings engine: pixel collision, destructible terrain, 10-state skills |
| 17 | [Part 005 — rotozoomer](17-part005.md) | Segment:offset texture addressing |
| 18 | [Part 006 — credits](18-part006-credits.md) | Line wipes and the 4000-dot whooshtext |
| 19 | [Part 007 — FLIC player](19-part007-flic.md) | Full Autodesk FLIC chunk decoder |
| 20 | [Parts 000 and 009](20-parts000-009-setup-and-end.md) | Setup program that writes NEUROSIS.CFG; end screen — superseded by 30 and 31 where they disagree |
| 09 | [Spotting hand assembler](09-hand-assembler.md) | Telling compiled Pascal from hand-written asm |
| 22 | [Part 002, Scene 2](22-part002-scene2.md) | The solid 3-D object scene, read from the binary |
| 23 | [Deliberate deviations](23-deviations.md) | Everything the reconstruction knowingly does differently, and why |
| 25 | [Part 004 working notes](25-part4-notes.md) | The Lemmings disassembly, block by block |
| 26 | [Part 005 working notes](26-part5-notes.md) | The rotozoomer part, read from the binary |
| 27 | [Part 006 working notes](27-part6-notes.md) | The credits part, read from the binary |
| 28 | [Part 007 working notes](28-part7-notes.md) | The FLIC player, read instruction by instruction |
| 29 | [PSYCHO.EXE charted](29-psycho-launcher.md) | The launcher: three EXECs, an exit-code protocol, byte-identical rebuild |
| 30 | [NEUR9.PAS charted](30-byebye.md) | The end screen, read mostly from its debug info; byte-identical rebuild |
| 31 | [NEUR0.PAS charted](31-startup.md) | Setup: the demo chain is authored here; byte-identical rebuild |

| 32 | [The tool disposition](32-tool-disposition.md) | Where every script goes as the kit absorbs the tooling; generated, and proven to cover the tree |

(24 is deliberately absent: it became the untracked local marker `continuation.md`.)

## Layout

```
bin/      original 1994 files, untouched
src/      reconstructed Pascal
docs/     these notes
assets/   extracted artwork and data (generated -- see assets/README.md)
tools/    extraction and analysis scripts
work/     scratch: split binaries, Ghidra project, site lists (generated)
```

Everything under `assets/` and `work/` is derived and can be rebuilt from
`bin/` with the scripts in `tools/`.

## Reconstruction status

Every part is decoded, with a Pascal reconstruction in `src/`. Remaining gaps
are listed at the foot of the individual documents and are all minor.

| Part | File | Status |
|---|---|---|
| `PSYCHO.EXE` | launcher (`PSYCHO.PAS`) | **byte-identical rebuild** (`TPSYCHO`), guarded in `status.toml` |
| `NEUROSIS.000` | setup (`NEUR0.PAS` + `DETECT`) | **byte-identical rebuild** (`NEUR0`), guarded in `status.toml` |
| `NEUROSIS.001` | intro | reconstructed; observed `differs` at R2 — see the plan |
| `NEUROSIS.002` | house + Enterprise | reconstructed; observed `differs` at R2 — see the plan |
| `NEUROSIS.003` | "Techno Tick" | reconstructed; observed `differs` at R2 — see the plan |
| `NEUROSIS.004` | **Lemmings game** | reconstructed; observed `differs` at R2 (scene tier) |
| `NEUROSIS.005` | terrain / rotozoom / heightmap | reconstructed; observed `differs` at R2 — see the plan |
| `NEUROSIS.006` | credits / whooshtext | reconstructed; observed `differs` at R2, closest match |
| `NEUROSIS.007` | FLIC player | reconstructed; observed **`matches` at R3** |
| `NEUROSIS.008` | DemoVT (third-party) | LZEXE-packed, out of scope — see the `VangeliSTracker` repo |
| `NEUROSIS.009` | end screen (`NEUR9.PAS`) | **byte-identical rebuild** (`NEUR9`), guarded in `status.toml` |

"See the plan" means the `[plan]` section of `status.toml` — five investigations, defect-first, reported by `kit/tools/pascal/plan.py`. Observations and rungs live in `status.toml` too; the register is the authority, this table is a snapshot from 22 Aug 2026.

## Building

[21 — Building the reconstruction](21-building.md): the DOSBox-X + Turbo Pascal
7.01 harness, what compiles today, and the remaining error list.
