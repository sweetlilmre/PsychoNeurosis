# The VGA unit

Segments `12f8` and `1192` (in part 003) are a shared graphics unit used by
every scene. **It is hand-written assembler throughout** — see
[09-hand-assembler.md](09-hand-assembler.md) for how we know.

Reconstruction: [`src/VGA.PAS`](../src/VGA.PAS).

## Contents

| Routine | Address | What it does |
|---|---|---|
| `PutPixel` | `12f8:0048` | plot via a precomputed `y*320` row table at `DS:$E772` |
| `SetRGB` | `12f8:0064` | one DAC entry: index to `$3C8`, R/G/B to `$3C9` |
| `GetRGB` | `12f8:007f` | read one DAC entry back via `$3C7` |
| `WaitRetrace` | `12f8:009f` | poll `$3DA` bit 3 |
| `CopyScreen` | `12f8:00ad` | 64,000-byte copy (`REP MOVSW`, 32,000 words) |
| `ClearScreen` | `12f8:00c9` | 64,000-byte fill (`REP STOSW`) |
| `BuildRowTable` | `1192:0000` | `RowOfs[i] := 160 * i`, i = 0..799, into `DS:$BEC6` |
| `SetMode` | `1192:002a` | mode 13h, then unchain to Mode-X |
| `SelectPlane` | `1192:0087` | Sequencer register 2 (Map Mask) |

## Two details worth knowing

**`WaitRetrace` waits twice.** It first waits for retrace to *end*, then for it
to *begin*, so the caller always gets a full blanking interval rather than
joining one already in progress.

**`CopyScreen` is used two different ways.** As a mode 13h page flip (virtual
screen → `$A000`), and in Scene 1 to push one 64,000-byte Mode-X *plane* into
video memory with the Map Mask already set. Same routine, quite different
meaning — don't read the name as "blit a screen".

## Mode-X setup

`SetMode` is the textbook sequence:

```
INT 10h mode 13h
Seq 4      chain-4 off, extended memory on
GC 5       odd/even off
GC 6       chain odd/even off
Map Mask   all four planes, then clear 64K (which wipes all 256K)
CRTC $14   doubleword mode off
CRTC $17   byte mode on
CRTC $13   logical width := DS:$76B6
```

`CRTC $13` is the **Offset register**, in units of 8 pixels. Part 003 writes 80,
giving a **640-pixel logical line**. That single value is what makes Scene 1's
hardware panning possible.

Scene 3 additionally calls `VGA_Set400Lines` (`1139:02f2`), which clears the low
five bits of **CRTC register 9** (Maximum Scan Line) to disable double-scanning,
turning the screen into 320×400.

## Row tables

There are two, and conflating them will produce nonsense:

- `DS:$E772` — 200 entries of `y*320`, used by `PutPixel` for the **mode 13h**
  software screen.
- Scene 1 and Scene 3 build their own tables of `y*160`, because a Mode-X
  logical line is 160 bytes **per plane**, not 320.

## The row-offset table

`1192:0000` fills `RowOfs : array[0..799] of Word` at `DS:$BEC6` with
`RowOfs[i] := 160 * i`. The multiplier is the byte at `DS:$76B6` — **80**, the
Mode-X plane stride for a 320-pixel row — shifted left once by the code itself
(`MUL` then `SHL AX,1`).

A 160-byte row stride is **640 pixels** in Mode-X, and 400 such rows come to
exactly 64,000 bytes: one full VGA plane. The table is declared at 800 entries,
twice what a 400-row screen needs, so indexing never has to be bounds-checked.

That is what makes the panning scenes possible — the logical screen is wider
than the display, and the CRTC Offset register plus a start address into this
table is the whole pan.
