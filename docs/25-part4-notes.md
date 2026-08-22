# Part 004 — working notes from the disassembly

Raw findings, written down as they are read so the work survives a context
reset. Everything here is off `NEUROSIS_004.exe`; nothing is inferred.

**Part 004 is done.** `P4VGA.PAS`, `P4VT.PAS` and `PART4_LEMMINGS.PAS` are all
transcribed in full, with no inference and no stubs, and `TP4S1` builds. These
notes are kept as the working record of how it was read; the source is the
authority.

---

## Layout

| segment | what |
|---|---|
| `1005` | the whole Lemmings scene, 0x1D40 bytes, ~30 routines |
| `11d9` | the tracker client — **done**, `P4VT.PAS` |
| `11e3` | the VGA unit — **done**, `P4VGA.PAS` |
| `1226` | Turbo Pascal's Crt |
| `1288` | the RTL |

**No 386 instructions anywhere in part 004**, so there is no TASM object to
link — unlike parts 001, 002 and 005.

Hand assembler in `1005`, from the `ENTER` and `REP` sweeps:

- `1005:0328` vertical run
- `1005:0354` horizontal run
- `1005:037a` transparent sprite blit
- `1005:07f9` the scroller's blit-and-shift
- `1005:0835` 64,000-byte screen copy

Everything else in `1005` has a compiler frame.

---

## The lemming record

`Lem_InitAll` (`1005:06c8`) clears index 1 through 25, stride `$15` = 21
bytes, so the array is `array[0..25]` at **`DS:$02FC`** with 1..25 in use.
Element *I* is at `I * $15 + $2FC`.

Fields, as offsets within the record, with the values `Lem_Spawn`
(`1005:06e7`) writes:

| ofs | size | spawn value | what |
|---|---|---|---|
| +0 | Word | `$23` = 35 | X |
| +2 | Word | `$3C` = 60 | Y |
| +4 | Word | 0 | — |
| +6 | Word | 1 | animation frame (`Lem_DrawSprite` indexes banks with it) |
| +8 | Word | 0 | — (also zeroed by `Lem_SetState`) |
| +10 | Word | 0 | — |
| +12 | Byte | 1 | active flag; 0 = slot free |
| +13 | Byte | 2 | **state** (`Lem_SetState` writes here) |
| +14 | Byte | 1 | direction — `Lem_DrawSprite` tests `< 1` and mirrors |
| +15 | Byte | 0 | sub-state; state 2 branches on `< 4` |
| +16 | Word | `$23` | spawn X, kept |
| +18 | Word | `$3C` | spawn Y, kept |
| +20 | Byte | 2 | — |

Counters: `DS:$051E` is the live count, `DS:$0520` the total spawned.
`Lem_Spawn` stops at `$50` = 80 spawned and scripts four one-off events at
totals 3, 5, `$41` and `$50` by poking three fields of a fixed slot.

`Lem_SetState(S, N)` sets state, frame := 1 and +8 := 0.

---

## The sprite banks

`Lem_DrawSprite` (`1005:03b9`) switches on the state byte. Every base
address resolves to a `LoadAssets` `BlockRead` destination once you account
for the frame index being **one-based** — the compiler folds `base - stride`
into the instruction.

| state | name | W x H | stride | bank at | bytes | frames |
|---|---|---|---|---|---|---|
| 1 | Walker | 6 x 9 | `$36` | `$0522` | `$1B0` | 8 (4 + 4 mirrored) |
| 2 | Faller, sub < 4 | 6 x 9 | `$36` | `$0522` | shared | |
| 2 | Faller, sub >= 4 | 10 x 10 | 100 | `$06D2` | 400 | 4 |
| 3 | Timer | 15 x 10 | `$96` | `$23E2` | `$2EE` | 5 |
| 4 | Basher | 17 x 13 | `$DD` | `$1498` | `$52E` | 6 |
| 5 | Builder | 12 x 10 | `$78` | `$2112` | `$2D0` | 6 |
| 6 | DeathA | 9 x 12 | `$6C` | `$1E8A` | `$288` | 6 |
| 7 | DeathB | 16 x 10 | `$A0` | `$1B6A` | 800 | 5 |
| 8 | Splat | 12 x 10 | `$78` | `$12B8` | `$1E0` | 4 |
| 10 | Miner | 14 x 10 | `$8C` | `$19C6` | `$1A4` | 3 |
| 11 | Countdown | 63 x 55 | `$D89` | `$26D0` | `$5EBF` | 7 |

Two specials:

- **state 6 frame 1** also blits a still from `$BF97` (`$C6C`) at a FIXED
  place, nothing to do with the lemming's own position. The four immediates
  are `PUSH $5F / $32 / $3C / $35` (`1005:068a`), and `Blit` takes them as
  X, Y, W, H — so it is **60 wide by 53 tall at (95, 50)**, not 53 x 60 at
  (50, 95). Both pairs multiply out to the same 3180 bytes, which is why the
  wrong reading loaded and drew without complaint: it just skewed the picture
  into diagonal garbage and put it in the wrong place. The picture is the
  storm cloud with a lightning bolt coming out of it, and it lands directly
  under the cloud `BackdropAnim` animates at (113, 50). Only the disassembly
  settles this; the block size does not.
- **state 11** shows the FIRST frame for frames 1..9 and only starts stepping
  the bank at frame 10, via `$1947 + (Frame-8) * $D89`.

Direction: `Lem_DrawSprite` adds 4 to the frame index for states 1 and 2 when
the direction byte is `< 1`, so the walker bank holds four frames facing one
way and four the other.

Blit parameter order, read off `1005:037a`:
`Blit(Src : Pointer; X, Y, W, H : Integer; Segment : Word)` — `Src` highest at
`[BP+$E]`, `Segment` lowest at `[BP+4]`.

---

## The drawing primitives

`1005:0328` and `1005:0354` are named `VGA_FillRect` and `VGA_FillTri` by
Ghidra and are **neither**:

- `1005:0328` `(X, YTop, YBottom, Colour, Segment)` — a one-pixel-wide
  VERTICAL run. `STOSB` then `ADD DI,$13F`, which with the store's own +1
  is 320.
- `1005:0354` `(X1, X2, Y, Colour, Segment)` — a HORIZONTAL run, `REP STOSB`.

`1005:07f9` is the scroller's renderer, and it takes no parameters:

```
    ES := [DS:$030D]                  the destination screen
    DS:SI := [DS:$0309]               the scroll buffer, 341 x 18 = 6138
    18 rows of REP MOVSW 160          320 visible bytes per row
      SI += $15                       341 - 320 = 21 off-screen
    18 x  write 0 at row start, stepping $155
    then MOVSW $BFC words from offset 2 to offset 0
```

so the buffer is 341 bytes per row with a 320-pixel window, and the whole
6,138 bytes are shifted left two bytes per call — the rows are scrolled as
one linear block, not individually. `Demo_Main` frees `$17FA` = 6138 for it.

---

## NEUROSIS.DAT

`Lemmings_LoadAssets` (`1005:00a6`) seeks **`$001228CE`** = 1,189,070 and
reads twenty blocks in this order:

| # | bytes | destination | what |
|---|---|---|---|
| 1 | `$5B8C` 23436 | GetMem, `DS:$CC03` | |
| 2 | 768 | stack | palette for the first screen |
| 3 | 64000 | virtual screen | first screen |
| 4 | 64000 | virtual screen | second screen |
| 5 | 768 | stack | |
| 6 | 768 | `DS:$CC07` | the scene palette |
| 7 | `$1B0` 432 | `DS:$0522` | walker, 8 frames |
| 8 | 400 | `DS:$06D2` | faller, 4 frames |
| 9 | `$1E0` 480 | `DS:$12B8` | splat, 4 frames |
| 10 | `$52E` 1326 | `DS:$1498` | basher, 6 frames |
| 11 | `$1A4` 420 | `DS:$19C6` | miner, 3 frames |
| 12 | 800 | `DS:$1B6A` | death B, 5 frames |
| 13 | `$C18` 3096 | `DS:$858F` | |
| 14 | `$288` 648 | `DS:$1E8A` | death A, 6 frames |
| 15 | `$2D0` 720 | `DS:$2112` | builder, 6 frames |
| 16 | `$C6C` 3180 | `DS:$BF97` | the lightning still, 60 x 53 |
| 17 | `$2AA8` 10920 | `DS:$91A7` | |
| 18 | `$348` 840 | `DS:$BC4F` | |
| 19 | `$5EBF` 24255 | `DS:$26D0` | countdown, 7 frames of 63 x 55 |
| 20 | `$2EE` 750 | `DS:$23E2` | timer, 5 frames |

Between reads 3 and 4 it runs `Effect_ColumnSlideIn`, `Delay($514)` = 1300,
then 64 x `FadeStep`. After read 20 it sets the palette and blacks entries
`$E0`..`$E9`.

Blocks 1, 13, 17 and 18 were the last to be identified -- see the final section.

---

## The frame loop

`Lemmings_MainLoop` (`1005:1bbb`):

```
    LiveCount := 0;  TotalSpawned := 0;  Frame := 0
    Mem[DS:$0310] := 1              -- element 0's +20, reused as the
                                       background animation's counter
    Lem_InitAll;  Lem_Spawn
    repeat
      CopyScreen(VirtScrSeg, WorkSeg)     -- the clean background
      Lemming_Walk                        -- the background animation
      Lem_UpdateAll
      Scroller_Step
      Inc(LongInt at DS:$0002)            -- a 32-bit frame counter
      CopyScreen(WorkSeg, $A000)
      Inc(Frame)
      if Frame mod 20 = 0 then Lem_Spawn
      if KeyPressed or (LiveCount = 0) then
      begin
        FadeStep
        for I := 1 to 24 do
          if Mem[DS:$00F4 + I] <> 0 then Dec(Mem[DS:$00F4 + I])
        twice:  V := GetVolume
                if V = 0 then Done := True else SetVolume(V - 1)
      end
    until Done
```

So the exit is driven by the VOLUME, not by a key: once a key is down (or
the last lemming is gone) the palette fades a step and the volume drops TWO
per frame, and the loop ends when the volume reaches zero. The 24-byte table
at `DS:$00F5..$010C` is decremented alongside; what it is has not been
established.

There are two screens: `VirtScrSeg` (`DS:$CF8C`) holds the clean background
and is what `GetPixel` reads as the collision map, and `DS:$030D` is a second
64,000-byte buffer that each frame is composed into. `Demo_Main` frees both.

## Lem_UpdateAll (`1005:1a4c`)

For N := 1 to 25:

```
    if Lem[N].Y > 199 then Remove(N)
    if Lem[N].Active <> 0 then
    begin
      if (TrigX >= 0) and (TrigX = X) and (TrigY >= 0) and (TrigY = Y) then
      begin
        SetState(TrigState, N);  TrigX := 0;  TrigY := 0
      end
      if Timer > 0 then Dec(Timer)
      if Timer = 1 then SetState(3, N)          -- 3 = Timer/fuse
      if Timer < 0 then Inc(Timer)
      if Timer = -1 then Remove(N)
      DrawSprite(@Lem[N])
      case State of 1,2,10,4,8,5,6,7,3,11 -> the ten state routines
    end
```

That fixes three more fields: **+16 TrigX, +18 TrigY, +20 TrigState** are the
scripted event `Lem_Spawn` pokes at totals 3, 5, `$41` and `$50`, and
**+10 is a signed timer** — positive counts down to a fuse, negative counts
up to removal.

## The states that are decoded

| addr | state | what it does |
|---|---|---|
| `1005:17ff` | 8 Splat | `Inc(Frame)`; at frame 4 stamps splat frame 4 (`$1420`) permanently into **VirtScrSeg** — the background — then `Remove`. So a splat leaves a mark on the terrain. |
| `1005:1850` | 6 DeathA | tick mod 5; every 5th, `Inc(Frame)`; `Remove` after 6 |
| `1005:18a6` | 7 DeathB | tick mod 3; every 3rd, `Inc(Frame)`; `Remove` after 5 |
| `1005:18fc` | 3 Timer | tick mod 3; every 3rd, `Inc(Frame)`; after 5 → `SetState(11)` |
| `1005:1954` | 11 Countdown | tick mod 5, act on mod 3. While frame < 10, five passes bumping DAC entries `$E0`..`$E9` up toward the loaded palette at `DS:$CC07` — which `LoadAssets` deliberately blacked, so this is the explosion lighting them. Past frame 15 it sets the timer to **-60** and holds the frame. |

`LemState2_Faller` (`1005:0b68`) is the interesting one:

```
    for DX := -3 to 3
      Pix := GetPixel(X + DX, Y + 1, VirtScrSeg)
      if Pix in <32-byte set at DS:$0B48> then       -- solid ground
      begin
        if FallDist < 11 then
          SetState(1); Y := Y + 0; FallDist := 0     -- land and walk
        else
          Inc(f4);  if f4 = 2 then SetState(8)       -- splat
                    else land and walk as above
        Frame := (Frame mod 4) + 1;  exit
      end
      if (Pix > $1F) and (Pix < $2A) then            -- colours 32..41
        SetState(7);  exit                           -- DeathB
    { nothing under it }
    if FallDist < 2 then X := X + Dir
    Y := Y + 1
    Inc(FallDist)
    Frame := (Frame mod 4) + 1
```

so **the terrain is read out of the background screen** and two colour ranges
mean different things: one set is solid, and colours 32..41 kill. That is why
part 004's VGA unit is the only one with `GetPixel`.

`Lemming_Walk` (`1005:0a4f`) is NOT a lemming — it is a 43 x 24 background
animation at (113, 50), three frames of 1032 bytes from `DS:$858F`
(BlockRead #13), stepping every fourth tick off the counter in `DS:$0310`.
That identifies block 13.

---

## What the last ten routines turned out to be

All read; nothing outstanding.

## The main body

Part 004 has no driver unit -- `1000:0019` is the whole of it, and it is three
calls plus a tidy-up:

    1000:001c  CALLF 11e3:0000   SetMode13h
    1000:0021  CALLF 11e3:0006   VirtScrAlloc
    1000:0026  CALLF 1005:1cd6   RunPart4
    1000:002b  while KeyPressed do ReadKey
    1000:003b  CALLF 11e3:0033   VirtScrFree
    1000:0041  Halt(0)

**Nothing inside `RunPart4` sets a video mode.** `TP4S1` originally allocated
the virtual screen and called `RunPart4` without the `SetMode13h`, so the whole
scene ran correctly and invisibly in 80x25 text -- indistinguishable from a
hang. `tools/mktests.py` now stands in for all six lines.

- **`1005:0000 ColumnSlideIn`** — gives every one of 200 columns a random head
  start of `Random(200) - 400` and then runs 400 passes, each copying the
  columns whose offset has reached zero. The title screen assembles out of
  vertical strips arriving at staggered times.

  Read from the decompiler this looked like a copy *within* the virtual screen,
  which shows nothing at all. The disassembly has it plainly: `1005:004A` loads
  `ES := $A000` and `1005:004F` loads `DS := VirtScrSeg`, so `MOVSB` at
  `1005:0072` reads the assembled picture and writes it to the **display**. Two
  further details only the disassembly gives: the walk loop at `1005:0065`
  advances the *source* alone while the destination stays at the top of the
  column, which is what makes a strip appear to slide down; and the guard at
  `1005:005B` is `CMP AX,1 / JGE`, so once a column's offset reaches 1 it is
  finished and never copied again.
- **`DS:$00F2`..`DS:$010C` is initialised data, and it is the conveyor belt.**
  Twenty-eight bytes straight out of the image:

      00 00 | 01 | 07 07 07  07 07 07  07 07 07  07 07 07
                   1E 1E 1E  1E 1E 1E  1E 1E 1E  1E 1E 1E

  `ScrollCol` = 0, `ScrollIdx` = 1, then eight RGB triples. `ScrollStep`
  rotates those eight by one every frame and writes them to DAC entries
  `$80`..`$87` (`1005:094d`..`1005:0a4d`, twice per frame). The belt across the
  top of the hillside is painted in exactly those eight indices — four at
  intensity 7 and four at 30 — so rotating them runs a light band along it and
  the belt turns. They are typed constants, not variables: a plain `var` gives
  zeros, which writes black into `$80`..`$87`, and the belt is then simply not
  on the screen. Nothing ever restores them, so `MainLoop` must not reset them
  either — `1005:1bbb` does not.

- **There is no fade-out without a tracker, and that is the original.**
  `MainLoop`'s ending is driven by the VOLUME, not by a timer: each frame past
  the keypress does one `FadeStep` and drops the volume twice, ending when the
  volume hits zero. `GetVolume` (`11d9:0078`) opens with

      11d9:0078  XOR AL,AL
      11d9:007a  CMP word ptr [0x110],0
      11d9:007f  JZ  <return>

  — no player resident, answer zero. So the first ending frame sets Done and
  the scene stops after a single `FadeStep`. Run inside the demo chain, with
  the player loaded, it fades over as many frames as the music was loud.

- **`1005:0000 ColumnSlideIn` is half compiled, half hand written.** The
  `Random` fill at `1005:0004` has to be compiled Pascal because it calls the
  RTL. Everything from `1005:0029` is hand assembler, and it says so plainly:
  `PUSH DS` / `POP DS` bracketing a block, `MOV ES` from an immediate, `MOVSB`
  with the pointers stepped by hand, and a `LOOP` — none of which Turbo
  Pascal's code generator emits.

  It matters for speed, not just fidelity. The segment registers are loaded
  ONCE per column and the inner loop is bare `MOVSB`; Pascal's
  `Mem[Seg:Ofs] := Mem[Seg:Ofs]` reloads a segment register per byte, so the
  Pascal reading assembles the title screen at a visible crawl.

  Transcribed verbatim, the built code is byte-identical to `1005:0029`..`0097`
  apart from four bytes, all of them data addresses: `VirtScrSeg`'s DGROUP
  offset, two copies of `SrcSeg`'s frame slot, and `OFFSET ColOfs`. Every
  opcode, displacement and jump matches.

- **`1005:1bf1`** bumps a 32-bit counter at `DS:$0002` every frame with
  `ADD [0002],1 / ADC [0004],0`. Nothing in part 004 reads it. Kept anyway.

- **`1005:14d6 Walker`** — the climb block (`1005:16b3`..`1005:177c`) leaves
  BOTH its loops the instant it finds a wall pixel:

      1005:170f  MOV AX,[BP-2]       ; Row
      1005:1712  DEC AX
      1005:1717  MOV [DI+0x2fe],AX   ; Lem[N].Y := Row - 1
      1005:171b  JMP 1005:1791       ; straight to the move

  That JMP is load-bearing. The new Y is one LESS than the row just tested, so
  a row loop that carried on would step back onto the row it came from and
  never advance -- which is exactly what an earlier transcription did, and it
  froze the frame loop at the first lemming that met a step.

  The two colour sets it tests are `CS:$1496` (Ground) and `CS:$14B6` (Wall).
  Wall is Ground plus the `$20`..`$29` hazard stripe. The Digger's set at
  `CS:$0DD5` and the Tunneller's at `CS:$1146` are byte-identical copies of
  Wall, so one `Wall` constant covers all three.

- **`1005:0853 ScrollChar`** — writes ONE column of one glyph into buffer
  column 320, the off-screen edge. The font is 62 glyphs of 21 columns x 18
  rows stored column-major; the index is `Ch*378 + Col*18 + Row + 1 - 12115`
  and 12115 is `32*378 + 18 + 1`, so the character is 32-based and the column
  one-based.
- **`1005:08ad ScrollStep`** — advances the column counter by **two** because
  the bitmap slides two pixels a frame, so every other column of every glyph
  is never written and the message is drawn at half horizontal resolution.
  That is the original, not a slip. It also runs the two side animations from
  one six-frame bank read in opposite directions, and rotates the eight-entry
  colour cycle **twice** per frame.
- **`1005:14d6 Walker`** — ground scan, then a wall check at head height that
  reverses it, then a step check that lets it climb. Colour 3 kills one way,
  `$20..$29` another, and **colour `$12` sends it to state 9, for which there
  is no handler at all** — the lemming stops being simulated. Left in.
- **`1005:0b68 Faller`** — lands as a walker under 11 pixels of fall; past
  that the FIRST hard landing is survived and counted and the second splats.
  Drifts one pixel sideways for the first two rows of a fall only.
- **`1005:0df5 Digger`** (state 4) — diagonal: two pixels along and one down
  every sixth frame. **`1005:1166 Tunneller`** (state 10) — horizontal, never
  changes Y. Ghidra's "Basher" and "Miner" labels are the wrong way round.
- **`1005:0d1a Builder`** — lays a five-pixel brick in colour `$4D` into the
  hillside every sixth frame, stepping up and right. Gives up after 500 ticks
  and sets a 20-frame timer, which becomes a fuse.
- **`1005:1954 Explode`** — while the fireball is young it bumps DAC entries
  `$E0..$E9` up toward the scene palette, which `LoadAssets` deliberately
  blacked. The explosion is already on screen in colours nobody can see until
  the flash brings them up.
- **`1005:0a86 Intro`** — blanks the DAC, shows the hillside, fades up, then
  runs a seven-frame 65x24 animation BACKWARDS at (5, 50) 150 ms apart, and
  starts the music.
- **`1005:1c9a Setup`** — the work screen and the scroll buffer.
  **`1005:1d3a`** is an empty unit initialisation.

## The two terrain sets

Read out of the code segment at `1005:0B48` / `1005:1496` (ground) and
`1005:0DD5` / `1005:1146` / `1005:14B6` (wall) — five references, two
distinct constants:

```
    ground  [4,5, $0F, $15..$18, $1D, $1F, $33, $36,
             $3E..$40, $42..$47, $4D..$52]
    wall    the same PLUS [$20..$29]
```

so `$20..$29` blocks movement but cannot be stood on, and touching it kills.
`$4D` is in both, which is the builder's brick colour — bricks are walkable.
This confirms the plate comment already on `LemState1_Walker` independently.

## The message

Compiled into DGROUP at `DS:$0005`, 237 bytes, which is exactly the `< $ED`
bound `ScrollStep` tests:

> FOR THOSE OF YOU THAT REALLY HATE LONG, BORING SCROLLIES, WE DECIDED TO PUT
> A NEW TWIST ON IT \*\*\* BUT IF YOU DONT LIKE LEMMINGS, THEN THERE IS NO
> HOPE, HIT ANY KEY NOW. THE ANY KEY? THE ONE ON THE SIDE MARKED -POWER-
> \*\*\*

## All twenty asset blocks identified

The four that were open resolved as: **1** the 62-glyph scroller font,
**13** the hillside's own 43x24 animation, **17** the intro's 65x24
animation, **18** the two 14x10 animations either side of the message.
