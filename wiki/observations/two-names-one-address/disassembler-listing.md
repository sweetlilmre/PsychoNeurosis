---
type: Artefact Answer
title: Two names from a disassembler's segment listing
description: The tool's segment ranges are derived and can overlap, so one routine is listed under two segments.
order: 1
holding: a disassembler's segment listing
identify: the address came from the tool's segment map -- a routine listed under two segments, or sitting at or past a segment's computed end
artefact: segment listing
tier: substrate
ladder_node: G2
tags: [ghidra, segments, charting]
timestamp: 2026-08-21T00:00:00Z
---

# Two names from a disassembler's segment listing

Part of [The same bytes answer to two different addresses](./observation.md).

## What to do

Treat the listing as derived, never authoritative. A segment's real extent is `(next segment's base - this base) * 16` bytes; any routine listed at or past that extent belongs to the *next* segment, and the double listing is the tool naming the same linear bytes twice. Compute the linear address of both listings; if they are equal there is one routine, and the copy under the earlier segment is an artefact to delete from your chart.

## Why it works

Real-mode segments are just base paragraphs, and a disassembler that derives per-segment ranges from symbols or heuristics can make them overlap. Ghidra lists a routine under two segment bases when the ranges overlap; the second listing looks exactly like a second routine. The arithmetic is the whole cure because linear addresses are what the machine actually fetches.

## Blind spot

**Byte-identical is not linear-identical.** Two routines at *different* linear addresses can still compare equal because the program genuinely carries two copies -- Turbo Pascal links a unit's code into every program that uses it, and one program can hold a routine twice under two units. The linear test separates "one routine, two names" from "two real copies"; a byte comparison alone cannot. [2]

## Cost

Arithmetic on addresses already in hand. No build, no disassembler run beyond the listing you already have.

## Example

Charting `PSYCHO.EXE` (1,936 bytes), the trap fired twice in one session: the `Exec` routine was listed under a segment `100b` while the call named `1000:00b0` -- same linear `0x10b0` past the image base -- and `Sprites`-era history shows the same defect at project scale: `SetMode13h`'s "copies" at `1483:00E0`/`1491:0000` and `142A:00C0`/`1436:0000` were one routine each, one byte past the computed end of the earlier unit. [1] [2]

## Withdrawn

The original conclusion this page corrects: "the original simply duplicated small routines across units", argued from the double listing. Withdrawn when the extents were computed -- four such artefacts fell in one sweep, and one had been hiding a real error underneath. [2]

# Citations

[1] `docs/29-psycho-launcher.md`, the chart's segment table, in the psycho repository.

[2] `docs/continuation.md` (untracked working register in the psycho repository), section "Ghidra's segment ranges OVERLAP, and I read the overlap as duplication". **Gist restated here** because the file is deliberately untracked: a unit's real extent is `(next base - base) * 16`, both "duplicates" sat exactly one byte past an end, and the rule written there is the one this page carries -- convert to LINEAR and compare before believing duplication.
