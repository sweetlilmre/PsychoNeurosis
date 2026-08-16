# Part 006 — the credits

`NEUROSIS.006`, MOD *LaTeX LoVeR*. 147 functions, four scenes.

This is the greetings and dedications part. The text is in the binary as
12-character lines at 256-byte spacing:

```
MY WORK IN / THIS DEMO IS / DEDICATED TO / $ADELE$ / MY LADYMOTH / - EZE
GREETS FROM / EZE / GO TO :- / SPLIT / NEMESIS / CAZ / SCHMUCK ...
```

and the scene announces itself:

> `ISNT'T THIS GREAT?     ,THIS WHOOSHTEXT HAS 4000 DOTS!!!`

## Scene 1 — line wipe

`Scene1_LineWipe` (`1095:0578`) draws three sweeps of lines: sixteen lines
fanning from the bottom-left, then 63 lines converging, then 63 diverging.
Straight vector wipes, no bitmap.

## Scene 2 — the whooshtext

`Whoosh_Run` (`100f:0590`), `Whoosh_Load` (`100f:03f8`),
`Whoosh_BuildPaths` (`100f:0173`).

> `ISNT'T THIS GREAT?     ,THIS WHOOSHTEXT HAS 4000 DOTS!!!`

The text is a **board of cells**, not a bitmap of characters. Each cell is drawn
as a 25×25 animated sprite, and the whole board rotates.

### The board

`Whoosh_Load` allocates a 170 × 16 byte board (`$AA0`) and fills every cell with
**2** — the background dot. It then overlays rows 39..166 from a typed constant
in DGROUP at `DS:$000A`, `array[1..26, 1..16, 1..8] of Byte`: sixteen bands of
eight rows, each band one letter, cells valued **1**.

The letters are stored **lying on their side**, because the board is drawn
transposed — board row becomes screen X, board column becomes screen Y. Decoded,
bands 1..16 spell:

> **`ASPHYXIA RULZ`**  (13 letters then three blank bands)

Bands 17..26 spell **`0,000 DOTS`** and are never copied onto the board — dead
data left in the executable. Given the scroll text boasts "4000 DOTS", this was
presumably an earlier take on the same joke.

Emitted as [`src/gen/P6CELL.INC`](../src/gen/P6CELL.INC).

### The paths are generated, not loaded

The two 59,904-byte tables (`$EA00` = 72 angles × 26 rows × 16 cols × 2) are
`GetMem`'d and then **computed** by `Whoosh_BuildPaths`:

1. build 72-entry cos/sin tables at **5° per step** — 360° in all;
2. lay out a 28 × 16 grid of points, spacing 15, centred on cell (14, 8):
   `Px := (Row - 14) * 15`, `Py := (Col - 8) * 15`;
3. for every angle, rotate every point about the origin and store the screen
   position:

```
PathX[A, Row, Col] := Px*Cos + Py*Sin + 160
PathY[A, Row, Col] := Py*Cos - Px*Sin + 100
```

So the whole board spins about the screen centre, one full revolution every 72
frames, and the renderer just looks up where each cell goes.

### What the 45,000-byte block actually is

It is the **cell animation**: 72 frames of a 25×25 sprite, 72 × 625 = 45,000.
The two 256-byte reads are per-cell-type **colour maps**, moved to `DS:$70F2`
(cell 1, the letters) and `DS:$71F2` (cell 2, the background) by
`Whoosh_LoadColourMap` (`100f:00ac`). Each frame, the current animation frame is
recoloured through both maps into two 627-byte working cells (625 pixels plus a
2-byte `25,25` header), and every lit board cell blits whichever one its value
selects.

That is the whole trick: **one animation, two palettes, and a rotating lookup
table.**

The visible window is 26 rows × 14 columns, scrolling two rows per frame to row
170; the display switches from copy to clear at row 145.

## Scene 3 — fire

`Fire_Run` (`1118:08d3`). The classic flame algorithm, and cheap:

```pascal
A := (P[-1] + P[0] + P[1] + P[80]) shr 2;   { four-neighbour average }
if A <> 0 then Dec(A);                       { decay }
P[-80] := A;                                 { write ONE ROW UP }
```

Heat rises by construction — no separate propagation step. The buffer is 80×98,
its bottom row re-randomised every frame (`-Random(2)`), and it is scaled **4×**
on the way out (four bytes written per source byte, twice per row) to fill
320×200. Runs 300 frames.

**Two different motions, and an earlier version of this page conflated them.**

*Within the buffer, heat rises.* The averaging step writes its result **one row
up** — `P[-FireW] := A` — so the flame climbs by construction, with no separate
propagation pass. That is the effect itself and it is unambiguously upward.

*At the end of the scene, the whole picture slides down.* From frame 100 the
output goes through `FUN_1118_08a2` instead of a straight copy, and that routine
blanks the **first** *n* bytes of the destination and copies the source in behind
them:

```
XOR DI,DI ; MOV CX,BX ; REP STOSB    (AL = 0)   blank dest[0 .. n-1]
MOV CX,$FA00 ; SUB CX,BX ; REP MOVSB            src[0..] -> dest[n..]
```

So `dest[n + i] = src[i]`: the composited image is displaced **downward** by
*n* bytes while black grows from the top, and over the remaining 200 frames the
scene slides off the bottom. That is a wipe-out transition, not the fire's own
motion.

The original page said "scrolls upward, lifting the fire off the bottom", which
described neither correctly.

## Scene 4 — the greetings scroller

`Credits_Step` (`11bb:0168`). A vertical scroller in a 64K buffer **256 bytes
wide**: each frame draws one more glyph row, then scrolls the whole buffer up by
256 bytes — exactly one row — with `FillChar` + `Move`.

The font is 18×21 (378 bytes per character, `$17A`), the text is 12-character
lines at 256-byte spacing, 20 columns visible, running to line 114.

### The credit text

99 lines of 12 characters, a Borland `array[1..99] of String` compiled into
DGROUP at `DS:$0D8A` — 256 bytes per element, which is why the stride is `$100`.
Emitted as [`src/gen/P6TEXT.INC`](../src/gen/P6TEXT.INC).

Four blocks, one per member:

| Member | Content |
|---|---|
| **EzE** | a dedication to `$ADELE$`, "MY LADYMOTH", then greets |
| **GoTH** | "TO ALL THE LOST AND BORED SOULS, ALL IDEAS WELCOMED!", thanks to `-TELKOM(NOT)` and `-ESKOM` |
| **Denthor** | "FULL SOURCE TO BE RELEASED IN MY NEXT TRAINER", then greets |
| **Fubar** | "A MAN OF MANY WORDS IS A MAN WITH LITTLE BRAINS", then `--BYE--` |

## Open

- Nothing outstanding.
