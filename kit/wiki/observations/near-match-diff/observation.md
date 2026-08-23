---
type: Observation
title: The rebuild nearly matches, and the last bytes name their causes
description: A handful of differing bytes between a rebuilt image and the original -- each diff pattern is a fingerprint of one source-level or switch-level fact.
tags: [comparison, turbo-pascal, codegen, byte-diff]
timestamp: 2026-08-21T00:00:00Z
---

# The rebuild nearly matches, and the last bytes name their causes

You rebuilt a Turbo Pascal program from reconstructed source, the logic is right, and the byte comparison against the original leaves a small number of differences. **Do not tune at random: each diff pattern is a fingerprint of one specific fact about the original source or its compiler switches.** Read the pattern, change that one thing, and the diff count falls in steps, not gradually.

Patterns measured so far, each closed by exactly one change:

| you see | it means | the one change |
|---|---|---|
| `75 02 EB xx xx` (`JNZ +2` over `JMP`) where yours has a short conditional jump | the original statement was `if X then goto L` with a forward label -- TP7 emits the jump-over-jump because the label's distance is not yet known; an `if`/`begin` block emits the short jump instead | write the `goto`, with the tests in the original's order |
| `C9` (`LEAVE`) where yours has `5D` (`POP BP`) at a routine's end | the original was compiled `{$G+}` -- `LEAVE` is a 286 encoding, and with `$G-` TP7 closes the frame with `POP BP` | set `{$G+}` |
| every relocation entry after some point shifted by a constant | your code upstream of that point is longer or shorter than the original's by that constant -- the relocations are right, the code before them is not | fix the code-shape diff earlier in the image; the relocations follow by themselves |
| comparisons in a different order than yours | source statement order, not optimisation -- TP7 does not reorder tests | match the original's statement order |
| one register load followed by a chain of `CMP AX/AL, imm`, where yours reloads memory per test | the original was a `case` statement (or a constant-set `in` test) -- an `if`/`else if` chain compiles a memory compare per arm | write the `case` (or the `in`) |
| a routine present in the original that nothing calls, missing from yours | the original linked a TASM object whole with `{$L}` -- Pascal smart-links per routine and drops the uncalled; `XOR r,r` as `33 Cx` (TASM operand order) instead of BASM's `31 Cx` corroborates | move the routines to a `.ASM` linked with `{$L}` |
| two whole unit code segments swapped | TP7 emits unit segments in REVERSE `uses` order | swap the `uses` clause |
| an additive chain computed back to front | TP7 computes the RIGHTMOST term of `a + b + c` first -- the first-computed term in the bytes is the source's last | reorder the expression's terms |

## Why it works

TP7 has no optimiser to speak of: statement shape maps to instruction shape nearly one to one, and the code-generation switches change single encodings. So a small residual diff is not noise to be minimised -- it is a message naming a source construct or a switch. This is the same property that makes the byte instrument usable at all on this compiler.

## Blind spot

**The fingerprint table only names causes that have been measured once.** A pattern not in the table means the cause is still unknown, not that the table's nearest row applies. Add the row when the cause is proven by a build, never by analogy -- five of six claimed compiler differences in this project's history were our own source.

## Cost

A built image, the original, and a byte comparison. The period toolchain must already stand up; no disassembler is needed to read the patterns, though one names the instructions.

## Example

`PSYCHO.EXE`, rebuilt from a chart: 76 differing bytes fell to 1 by writing the two `goto`s (which also restored every shifted relocation), and to **0 -- SHA256-identical, 1,936 bytes** -- by setting `{$G+}`. Two facts about the 1994 source were recovered from the diff alone. [1]

# Citations

[1] `docs/29-psycho-launcher.md`, the reconstruction section, in the psycho repository.
