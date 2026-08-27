# docs/research — findings behind the RE knowledge base

These are the resolved **research tickets** of the wayfinder map [The Pascal RE knowledge base](https://github.com/sweetlilmre/PsychoNeurosis/issues/1). They are **inputs**, not the knowledge base itself: raw inventories and audits, produced deliberately without designing anything, so the design decisions could be made against facts rather than impressions.

Each file is also posted as a resolution comment on its ticket. These copies exist because a 275 KB inventory split across nine GitHub comments is painful to reassemble, and because the map is the canonical *route* while the facts belong with the code.

| file | ticket | what it establishes |
|---|---|---|
| [02-script-classification.md](02-script-classification.md) | [#2](https://github.com/sweetlilmre/PsychoNeurosis/issues/2) | All 55 scripts tiered as substrate / Pascal / project, with what each measures, whether it needs a disassembler, and library-vs-driver. Seven genuine overlaps between the two repos |
| [03-technique-inventory.md](03-technique-inventory.md) | [#3](https://github.com/sweetlilmre/PsychoNeurosis/issues/3) | 209 techniques (76 substrate, 133 Pascal), 88 with a worked example, 91 needing no disassembler, and 79 withdrawn conclusions in 9 repeating classes |
| [04-ledger-audit.md](04-ledger-audit.md) | [#4](https://github.com/sweetlilmre/PsychoNeurosis/issues/4) | What `tools/ledger.py` actually records (18 of 317 routines, 3 rows being regex artifacts), why it cannot carry a graded status, and that `asmverify.py` is the only real per-routine instrument |
| [borland-debug-info.md](borland-debug-info.md) | [#27](https://github.com/sweetlilmre/PsychoNeurosis/issues/27) | The TP7 appended debug format (magic `0x52FB`, version 2.08) decoded end to end against `NEUROSIS.000`/`.009` with zero residue: every table, every symbol name and address, the source names NEUR0.PAS and NEUR9.PAS with their 1994 save timestamps, and where both published open-source readers get the layout wrong. Decoder: `kit/tools/substrate/tddump.py` |

## Reading them with the right expectations

**They are not authoritative on design.** Every structural conclusion drawn from them lives on the map or in a ticket, because that is where it can be argued with. Three findings from the inventory reshaped the map and are recorded there: the blind spot is a property of an *ordered set* of instruments rather than a per-page footnote; technique identity keys to the **artefact measured** rather than the operation; and a lesson recorded only in a retrospective demonstrably fails to prevent its own recurrence.

**Coverage is thorough, not proven exhaustive.** Two of the three original mining passes stalled on the largest inputs — `CONTINUATION.md` alone is 292 KB — and were re-run as six smaller slices. Treat the 209 as a broad sweep.

**Location is provisional.** Where the knowledge base ultimately lives is still an open decision ([#6](https://github.com/sweetlilmre/PsychoNeurosis/issues/6)), and these may move with it.
