# How to read Borland appended debug info

Resolves [#27](https://github.com/sweetlilmre/PsychoNeurosis/issues/27). Everything below is tagged **MEASURED** (this session ran it against `bin/NEUROSIS.000` and `bin/NEUROSIS.009`), **DOCUMENTED** (a primary source says it, cited), or **INFERRED**. The decoder that produced every measured value is `toolkit/substrate/tddump.py`, stdlib-only Python, and both appended blocks now decode **end to end with zero unexplained bytes**.

## 1. What the format is and where it lives

Turbo Pascal 7 (and Borland C++) append a Turbo Debugger symbol table after the MZ load image when a program is built with debug info in the executable. There is **no trailer**: the block is found from the front, at the byte the MZ header declares as the end of the load image (`(e_cp - 1) * 512 + e_cblp`, with `e_cblp = 0` meaning a full last page), and it begins with the magic word `0x52FB` (bytes `FB 52`). The name pool of NUL-terminated ASCII strings sits at the very end of the file, `names_pool_size` bytes back from EOF. DOCUMENTED in Ralf Brown's Interrupt List, table 01624 ("Format of Borland debugging information header (following load image)", [mirror](https://github.com/cirosantilli/ralf-brown-interrupt-list/blob/master/inter61b/INTERRUP.G)), which defers to **Borland's Open Architecture Handbook** — the owning spec, long out of print; the fullest surviving copy of its debug-info chapter is quoted wholesale in the comments of Reko's [`SymbolLoader.cs`](https://github.com/uxmal/reko/blob/master/src/ImageLoaders/MzExe/Borland/SymbolLoader.cs). MEASURED: both binaries carry `FB 52` at exactly the load-image boundary.

| file | on disk | load image | appended block | version word |
|---|---|---|---|---|
| `NEUROSIS.000` | 17,426 | 12,880 | 4,546 | `0x0208` |
| `NEUROSIS.009` | 10,356 | 7,312 | 3,044 | `0x0208` |

The version word at offset 02h is `0x0208` in both (read as minor byte 0x08 then major byte 0x02, i.e. format 2.08 — the byte order is DOCUMENTED in [ramikg/tdinfo-parser](https://github.com/ramikg/tdinfo-parser/blob/master/tdinfo_structs.py), RBIL just says "version ID"). Later Borland C++ era files carry higher versions and larger header extensions; TP7 emits extension size 0. The same magic also opens standalone 16-bit `.TDS` files (what TDSTRIP/TSPLIT peel off an EXE) — same format, just not appended.

## 2. The header, measured against Table 01624

RBIL Table 01624 names every field; the base header is 0x30 (48) bytes, followed by an extension of 0, 0x10, or 0x20 bytes whose size is at offset 2Eh. Measured values for both files:

| offset | size | field (RBIL 01624) | `.000` | `.009` |
|---|---|---|---|---|
| 00h | WORD | signature `52FBh` | `52FB` | `52FB` |
| 02h | WORD | version ID | `0208` | `0208` |
| 04h | DWORD | size of name pool in bytes | 1,274 | 1,182 |
| 08h | WORD | number of names in name pool | 157 | 138 |
| 0Ah | WORD | number of type entries | 52 | 43 |
| 0Ch | WORD | number of structure members | 0 | 0 |
| 0Eh | WORD | number of symbols | 150 | 132 |
| 10h | WORD | number of global symbols | 0 | 0 |
| 12h | WORD | number of modules | 4 | 3 |
| 14h | WORD | number of locals (optional) | 0 | 0 |
| 16h | WORD | number of scopes | 15 | 6 |
| 18h | WORD | number of line-number entries | 284 | 25 |
| 1Ah | WORD | number of include (source) files | 1 | 1 |
| 1Ch | WORD | number of segment records | 4 | 3 |
| 1Eh | WORD | number of segment/file correlations | 1 | 1 |
| 20h | DWORD | size of load image sans debug info | 0 | 0 |
| 24h | DWORD | debugger hook | 0 | 0 |
| 28h | BYTE | program flags (bit 0 case-sensitive, bit 1 overlay) | 0 | 0 |
| 29h | WORD | no longer used | 0 | 0 |
| 2Bh | WORD | size of data pool | 0 | 0 |
| 2Dh | BYTE | padding | 0 | 0 |
| 2Eh | WORD | size of header extension | 0 | 0 |

TP7 leaves everything from 20h to 2Dh zero (MEASURED — so the "image size" and "debugger hook" fields cannot be used to locate anything in these files).

## 3. Table order and record layouts — and two published readers that disagree

After the header the tables follow back to back, then the name pool. The order and sizes, MEASURED on both files:

| # | table | record size | record fields |
|---|---|---|---|
| 1 | symbols | 9 | name index W, type index W, offset W, segment W, flags B (bits 0-2 class: 0 static, 1 absolute, 2 auto/BP-relative, 3 Pascal var-param, 4 register, 5 constant, 6 typedef, 7 tag) |
| 2 | modules | 16 | name index W, language B (low 3 bits: 2 = Pascal), flags B, then three index/count word pairs: symbols, source files, correlations |
| 3 | source files | 6 | name index W, DOS-packed timestamp DW (date in the high word) |
| 4 | line numbers | 4 | line number W, code offset W (relative to the correlated segment) |
| 5 | scopes | 12 | autos index W, autos count W, parent W, function symbol W, offset W, length W |
| 6 | segments | 16 | module W, segment W, offset W, length W, scopes index/count W W, correlations index/count W W |
| 7 | correlations | 8 | segment W, source file W, lines index W, lines count W |
| 8 | types | 8-byte slots | id B, name index W, size W, 3 payload bytes; range types (SCHAR/SINT/SLONG/UCHAR/UINT/ULONG/PCHAR) carry 4-byte lower and upper bounds and **consume the following slot too** |
| 9 | members | 5 | info B, name index W, type index W (0 records here, layout DOCUMENTED only) |
| 10 | name pool | — | `names_pool_size` bytes of NUL-terminated ASCII at EOF; indexed from 1, index 0 = no name |

All indexes into the symbol/scope/line tables are 1-based; 0 means none, and 0xFFFF/0xFFFE appear as sentinels in scope function fields (MEASURED).

The two open-source readers each get one thing wrong, and both errors were settled by measurement, not by trusting either source — the project's "distrust the verifier" rule applying to *published* verifiers:

- **Reko parses scopes before line numbers** ([`SymbolLoader.cs`](https://github.com/uxmal/reko/blob/master/src/ImageLoaders/MzExe/Borland/SymbolLoader.cs), `LoadDebugHeader`). On TP7 output that order reads garbage; with **lines first** the line table rises monotonically (`300@0000 301@0014 ... 340@005A` for BYEBYE.PAS) and the scope autos ranges exactly tile the symbol table by module (`(1,6) (7,53) (60,73)` = PROGRAM's 6 + Crt's 53 + System's 73 = 132). MEASURED.
- **tdinfo-parser gives segment records 14 bytes** ([`tdinfo_structs.py`](https://github.com/ramikg/tdinfo-parser/blob/master/tdinfo_structs.py), `Padding(4)` after six words); Reko's 16-byte struct with correlation index/count is right. With 14 bytes every later table shears by 2 bytes per segment record and the type table decodes as noise; with 16 the block closes exactly: header 48 + symbols + modules + sources + lines + scopes + segments + correlations + types + name pool = appended size, **residue 0 bytes, in both files**. MEASURED.

The fixed-8-byte-slot type walk (tdinfo-parser's model) also misreads TP7 types unless range records are given their second slot — Reko's variable reads with `++i` are correct there. With both corrections the TP7 type table decodes into textbook Pascal: `SCHAR Shortint -128..127`, `SINT Integer -32768..32767`, `UCHAR Byte 0..255`, `TPREAL Real size 6`, `PSTR STRING size 256`, `TFILE Text size 256`, and in `.009` a `PARRAY` of size 4,000 with index subrange `1..4000` — `IMAGEDATA`, the 80x25x2 text screen (MEASURED; the constant `IMAGEDATA_LENGTH = 0FA0h = 4000` in the same block agrees).

## 4. The empirical decode

Run it yourself; the tool takes any MZ file on argv and has no project facts in it:

    python toolkit/substrate/tddump.py bin/NEUROSIS.000 bin/NEUROSIS.009
    python toolkit/substrate/tddump.py --names-only bin/NEUROSIS.009

### NEUROSIS.009 (BYEBYE.PAS)

3 modules, 1 source file, 132 symbols, 25 line records, all decoded (MEASURED):

    module 1: PROGRAM   language=Pascal flags=0x04 symbols=(7,0)   srcfiles=(1,1) correlations=(1,1)
    module 2: Crt       language=Pascal flags=0x04 symbols=(60,0)  srcfiles=(0,0) correlations=(0,0)
    module 3: System    language=Pascal flags=0x04 symbols=(133,0) srcfiles=(0,0) correlations=(0,0)
    source 1: BYEBYE.PAS  timestamp 0x1C4493E7 = 1994-02-04 18:31:14

One field does not read as documented: the module record's symbols pair is documented as (index, count), but TP7 writes (7,0), (60,0), (133,0) — each value is one past the module's last symbol (PROGRAM owns 1-6, Crt 7-59, System 60-132), so it behaves as an exclusive end index with the count unused. INFERRED from three consistent module records in each file; the scope table, which does carry honest (index, count) pairs, is the reliable way to partition symbols by module.
    segment 1: module=1 0000:0000 length=0x0062   (the program body: 98 bytes of code)
    segment 2: module=2 0007:0000 length=0x061F   (Crt)
    segment 3: module=3 0069:0000 length=0x0592   (System)
    correlation 1: segment=1 file=1 lines=(1,25)

The program module's own symbols — the ones an RE session actually wants — are exactly the six that `docs/20-parts000-009-setup-and-end.md` recorded:

    sym 1: 00C3:0002 static    type#38 IMAGEDATA          (PARRAY, 4000 bytes)
    sym 2: 00C3:0FF0 static    type#26 P                  (far pointer)
    sym 3: 00C3:0FF4 static    type#8  Flag               (Byte)
    sym 4: 0000:0050 constant          IMAGEDATA_WIDTH  = 80
    sym 5: 0000:0019 constant          IMAGEDATA_DEPTH  = 25
    sym 6: 0000:0FA0 constant          IMAGEDATA_LENGTH = 4000

Constants store their value in the offset/segment fields (class 5; `MaxLongint` arrives as `7FFF:FFFF`). Symbols 7 through 132 are the Crt and System unit interfaces — `ClrScr`, `GotoXY`, `ReadKey`, `HeapOrg`, `SaveInt00`..`SaveInt75`, `Test8086`, and the full typedef set (`Integer`, `Byte`, `Real`, ...). The 25 line records map BYEBYE.PAS source lines 300-340 onto code offsets 0000-005A of segment 1, so the main body starts at line 300 of a file whose earlier lines are the IMAGEDATA typed constant.

### NEUROSIS.000 (STARTUP.PAS)

4 modules (PROGRAM, **Detect**, Crt, System), 150 symbols, 284 line records covering source lines up to the main body, and — unlike `.009` — named program routines with their locals, because scopes 8-13 carry function symbols (MEASURED):

    source 1: STARTUP.PAS  timestamp 0x1C460164 = 1994-02-06 00:11:08
    sym 1: 0000:0039 static YesNo         scope  8: offset=0x0039 length=0x008A
    sym 2: 0000:00C3 static WriteStr      scope  9: offset=0x00C3 length=0x00AF
    sym 3: 0000:01B9 static detected      scope 10: offset=0x01B9 length=0x005D
    sym 4: 0000:09E3 static ChooseCard    scope 11: offset=0x09E3 length=0x0D8C
    sym 5: 0000:176F static IsVGA         scope 12: offset=0x176F length=0x0029
    sym 6: 0000:18B8 static Detections    scope 13: offset=0x18B8 length=0x00EA
    sym 7..19: auto (BP-relative) locals: ch, x, y, col, s, loop1, loop1, loop2, opt, ch, forfile, f, IsVGA
    sym 20: 01AD:0000 static Is386        sym 21: 01AD:0014 static IsProtMode    sym 22: 01AD:001B static HasMouse
    segment 1: module=1 0000:0000 length=0x1AC7    segment 2: module=2 (Detect) 01AD:0000 length=0x0031

Auto-class offsets are signed BP-relative (`loop1` at `FFFE` = BP-2), and a `pasvar`-class symbol would be a `var` parameter's far-pointer slot. `MEMAVAIL` and `MAXAVAIL` are present as System-unit entries at `0213:02E7` and `0213:0303`, confirming the claim in `docs/20`. The Detect unit — Asphyxia's own — exports exactly `Is386`, `IsProtMode`, `HasMouse` in 0x31 bytes of code.

### New facts this decode adds to the record

- **Source timestamps survive in the binaries**: BYEBYE.PAS was last saved 1994-02-04 18:31:14, STARTUP.PAS 1994-02-06 00:11:08 (DOS packed format, DOCUMENTED as "time stamp" in the source-file record; the decoding to date fields is standard DOS and the 1994 values are self-authenticating). Reconstruction sources can carry these as targets.
- The unit link order and per-unit code sizes are in the segment table (Crt is 0x61F bytes in both, System 0x592 vs 0xD95 — `.000` links file I/O that `.009` never touches).
- The "70 functions" (`.000`) and "38 functions" (`.009`) figures in `docs/20` are **not from this debug info** — the debug info names 6 program routines in STARTUP.PAS and none in BYEBYE.PAS (its main body only); those counts must come from disassembly of the whole image including the RTL. Not a contradiction, but the doc reads as if the debug info supplied them. INFERRED.

## 5. What can read it, verified to source

| reader | verdict | evidence |
|---|---|---|
| `toolkit/substrate/tddump.py` | full decode, zero residue | MEASURED here; stdlib only, no project facts, paths from argv |
| Borland TDUMP.EXE | the reference dumper | DOCUMENTED — Borland's own utility, shipped with TP7/BC++; named as the "more complete parsing" route by tdinfo-parser's README. Period binary, so not fetched (standing rule) |
| Turbo Debugger (TD.EXE) | consumes it directly | DOCUMENTED — [TD 4.0 User's Guide, bitsavers](https://bitsavers.org/pdf/borland/turbo_debugger/Turbo_Debugger_Version_4.0_Users_Guide_Oct93.pdf) |
| [ramikg/tdinfo-parser](https://github.com/ramikg/tdinfo-parser) | works for symbols/names into IDA; segment record 2 bytes short, type table wrong for TP7 | MEASURED against its `tdinfo_structs.py` |
| [Reko decompiler](https://github.com/uxmal/reko) | real `SymbolLoader` for this format, and the best surviving copy of the OAH text in its comments; scopes/lines order wrong for TP7 | MEASURED against its `SymbolLoader.cs` |
| Ghidra | **no support** | DOCUMENTED — open issues [#3635](https://github.com/NationalSecurityAgency/ghidra/issues/3635), [#3877](https://github.com/NationalSecurityAgency/ghidra/issues/3877) |
| radare2 | **no support** | MEASURED — a code search over the repo finds `52fb` only in an ARM test vector and nothing under `libr/bin` |
| Free Pascal | **no reader** | MEASURED — code search over `fpc/FPCSource` finds no `52FB`; FPC emits STABS/DWARF, and Delphi-era 32-bit `.TDS` is a different, later format (the one [tds2dbg](https://sourceforge.net/projects/tds2dbg/) targets) |
| Open Watcom | **no reader** | MEASURED — code search over `open-watcom/open-watcom-v2` finds no `52FB` |

## 6. Sources

- Ralf Brown's Interrupt List, 61b, `INTERRUP.G` table 01624 — header layout. [Mirror on GitHub](https://github.com/cirosantilli/ralf-brown-interrupt-list/blob/master/inter61b/INTERRUP.G).
- Borland Open Architecture Handbook, debug-info chapter — record layouts, symbol classes, type ids, register id table. Quoted at length inside [Reko `SymbolLoader.cs`](https://github.com/uxmal/reko/blob/master/src/ImageLoaders/MzExe/Borland/SymbolLoader.cs); the plain-text copy this trail started from (`download.xskernel.org/docs/file formats/omf/borland.txt`, cited by [excbadacc.es/borland](https://excbadacc.es/borland)) is now a parked domain.
- [ramikg/tdinfo-parser](https://github.com/ramikg/tdinfo-parser) — independent reader, table order, version-word byte order.
- `bin/NEUROSIS.000`, `bin/NEUROSIS.009` — the bytes themselves, which outvoted both readers once each.
