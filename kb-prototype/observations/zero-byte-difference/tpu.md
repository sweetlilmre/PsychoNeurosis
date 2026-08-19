---
type: Artefact Answer
title: A zero byte in a .TPU
description: In an unlinked Turbo Pascal unit, a zero is where the linker has not filled in a reference yet.
order: 1
holding: a `.TPU` from Turbo Pascal
summary: Forgive it, but only where YOUR byte is the zero one.
artefact: TPU
tier: pascal
ladder_node: R7
tags: [comparison, fixups, turbo-pascal]
timestamp: 2026-08-19T00:00:00Z
---

# A zero byte in a `.TPU`

Part of [A zero byte where the original has something else](./observation.md).

## What to do

Forgive the difference **only where your byte is `0x00`**. If your byte is anything else, it is a real difference and the rule does not apply.

Forgive nothing on the strength of the original's byte. The test is one-directional: your zero against their value, never the reverse.

## Why it works

A `.TPU` is not linked. Every reference the linker still has to resolve -- a variable in DGROUP, a call into another unit -- sits in the byte stream as zero, while the original you are comparing against has the resolved value already in place.

The rule is safe because the placeholder is a *fixed* value rather than a plausible one:

> A wrong branch direction, a swapped operand or a different instruction will not coincidentally emit zero. [1]

## Blind spot

**A zero is only evidence of a pending fixup if something is actually pending.** This is the rule's own hole and it was found the hard way.

A near call to a label inside the same unit is *not* a fixup. So a zero there is a real defect that this rule reads as agreement -- "a bug wearing a fixup's clothes". One such call ran to a one-byte stub for the whole life of a unit and every comparison passed. [1]

Two more, both narrower and both real:

- `DW OFFSET` fixups also sit as zeros. Four gain-table pointers were three bytes short, invisibly, for as long as an offending `JMP` existed. [1]
- A same-unit near `CALL` is left as zeros and excused, so **a call inside the unit is not evidence its target is right.** That is the exact opposite of the jump-displacement rule, which treats a displacement as checkable. Do not carry the intuition from one to the other. [1]

## Cost

A built `.TPU` and a byte comparator. So: DOSBox and a working period toolchain, because the `.TPU` has to be freshly compiled to be comparable. No disassembler.

## Example

The `verify.py` comparison of a `.TPU`'s CODE section against the original's segment. See [2].

## Withdrawn

None recorded for this artefact. The withdrawn conclusions attached to this observation belong to the `.OBJ` case -- see [obj-tasm](./obj-tasm.md).

# Citations

[1] `06-transcription.md`, sections on the zero rule and on pending fixups, in the VangeliSTracker repository. **Quoted inline above** because that document is in a different repository and cannot be resolved from this one.

[2] `CONTINUATION.md`, the seven-measures table, in the VangeliSTracker repository. Its row for `verify.py` reads: compares "a `.TPU`'s CODE against its segment", and cannot see "every DGROUP address and inter-unit call -- they are pending fixups it excuses. Also cannot see whether a routine is an init section or a named procedure."
