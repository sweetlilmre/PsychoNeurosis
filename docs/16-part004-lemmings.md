# Part 004 — the Lemmings game

`NEUROSIS.004`, MOD *The Deth March*. 121 functions, **no floating point at all**.

Reconstruction: [`src/PART4_LEMMINGS.PAS`](../src/PART4_LEMMINGS.PAS).

This is not a scroller with lemming decorations. It is a **working Lemmings
engine** — pixel-accurate terrain collision, destructible terrain, a ten-state
skill machine — playing a scripted level that solves itself, with the scroll
text running alongside.

That is the "new twist" the text promises:

> ` FOR THOSE OF YOU THAT REALLY HATE LONG, BORING SCROLLIES, WE DECIDED TO PUT
> A NEW TWIST ON IT ***      BUT IF YOU DONT LIKE LEMMINGS, THEN THERE IS NO
> HOPE, HIT ANY KEY NOW. THE ANY KEY? THE ONE ON THE SIDE MARKED -POWER-
> ***     `

237 characters, matching the `$ED` bound the code checks.

## The lemming record

25 concurrent slots (`$19`) of **21 bytes** (`$15`), array base `DS:$02FC`, so
slot *N* lives at `DS:$02FC + N*$15`. Derived from `Lem_Spawn`, which writes
every field, and `Lem_SetState`:

| Offset | Field | At spawn |
|---:|---|---|
| +0 | X | 35 |
| +2 | Y | 60 |
| +4 | *unused* | 0 |
| +6 | animation frame | 1 — reset to 1 by `Lem_SetState` |
| +8 | tick | 0 — reset to 0 by `Lem_SetState` |
| +10 | countdown | 0 |
| +12 | alive flag (byte) | 1 — this is the free-slot test |
| +13 | **state** (byte) | 2 — written by `Lem_SetState` |
| +14 | direction (byte, ±1) | 1 |
| +15 | fall distance (byte) | 0 |
| +16, +18, +20 | scripted target X, Y, state | 35, 60, 2 |

The countdown at +10 works in both directions: positive values tick **down**,
and reaching 1 sets state 3; negative values tick **up**, and reaching −1 removes
the lemming. That is how the death animations time themselves out.

## Terrain collision is done against the screen

There is no separate collision map. `VGA_GetPixel` (`11e3:0048`) reads the
**virtual screen**, and solidity is a Pascal **set membership test** on the
pixel's colour (`RTL_0b41`). So the level artwork *is* the collision data, and
digging — drawing in colour 0 — makes the terrain destructible for free.

There are **two** set constants, held as 32-byte literals in the code segment
(`CS:$1496` and `CS:$14B6` in segment `1005`, reached through a `CS:` override,
not in DGROUP):

| Set | Colours |
|---|---|
| **ground** — can you stand on it | `$04..$05, $0F, $15..$18, $1D, $1F, $33, $36, $3E..$40, $42..$47, $4D..$52` |
| **wall** — does it block you | the same, **plus `$20..$29`** |

The difference is exactly the `$20..$29` band: it blocks movement but you cannot
stand on it, and touching it kills you. A hazard stripe, in one byte of set
difference.

Note `$4D` is in both sets — that is the colour the builder lays bricks in, so
bricks become walkable terrain the moment they are drawn.

Colours the walker treats as triggers rather than terrain:

| Colour | Effect |
|---|---|
| 3 | death animation A (state 6) |
| `$12` | state 9 — **which has no handler**, see below |
| `$20`–`$29` | death animation B (state 7) |

## The state machine

`Lem_UpdateAll` (`1005:1a4c`) runs every slot each frame: removes anything below
y = 199, applies a scripted skill whose target position has been reached, ages
the countdown, draws the sprite, then dispatches on the state byte.

| State | Routine | Behaviour |
|---:|---|---|
| 1 | `LemState1_Walker` | see below |
| 2 | `LemState2_Faller` | falls; drifts sideways for the first two rows only; **splats if the drop exceeded 11** — but only on the *second* such landing, counted in field +4 |
| 3 | `LemState3_Timer` | the "oh no" animation — 5 frames at one per 3 ticks, then state 11 |
| 4 | `LemState4_Miner` | digs **diagonally** — erases, then moves two across and one down per frame cycle |
| 5 | `LemState5_Builder` | see below |
| 6 | `LemState6_DeathA` | 7 frames then removed |
| 7 | `LemState7_DeathB` | 6 frames then removed |
| 8 | `LemState8_Splat` | 4 frames, draws the splat sprite, removed |
| 10 | `LemState10_Basher` | digs **horizontally** — scans a vertical column ahead, erases a slab, moves one across every third frame, no vertical movement |
| 11 | `LemState11_Countdown` | flashes palette `$E0`–`$E9` over 5 steps, then arms the countdown at −60 |

**There is no state 9.** The dispatch chain handles exactly the ten states above.
A lemming that walks onto colour `$12` is put into state 9 by the walker and
then falls through every branch, so no routine runs for it again — it is still
drawn each frame, but it never moves, never ages, and never frees its slot. It
freezes on the spot permanently. Whether that was meant as the level's exit or
is simply an oversight cannot be told from the code; the effect is deterministic
either way.

### The walker

1. Scan `(Y+1, X-3 .. X+3)` for ground. A trigger colour fires immediately; the
   first ground colour stops the scan; if all seven are empty, become a faller.
2. Ground found — look for a **wall**: rows `Y-9 .. Y-4`, three columns ahead.
   Anything in the wall set **reverses direction**. So obstacles taller than
   about five pixels turn the lemming around.
3. Otherwise look for a **step**: rows `Y-4 .. Y`, two columns ahead. If solid,
   `Y := row - 1` — it climbs up.
4. Move X by the direction byte. The tick cycles 1..2 and the frame advances
   1..4 on every second tick, so the walk cycle runs at half the frame rate.

### The builder

Ticks up to 500. Every third tick the frame advances 1..6, and **on frame 6 a
brick is laid**: `X += 2`, `Y -= 1`, then a filled triangle in colour `$4D`
spanning `X-2 .. X+2` at the new Y. So the staircase climbs two pixels across
for one up, and the bricks are themselves walkable.

At tick 500 the builder reverts to walker — and sets its **countdown to 20**. So
twenty frames later the countdown reaches 1, which triggers state 3, which
triggers state 11: the builder finishes its staircase and then blows itself up.

## The level is scripted

`Lem_Spawn` (`1005:06e7`) releases lemmings from a hatch at (35, 60) as fallers,
up to **80 total**, and at four specific release counts writes a target position
and skill into a slot — so the right lemming gets the right skill at the right
place and the level solves itself:

| Release # | Slot written | Target | Skill |
|---:|---:|---|---:|
| 3 | 3 | (50, 102) | 10 — basher |
| 5 | 5 | (49, 102) | 4 — miner |
| 65 | **1** | (181, 158) | 10 — basher |
| 80 | **1** | (223, 158) | 5 — builder |

Note the last two write into **slot 1**, not slots 65 and 80 — there are only 25
slots, so the script targets whichever slot it wants by index and relies on the
release count purely as a clock. `Lem_UpdateAll` applies the skill when that
slot's position matches its target, then clears the target.

## The scroller

`Scroller_Step` (`1005:08ad`) advances two columns per frame, wrapping at 21
(about 11 characters visible), draws two carrying lemmings — one facing each way,
indexed `(4 - frame)` and `(frame + 4)` into the same 140-byte-per-frame bank —
and rotates the 8-entry colour band at `$80`–`$87` twice per frame.

## Assets

Twenty reads from `$1228CE` totalling 202,007 bytes — the level graphics, three
palettes, two 320×200 screens and fourteen sprite banks between 400 and 24,255
bytes. The many banks are the per-skill animation sets.
See [`assets/part004/`](../assets/part004/).

## Effect_ColumnSlideIn

`1005:0000` — the transition into the level: 200 columns spanning x = 60..259
each scroll into place at the same rate but with a random head start
(`Random(200) - 400`), over 400 frames.

## Open

- Nothing outstanding.

## Correction: the two digging skills were the wrong way round

An earlier version of this page had states 4 and 10 swapped. Decompiling both
settles it by how they move:

| | Scan | Movement per cycle |
|---|---|---|
| **State 4 — miner** | the row below, `X-3..X+4` | `X += Dir * 2`, `Y += 1` — diagonal |
| **State 10 — basher** | a vertical column ahead, `Y-9..Y` | `X += Dir`, no `Y` change — horizontal |

Which also flips the level script: lemmings 3 and 65 are **bashers**, lemming 5
is a **miner**.

Both erase terrain by drawing colour 0 through the same two span fills.
`VGA_FillRect` (`1005:0328`) and `VGA_FillTri` (`1005:0354`) are misnomers —
neither draws what its name suggests. They are one-pixel-thick spans, vertical
and horizontal respectively, both indexing the sprite blitter's row table at
`DS:$CF8E`.

## The sprite banks

`Lem_DrawSprite` (`1005:03b9`) does one blit per state, and the frame stride is
always `H * W`, which is what fixes each sprite's dimensions:

| State | Size | Stride | Bank |
|---|---|---:|---|
| walker / faller | 9 × 6 | `$36` | `$04EC` |
| long fall | 10 × 10 | 100 | `$066E` |
| miner | 13 × 17 | `$DD` | `$13BB` |
| splat | 10 × 12 | `$78` | `$1240` |
| basher | 10 × 14 | `$8C` | `$193A` |
| death B | 10 × 16 | `$A0` | `$1ACA` |
| death A | 12 × 9 | `$6C` | `$1E1E` |
| builder | 10 × 12 | `$78` | `$209A` |
| timer | 10 × 15 | `$96` | `$234C` |
| explosion | 55 × 63 | `$D89` | `$1947` / `$26D0` |

The walker and faller share one bank: frames 1–4 face one way and 5–8 the
other, which is why a leftward lemming indexes `(Frame + 4)`.

`Sprite_Blit` (`1005:037a`) is a transparent blit — zero bytes are skipped —
stepping `DI` by `320 - W` between rows.
