---
type: Artefact Answer
title: A zero byte in an .OBJ assembled by TASM
description: TASM leaves an addend, not a zero, so the zero rule is wrong here -- read the relocation records instead.
order: 2
holding: an `.OBJ` assembled by TASM
summary: Do not use the zero rule at all. Read the FIXUPP records instead.
artefact: OBJ
tier: substrate
ladder_node: R7
tags: [comparison, fixups, relocation, omf, tasm]
timestamp: 2026-08-19T00:00:00Z
---

# A zero byte in an `.OBJ` assembled by TASM

Part of [A zero byte where the original has something else](./observation.md).

## What to do

**Do not use the zero rule.** Read the **FIXUPP records** in the OMF object file and build the set of relocated positions from them. Then forgive a byte because the assembler *recorded a relocation there* -- never because the byte happens to be zero.

> That is stricter than the zeros heuristic, not looser -- a byte is excused because the assembler recorded a relocation there, not because it happens to be zero. [1]

## Why it works

TASM resolves whatever it can and leaves an **addend** in the placeholder, not a zero. `DW OFFSET Label` becomes the offset from the module's own start. `Volumes[2]` becomes the displacement `2`.

> Against a linked binary both are flat mismatches, and no rule about the bytes can tell them from real ones. [1]

That is the whole problem in one sentence. The placeholder is a plausible-looking value, so no rule *about the bytes* can separate it from a genuine difference. Only the assembler's own record can.

## Blind spot

**It is only as good as the assembler's own record.** It excuses whatever TASM chose to relocate and says nothing about whether the **addend** is correct. It can print the implied offset for a human to recognise, but it cannot validate the *symbol* half of the reference.

It is also blind to anything outside the assembled run, and to DGROUP contents entirely.

Because of that, the mask was **checked a second way** -- and this is the discipline the blind spot demands rather than an optional extra. All 192 word fields were classified: 112 code self-references off by exactly the module base, 7 DGROUP symbols with an addend, 73 zeros, and **0 unexplained**. A classification that leaves nothing unexplained is the check; a count of differences is not.

## Cost

The `.OBJ` file and an OMF record parser. **No built executable, no DOSBox, no disassembler** -- so this is markedly cheaper than the `.TPU` case, which needs the whole period build chain.

## Example

The four-line classification above, from the DemoVT byte-exact rebuild. See [2].

## Withdrawn

**The zero heuristic was applied here first, and it was wrong in both directions at once.**

- The first measurement of a module that was **actually correct** reported **65 divergent regions**. [1]
- Another run gave **27 phantom differences for 36 relocation bytes**. [1]

The lesson generalises past this page, and it is the reason the observation hub refuses to state a general rule: **a tool's idea of an acceptable difference is part of the measurement.** The same excuse-a-zero heuristic is exactly right one artefact over and catastrophically wrong here.

# Citations

[1] `06-transcription.md`, section on reading FIXUPP records, in the VangeliSTracker repository. **Quoted inline above** because that document is in a different repository and cannot be resolved from this one.

[2] `CONTINUATION.md`, the OMF fixup classification, in the VangeliSTracker repository. Also recorded as project memory `demovt-obj-fixups`, whose one-line form is: "a tool's idea of an acceptable difference is part of the measurement; zeros are a `.TPU` rule, not an assembler one."
