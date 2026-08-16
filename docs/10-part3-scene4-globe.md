# Part 3, Scene 4 — the globe

`Demo_Scene4` at `119d:0211`. Reconstruction: [`src/PART3_GLOBE.PAS`](../src/PART3_GLOBE.PAS).

## What it is

A picture show with cross-fades that alternates a title image with three
others, and between each pair runs a **rotating globe**: a scrolling cloud band
mapped onto a sphere.

There is **no sphere maths at run time**. The geometry was baked at build time
into two tables of 16-bit offsets, and a frame is just:

```pascal
for i := 1 to 22996 do
  Mem[$A000 : Dst[i]] := Mem[VirtScr : Src[i]];
```

followed by scrolling the source band one pixel left. The scroll is what makes
the globe appear to turn.

## Assets

All from `$0C0E2E`, 92,756 bytes in three reads:

| File | Size | Role |
|---|---:|---|
| [`scene4_palette.pal`](../assets/part003/scene4_palette.pal) | 768 | shared by all four images |
| [`globe_src_offsets.bin`](../assets/part003/globe_src_offsets.bin) | 45,994 | source offsets into the virtual screen |
| [`globe_dst_offsets.bin`](../assets/part003/globe_dst_offsets.bin) | 45,994 | destination offsets into video memory |

The four full-screen images:

| File | DAT offset | Content |
|---|---|---|
| [`scene4_screen1.png`](../assets/part003/scene4_screen1.png) | `$0D7882` | "ReAl TiMe" gold lettering — shown three times |
| [`scene4_screen2.png`](../assets/part003/scene4_screen2.png) | `$0E7282` | city skyline against clouds |
| [`scene4_screen3.png`](../assets/part003/scene4_screen3.png) | `$0F6C82` | two figures against clouds |
| [`scene4_screen4.png`](../assets/part003/scene4_screen4.png) | `$106682` | fiery DETH logo |

Generated coverage maps, not present in the demo:

| File | Shows |
|---|---|
| [`globe_warp_dst.png`](../assets/part003/globe_warp_dst.png) | a filled **disc** — 22,996 pixels |
| [`globe_warp_src.png`](../assets/part003/globe_warp_src.png) | a **300×150 band**, dense at left and right — 16,316 pixels |

## Why we know it is a sphere

- The destination coverage is a **disc**.
- The source coverage is a rectangle sampled **many-to-one at the edges**:
  22,996 destinations drawn from only 16,316 distinct sources. That
  compression at the limb is exactly sphere foreshortening.
- The scrolled band — rows 1..150, 300 bytes wide — matches the source
  coverage map **exactly**, which says the tables and the scroll were authored
  together.

## One palette, four images

`Globe_LoadTables` reads the palette **once** at the start of the scene. All
four images fade to the same 256 colours, which is what lets them cross-fade
into one another without a palette reload — only the pixels change.

This also fixed a rendering bug in the extracted assets: the four screens were
initially carved with a palette carried forward from an earlier region, which
made the city look plausible but was not the demo's own. `build_assets.py` now
has an explicit `PALETTE_OVERRIDES` map for cases where a screen's palette is
loaded by a different region than its own.

## The fades

`Palette_FadeIn` (`119d:0064`) reads each DAC entry back with `GetRGB`, steps
any channel below its target up by one, and writes it out. `Palette_FadeOut`
(`119d:0000`) is the same shape but steps every non-zero channel down toward
black, so it needs no target table.

Both are called 64 times — one step per frame, which is the full 6-bit DAC
range. Every loop is guarded by `KeyPressed` so the scene can be skipped
mid-fade.

## Structure

```
load palette + both offset tables
blank the DAC
repeat three times:
  show the title image flat   -- fade in, hold 1s, fade out
  load the next image into the VIRTUAL screen
  blank the visible screen
  fade in  + run the globe    (64 frames)
  fade out + run the globe    (64 frames)
```

Note the asymmetry: the flat images are copied to `$A000` and displayed
directly, while the globe textures are left in the virtual screen and only ever
reach the visible screen through the scatter blit.
