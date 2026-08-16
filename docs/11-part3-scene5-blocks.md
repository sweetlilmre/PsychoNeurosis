# Part 3, Scene 5 — the block dissolve

`Demo_Scene5` at `11f3:01ac`, body at `11f3:0017`.
Reconstruction: [`src/PART3_BLOCKS.PAS`](../src/PART3_BLOCKS.PAS).

## What it is

An image is revealed by repeatedly brightening 10×10 pixel blocks in a
precomputed order, then hidden again by running the same order backwards.

**Nothing is ever drawn.** The pixels are already in video memory when the
scene starts. Each frame simply adds 1 to the pixel *values* of 72 blocks, and
since the palette is a ramp, higher value means brighter. Run it 91 times and
the picture emerges.

## Assets

| File | Size | Role |
|---|---:|---|
| [`blocks_order.bin`](../assets/part003/blocks_order.bin) | 13,104 | 6,552 16-bit screen offsets |

The size identifies the layout: **91 × 8 × 9 × 2 = 13,104** exactly, matching
the three nested loops (91 frames, 8 columns, 9 rows) and the address strides
in the original (`$90`, `$12`, `2`).

## How it works

```pascal
for Frame := 0 to 90 do
  for C := 1 to 8 do
    for R := 1 to 9 do
      { add 1 to every pixel in the 10x10 block at Order[Frame, C, R] }
```

then `Delay(1000)`, then the identical walk with all three loops reversed and
`Dec` instead of `Inc`.

The reverse pass being an exact mirror matters: it guarantees the screen
returns to its starting state with no accumulated error, so the scene can hand
off cleanly to whatever follows.

## Why it looks gradual

6,552 block positions × 100 pixels = 655,200 increments over a 64,000-pixel
screen, so an average pixel is touched about **ten times**. The reveal is a
brightness build-up rather than a hard on/off wipe.

## What `Blocks_Run` actually does

The scene **clears the virtual screen first**, so nothing is inherited from
whatever ran before — the image is built here, by arithmetic on pixel values
rather than by drawing anything.

The effect works on **72 blocks of 10×10 pixels** (8 × 9, screen stride `$140`),
whose addresses come from a precomputed pointer table indexed
`[step][col][row]` with strides `$90`, `$12` and 2.

Then:

1. **91 steps** (0..90), each **adding 1** to every pixel of every block, in
   row-major order;
2. a `Crt_Delay`;
3. **91 steps** each **subtracting 1**, walking all three loops backwards.

So the picture ramps up through the palette and back down again, and the ramp
built over entries 1..221 is what turns a pixel *count* into a colour. The image
is literally painted by counting.

## The palette ramp

Read off the patched x87 stream at `11f3:0072..00a7`. The decompiler is no help
— it renders the traps as argument-less calls — but the **disassembly** is clean
once `fpfix.py` has run:

```
FILD  word ptr [BP-8]              ; I
FLD   extended double ptr CS:[$0D] ; 0.2
FMULP                              ; I * 0.2
call  Round                        ; -> DX:AX
ADD   AX,$13                       ; + 19
```

`VGA_SetPalette` (`12f8:0064`) takes `(Index, R, G, B)` — the first pushed goes
to port `$3C8` and the rest to `$3C9` in order — and the loop pushes `I, 0, 0,`
then the computed value. So the ramp is on **blue**:

```pascal
for I := 1 to 255 do SetPalette(I, 0, 0, 0);                    { blank }
for I := 1 to 221 do SetPalette(I, 0, 0, Round(I * 0.2) + 19);  { blue ramp }
```

The constant at `CS:$000D` is exactly **0.2** (`cd cc cc cc cc cc cc cc fc 3f`),
so the ramp is `I/5 + 19`. It starts at 19 and reaches **63 — the top of the VGA
DAC — at I = 220**, one short of the end of the loop.

The whole scene is one blue gradient, and a pixel's colour is simply how many
times it was incremented.

## Open

- Nothing outstanding.
