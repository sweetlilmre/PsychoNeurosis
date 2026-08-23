# Log

## 2026-08-23

* **Create**: [Every declared routine matches, and the rebuild still behaves differently](/observations/verifier-blind-to-absence/observation.md). Read out of part 001 of the demo: the per-routine byte check reported 73 routines locked and 0 failing while a hand-written blitter sat re-expressed as Pascal, because a checker driven by declarations has nowhere to report a routine nobody declared. Coverage alignment found it as a 799-byte span.
* **Create**: [The same routine sits mid-unit in one binary and at a segment head in another](/observations/one-routine-two-units/observation.md). The same routine in two parts, and where it sits in the segment says whether the original shared a unit or shared source text. Carries the two Turbo Pascal mechanics for sharing it: a `{$I}` inside an `asm` block is refused, and an include quoting a directive needs `(* *)` delimiters.
* **Withdrawn**: that a shared include would drop the routine out of the byte check, which is why an earlier commit that day kept two copies. The marker had always allowed a name of its own. Recorded on the observation itself, at the point of use.
* **Correct**: `kbprofile.py` reported every single-page observation as having stale generated content, for ever -- there is no discriminator table to generate for a hub with no artefact answers, and `--write` printed "regenerated" while writing nothing. The check exited 1 on the committed bundle before either page above existed. A hub with no children is no longer reported.

## 2026-08-19

* **Create**: the bundle, as the prototype for [Write one technique page as the pattern](https://github.com/sweetlilmre/PsychoNeurosis/issues/10).
* **Create**: [A zero byte where the original has something else](/observations/zero-byte-difference/observation.md), with three artefact answers -- `.TPU`, `.OBJ` from TASM, and a linked image.
* **Note**: the third answer, [a linked image](/observations/zero-byte-difference/linked-image.md), is stated outright in **neither** source technique. The discriminator table had a hole in it and the shape is what found the case. Its `Example` is `none yet` for exactly that reason, and the field says so rather than sitting blank.
* **Withdrawn, carried in from the source material**: the zero heuristic was applied to a TASM `.OBJ` first and was wrong in both directions at once -- 65 divergent regions reported on a module that was actually correct, and 27 phantom differences for 36 relocation bytes. Recorded on [the .OBJ answer](/observations/zero-byte-difference/obj-tasm.md) rather than in an appendix, because a lesson kept away from the point of use does not prevent its own recurrence.
* **Correct**: the hub's generated column held each artefact's *answer*, which put rules back into the hub. An observation must match what was observed and route to the artefact **without answering**. The column is now `identify` -- how to tell you are holding this artefact -- and the profile check reads the keys that feed the table, because it had always skipped the generated block and that was where the rules were.
