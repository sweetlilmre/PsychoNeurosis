"""Dump Borland Turbo Debugger debug info appended to a DOS MZ executable.

Turbo Pascal 7 / Borland C++ append a symbol table after the load image when
built with debug info in the executable ($D+ plus /v). The block starts with
the magic word 0x52FB at the byte the MZ header declares as the end of the
load image, and ends with a name pool of NUL-terminated ASCII strings. This
tool decodes the whole block and prints every table.

Format sources, in order of authority:

  * Ralf Brown's Interrupt List, table 01624 ("Format of Borland debugging
    information header"), which itself defers to Borland's Open Architecture
    Handbook. Header layout, field names.
  * Reko decompiler, src/ImageLoaders/MzExe/Borland/SymbolLoader.cs, which
    embeds long passages of the Borland documentation as comments. Record
    layouts, symbol classes, type ids, language codes.
  * ramikg/tdinfo-parser (tdinfo_structs.py). Record layouts, table order.

The two implementations disagree in two places, and both were settled by
measurement against real TP7 output (version word 0x0208), not by trusting
either source:

  * The line-number table comes BEFORE the scope table (tdinfo-parser's
    order). Reko parses scopes first; on TP7 output that reads garbage,
    while lines-first yields monotonically rising (line, offset) pairs and
    scope symbol ranges that exactly tile the symbol table by module.
  * A segment record is 16 bytes, ending with correlation index and count
    (Reko's struct). tdinfo-parser pads only 4 bytes after 6 words, giving
    14, which shears every later table by 2 bytes per segment record.

With those two corrections every byte of the block is accounted for: header
+ tables + name pool equals the appended size exactly, with no residue.

Type records sit in fixed 8-byte slots (id, name index, size, 3 payload
bytes); range types (SCHAR..PCHAR) carry 4-byte lower and upper bounds and
so consume the following slot as well, which is why a naive fixed-record
walk misreads the table's tail.

Usage:  python tddump.py FILE.EXE [FILE2.EXE ...]
        python tddump.py --names-only FILE.EXE

Exit code 0 if every named file carried decodable debug info, 1 otherwise.
Output is pure ASCII on stdout.
"""

import struct
import sys

MAGIC = 0x52FB

SYMBOL_CLASSES = {
    0: "static", 1: "absolute", 2: "auto", 3: "pasvar",
    4: "register", 5: "constant", 6: "typedef", 7: "tag",
}

LANGUAGES = {0: "unknown", 1: "C", 2: "Pascal", 3: "assembler",
             4: "C++", 5: "Prolog"}

# Type ids from the Borland documentation quoted in Reko's SymbolLoader.cs.
TYPE_IDS = {
    0x00: "VOID", 0x01: "LSTR", 0x02: "DSTR", 0x03: "PSTR",
    0x04: "SCHAR", 0x05: "SINT", 0x06: "SLONG", 0x07: "SQUAD",
    0x08: "UCHAR", 0x09: "UINT", 0x0A: "ULONG", 0x0B: "UQUAD",
    0x0C: "PCHAR", 0x0D: "FLOAT", 0x0E: "TPREAL", 0x0F: "DOUBLE",
    0x10: "LDOUBLE", 0x11: "BCD4", 0x12: "BCD8", 0x13: "BCD10",
    0x14: "BCDCOB", 0x15: "NEAR", 0x16: "FAR", 0x17: "SEG",
    0x18: "NEAR386", 0x19: "FAR386", 0x1A: "CARRAY", 0x1B: "VLARRAY",
    0x1C: "PARRAY", 0x1D: "ADESC", 0x1E: "STRUCT", 0x1F: "UNION",
    0x20: "VLSTRUCT", 0x21: "VLUNION", 0x22: "ENUM", 0x23: "FUNCTION",
    0x24: "LABEL", 0x25: "SET", 0x26: "TFILE", 0x27: "BFILE",
    0x28: "BOOL", 0x29: "PENUM", 0x2A: "PWORD", 0x2B: "TBYTE",
    0x2C: "FUNCPROTOTYPE", 0x2D: "SPECIALFUNC", 0x2E: "CLASS",
    0x30: "HANDLEPTR", 0x33: "MEMBERPTR", 0x34: "NREF", 0x35: "FREF",
    0x36: "WORDBOOL", 0x37: "LONGBOOL", 0x3E: "GLOBALHANDLE",
    0x3F: "LOCALHANDLE",
}

# Range types carry 4-byte lower/upper bounds and spill into the next
# 8-byte type slot.
RANGE_TYPE_IDS = {0x04, 0x05, 0x06, 0x08, 0x09, 0x0A, 0x0C}


def dos_timestamp(raw):
    """Render a DOS packed date/time dword (date in the high word)."""
    date, time = raw >> 16, raw & 0xFFFF
    return "%04d-%02d-%02d %02d:%02d:%02d" % (
        1980 + (date >> 9), (date >> 5) & 15, date & 31,
        time >> 11, (time >> 5) & 63, 2 * (time & 31))


def load_image_size(data):
    e_cblp, e_cp = struct.unpack_from("<HH", data, 2)
    return (e_cp - 1) * 512 + (e_cblp if e_cblp else 512)


def dump(path, names_only=False):
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:2] != b"MZ":
        print("%s: not an MZ executable" % path)
        return False
    load = load_image_size(data)
    dbg = data[load:]
    if len(dbg) < 48 or struct.unpack_from("<H", dbg, 0)[0] != MAGIC:
        print("%s: no Borland debug info after the %d-byte load image"
              % (path, load))
        return False

    minor, major = struct.unpack_from("<BB", dbg, 2)
    (pool_size,) = struct.unpack_from("<I", dbg, 4)
    (names_n, types_n, members_n, symbols_n, globals_n, modules_n,
     locals_n, scopes_n, lines_n, srcfiles_n, segs_n,
     corrs_n) = struct.unpack_from("<12H", dbg, 8)
    image_size, hook = struct.unpack_from("<II", dbg, 32)
    prog_flags = dbg[40]
    unused, data_pool = struct.unpack_from("<HH", dbg, 41)
    (ext_size,) = struct.unpack_from("<H", dbg, 46)

    print("== %s" % path)
    print("file %d bytes, load image %d, appended debug info %d"
          % (len(data), load, len(dbg)))
    print("magic 0x%04X  version word 0x%02X%02X (major %d, minor %d)"
          % (MAGIC, major, minor, major, minor))
    print("counts: names=%d types=%d members=%d symbols=%d globals=%d"
          % (names_n, types_n, members_n, symbols_n, globals_n))
    print("        modules=%d locals=%d scopes=%d lines=%d srcfiles=%d"
          % (modules_n, locals_n, scopes_n, lines_n, srcfiles_n))
    print("        segments=%d correlations=%d" % (segs_n, corrs_n))
    print("image_size=%d hook=0x%08X flags=0x%02X data_pool=%d ext=%d"
          % (image_size, hook, prog_flags, data_pool, ext_size))

    # Name pool: NUL-terminated ASCII strings at the very end of the file,
    # pool_size bytes long, indexed from 1. Index 0 means "no name".
    pool = dbg[len(dbg) - pool_size:]
    names = pool.split(b"\x00")

    def name(i):
        if i == 0:
            return "<none>"
        if 1 <= i <= len(names):
            return names[i - 1].decode("ascii", "replace")
        return "<bad name index %d>" % i

    off = 48 + ext_size

    def take(count, size):
        nonlocal off
        blob = dbg[off:off + count * size]
        off += count * size
        return blob

    syms = take(symbols_n, 9)
    mods = take(modules_n, 16)
    srcs = take(srcfiles_n, 6)
    lines = take(lines_n, 4)        # lines BEFORE scopes: measured on TP7
    scopes = take(scopes_n, 12)
    segs = take(segs_n, 16)         # 16-byte records: measured on TP7
    corrs = take(corrs_n, 8)
    types_off = off
    off += types_n * 8
    membs = take(members_n, 5)
    pool_start = len(dbg) - pool_size
    print("tables end at %d, name pool starts at %d, residue %d bytes"
          % (off, pool_start, pool_start - off))

    if names_only:
        for i in range(symbols_n):
            nm, typ, soff, sseg, bits = struct.unpack_from("<4HB", syms, i * 9)
            print("%04X:%04X %-9s %s"
                  % (sseg, soff, SYMBOL_CLASSES.get(bits & 7, "?"), name(nm)))
        return True

    print("-- modules")
    for i in range(modules_n):
        nm, lang, flags, sym_i, sym_c, src_i, src_c, cor_i, cor_c = \
            struct.unpack_from("<HBB6H", mods, i * 16)
        print("  module %d: %-12s language=%s flags=0x%02X symbols=(%d,%d)"
              " srcfiles=(%d,%d) correlations=(%d,%d)"
              % (i + 1, name(nm), LANGUAGES.get(lang & 7, "?"), flags,
                 sym_i, sym_c, src_i, src_c, cor_i, cor_c))

    print("-- source files")
    for i in range(srcfiles_n):
        nm, ts = struct.unpack_from("<HI", srcs, i * 6)
        print("  source %d: %s  timestamp 0x%08X = %s"
              % (i + 1, name(nm), ts, dos_timestamp(ts)))

    print("-- symbols")
    for i in range(symbols_n):
        nm, typ, soff, sseg, bits = struct.unpack_from("<4HB", syms, i * 9)
        print("  sym %3d: %04X:%04X %-9s type#%-3d %s"
              % (i + 1, sseg, soff, SYMBOL_CLASSES.get(bits & 7, "?"),
                 typ, name(nm)))

    print("-- scopes")
    for i in range(scopes_n):
        a_i, a_c, parent, func, s_off, s_len = \
            struct.unpack_from("<6H", scopes, i * 12)
        print("  scope %d: autos=(%d,%d) parent=%d function=%d"
              " offset=0x%04X length=0x%04X"
              % (i + 1, a_i, a_c, parent, func, s_off, s_len))

    print("-- line numbers (line@offset)")
    pairs = []
    for i in range(lines_n):
        ln, loff = struct.unpack_from("<2H", lines, i * 4)
        pairs.append("%d@%04X" % (ln, loff))
    for i in range(0, len(pairs), 8):
        print("  " + " ".join(pairs[i:i + 8]))

    print("-- segments")
    for i in range(segs_n):
        mod, cseg, coff, clen, sc_i, sc_c, co_i, co_c = \
            struct.unpack_from("<8H", segs, i * 16)
        print("  segment %d: module=%d %04X:%04X length=0x%04X"
              " scopes=(%d,%d) correlations=(%d,%d)"
              % (i + 1, mod, cseg, coff, clen, sc_i, sc_c, co_i, co_c))

    print("-- correlations")
    for i in range(corrs_n):
        seg_i, file_i, l_i, l_c = struct.unpack_from("<4H", corrs, i * 8)
        print("  correlation %d: segment=%d file=%d lines=(%d,%d)"
              % (i + 1, seg_i, file_i, l_i, l_c))

    print("-- types (8-byte slots; range types consume two)")
    i = 0
    while i < types_n:
        slot = types_off + i * 8
        tid, nm, size = struct.unpack_from("<BHH", dbg, slot)
        tail = dbg[slot + 5:slot + 8]
        label = TYPE_IDS.get(tid, "id 0x%02X" % tid)
        if tid in RANGE_TYPE_IDS and i + 1 < types_n:
            filler, parent = struct.unpack_from("<BH", dbg, slot + 5)
            lower, upper = struct.unpack_from("<ii", dbg, slot + 8)
            print("  type#%-3d %-8s name=%s size=%d parent=%d"
                  " range %d..%d [2 slots]"
                  % (i + 1, label, name(nm), size, parent, lower, upper))
            i += 2
        else:
            print("  type#%-3d %-8s name=%s size=%d tail=%s"
                  % (i + 1, label, name(nm), size, tail.hex()))
            i += 1

    if members_n:
        print("-- members")
        for i in range(members_n):
            info = membs[i * 5]
            m_nm, m_ty = struct.unpack_from("<HH", membs, i * 5 + 1)
            print("  member %d: info=0x%02X name=%s type#%d"
                  % (i + 1, info, name(m_nm), m_ty))

    print("-- name pool (%d names, %d bytes)" % (names_n, pool_size))
    for i in range(min(names_n, len(names))):
        print("  name#%-3d %s" % (i + 1, names[i].decode("ascii", "replace")))
    return True


def main(argv):
    names_only = "--names-only" in argv
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__)
        return 1
    ok = True
    for path in paths:
        ok = dump(path, names_only) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
