---
type: Artefact Answer
title: A zero byte in a linked image
description: After linking there are no placeholders left, so a zero is an ordinary difference and excusing it hides a fault.
order: 3
holding: a linked image
summary: Nothing is pending. A zero is a real difference.
artefact: linked image
tier: substrate
ladder_node: R7
tags: [comparison, fixups, relocation, linking]
timestamp: 2026-08-19T00:00:00Z
---

# A zero byte in a linked image

Part of [A zero byte where the original has something else](./observation.md).

## What to do

**Nothing is pending, so forgive nothing.** Treat the zero as an ordinary difference and go and find out why it is there.

If you have arrived here carrying a habit from the `.TPU` case, drop it. Excusing zeros in a linked image does not weaken the comparison slightly -- it removes the comparison from exactly the bytes most likely to be wrong, because a reference that failed to resolve is a plausible cause of a zero.

## Why it works

Linking is the step that fills placeholders in. Once it has run, every reference has its final value and there is nothing left for a rule to excuse. A zero in a linked image is either a value that is genuinely zero, or a fault.

## Blind spot

**This answer is trivially correct and therefore easy to skip past, which is its own risk.** Two real ones sit behind it:

- **A boundary inside a run of zeros is invisible to a byte comparison.** The initialised DGROUP image once read 100% identical while `SelfName` was six bytes too long, because the error fell inside a stretch of zeros where no byte differed. So "no differing bytes" is not the same as "correct", and a length check is a separate instrument. [1]
- **Plain `var`s are never written to the executable at all**, so they cannot be compared here by any rule. Their absence is not agreement. [1]

## Cost

The linked executable and a byte comparator. But note the prerequisite, inherited from ladder node R7 rather than restated here: **the segments must already be aligned and the right length**, or nothing lines up and every byte reads as different. If this comparison looks impossible, something upstream of it is still wrong.

## Example

`none yet` -- this artefact answer was written because the shape of the observation demanded a third case, not because a specific incident produced it. That is worth being explicit about: neither source technique states this case outright, and the page exists because the discriminator table had a hole in it.

## Withdrawn

None recorded.

# Citations

[1] `CONTINUATION.md`, the seven-measures table, in the VangeliSTracker repository. **Quoted inline** because that document is in a different repository: the `dgroup.py` row compares "the INITIALISED DGROUP image, byte for byte" and cannot see "plain `var`s, which are never written to the EXE. **And a boundary inside a run of zeros** -- it read 100% identical while `SelfName` was six bytes too long."
