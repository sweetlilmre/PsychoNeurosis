# The x87 emulator traps

## The symptom

Six of the seven effect parts disassemble with dozens of `INT 35h`–`3Eh`
instructions scattered through otherwise ordinary code, and everything after
each one is garbage:

```
1015:0715  CALLF 0x1000:692d     9a 7d 31 7b 13
1015:071a  INT 0x3c              cd 3c        <- not actually an interrupt
1015:071c  WAIT                  9b           <- actually FP operand bytes
1015:071d  CLI                   2e fa
```

These are **Borland's inline x87 emulator traps**. The compiler was used with
`$E+`, so the linker overwrote each floating-point instruction's `WAIT ESC`
prefix with a two-byte `INT n`. Lengths are preserved, which is what lets the
RTL patch them back to real FP opcodes at startup when a 387 is present.

## The encoding

| Trap | Rewrites to | Meaning |
|---|---|---|
| `CD n`, n = 34–3B | `9B` + `D8+(n−0x34)` | ESC with register/BP-relative operand |
| `CD 3C <b>` | `9B 2E` + `<b+0x40>` | **CS-relative** ESC |
| `CD 3D` | `90 9B` | standalone FWAIT |
| `CD 3E <b>` | — | RTL emulator dispatch; `<b>` is an index, not an opcode |

`INT 34h` (ESC `D8`, single precision) never appears — consistent with Pascal
using 64-bit `Real`/`Double`.

Decoding under this scheme immediately produces the instruction mix real Pascal
float code makes: `FINIT`, `FMULP ST(1),ST`, `FLDCW`, `FSTP qword[BP+d]`,
`FILD word[BP+d]`.

### The `INT 3Ch` subtlety

`3C`'s operand byte is always `98`/`99`/`9B`/`9F` — exactly `D8`/`D9`/`DB`/`DF`
with bit 6 cleared. That is what identified it.

The important part took a second pass to get right. `INT 3Ch` is not merely
"ESC with a direct disp16 operand" — it is **ESC whose operand lives in the code
segment**. Borland parks floating-point literals beside the procedures that use
them:

```
9B 2E D8 1E 44 07     WAIT ; CS: ; FCOMP dword ptr CS:[0744]   <- original
CD 3C 98 1E 44 07     emulated form -- same six bytes
```

The first version of the fixup emitted `90 9B D8 1E 44 07` (NOP, WAIT, ESC).
Correct length, but **the `CS:` prefix is gone**, so every code-segment literal
silently resolved against DS and decoded as garbage. The tell was `DS:$0744`
holding what looked like coordinate pairs instead of floats — which it was, but
belonging to something else entirely.

`INT 3Eh`'s operand is *not* an x87 sub-opcode: `$FA` appears both under
`INT 35h` (as `FSQRT`) and under `INT 3Eh`, so it must be a dispatch index into
the emulator.

## Applying the fix

`tools/fpfix.py` patches a part given a list of **Ghidra-confirmed** trap
addresses. It never patches on byte match alone — a flat byte scan produces
false positives (part 004 shows 7 raw `CD 3x` hits but has zero real traps).

```sh
python tools/fpfix.py work/split/NEUROSIS_003.exe \
    -s work/sites/NEUROSIS_003.json -o work/split/NEUROSIS_003_fpu.exe
```

The process is **iterative**: fixing early traps re-syncs the disassembler and
reveals more that were hidden inside mis-decoded bytes. `tools/fpround.sh` runs
one round per part — dump surviving traps, merge into the accumulated site list,
re-patch from the pristine original, re-import:

```sh
for r in 1 2 3 4 5; do
  for n in 001 002 003 005 006 007; do bash tools/fpround.sh $n; done
done
```

It converges after about four rounds. Part 006 needed the most: 41 sites found
initially, 79 by convergence.

If a fixup has already been applied with the old (NOP) form,
`tools/ghidra/FixCsOverride.java` corrects the `INT 3Ch` sites **in place** —
patching the open programs rather than re-importing, so naming and comments
survive.

## Result

| Part | Traps before | after | x87 recovered | Funcs |
|---|---:|---:|---:|---:|
| 001 | 52 | 4 | 21 → 137 | 195 |
| 002 | 15 | 2 | 17 → 44 | 167 |
| 003 | 55 | 4 | 27 → 129 | 179 |
| 005 | 10 | 3 | 17 → 66 | 137 |
| 006 | 41 | 4 | 50 → 140 | 147 |
| 007 | 7 | **0** | 17 → 34 | 125 |

The residual traps are all inside the RTL's own emulator helper routines, none
in demo code.

## What this told us about the demo

The FP is **not** in the effects. Every site sits in setup or table-building
code — the render loops are integer. `NEUROSIS.004` has no floating point at
all. A representative site, `120f:008a` in part 003:

```
MOV AL,[BP-0x82]                  ; integer index in
PUSH AX; PUSH 0; PUSH 0           ; 6 bytes = Borland Real
WAIT; FILD word ptr [BP-0x82]
WAIT; FLD tbyte ptr [0x000D]
WAIT; FMULP ST(1),ST
CALLF RTL helper                  ; Round
ADD AX,0x1b                       ; integer out
```

`Round(i * constant) + 27` — integer in, integer out.
