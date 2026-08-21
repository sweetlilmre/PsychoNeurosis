---
type: Artefact Answer
title: Two names from a far-call or far-pointer operand
description: The pair encoded in the bytes uses whatever normalization the linker chose, not the segment map's name.
order: 2
holding: a far-call or far-pointer operand
identify: the address is encoded in an instruction or data, and it disagrees with the segment map's name for the same target
artefact: far operand
tier: substrate
ladder_node: G2
tags: [mz, relocation, far-call, charting]
timestamp: 2026-08-21T00:00:00Z
---

# Two names from a far-call or far-pointer operand

Part of [The same bytes answer to two different addresses](./observation.md).

## What to do

Compute the operand's linear address and look it up in the segment map by *linear* position, ignoring the segment half of the printed name. The target is whatever routine's extent contains that linear address, whatever pair the instruction spells it with.

## Why it works

In an MZ executable a far operand's segment word is a relocation slot: the linker stores some base-relative value, the loader adds the actual load segment, and *which* base-relative value the linker stored is its own choice -- it does not have to match the name the segment map gives the target. A call encoded `1000:0190` and a map entry `1019:0000` are the same linear byte spelled two ways.

## Blind spot

**An operand that was never relocated really is a different address.** If the segment word is not in the relocation table, it is an absolute segment (a `0xA000` video write, a BIOS entry) and the linear arithmetic against the image base is wrong for it. Check the relocation table before normalising: the table says which operands play this game.

## Cost

The MZ relocation table (a header read) and arithmetic. No disassembler needed beyond the operand itself.

## Example

`PSYCHO.EXE`'s program body calls `CALLF 1000:0190` and `CALLF 1000:02a6`. Neither offset exists in segment `1000`'s own code; linear, they are `1019:0000` and `1019:0116` -- the Turbo Pascal RTL's init and `Halt`. Read as printed, the chart would have contained two calls into a gap. [1]

## Withdrawn

None recorded yet for this artefact.

# Citations

[1] `docs/29-psycho-launcher.md`, the chart's call table, in the psycho repository.
