# Part 007 — the reading

Read out of `NEUROSIS_007_fpu.exe`, instruction by instruction. Every routine
in the part is accounted for below.

Like part 006, this binary had to be imported into Ghidra and its
auto-analysis finds no functions, so every address came from following calls.
Where Ghidra prints an address as `0x1000:XXXX` the real segment is in the
instruction bytes; for segment `100f` the conversion is **offset = 0xXXXX −
0xF0**, and every branch below was checked against it.

---

## What part 007 is

One thing: an Autodesk Animator **FLI/FLC player**, pointed at an animation
embedded in `NEUROSIS.DAT` at `$0019117F`. There is no rendering code of its
own and no virtual screen — every chunk handler writes straight to `$A000`.

## Layout

| segment | linear | what |
|---|---|---|
| `1000` | `0x10000` | the main body, `0x00`..`0xbb` |
| `100b` | `0x100b0` | the video unit — **two routines** |
| `100f` | `0x100f0` | the player, `0x000`..`0x891` |
| `1099` | `0x10990` | Turbo Pascal's Crt |
| `10fb` | `0x10fb0` | the DemoVT client |
| `110c` | `0x110c0` | the RTL |
| `14ce` | `0x14ce0` | DGROUP |

Segment `100b` is only:

    100b:0000   MOV AX,0013h / INT 10h / RETF      SetMode13h
    100b:0006   MOV AX,0003h / INT 10h / RETF      SetTextMode

---

## `1000:001e` — the main body

```
100b:0000  SetMode13h
10fb:0000  MusicDetect      10fb:006a  function 3
10fb:0093  MusicCue         10fb:004e  MusicStart
100f:084c  the scene
           while KeyPressed do ReadKey
           SavedVol := GetVolume                      DS:$0066
           repeat SetVolume(GetVolume-1); Delay(10) until GetVolume = 0
10fb:005c  MusicStop        10fb:00d8  SetVolume(SavedVol)
100b:0006  SetTextMode
           MOV AH,1 / MOV CH,0FFh / MOV CL,9 / INT 10h
           Halt(0)
```

That last `INT 10h` is **AH=1, CX=$FF09 — set cursor shape**, start line above
end line, which hides the cursor. Part 007 is the last part of the demo and it
is the only one that leaves DOS tidy.

There is **no `VirtScrAlloc`**.

---

## `100f:084c` — the scene

Stores four far pointers and makes two calls:

```
DS:$340d := 100f:0019 (SS2)    DS:$3411 := 100f:007b (LC)
DS:$3415 := 100f:0000 (COPY)   DS:$3419 := 100f:0284 (BRUN)
100f:0771  AddFlic     100f:07d4  PlayAll
```

### `100f:0771` — AddFlic

```
Count := 0;  PlayIdx := 1;  DS:$340c := 0;  LoopCnt := 1;
S := UpCaseStr('lemend.flc');            { CS:$0766 }
if Count < 100 then Inc(Count);          { 100f:07ad, JGE }
Names[Count] := S;
```

`Names` is `array[1..100] of String[127]`; the compiler's base is `$0186` and
`DI := Count shl 7 + $186`, so entry 1 sits at `DS:$0206`. That places the end
of the array at `$0206 + 12800 = $3406` — which is exactly where `Count`
lives, and confirms the layout independently.

**`lemend.flc` is a dead string.** The player ignores its parameter and opens
`neurosis.dat` by name, so nothing ever reads this slot. It is the author's
own working filename left in, the same as part 006's `.cel` names, and the
file is not shipped with the demo. (An extracted copy of the animation is at
`assets/part007/LEMEND.FLC`, 62,206 bytes.)

### `100f:07d4` — PlayAll

Two nested loops falling out on the same flags. Since `Play` always answers 0
(see below), `Done` and `Abort` stay false, `Left` goes 1 → 0 on the first
pass, and the animation runs exactly once.

---

## `100f:0453` — Play

`ENTER $238,0`. Frame layout, worked back from the `LEA`s:

| slot | what |
|---|---|
| `BP-$102` | the name parameter, copied in at `100f:045e` and then **never used** |
| `BP-$182` | a `file` record — see the bug below |
| `BP-$202` | the 128-byte FLI header |
| `BP-$212` | the 16-byte frame header |
| `BP-$228` | the 6-byte chunk header |

```
Stop := False;  Result := 0;              { and the result is never touched again }
GetMem(Buf, 65000)                        { $FDE8 }
Calibrate                                 { 100f:031d }
Assign(F,'neurosis.dat')                  { CS:$0411, into the GLOBAL file at DS:$341d }
Reset(F,1);  Seek(F,$0019117F);  FrameNo := 1
BlockRead(F, Hdr, 128)
```

Header checks: `+4` must be `$AF12` (FLC); `+8` must be 320 and `+10` must be
200. The speed at `+16` is taken as-is for `$AF12` and otherwise computed as
`Round(Speed / 70.0 * 1000.0)` — `CS:$041e` is the 70.0 and `CS:$0422` the
1000.0. On a size mismatch it drops to text mode, prints

    Error : Sorry, only 320x200 flics supported.

(`CS:$0426`, 44 characters) and halts.

### A bug in the original, at `100f:054d`

For an FLC it then seeks to the header's `oframe1` field at `+80` — but it
seeks **`SS:BP-$182`, a local `file` record that was never assigned and never
opened**, not `DS:$341d`. There is no `CheckIO` call after any I/O in this
routine, so the unit is compiled `{$I-}`: the RTL sets `InOutRes` and returns,
and the seek quietly does nothing. Reading carries on from the end of the
128-byte header, which for this file is where frame 1 begins anyway, so it
never showed. Compile the reconstruction with I/O checking on and it dies
here.

### The frame loop

```
100f:0560  Stamp := ReadTimer                 { DS:$0202 -- the frame's clock }
           BlockRead(F, Frame, 16)
           for N := 1 to Frame.Chunks do
             BlockRead(F, Chunk, 6)
             if Chunk.Kind = 16 then Inc(Chunk.Size, 2)     { 100f:05b5 }
             BlockRead(F, Buf^, Chunk.Size - 6)
             dispatch
             if KeyPressed then while KeyPressed do ReadKey { drained, ignored }
100f:06b1  WaitTicks(Speed)
           Inc(FrameNo)
until (Hdr.Frames + 1 < FrameNo) or Stop
100f:06d2  RestoreTimer;  Close(F);  FreeMem(Buf, 65000)
```

`Stop` is cleared at `100f:046e` and never set, and the key that gets drained
is stored to a slot nothing reads — so **a keypress does not end part 007**;
it runs to the last frame. The `+2` on a COPY chunk's size is a workaround for
encoders that understate it.

The dispatch:

| type | name | handler |
|---|---|---|
| 18 | PSTAMP | skipped |
| 7 | SS2 | `CALLF [$340d]` → `100f:0019` |
| 12 | LC | `CALLF [$3411]` → `100f:007b` |
| 16 | COPY | `CALLF [$3415]` → `100f:0000` |
| 15 | BRUN | `CALLF [$3419]` → `100f:0284` |
| 4 | COLOR256 | `CALL 100f:00de` |
| 11 | COLOR | `CALL 100f:01dc` |
| anything else | | **`Halt(5)`** at `100f:067f` |

Every handler is called with **two** pointers — the header first, then the
chunk — and every one ends `RETF 8`. Only BRUN reads the header, for the width
and height.

---

## The six handlers

`100f:0000` **COPY** — `MOV CX,7D00h / REP MOVSW`. 25 bytes, the whole frame.

`100f:0019` **SS2** — the word-aligned delta. A line count, then per line an
opcode word: top two bits set means a line skip (`NOT AX / INC AX`, × 320,
re-read the word), otherwise it is a packet count. Each packet is a skip byte
and a signed count — **positive copies words, negative repeats one word**.
`ADD DX,AX` at `100f:0064` is dead: DX is popped back on the next instruction.

`100f:007b` **LC** — the byte-run delta. Start line × 320, a line count, then
per line a packet count (zero skips the line), and per packet a skip byte and
a signed count — **positive copies bytes, negative repeats one byte**.

`100f:0284` **BRUN** — whole-frame RLE. Width and height come from the header.
The per-line packet count is read and **thrown away**; the loop is driven by
the width remaining instead. **Negative copies literally, positive repeats** —
the opposite way round from SS2 and LC.

`100f:00de` **COLOR256** and `100f:01dc` **COLOR** are compiled Pascal in the
original, not hand assembler (`ENTER $18,0` / `ENTER $16,0`, every value in a
`[BP-n]` slot, only the BIOS call inline). Both walk packets of (skip, count,
count×3 bytes) and hand each block to `INT 10h AX=$1012`; a count of zero
means 256. COLOR256 additionally shifts every byte down two in place, 8-bit to
6-bit, which is why it winds the offset back over the triples and forward
again. COLOR is byte for byte the same routine with that loop taken out.

---

## Timing

Part 007 does not use `Delay`.

`100f:031d` **Calibrate** puts PIT counter 0 into mode 2, binary, reload 0 —
the same 65536 the BIOS uses, so `0040:006C` keeps ticking at 18.2 Hz. Then it
times its own arithmetic a hundred times over and keeps the average in
`DS:$01fe`.

`100f:02cf` **ReadTimer** latches counter 0 and reads the BIOS tick with
interrupts off and the PIC masked, and bumps the tick by one if the IRR says a
timer interrupt is pending while the counter has just wrapped. The answer is a
`LongInt` — BIOS tick in the high word, PIT counter in the low — i.e. 65536
units per tick, **1,193,182 a second**.

`100f:03c9` **WaitTicks** computes `MS * $1234DE div 1000`, adds the measured
overhead and the frame's stamp, and spins. The target is **absolute**, so
decoding time is free until it exceeds the frame delay and the animation runs
at its authored speed rather than at decode speed plus the delay.

`100f:03b4` **RestoreTimer** puts counter 0 back to mode 3, reload 0.

`100f:088d`, the unit's initialisation, is empty.

---

## Verification

All four hand-written handlers are transcribed verbatim and byte-diffed
against the 1994 binary by `tools/asmverify.py`:

| routine | bytes matched | holes |
|---|---|---|
| `FliCopy` | 25 | 0 |
| `FliSS2` | 98 | 0 |
| `FliLC` | 99 | 0 |
| `FliBrun` | 75 | 0 |

Whole routine, end to end, with no displacement holes at all — nothing in
these four touches an absolute address, so there is nothing that had to
differ. `RestoreTimer` carries no marker: the original opens `PUSH BP / MOV
BP,SP` and Turbo Pascal gives a procedure with no parameters and no locals no
frame at all, so the walk has nothing to anchor on.
