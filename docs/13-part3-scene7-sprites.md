# Part 3, Scene 7 — the spinning portraits

`Demo_Scene7` at `125e:0958`. Reconstruction: [`src/PART3_SPRITES.PAS`](../src/PART3_SPRITES.PAS).

The closing scene of the part.

## What it is

Four 56×56 face portraits, each spinning at 5 degrees per frame, stacked 70
pixels apart vertically and swept across the screen together.

## Assets

From `$11EEC0`, 14,862 bytes in six reads:

| File | Size | Role |
|---|---:|---|
| [`font_5x5.bin`](../assets/part003/font_5x5.bin) | 1,550 | the 5 x 5 bitmap font -- byte-identical to `part002/font_5x5.bin`; see docs/15 |
| [`sprite1.png`](../assets/part003/sprite1.png) … `sprite4.png` | 3,136 each | 56×56 portraits |
| [`sprites_palette.pal`](../assets/part003/sprites_palette.pal) | 768 | |

The four 3,136-byte reads sit in a 4-iteration loop in the original.
**3136 = 56×56** is what fixes the dimensions, and rendering at that size shows
four faces — almost certainly the four Asphyxia members named in `PSYCHO.NFO`
(EzE, GoTH, Denthor, Fubar), though that identification is context, not proof.

## The rotation

A straight incremental 2-D rotate-and-sample, in 6-bit fixed point, with no
multiplies inside the loop: step `(cos, sin)` along each output row and
`(sin, -cos)` down each column, reading the source at the rotated coordinate.

The destination address is written as `(U shr 6) + (V and $FFC0) * 5`, which is
just `(V shr 6) * 320 + (U shr 6)` — since `(V and not 63) * 5 = (V shr 6) * 320`.

Above angle `$B5` the two source bytes are written swapped; that is the
odd/even alignment case for the word store.

## Motion

- Each portrait gets a **random** starting angle, so the four are never in
  phase even though they spin at the same rate.
- The sweep runs 140 frames (−20 to 120) and X is `SweepX * 2`, so the group
  travels 280 pixels — entering off-screen left, leaving right.
- Each position also has a sin/cos term added, so they weave as they travel
  rather than moving in a straight line.
- Double-buffered through the virtual screen, unlike Scene 6.

## Sprites_Prepare — the introductions

`125e:0550` runs once per portrait, in three phases:

1. **Fly-in** — 90 frames, the sprite spinning 5 degrees per frame while its X
   sweeps in from off-screen.
2. **Orbit** — 180 frames, position taken from `Sin`/`Cos` of twice the frame
   counter, offset by (100, 140).
3. **Caption** — 10 lines of 50 characters drawn beside the portrait at 6-pixel
   spacing, one character every 10 ms.

### The captions are compiled into the executable

At `DS:$6BB8 + n * $A00`, 10 lines of 256 bytes each. They identify the four
faces outright:

| Sprite | Subject | Codename | Occupation | Tasks | |
|---|---|---|---|---|---|
| 1 | PETER EDWARDS | EZE | STUDENT | CODE, MUSIC | *THE WIERD ONE* |
| 2 | GRANT SMITH | DENTHOR | STUDENT | CODE | *THE TALL ONE* |
| 3 | BRIAN BAILEY | GOTH | STUDENT | CODE | *THE BITCHY ONE* |
| 4 | PIETER BUYS | FUBAR | STUDENT | ART | *THE UNFORGIVEN ONE (BECAUSE OF EXAMS...)* |

Which confirms the four 56x56 portraits are the four members, and matches the
names in `PSYCHO.NFO`.


## The captions

`Sprites_Prepare` (`125e:0550`) draws a caption beside each portrait. The text is
a typed constant in DGROUP at `DS:$76B8`, `array[1..40] of String`, stride `$100`
— **ten 50-character lines per member**, in portrait order. Emitted as
[`src/gen/P3CAPT.INC`](../src/gen/P3CAPT.INC).

| Subject | Codename | Occupation | Tasks | Tagline |
|---|---|---|---|---|
| PETER EDWARDS | EZE | STUDENT | CODE, MUSIC | THE WIERD ONE |
| GRANT SMITH | DENTHOR | STUDENT | CODE | THE TALL ONE |
| BRIAN BAILEY | GOTH | STUDENT | CODE | THE BITCHY ONE |
| PIETER BUYS | FUBAR | STUDENT | ART | THE UNFORGIVEN ONE (BECAUSE OF EXAMS...) |

This settles the identification of the four faces — they are the four members,
named in the executable, matching `PSYCHO.NFO`.

## The fade

`Sprites_FadeStep` (`125e:047a`) is a one-step fade **in**. It waits for retrace,
then for all 256 entries reads the current RGB back from the DAC and increments
each channel by one if it is still below the target held at `DS:$E3EC`. Called
64 times, so the palette walks up from black over 64 frames.

## The dead 1,550-byte block

The 1,550 bytes read at the start of the region are **dead, provably**: the same
1,550 bytes appear byte-identically in part 002 (DAT `$080CB2`, loaded to
`DS:$5448`), the block contains only the values 0 and `$AB`, and in both parts
the only instruction that mentions the destination buffer is the `BlockRead`.
Nothing consumes it in either place — the read simply walks the file pointer
This was wrong. The block is the 5 x 5 bitmap font, indexed off a base
806 bytes below where it is loaded, which is why nothing appears to
reference the destination buffer. See
[`assets/part002/font_5x5.bin`](../assets/part002/font_5x5.bin) and the
worked explanation in [docs/15](15-part002.md).

## Open

- Nothing outstanding.
