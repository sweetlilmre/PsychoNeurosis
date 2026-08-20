# The toolkit

Reusable programs with no project facts in them. Three folders, decided in [Draw the tooling package boundary](https://github.com/sweetlilmre/PsychoNeurosis/issues/9).

| folder | what it holds | tier |
|---|---|---|
| `substrate/` | Reading DOS and 16-bit binaries: MZ headers, LZEXE, segments, relocation tables. Should work against a C or assembler target too. | substrate |
| `pascal/` | Facts true only of Borland Pascal: `.TPU` structure, DGROUP layout, RTL byte patterns. | pascal |
| `wikitools/` | Looking after the wiki itself: OKF conformance, our stricter profile, and the generators. | neither |

**`substrate/` and `pascal/` are empty.** Nothing has been moved into them yet. The 55 existing scripts live in `tools/` and in the VangeliSTracker repo, and consolidating them is [Consolidate and prune the tools](https://github.com/sweetlilmre/PsychoNeurosis/issues/17). The map's standing rule is **copy and adjust, never refactor the originals** -- so `tools/*` keeps working, untouched, and anything generic gets *copied* here and adapted.

## Two rules that shaped this

**One compare tool, not four.** Four scripts across the two repos compare bytes and differ *only* in which differences they accept -- a zero for a `.TPU`'s pending fixup, whatever an `.OBJ` records as a relocation, an isolated one- or two-byte run, an address inside a known DGROUP window. So the **allowed-difference rule is passed in, never built in.** Baking it in hides how strict a measurement was; passing it in makes that readable at the call site.

**"Needs no disassembler" is a note on a tool, not a folder.** Eight tools qualify and they are the cheap, portable half -- but they span both tiers, so filing them together by what they *don't* need would split things that belong side by side.

## Running it

    uv venv .venv
    uv pip install --python .venv/Scripts/python.exe -e toolkit

Then, from the repo root:

    .venv/Scripts/python.exe toolkit/wikitools/okfcheck.py wiki
    .venv/Scripts/python.exe toolkit/wikitools/kbprofile.py wiki
    .venv/Scripts/python.exe toolkit/wikitools/kbprofile.py wiki --write

`okfcheck.py` checks only what the OKF spec requires. `kbprofile.py` checks our house rules and regenerates the parts of the wiki that are generated. Keeping them apart is deliberate: if `okfcheck.py` ever rejects a document only our template dislikes, we have quietly redefined a portable format as ours.

**A note about `okfcheck.py`, so nobody "fixes" it.** It contains no project facts at all. It implements the published OKF spec and nothing else, so anyone using OKF could run it unchanged. Do not wire it into this repo's layout.
