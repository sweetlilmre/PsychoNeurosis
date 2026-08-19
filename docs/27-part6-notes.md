# Part 006 — working notes from the disassembly

Read out of `NEUROSIS_006_fpu.exe`. Nothing here is inferred from the other
parts; where something has not been read yet, it says so.

**Status: all four scenes read and transcribed.** `P6S1`, `P6S2`, `P6S3`,
`P6S4` and `P6Main` all build, and every routine that is assembler end to end
is byte-checked against the binary. `src/PART6_CREDITS.PAS` — the earlier
inferred single-unit pass — has been deleted.

The binary had to be imported into Ghidra (it was not in the project) and its
auto-analysis finds no functions, so unlike parts 001–005 there is no function
table to read boundaries off. Every address below was found by following calls.

---

## Layout

| segment | linear | what |
|---|---|---|
| `1000` | `0x10000` | the main body, `0x00`..`0xef` |
| `100f` | `0x100f0` | **scene 2**, `0x00`..`0x85f` |
| `1095` | `0x10950` | **scene 1**, the whooshtext, `0x00`..`0x82f` |
| `1118` | `0x11180` | **scene 3**, `0x00`..`0xa2f` |
| `11bb` | `0x11bb0` | **scene 4**, `0x00`..`0x335` |
| `11ee` | `0x11ee0` | the shared VGA unit |
| `1217` | `0x12170` | Turbo Pascal's Crt |
| `1279` | `0x12790` | the DemoVT client |
| `128a` | `0x128a0` | the RTL |
| `164e` | `0x164e0` | DGROUP |

The unit initialisation chain runs `1095` LAST of the four scene units, but
the main body calls `1095` FIRST — link order and run order are not the same
here, so the segment numbers do not tell you the scene order.

---

## The main body — `1000:002d`

```
11ee:0000  SetMode13h
11ee:0006  VirtScrAlloc
1279:0000  MusicDetect
1279:006a  DemoVT function 3
1279:0093  MusicCue
1279:004e  MusicStart
1095:07d4  scene 1      then  while KeyPressed do ReadKey
100f:07d5  scene 2      then  while KeyPressed do ReadKey
1118:09df  scene 3      then  while KeyPressed do ReadKey
11bb:02c9  scene 4      then  while KeyPressed do ReadKey
           SavedVol := GetVolume                       DS:$70ec
           repeat SetVolume(GetVolume - 1); Delay(10) until GetVolume = 0
1279:005c  MusicStop
1279:00d8  SetVolume(SavedVol)
11ee:0033  VirtScrFree
           Halt(0)
```

Byte for byte the same shape as part 005's main body, including the call to
DemoVT **function 3** — which before part 005 was thought to be part 001 only.

---

## The shared units in this part

### VGA — segment `11ee`

Twelve routines survive the smart link. Confirmed so far by call site:

| offset | routine |
|---|---|
| `0000` | SetMode13h |
| `0006` | VirtScrAlloc |
| `0033` | VirtScrFree |
| `0048` | PutPixel |
| `00b8` | DrawLine |
| `01f7` | SetRGB |
| `0212` | SetPalette768 |
| `0246` | ClearScreen |
| `0281` | (unit init) |

`022a` is almost certainly CopyScreen and `025c` BuildRowTable by the source
order the unit is known to have, but neither has been reached from a call yet
and so neither is written down as fact.

### RTL — segment `128a`

The offsets differ from every other part, because each part links a different
subset. Established by call site:

| offset | routine |
|---|---|
| `028a` | GetMem |
| `029f` | FreeMem |
| `02e7` | MemAvail / MaxAvail — walks the free list at `128a:0323` |
| `3420` | Assign |
| `345b` | Reset |
| `34dc` | Close |
| `3546` | BlockRead |
| `35ae` | Seek |
| `3bf5` | Move |
| `3c19` | FillChar |

---

## Scene 1 — segment `1095`, the whooshtext

Two lines of text, drawn as a cloud of dots that whoosh into place. The
strings are CS constants and read out of the image directly:

    1095:078f   len 23   "ISNT'T THIS GREAT?     "
    1095:07a7   len 44   "THIS WHOOSHTEXT HAS 4000 DOTS!!!            "

The apostrophe placement in the first one is the original's.

### `1095:07d4` — the scene

```
1095:000d   Setup
1095:0578   DrawFrame
1095:067d   Whoosh(CS:$078f)
1095:067d   Whoosh(CS:$07a7)
11ee:0246   ClearScreen($A000, 0)
            FreeMem(DS:$737e, 6400)     FreeMem(DS:$7386, 15104)
            FreeMem(DS:$7382, 3200)
```

### `1095:000d  Setup`

`ENTER $386` — 902 bytes of frame, of which `[BP-$386]` is a 768-byte palette
buffer.

```
Assign(F, CS:$0000)          the filename is at the very start of the segment
Reset(F, 1)
Seek(F, $001743E5)
MemAvail                     -> a local that is never read again
GetMem(6400)  -> DS:$737e    and FillChar 0
GetMem(3200)  -> DS:$7382    and FillChar 0
GetMem(15104) -> DS:$7386
BlockRead(F, DS:$7386^, 15104)
BlockRead(F, palette, 768)
Close(F)
SetPalette768(palette)
MemAvail                     -> the same dead local
for I := 0 to 63 do SetRGB(I + 100, I, 0, 0)      a red ramp on 100..163
```

Both `MemAvail` calls store into `[BP-$86]` and nothing ever reads it. It is
dead in the original and will be transcribed as such.

### `1095:0578  DrawFrame`

```
for I := 1 to 16 do  1095:01a0(320 - I*2, 0, 0, 199 - I*6, I)
for I := 1 to 63 do  DrawLine(288 - I, 0, 0, 103 - I, 99 + I, $A000)
for I := 1 to 63 do  DrawLine(I, 199, 319, I, 99 + I, $A000)
```

Two fans of 63 lines in the red ramp, and sixteen calls to the path builder.

### `1095:01a0  the path builder` — ~980 bytes, FLOATING POINT

Takes five words and walks a line in six-byte Reals, recording a screen offset
per step into the 6400-byte table at `DS:$737e` — `Tab[Param1 * 400 + Step*2]`,
with 0 meaning "off screen". It bails out at 200 steps. Three Real constants
live in the code segment at `1095:018e` (a single), `1095:0192` (a single) and
`1095:0196` (a ten-byte extended). Not yet transcribed.

### `1095:067d  Whoosh(S : String)` — the renderer

Copies the string into its own frame, caches the two table pointers, and then

```
for CharIdx := 1 to Length(S) do
begin
  1095:0614(S[CharIdx])            prepare this glyph -- NOT YET READ
  for Pass := 1 to 16 do
    for Col := 1 to 16 do
    begin
      walk 200 entries of the path table; where the entry is non-zero, copy
      one byte from the 3200-byte dot table to $A000 at that offset
      Move(Dot[(Col-1)*200], Dot[(Col-1)*200 + 1], 164)   -- shift the trail
    end
end
```

The inner plot loop is hand assembler: it juggles DS between the path table,
the dot table and the caller's data segment, and reuses SI as both the table
index and the source offset.

---

## Scene 2 — segment `100f`, the rotating tile mesh

A grid of 25 x 25 animated tiles on a rotating rectangular mesh, scrolled up
the screen. Every tile plays the same 72-frame animation; which of two colour
maps it uses comes out of a cell grid, and where it lands comes out of a table
of 72 pre-rotated positions worked out before anything is drawn.

**The two .cel filenames are dead.** `LoadCel` (`100f:00ac`) takes a name —
`'p5.cel'` and `'p8.cel'`, still in the code segment at `100f:00fc` and
`100f:0103` — copies it into a 256-byte local, and never looks at it again.
The 256 bytes come from the NEUROSIS.DAT handle the caller already has open.
Neither file ships with the demo and neither is needed.

`100f:0000` is a clipped sprite blitter, hand assembler, 170 bytes. The sprite
carries its own size in its first two bytes and colour 0 is transparent.
Clipping moves the pointers rather than testing pixels: the top rows go with
one `MUL`, the two side margins become per-row skips held in the frame. It
reads four clip bounds straight out of DGROUP at `DS:$0002`..`$0008` and
indexes a row table at `DS:$96da`.

`100f:0173` precomputes everything: 72 sine and cosine values in 16.13 fixed
point biased by 8192, a 28 x 16 grid on a 15-pixel pitch, and then 72 x 26 x 16
pairs of rotated screen coordinates. `100f:0133` is `D * Pi / 180.0`.

---

## Scene 3 — segment `1118`, the fire

An 80 x 100 grid seeded along its bottom row with random 0 or 255. Each frame
every cell becomes the average of ITSELF, its two side neighbours and the one
BELOW, minus one, written one row UP — which is what makes the flames climb.
Each cell draws as a 4 x 2 block. A 29,120-byte picture is then laid over the
bottom 91 rows.

**The overlay does not skip transparent pixels.** `1118:01e3` advances DI only
when it actually stores, so a run of zeroes SHIFTS the rest of the picture
left rather than leaving a gap. Reading that as "if non-zero then plot at the
same offset" gives a different picture.

Before the fire there is a long title sequence (`1118:0486`): a 30 x 7 bitmap
slides in from the right in four stages — 320→190, 189→170, 169→160, 159→-30
— with three palette entries flickering at random, a fourth tracking the
position, and a spark walking diagonally and leaving a trail. The first two
stages flicker RED and ramp on a divisor of 20; the last two flicker BLUE and
ramp on 40. Then 500 frames of the spark alone, a white flash and a fade.

`1118:0000` is the scene's own copy of `SetRGB`, nested inside `Setup` —
it does not use the VGA unit's.

---

## Scene 4 — segment `11bb`, the credits

A vertical scroller seen in perspective. A 256 x 256 buffer holds the text;
one row of glyph pixels is fed into the bottom per frame and the whole 64K is
shifted up by 256 bytes. Screen rows 20..180 then each take one row of that
buffer and stretch it horizontally by a per-row amount, so the text narrows
towards the middle and flares at the top and bottom.

The stretch is `Round(255.0 / (320 - 2*margin) * 256.0)` in 8.8, where the 180
margins are read off the file. The render loop (`11bb:025f`) loads the data
segment from an IMMEDIATE — `MOV AX,164Eh` — to reach the margin table, then
swaps DS for the text buffer.

A row is only fed when the row counter reaches 19, so eighteen frames out of
nineteen scroll without adding anything. That is what slows the crawl.

The font is 23,436 bytes — 62 glyphs of 21 x 18 — **the same font part 004's
scroller uses**, with the same `(Ch-32)*378 + (Col-1)*18 + Row` layout.

The credits text is 113 lines on a 256-byte stride at `DS:$0C8A`, of which
only bytes 1..12 of each are ever read. Lines past 100 fall off the end of the
file image and are blank at run time. Extracted to `src/gen/P6TEXT.INC` by
`tools/emit_p6text.py`.

---

## What is byte-checked

    Blit       100f:0000   170 of 170   1 hole
    Overlay    1118:01e3    33 of  33   2 holes
    ScrollOut  1118:08a2    37 of  37   0 holes

Every hole is a DGROUP displacement. The remaining hand assembler in part 006
is inline inside compiled Pascal — the whoosh plot loop in scene 1, the tile
builder in scene 2, the fire diffusion in scene 3 — and is transcribed
verbatim with its addresses but not separately marked.

---

## The audit — ten real errors, in two rounds

The first round of testing gave: scene 1's dots going straight left, scene 2's
screen rubbish. The second round, after fixing those: scene 1 still wrong,
scene 3's city not appearing, scene 4's scroller drawing single lines instead
of letters. Re-reading every routine against the disassembly turned up ten
errors in two clusters.

### Round two — branch targets, read one instruction out

Three of these are the same slip: converting `0x1000:XXXX` to a segment offset
and landing on the wrong instruction.

- **`P6S1`'s plot loop re-enters at the DS RELOAD, not at the INC.**
  `1095:073e` jumps to `1095:070F`, which is `MOV AX,PathSeg / MOV DS,AX`. The
  body may have left DS pointing at the DOT table, so coming back one
  instruction later reads the next PATH entry out of the dot table — small
  byte values as word offsets, and the dots fly off in a straight line. That
  was the "straight to the left".
- **`P6S3`'s picture overlay advances DI on EVERY byte.** `1118:01f9` jumps to
  `1118:01FE`, which IS the `INC DI`. Reading it as landing after the INC held
  DI back on every transparent pixel and slid the picture apart — the city not
  showing.
- **`P6S3`'s fire clears AX ONCE, outside the loop.** `1118:099f` comes back to
  `1118:0959`, not to the `XOR AX,AX` at `0957`. So AH is not cleared per cell:
  the four `ADC AH,0` carry across cells and `SHR AX,2` shifts some of that
  back into AL. Clearing AX inside the loop puts the fire out.

And one inverted test:

- **`P6S4` feeds a glyph row when the counter is NOT 19.** `11bb:017b` is a
  `JNZ` INTO the feed. Reading it the other way up feeds only row 19 of every
  glyph — which is exactly "single lines, not fonts".

**The byte check did not catch any of these**, because a branch target is one
byte and looked like an ordinary displacement. `tools/asmverify.py` now refuses
a one-byte hole sitting immediately behind a short jump or `LOOP`.

### Round one — absolute addresses and index arithmetic

### The first six


After the first pass, scene 1's dots went straight left and scene 2's screen
was rubbish. Re-reading every routine against the disassembly turned up six
errors, five of which are the same mistake in different clothes.

**COPYING AN ABSOLUTE ADDRESS OUT OF THE ORIGINAL.** The binary is full of
`MOV AX,[6]` and `MOV DI,[BX+96DAh]` and `MOV AX,164Eh`. Those are offsets and
segments in the ORIGINAL's data segment. Transcribing them literally compiles
cleanly and reads whatever our own build happens to have there.

- **`P6S2.Blit`** read its four clip bounds from `DS:$0002..$0008` and its row
  table from `DS:$96DA`. The bounds are initialised data — `5, 315, 5, 195`,
  a five-pixel border — and the row table is the VGA unit's `YOfs`. This alone
  turned scene 2's screen to rubbish.
- **`P6S4.Render`** did the same twice: `MOV SI,942Ch` for the margin table and
  `MOV AX,164Eh` for the data segment.
- **`P6S2.Setup`** reached the cell shape table with
  `absolute $164E:$000A`. It is 2,048 bytes of initialised data, now extracted
  to `gen/P6SHAPE.INC` by `tools/emit_p6shape.py`.

The other three:

- **`P6S2.BuildTables` had the Y rotation backwards.** `100f:02c9` pushes the
  `X*Sin` term and `100f:0307` SUBTRACTS it from `Y*Cos`. I had
  `X*Sin - Y*Cos`, which mirrors the mesh about the wrong axis.
- **`P6S2`'s tile builder used DX for two things.** `DX` is the outer loop
  counter; the frame base lives in a local at `[BP-$15]`. I had conflated
  them, so every tile was built from the wrong bytes.
- **`P6S3` indexed its fire grid and title bitmap one element in.** The binary
  writes `[$73b9 + I*80 + J]`, so element [1,1] is 81 bytes into the variable,
  not at its start. Declaring `array[1..100,1..80]` and writing `Grid[I,J]`
  shifts everything by 81 bytes and puts the seed row one byte out. The grid is
  now a flat array indexed exactly as the binary indexes it.

And one thing the audit corrected rather than fixed: **scene 3's title bitmap
and its "210 bytes read and never used" are the same object.** `1118:04f8`
reads `[$932f + B*30 + A]`, and `$932f + 31` is exactly `$934e` — where the
210 bytes land. 7 x 30 is 210.

### Scene 1 — a register that cannot survive a Pascal call

`1095:067d` keeps its running index in **SI** across the whole lane loop,
including across the `Move` that shifts each lane. It never reloads it. So
what the next lane starts from is `Move`'s own side effect: source is one
below destination here, so Turbo Pascal's `Move` takes its backward path and
comes out at `Source - 1`. That is why lane L+1 walks lane L's stretch of the
tables rather than its own.

A register cannot be relied on to survive a Pascal call in the reconstruction,
so the index is now an explicit variable and the value `Move` leaves is
written down rather than assumed.

`BuildPath` itself was checked numerically and is right — lane 1 runs from
(290, 17) to (1, 192), which is the diagonal it should be.

---

## Still open

- `1095:01a0`, the floating-point path builder, is transcribed as Pascal from
  the disassembly but its Bresenham is compiled code, so nothing byte-checks
  it. The three code-segment constants (2.0, 1.0, 0.005) and the 1.3 starting
  threshold were read out of the image.
- None of the four scenes has been run. The harnesses are `TP6S1`..`TP6S4`
  and `TPART6`.
