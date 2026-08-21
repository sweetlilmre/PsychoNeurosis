---
type: Observation
title: The line table advances one line per instruction
description: In Borland debug info, a run of line-number entries stepping one instruction each marks a BASM asm block -- the compiler maps each assembler line to its own instruction.
tags: [debug-info, basm, hand-assembler, identification, pascal]
timestamp: 2026-08-21T00:00:00Z
---

# The line table advances one line per instruction

You have Borland debug info with a line-number table, and a stretch of it maps a *new source line to nearly every instruction*, while the rest of the routine maps one line to several instructions.

**That stretch is an inline `asm` block.** Turbo Pascal's built-in assembler puts one instruction on one source line, so the compiler's line table steps line-by-line through it; compiled Pascal statements each cover several instructions, so their entries are sparser. The boundary where the density changes is the `asm` keyword, readable without disassembling a single byte of the routine.

Gaps in the line numbers inside the dense stretch are the source's blank and comment lines -- they even sketch how the original author grouped the assembler.

## Why it works

The line table exists so a debugger can step by source line. For Pascal, a line is a statement; for BASM, a line is an instruction. The table faithfully records whichever the compiler saw, so the mapping's *density* betrays the source's language even though the bytes alone do not.

## Blind spot

**It needs the debug info, which most shipped binaries strip.** And it cannot see `{$L}`-linked external assembler at all -- a TASM object carries no Borland line entries, so the technique marks only *inline* asm. Absence of a dense stretch is not absence of hand assembler; the `docs/09` behavioural tells still apply to everything the table cannot vouch for.

## Cost

`toolkit/substrate/tddump.py` over the binary; arithmetic on the printed table. No disassembler.

## Example

`NEUROSIS.009`'s main: lines 300-302 cover the entry, `ClrScr` and a pointer assignment at normal density, then lines 304-334 advance one instruction each -- the scroll loop is a BASM block, and the missing numbers inside the run (303, 305, 308-309, ...) are its blank lines. Confirmed against the disassembly: `PUSH DS` through `POP DS`, `REP MOVSW` included. [1]

# Citations

[1] `docs/30-byebye.md`, the chart's line-table section, in the psycho repository.
