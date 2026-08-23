---
okf_version: "0.1"
---

# The Pascal RE wiki

A field manual for reverse engineering 16-bit DOS binaries built with Borland Pascal. It grows every time somebody reads a binary. See `README.md` for how to check it, and `CONTEXT.md` for the vocabulary.

## Observations

* [A zero byte where the original has something else](observations/zero-byte-difference/observation.md) - the rule inverts by artefact, and using the wrong one is destructive in both directions
* [The same bytes answer to two different addresses](observations/two-names-one-address/observation.md) - segment:offset is a many-to-one name; convert to linear before believing duplication or a gap
* [The rebuild nearly matches, and the last bytes name their causes](observations/near-match-diff/observation.md) - each residual diff pattern fingerprints one source construct or compiler switch; read it, do not tune
* [The file is bigger than its load image](observations/file-bigger-than-image/observation.md) - the tail past the MZ image is data for another reader; the measured cause is Borland debug info, decoded whole by tddump.py
* [The line table advances one line per instruction](observations/line-table-reveals-asm/observation.md) - a dense stretch in the debug info's line table marks an inline asm block, no disassembly needed
* [Readable text sits between the routines](observations/text-between-routines/observation.md) - the gaps hold length-prefixed string literals; walk them and read the program's behaviour before its code
* [Every declared routine matches, and the rebuild still behaves differently](observations/verifier-blind-to-absence/observation.md) - a byte check driven by declarations cannot see a routine nobody declared; align every byte instead
* [The same routine sits mid-unit in one binary and at a segment head in another](observations/one-routine-two-units/observation.md) - where it sits says whether the original shared a unit or shared source text, and a shared unit changes the call
