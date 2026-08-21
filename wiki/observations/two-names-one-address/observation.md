---
type: Observation
title: The same bytes answer to two different addresses
description: A routine shows up at two segment:offset pairs, or two "different" routines are byte-identical -- segment:offset is a many-to-one name for a linear address.
tags: [segments, addressing, mz, ghidra, charting]
timestamp: 2026-08-21T00:00:00Z
---

# The same bytes answer to two different addresses

You are charting a real-mode program and something appears twice: a routine is listed under two `segment:offset` pairs, a call's target does not match any routine in the segment map, or two "different" routines in two "different" segments compare byte-identical.

**Nothing is duplicated until the linear addresses differ.** A `segment:offset` pair is a many-to-one name: `1000:0190` and `1019:0000` are the same byte at linear `0x10190`, and every tool in the chain -- the linker, the loader, the disassembler -- is free to pick a different pair for it. Before believing that two parts differ, or that one part duplicates something, convert both names to linear (`segment * 16 + offset`) and compare those.

The question this page answers is: **which artefact handed you the second name?**

<!-- generated:discriminator -->
| if you are looking at | how to tell | detail |
|---|---|---|
| a disassembler's segment listing | the address came from the tool's segment map -- a routine listed under two segments, or sitting at or past a segment's computed end | [disassembler-listing](./disassembler-listing.md) |
| a far-call or far-pointer operand | the address is encoded in an instruction or data, and it disagrees with the segment map's name for the same target | [far-operand](./far-operand.md) |
<!-- /generated:discriminator -->

## Why the answer cannot be general

The two cases fail in opposite directions. A derived segment listing invents a *second routine* that does not exist, so trusting it produces phantom duplication -- transcribing the same six bytes into two units. An encoded far operand names a *real* target by a pair the map never uses, so trusting the map produces a phantom gap -- a call into "nothing", or into the middle of the wrong unit. One mechanism, two artefacts, two opposite wrong conclusions.

## If you are not sure which you have

Ask where the printed address came from. If a tool computed it from segment boundaries, it is the listing case. If the bytes of the program contain it, it is the operand case. Then do the same arithmetic either way: linear first, conclusions second.
