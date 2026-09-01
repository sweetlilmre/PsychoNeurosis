"""Emit the compiled-in data of parts 001, 002, 003 and 006 as Pascal typed
constants -- the tables that need CODE to read.

Anything in DGROUP's *initialised* region was a typed constant in the original
source. Plain `var` lands in BSS and is not stored in the executable, so
whatever we can read out of the file image must have carried an initialiser.

THE DECLARATIVE EMITTER IS THE OTHER HALF OF THIS JOB, and it is where a table
belongs unless it needs code. `kit/tools/pascal/emit.py` reads `emit.toml` and
covers anything expressible as offset, count, element type and one group size;
P3PAL, P3SINE, P3SHAPE and (since 1 Sep 2026) P5MESH live there. This file is
for the rest, and each one earns its place:

    P1VECT      three arrays, one of which is never read at run time
    P2OBJ/2     the face array's EXTENT is computed by walking a variable-length
                record stream, scalars are interleaved between the arrays, and
                the split across two files is at a measured point
    P6TEXT      Borland String[n] read at a stride, with blank padding for the
                slots that fall past the load image
    P6CELL      a THREE-dimensional constant -- two levels of nesting
    P3CAPT      strings and two levels of nesting together

An earlier version of this line said "the same way tools/emit_pascal_data.py
does for part 003". That file no longer exists: it was archived under #29 and
superseded by the declarative emitter above. It also said parts 001, 002, 005
and 006, which named the one part that has now moved out and omitted 003.

DGROUP is always the highest segment in the relocation map:

    part 001  $18F8      part 002  $1866
    part 003  $1761      part 006  $164E

Output goes to src/gen/ and is included by the hand-written units.

    python tools/emit_pascal_data2.py            write src/gen/
    python tools/emit_pascal_data2.py --check    compare src/gen against this
                                                 script, write nothing

**RUN `--check` BEFORE REGENERATING.** All seven of these files were hand-edited
under ticket #70 to keep reverse-engineering apparatus out of the documentation
copy, and this script was not updated to match, so for months regenerating would
have reverted a closed ticket. The divergence was comment-only and the data
identical, which is precisely why nothing caught it: no compiled byte changes, so
the build stays byte-identical and every artefact row goes on holding. See
check() for what that costs and why the comparison is worth having.
"""
import re
import shutil
import struct
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
# mzinfo is the kit's now (#50). These scripts are the record's, or are
# waiting their turn to move, and they keep working meanwhile -- which is
# the standing rule: the originals go on working until their successor has
# landed AND every caller has been repointed.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
                      "kit" / "tools"))
from substrate.mzinfo import parse
# The formatter, so there is ONE of it. See fmt() below for what this replaced
# and what is left behind.
from pascal.emit import fmt_array

OUT = Path("src/gen")

DGROUP = {"001": 0x18F8, "002": 0x1866, "003": 0x1761,
          "006": 0x164E}


def dg(part):
    h = parse(Path(f"work/split/NEUROSIS_{part}.exe"))
    return h["raw"], h["hdrsize"] + DGROUP[part] * 16 - 0x10000


def fmt(name, typ, values, per_line=12, group=None):
    """A Pascal typed-constant array.

    Multidimensional arrays need NESTED parentheses: `array[1..N, 1..3]` takes
    ((a,b,c), (d,e,f), ...), not a flat list. Getting this wrong is what
    produced `Error 88: "(" expected` the first time these reached TPC.
    Pass group=3 for [N,3]; group=(16,8) for [N,16,8].

    THE FLAT AND SINGLE-GROUP CASES ARE THE KIT'S NOW. This file carried its own
    copy of that formatter, character for character, and the copy is exactly how
    `{ 1 faces the loader reads }` could be wrong here and right in the tree: a
    duplicated formatter means a fix lands in one of them. Verified by emitting
    every remaining file both ways -- byte-identical.

    What stays is the TWO-level case, because `fmt_array` does one level and only
    P6CELL and P3CAPT need two. When a string element type and two-level nesting
    move to the kit, those two files move with them and this function goes.
    """
    if not isinstance(group, tuple):
        return fmt_array(name, typ, values, per_line, group=group)

    # array[1..27, 1..16, 1..8]: one parenthesised block per band, one row per
    # column inside it. per_line does not apply -- the inner dimension sets the
    # line length, which is why the P6CELL call's 32 was never read.
    outer, inner = group
    lines = [f"  {name} : {typ} = ("]
    blk = outer * inner
    for b in range(0, len(values), blk):
        rows = [values[b:b + blk][i:i + inner] for i in range(0, blk, inner)]
        lines.append("    (")
        for j, r in enumerate(rows):
            body = "(" + ", ".join(str(v) for v in r) + ")"
            lines.append(f"      {body}" + ("," if j + 1 < len(rows) else ""))
        lines.append("    )" + ("," if b + blk < len(values) else ""))
    lines.append("  );")
    return "\n".join(lines)


def header(text):
    return "{ " + text.strip() + "\n\n  Generated by tools/emit_pascal_data2.py -- do not edit. }\n\ncons" + "t\n"


# ---------------------------------------------------------------- part 001

def emit_p001():
    raw, base = dg("001")
    out = [header("""Part 001 scene 5 -- the two 3-D vector objects.

  Compiled in as signed integer (X, Y, Z) triples and converted to Real at
  load time into 12-byte records.

  VecLogoA is flat (Z = 0 throughout) -- the circled "A" logo mark.
  VecGlobe is three orthogonal rings, +/-50 on every axis.

  See assets/part001/VECLOGOA.PNG and VECGLOBE.PNG.""")]
    total = 0
    # VecRing sits BETWEEN the two and nothing reads it. It is 18 points of a
    # radius-50 circle in the YZ plane at 20-degree steps -- one of the globe's
    # three rings, emitted on its own. The loader reads the globe from $01A8
    # (12c5:08b3 is PUSH WORD PTR [DI+$1A8]), so these 108 bytes are never
    # touched at run time. They are in DGROUP all the same, and leaving them
    # out shifted every initialised byte after $013C.
    for name, off, n, note in (("VecLogoA", 0x001C, 48, "the circled A, Z = 0"),
                               ("VecRing",  0x013C, 18, "a YZ ring, radius 50 -- NEVER READ"),
                               ("VecGlobe", 0x01A8, 36, "three rings, +/-50")):
        vals = []
        for i in range(n):
            vals.extend(struct.unpack_from("<hhh", raw, base + off + i * 6))
        out.append(f"  {{ DS:${off:04X} -- {n} points, {note} }}")
        # THE FIRST DIMENSION IS ZERO-BASED, and the loader's fold displacement
        # says so exactly. VecGlobe sits at DS:$01A8 and 12c5:08b3 is
        # PUSH WORD PTR [DI+$1A8] with DI = I * 6 -- the folded displacement IS
        # the base, so the first subscript contributes nothing to it and its low
        # bound is 0. Emitted as array[1..n] the fold came out $1A2, one 6-byte
        # element low, and the loader carried an INC AX per point to compensate.
        # FLAT AND ZERO-BASED, and the ORDER OF THE TWO MULTIPLIES says so. The
        # loader scales its counter by six either way, but 12c5:08a6 does it as
        # MOV SI,AX / SHL AX,1 / ADD AX,SI -- times THREE -- and only then
        # MOV DI,AX / SHL DI,1, times two. A two-dimensional [I, 1] subscript
        # emits the halves the other way round (times two, then three), because
        # it scales by the element size and the element is three Integers. Times
        # three then two is an INDEX of I * 3 into a one-dimensional Integer
        # array, with the trailing SHL being the Integer stride.
        # The fold confirms it: VecGlobe is at DS:$01A8 and the displacement is
        # $1A8, $1AA, $1AC for the three components -- base plus 0, 2, 4, which
        # is `[I * 3]`, `[I * 3 + 1]`, `[I * 3 + 2]` with the constant folded in.
        # Same shape as the Vert* arrays emitted further down.
        out.append(fmt(name, f"array[0..{n * 3 - 1}] of Integer", vals, 9))
        total += len(vals)
    OUT.joinpath("P1VECT.INC").write_text("\n".join(out) + "\n", encoding="ascii")
    return total


# ---------------------------------------------------------------- part 002

# THE ARRAY SIZE AND THE FACE COUNT ARE TWO DIFFERENT NUMBERS, and conflating
# them cost two bytes and a wrong reading. The ARRAY has to span the whole
# extent, because DGROUP's bytes are what dgimage compares and everything after
# a short array sits low: the Enterprise's stream runs to MViewW at $046A, the
# Revolver's to the Sailboat's vertices at $0B06, the Sailboat's to the Quad's
# at $0CAE, giving 338, 376 and 116 words. The COUNT is what the LOADER reads,
# and the original states it in its own code:
#
#     108b:1ec0  MOV word ptr [$65A7], $44     68  NVertRevolver
#     108b:1ec6  MOV word ptr [$65A9], $40     64  NFaceRevolver
#     108b:209e  MOV word ptr [$70FA], $15     21  NFaceSailboat
#
# 64 faces occupy 371 words of the Revolver's 376, and 21 occupy 111 of the
# Sailboat's 116. So five words at the end of each stream are IN DGROUP and are
# NEVER READ -- the same shape as part 001's VecRing, where 108 bytes sit in the
# image untouched and leaving them out shifted everything behind them.
#
# Deriving the count from the extent made both counts one too high and put 65
# and 22 into the loader where the original has 64 and 21, which is exactly the
# two one-byte spans at 108b:1ec8 and 209e. The extent gives the array; only the
# loader gives the count.
P2_OBJECTS = [
    # name, voff, nv, foff, fend (array extent), nf (what the loader reads)
    ("Enterprise", 0x0004, 75, 0x01C6, 0x046A, 55, "the USS Enterprise"),
    ("Revolver",   0x067E, 68, 0x0816, 0x0B06, 64, "a revolver, modelled along Y"),
    ("Sailboat",   0x0B06, 32, 0x0BC6, 0x0CAE, 21, "a sailboat, modelled along Y"),
    ("Quad",       0x0CAE,  4, 0x0CC6, None,    1, "a single quad"),
]


def emit_p002():
    raw, base = dg("002")
    out = [header("""Part 002 scene 2 -- the four 3-D models, compiled into DGROUP.

  Vertices are signed word triples; coordinates are HALVED on load.

  The face stream is variable length -- for each face:

      count, index1 .. indexN, colour        (count + 2 words)

  Faces have 3, 4, 6 or 8 vertices.

  THE INDEX BASE IS PER MODEL, and only the loader says which. The Enterprise's
  indices are stored ZERO-based and Scene2_Setup adds one; the revolver's, the
  sailboat's and the quad's are stored ONE-based and are used as read. Same
  format, same segment, three models one way and one the other:

      Obj[1].Face[I].Idx[K] := FaceEnterprise[P] + 1;
      Obj[2].Face[I].Idx[K] := FaceRevolver[P];
      Obj[3].Face[I].Idx[K] := FaceSailboat[P];
      Obj[4].Face[I].Idx[K] := FaceQuad[P];

  This header read "indices are stored zero-based and incremented on load" until
  1 Sep 2026, which is one model of four. The quad settles it alone: four
  vertices, one four-vertex face, and 1, 2, 3, 4 on disk.

  See assets/part002/OBJ*.PNG -- five projections of each, because a model is
  often unrecognisable from the obvious X/Y view. Whatever renders them has to
  carry the bias per model; one rule for all four is wrong three times.""")]
    total = 0
    for name, voff, nv, foff, fend, nf, note in P2_OBJECTS:
        # the ARRAY spans the whole extent; nf is only what the loader reads
        p = 0
        while (fend is None and p < 6) or (fend is not None and p * 2 < fend - foff):
            cnt = struct.unpack_from("<h", raw, base + foff + p * 2)[0]
            p += cnt + 2
        verts = []
        for i in range(nv):
            verts.extend(struct.unpack_from("<hhh", raw, base + voff + i * 6))
        out.append(f"\n  {{ {note} -- vertices }}")
        # The counts are emitted rather than written into the loader by hand:
        # Scene2_Setup reads them back OUT of the object it just filled,
        # so the only place a literal belongs is beside the table it counts.
        out.append(f"  NVert{name} = {nv};")
        out.append(f"  NFace{name} = {nf};")
        # FLAT, and the loader indexes it [(I - 1) * 3 + k]. A two-dimensional
        # array was an improvement on a bare [I] and still not the shape: for
        # A[I - 1, 2] the compiler multiplies the outer index by SIX in one go
        # and folds the inner subscript into the displacement, while the
        # original multiplies by THREE, adds the inner offset AT RUNTIME -- one
        # INC per unit, so the third component is INC AX twice -- and only then
        # doubles for the element size. That is the code for an explicit
        # `(I - 1) * 3 + k` index into a one-dimensional array of Integer, and
        # the displacement left over is the table's own DGROUP offset.
        #
        # The bytes are identical either way; only the addressing differs. This
        # closed twelve spans in the four loaders, three per object.
        out.append(fmt(f"Vert{name}", f"array[0..{nv * 3 - 1}] of Integer", verts, 9))

        # the array spans the EXTENT, read as flat words: past the nf faces the
        # stream is not necessarily well-formed, and it does not need to be --
        # nothing reads it, and only its BYTES have to be in DGROUP
        nw = p if fend is None else (fend - foff) // 2
        faces = [struct.unpack_from("<h", raw, base + foff + i * 2)[0]
                 for i in range(nw)]
        p = nw
        out.append(f"  {{ {nf} face{'' if nf == 1 else 's'} the loader reads, "
                   f"{nw} words }}")
        # ZERO-BASED, LIKE THE VERTEX ARRAYS ABOVE, and Scene2_Setup's counter
        # says so: 108b:1d9c is XOR AX,AX / MOV [BP-$06],AX -- the walk index
        # starts at 0 -- and every read of it is a bare MOV DI,[BP-$06] with no
        # arithmetic. Emitted as array[1..n] the only way to read the same
        # element was Face...[P + 1], which cost MOV AX / INC AX / MOV DI,AX at
        # twelve sites, and starting the counter at 1 instead traded those for a
        # MOV [BP-$06],1 where the original has the shorter XOR pair. Four
        # objects, three bytes each.
        out.append(fmt(f"Face{name}", f"array[0..{p - 1}] of Integer", faces, 12))
        total += len(verts) + len(faces)
        if name == P2_OBJECTS[0][0]:
            first, out = out, ["const"]     # split after the first model

    # TWO FILES, AND THE SPLIT IS MEASURED. The original's initialised data has
    # the FIRST model's tables at DS:$000A..$0469 and then MViewW, MViewH, Msg1
    # and Msg2 -- the other three models come AFTER those, from DS:$066E.
    # Emitted as one include all four land together and everything behind them
    # sits 1,606 bytes too high: dgimage put our MViewW at $0AAA against the
    # original's $046A. So P2SOLID includes the first file, declares the four
    # constants, and includes the second.
    OUT.joinpath("P2OBJ.INC").write_text("\n".join(first) + "\n", encoding="ascii")
    OUT.joinpath("P2OBJ2.INC").write_text(
        "{ GENERATED by tools/emit_pascal_data2.py -- DO NOT EDIT.\n"
        "\n"
        "  Part 002 scene 2 -- models two, three and four. The FIRST model is in\n"
        "  P2OBJ.INC and included BEFORE MViewW; these come after Msg2, which is where\n"
        "  the original has them. Include order is declaration order, so moving either\n"
        "  include moves everything after it. }\n"
        + "\n".join(out) + "\n", encoding="ascii")
    return total


# PART 005 IS NOT HERE ANY MORE. P5MESH.INC moved to emit.toml on 1 Sep 2026 --
# it was offset, count, element and one group size with no logic around it, so
# the declarative config could already say all of it, and a hand-written emitter
# for a pure table only bought a second copy of the same formatter. Verified by
# emitting it both ways and comparing: the const body is BYTE-IDENTICAL, 5,766
# values, 34,844 bytes. What is left in this file is the data that needs code.


# ---------------------------------------------------------------- part 006

# P6CREDIT declares `Lines = 113` and indexes String[12]; the generator must
# agree with the source it feeds, so both live here as names rather than
# being derived from however much text the image happens to hold.
P6_CREDIT_LINES = 99       # NOT 113 -- see the docstring below
P6_CREDIT_WIDTH = 255      # 256 bytes per element, and the docstring below
                           # always said so -- a Borland String[n] occupies
                           # n+1 bytes, so the $100 stride this table is READ
                           # with IS the declaration. Declared String[12] the
                           # stride was 13 and the array was 1,469 bytes where
                           # the original's is 28,928.


def pascal_strings(raw, base, first, stride, limit=400):
    out, off = [], first
    while len(out) < limit:
        n = raw[base + off]
        if n == 0 or n > 80:
            break
        out.append(raw[base + off + 1: base + off + 1 + n].decode("latin1"))
        off += stride
    return out


def emit_p006_text():
    """The credits table -- NINETY-NINE entries of 256 bytes from DS:$0D8A.

    This docstring used to say 113, and 113 is the LOOP'S bound, not the
    array's. The two are not the same and the address of the next variable
    proves it: P6WHOOSH's Path pointer is at DS:$737E, and 99 slots of 256 from
    $0D8A end at $708A while 113 would run to $7F8A -- with Path inside the
    array. It cannot be 113.

    P6CREDIT does count to 113 (11bb:02fa stops at $72), so lines 100..113 read
    PAST the array into the constants beyond it, which are zeros. That is why
    they arrive blank at run time, and it is the observation the old docstring
    had hold of by the wrong end.

    The stride is $100, so the element type is String[255]: a Borland
    String[n] occupies n+1 bytes. Declared String[12] the table came out 1,469
    bytes where the original's is 25,344.
    """
    raw, base = dg("006")
    lines = pascal_strings(raw, base, 0x0D8A, 0x0100, limit=P6_CREDIT_LINES)
    blank = ""             # the trailing slots are ZEROS in the image, which
                           # is a String of length 0, not a run of spaces
    lines += [blank] * (P6_CREDIT_LINES - len(lines))
    body = header(f"""Part 006 scene 4 -- the credits text.

  A Borland `array[1..{P6_CREDIT_LINES}] of String[{P6_CREDIT_WIDTH}]` -- {P6_CREDIT_WIDTH + 1} bytes per element, which is
  why the stride is $100. Only the first {sum(1 for s in lines if s.strip())} lines carry text in the load
  image; the rest fall past its end and are blank at run time, so they are
  blank here.

  Four blocks, one per member: EzE, GoTH, Denthor and Fubar.""")
    body += "  CreditText : array[1..%d] of String[%d] = (\n" % (
        P6_CREDIT_LINES, P6_CREDIT_WIDTH)
    for i, s in enumerate(lines):
        comma = "," if i + 1 < len(lines) else ""
        body += f"    '{s.replace(chr(39), chr(39) * 2)}'{comma}\n"
    body += "  );\n"
    OUT.joinpath("P6TEXT.INC").write_text(body, encoding="ascii")
    return len(lines)


def emit_p006_cells():
    """The whoosh board: array[1..27, 1..16, 1..8] of Byte.

    Stored [band][column][rowInBand]; each band is one 8-wide x 16-tall letter
    lying on its side, because the board is drawn transposed (map row -> screen
    X, map column -> screen Y).
    """
    raw, base = dg("006")
    A = 0x000A
    # TWENTY-SEVEN BANDS, and DGROUP's own arithmetic is what fixes the count:
    # the credits text starts at DS:$0D8A in the 1994 file, and $000A plus
    # 27 * 128 is $0D8A exactly, where 26 bands land it at $0D0A. The
    # twenty-seventh is all zeroes, which is why nothing in the data itself
    # gives it away -- it took the two DGROUP images side by side, where the
    # original has 128 more zeros before the first credit string than ours did.
    # Worth 128 bytes to every variable in the part, and the part's data was
    # 128 bytes short of the original's until it was counted.
    vals = list(raw[base + A: base + A + 27 * 128])
    body = header("""Part 006 scene 2 -- the whoosh board.

  array[1..27, 1..16, 1..8] of Byte. Each band is one letter cell
  block; the value is the CELL TYPE drawn at that grid position (1 = letter,
  0 = nothing; Whoosh_Load pre-fills the whole board with 2 = background).

  The storage is [band][column][rowInBand], and the board is drawn transposed
  -- map row becomes screen X, map column becomes screen Y -- so each band is
  an 8-wide by 16-tall letter lying on its side.

  Bands  1..16 spell "ASPHYXIA RULZ" (13 letters then 3 blanks) and are the
                only ones Whoosh_Load copies onto the board.
  Bands 17..26 spell "0,000 DOTS" and are NEVER USED -- dead data left in the
                executable. The scroll text boasts "4000 DOTS", so this was
                presumably an earlier version of the same gag.
  Band     27 is entirely ZERO and is never drawn either. It is here because
                the credits text that follows it in DGROUP is at $0D8A, and
                $000A + 27 * 128 is $0D8A; twenty-six bands put every variable
                in the part 128 bytes low.""")
    # CELLSHAPE, and all TWENTY-SEVEN bands. The truncated 16-band copy in
    # P6SHAPE.INC was read from the same DS:$000A with a shorter length, and
    # its own generator no longer exists. Bands 17..27 are never drawn -- the
    # same shape as part 003's unused shape slots -- but they are in DGROUP
    # and everything declared after them moves if they are left out.
    body += fmt("CellShape", "array[1..27, 1..16, 1..8] of Byte", vals, 32, group=(16, 8))
    OUT.joinpath("P6CELL.INC").write_text(body + "\n", encoding="ascii")
    return len(vals)


# ---------------------------------------------------------------- part 003

def emit_p003_captions():
    raw, base = dg("003")
    lines = pascal_strings(raw, base, 0x76B8, 0x0100)
    body = header(f"""Part 003 scene 7 -- the member captions, {len(lines)} lines.

  array[1..4, 1..10] of String[255], stride $100. Ten lines per member, in
  the same order as the four rotating portraits.

  TWO-DIMENSIONAL, not flat: the two subscripts are applied separately, so the
  displacement absorbs the low bounds. A flat array of 40 indexed
  Captions[(N-1)*10 + Row] reaches the same address by a different route and
  emits different code. Same 10,240 bytes either way.

  [re] 125e:0741 is why. The original indexes it as
  Captions[N, Row][Col]: IMUL DI,[BP+4],$0A00 for the member, a separate
  Row*256, and Col added last. A flat array[1..40] indexed
  Captions[(N-1)*10 + Row] emits a DEC and an IMUL by 10 instead, so the bytes
  never match.

  STRING[255], AND THE STRIDE THIS TABLE IS READ WITH IS WHY. A Borland
  String[n] occupies n+1 bytes, so $100 is String[255]; the declaration used to
  say String[50], a stride of 51. Across forty slots that is 8,200 bytes, and
  it was the whole of this part's remaining DGROUP size difference.

  The unused tail of each slot is zeros, and they are STORED -- a typed
  constant is in the file image and a var is not. Nothing in the part's code
  reads them: a scan of every code segment for absolute displacements into that
  range found nine scalars at the very top and nothing across the eight
  kilobytes below.""")
    rows = 10
    members = len(lines) // rows
    body += ("  Captions : array[1..%d, 1..%d] of String[255] = ("
             + "\n") % (members, rows)
    for m in range(members):
        body += "    (" + "\n"
        for r in range(rows):
            s = lines[m * rows + r]
            comma = "," if r + 1 < rows else ""
            body += "      '%s'%s" % (s, comma) + "\n"
        body += "    )%s" % ("," if m + 1 < members else "") + "\n"
    body += "  );" + "\n"
    OUT.joinpath("P3CAPT.INC").write_text(body, encoding="ascii")
    return len(lines)


# Every file this script writes. P2OBJ2.INC has no emitter of its own -- it is
# the second half of emit_p002 -- so it has to be named here or a check would
# silently skip it.
FILES = ("P1VECT.INC", "P2OBJ.INC", "P2OBJ2.INC",
         "P6TEXT.INC", "P6CELL.INC", "P3CAPT.INC")


def emit_all():
    OUT.mkdir(parents=True, exist_ok=True)
    return [
        ("P1VECT.INC", emit_p001(), "values"),
        ("P2OBJ.INC", emit_p002(), "values"),
        ("P6TEXT.INC", emit_p006_text(), "strings"),
        ("P6CELL.INC", emit_p006_cells(), "bytes"),
        ("P3CAPT.INC", emit_p003_captions(), "strings"),
    ]


def code_only(data):
    """The file with every Pascal comment removed, for comparing DATA alone."""
    text = data.decode("latin-1")
    while True:
        stripped = re.sub(r"\{[^{}]*\}", "", text, flags=re.S)
        if stripped == text:
            break
        text = stripped
    return re.sub(r"\s+", " ", text).strip()


def check():
    """Regenerate into a temporary directory and compare against src/gen.

    WHY THIS EXISTS, and it is the whole reason to run it. These files are
    generated, and for months they were not what this script produces. Ticket
    #70 edited all seven BY HAND to keep reverse-engineering apparatus out of
    the documentation copy, and nothing updated the emitter -- so running the
    emitter silently REVERTED a closed ticket, and the only thing preventing
    that was nobody happening to run it.

    It stayed invisible because the divergence was comment-only and the data
    identical in all seven files. Every byte instrument in the tree was blind to
    it by construction: a comment changes no compiled byte, so the build stayed
    byte-identical and every artefact row went on holding. Nothing was WRONG
    with the tree. What was wrong was that two things claimed to be the same
    file and nobody compared them.

    A generated file that nothing checks against its generator is a hand-written
    file with a misleading banner on top.
    """
    global OUT
    tree = OUT
    tmp = Path(tempfile.mkdtemp(prefix="emitcheck-"))
    try:
        OUT = tmp
        emit_all()
        bad, data_bad = 0, 0
        print("regenerated into a temporary directory and compared against "
              "%s\n" % tree)
        for name in FILES:
            a, b = tree / name, tmp / name
            if not a.exists():
                print("  %-14s MISSING from the tree" % name)
                bad += 1
                continue
            ab, bb = a.read_bytes(), b.read_bytes()
            if ab == bb:
                print("  %-14s identical" % name)
                continue
            bad += 1
            if code_only(ab) == code_only(bb):
                print("  %-14s DIFFERS in comments only -- the data is "
                      "identical, so no build changes" % name)
            else:
                data_bad += 1
                print("  %-14s DIFFERS IN THE DATA -- this changes what the "
                      "compiler sees" % name)
        print("\n  %d of %d file(s) differ from what this script produces."
              % (bad, len(FILES)))
        if data_bad:
            print("  %d of them differ in DATA. Do not regenerate over the tree "
                  "until that is\n  understood: a byte-identical build is "
                  "resting on the committed copies." % data_bad)
        elif bad:
            print("  All comment-only. Either the tree was edited by hand and "
                  "this script needs\n  the same edit, or this script was "
                  "changed and the tree needs regenerating.\n  Whichever it is, "
                  "they disagree, and running the emitter would overwrite the\n"
                  "  tree's wording without saying so.")
        else:
            print("  The tree is exactly what this script writes.")
        return 1 if bad else 0
    finally:
        OUT = tree
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    for name, n, unit in emit_all():
        p = OUT / name
        lines = len(p.read_text(encoding="ascii", errors="replace").splitlines())
        print(f"  {name:<14} {n:>7,} {unit:<8} {lines:>6,} lines")


if __name__ == "__main__":
    sys.exit(check() if "--check" in sys.argv else main())
