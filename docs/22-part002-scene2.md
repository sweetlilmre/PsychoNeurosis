# NEUROSIS.002 scene 2 — the solid 3-D object scene

Working notes from the disassembly of `NEUROSIS_002_fpu.exe`. Everything here
was read out of the binary; nothing is inferred. Both scenes are transcribed
� `src/P2S1.PAS` and `src/P2S2.PAS` � and this is the working record behind
the second.

Segment map for the part:

| segment | unit | status |
|---|---|---|
| 1008 | scene 1 | transcribed — `P2S1.PAS` |
| 107c | Mode-X, 1280-wide | transcribed — `P2MODEX.PAS` |
| 108b | scene 2 | transcribed � `P2S2.PAS` (this document) |
| 13f9 | resident tracker client | transcribed — the shared `DEMOVT.PAS` |
| 140c | 320x400 two-page unchained | transcribed — `P2VIEW.PAS` |
| 142a | 16.16 fixed point | transcribed — `P2FIX.PAS` |
| 1436 | VGA / palette / staging buffer | transcribed — the shared `VGA.PAS` |
| 14b1 | Turbo Pascal RTL | not ours |

---

## The object record

Four objects live in DGROUP, `$B51` (2,897) bytes apart:

```
obj 1  DS:$5A56      obj 2  DS:$65A7      obj 3  DS:$70F8      obj 4  DS:$7C49
```

Layout, relative to the object's base address:

| offset | size | what |
|---|---|---|
| `+$000` | word | vertex count |
| `+$002` | word | face count |
| `+$004` | 12 × N | vertices, three 16.16 values each |
| `+$382` | 6 × N | projected output: X, Y, D as words |
| `+$533` | 23 × F | faces |
| `+$B21` | 12 | rotation angles, three LongInts (tenths of a degree) |
| `+$B2D` | 12 | translation, three 16.16 values |
| `+$B39` | 12 | pivot, three 16.16 values |
| `+$B45` | 12 | accumulated angles, three LongInts |

Vertex `I` (1-based) is at `obj + 12*I - 8`. Output record `I` is at
`obj + $382 + 6*I`; `.X` at `+0`, `.Y` at `+2`, `.D` at `+4`.

A face is 23 bytes but only 21 are used:

| offset | size | what |
|---|---|---|
| `+$00` | word | vertex count |
| `+$02` | word × 8 | vertex indices |
| `+$12` | byte | colour |
| `+$13` | byte | zero |
| `+$14` | byte | zero |
| `+$15` | word | average depth — written by the sort at `108b:0e03` |

Face `F` is at `obj + $533 + 23*F`.

---

## Routines

### `108b:2454` Demo_Scene2

```
Assign(F, CS:$2447 = 'neurosis.dat') ; Reset(F, 1)
Seek(F, $0007D9B2)
GetMem(P, $3200 = 12800) ; BlockRead(F, P^, 12800)
BlockRead(F, DS:$5448, $60E = 1550)
MusicStart                                   13f9:004e
[$8ED1] := 0  (a 32-bit frame counter)
SetMode400                                   140c:009c
BuildRowTable80                              108b:0a09
FlipPage(0)                                  140c:00f4
BlockRead(F, DS:$5148, $300)                 palette
Scene2_Setup                                 108b:1bbd
BlockRead(F, DS:$8ED5, $5B6 = 1462)
Close(F)
SetRGB 1..6 := (3F,3F,3F) (1B,1B,1B) (27,27,27) (03,33,03) (0F,27,0F) (16,16,16)
Scene2_Choreography                          108b:11c1
save volume, ramp it to zero with Delay(10) per step
SyncPattern(1, 1) ; MusicStop ; restore volume
FreeMem(P, 12800)
```

### `108b:0a09` BuildRowTable80

`RowOfs[I] := I * 80` for `I = 0..$EF`, into `DS:$A0CA`. 240 entries — the
320x240 field the projection centres on.

### `108b:1bbd` Scene2_Setup

Not an intro. It is the palette and object initialiser.

1. Colours 1..255 get a grey ramp: `SetColour(C, (C mod 53)+10, same, same)`.
2. Thirteen specific colours are overwritten — `$18` and `$30` to `(0A,00,3C)`,
   `$42` to `(00,32,00)`, and two five-entry brown ramps at `$D1..$D5` and
   `$D5..$D9`.
3. `[$8ED0] := 1`.
4. The projection scale:
   `[$87C4] := RealToFixed(320 / CS:$1BAF * CS:$1BB3)` — the two constants
   still need decoding (a `single` and an `extended` in segment 108b).
5. Four objects built from DGROUP tables. Per object: vertex and face counts
   written to `+0`/`+2`, vertices read as integer triples and **halved** before
   `IntToFixed`, faces read as a run of words (count, then that many indices,
   then the colour), then the angles zeroed and a translation and pivot set.
   The per-object differences in how indices and colours are handled are set
   out under "Object data" below � they are not the same for all four.

| object | base | verts | faces | vertex table | face table | translation | pivot |
|---|---|---|---|---|---|---|---|
| 1 Enterprise | `$5A56` | 75 | 55 | `DS:$0004` | `DS:$01C6` | (0, 0, −850) | (150, 0, 0) |
| 2 Revolver | `$65A7` | 68 | 64 | `DS:$067E` | `DS:$0816` | (1500, 0, −1500) | (150, 0, 0) |
| 3 Sailboat | `$70F8` | 32 | 21 | `DS:$0B06` | `DS:$0BC6` | (−1500, 0, −1500) | (0, 0, 0) |
| 4 Quad | `$7C49` | 4 | 1 | `DS:$0CAE` | `DS:$0CC6` | (0, 0, −1000) | (0, 0, 0) |

**Do not read those blocks positionally.** Each object's angle / translation /
pivot block sits AFTER its own face loop and BEFORE the next object's vertex
loop, so the block at `108b:201b` looks like it introduces object 3 when its
addresses are object 2's. Take the base from the address:

```
108b:1e4c  ->  $6577 - $B21 = $5A56   object 1
108b:201b  ->  $70C8 - $B21 = $65A7   object 2
108b:21f1  ->  $7C19 - $B21 = $70F8   object 3
108b:23cc  ->  $876A - $B21 = $7C49   object 4
```

The components are `+$B2D`, `+$B31`, `+$B35` for X, Y, Z. Object 3 writes
`$7C25` and `$7C2D` — offsets 0 and 8, so X and **Z**; object 4 writes `$877E`
— offset 8, so **Z**. Putting either on the wrong axis leaves Z at zero, which
lands the object on the projection plane and sprays it across the screen.

### `108b:00bf` Obj_SetRotation — really the whole transform

`RET $10`: `(var Obj; A, B, C : LongInt)`.

1. Wrap each of the three accumulated angles at `Obj+$B45`: if negative, add
   `$E10` (3600).
2. `SinCos` each into `DS:$87AC/$87B0`, `$87B4/$87B8`, `$87BC/$87C0`
   (cos first, sin second — the first var parameter takes the cosine).
3. Copy the pivot `Obj+$B39` to a local, `RotatePoint` it.
4. Wrap the three parameters the same way, store them into `Obj+$B21`, and
   `SinCos` them into the *same* six globals — overwriting step 2.
5. For `I := 1 to VertexCount`:
   - copy vertex `I` to a local, `RotatePoint`
   - add the rotated pivot from step 3
   - add the translation `Obj+$B2D`
   - `Project` (`108b:362f`)
   - store `Out[I].X`, `Out[I].Y`, and `Out[I].D := FixedToInt(z)`

### `108b:03be` Obj_AddRotation

`RET $10`. Adds `IntToFixed(low word of each parameter)` to the three
LongInts at `Obj+$B2D`. Call sites always pass sign-extended small values.

### `108b:342f` Math_SinCos

Identical in shape to part 001's `1107:1804`: a 901-entry 16.16 **cosine**
table at `CS:$261B`, quadrant-folded, angle in tenths of a degree. First var
parameter receives cos, second sin.

### `108b:34e1` Math_RotatePoint

Identical to part 001's rotate. Three concatenated 2-D rotations, X then Y
then Z, `(a*b)>>16` throughout:

```
y1 = y*C1 + z*S1     z1 = z*C1 - y*S1
x2 = x*C2 - z1*S2    z2 = z1*C2 + x*S2
x3 = x2*C3 + y1*S3   y3 = y1*C3 - x2*S3
```

with `C1 = [$87AC]`, `S1 = [$87B0]`, `C2 = [$87B4]`, `S2 = [$87B8]`,
`C3 = [$87BC]`, `S3 = [$87C0]`.

### `108b:362f` Math_Project

Byte-for-byte part 001's projection. Divides by the **third** parameter (Z):

```
Sx := round(X/Z * [$87C4]) + [$046A] div 2
Sy := [$046C] div 2 - round(Y/Z * [$87C4])
```

`DS:$046A = 320` and `DS:$046C = 240`, both initialised data — so the centre
is **(160, 120)**, not (160, 100). Z is left alone for the caller to truncate.

### `108b:0e03` Obj_SortFaces

Copies the whole object (`$B51` bytes) onto the stack, then:

1. For each face: `Key := sum of Out[v].D over its vertices, div vertexCount`.
2. Selection sort into the *original* object's face array, starting at slot 1:
   repeatedly find the face with the **smallest** key (the scan at
   `108b:0eff` updates only when `Key < Best`, and `Best` starts at 0), copy
   its 23 bytes into the next slot, and zero its key so it is not picked
   again. Stop when no face has a key below zero.

So: painter's order, farthest first, with everything at `D >= 0` culled. Note
the emitted count is not written back to `Obj+2` — the renderers still draw
`FaceCount` faces, so the tail of the array holds whatever the previous frame
left there. That is the original's behaviour.

### `108b:0b42` Obj_RenderA

1. Copy the object onto the stack; copy 65 faces (`$5D7` bytes) to a second
   stack buffer.
2. Draw 500 stars with `Plot` (`140c:00b1`) from `DS:$9485` (X), `$9487` (Y),
   `$9489` (colour), stride 6.
3. For each face, gather its vertices' `Out[].X`/`.Y` into an interleaved
   array of 4-byte pairs, then `Poly_FillFan(@pairs, count, colour, WritePage)`.
4. `FlipPage(WritePage)`, then `[$0CEC] := ([$0CEC] + 1) mod 2`.

`108b:0ca1` (RenderB) and `108b:0a2d` (RenderC) are variants — B also calls
`108b:0422`, C draws no stars. **Not yet read.**

### `108b:11c1` Scene2_Choreography

Thirteen phases. Structure of a phase:

```
for I := 1 to N do
  Obj_AddRotation(@Obj, dA, dB, dC)
  Obj_SetRotation(@Obj, angleZ, angleX, angleY)      { locals BP-2, BP-6, BP-4 }
  WritePage := PageBase[[$0CEC]]
  FillRect(0, 0, 320, 200 or 240, WritePage, 0)
  Obj_SortFaces(@Obj)
  Obj_RenderA/B/C(@Obj)
  Inc(FrameCounter at [$8ED1])
  Present (108b:0f66)
```

Before the phases: a blue ramp into colours 70..90, 500 stars seeded at
`Random(320)`, `Random(200)`, `Random(20)+70`, and both pages cleared.

Phase lengths and the rotation deltas, in order, read from the call sites:

| phase | frames | object | AddRotation deltas | renderer |
|---|---|---|---|---|
| 1 | 100 | 1 | (0, 0, 3) | A |
| 2 | 80 | 1 | (−1, 0, 3) | A |
| 3 | 20 | 1 | (−1, 0, 3) | A |
| 4 | 50 | 1 | (−1, 0, 2) | A |
| 5 | 50 | 1 | (−1, 0, 0) | A |
| 6 | 50 | 1 | (−1, 0, 0) | A |
| 7 | 12 | 1 | (0, 0, 0) | B |
| 8 | 12 | 1 | (0, 0, 0) | B |
| 9 | 12 | 1 | (0, −1, −8) | B |
| 10 | 5 | 1 | (0, −1, −12) | B |
| 11 | 45 | 1 | (0, −1, −12) | B |
| 12 | 120 | 2 | (−1, 0, 10) | C |
| 13 | 120 | 3 | (0, 0, 10) | C |
| 14 | 99 | 4 | (0, 0, 10) | C |

with `SyncPattern` cues at phases 2 (2,1), 6 (3,1), 7 (4,1) and before the
last group (6,1), position tweaks between phases, three 50-frame retrace
waits with `Delay(300)` and a full-screen clear of both pages between them,
and a `PaletteFade(10)` before the final group.

---

## The rest of the routines

### `108b:09b1` Poly_FillFan(Pts, Count, Colour, Page)

`if Count < 3 then exit`, then `Count - 2` triangles all sharing the first
point. The cursor advances one point per triangle (the `ADD DI,4` at
`108b:09d3` is the loop top, not a preamble). The `Page` parameter is passed
and never read — `Tri_Fill` takes the page from `DS:$A69A` instead.

### `108b:0461` Tri_Fill

Scanline triangle filler. The first two vertices arrive in `BX`/`CX` and
`DX`/`SI`, the third and the colour on the stack. It sorts the three by Y with
a chain of `XCHG`s, walks two edges into a per-scanline buffer at `DS:$A2AA`
as `(left, right)` word pairs, then fills the spans **backwards** from the
last scanline. Spans are written through the Map Mask with the same two
nibble tables as the rectangle fill, at `DS:$0676` and `DS:$067A`:

```
LeftMask  = $0F $0E $0C $08      RightMask = $0F $01 $03 $07
```

Clip box, all initialised data: `DS:$066E..$0675` = Y 0..239, X 0..319. The
X clamps are clamps, not rejects. Destination is `RowOfs80[y] + x div 4 +
WritePage`.

### `108b:0000` DrawText(X, Y, S)

A 5 × 5 bitmap font. The glyph byte is at `Ord(Ch) * 25 + R * 5 + C` off
`DS:$5122`, and the loader reads the glyphs to `DS:$5448` (`assets/part002/font_5x5.bin`) — 806 bytes higher,
and `806 = 32*25 + 6` — so the effective index is

```
(Ord(Ch) - 32) * 25 + (R - 1) * 5 + (C - 1)
```

a clean 5 × 5 glyph biased by 32, the same shape as part 001's fonts. `R` is
the horizontal axis, `C` the vertical, the pen steps 6 per character, and
every pixel is colour `$42`. 1,550 bytes is 62 glyphs, `$20..$5D`.

### `108b:0f66` Present — the typewriter

Driven entirely by the LongInt frame counter at `DS:$8ED1`:

```
100 < Frame < 150     message 1, character Frame-100, row $D2 = 210
250 < Frame < 300     message 2, character Frame-250, row $D9 = 217
```

X is `index * 6 + 15`. The RTL helper at `14b1:3651` is a LongInt **multiply**
— its 386 path is `SHL/SHRD` into `EAX` and `ECX` then `IMUL ECX`, with the
operand assembled as `BX:CX`, so `BX = 0, CX = 6` really is six. Each
character is drawn into **both** pages so it survives the flip.

The two messages are Pascal strings in DGROUP:

```
DS:$046E  'CAPTAINS LOG, STARDATE 426987.2, SUPPLIMENTAL  :           '
DS:$056E  '     PICTURE IT,   SICILY,   1942 ....               '
```

### `108b:1101` DrawBanner

Colours 100..200 loaded from the 768-byte palette at `DS:$5148`, then the
12,800-byte heap block plotted into rows 200..239 of **both** pages, a pixel
at a time. 12,800 is 320 × 40 — exactly that strip.

### `108b:0422` DrawBadge

A 34 × 43 image plotted at the top-left corner from the 1,462-byte block at
`DS:$8ED5` (`assets/part002/sprite_34x43.bin`). The index at `108b:0443` is `Y * $22 + X` off a base `$23` lower,
which makes it one-based in both axes.

### `108b:0ca1` / `108b:0a2d` RenderB, RenderC

Same body as RenderA. B adds `DrawBadge` between the stars and the faces
(`CALL` at `108b:0d18`, before the fan fill at `108b:0dd7`); C draws neither
stars nor badge.

### The projection scale

`CS:$1BAF` is a single = **2.0** and `CS:$1BB3` an extended = **0.9**, so
`Scale := RealToFixed(320 / 2.0 * 0.9)` = **144.0**.

---

## Object data

`tools/p2obj.py` lifts the four objects out of DGROUP into
`src/gen/P2OBJ.INC`.

**The four objects are NOT built the same way.** `Scene2_Setup` has four
separate copies of the loop, and object 1's differs from the other three:

| | vertex components | face vertex index | face colour |
|---|---|---|---|
| object 1 | halved | **plus one** (`INC AX`, 108b:1df6) | word, **halved** (108b:1e14) |
| objects 2–4 | halved | unchanged (108b:1fca / 21a0 / 237b) | **byte**, not halved (108b:1fee / 21c4 / 239f) |

So object 1's table is 0-based and the other three are already 1-based.
Applying object 1's rule to all four is what put the pistol's faces in the
top-left corner and made the sailboat cover the screen — the index range
proves it:

```
Ente  bias=0  indices 1..74   bias=1  indices 2..75    both inside 1..75
Revo  bias=0  indices 1..68   bias=1  indices 2..69    3 outside 1..68
Sail  bias=0  indices 1..31   bias=1  indices 2..32    both inside 1..32
Quad  bias=0  indices 1..4    bias=1  indices 2..5     1 outside 1..4
```

Object 1 needs the bias for the opposite reason: without it the Enterprise never
references vertex 75, and with it never references vertex 1 — which is
`(0, 0, 0)`, the dummy origin. `p2obj.py` now flags any index that falls
outside `1..VertCount`, so this class of mistake cannot pass silently again.

| object | verts | faces | vertex table | face table | face words |
|---|---|---|---|---|---|
| Enterprise | 75 | 55 | `DS:$0004` | `DS:$01C6` | 338 |
| Revolver | 68 | 64 | `DS:$067E` | `DS:$0816` | 371 |
| Sailboat | 32 | 21 | `DS:$0B06` | `DS:$0BC6` | 111 |
| Quad |  4 |  1 | `DS:$0CAE` | `DS:$0CC6` |   6 |

Two independent checks that the extraction is right: each vertex table ends
exactly where its face table begins, and the Ship's face table ends at
`$01C6 + 338*2 = $046A` — which is `ScreenWidth`, the next known global. The
maximum face arity across all 141 faces is 8, exactly the number of index
slots the 23-byte face record has.

---

## Status

Transcribed as `src/P2S2.PAS`, with `src/TP2S2.PAS` as the harness. Compiles
under TP 7.01 and installs as `run/TP2S2.EXE`.
