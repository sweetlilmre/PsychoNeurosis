# Psycho Neurosis — orientation

Asphyxia's first megademo, 1994. Borland Pascal 7 plus hand-written assembler, real-mode DOS, VGA. The user is an original author. **This file is a router, not a manual** — read the entry point for whichever job you are on, and nothing else.

## Three separate jobs live here. Do not confuse them.

| job | entry point | state |
|---|---|---|
| **Reconstruct the demo** — recover Pascal source for parts 001–007 that behaves like the 1994 binaries | `docs/24-continuation.md`, then `docs/23-deviations.md` | in progress; **behavioural** fidelity, not byte-exact |
| **Build the RE knowledge base** — a Pascal/DOS field manual and a reusable toolkit, extracted from what both efforts learnt | [The Pascal RE knowledge base](https://github.com/sweetlilmre/PsychoNeurosis/issues/1) | charted 19 Aug 2026; work it with `/wayfinder <that url>` |
| **DemoVT byte-exact rebuild** | `D:\source\VangeliSTracker\v1.31b\docs\CONTINUATION.md` | **a different repo.** Complete: byte-identical load image, blocked only on LZEXE |

`docs/README.md` indexes all 28 numbered documents by topic. `NEUROSIS.008` is **not** Asphyxia code — it is third-party, and its reconstruction moved out to `D:\source\VangeliSTracker`.

## Working the knowledge base

It is a wayfinder map on GitHub Issues: tickets are sub-issues, blocking is native, and the frontier is the open, unblocked, unassigned ones. **Its governing rule is copy and adjust, never refactor the originals** — `tools/*`, `docs/*` and the VangeliSTracker scripts stay exactly as they are; anything generic gets *copied* into the knowledge base and adapted there. Refactoring the originals to consume it is a later, separate effort, and executing the demo cleanup is out of scope for that map.

## Standing rules

- **Never re-express hand-written assembler as Pascal.** Transcribe it verbatim, comment every line, and put equivalent Pascal above it as a comment.
- **A measurement beats an argument.** Every confident claim about the compiler in this project's history has a roughly one-in-six survival rate; put the claimed difference in a probe and let a build settle it.
- **Distrust the verifier before the transcription.** The verify tooling has been wrong more often than the code it judged. Check a surprising measurement a second way.
- Prose in markdown is never hard-wrapped. Commits carry `Co-authored-by: Claude <noreply@anthropic.com>`.
- **Encoding and line endings split by who reads the file, and every script must say which it means.** Never rely on the locale: Windows' is cp1252, so a bare `open`/`read_text`/`write_text`, or a `subprocess` with `text=True`, silently decodes UTF-8 as cp1252. That has already mojibaked two documents and produced two false comparisons.

| the file is read by | encoding | line ending |
|---|---|---|
| humans and modern tools — `.md` | `utf-8` | LF, so pass `newline='\n'`; Python defaults to CRLF on Windows |
| a 1990s DOS tool — `.PAS` `.ASM` `.INC` `.MAP` `.BAT` `.CFG` | **`ascii`**, and strictly on write | CRLF |
| our own scripts' stdout via `subprocess` | `utf-8` | — |

  `ascii` on a DOS file is a **guard**, not a codec preference: it raises rather than quietly encoding an em dash as two bytes into a file Turbo Pascal will read. `paslint.py` checks for non-ASCII bytes and `build.py` refuses to compile when lint fails, so **write `--` not `—`, and `"` not `“`, in any `.PAS` comment.** `.gitattributes` in both repos enforces the line-ending half.
- Do not fetch period third-party binaries (LZEXE and friends). That is the user's call.

## Environment traps that have each cost real time

- Git Bash rewrites an argument starting with a slash into a Windows path, so `--sw=/GS` silently compiles **nothing** and reports `0 unit(s) compiled`. Prefix with `MSYS_NO_PATHCONV=1`, or use PowerShell. The same happens to `gh api /repos/...` — call `gh` from Python's `subprocess`, or use the `gh issue` / `gh label` subcommands.
- A `\\` inside a quoted heredoc reaches Python as a single backslash. Build escapes with `chr(92)` instead of writing them literally.
- **Something in this environment has twice multiplied every line break in a markdown file** — `VangeliSTracker`'s `00-map.md` (91% blank lines) and this repo's `docs/README.md` (58%). The cause was never found. `tools/repairdoc.py` diagnoses and repairs it, and proves content preservation before writing.
