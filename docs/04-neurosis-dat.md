# NEUROSIS.DAT

1,718,189 bytes. **No header, no directory, no index.** It opens straight into a
raw 6-bit VGA palette.

Every part does the same thing: `Assign('neurosis.dat')`, `Seek` to a hardcoded
absolute offset, `BlockRead` a fixed count. Those constants are the only asset
map that exists.

## Recovering the map

Once `RTL_FileAssign` / `RTL_FileSeek` / `RTL_FileBlockRead` are named in every
part ([03-borland-rtl.md](03-borland-rtl.md)),
`tools/ghidra/DumpDatAccess.java` sweeps their call sites and reads back the
immediates pushed just before each call. Borland pushes arguments left to
right, so `Seek(f, n)` puts `n` as high word then low word directly before the
`CALLF`.

## The map is provably complete

`tools/datmap.py` sorts the seek targets and checks each region's declared read
sizes against the distance to the next seek:

```
26/26 regions tile exactly against the next seek
declared bytes: 1,718,189 of 1,718,189 (100.0%)
```

Every region's reads exactly fill the space to the next one, and the final
region ends precisely at EOF. An error anywhere would break the tiling, so this
is a strong correctness check on the whole extraction.

It also settled three ambiguities, because only one arrangement tiles:

- **`Assign`/`Seek` and the `BlockRead`s often sit in different routines** —
  part 001's seek is in `FUN_1082_056f`, the reads in `FUN_1082_0000`.
- Part 003's `$11EEC0` read of 3,136 bytes is inside a **4-iteration loop**,
  matching `Demo_Scene7` freeing exactly four 3,136-byte buffers.
- Part 006's `$1781E5` region is read by two cooperating routines.

## Layout

Ordered by demo part, with one part-003 region parked at the end.

| Range | Part | Contents |
|---|---|---|
| 0 – 245,302 | 001 | logo, palettes, 2 screens, small tables |
| 245,302 – 531,062 | 002 | palette + 4 screens + 12,412 |
| 531,062 – 1,190,094 | 003 | tunnel plane set, 6 further screens, 36,414 |
| 1,190,094 – 1,392,101 | 004 | Lemmings sprite set (20 reads, 202,007 B) |
| 1,392,101 – 1,524,709 | 005 | 3×1024 tables, 2 screens |
| 1,524,709 – 1,642,879 | 006 | 4 regions, several palettes |
| 1,642,879 – 1,705,085 | 007 | `lemend.flc`, 62,206 B |
| 1,705,085 – EOF | 003 | 13,104 B |

Full per-region detail is in [`assets/README.md`](../assets/README.md).

## Not everything is in the blob

Part 003's Scene 3 never appears in the DAT map because its 3-D shape data is
**compiled into the executable** as typed constants in DGROUP. Absence from
this map is a signal to go looking in the data segment, not evidence that a
scene is procedural.

## Carving

`tools/build_assets.py` slices the blob into `assets/` and writes PNGs directly
(indexed colour, pure-Python zlib — no imaging library). VGA palettes are 6-bit
and scaled to 8. Where a screen's palette is loaded by a different routine, the
most recent palette in file order is carried forward.

**Mode-X plane sets are not four images.** Part 003's four 64,000-byte reads at
`$081A76` are the four *planes* of one 640×400 image; rendering a plane at 320
wide produces a phantom second centre. The builder suppresses per-plane PNGs and
writes the de-interleaved composite instead.

## Verified by eye

- `assets/part001/asphyxia_logo.png` — the **ASPHYXIA logo**, chrome/green with reflection
- `assets/part002/house_screen1.png` — a **house exterior**, brick and corrugated roof
- `assets/part004/lemming_sprite1.png` — the **Lemming character** with a thought bubble
- `assets/part003/tunnel_640x400.png` — the tunnel texture
- `assets/part003/scene4_screen1.png` — **"ReAl TiMe"** gold 3-D lettering

Images decoding correctly against their paired palettes is independent
confirmation that both the offsets and the sizes are right.
