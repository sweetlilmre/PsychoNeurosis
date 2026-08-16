# Part 3, Scene 1 — the tunnel

`Demo_Scene1` at `1015:098d`. Reconstruction: [`src/PART3_TUNNEL.PAS`](../src/PART3_TUNNEL.PAS).

## What it actually is

A **640×400 tunnel image, precomputed and stored as four Mode-X planes** in
NEUROSIS.DAT at `$081A76`. It is loaded once, straight into VGA memory. There is
**no per-frame pixel work at all**.

The motion comes entirely from two things:

1. **Hardware panning** — the visible 320×200 window walks a circular path
   around the 640×400 image, using the CRTC start address for 4-pixel steps plus
   Attribute Controller register `$13` for the sub-pixel remainder.
2. **Palette animation** — 225 colours arranged as 15 bands of 15, rotated both
   *within* each band and *by whole bands* every frame, making the rings flow.

That is why the source artwork looks like static concentric rings.

## Assets

| File | Role |
|---|---|
| [`assets/part003/tunnel_plane0.raw`](../assets/part003/tunnel_plane0.raw) … `plane3.raw` | the four 64,000-byte Mode-X planes, as loaded |
| [`assets/part003/tunnel_palette.pal`](../assets/part003/tunnel_palette.pal) | 768-byte DAC image rebuilt from the three embedded tables |
| [`assets/part003/tunnel_640x400.png`](../assets/part003/tunnel_640x400.png) | de-interleaved composite in its real colours |

## Where the palette lives

**Compiled into the executable**, not in NEUROSIS.DAT. Borland keeps the
channels as three separate tables rather than interleaved triples:

| Table | Address | Size |
|---|---|---|
| Red | `DS:$0002` | 225 bytes |
| Green | `DS:$00E3` | 225 bytes |
| Blue | `DS:$01C4` | 225 bytes |

They are contiguous (`$0002 + 225 = $00E3`, and so on) and run straight into the
sine table at `$02A8`. `Tunnel_UploadPalette` writes them to DAC indices 1–225.

The ramp is symmetric across the 15 bands — peak red climbs 0 → 16 → 24 → 34 →
51, holds through the middle bands, then falls back — and **every band has black
at both ends**, which is what draws the dark grid lines between tiles.

Rendering the texture with these values instead of a neutral ramp reveals what
it actually is: a **red tiled tunnel with the letter "A" repeated across the
walls** — Asphyxia's initial. With a grayscale ramp the glyphs are invisible.
Worth remembering for the other parts: a carved screen is not really decoded
until it has been paired with its true palette.

## How we know it is 640×400

The carved chunks first appeared as four 320×200 images each with *two* ring
centres. They are not four images: `VGA_SelectPlane` writes Sequencer register 2
(Map Mask), so they are the four **planes** of one image. De-interleaved at
640×400 they resolve to a single centred tunnel — the twin centres were a stride
artefact.

Five independent confirmations:

| Evidence | Implies |
|---|---|
| CRTC Offset register := 80 | logical width 80×8 = **640** |
| 64,000 bytes/plane ÷ 160 bytes/plane-line | **400** lines |
| `PlaneOf[]` table built for 640 entries | width 640 |
| De-interleaved image has one centre | layout correct |
| Initial radius = exactly **100.0** | = (400−200)÷2, the largest in-bounds circle |

## The motion

Constants live in the **code segment** (`CS:`), not DGROUP — Borland parks FP
literals beside the procedures that use them:

| Address | Type | Value | Meaning |
|---|---|---|---|
| `CS:$0744` | Single | 1.0 | radius floor |
| `CS:$0748` | Extended | 0.1 | radius decay per frame |
| `CS:$0752` | Single | 3.0 | angle step per frame |
| `CS:$0756` | Single | 360.0 | angle wrap |
| `CS:$06FA` | Extended | π | degrees→radians helper |
| `CS:$0989` | Single | 1.0 | loop-exit threshold |

The 360 wrap plus the π multiply prove the **angle is held in degrees**.

```pascal
PanX := Round(Radius * Cos(Angle * Pi / 180)) + 160;
PanY := Round(Radius * Sin(Angle * Pi / 180)) + 100;
if Radius > 1.0 then Radius := Radius - 0.1;
Angle := Angle + 3.0;
if Angle > 360.0 then Angle := Angle - 360.0;
```

3°/frame is a full revolution every 120 frames; the radius decays 100 → 1 over
990 frames. So the window performs a **spiral-in of about eight revolutions**.

The scene ends when the spiral reaches the centre — the loop tail is
`FCOMP float ptr CS:[0989]` (= 1.0) then `JNC` back, i.e. **while Radius >= 1.0**.
It is self-timed, not music-gated; the DemoVT call each frame only advances the
music position.

## Frame loop

```pascal
repeat
  MusicPoll;            { DemoVT 136b:0040 }
  RotateBandsFine;      { each 15-colour band left by one }
  RotateBandsCoarse;    { whole 225 right by one band }
  WaitRetrace;          { the DAC write must not tear }
  UploadPalette;        { 225 colours from three separate R/G/B tables }
  UpdateMotion;
until Radius < 1.0;
```

R, G and B live in **three separate 225-byte tables** at `DS:$0002`, `$00E3` and
`$01C4` — back to back, not interleaved triples. This appears to be a house
convention; watch for it in the other parts.
