---
type: Observation
title: The same routine sits mid-unit in one binary and at a segment head in another
description: Identical code in two parts was shared as SOURCE, not as a unit, when it sits surrounded by one unit's own routines -- and rebuilding it as a shared unit turns the callers' near calls into far ones.
tags: [pascal, segments, source-shape, include, rebuild, hand-assembler]
timestamp: 2026-08-23T00:00:00Z
---

# The same routine sits mid-unit in one binary and at a segment head in another

Two parts of the same program contain the same routine, instruction for instruction, at different addresses. You are about to rebuild both, and you have to decide what the original source looked like: one unit that both parts imported, or one piece of text that both parts included.

**Where the routine sits decides it.** Borland Pascal lays a unit's routines out contiguously in one segment, in source order. So:

* **Surrounded by another unit's own routines** -- the ones before and after it belong unmistakably to that part's effect, and it is nowhere near the head of the segment -- and it was not imported from anywhere. It was compiled *into* that unit, which is what happens to an included procedure and cannot happen to an imported one.
* **At the head of a segment, with only its own family following**, and a shared unit is consistent with what you see.

The second reading is much weaker than the first: a unit holding one routine and an included routine that happens to be declared first look identical. The mid-unit case, though, is decisive.

## Why it works

A unit is a compilation and a segment; an include is text. `{$I}` is resolved before the compiler decides anything about layout, so an included procedure is indistinguishable in the output from one typed into the unit -- and it is duplicated into every unit that includes it. An imported routine cannot be duplicated: there is one copy, in the exporting unit's segment, and everyone else reaches it with a far call.

That last part is why the choice is not cosmetic. Hoisting a duplicated routine into a shared unit to tidy the rebuild **changes the emitted code at every call site** -- near calls become far ones -- and moves the routine out of the segment the disassembly reads it from. The tidier source produces the wrong bytes.

## Doing it, in Turbo Pascal 7

Two mechanics, both measured on 23 Aug 2026 and neither documented anywhere obvious:

* **The include must carry the whole procedure, header and all.** A `{$I}` *inside* an `asm` block is refused -- `Error 118: Include files are not allowed here`. At declaration level it compiles.
* **A `}` closes a `{ }` comment, so an include whose own header comment quotes a directive needs `(* *)` delimiters.** A block explaining `{$I}` and `{$G+}` in `{ }` ends at the first quoted directive and everything after it is parsed as code, which arrives as `Error 37: END expected` pointing at prose.

Offsets in the shared text's comments have to be **relative to the routine's own start**, since each including part sits at a different address, and each including unit keeps whatever names the shared assembler references -- the addresses, and anything held in that part's own data.

## Blind spot

Position is evidence, not proof. Smart linking drops unreferenced routines, so what surrounds what in the image is not exactly what surrounded what in the source. A one-routine unit is indistinguishable from an include at a segment head. And identical instructions do not always mean shareable text: three copies of one nine-instruction routine in this corpus have three different *declarations* -- `far` in a shared unit, an untyped `var` parameter, and a typed pointer -- so there is no single text to share, only the same body reached three ways.

## Cost

Two addresses and the routine boundaries either side of them, which you have already if you were transcribing the routine.

## Example

`PSYCHO NEUROSIS`'s clipped transparent sprite blit, 170 bytes, appears in part 001 at `1107:0199` and in part 006 at `100f:0000` -- every address differing by exactly `$199`. Part 001's copy sits between that scene's `Banner_Load` (`$0025`) and `DrawBlobs` (`$0245`), inside the scene unit's own code, so the original shared the source. It is now one text included by both units, and both copies still match at 170 bytes. [1] [2]

An earlier session kept the two copies duplicated instead, on the stated grounds that a shared include would drop the routine out of the byte check. That was a **withdrawn conclusion**: the byte-check marker had always allowed a name of its own, precisely so the declaration could live elsewhere. The tool had not been read before it was worked around. [2]

# Citations

[1] `src/asm/BLITCLIP.INC` and `tools/asmshare.py`, in the psycho repository -- the shared text, and the check that no verbatim assembler is duplicated between units instead of shared.

[2] Commits `d6e0882` and `ed0314c` in the psycho repository: the reasoning, and its correction.
