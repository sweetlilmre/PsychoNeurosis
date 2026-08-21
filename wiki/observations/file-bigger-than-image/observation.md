---
type: Observation
title: The file is bigger than its load image
description: The MZ header accounts for fewer bytes than the file holds -- something is appended, and the one measured cause so far is Borland debug info.
tags: [mz, debug-info, container, substrate]
timestamp: 2026-08-21T00:00:00Z
---

# The file is bigger than its load image

An MZ executable's header states its own load-image size (`(e_cp - 1) * 512 + e_cblp`), and the file on disk is bigger than that. The loader will never bring the tail into memory, so whatever it is, the program cannot be *running* it -- it is data for some other reader.

**Check the arithmetic first**: the difference is exact, and what sits at the boundary identifies the tail. The one cause measured in this project so far:

**Borland debug info** -- magic word `0x52FB` at exactly the load-image boundary, followed by a version word (`0x0208` for TP7). `toolkit/substrate/tddump.py` decodes it completely: module names, source-file names with save timestamps, every public symbol with its address, scopes, per-line addresses, and the type table. It is the strongest identification evidence there is -- `NEUROSIS.009`'s 3,044-byte tail yielded the source filename, its save time to the second, and the address of every variable. See the research record for the format, the two published readers it corrects, and the field layouts. [1]

Other causes exist -- appended data payloads a program reads from its own file, packer signatures -- but none has been measured in this project yet, so this page does not describe them. Add the section when one is read, not before.

## Blind spot

**A file that is NOT bigger than its image proves nothing.** Debug info can be stripped, payloads can live in separate files, and `PSYCHO.EXE`'s image accounts for every byte while two of its siblings carry tails. Absence of a tail is not absence of evidence elsewhere in the file.

## Cost

An MZ header read and a subtraction -- stdlib Python, no disassembler, no toolchain. If the magic matches, `tddump.py` does the rest.

## Example

`NEUROSIS.009`: 10,356 bytes on disk = 7,312 load image + 3,044 debug info, exactly. `NEUROSIS.000`: 17,426 = load image + tail the same way. Both decoded with zero residue bytes. [1]

# Citations

[1] `docs/research/borland-debug-info.md`, in the psycho repository -- the format read against primary sources, the empirical decode of both binaries, and the two published readers that were each measurably wrong once.
