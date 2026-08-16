# Binaries and loading

## What the files are

All real-mode DOS **MZ** executables built with **Borland Pascal 7** — every
part carries `Portions Copyright (c) 1983,92 Borland`. There is no custom
container format; `NEUROSIS.000`–`.009` are ten separate programs.

| File | Image | Appended payload | Role |
|---|---:|---|---|
| `PSYCHO.EXE` | 1,936 | — | launcher |
| `NEUROSIS.000` | 12,880 | 4,546 B debug info | setup / detect (`STARTUP.PAS`) |
| `NEUROSIS.001` | 38,528 | MOD *In awe of you.* | intro — `asphyxia.cel`, welcome scroller |
| `NEUROSIS.002` | 38,832 | MOD *StarTrek Samples* | effects |
| `NEUROSIS.003` | 72,240 | MOD *Techno Tick* | effects (largest) |
| `NEUROSIS.004` | 15,008 | MOD *The Deth March* | Lemmings scroller |
| `NEUROSIS.005` | 38,496 | MOD *Neurotic Interlude* | effects |
| `NEUROSIS.006` | 55,984 | MOD *LaTeX LoVeR* | effects |
| `NEUROSIS.007` | 20,112 | MOD *The Deth March* | FLI/FLC player — `lemend.flc` |
| `NEUROSIS.008` | 31,711 | — | JCAB's **DemoVT** mod player (**LZEXE-packed**) |
| `NEUROSIS.009` | 7,312 | 3,044 B debug info | end screen (`BYEBYE.PAS`) |

## How it fits together

`PSYCHO.EXE` references only four names — `Neurosis.000`, `neurosis.008`,
`@neurosis.cfg`, `neurosis.009`:

```
PSYCHO.EXE
  ├─ runs NEUROSIS.000                 setup: VGA detect, MemAvail/MaxAvail
  ├─ runs NEUROSIS.008 @neurosis.cfg   DemoVT drives the whole show
  │      └─ per NEUROSIS.CFG, for each part 001..007:
  │           load MOD from <file> at /off:<n>, then shell <file>
  └─ runs NEUROSIS.009                 end screen
```

Each part is **`[EXE image][ProTracker MOD]` in one file**. The `/off:` values in
`NEUROSIS.CFG` are exactly each part's MZ image size, so DemoVT reads the module
from the tail while the same file runs as the effect. Parts talk back to the
resident player over **INT 2Fh** (one call in every effect part).

## Recovered symbols

Parts 000 and 009 shipped with Borland debug info (magic `0x52FB`):

- `NEUROSIS.000` → `STARTUP.PAS` — `VGA`, `MEMAVAIL`, `MAXAVAIL`
- `NEUROSIS.009` → `BYEBYE.PAS` — `IMAGEDATA`, `IMAGEDATA_WIDTH`, `IMAGEDATA_LENGTH`, `IMAGEDATA_DEPTH`

The seven effect parts were built without debug info.

## Loading into Ghidra

Ghidra's stock MZ loader handles these correctly, including relocations and
per-unit segment splitting. Two prep steps matter:

1. **Strip the appended MOD** so the imported file is only the load image.
2. Import as `x86:LE:16:Real Mode` (auto-detected).

```sh
python tools/split.py -o work/split bin/PSYCHO.EXE bin/NEUROSIS.00*

"$GHIDRA/support/analyzeHeadless.bat" work/ghidra psycho \
    -import work/split/NEUROSIS_004.exe -overwrite
```

Verified on Ghidra 12.1.2. The loader recovers one memory block per Borland
Pascal unit, matching the segment map derived independently from the relocation
table (`tools/segmap.py`).

### Gotchas

- **Import via the MCP bridge gives weaker analysis** than headless — fewer
  functions found. Prefer headless for the initial import; the bridge is for
  interactive work afterwards.
- **Ghidra labels DGROUP as a code block.** In part 003, `CODE_13` at segment
  `1761` is really the initialised data segment. Find DGROUP by reading the
  relocated word in the RTL prologue (`MOV DX, dgroup` at RTL+1).
- **The decompiler mis-resolves CS-relative operands**, using the image base
  rather than the owning segment. The disassembly is correct — read
  code-segment constants from the listing, never from the decompiler.

## Per-part hardware profile

`OUT DX` counts are VGA register writes, a rough proxy for graphics weight.

| Part | Funcs | Instrs | INT 10h | INT 21h | INT 2Fh | OUT DX | Notes |
|---|---:|---:|---:|---:|---:|---:|---|
| 000 | 70 | 3,918 | 3 | 9 | — | 0 | setup only |
| 001 | 196 | 7,746 | 2 | 19 | 1 | 11 | most functions |
| 002 | 167 | 8,256 | 4 | 18 | 1 | 52 | heavy VGA regs |
| 003 | 180 | 7,556 | 3 | 18 | 1 | 43 | heavy VGA regs |
| 004 | 121 | 4,657 | 2 | 13 | 1 | 11 | no FP at all |
| 005 | 130 | 4,728 | 2 | 18 | 1 | 6 | |
| 006 | 148 | 5,943 | 2 | 18 | 1 | 11 | PIC writes (0x20/0xA0) |
| 007 | 125 | 4,219 | 7 | 18 | 1 | 1 | reprograms PIT for FLC timing |
| 008 | 1 | 17 | — | — | — | — | packed |
| 009 | 38 | 772 | 1 | 9 | — | 0 | end screen |
