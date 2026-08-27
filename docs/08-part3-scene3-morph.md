# Part 3, Scene 3 — the morphing object

`Demo_Scene3` at `1139:03b4`. Reconstruction: [`src/P3MORPH.PAS`](../src/P3MORPH.PAS).

## What it is

765 3-D points rotating on three axes and morphing between shapes, drawn in
**320×400 Mode-X** with hardware page flipping, faded to black at the end.

The sequence is **sphere → cube → plane → cube → sphere**, in eight scripted
segments of 45 frames (63 for the last).

Fixed-point 16.14 throughout — three rotations then a perspective divide. No
floating point at all.

## Assets

The shape data is **compiled into the executable**, not in NEUROSIS.DAT — which
is why part 003's DAT map has no entry for segment `1139`. It lives in DGROUP in
4800-byte slots (800 points × 6 bytes; 765 drawn).

| File | DGROUP | Extent |
|---|---|---|
| [`assets/part003/SHPSPHER.PNG`](../assets/part003/SHPSPHER.PNG) / `.bin` | `DS:$0636` | X,Y,Z −800…800 |
| [`assets/part003/SHPCUBE.PNG`](../assets/part003/SHPCUBE.PNG) / `.bin` | `DS:$5136` | X,Y,Z −400…400 |
| [`assets/part003/SHPGRID.PNG`](../assets/part003/SHPGRID.PNG) / `.bin` | `DS:$63F6` | X,Z −1000…1000, Y −400…400 |

Rendering the raw vertex data with the recovered constants produces a
recognisable dotted sphere, cube and flat grid. That independently confirms the
record layout (three signed words, X/Y/Z), the base addresses, the 4800-byte
slot spacing, the view distance and the projection scale. The clean symmetric
ranges are a further sanity check.

Slots 1, 2 and 3 exist in DGROUP but are unused by this scene.

## One sine table, two functions

`Morph_SetAngles` reads sin at `DS:$02A8` and cos at `DS:$035C`. The gap is 180
bytes = **90 entries**, because cos(a) = sin(a+90). A single 450-entry table
serves both, and it ends exactly where the shape data begins at `$0636`.

Entries are 16.14 fixed point (×16384).

## The transform

```
rotate about three axes, each product a 32-bit multiply shifted right by 14
D := 2500 - Z'                      { view distance, DS:$BEB4 }
if D >= 0 then
  SX := ((X' - XCentre) * 256) div D
  SY := ((Y' - YCentre) * 256) div D + 200
```

`Morph_TransformPoint` takes X/Y/Z in BX/CX/DX and leaves results in DI/BX for
the plotter — a register convention, so it is hand assembler and the Pascal in
`src/` describes it rather than translating it literally.

## 320×400 Mode-X with page flipping

`VGA_Set400Lines` (`1139:02f2`) clears the low five bits of **CRTC register 9**
(Maximum Scan Line), disabling double-scan and turning the screen into 320×400.

Two 320-wide pages sit **side by side** in the 640-wide logical screen, at byte
offsets 0 and 80 of each 160-byte row:

- `ModeX_ClearPage` wipes 40 words then skips 40 words per row, clearing only
  the back page's half and leaving the visible page untouched.
- `ModeX_FlipPage` writes the current offset to the CRTC start address, then
  toggles `PageOfs := 80 - PageOfs`.

## Constants

| Value | Where | Meaning |
|---|---|---|
| 2500 | `DS:$BEB4` | view distance |
| 256 | `DS:$BEB2` | projection scale |
| 3 | `DS:$BEA2/4/6` | degrees per frame, all three axes |
| 360 | literal | angle wrap (degrees again) |
| 45 | `DS:$BEB6` | morph length in steps |
| 45 / 63 | literals | frames per segment / closing segment |
| `$0E` | literal | dot colour (yellow) |

## The fade

`Morph_FadeStep` reads the whole DAC back, decrements every non-zero component
by one, waits for retrace and writes it out again — a one-step fade toward
black, called once per frame during the closing segment. Both the read and the
write are single `REP OUTSB`/`REP INSB`-style string operations, i.e. hand
assembler.

## The blend is integer, not floating point

`Morph_DrawMorph` (`1139:021d`) transcribed instruction by instruction. There is
**no floating point** in the morph at all — the blend is 16-bit integer linear
interpolation through a 32-bit intermediate (`CWD` before each `IMUL`):

```
P := A + (B - A) * MorphStep div MorphSteps
```

applied to X, Y and Z in turn, over 765 points (`$2FD`), the pointers advancing
two bytes between components and six between points.

The three blended components reach `Morph_TransformPoint` **in registers** — X
in `BX`, Y in `CX`, Z in `DX` — not on the stack. That is a register-convention
call and has to be preserved as assembler in any reconstruction; see
[docs/09](09-hand-assembler.md).

Once `MorphStep` passes `MorphSteps` the routine latches `MorphTo` into
`CurShape` and simply draws the destination shape from then on.

## Open

- Nothing outstanding.
