---
type: Observation
title: Every declared routine matches, and the rebuild still behaves differently
description: A byte check that walks a list of declared routines cannot see a routine nobody declared; align every byte of the original's user segments instead, and read the spans that will not align.
tags: [verification, coverage, hand-assembler, tooling, pascal, rebuild]
timestamp: 2026-08-23T00:00:00Z
---

# Every declared routine matches, and the rebuild still behaves differently

Your byte check is green. Every routine it knows about lines up against the original, nothing is failing, and the rebuild still runs at the wrong speed or draws the wrong thing.

**A checker driven by declarations measures the declarations, not the binary.** It answers "does each routine I was told about match?", and a routine nobody declared is not a failure in that scheme -- it is not a row at all. Absence has no place to show up.

The measurement that does see it is the complementary one: walk **every byte** of every user segment of the original and report the spans that cannot be aligned against your build. Same tolerant differ, opposite question -- coverage rather than a sample. Two spans of the same length mean two very different things, so it reports position and size and stops there.

## Why it works

Alignment is a property of the whole image, and it is total: every byte either lines up somewhere in the rebuild or does not. A declaration list is a sample chosen by whoever wrote the declarations, and it therefore inherits their blind spots. The routine that gets re-expressed in Pascal instead of transcribed is exactly the routine nobody thought to declare, because the person who rewrote it did not think it was assembler.

## Blind spot

**An unaligned span is not proof of lost assembler.** Compiled code with a different statement shape, different locals or a different loop counter also fails to align, and may be behaviourally right. The span says *where to look*, never *what you will find* -- each one still has to be disassembled and judged. Two spans in one part of the same size were, on the run below, one lost hand-written routine and one deliberate deviation.

It also cannot run before there is something to compare with: it needs a build. And it says nothing about a segment it has no bounds for -- the segment table is hand-written from the unit headers, so a part whose bounds are missing silently scores nothing.

## Cost

The differ you already have for the per-routine check, plus a walk over each user segment and a minimum span length to keep data between routines out of the report. No disassembler until you read a span.

## Example

Part 001 of `PSYCHO NEUROSIS` on 23 Aug 2026: the per-routine check reported 73 routines locked, 0 failing. Coverage alignment on the same build was **63.3%**, and the largest span, `1107:007b..039a` at 799 bytes, was mostly one routine -- a hand-written clipped transparent blit re-expressed as a Pascal double loop over `Mem[]`, called 144 times a frame over 49 pixels each. The same routine had been transcribed verbatim and locked at 170 bytes in another unit for weeks; nothing in the per-routine check could say so, because in this unit it was not declared. Transcribing it moved alignment to **66.6%**. [1] [2]

The second-largest remainder of that span, `1107:0287..039a`, was the opposite finding: compiled code whose shape genuinely differs, recorded as a deviation rather than transcribed. [2]

# Citations

[1] `tools/shapediff.py`, in the psycho repository -- the coverage differ, and its docstring's account of the two classes a span belongs to.

[2] `docs/23-deviations.md`, the depth-sort entry, and commit `c15bd92` in the psycho repository.
