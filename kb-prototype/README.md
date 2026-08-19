---
type: Orientation
title: Prototype -- one technique page as the pattern
description: What this bundle is, why it exists, and what is deliberately missing from it.
tags: [prototype, orientation]
timestamp: 2026-08-19T00:00:00Z
---

# Prototype: one technique page as the pattern

This directory is the artefact for [Write one technique page as the pattern](https://github.com/sweetlilmre/PsychoNeurosis/issues/10). It is a **prototype to react to**, not the knowledge base.

**Its location is provisional.** [Where the knowledge base lives](https://github.com/sweetlilmre/PsychoNeurosis/issues/6) decides where a real bundle sits, and this directory name is deliberately ugly so nobody mistakes it for that decision.

## What it is

An [OKF v0.1](https://okf.md/spec/) bundle holding exactly one observation, chosen because it exercises every decision made in tickets [#7](https://github.com/sweetlilmre/PsychoNeurosis/issues/7), [#14](https://github.com/sweetlilmre/PsychoNeurosis/issues/14) and [#8](https://github.com/sweetlilmre/PsychoNeurosis/issues/8) at once:

    observations/zero-byte-difference/
        observation.md      the hub -- a DISCRIMINATOR, never a rule
        tpu.md              artefact answer, Pascal tier
        obj-tasm.md         artefact answer, substrate tier
        linked-image.md     artefact answer, substrate tier
        index.md            generated

Three artefacts whose rules **invert**. Two tiers inside one hub. A caveat and a withdrawn conclusion belonging to different children. And a third child, `linked-image.md`, that **neither source entry states outright** -- the shape found a missing case.

## Two validators, deliberately separate

    python kb-prototype/tools/okfcheck.py kb-prototype
    python kb-prototype/tools/kbprofile.py kb-prototype

`okfcheck.py` asks only what OKF asks: does every non-reserved document have parseable frontmatter with a non-empty `type`? The spec says a linter for that is "about 10 lines of bash", and it is right. It must **not** reject a document for missing optional fields, unknown `type` values, unknown keys, or broken links.

`kbprofile.py` is ours and is stricter. It requires the fields our template settled on, and it refuses a hub that states an unqualified rule. It also **generates** the hub's discriminator table and the `index.md` files from the children's frontmatter, so those cannot drift from the answers they summarise.

    python kb-prototype/tools/kbprofile.py kb-prototype --write

## Known gaps, recorded rather than hidden

- **It needs a virtual environment.** Both tools import `pyyaml` from PyPI, installed with `uv` into `.venv` at the repo root, because #8 argued for a real YAML parser rather than a regex -- this project has been burned by regex-over-text before. Run them with `.venv/Scripts/python.exe`, not the system Python. **This is the knowledge base's first third-party dependency**, and whether the tooling package may carry one at all is [Draw the tooling package boundary](https://github.com/sweetlilmre/PsychoNeurosis/issues/9)'s decision, not this prototype's.
- **`tools/encaudit.py` does not scan this directory.** Its `DEFAULT_DIRS` is `('tools', 'tools/dosbox')` and the map forbids adjusting the originals, so run it explicitly: `python tools/encaudit.py kb-prototype/tools`.
- **A README is a concept document.** OKF reserves only `index.md` and `log.md`, so `okfcheck.py` correctly refused this very file until it grew frontmatter and a `type`. The spec has no notion of a README, so anything else in a bundle must declare a type or be reserved.
- **The hub was still answering, via the generator.** The first version generated a `summary` column holding each artefact's *rule*, which put rules back into the hub -- the exact thing the design forbids. Worse, `check_hub_states_no_rule` deliberately strips the generated block before looking, so **the one place rules ended up was the one place exempt from the check.** Fixed twice over: the column is now `identify` ("how to tell you are holding this"), which serves discrimination and gives nothing away, and the check now also reads the `identify` and `description` keys that feed the table. Verified by injecting a rule and watching it fail.
- **The hub's no-rule check is a text heuristic and it produced a false positive on its first run** -- it flagged the sentence *A rule phrased as "forgive zeros" silently assumes the first case*, which is the hub doing its job. Stripping quoted spans fixed that case on a principled basis: a rule verb inside quotation marks is a rule being *discussed*, not stated. But the check remains a heuristic over prose, which is the exact disease `encaudit.py` was rewritten to cure. **The most important guardrail in the design is the one that resists automation**, and that belongs to [Decide how a blind spot becomes a mechanism](https://github.com/sweetlilmre/PsychoNeurosis/issues/15).
- **`ladder_node` earned its keep as evidence, not as an index.** All three answers are R7, so the ladder cross-index would file them together and tell a reader nothing -- which is what #8 predicted when it put the ladder index last.
- **OKF v0.1 appears to contradict itself on `index.md` frontmatter**: section 6 says index files carry none, section 11 says the root `index.md` declares `okf_version` in frontmatter. This bundle follows section 11 for the root and section 6 everywhere else.
