# Borland RTL signatures

Roughly 40% of each part's listing is Borland runtime, not demo code. Naming it
once removes that noise everywhere.

## Finding the RTL segment

`tools/ghidra/ApplyRtlNames.java` locates it by signature rather than a per-part
base table:

```
BA ?? ?? 8E DA 8C 06           at segment+0      (MOV DX,dgroup / MOV DS,DX)
33 C9 33 DB BA ?? ?? 8E DA FB  at segment+0x116  (Halt -- the discriminator)
```

The `??` bytes are relocated DGROUP segment values that differ per part and
**must be wildcards** — a literal match finds nothing. That was the first
version's bug: I had derived the pattern from relocation-masked bytes and baked
the zeros in.

This also yields the DGROUP base for free: the relocated word at RTL+1. For part
003 that is `$1761`, which is what Ghidra labels `CODE_13`.

Detected bases:

| Part | RTL base | Named |
|---|---|---:|
| PSYCHO_EXE | `1019` | 17 |
| NEUROSIS_000 | `1213` | 43 |
| NEUROSIS_001 | `1543` | 80 |
| NEUROSIS_002 | `14b1` | 75 |
| NEUROSIS_003 | `137b` | 78 |
| NEUROSIS_004 | `1288` | 48 |
| NEUROSIS_005 | `12d9` | 68 |
| NEUROSIS_006 | `128a` | 75 |
| NEUROSIS_007 | `110c` | 77 |
| NEUROSIS_009 | `1069` | 19 |
| NEUROSIS_008 | — | skipped (LZEXE-packed) |

**1018 functions** named across 16 programs. Everything in the RTL segment
becomes `RTL_<offset>`; the script never overwrites a hand-chosen name.

## Offsets are NOT stable across parts

An early assumption — that one offset→name table would serve every binary — was
**wrong**, and mislabelled routines in most parts. Only a core is stable:
`SystemInit` (0), `Halt` (`$116`), `GetMem` (`$28a`), `FreeMem` (`$29f`).
Everything above shifts, and there are at least **four distinct RTL layouts**:

| Group | Parts | `Random` | `FileAssign` |
|---|---|---|---|
| A | 001, 002, 005 | `d2e` | `347b` |
| B | 003, 006 | `cd3` | `3420` |
| C | 004 | — | `8ce` |
| D | 007 | `cd3` | `3623` |

`tools/rtlfind.py` fixes this by locating each routine **by byte pattern**: it
masks relocated words in both reference and target, then searches the target's
RTL segment for the reference routine's body, accepting only unique hits. The
resulting per-part table is passed to `ApplyRtlNames.java` as
`off=name,off=name,...` arguments; the script also creates a function at any
address Ghidra never turned into one.

The give-away that something was wrong: `DumpDatAccess` reported "no
neurosis.dat access" for parts 001 and 002, which certainly do read it.

## Identified routines

Reference offsets in part 003. Each confirmed by decompiling it:

| Offset | Name | How identified |
|---|---|---|
| `0000` | `RTL_SystemInit` | segment start by construction |
| `0116` | `RTL_Halt` | |
| `028a` / `029f` | `RTL_GetMem` / `RTL_FreeMem` | |
| `0cd3` | `RTL_Random` | |
| `0e7c` | `RTL_FillChar` | |
| `320d` | `RTL_RoundToInt` | FISTP-based |
| `3240` | `RTL_RoundInt` | `D9 FC` = `FRNDINT` |
| `324e` | `RTL_Sqrt` | `D9 FA` = `FSQRT` |
| `3252` | `RTL_Sin` | see below |
| `3257` | `RTL_Cos` | see below |
| `325c` | `RTL_ArcTan` | |
| `3420` | `RTL_FileAssign` | copies Pascal string into FileRec |
| `345b` | `RTL_FileReset` | |
| `34dc` | `RTL_FileClose` | |
| `3501` | `RTL_FileCheckOpen` | |
| `3546` | `RTL_FileBlockRead` | scales by RecSize, INT 21h, divides back |
| `35ae` | `RTL_FileSeek` | scales by RecSize, INT 21h |
| `36f2` | `RTL_Shl32` | `DX:AX shl CX`, with an 8086/386 branch |

### Sin vs Cos

The math routines form a contiguous run of 5-byte stubs. `Sqrt` is
independently identifiable (`D9 FA` = `FSQRT`), which anchors the ordering:
**Sqrt, Sin, Cos, ArcTan, Ln, Exp** — exactly how Turbo Pascal's System unit
groups them.

Usage agrees independently. Part 003's Scene 2 point generator calls
`137b:3257` and stores the result as the X coordinate, then calls `137b:3252`
for Y — `x = r·cos, y = r·sin`. Scene 1 does the same.

## Why the file group matters

`RTL_FileSeek` and `RTL_FileBlockRead` named in every part is what makes the
`NEUROSIS.DAT` asset map recoverable — see [04-neurosis-dat.md](04-neurosis-dat.md).

## Aside: `var` vs typed constants

Worth stating plainly because it decides where data lives, and therefore
whether a reconstruction is real source or a skeleton.

| Declaration | Lands in | In the EXE file? | Writable |
|---|---|---|---|
| `var X : T;` | BSS (uninitialised) | **no** | yes |
| `const X : T = (...);` | initialised data | **yes** | yes, in BP7 by default |

So anything we can *read out of the file image* was a typed constant in the
original source. In part 003 that includes the tunnel palette (`DS:$0002`), the
sine table (`DS:$02A8`) and the Scene 3 shapes (`DS:$0636`) — all sitting in
one packed block at the bottom of DGROUP.

That BP7 typed constants are writable by default is not incidental: the tunnel's
band rotations shuffle the palette arrays in place every frame, which would be
illegal for a true read-only constant.

`tools/emit_pascal_data.py` writes these back out as Pascal declarations into
`src/gen/`, included by the reconstructed units. Without them the source would
compile to a different binary.
