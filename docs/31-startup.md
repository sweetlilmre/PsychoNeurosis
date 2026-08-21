# NEUROSIS.000 — STARTUP.PAS, charted

Read from `bin/NEUROSIS.000` for [Chart NEUROSIS.000](https://github.com/sweetlilmre/PsychoNeurosis/issues/22). Supersedes `docs/20-parts000-009-setup-and-end.md` where they disagree ("70 functions" was a disassembly count including the RTL; the program has seven routines).

## G0 — the container

17,426 bytes on disk = 12,880-byte load image + 4,546 bytes of Borland debug info, zero residue (`tddump.py`). Source **`STARTUP.PAS`, saved 1994-02-06 00:11:08** — twenty-nine hours before the demo shipped.

## G1 — identification

Turbo Pascal 7, **four** modules: the program, a unit named **`Detect`** (not Borland's — three hand-asm probes in 49 bytes), `Crt`, `System`. `{$G+}` (`PUSH imm` throughout) and `{$S+}` (`__StackCheck` called everywhere) — same flags as BYEBYE, opposite of the demo parts.

| segment | runtime | module | length |
|---|---|---|---|
| 1 | `1000` | the program | `$1AC7` |
| 2 | `11AD` | `Detect` | `$31` |
| 3 | `11B1` | `Crt` | `$61F` |
| 4 | `1213` | `System` | `$D95` |

## G2 — the chart

Seven program routines plus three in `Detect`, all named by the debug info, extents from its scope table:

| routine | extent | lines | reading |
|---|---|---|---|
| `YesNo` | `0039`–`00C2` | 5–16 | writes the prompt at `CS:0000`; loops `ch := UpCase(ReadKey)` until `'Y'` or `'N'`; on `'N'` writes `'Later, dudes!'` (`CS:002B`) and **`Halt(0)`** |
| `WriteStr(s, x, y, col)` | `00C3`–`0171` | 20–25 | prints `s` at column/row in colour — locals `x, y, col, s, loop1`; compiled Pascal |
| `detected` | `01B9`–`0215` | 28–37 | paints the DETECTED box: `'DETECTED :'` at (45,18) colour 30, `'VGA Card'` (50,20), `'386/486'` (50,21), then `IsProtMode` choosing `'Protected mode'`/`'Real mode'` (50,22), colour 7 |
| `ChooseCard` | `09E3`–`176E` | 46–315 | the menu machine, 3,468 bytes — see below |
| `IsVGA` | `176F`–`1797` | 319–332 | inline asm (line-table density): `INT 10h AX=1A00h`, VGA if `BL` in 7..12 — **and the result is returned from the never-assigned result variable**, see the defect note |
| `Detections` | `18B8`–`19A1` | 335–353 | `IsVGA` else `'VGA not detected! ByeBye'` + `Halt(0)`; `Is386` else `'386 processor not detected! ByeBye'` + `Halt(0)`; `IsProtMode` → three warning lines + `YesNo` |
| main | `19F0`–`1AC6` | 355–376 | memory gate, then the flow below |
| `Detect.Is386` | `11AD:0000`–`0013` | — | hand asm: FLAGS bits 12–14 writability test |
| `Detect.IsProtMode` | `11AD:0014`–`001A` | — | hand asm: `SMSW AX / AND AX,1` |
| `Detect.HasMouse` | `11AD:001B`–`0030` | — | hand asm: INT 33h vector null-check at `0000:00CC`, then `INT 33h AX=0` (linked but not seen called by the program's own code) |

**Main**: `if MemAvail + 28944 < 620000` → write `'You do not have enough memory to run this demo.'`, `'You need : '`, the exact shortfall in bytes, `' extra bytes free'`, and **`Halt(2)`** — the "quit silently" code in PSYCHO's protocol, measured at its source. Otherwise `ClrScr`, `TextColor(7)`, hide the cursor (`INT 10h AH=1, CX=$FF09`), `Detections`, `ChooseCard`, `ClrScr`, `TextColor(0)`, `Halt(0)`.

### ChooseCard, structurally

Locals say most of it: `opt : array[1..7] of String` (the current menu's labels), `forfile : array[1..5] of String` (the switch lines chosen so far), `f : Text`, `loop1, loop2 : Integer`, `ch : Char`, and a **`label forfile`**-style goto target is *not* what `forfile` is — it is the accumulator. The literal pool before it (`CS:0217`–`09B1`) is the whole state machine's content:

- menus: sound card (7 options), IRQ (7/5), DMA (0/1/3/5/7), port (210h–270h), sampling rate (8000–40000 Hz), with headers `'Please Select your Sound Card:'`, `'…IRQ setting:'`, `'…Sampling rate:'`;
- their cfg lines: `/d:DMA-SB-Mono`, `/d:DMA-SB-Stereo`, `/d:GUS`, `/d:Silence`, `/irq:N`, `/dma:N`, `/port:$NNN`, `/f:NNNNN`, plus `/v:127`;
- the filename `'neurosis.cfg'`;
- **and the demo chain itself**: seven lines `neurosis.001 /off:38528 /sh:neurosis.001` … `neurosis.007 /off:20112 /sh:neurosis.007`.

So **the chain of parts 001–007 is authored here**: setup writes it into `NEUROSIS.CFG`, and DemoVT (which receives `@neurosis.cfg` from the launcher) plays music and executes the parts off that list. `PSYCHO.EXE` (docs/29) EXECs three children; this file writes the script for the fourth actor. The `/off:` values are per-part offsets whose meaning belongs to DemoVT (the VangeliSTracker repo's territory).

`Halt(1)` — PSYCHO's "skip the demo, show the end screen" — has not been sighted yet; it must be inside `ChooseCard` (the `Exit` menu option is the obvious suspect). The reconstruction ticket settles it.

### Two original defects, recorded as behaviour to preserve

- **`IsVGA` returns garbage that is accidentally always True.** The asm computes the answer into `AX` but the function epilogue returns the *never-written* result variable `[BP-1]` — which at that point holds the high byte of the `__StackCheck` call's pushed return segment: nonzero on any real machine, so the Boolean reads True and the VGA gate never fires. A verbatim reconstruction preserves this exactly; an "obvious fix" would change behaviour on no machine that exists, but the bytes would differ.
- **Failed detections `Halt(0)`,** which PSYCHO's protocol reads as "run the demo" — a machine without a 386 is told `'ByeBye'` and then the demo is launched at it anyway (with the previous cfg, since setup never wrote one). `YesNo`'s `'N'` branch does the same. Only low memory (`Halt(2)`) actually stops the show.

## The reconstruction: byte-identical

`src/STARTUP.PAS` + `src/DETECT.PAS` (a TASM object, `src/asm/DETECT.ASM`, linked `{$L}`) rebuild to a **load image byte-identical to the original's 12,880 bytes** — the third and last of the unread binaries at R7. The near-match iteration ran 569 → 98 → 22 → 9 → 1 → 0 diff runs, and each step recovered a fact about the 1994 source:

- **`YesNo` waits with `until ch in ['N','Y']`** — the single-load compare chain, not two equality tests.
- **Every selection is a `case`** — the arrow handlers (`case ch of 'P','H'`), the Previous-Setup/Exit pair, and all five `forfile` assignments. An `if`/`else if` chain compiles a memory compare per arm; the original loads once.
- **Each menu's initial highlight is `WriteStr(opt[loop2], 22, loop2 + 8, 30)`** — indexed and computed, even though `loop2` is always 1 there.
- **`WriteStr` addresses the screen as `x*2 + loop1*2 + y*160 - 2`** — recovered from TP7 computing the rightmost additive term first.
- **`Detections`' protected-mode branch writes a second blank line** before `YesNo`.
- **`Detect` is a TASM object linked whole** — proven twice: the pure-Pascal unit lost the never-called `HasMouse` to the smart linker, and the original's `XOR AX,AX` is `33 C0`, TASM's operand order where BASM emits `31 C0`. TASM needs `.286P` for `SMSW`.
- **The `uses` clause is `Crt, Detect`** — TP7 emits unit code segments in *reverse* uses order, measured when the two segments came out swapped.

All fingerprints are recorded as new rows in the wiki's [near-match-diff](../wiki/observations/near-match-diff/observation.md) table. The three `Detect` routines carry `@asm` markers (coverage 71 → 74); `asmverify.py` finds them in `STARTUP.EXE` and matches all three end to end.
