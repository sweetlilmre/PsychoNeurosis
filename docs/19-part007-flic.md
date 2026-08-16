# Part 007 — the FLIC player

`NEUROSIS.007`, MOD *The Deth March* (reused). 125 functions.

A complete **Autodesk Animator FLIC player**, playing `lemend.flc` — 62,206
bytes at `$19117F`, the end-of-demo Lemmings animation.

## The player

`FLIC_Play` (`100f:0453`) is a textbook FLIC reader:

1. Read the 128-byte file header.
2. Check the magic word — `$AF12`, which is **FLC** (`$AF11` would be FLI).
3. Check width = 320 and height = 200; otherwise print
   `Error : Sorry, only 320x200 flics supported.` and halt.
4. For each frame: read the 16-byte frame header, then loop over its chunks,
   each with a 6-byte header (size, type).

## Chunk types handled

| Type | Name | Handling |
|---:|---|---|
| 4 | `FLI_COLOR256` | `FLIC_Color256` |
| 7 | `FLI_SS2` | via function pointer |
| 11 | `FLI_COLOR64` | `FLIC_Color64` |
| 12 | `FLI_LC` | via function pointer |
| 15 | `FLI_BRUN` | via function pointer |
| 16 | `FLI_COPY` | via function pointer (size fixed up by +2) |
| 18 | `PSTAMP` | skipped |
| other | | halt |

That is the full standard set. The four delta/RLE decoders are reached through
a table of procedure pointers at `DS:$340D`, which is why they are indirect
calls rather than direct.

The player also reprograms the PIT (ports `$40`/`$43`) for frame timing —
consistent with part 007 being the only part with timer writes.

## Assets

[`assets/part007/lemend_flc.flc`](../assets/part007/lemend_flc.flc) — extracted
verbatim, 62,206 bytes, playable in any FLIC viewer.
