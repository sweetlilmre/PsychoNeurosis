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

## Building it back: the manifest and MKDAT

Carving is only half of it. Reading a blob somebody else built needs the map;
BUILDING one needs the map to be the only copy of itself, and the hardcoded
`Seek` constants are the opposite of that — the same offset written out in
seven programs, where moving any file silently invalidates every offset after
it. The reads still succeed. They just return the wrong bytes.

So the blob is now built from a manifest, and the offsets are generated:

    assets/NEUROSIS.MAN     the ordered list of files, and nothing else
    src/dos/MKDAT.PAS       concatenates them, emits src/gen/DATOFS.INC
    src/dos/MKDAT.BAT       compiles and runs it at the DOS prompt
    tools/mkmanifest.py     regenerates the manifest from the recovered map
    tools/mkdat_mirror.py   a host mirror of MKDAT, so it can be checked here

**The manifest holds the ORDER and not the offsets.** Offsets are a consequence
of the order and the file lengths, so putting them in the manifest would be a
second copy of a derived fact, and a second copy is a thing that can disagree.
`MKDAT` computes them, and writes each file's offset and length out as a pair
of Pascal constants.

**The constants are UNTYPED, and that is what makes this free.** An untyped
constant in Turbo Pascal is a compile-time value folded into the instruction
stream at the point of use: it occupies no storage, so a unit can include the
whole set and use two of them. `Seek(F, DAT_P1_INTROSCR)` and `Seek(F,
$02AEE0)` compile to identical bytes — verified, not assumed: part 001 was
repointed at four of them and all ten targets still rebuild byte-identical,
with part 001's data image unchanged at 752 bytes. A TYPED constant
(`X : LongInt = $02AEE0`) would allocate four initialised bytes in DGROUP,
move every variable after it and change the data image of every part that
included the file. `DATOFS.INC`'s own header says so, where somebody editing it
would look.

**Every asset filename is 8.3**, and that is not tidiness. `MKDAT` is a
real-mode DOS program and DOS cannot open `asphyxia_logo.raw`. The names were
shortened for it — `ASPHLOGO.RAW`, `TUNNPLN0.RAW`, and the offset-coded ones as
six hex digits plus an index letter (`03A8E0A.BIN`) — and
`tools/build_assets.py` produces them that way, so a regeneration keeps them
8.3.

**What the round trip proves.** `tools/mkmanifest.py` refuses to write a
manifest unless every entry names a file that exists, whose length equals the
`BlockRead` size the map records, and whose bytes equal that slice of the 1994
file. Then `mkdat_mirror.py` concatenates the manifest and compares: **85
files, 1,718,189 of 1,718,189 bytes, identical.** `MKDAT` itself takes an
optional reference blob and does the same comparison in DOS, which is the check
that matters — a manifest in the wrong ORDER produces a blob of exactly the
right LENGTH that every part misreads.

`MKDAT` is deliberately **not** in `build.toml`. That file's output is what the
ten byte-identical artefacts are measured from, and `build.py build.toml` should
go on meaning "build the demo".

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

- `assets/part001/ASPHLOGO.PNG` — the **ASPHYXIA logo**, chrome/green with reflection
- `assets/part002/house_screen1.png` — a **house exterior**, brick and corrugated roof
- `assets/part004/LEMSPR1.PNG` — the **Lemming character** with a thought bubble
- `assets/part003/TUNNEL.PNG` — the tunnel texture
- `assets/part003/S4SCRN1.PNG` — **"ReAl TiMe"** gold 3-D lettering

Images decoding correctly against their paired palettes is independent
confirmation that both the offsets and the sizes are right.
