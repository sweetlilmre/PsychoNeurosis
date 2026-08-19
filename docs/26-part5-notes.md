# Part 005 — working notes from the disassembly

Read straight out of `NEUROSIS_005_fpu.exe` with Ghidra. Nothing here is
inferred from the other parts or from what a routine "ought" to do; where
something is not yet read, it says so.

---

## Layout

| segment | linear | what |
|---|---|---|
| `1000` | `0x10000` | the main body, `0x00`..`0xdf` |
| `100e` | `0x100e0` | **scene 1** — the heightfield mesh, `0x00`..`0x87f` |
| `1096` | `0x10960` | **scene 2** — the rotozoomer, `0x00`..`0x6bf` |
| `1102` | `0x11020` | **scene 3**, `0x00`..`0x147f` |
| `124a` | `0x124a0` | FixMath — two routines |
| `1252` | `0x12520` | the shared VGA unit |
| `1266` | `0x12660` | Turbo Pascal's Crt |
| `12c8` | `0x12c80` | the DemoVT client |
| `12d9` | `0x12d90` | the RTL |
| `166c` | `0x166c0` | DGROUP |

**Part 005 was built with `{$S+}`.** Its procedures open `MOV AX,<locals>` /
`CALLF 12d9:0530` — Turbo Pascal's stack check — where part 004's do not. That
is the opposite of every other part read so far, and it means `PART5` needs an
explicit `{$S+}` to override the `/$S-` the build passes.

---

## The main body — `1000:002d`

Unit initialisation first (`1000:0000`..`0028`), then:

```
1252:0000  SetMode13h
1252:0006  VirtScrAlloc
12c8:0000  MusicDetect
12c8:006a  DemoVT function 3
12c8:0093  MusicCue
12c8:004e  MusicStart
100e:07a4  Demo_Scene1        then  while KeyPressed do ReadKey
1096:03d7  Demo_Scene2        then  while KeyPressed do ReadKey
1102:035a  Demo_Scene3        then  while KeyPressed do ReadKey
           SavedVol := GetVolume
           repeat
             SetVolume(GetVolume - 1)
             Delay(10)
           until GetVolume = 0
12c8:005c  MusicStop
12c8:00d8  SetVolume(SavedVol)
1252:0033  VirtScrFree
           Halt(0)
```

`DS:$2d7c` is `SavedVol` and `DS:$2d7d` the loop's copy of the volume.

Note this part calls **function 3** (`12c8:006a`), which so far only part 001
was known to use.

---

## FixMath — segment `124a`

Two routines survive the smart link, plus an empty unit initialisation at
`124a:0071`.

- **`124a:0000  IntToFixed(N : Integer) : LongInt`** — sign-extends N to
  `DX:AX`, loads `BX:CX` with 16 and calls `12d9:3735`, which is the RTL's
  32-bit left shift (`SHLD DX,AX,CL` on a 386, a `SHL`/`RCL` loop otherwise,
  chosen off the CPU-type byte at `DS:$2d78`). So it is `LongInt(N) shl 16`.
  Only CL is used; BX is loaded because the caller passes a whole LongInt.
- **`124a:0034  RealToFixed(R : Real) : LongInt`** — `Round(R * 65536.0 + 0.5)`.
  The two multiplicands are 4-byte singles in the code segment:
  `124a:002c` = `47800000` = 65536.0, `124a:0030` = `3F000000` = 0.5.

---

## Scene 1 — segment `100e`, the heightfield mesh

A 32 x 32 grid of points is projected and drawn as 1922 filled triangles. The
height of each point comes from a 1024-byte greyscale map read off
NEUROSIS.DAT, thresholded — and the threshold is what is animated, so the
landscape grows out of a flat plane and sinks back into it.

### DGROUP

| address | what |
|---|---|
| `DS:$0002` | the triangle list, 1922 x 3 words of vertex index |
| `DS:$2d7e` | the height map, 1024 bytes |
| `DS:$317e` | the grid, 1024 points of (X, Y, Z) as three words = 6 bytes |
| `DS:$497e` | the projected vertices, 1024 x (SX:Word, SY:Word, Colour:Byte) |
| `DS:$5d7e` | the file variable |
| `DS:$5dfe` | a row table, 200 words |
| `DS:$aa08` | `VirtScrSeg` |

### `Demo_Scene1` — `100e:07a4`

```
Assign(F, 'neurosis.dat')        the name is a CS constant at 100e:0797
Reset(F, 1)
Seek(F, $00153DE5)               = 1,392,101
SetRGB(1, 0, 0, 0)               black out colour 1
100e:050b   BuildGrid
100e:04e6   BuildRowTable
100e:056d   HeightFromMap($37)   the map is still zero, so this flattens it
100e:05d3   Project(@Grid, @Proj)
100e:062a   DrawMesh(@Proj, @Tris)
100e:076c   FadeUpDot
100e:073c   BuildRamp
BlockRead(F, HeightMap, $400);  100e:06ae  Morph($41, $14)
BlockRead(F, HeightMap, $400);  100e:06ae  Morph($41, $14)
BlockRead(F, HeightMap, $400);  100e:06ae  Morph($37, $05)
ClearScreen($A000, 0)
Close(F)
```

So three 1024-byte maps are read in turn and each is morphed up and back down.

### `100e:04e6  BuildRowTable`

`for I := 0 to 199 do RowOfs[I] := I * 320` into `DS:$5dfe`. Scene 1 keeps its
own copy rather than using the VGA unit's.

### `100e:050b  BuildGrid`

```
for I := 0 to 1023 do
begin
  Grid[I].X := ((I mod 32) - 16) * 20;      { IDIV 32, remainder  }
  Grid[I].Y := ((I div 32) - 16) * 20;      { SHR 5, so unsigned  }
  Grid[I].Z := 300;
end;
```

### `100e:056d  HeightFromMap(Threshold : Byte)`

```
for I := 0 to 1023 do
  if HeightMap[I] > Threshold then          { JBE, so unsigned }
    Grid[I].Z := 250 - (HeightMap[I] - Threshold)
  else
    Grid[I].Z := 250;
```

A lower threshold lets more of the map through, so the mesh rises.

### `100e:05d3  Project(Src, Dst)` — HAND ASSEMBLER

Near procedure, `RET 8`, two far pointers; `Src` is pushed first and read from
`[BP+8]`, `Dst` from `[BP+4]`. It saves DS and **uses BP as a scratch register**
for Z, which is why it pushes BP separately.

```
CX := 1023
per point:  X := Src^;  BX := X shl 6
            Y := Src^;  CX := (-Y) shl 6
            Z := Src^;  BP := Z
            Dst^.SX := 160 - (X shl 6) div Z
            Dst^.SY := 100 - ((-Y) shl 6) div Z
            Dst^.Col := ((250 - Z) mod 255) + 1
loop while (DEC CX) stays non-negative -- JNS, so 1024 points
```

The colour is a byte, making the record 5 bytes.

### `100e:062a  DrawMesh(Verts, Tris)` — HAND ASSEMBLER

Near procedure, `RET 8`; `Verts` pushed first at `[BP+8]`, `Tris` at `[BP+4]`.

```
ClearScreen(VirtScrSeg, 0)
CX := 1922
BX := offset of Verts
per triangle:
  PUSHA
  three times:  I := Tris^          (LODSW)
                DI := I*5 + BX      (MOV DI,AX / SHL AX,2 / ADD DI,AX / ADD DI,BX)
                push ES:[DI], then ES:[DI+2]        the X and Y
  DI := DI + 1                      now at the third vertex's +3
  AX := ES:[DI]; AL := AH           the colour byte, read as the high half
  push it, push VirtScrSeg
  CALL 100e:0000                    the filler
  POPA
  SI := SI + 6                      three indices -- POPA put SI back
CopyScreen(VirtScrSeg, $A000)
```

`PUSHA`/`POPA` are 186 instructions, so this unit needs `{$G+}`.

### `100e:073c  BuildRamp`

`for I := 30 to 74 do SetRGB(I - 29, 0, 0, I - 10)` — colours 1..45 get a blue
ramp from 20 to 64. `SetRGB` is `(Col, R, G, B)`, confirmed at `1252:007f`
where the first parameter is the one written to port `$3C8`.

### `100e:076c  FadeUpDot`

`for I := 1 to 20 do begin SetRGB(1, 0, 0, I); Delay(50) end`.

### `100e:06ae  Morph(A, B : Byte)`

`A` is pushed first and read from `[BP+6]`, `B` from `[BP+4]`.

```
for T := A downto B do begin HeightFromMap(T); Project; DrawMesh end;
for T := B to A   do begin HeightFromMap(T); Project; DrawMesh end;
```

Both loops are guarded, so an inverted pair would simply do nothing.

### `100e:0000  FillTriangle` — read in full

1254 bytes, called as
`Fill(X1, Y1, X2, Y2, X3, Y3, Colour, Segment)` — eight words pushed in that
order, near call.

---

## Scene 2 -- segment `1096`, the rotozoomer

A rotozoomer, and in front of it a scatter-and-reassemble.

### `1096:0000  RotozoomFrame` -- hand assembler, 64 bytes

`RotozoomFrame(V0, U0, dV, dU : Integer; Tex : Pointer)`, near, `RET $0C`.

**The whole trick is the addressing.** The texture is 256 wide, so the texture
offset is the two HIGH bytes of the two 8.8 fixed-point coordinates stuck
together -- `MOV AH,DH` / `MOV AL,BH` / `MOV SI,AX`, and then `MOVSB` with DS
already on the texture. No shift, no mask, no multiply, and no bounds test:
the coordinates wrap in eight bits by themselves.

`DI` walks the whole screen once and is never reset per row. Only 195 rows are
drawn (`CMP CX,0C3h`), not 200. `V0` and `U0` are updated IN THE CALLER'S
FRAME at the end of each row -- `SUB V0,dU` / `ADD U0,dV` -- which is the
incremental rotation and is why Pascal would need var parameters.

**Verified at 64 of 64 bytes**, two holes, both DGROUP addresses.

### `1096:0042  Shatter`

Eight passes. Each draws one rotozoom frame into the virtual screen, walks it
from the BOTTOM LEFT upwards collecting every non-black pixel as a 10-byte dot
record with a random starting point, blanks the virtual screen, and then runs
25 steps of linear interpolation -- erase at the previous position, draw at
the new one. It stops collecting at 1,500 dots.

**A BLACK PIXEL IS SKIPPED, NOT AN END.** `1096:00f4` is a `JNZ` to the
recording code and `1096:00f6` a `JMP` straight to the `Inc(X)` at
`1096:0180`, so the scan carries on either way. Reading that as
`while GetPixel <> 0` stops the whole thing on the first pixel, because
`RotozoomFrame` only draws 195 rows and the scan starts on row 199, which is
blank -- the effect then produces nothing at all and the scene looks like it
goes straight to the rotozoomer.

`X` and `Y` are set once at `1096:0074`, BEFORE the pass loop, so a later pass
carries on scanning from wherever the last one ran out of dots.

Nothing here advances the frame index, so all eight passes shatter the SAME
picture.

The dot record, off `1096:010f` onwards: `Age:Byte` `Col:Byte` `FromX:Word`
`ToX:Word` `FromY:Word` `ToY:Word`, indexed one-based as `DI := Count*10` with
every field reached at `DI-10`..`DI-1`.

### `1096:03d7  Demo_Scene2`

Reads a palette and a 320x200 picture from `$001549E5`, lifts a **256-wide
window starting four pixels in** into a 64K texture, and blanks the 56 rows
past the bottom of it so a coordinate that runs off reads black.

Then two tables of 2001 entries each:

    TabSin[I] := Round(I * Sin((I + 270) / 180.0 * Pi))
    TabCos[I] := Round(I * Cos((I + 270) / 180.0 * Pi))
    TabU[I]   := -Round(TabSin[I] * 100)
    TabV[I]   := -Round(TabCos[I] * 160)

The angle is in DEGREES: `CS:$03c9` is the single `180.0` and `CS:$03cd` the
ten-byte extended Pi, both read straight out of the image. The amplitude grows
with the index, so as the index runs 270 -> 1980 the zoom spirals outwards as
well as turning.

`Sin` and `Cos` are the RTL stubs at `12d9:32ad` and `12d9:32b2`. They are
`INT 3Eh` emulator patch points, five bytes each, in a table that starts with
`12d9:32a9` = `CD 35 FA CB` -- `INT 35h,FAh`, which is the emulator's form of
`D9 FA`, **FSQRT**. Sqrt/Sin/Cos/ArcTan at 4/5/5/5 bytes is the same layout
Ghidra names in part 003 at `137b:324e`..`325c`.

One curiosity transcribed as it stands: `1096:049d` is `FillChar` with a count
of **zero**, which does nothing. The intent was presumably 65536, which does
not fit the Word the count is.

Note the two calls to `RotozoomFrame` do NOT agree: `Shatter` takes the U term
at `Index+1` with a bias of `$4E20`, the scene's own loop takes it at `Index`
with a bias of `$3E80`.

---

## Scene 3 -- segment `1102`, the turning relief

A 30 x 30 patch of a loaded picture, lifted into three dimensions and turned
about one axis while the patch itself wanders around the picture and bounces
off all four edges.

### The maths is the SAME OBJECT parts 001 and 002 link

`SinCos` (`1102:11d9`), `RotatePoint` (`1102:128b`) and `Project`
(`1102:13d9`) are byte-identical to part 001's copies at `1107:1804`,
`1107:18b6` and `1107:1a04`. 16, 24 and 7 bytes differ across the three and
every one is a DGROUP or table displacement; the lengths are identical to the
byte. The table at `CS:$03C5` is 901 entries and was checked against
`Round(cos(i/10 degrees) * 65536)` -- exact.

**It also showed the module has FIVE routines, not three.** `FixMul` at
`1102:0391` and `FixDiv` at `1102:03a5` sit ahead of the table in both
binaries, and `src/asm/DEMOMATH.ASM` was missing them.

    FixMul(A, B) = (A * B) shr 16, and NO SHIFT PAIR IS NEEDED: IMUL leaves
    the 64-bit product in EDX:EAX and Turbo Pascal returns a LongInt in the
    SEPARATE registers DX:AX, so shifting EAX alone by 16 puts bits 16..31 in
    AX while DX already holds bits 32..47.

    FixDiv(A, B) widens A to 48 bits with SHRD/SAR, divides, and puts the
    quotient back together with SHLD.

Neither is called from Pascal in any part read so far. They survive the link
because an external OBJ is linked whole rather than per procedure.

### `1102:0000  RenderPatch(CX, CY, Angle, Seg)`

900 loose pixels -- no mesh, no interpolation. Two things inference would get
wrong:

- The patch coordinate is used TWICE and differently. `Col - 15` added to `CX`
  picks the pixel out of the picture; the SAME `Col - 15` is the 3-D X.
- The height is not applied in three dimensions at all. Y goes in as the
  constant `-50`, and the pixel VALUE is added to the PROJECTED Y at
  `1102:0132`, after the divide. Only the low word of the projected
  coordinates is ever read -- `1102:011f` and `1102:012c` subtract with AX.

Only one axis turns: `1102:0022` fills `MCos2`/`MSin2` from the angle and the
other two pairs are filled from zero.

### `1102:017e  Run`

The patch moves diagonally two pixels a frame and reflects off each edge. At
frame 100 it stops and the rotation jumps to three degrees a frame; at 220 it
moves again at one degree. From 500 the palette dims a step a frame; at 564 it
stops. A keypress sets the frame count straight to 500, so a key buys the
fade-out rather than an exit.

`1102:01a9` tests `Running` and skips only the `Inc(Frame)` -- redundant,
since the loop only goes round again while it is set. Transcribed as it
stands.

`1102:035a` builds `MScale` as `RealToFixed(1600.0)`; the Real is assembled in
AX:BX:DX as `8B 00 00 00 00 48`, which is 1600.0 in Turbo Pascal's six-byte
format.

---

## Where part 005 stands

`P5S1`, `P5S2`, `P5S3` and `P5Main` are all read from the binary and all
build. `src/PART5_ROTOZOOM.PAS` -- the earlier single-unit pass, which carried
inference and stubs -- has been deleted.

Every routine that is assembler end to end is byte-checked:

    FillTriangle   100e:0000   1254 of 1254   15 holes
    Project        100e:05d3     87 of   87    0 holes
    DrawMesh       100e:062a    132 of  132    8 holes
    RotozoomFrame  1096:0000     64 of   64    2 holes
    FixMul         1102:0391     19 of   19    0 holes
    FixDiv         1102:03a5     32 of   32    0 holes
    SinCos         1102:11d9    178 of  178    9 holes
    RotatePoint    1102:128b    334 of  334   12 holes
    Project        1102:13d9    166 of  166    4 holes

Every hole is a DGROUP or table displacement or a relocated far call.
