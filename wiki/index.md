---
okf_version: "0.1"
---

# The Pascal RE wiki

A field manual for reverse engineering 16-bit DOS binaries built with Borland Pascal. It grows every time somebody reads a binary. See `README.md` for how to check it, and `CONTEXT.md` for the vocabulary.

## Observations

* [A zero byte where the original has something else](observations/zero-byte-difference/observation.md) - the rule inverts by artefact, and using the wrong one is destructive in both directions
* [The same bytes answer to two different addresses](observations/two-names-one-address/observation.md) - segment:offset is a many-to-one name; convert to linear before believing duplication or a gap
