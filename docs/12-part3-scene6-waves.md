# Part 3, Scene 6 — the wave particles

`Demo_Scene6` at `120f:04d0`. Reconstruction: [`src/PART3_WAVES.PAS`](../src/PART3_WAVES.PAS).

## What it is

800 particles tracing precomputed curves, swept across the screen four times
with different parameters each pass.

Curve shapes are not computed at run time. A 36,414-byte table holds **51
curves of 357 X-offsets each**; a particle is just `(curve index, phase, row)`,
and advancing its phase walks it along its curve.

## Assets

| File | Size | Role |
|---|---:|---|
| [`waves_curves.bin`](../assets/part003/waves_curves.bin) | 36,414 | 51 × 357 signed 16-bit X offsets |

51 × 714 = 36,414 exactly, which is what fixes the stride (`$2CA` = 714 bytes
per curve, as used in the indexing).

## The particle record

Four bytes, straight from the DGROUP layout:

```
+0  curve index
+1  phase (word)
+3  screen row
```

## Erase-then-draw

There is no screen clear. Each particle erases its own previous pixel and draws
the new one:

```pascal
OldX := Curve[C, Phase] + SweepX - 1;
Phase := Phase mod 356 + 1;
NewX := Curve[C, Phase] + SweepX;
Mem[$A000 : YOfs[Row] + OldX] := 0;
Mem[$A000 : YOfs[Row] + NewX] := Phase shr 1;
```

With 800 particles that is 1,600 byte writes per frame against 64,000 for a
full clear. Colour is `Phase div 2`, so a particle's colour shifts as it
travels and the motion reads as a gradient.

This scene writes straight to `$A000` with no virtual screen — consistent with
never needing a full-screen operation.

## Four passes

Each pass reseeds the array, spreads the phases so particles are staggered
along their curves, then sweeps `SweepX` from −320 to +320 (640 frames, roughly
9 seconds at 70 Hz — about 36 seconds for the scene).

| Pass | Curve index | Row |
|---|---|---|
| 1 | 30 (all particles on one curve) | `I mod 200` |
| 2 | `(I mod 100) div 2` | `(I*4) mod 200` |
| 3 | `(I mod 100) div 2` | `(I*8) mod 200` |
| 4 | `(I mod 200) div 4` | `(I*8) mod 200` |

The phase spread is done the slow way — a loop advancing one particle's phase
`(i*15) mod 360` times, one step at a time. That is a couple of hundred
thousand iterations, but it only runs four times, between passes.

## Resolved — what the 51 curves look like

They are **absolute X coordinates, not signed offsets** — every value lies in
0..317 and every curve starts at x = 160, the centre of the screen. (An earlier
version of this page called them offsets; that was wrong.)

The 51 curves are **one shape at 51 amplitudes**. Each traces a decaying
oscillation away from centre — out to one side, back, out to the other — and the
peak-to-peak amplitude grows strictly monotonically with the index:

| Curve | Amplitude |
|---:|---:|
| 0 | 0 — a dead straight vertical line |
| 1 | 6 |
| 15 | 95 |
| 30 | 190 |
| 50 | 317 — the full width of the screen |

So the curve index is effectively an **amplitude dial**, which is exactly why
the passes work as they do: pass 0 puts every particle on curve 30 so they all
trace the same mid-amplitude wave, and the later passes spread the indices to
fan the particles into a family of nested waves.

![all 51 curves overlaid](../assets/part003/waves_curves_all.png)

*All 51 overlaid — [`waves_curves_all.png`](../assets/part003/waves_curves_all.png).*

## Open

- Nothing outstanding.
