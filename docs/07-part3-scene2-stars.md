# Part 3, Scene 2 — the star tube

`Demo_Scene2` at `10b8:0592`. Reconstruction: [`src/PART3_STARS.PAS`](../src/PART3_STARS.PAS).

## What it is

500 points on a circle of radius 40, spread evenly in depth from Z=−1 to −500,
flying toward the viewer — a **star tube**. Perspective-divided onto a mode 13h
software screen, depth-shaded, panned by a waypoint script, and ending with
every point collapsing into the centre.

Note the contrast with Scene 1: plain mode 13h with a virtual screen, versus
Mode-X with hardware panning. The two scenes share only the VGA unit.

## Assets

| File | Role |
|---|---|
| [`assets/part003/stars_waypoints.bin`](../assets/part003/stars_waypoints.bin) | 3,000 bytes from `$0C0276` — 6-byte waypoint records |

**The point cloud is not an asset.** It is generated procedurally at startup;
only the camera waypoints come from the blob.

## The generator

Floating point is used exactly once, here:

```pascal
A := Random(360) * Pi / 180;
X := Round(Cos(A) * 40);      { RTL_Cos 137b:3257 -> record +0 }
Y := Round(Sin(A) * 40);      { RTL_Sin 137b:3252 -> record +4 }
Z := -I;                      { I = 1..500 }
```

A point that rounds to dead centre is rejected and re-rolled, otherwise it would
sit on the vanishing point forever.

This is also where the Sin/Cos identification was settled by direct observation —
the two `CALLF` targets are visible in the disassembly, and X takes `3257`
while Y takes `3252`.

## The render

Pure integer, no FP:

```pascal
SX := XOfs + ((X shl 8) div Z);
SY := YOfs + ((Y shl 8) div Z);
if in bounds then PutPixel(SX, SY, ((-Z) shr 6) + 1);
```

- `shl 8` is `RTL_Shl32` (`137b:36f2`), a 32-bit `DX:AX shl CX` that branches on
  CPU type — a loop on 8086, a single shift on 386.
- The divide is `Math_DivLong` (`10b8:07f4`), a 32-bit long division.
- Depth shading falls straight out of Z: `colour := (-Z shr 6) + 1`, against a
  13-step blue ramp where colour 1 is brightest and 13 is black.

Points that pass the viewer (`Z > -10`) are pushed back 500 and re-seeded from
an untouched `Source` template, which is what makes the tube endless.

## Structure

| Phase | What happens |
|---|---|
| 1 | Fly the tube, stepping backwards through a 50-entry waypoint table; each entry holds a pan offset and a dwell time in frames |
| 2 | Freeze every still-visible point into a 5-byte display list |
| 3 | Over 32 frames (`DS:$02A6`), lerp every listed point toward (160,100) |

Phase 3 reads on screen as the whole field imploding to a dot.

## Constants

| Value | Where | Meaning |
|---|---|---|
| 40.0 | `CS:$05EE`, Single | tube radius |
| shl 8 | `CX=8` into `RTL_Shl32` | projection scale (×256) |
| 32 | `DS:$02A6` | collapse frames |
| −1 … −500 | computed | Z is minus the point index |

## Resolved — the unwalked tail

The block is declared as 500 six-byte records, but only **56 are non-zero**.
Records 1..57 hold real `(PanX, PanY, Hold)` data; from record 58 to 500 every
byte is zero.

The scene walks indices 50 down to 1, so records 51..57 are authored data that
is never reached and the remaining 443 are padding. The array was declared at a
round 500 and filled as far as the choreography needed — not a second consumer,
just a generous bound.

## Open

- Nothing outstanding.
