---
okf_version: "0.1"
---

# Pascal RE knowledge base

A field manual for reverse engineering 16-bit DOS binaries built with Borland Pascal. One observation today; it grows every time somebody reads a binary. See `README.md` for how to check it, and `CONTEXT.md` for the vocabulary.

## Observations

* [A zero byte where the original has something else](observations/zero-byte-difference/observation.md) - the rule inverts by artefact, and using the wrong one is destructive in both directions
