# Psycho Neurosis and the Pascal RE knowledge base

The shared vocabulary for reverse engineering 16-bit DOS binaries built with Borland Pascal. It covers all three jobs in this tree, because they measure the same things and argue about the same words.

**Wiki-specific terms live in [`wiki/CONTEXT.md`](wiki/CONTEXT.md)** -- how a page is shaped, how the catalogue is organised, and the fidelity ladder. They are kept there deliberately, so that when the wiki lifts out into its own repository its vocabulary goes with it instead of being left behind here.

Note one deliberate absence across both files: there is no entry for *axis*. The catalogue is sorted by what a reader already knows, which is the **lookup key**, and "axis" was the word we used while that was still unclear.

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

### The toolkit

**Toolkit**:
The reusable programs, with no project facts in them. Three folders: `substrate`, `pascal`, `wikitools`.
_Avoid_: tools, library, framework, package

**Core**:
The part of a program with no project facts in it. The reusable part.
_Avoid_: engine, kernel, generic layer

**Driver**:
The part of a program that holds one project's own facts: file names, addresses, unit lists.
_Avoid_: script, wrapper, harness (a harness is a different thing)

**Compare tool**:
A program that compares our bytes against the original's bytes.
_Avoid_: comparator, differ, verifier

**Allowed-difference rule**:
The rule that says which differences a compare tool accepts. It is passed in, never built in, because the rule inverts by artefact.
_Avoid_: excuse rule, mask, tolerance, heuristic

**Scratch folder**:
A temporary folder that a build erases and then uses. One per project, named in config, because three build scripts once shared one and could not run at the same time.
_Avoid_: build dir, temp, workspace

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

