---
type: Observation
title: Readable text sits between the routines
description: Gaps between a Turbo Pascal program's routines hold its string literals, length-prefixed and walkable -- the program's menus, messages and filenames, before any instruction is read.
tags: [strings, code-segment, turbo-pascal, charting]
timestamp: 2026-08-21T00:00:00Z
---

# Readable text sits between the routines

Charting a Turbo Pascal program, the extents of its routines leave gaps in the code segment, and the gaps contain readable text.

**Those are the program's string literals, and they are walkable as data.** TP7 pools a routine's string constants into the code segment near their user; each is a Pascal string — one length byte, then exactly that many characters. Starting from a gap's first byte, read a length, take that many characters, repeat: when the walk yields clean printable strings end to end, you have the pool, each literal's `CS:offset` (which the code references as an immediate), and — often — the program's whole user-facing behaviour before a single routine is disassembled.

What fell out of one such walk on a setup program: every menu, every config switch it can write, its output filename, and the list of seven other executables it schedules — the content of a 3,468-byte routine, read from its literal pool in seconds.

## Why it works

String literals must live somewhere addressable, TP7 chooses the code segment, and the Pascal string layout is self-describing. The pools sit between routines because the compiler emits them adjacent to the code that uses them.

## Blind spot

**A length byte is just a byte.** A pool walked from the wrong start, or a gap that is actually data or padding, can still yield "strings" — a printable run after a plausible length byte is weak evidence on its own. Anchor the walk: the code references each literal by its exact offset (`MOV DI, imm` / `PUSH CS` / `PUSH DI` in TP7's calling pattern), so a literal is confirmed when an instruction cites its first byte. And text the program builds at run time, or reads from files, never appears in any pool.

## Cost

The load image and a ten-line script. No disassembler, no toolchain.

## Example

`NEUROSIS.000`'s four pools (`docs/31-startup.md`): the DETECTED box labels, the full menu tree with its `/d:` `/irq:` `/dma:` `/port:` `/f:` config vocabulary, `'neurosis.cfg'`, and the seven-line demo chain — the finding that settled where the part sequence is authored. [1]

# Citations

[1] `docs/31-startup.md`, the ChooseCard section, in the psycho repository.
