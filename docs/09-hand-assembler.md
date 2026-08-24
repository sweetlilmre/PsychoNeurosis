# Spotting hand assembler

Parts of the demo are hand-written assembler rather than compiled Pascal.
Reconstructions must preserve those as `assembler` procedures rather than
paraphrasing them into Pascal, so it matters that we can tell them apart.

## Tells

**Compiled Borland Pascal 7:**

- ~~`ENTER` / `LEAVE` with BP-relative locals~~ -- **WITHDRAWN, 24 Aug 2026.** This is not a tell in either direction and it cost this project the largest unaligned span in the corpus. Borland emits its standard frame for an `assembler` procedure that declares local variables, so a hand-written routine with locals opens `ENTER n, 0` exactly like a compiled one. `Tri_Fill` at `108b:0461` opens `ENTER $28` over 40 bytes of declared locals and is hand assembler throughout; it was read as compiled Pascal for that reason, transcribed as Pascal, and 1,276 bytes never aligned.
- calls into RTL helpers for range checks, long arithmetic, Real conversion
- a multiply where a lookup table would do
- arguments on the stack, results in AX/DX

**Hand-written assembler:**

- **no prologue at all**, or `PUSH BP / MOV BP,SP` with no locals
- string instructions: `REP MOVSW`, `REP STOSW`, `REP OUTSB`, `STOSB`
- `LOOP`, direct segment register loads, `LDS`/`LES` on parameters
- precomputed offset tables instead of multiplies
- fully unrolled bodies — BP7 does not unroll loops
- arguments arriving in registers (BX/CX/DX) rather than on the stack
- **BP used as a scratch register** between a `PUSH BP` and a `POP BP` inside a framed routine. The code generator will not clobber its own frame pointer, and every BP-relative operand in such a stretch is necessarily read before the clobber.
- **a general-purpose value parked in a segment register** — `MOV ES,BX` to free BX as an index — which no code generator has any notion of doing
- **`REP STOSW` / `ADC CX,CX` / `REP STOSB` inline**, the word-then-odd-byte fill. `FillChar` is a far call into the runtime and is never inlined.
- **every two-byte register-to-register op in the store direction** (`MOV AX,BX` as `89 D8`, not `8B C3`). This one is a measurement rather than an impression and it is the strongest of the set: the general form, what it can and cannot identify, and a conclusion it was first read wrong are in the wiki, [`direction-bit-names-basm`](../kit/wiki/observations/direction-bit-names-basm/observation.md).

## Confirmed hand assembler

**The whole VGA unit** (segments `12f8` + `1192` in part 003) — see
[05-vga-unit.md](05-vga-unit.md) and `src/VGA.PAS`. The clincher is
`WaitRetrace` at `12f8:009f`, which has no procedure prologue whatsoever:
straight into `MOV DX,$3DA`, out via `RETF`.

| Routine | Address | Tell |
|---|---|---|
| `VGA_WaitRetrace` | `12f8:009f` | no prologue at all |
| `VGA_CopyScreen` | `12f8:00ad` | `REP MOVSW`, CX=32000, `PUSH DS`/`POP DS` |
| `VGA_ClearScreen` | `12f8:00c9` | `REP STOSW`, CX=32000 |
| `VGA_PutPixel` | `12f8:0048` | row-table lookup then `STOSB`, no multiply |
| `VGA_GetRGB` | `12f8:007f` | `LES DI` on var params, `STOSB` per channel |
| `VGA_SetPalette768` | `1139:0335` | whole DAC via one `REP OUTSB` |
| `VGA_GetPalette768` | `1139:034d` | matching read |
| `VGA_Set400Lines` | `1139:02f2` | bare CRTC read-modify-write |
| `Morph_TransformPoint` | `1139:0096` | args in BX/CX/DX, results in DI/BX |
| `ModeX_PlotPixel` | `1139:01bb` | consumes DI/BX directly |
| `Tri_Fill` | `108b:0461` | 62 of 62 reg-to-reg ops store direction; BP clobbered; `ES` parked; inline `REP STOSW`; X1/Y1/X2/Y2 in BX/CX/DX/SI |
| `Poly_FillFan` | `108b:09b1` | loads BX/CX/DX/SI for the call above, which no Pascal caller can do |

## Strong candidates, not yet transcribed

| Routine | Address | Tell |
|---|---|---|
| `Tunnel_UploadPalette` | `1015:0000` | tight `OUT`/`LOOP` DAC loop, three table pointers in BP locals |
| `Tunnel_RotateBandsFine` | `1015:017f` | 15 moves fully unrolled × 3 tables |
| `Tunnel_RotateBandsCoarse` | `1015:004d` | same shape, block rotate |
| `VGA_SetDisplayStart` | `1015:06b0` | CRTC + Attribute Controller sequence including the `$3DA` flip-flop reset |

## Note on fidelity

Where a routine takes its arguments in registers, the Pascal in `src/` is a
*behavioural description* rather than a literal translation, and the file says
so. Getting back to buildable source will mean writing those as `asm` blocks
with the original register discipline.

## Related trap: naming a 3-D model from one view

Not assembler, but the same class of mistake and it cost three wrong answers in
part 002. A model rendered from a single axis pair is easy to misname:

| Model | Looked like | Actually |
|---|---|---|
| 75 verts | a flying saucer (front) | the **USS Enterprise** (from above) |
| 68 verts | a street lamp (Y vertical) | a **revolver** (Y horizontal) |
| 32 verts | a telegraph pole (Y vertical) | a **sailboat** (Y horizontal) |

Models built along Y read as tall thin towers until Y is turned horizontal.
`tools/vecobj.py` now renders five axis pairs per object for this reason.
Render every view before naming anything.

## Register-convention calls found so far

Routines whose parameters arrive in registers rather than on the stack. These
cannot be expressed in plain Pascal and have to stay as `asm` blocks.

| Caller | Callee | Convention |
|---|---|---|
| `Morph_DrawMorph` `1139:021d` | `Morph_TransformPoint` `1139:0096` | X in `BX`, Y in `CX`, Z in `DX` |

`Morph_DrawMorph` also saves the two shape pointers with `PUSH DI` / `PUSH SI`
around the per-point calls precisely so the callees can use `SI` and `DI`
freely — another sign it was written as assembler rather than compiled.
