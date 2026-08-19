# Psycho Neurosis and the Pascal RE knowledge base

The shared vocabulary for reverse engineering 16-bit DOS binaries built with Borland Pascal. It covers all three jobs in this tree, because they measure the same things and argue about the same words.

**This file is provisional.** Its final home is decided by [Where the knowledge base lives](https://github.com/sweetlilmre/PsychoNeurosis/issues/6). Note one deliberate absence: there is no entry for *axis*. The catalogue is sorted by what a reader already knows, which is the **lookup key**, and "axis" was the word we used while that was still unclear.

## Language

### The things we measure

**Artefact**:
A thing you can measure. It is a whole file, or one named part of a file. Examples: `PSYCHO.EXE`, one segment, one routine, one `.PAS` file.
_Avoid_: target, object, item, subject

**Instrument**:
A tool or a method that measures how well an artefact agrees with the original. A person who watches the screen is an instrument.
_Avoid_: tool, check, test, measure (as a noun)

**Blind spot**:
The thing an instrument cannot see. Every instrument has one. Each instrument is blind to something the next one catches.
_Avoid_: limitation, gap, weakness

**Part**:
One of the nine files the 1994 demo shipped as, named `NEUROSIS.000` to `NEUROSIS.008`. A part runs on its own.
_Avoid_: module, stage, chapter

**Scene**:
One visual effect inside a part. A part driver runs its scenes in order.
_Avoid_: effect, section, sequence

### The knowledge base

**Technique**:
One method. It answers one question about a binary.
_Avoid_: trick, approach, procedure, recipe

**Catalogue**:
The set of all technique pages. It holds 209 techniques today.
_Avoid_: manual, library, index

**Tier**:
Which layer of knowledge a piece of advice belongs to. There are exactly two, below. A tier is a field on one section of a page, not a way of grouping pages: one page can hold a Pascal-tier section and a substrate-tier section.
_Avoid_: level, layer, category

**Substrate tier**:
Knowledge about DOS and 16-bit binaries. It says nothing about Pascal, so it should also work on a C or assembler program. Examples: MZ headers, LZEXE packing, segment addresses.
_Avoid_: DOS layer, lower tier, base tier

**Pascal tier**:
Knowledge that is true only for Borland Pascal. Examples: `.TPU` files, DGROUP layout, smart linking.
_Avoid_: compiler layer, upper tier

**Withdrawn conclusion**:
A claim this project made, believed, and then disproved by measurement. These belong in the catalogue next to the technique that produced them. They are not an appendix.
_Avoid_: mistake, error, false start, retraction

### How the catalogue is organised

**Lookup key**:
The thing a reader knows before they open a page. It decides how the catalogue is sorted.
_Avoid_: axis, organising principle, taxonomy

**Symptom page**:
A page you find by what you observed. It opens with the observation, then has one section for each artefact you might be holding. Example: "a zero byte where the original has something else".
_Avoid_: lookup page, diagnostic page

**Procedure page**:
A page you find by the job you decided to do. Example: "unpack the container".
_Avoid_: how-to, task page, method page

**Section**:
One artefact's answer inside a page. It carries its own rule, its own caveats, its own withdrawn conclusions, and its own tier.
_Avoid_: branch, case, variant

**Cross-index**:
A list that points at pages already written, sorted a second way. It adds no pages. There are three: the nine classes of withdrawn conclusion, the twelve activities, and the ladder nodes.
_Avoid_: view, tag, secondary axis

### The fidelity ladder

**Ladder**:
The ordered set of gates and rungs. It runs from "we know nothing about this artefact" up to "its bytes are identical to the original".
_Avoid_: scale, spectrum, hierarchy, maturity model

**Gate**:
A node near the bottom of the ladder that you must pass through. A gate is never a goal. You cannot read a file you have not unpacked. There are three: container opened, identified, charted.
_Avoid_: stage, prerequisite, step

**Rung**:
A node on the ladder that you can choose as a goal. There are six, from "it compiles" up to "the artefact is byte-identical".
_Avoid_: level, grade, tier (a tier is a different thing)

**Strand**:
One of the two paths up the ladder. The behavioural strand watches the demo run. The structural strand compares bytes. Neither one proves the other.
_Avoid_: branch, track, axis

**Target rung**:
The rung an artefact is meant to reach. A person declares it.
_Avoid_: goal, aim, requirement

**Achieved rung**:
The rung an artefact has reached. A tool computes it. A person may not assert it, with one exception: watching the demo run.
_Avoid_: status, actual, current level

**Transcription stance**:
What the Pascal source is allowed to look like. There are three, below. The stance is independent of the rung.
_Avoid_: style, fidelity mode, approach

**Verbatim**:
A stance. Hand-written assembler is copied instruction by instruction, with a comment on every line.
_Avoid_: literal, exact, faithful

**Idiomatic**:
A stance. The binary is plainly compiler output, so normal Pascal is the honest transcription. Inventing assembler here would be the deviation.
_Avoid_: natural, clean, native

**Equivalent**:
A stance. The code is knowingly different but has the same visible effect. It can never be byte-identical.
_Avoid_: approximate, rewritten, functional

**Provenance**:
How a piece of source came to exist. Did a person read the bytes, or write something plausible? It never tells you whether the code is correct.
_Avoid_: evidence class, confidence, quality

**Deviation**:
A difference from the original that we chose on purpose and wrote down. Anything not written down is a defect, not a choice.
_Avoid_: divergence, variance, exception

### Verification

**Harness**:
A small program that runs one scene or one whole part on its own, so a person can watch it. A harness is itself a deviation from the demo.
_Avoid_: test, driver, runner

**Marker**:
A comment in a `.PAS` file that a tool reads. `{ @asm 003 11f3:0105 }` names the address in the original that a routine's bytes must match.
_Avoid_: annotation, tag, directive

**Fragment**:
Hand-written assembler inside a compiled Pascal routine. It has no routine boundary, so its marker states a byte count instead.
_Avoid_: inline block, snippet, chunk

**Ratchet**:
A measure that cannot go backwards without failing the build. `asmverify.py` locks routine lengths, so a change that shortens a match is a regression.
_Avoid_: gate (a gate is a different thing), guard, lock
