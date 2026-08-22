# Part 001 — the intro

`NEUROSIS.001`, MOD *In awe of you.* 196 functions, the most of any part.

**Status: all five scenes understood.** Reconstruction: [`src/PART1_INTRO.PAS`](../src/PART1_INTRO.PAS).

> **Angles in part 001 are in TENTHS of a degree** — wrap values 3600 (`$E10`)
> and 3590 (`$E06`), steps 60 (6.0°) and 20 (2.0°). Part 003 used whole
> degrees. Easy to misread a 3600 wrap as a sine-table size.

## Main body

Identical architecture to part 003: twelve Borland unit inits at `1000:0000`,
then the main body at `1000:003c`, five scenes each followed by a keyboard
flush, then the music fade-out.

```pascal
begin
  VirtScr_Alloc;               { 1491:0006 }
  SetMode13h;                  { 1491:0000 }
  DemoVT_Init; ...             { 1532:0000, :006a, :0093, :004e }

  Demo_Scene1;  FlushKeys;     { 1012:0678  logo + bouncing sprites }
  Demo_Scene2;  FlushKeys;     { 1082:056f  ASPHYXIA PRESENTS }
  Demo_Scene3;  FlushKeys;     { 10e3:0206  mosaic }
  Demo_Scene4;  FlushKeys;     { 1107:0977  3-D text banner }
  Demo_Scene5;  FlushKeys;     { 12c5:0a89  vector objects + wipe }

  { music fade: save volume, step down to 0, stop, restore }
  VirtScr_Free;
  Halt(0);
end.
```

The VGA unit lives at segment `1491` here (it was `12f8` in part 003) and is
**larger** — 1002 bytes against 266 — because it also carries a Bresenham line
drawer at `1491:0048`, which part 003's copy does not have.

## Scene 1 — logo and bouncing sprites

`Demo_Scene1` `1012:0678`, effect at `Bounce_Run` `1012:03e3`.

Loads the ASPHYXIA logo (palette + 320×200 screen from DAT `$000000`), draws
two black vertical lines at x=319 and x=318 — tidying the right edge — blits,
then runs **ten bouncing sprites**:

```pascal
for I := 1 to 10 do
begin
  DX[I] := Random(3) + 2;   DY[I] := Random(3) + 2;
  X[I]  := Random(250) + 30; Y[I] := Random(150) + 30;
end;
```

Each frame: draw all ten, blit, erase all ten in reverse order, then move and
bounce (X clamped 21..299, Y clamped 21..179). Erase-in-reverse means
overlapping sprites restore correctly.

## Scene 2 — "ASPHYXIA PRESENTS"

`Demo_Scene2` `1082:056f`, effect at `Title_ShowWord` `1082:02fd`.

The two words are Pascal string constants at `1082:055E` and `1082:0567`; the
scene calls the same routine twice, once per word. It copies the string to a
local, then runs a floating-point animation with a counter falling from 80 to
−18, revealing one character at a time, followed by a 100-frame outro.

Reads 111,072 bytes from DAT `$00FD00`: a palette, a 31,200-byte buffer
(indexed in units of `$C30` = 3,120, so ten entries), a 320×200 screen, and a
15,104-byte buffer. A 5,200-byte working buffer is allocated separately.

The 31,200-byte buffer is **ten 65×48 frames of a flaming comet** — 65 × 48 =
3,120, exactly the indexing stride. `Sprite_BlitClipped` (`1082:0128`) blits
them with zero-as-transparent and clipping against four bounds held at
`DS:$04/$06/$08/$0A`, adjusting pointers and counts before the copy loop rather
than testing per pixel.

So the scene is a comet streaking across while the letters of each word appear
in its wake.

The **15,104-byte buffer is a font**: 15104 / 256 = **59 characters** of 16x16,
the same character count as scene 4's 8x8 font. `1082:0200` draws a character
two rows at a time into a 26-byte-stride working buffer in colour `$79`.

## Scene 3 — mosaic

`Demo_Scene3` `10e3:0206`, effect at `Mosaic_Run` `10e3:00bb`. **Fully decoded.**

A progressive pixelate, in and out. The routine builds a table of block sizes
and matching shift counts:

| Block | Pixels | Shift | = divide by |
|---|---:|---:|---:|
| 4×4 | 16 | 4 | 16 |
| 8×8 | 64 | 6 | 64 |
| 16×16 | 256 | 8 | 256 |
| 32×32 | 1024 | 10 | 1024 |
| 64×64 | 4096 | 12 | 4096 |

For each level it sums every pixel in a block and writes `sum shr shift` — the
**average** — back over the whole block. Levels run 5 down to 0, `Delay(20)`
between; at the turnaround it holds `Delay(5000)` and then runs back up.

The shift is exactly `log2(size²)`, so the averaging is a pure shift with no
division anywhere.

## Scene 4 — 3-D text banner

`Demo_Scene4` `1107:0977`, point building at `Banner_BuildPoints` `1107:07a2`.

**The 3-D object is built from ASCII art.** Eight 256-byte line buffers are
filled with `$FF`, then text is loaded into them; each character is compared
against two marker characters and every match becomes a 3-D point:

```
x := (col - 1) * 10 - 90;
y := (row - 1) * -8 + 32;
```

capped at `$90` = 144 points.

`Text_ShowString` (`1107:0600`) then does the display: for every character of
the message it builds an 8×8 point grid from a **59-character font** (3,776
bytes = 59 × 64, loaded from `$03A8E0`) and spins it through 8 steps of 6°. So
the message arrives one rotating letter at a time rather than scrolling.

The welcome scroller text lives in this segment at `1107:070A`:

> `HELLO AND WELCOME TO ASPHYXIAS FIRST MEGADEMO, PSYCHO NEUROSIS!!! NOW SIT
> BACK AND ENJOY!!!`

## Scene 5 — vector objects and wipe

`Demo_Scene5` `12c5:0a89`, effect at `Vector_Run` `12c5:0870`.

The scene body's order matters at the 4→5 transition (plan `part1-s4s5-palette`): it flushes the keyboard inline, blanks the screen with `ClearScreen($A000, 0)`, allocates and clears the 64,000-byte work buffer (`12c5:0a60`), and only THEN does `Vector_Load` (`12c5:0413`) rewrite the whole DAC — so the palette swap happens over black. A reconstruction that loads first recolours scene 4's still-displayed final frame for the whole file read and backdrop build, which is exactly the glitch the first observation run reported. `Vector_Load` reads the palette into a stack local and hands it to `VGA.SetPalette768` (`1491:01c2`); the scene ends with `FreeMem(Work, 64000)`.

Two 3-D objects compiled into DGROUP as integer coordinate triples, converted
to Real at load time by `Math_IntToReal` (`1483:0000`) into 12-byte records:

| Object | DGROUP | Points | What it is |
|---|---|---:|---|
| [`vector_globe`](../assets/part001/vector_globe.png) | `DS:$01A8` | 36 | three orthogonal rings — a wireframe **globe**, ±50 on all axes |
| [`vector_logo_a`](../assets/part001/vector_logo_a.png) | `DS:$001C` | 48 | a circled **"A"** — the Asphyxia logo mark, flat (Z = 0 throughout) |

Each is spun for 240 frames at 2.0° per frame before the next.

After rendering, the scene ends with a **vertical wipe** — repeatedly moving
the screen down by 640 bytes (two rows) and zeroing the top, 100 steps to clear
64,000 bytes.

## Assets

| File | DAT offset | Content |
|---|---|---|
| [`asphyxia_logo.png`](../assets/part001/asphyxia_logo.png) | `$000000` | the logo, chrome/green with reflection |
| `00FD00_*.bin` | `$00FD00` | scene 2 buffers |
| [`intro_screen.png`](../assets/part001/intro_screen.png) | `$02AEE0` | scene 3's mosaic source |
| `03A8E0_*.bin` | `$03A8E0` | scene 4 banner data |
| `03BB02_*.bin` | `$03BB02` | scene 5 |

### The two 49-byte reads

`Banner_Load` (`1107:0025`) reads two 49-byte blocks, copies one to a scratch
address and then **replicates it into 144 records of 51 bytes** — 49 bytes of
template plus two bytes set to 7.

144 is exactly the `$90` point cap in `Banner_BuildPoints`, so these are the
per-point initial-state templates for the 3-D text.

### Scene 5's renderer

`12c5:061D` draws each object in two passes: the second half of the point list
straight, and the first half with Y decremented by 7 — an offset copy, which
reads as a drop shadow.

## Scene 5's transform helpers

| Address | Name | What it does |
|---|---|---|
| `12c5:03a2` | `Obj_Translate` | converts three Integer deltas with `Math_IntToReal` and **adds** them into the object's three 4-byte position fields at `+$4B0`, `+$4B4`, `+$4B8` — an accumulating world position, not an absolute set |
| `12c5:02e3` | `Obj_TransformAll` | builds sin/cos for the three rotation angles into `DS:$AAA6`/`$AAAA`, `$AAAE`/`$AAB2`, `$AAB6`/`$AABA`, loads the position from `+$4B0`, then walks the point count at `DS:$AAC8` calling the per-point rotate/project at `12c5:01b0` — 12 bytes per point |

## Scene 2's placement maths

This one really is floating point — the only effect in the demo that is. Read
instruction by instruction off the patched x87 stream at `1082:02fd`.

Three state variables live in the stack frame as **Borland Real48** (not an x87
format — it is the software `Real` that Turbo Pascal variables use: byte 0 is
the exponent biased by 129, bytes 1..5 the mantissa with the sign in the top
bit). Their initial values are `CometX = -48.0`, `Frame = 1.0`, `Phase = 1.0`.

The four constants are ordinary FP operands in the code segment, decoded with
[`tools/fpconst.py`](../tools/fpconst.py):

| Address | Format | Value | Role |
|---|---|---:|---|
| `CS:$02E7` | single | 2.0 | added to `Phase` **and** to `CometX` |
| `CS:$02EB` | single | 15.0 | `Phase` wrap → reveal the next character |
| `CS:$02EF` | ext80 | 0.3 | added to `Frame` |
| `CS:$02F9` | single | 10.0 | `Frame` wrap |

```pascal
Phase := Phase + 2.0;
if Phase > 15.0 then begin Phase := 1.0; Inc(CharIdx) end;
Frame := Frame + 0.3;
if Frame > 10.0 then Frame := 1.0;
CometX := CometX + 2.0;
```

Which gives the three timings directly:

- **a character is revealed every eight frames** — `Phase` steps 1, 3, 5, 7, 9,
  11, 13, 15 and wraps on the ninth add;
- **the comet's ten frames cycle every ~31 frames** — 0.3 per frame up to 10.0,
  with `Trunc(Frame)` selecting the sprite;
- **the comet sweeps diagonally up and right** — `x` runs −48 to 148 while
  `y = Count * 4` runs 320 down to −72 across the 99 frames.

Only the character currently animating is drawn by this routine;
`Trunc(Phase)` is its animation step, and the already-revealed ones are redrawn
by `1082:01d0`.

## Open

- Nothing outstanding.
