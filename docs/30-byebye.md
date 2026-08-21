# NEUROSIS.009 — BYEBYE.PAS, charted

Read from `bin/NEUROSIS.009` for [Chart NEUROSIS.009](https://github.com/sweetlilmre/PsychoNeurosis/issues/21). Supersedes the sketch in `docs/20-parts000-009-setup-and-end.md` where they disagree — in particular, the "38 functions" figure there was a disassembly count, not a debug-info fact, and `IMAGEDATA` is not a picture.

## G0 — the container

10,356 bytes on disk = 7,312-byte load image + 3,044 bytes of appended Borland debug info, exactly. The tail decodes with zero residue (`toolkit/substrate/tddump.py`, format in `docs/research/borland-debug-info.md`): source file **`BYEBYE.PAS`, saved 1994-02-04 18:31:14**, modules PROGRAM / `Crt` / `System`, 132 symbols, 25 line-number entries, 3 segments.

## G1 — identification

Turbo Pascal 7, `uses Crt`, no other units. Three segments, named by the debug info itself:

| segment | runtime | module | length |
|---|---|---|---|
| 1 | `1000` | the program | `$62` = 98 bytes |
| 2 | `1007` | `Crt` | `$61F` |
| 3 | `1069` | `System` | `$592` |

The program's own symbols: `IMAGEDATA` at `DS:0002` (a 4,000-byte typed constant — `IMAGEDATA_WIDTH`=80, `IMAGEDATA_DEPTH`=25, `IMAGEDATA_LENGTH`=4000: **an 80×25 text screen with attributes**, not a picture), `P : Pointer` at `DS:0FF0`, `Flag : Byte` at `DS:0FF4` (never referenced by the code). The `INT 10h`/`INT 21h` counts `docs/20` recorded live in `Crt` and `System`, not in the program.

## G2 — the chart

Main is the whole program: 98 bytes, 37 instructions, every one read. The debug info's line table maps it to source lines 300–340 — so `BYEBYE.PAS` was ~340 lines, mostly the `IMAGEDATA` typed constant above main.

**Lines 304–334 advance one line per instruction: the body's core is an inline BASM `asm` block** (see the wiki's [line-table-reveals-asm](../wiki/observations/line-table-reveals-asm/observation.md)); the gaps in the numbering are its blank lines. Around it, compiled Pascal.

```
line  offset
300   0000  entry: CALLF System:0000 (init), CALLF Crt:000D (Crt init),
            PUSH BP / MOV BP,SP, XOR AX,AX / CALLF System:02CD (__StackCheck, 0 locals)
301   0014  ClrScr                                  (CALLF Crt:01CC)
302   0019  P := Ptr(DSeg, 2)                       { @IMAGEDATA }
      -- asm block, one instruction per line --
304   0025  PUSH DS
306   0026  MOV  BX, 25                              { Row := 25 }
310   0029  loop: LDS SI, [P]
312   002D  MOV  AX, 160
313   0030  MUL  BX
314   0032  ADD  SI, AX                              { SI := P + Row*160 }
316   0034  MOV  CX, 2000
317   0037  SHR  AX, 1
318   0039  SUB  CX, AX                              { CX := 2000 - Row*80 words }
320   003B  MOV  AX, $B800
321   003E  MOV  ES, AX
322   0040  XOR  DI, DI
324   0042  REP  MOVSW                               { image tail -> screen top }
326   0044  PUSHA
327   0045  PUSH 100
328   0047  CALLF Crt:02A8                           { Delay(100) }
329   004C  POPA
331   004D  DEC  BX
332   004E  JNZ  loop
334   0050  POP  DS
      -- Pascal again --
338   0051  GotoXY(1, 23)                            (PUSH 1 / PUSH 23 / CALLF Crt:021F)
340   005A  LEAVE; Halt(0)
```

**What it does**: the sign-off screen scrolls up into view from the bottom. Each pass copies the last `25-Row+…` — concretely, `2000 - Row*80` words from `IMAGEDATA + Row*160` — to the top of text video memory, so at `Row=24` only the image's last row shows at the top, and by `Row=1` all but the first row is on screen, at ten frames a second (`Delay(100)`). The final `GotoXY(1,23)` parks the DOS prompt below the artwork. (Note `Row=25` copies zero words and `Row=0` never runs: the image's first row is never drawn — visible in the original too, presumably invisible because row 1 is blank.)

## Build flags, measured

- **`{$S+}` — stack checking ON.** `System:02CD` is `__StackCheck` (checks against `StackLimit` at `DS:0FDA`, runtime error 202 on failure) and main calls it. The demo parts are built `/$S-`; **the BYEBYE reconstruction must re-enable it in-source or its bytes will not match.**
- **`{$G+}`** — `PUSHA` and `PUSH imm` are 286 encodings (here the author's own, inside the asm block, which BASM only accepts under `$G+`); the compiled `LEAVE` at `005A` agrees.

## For the reconstruction (#24)

- `IMAGEDATA` must be extracted from the binary's data segment (4,000 bytes at DGROUP+2) into a typed constant — the extraction route needs deciding (an emitter into `gen/`, per the part-006 pattern).
- The asm block is transcribed verbatim under THE RULE, one instruction per line as the line table proves the original was, with the per-line comments above.
- `Flag` is declared and unused; keep it — it is part of the data-segment layout the debug info records.
