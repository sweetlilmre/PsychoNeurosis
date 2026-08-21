# PSYCHO.EXE — the launcher, charted

Read from `bin/PSYCHO.EXE` (1,936 bytes, dated 7 Feb 1994) for [Chart PSYCHO.EXE](https://github.com/sweetlilmre/PsychoNeurosis/issues/20). Every byte of the load image is accounted for below; nothing is inferred.

## G0 — the container

The file is *all* load image: MZ header of 112 bytes (7 paragraphs), 20 relocations, no overlay, no appended debug info (`toolkit/substrate/tddump.py` reports none). Entry `0000:0036`, stack `SS:SP = 0098:0800` (a 2KB stack), and **minalloc = maxalloc = 166 paragraphs** — the program caps its own memory at ~2.6KB above the image, which is what a launcher that EXECs children must do to leave RAM for them. In Turbo Pascal that spells `{$M $800,0,0}`.

## G1 — identification

Turbo Pascal 7, three segments: the program, a smart-linked subset of the **`Dos` unit**, and the System RTL. The `Dos` unit identifies itself beyond doubt: `SwapVectors`' embedded vector list at `100b:00bf` is the 19 interrupts `00 02 1B 21 23 24 34 35 36 37 38 39 3A 3B 3C 3D 3E 3F 75` — including the x87-emulator vectors `34h`–`3Eh` that `docs/02-fpu-emulator.md` documents from the receiving end.

## G2 — the chart

| segment | extent | what |
|---|---|---|
| `1000` | `0000`–`00AF` | the program: string table + main body |
| `100b` | `0000`–`00D1` (+ padding) | TP7 `Dos` unit, smart-linked to three routines |
| `1019` | to end of image | System RTL (`SystemInit` `0000`, `Halt` `0116`, runtime-error machinery) |

DGROUP is `106d`. Globals: `[0x50]` the child's exit code, `[0x52]` `DosError`, `[0x54]/[0x56]` `Exec`'s saved `SP`/`SS`, `[0x258]` the 19-entry saved-vector table (`SaveIntXX`, 76 bytes).

### The string table, `1000:0000`–`0035`

Five Pascal string literals in the code segment: `'Neurosis.000'` (`0000`), `''` (`000D`), `'neurosis.008'` (`000E`), `'@neurosis.cfg'` (`001B`), `'neurosis.009'` (`0029`).

### Main, `1000:0036`–`00AF` — compiled Pascal, the whole program

```
0036  CALLF 1019:0000        RTL init            (encoded 1000:0190 -- same linear)
003e  SwapVectors
0043  Exec('Neurosis.000', '')                   the setup program
0052  SwapVectors
0057  DosExitCode -> [0x50]
005f  if code = 1 then goto 008a                 skip the demo, still say goodbye
0068  if code = 2 then goto 00a3                 quit silently
0071  SwapVectors; Exec('neurosis.008', '@neurosis.cfg'); SwapVectors
008a  SwapVectors; Exec('neurosis.009', ''); SwapVectors
00a3  LEAVE; Halt(0)                             (encoded 1000:02a6 = 1019:0116)
```

Equivalent Pascal, the entire program:

```pascal
{$M $800,0,0}
program Psycho;
uses Dos;
var Code : Byte;
begin
  SwapVectors; Exec('Neurosis.000', ''); SwapVectors;
  Code := Lo(DosExitCode);
  if Code <> 2 then
  begin
    if Code <> 1 then
    begin
      SwapVectors; Exec('neurosis.008', '@neurosis.cfg'); SwapVectors;
    end;
    SwapVectors; Exec('neurosis.009', ''); SwapVectors;
  end;
end.
```

(The exact branch shape in the binary is two forward tests and two joins, as charted above; the reconstruction ticket decides the source shape that compiles to it.)

### The Dos unit, segment `100b`

| addr | routine | reading |
|---|---|---|
| `100b:0000` | `Exec(Path, CmdLine: PathStr)` | saves `SP`/`SS` to `[0x54]/[0x56]`; copies `Path` to an ASCIIZ buffer (clamped 79); copies `CmdLine` to a length-byte + CR command tail (clamped 126); parses two FCBs with `INT 21h AX=2901h`; builds the parameter block (env segment from PSP `[0x2C]`); `INT 21h AX=4B00h`; restores `SS:SP` and DGROUP `106d`; `DosError` to `[0x52]` |
| `100b:0094` | `DosExitCode` | `MOV AH,4Dh / INT 21h / RETF` — three instructions |
| `100b:0099` | `SwapVectors` | walks the 19-byte vector list at `CS:00BF`; for each: `AH=35h` get vector, `AH=25h` set from the table at DGROUP `[0x258]`, store the old one back into the table — a true swap, so calling it twice restores |
| `100b:00bf` | data | the vector list: `00 02 1B 21 23 24 34-3F 75` |

This is Borland's own library code, not Asphyxia's — the reconstruction writes `uses Dos` and gets all of it.

### What the chart settles

- **PSYCHO.EXE never runs parts 001–007.** It EXECs exactly three children: setup, DemoVT with `@neurosis.cfg`, and the end screen. The demo chain therefore lives *inside* `NEUROSIS.008` (DemoVT, third-party), which receives the config file as its command line. This sharpens `docs/01-binaries-and-loading.md`'s picture of how the ten files fit together.
- **Setup's exit code is a protocol**: `1` = skip the demo but show the end screen, `2` = quit silently, anything else = run the demo. The reconstruction of `NEUROSIS.000` (`STARTUP.PAS`) must reproduce these `Halt` codes — this is a cross-artefact constraint the `STARTUP.PAS` ticket needs.
- **How much is ours**: Asphyxia's own code in this file is main's 122 bytes plus five string literals. Everything else is the compiler's.

## The reconstruction: byte-identical

`src/PSYCHO.PAS` rebuilds to a **SHA256-identical 1,936-byte executable** (`f1264dc5…10dce`), so the launcher stands at **R7, artefact-identical** — the first artefact in the project to reach the ladder's top, and it needs no behavioural observation: identical bytes behave identically.

The closing byte-diff recovered two facts about the 1994 source that no amount of charting gives:

- **It used `goto`.** The original's `75 02 EB xx` jump-over-jump at `1000:0064`/`006d` is TP7's encoding for `if X then goto L` with a forward label; a nested `if`/`begin` shape emits short jumps, reorders the tests, and shifts every relocation after it by four bytes. 76 differing bytes fell to 1 when the `goto`s went in.
- **It was compiled `{$G+}`.** The last byte, `LEAVE` (`C9`) against our `POP BP` (`5D`) at main's end, is a 286 encoding. `{$G+}` closed it to zero.

The diff-reading method is now the wiki observation [The rebuild nearly matches, and the last bytes name their causes](../wiki/observations/near-match-diff/observation.md).

### Addressing note, recorded once

Two addresses in this chart wear two names each: the `Dos` unit's base (`100b:0000` = `1000:00B0`) and both RTL calls (`1000:0190` = `1019:0000`, `1000:02A6` = `1019:0116`). The wiki observation [The same bytes answer to two different addresses](../wiki/observations/two-names-one-address/observation.md) is the rule for this; it was written from this chart.
