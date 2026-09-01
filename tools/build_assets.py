"""Build the clean asset tree in assets/ from NEUROSIS.DAT and from DGROUP.

MOST of assets/ is derived and can be rebuilt at any time. NOT ALL OF IT, and
saying otherwise is what let the tree drift for months: this script produced 128
files where the tree held 163, and nothing measured the difference, so the claim
in the old first line went on being false and unread.

THREE of those files are HAND-MADE -- a panel view, its palette, and a curve
composite. They are listed in KEPT below, they have no generator, and they are
somebody's work. `--audit` is what keeps that honest: it regenerates into a
temporary directory and reports every difference between the tree and this
script, classified, so a NEW extra file is a finding rather than sediment.

IT SAID TWENTY-EIGHT UNTIL 1 Sep 2026, and twenty-five of those were wrong. One
was a mis-carve of the 5x5 font that docs/15 had already identified and this
table went on calling unidentified. The other twenty-four -- part 002's four
solid models and five projections of each -- were labelled "rendered by hand"
when in fact tools/vecobj.py had rendered them until it was archived as spent.
Nothing regenerated them after that, so nothing compared them either, and every
one of the twenty projections was drawn from a face index that was off by one.
See carve_solid_models() and the note above KEPT. The pattern to take from it:
"nothing generates this" is a claim, and an unexamined one decays into cover for
a tool somebody deleted.

    python tools/build_assets.py            write the derived files
    python tools/build_assets.py --audit    report tree against generator

Two sources:
  * NEUROSIS.DAT, sliced with the region map recovered from the Seek/BlockRead
    constants (see docs/04-neurosis-dat.md). The map tiles the file exactly.
  * DGROUP of individual parts, for data compiled into the executable rather
    than shipped in the blob -- part 003's 3-D shapes, for instance.

Screens (64000 bytes) and palettes (768) are paired into PNGs where possible;
everything else is written as raw .bin so nothing is lost.
"""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from datmap import RECORDS
from datcarve import png_indexed
# mzinfo is the kit's now (#50). These scripts are the record's, or are
# waiting their turn to move, and they keep working meanwhile -- which is
# the standing rule: the originals go on working until their successor has
# landed AND every caller has been repointed.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] /
                      "kit" / "tools"))
from substrate.mzinfo import parse

DAT = Path("bin/NEUROSIS.DAT")
OUT = Path("assets")
PALETTE, SCREEN = 768, 64000

# Human names for reads we have identified. Key: (seek, index within the region).
NAMES = {
    (0x000000, 0): "LOGOPAL",
    (0x000000, 1): "ASPHLOGO",
    (0x00FD00, 0): "INTROPAL",
    (0x00FD00, 1): "COMETFRM",
    (0x00FD00, 2): "INTROBAK",
    (0x00FD00, 3): "TITLEFNT",   # the 15,104-byte font ShowWord draws with
    (0x02AEE0, 0): "INTROSCR",
    (0x03A8E0, 0): "BALLFONT",   # scene 4's own font, TFont, 3,776 bytes
    (0x03A8E0, 1): "BALLSPAL",   # the ball scene palette
    (0x03A8E0, 2): "PROFILEA",   # ProfileA, one 7x7 ball sprite
    (0x03A8E0, 3): "PROFILEB",   # ProfileB, the other 7x7 ball sprite
    (0x03BB02, 0): "OBJMETA",   # ObjMeta, 52 bytes of vector object metadata
    (0x03BB02, 1): "VECTORPL",   # the vector scene palette
    (0x03BE36, 0): "HOUSEPAL",
    (0x03BE36, 1): "HOUSEPL0",
    (0x03BE36, 2): "HOUSEPL1",
    (0x03BE36, 3): "HOUSEPL2",
    (0x03BE36, 4): "HOUSEPL3",
    (0x03BE36, 5): "GARAGE",
    (0x07D9B2, 0): "BANNSTRP",
    (0x07D9B2, 1): "FONT5X5",
    (0x07D9B2, 2): "OBJSPAL",
    (0x07D9B2, 3): "REWIND",
    (0x081A76, 0): "TUNNPLN0",
    (0x081A76, 1): "TUNNPLN1",
    (0x081A76, 2): "TUNNPLN2",
    (0x081A76, 3): "TUNNPLN3",
    (0x0C0276, 0): "STARSWPT",
    (0x0C0E2E, 0): "S4PAL",
    (0x0C0E2E, 1): "GLOBESRC",
    (0x0C0E2E, 2): "GLOBEDST",
    (0x0D7882, 0): "S4SCRN1",
    (0x0E7282, 0): "S4SCRN2",
    (0x0F6C82, 0): "S4SCRN3",
    (0x106682, 0): "S4SCRN4",
    (0x116082, 0): "WAVECURV",
    (0x11EEC0, 0): "FONT5X5",
    (0x11EEC0, 1): "SPRITE1",
    (0x11EEC0, 2): "SPRITE2",
    (0x11EEC0, 3): "SPRITE3",
    (0x11EEC0, 4): "SPRITE4",
    (0x11EEC0, 5): "SPRTSPAL",
    (0x1228CE, 0): "LEMFONT",   # Font^, TFont
    (0x1228CE, 1): "TITLEPAL",   # Pal, set before the title screen
    (0x1228CE, 2): "TITLESCR",   # VirtScr^, 64,000 -- the title screen
    (0x1228CE, 3): "HILLSIDE",   # VirtScr^, 64,000 -- the hillside
    (0x1228CE, 4): "HILLPAL",   # Pal, set after the hillside
    (0x1228CE, 5): "SCENEPAL",   # ScenePal, DS:$CC07
    (0x1228CE, 6): "WALKBANK",   # WalkBank, 8 x 54
    (0x1228CE, 7): "TUMBLEBK",   # TumbleBk, 4 x 100
    (0x1228CE, 8): "SPLATBNK",   # SplatBank, 4 x 120
    (0x1228CE, 9): "DIGBANK",   # DigBank, 6 x 221
    (0x1228CE, 10): "TUNNELBK",   # TunnelBk, 3 x 140
    (0x1228CE, 11): "DEATHBBK",   # DeathBBk, 5 x 160
    (0x1228CE, 12): "HILLANIM",   # HillAnim, 3 x 1032
    (0x1228CE, 13): "DEATHABK",   # DeathABk, 6 x 108
    (0x1228CE, 14): "BUILDBNK",   # BuildBank, 6 x 120
    (0x1228CE, 15): "DEATHAPC",   # DeathAPic, 60 x 53, the storm
    (0x1228CE, 16): "INTROANM",   # IntroAnim, 7 x 1560
    (0x1228CE, 17): "SIDEANIM",   # SideAnim, 6 x 140
    (0x1228CE, 18): "EXPLOSN",   # Explosion, 7 x 3465
    (0x1228CE, 19): "FUSEBANK",   # FuseBank, the last read of the region
    (0x153DE5, 0): "HEIGHT1",   # the first 32x32 height map, morphed to at 100e:0823
    (0x153DE5, 1): "HEIGHT2",   # the second, morphed to at 100e:0840
    (0x153DE5, 2): "HEIGHT3",   # the third, morphed to at 100e:085d
    (0x1549E5, 0): "P5PAL",
    (0x1549E5, 1): "P5SCREEN",
    (0x1646E5, 0): "PATCHPIC",   # Pic^, the picture the 30x30 patch is lifted out of
    (0x1646E5, 1): "PATCHPAL",   # its palette
    (0x1743E5, 0): "WHOOSHFN",   # the whooshtext's font, 15,104 bytes
    (0x1743E5, 1): "WHOOSHPL",   # its palette
    (0x1781E5, 0): "CMAP2",   # colour map 2, "p5.cel" -- one 256-byte TCel
    (0x1781E5, 1): "CMAP1",   # colour map 1, "p8.cel"
    (0x1781E5, 2): "TILESPAL",   # the tile palette, written to the DAC entry by entry
    (0x1781E5, 3): "TILEANIM",   # Anim^, 72 frames of a 25x25 animation
    (0x1836AD, 0): "FIREPIC",   # Pic^, the picture that burns in front of the fire
    (0x1836AD, 1): "FIRETITL",   # TitleB, the 30x7 title bitmap that slides in
    (0x1836AD, 2): "FIREPAL",   # the full DAC, all 256 entries at 1118:00aa
    (0x1836AD, 3): "FIREPAL2",   # read again for entries $EE..$FF only, 1118:0105
    (0x1836AD, 4): "FIREPAL3",   # and again for $E1..$ED only, 1118:0160
    (0x18B23F, 0): "MARGIN",   # Margin, 180 bytes, the scroller edge table
    (0x18B23F, 1): "CREDFONT",   # the credits font -- 23,436 bytes, part 004's size
    (0x18B23F, 2): "CREDPAL",   # its palette
    (0x19117F, 0): "LEMEND",
    (0x1A047D, 0): "BLKORDER",
}

# HAND-MADE FILES WITH NO GENERATOR, kept deliberately. Every one arrived in the
# first commit and nothing in this script produces it. Listed so that --audit can
# tell "somebody's work" from "sediment left by a rename": an extra file that is
# NOT here is a finding, and one that is here is a decision.
#
# If any of these is ever reproduced by code, delete its row -- a name on this
# list is a statement that nothing generates it.
KEPT = {
    "part002/S2PANEL.PAL":  "the palette the panel view below is rendered with",
    "part002/S2PANEL.PNG":  "the banner strip rendered with S2PANEL.PAL",
    "part003/WAVECRVA.PNG": "all of the waves curves in one composite",
}
# TWO ENTRIES LEFT THIS TABLE, AND NEITHER WAS SOMEBODY'S WORK.
#
# `part002/DEAD1550.BIN` was carried here as "1,550 bytes, unidentified. The size
# matches the 5x5 font, so it may be an earlier carve of it." The guess was
# right, and one comparison settles it: the file is NEUROSIS.DAT at $080CB2 and
# the font is the same 1,550 bytes at $080BB2 -- 256 bytes earlier. So
# DEAD1550[0:1294] == FONT5X5[256:1550] exactly, and the 256 bytes it ran off the
# end are all zero. It held no byte the font does not, 256 is not a multiple of
# the 25-byte glyph, and that is why it looked like meaningless soup. docs/15 had
# already worked this out and said the file "should be ignored"; nothing acted on
# it, so the KEPT row went on describing it as unidentified. Deleted.
#
# `part002/OBJ*` -- the four models and their twenty projections -- were declared
# "rendered by hand". They were not: tools/vecobj.py made them, and when that was
# archived under #29 they became files with no producer. carve_solid_models()
# above generates them now, and it found the bug that six months of no generator
# had hidden. See its docstring.
#
# The lesson, and it is the same one this table exists for: a KEPT row is a claim
# that nothing generates a file, and the reason it needs to be read as a claim is
# that both of these were false in the direction that costs something -- one file
# that was fully explained elsewhere in the repository, and twenty-four that had
# a generator until somebody deleted it.

# Files that are inputs to the build rather than outputs of this script.
NOT_ASSETS = ("NEUROSIS.MAN", "README.md")

# THE MUSIC. Each shipped part is an executable with a ProTracker module
# APPENDED PAST ITS LOAD IMAGE -- the MZ header's own arithmetic says so, and
# mzinfo reports it as overlay_bytes. So the modules are derived from bin/ like
# everything else here, not loose files somebody has to keep.
#
# The names are the modules' OWN titles, read out of the 20 bytes at offset 0 of
# each one, shortened to 8.3. Parts 004 and 007 SHARE a module: "The Deth March"
# is byte-identical in both, 58,967 bytes, so it appears in both folders.
# part -> (8.3 stem, the title in the file)
MUSIC = {
    "001": ("INAWE",    "In awe of you."),
    "002": ("STARTREK", "StarTrek Samples"),
    "003": ("TECHTICK", "Techno Tick"),
    "004": ("DETHMRCH", "The Deth March"),
    "005": ("NEUROTIC", "Neurotic Interlude"),
    "006": ("LATEXLVR", "LaTeX LoVeR"),
    "007": ("DETHMRCH", "The Deth March"),
}

# Regions whose extension is not .BIN. Keyed like NAMES, so a rename cannot
# reach it. (seek, index) -> extension
EXTS = {
    (0x19117F, 0): ".FLC",      # an Autodesk FLIC animation, played by part 007
}

# Data compiled into an executable rather than stored in the blob.
# (part, dgroup segment, offset, count, stride, name)
EMBEDDED = [
    ("001", 0x18F8, 0x01A8, 36, 6, "VECGLOBE"),
    ("001", 0x18F8, 0x001C, 48, 6, "VECLOGOA"),
    ("003", 0x1761, 0x0636, 765, 6, "SHPSPHER"),
    ("003", 0x1761, 0x5136, 765, 6, "SHPCUBE"),
    ("003", 0x1761, 0x63F6, 765, 6, "SHPGRID"),
]

# Part 002's four solid models: a vertex array of signed word triples followed
# by a variable-length face stream. Unlike EMBEDDED above these have topology,
# so they get a wireframe from five axis pairs rather than a point cloud.
#
# The BIN name and the PNG prefix differ because both have to be 8.3 and the
# five view suffixes are two characters: OBJENTER.BIN, but OBJENTTP.PNG.
#
# THE INDEX BIAS IS PER MODEL, and it is the whole reason this table exists
# rather than a loop. The Enterprise's face indices are stored zero-based and
# the other three models' are stored one-based, in the same face stream format,
# in the same segment. The authority is P2SOLID.PAS's own loader, which part 002
# rebuilds BYTE-IDENTICAL from:
#
#     Obj[1].Face[I].Idx[K] := FaceEnterprise[P] + 1;      <- the Enterprise
#     Obj[2].Face[I].Idx[K] := FaceRevolver[P];            <- and the other
#     Obj[3].Face[I].Idx[K] := FaceSailboat[P];               three, verbatim
#     Obj[4].Face[I].Idx[K] := FaceQuad[P];
#
# So "indices are stored zero-based and incremented on load" -- what vecobj.py's
# docstring said, and what the generated P2OBJ.INC and docs/15 both repeated --
# is true of ONE model out of four. vecobj.py applied the +1 to all four, which
# is why the Enterprise came out clean and became the picture docs/15 links to,
# while the revolver and the sailboat were a cross-hatch nobody could read and
# the quad drew a triangle. A rule inferred from the model that happened to be
# looked at first, applied to three that were not.
# (part, seg, vert off, verts, face off, faces, bias, BIN name, PNG prefix, best)
SOLID_MODELS = [
    ("002", 0x1866, 0x0004, 75, 0x01C6, 55, 1, "OBJENTER", "OBJENT", "TP"),
    ("002", 0x1866, 0x067E, 68, 0x0816, 64, 0, "OBJREVLV", "OBJREV", "LG"),
    ("002", 0x1866, 0x0B06, 32, 0x0BC6, 21, 0, "OBJSAIL",  "OBJSAI", "L2"),
    ("002", 0x1866, 0x0CAE,  4, 0x0CC6,  1, 0, "OBJQUAD",  "OBJQUA", "TP"),
]

# A model is often unrecognisable from the obvious X/Y view: the Enterprise only
# reads from above, and the revolver and the sailboat are both modelled along Y,
# so they only read once Y is horizontal. Tag -> (across axis, down axis).
SOLID_VIEWS = {
    "TP": (0, 2),      # top    -- X across, Z down
    "SD": (2, 1),      # side   -- Z across, Y down
    "FR": (0, 1),      # front  -- X across, Y down
    "LG": (1, 0),      # long   -- Y across, X down
    "L2": (1, 2),      # long2  -- Y across, Z down
}

# Where the NEXT model's vertices start, so the face stream's length can be
# compared against the room it has. The revolver and the sailboat each leave 10
# bytes their face count never reads -- one more well-formed 3-vertex face
# apiece. That is not a miscount: P2SOLID.PAS writes both counts as IMMEDIATES
# and part 002 rebuilds byte-identical, so 64 and 21 are the original's own
# numbers and the trailing face is data the 1994 code does not draw either.
SOLID_NEXT = {"OBJENTER": 0x067E, "OBJREVLV": 0x0B06, "OBJSAIL": 0x0CAE,
              "OBJQUAD": None}

W_OBJ, H_OBJ = 320, 200

# Screens whose palette is loaded by a different region than their own. A
# carried-forward palette is a guess; these are known. Scene 4's four screens
# all fade to one palette loaded once at the start of the scene.
# Key: (part, screen asset name) -> palette asset name.
PALETTE_OVERRIDES = {
    ("003", "S4SCRN1"): "S4PAL",
    ("003", "S4SCRN2"): "S4PAL",
    ("003", "S4SCRN3"): "S4PAL",
    ("003", "S4SCRN4"): "S4PAL",
}

# Mode-X plane sets: four 64000-byte planes that are really one wide image.
# A per-plane PNG is actively misleading -- reading a plane at 320 wide shows
# a phantom second centre -- so those are suppressed and a de-interleaved
# composite is written instead.
PLANE_SETS = [
    ("002", ["HOUSEPL0", "HOUSEPL1", "HOUSEPL2", "HOUSEPL3"],
     "PANORAMA", 1280, 200, "HOUSEPAL"),
    ("003", ["TUNNPLN0", "TUNNPLN1", "TUNNPLN2", "TUNNPLN3"],
     "TUNNEL", 640, 400, "TUNNELPL"),
]

# Pairs of 16-bit offset tables that drive a precomputed scatter blit:
# for each entry, copy one byte from src[i] in the source buffer to dst[i] in
# video memory. The two PNG names are given EXPLICITLY rather than composed from
# a prefix: `globe_warp` plus `_src` was fifteen characters, and every name in
# this tree has to be 8.3 because MKDAT.PAS reads them under real-mode DOS.
# (part, src asset, dst asset, src PNG, dst PNG)
OFFSET_TABLES = [
    ("003", "GLOBESRC", "GLOBEDST", "GLBWRPSR", "GLBWRPDS"),
]

# Square sprites carved as raw .bin by the region pass; render them at their
# real dimensions with the palette from the same region.
# (part, [asset names], width, height, palette asset)
SPRITE_SETS = [
    ("003", ["SPRITE1", "SPRITE2", "SPRITE3", "SPRITE4"], 56, 56, "SPRTSPAL"),
]

# One .bin holding N frames back to back; split and render each.
# (part, source asset, count, width, height, palette asset, name prefix)
SPRITE_STRIPS = [
    # THE PREFIX IS UPPERCASE, like every other name here. It was "comet"
    # while the files were comet0.png, and the 8.3 rename moved the FILES
    # to COMET0.PNG without moving this -- so a regeneration wrote ten
    # lowercase-stemmed duplicates beside them, invisibly on a
    # case-insensitive filesystem.
    ("001", "COMETFRM", 10, 65, 48, "INTROPAL", "COMET"),
]

# Bitmaps stored with a 2-byte (width, height) header. In part 002 the header
# bytes are zero in the file and the code writes 146/85 into them after load,
# so the dimensions have to come from the code, not the data.
# (part, asset, skip, width, height, palette, name)
HEADERED_BITMAPS = [
    ("002", "GARAGE",  2, 146, 85, "HOUSEPAL",   "GARAGE"),
    ("002", "BANNSTRP", 0, 320, 40, "OBJSPAL", "BANNER"),
    ("002", "REWIND", 0,  34, 43, "OBJSPAL", "REWIND"),
]

# Palettes compiled into a part's DGROUP rather than shipped in the blob.
# Borland keeps R, G and B as three separate tables, not interleaved triples.
# (part, dgroup seg, R off, G off, B off, count, first DAC index, name)
EMBEDDED_PALETTES = [
    ("003", 0x1761, 0x0002, 0x00E3, 0x01C4, 225, 1, "TUNNELPL"),
]


def ramp_palette():
    return bytes(((i >> 2) & 63) for i in range(256) for _ in range(3))


def carve_music(manifest):
    """The appended ProTracker module of each shipped part.

    Nothing about this needs the region map: the MZ header says where the load
    image ends and everything past it is the module.
    """
    for part, (stem, title) in sorted(MUSIC.items()):
        src = Path("bin") / ("NEUROSIS.%s" % part)
        if not src.exists():
            continue
        mz = parse(src)
        # THE TAIL, BY LENGTH, NOT BY A COMPUTED START. hdrsize + imagesize
        # looked like the end of the load image and is not: it overshot part
        # 001 by exactly the 1,040-byte header and got parts 004 and 007 wrong
        # by different amounts, which is what says the arithmetic was invented
        # rather than read. mzinfo already reports overlay_bytes, so take that
        # many bytes off the end and let the field that was measured do the
        # work.
        raw = src.read_bytes()[-mz["overlay_bytes"]:] if mz["overlay_bytes"] else b""
        if not raw:
            continue
        d = OUT / ("part%s" % part)
        d.mkdir(parents=True, exist_ok=True)
        (d / ("%s.MOD" % stem)).write_bytes(raw)
        manifest.append((part, None, None, len(raw),
                         "part%s/%s.MOD" % (part, stem),
                         'ProTracker module "%s", appended past the load image'
                         % title))


def carve_dat(manifest):
    blob = DAT.read_bytes()
    last_pal = None
    for part, host, seek, sizes in sorted(RECORDS, key=lambda r: r[2]):
        d = OUT / f"part{part}"
        d.mkdir(parents=True, exist_ok=True)
        pos, pal = seek, None

        for i, sz in enumerate(sizes):
            data = blob[pos:pos + sz]
            # 8.3 THROUGHOUT: a real-mode DOS build tool cannot open a long name,
            # and MKDAT.PAS is the consumer. Six hex digits of offset plus
            # one index letter is seven characters and keeps both facts.
            name = NAMES.get((seek, i)) or f"{seek:06X}{chr(65 + i)}"

            if sz == PALETTE:
                pal = last_pal = data
                (d / f"{name}.PAL").write_bytes(data)
                manifest.append((part, seek, i, sz, f"part{part}/{name}.PAL", "VGA palette, 6-bit"))
            elif sz == SCREEN and (pal or last_pal):
                (d / f"{name}.RAW").write_bytes(data)
                if any(name in s[1] for s in PLANE_SETS):
                    manifest.append((part, seek, i, sz, f"part{part}/{name}.RAW",
                                     "Mode-X plane; see the composite below"))
                else:
                    ovr = PALETTE_OVERRIDES.get((part, name))
                    if ovr:
                        use, note = (d / f"{ovr}.PAL").read_bytes(), f"320x200 screen ({ovr})"
                    else:
                        use = pal or last_pal
                        note = "320x200 screen" + ("" if pal else " (palette carried forward)")
                    png_indexed(d / f"{name}.PNG", data, use)
                    manifest.append((part, seek, i, sz, f"part{part}/{name}.PNG", note))
            else:
                # AN EXPLICIT TABLE, not a name suffix. This used to read the
                # extension off a `_flc` suffix in the asset's own name, which
                # broke silently the moment every name became 8.3 -- the region
                # came out as LEMEND.BIN, a FLIC animation wearing .BIN. A
                # naming convention that carries meaning is a convention two
                # unrelated changes can break; a table cannot be broken by a
                # rename.
                ext = EXTS.get((seek, i), ".BIN")
                (d / f"{name}{ext}").write_bytes(data)
                manifest.append((part, seek, i, sz, f"part{part}/{name}{ext}", ""))
            pos += sz


def carve_embedded(manifest):
    for part, seg, off, count, stride, name in EMBEDDED:
        h = parse(Path(f"work/split/NEUROSIS_{part}.exe"))
        base = h["hdrsize"] + seg * 16 - 0x10000 + off
        raw = h["raw"][base:base + count * stride]
        d = OUT / f"part{part}"
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{name}.BIN").write_bytes(raw)

        # A quick orthographic-ish preview so the file is self-evidently right.
        W, H = 320, 400
        px = bytearray(W * H)
        for i in range(count):
            x, y, z = struct.unpack_from("<hhh", raw, i * stride)
            dd = 2500 - z
            if dd <= 0:
                continue
            sx, sy = (x * 256) // dd + 160, (y * 256) // dd + 200
            if 0 <= sx < W and 0 <= sy < H:
                px[sy * W + sx] = 255
        png_indexed(d / f"{name}.PNG", bytes(px), ramp_palette(), W, H)
        manifest.append((part, None, None, len(raw), f"part{part}/{name}.PNG",
                         f"embedded in DGROUP at DS:${off:04X}, {count} points x {stride}b"))


def obj_line(px, x0, y0, x1, y1, c):
    """Bresenham, clipped by test. The wireframe's only drawing primitive."""
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    while True:
        if 0 <= x0 < W_OBJ and 0 <= y0 < H_OBJ:
            px[y0 * W_OBJ + x0] = c
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x0 += sx
        if e2 < dx:
            err += dx
            y0 += sy


def parse_faces(raw, base, foff, nfaces, nverts, bias, name):
    """The face stream: for each face, `count, index1 .. indexN, colour`.

    `bias` is the per-model increment from P2SOLID.PAS's loader -- 1 for the
    Enterprise, 0 for the rest. See the note on SOLID_MODELS for why it is not
    one rule, and why assuming it was cost every projection but the Enterprise's.

    AN OUT-OF-RANGE INDEX REFUSES HERE, and that is the change that matters more
    than the bias itself. The old renderer filtered them -- `for i in idx if
    1 <= i <= nv` -- so a wrong bias drew a partial polygon instead of failing.
    The revolver had three faces silently reduced to triangles and the quad drew
    a triangle for its only face, and no run ever said anything. With the filter
    replaced by a refusal, getting this wrong is a stack trace rather than a
    picture nobody compares.

    BUT THE RANGE CHECK CATCHES ONLY TWO OF THE FOUR MODELS' BIAS ERRORS, and
    saying so is the point of writing it down. A wrong bias is only visible here
    when it pushes an index off the end, which needs the model's highest vertex
    to be used by some face: the revolver and the quad refuse, the Enterprise and
    the sailboat read perfectly in range with either bias. So this is a backstop,
    not the authority. The authority is P2SOLID.PAS's four loader lines, and the
    only way to check a bias is to read them.
    """
    faces, p = [], 0
    for f in range(nfaces):
        cnt = struct.unpack_from("<h", raw, base + foff + p * 2)[0]
        if not 3 <= cnt <= 8:
            raise SystemExit("  %s face %d has a vertex count of %d -- the face "
                             "stream has drifted" % (name, f, cnt))
        idx = [struct.unpack_from("<h", raw, base + foff + (p + 1 + k) * 2)[0]
               + bias for k in range(cnt)]
        bad = [i for i in idx if not 1 <= i <= nverts]
        if bad:
            raise SystemExit(
                "  %s face %d indexes vertex %s of %d, with bias %d -- the "
                "stream has drifted or the bias is wrong. P2SOLID.PAS's loader "
                "is what settles the bias." % (name, f, bad, nverts, bias))
        faces.append(idx)
        p += cnt + 2
    return faces, p


def carve_solid_models(manifest):
    """Part 002's four solid models, and five projections of each.

    WHY THESE ARE GENERATED AND WERE NOT. tools/vecobj.py made these files and
    was deleted under #29 as spent. Its disposition in docs/32 checked that
    build_assets.py reproduced part 001's vector_globe and vector_logo_a and
    concluded the tool was superseded -- but part 002's four models and their
    twenty projections had no producer here at all. They survived as files
    nothing generated, so --audit could only class them as somebody's work, and
    a KEPT row went in calling them "rendered by hand". They never were.

    The cost of that was not the wrong label. It was that the +1 bias above went
    unmeasured, because nothing regenerated the pictures to compare.

    The projection is orthographic and auto-scaled -- a preview for identifying
    a model, not what the demo draws, which is solid and depth-sorted.
    """
    for part, seg, voff, nv, foff, nf, bias, binname, pngpre, best in SOLID_MODELS:
        h = parse(Path(f"work/split/NEUROSIS_{part}.exe"))
        raw = h["raw"]
        base = h["hdrsize"] + seg * 16 - 0x10000

        pts = [struct.unpack_from("<hhh", raw, base + voff + i * 6)
               for i in range(nv)]
        faces, words = parse_faces(raw, base, foff, nf, nv, bias, binname)

        d = OUT / f"part{part}"
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{binname}.BIN").write_bytes(raw[base + voff:base + voff + nv * 6])

        for tag, (ai, bi) in SOLID_VIEWS.items():
            av = [q[ai] for q in pts]
            bv = [q[bi] for q in pts]
            # Scale from the axes that have an extent. A planar model viewed
            # edge-on has none on one axis -- obj_quad's Z is 0 throughout --
            # and that is a real projection, not a case to fudge.
            cand = [(W_OBJ - 20) / (max(av) - min(av)) for _ in (0,)
                    if max(av) > min(av)]
            cand += [(H_OBJ - 20) / (max(bv) - min(bv)) for _ in (0,)
                     if max(bv) > min(bv)]
            sc = min(cand) if cand else 1.0
            ca, cb = (max(av) + min(av)) / 2, (max(bv) + min(bv)) / 2
            px = bytearray(W_OBJ * H_OBJ)
            for idx in faces:
                poly = [(int((pts[i - 1][ai] - ca) * sc) + W_OBJ // 2,
                         int((pts[i - 1][bi] - cb) * sc) + H_OBJ // 2)
                        for i in idx]
                for k in range(len(poly)):
                    a, b = poly[k], poly[(k + 1) % len(poly)]
                    obj_line(px, a[0], a[1], b[0], b[1], 200)
            png_indexed(d / f"{pngpre}{tag}.PNG", bytes(px), ramp_palette(),
                        W_OBJ, H_OBJ)

        sizes = sorted({len(f) for f in faces})
        trailing = ""
        if SOLID_NEXT.get(binname) is not None:
            over = (SOLID_NEXT[binname] - foff) - words * 2
            if over:
                trailing = (", %d trailing byte(s) the count never reads"
                            % over)
        manifest.append((part, None, None, nv * 6, f"part{part}/{binname}.BIN",
                         f"DGROUP DS:${voff:04X}, {nv} vertices x 6b"))
        for tag in SOLID_VIEWS:
            png = d / f"{pngpre}{tag}.PNG"
            manifest.append((part, None, None, png.stat().st_size,
                             f"part{part}/{pngpre}{tag}.PNG",
                             f"{nf} faces, sizes {sizes}"
                             f"{', the view that identifies it' if tag == best else ''}"
                             f"{trailing if tag == best else ''}"))


def carve_embedded_palettes(manifest):
    """Rebuild a 768-byte DAC image from a part's three separate R/G/B tables."""
    for part, seg, ro, go, bo, count, first, name in EMBEDDED_PALETTES:
        h = parse(Path(f"work/split/NEUROSIS_{part}.exe"))
        base = h["hdrsize"] + seg * 16 - 0x10000
        R = h["raw"][base + ro:base + ro + count]
        G = h["raw"][base + go:base + go + count]
        B = h["raw"][base + bo:base + bo + count]

        pal = bytearray(768)
        for i in range(count):
            j = (first + i) * 3
            pal[j], pal[j + 1], pal[j + 2] = R[i], G[i], B[i]

        d = OUT / f"part{part}"
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{name}.PAL").write_bytes(bytes(pal))
        manifest.append((part, None, None, 768, f"part{part}/{name}.PAL",
                         f"embedded: R DS:${ro:04X} G DS:${go:04X} B DS:${bo:04X}, "
                         f"{count} entries from index {first}"))


def build_composites(manifest):
    """De-interleave Mode-X plane sets into the image they actually represent."""
    # The de-interleaver is the kit's now -- it says nothing about Pascal and
    # nothing about this demo, so it moved to substrate under #50. This script
    # stays with the record because its region map is this target's.
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "kit" / "tools"))
    from substrate.modex import deinterleave
    for part, planes, name, w, h, palname in PLANE_SETS:
        d = OUT / f"part{part}"
        data = [(d / f"{p}.RAW").read_bytes() for p in planes]
        px = deinterleave(data, w, h)
        palfile = d / f"{palname}.PAL"
        pal = palfile.read_bytes() if palfile.exists() else ramp_palette()
        png_indexed(d / f"{name}.PNG", px, pal, w, h)
        manifest.append((part, None, None, w * h, f"part{part}/{name}.PNG",
                         f"{w}x{h} de-interleaved from {len(planes)} Mode-X planes"))


def visualise_offset_tables(manifest):
    """Render where a scatter blit reads from and writes to, as coverage maps."""
    for part, srcname, dstname, srcpng, dstpng in OFFSET_TABLES:
        d = OUT / f"part{part}"
        names = {"src": srcpng, "dst": dstpng}
        for tag, asset in (("src", srcname), ("dst", dstname)):
            tab = (d / f"{asset}.BIN").read_bytes()
            n = len(tab) // 2
            px = bytearray(64000)
            hits = 0
            for i in range(1, n):               # the blit starts at index 1
                o = struct.unpack_from("<H", tab, i * 2)[0]
                if o < 64000:
                    if not px[o]:
                        hits += 1
                    px[o] = 40 + (i * 200) // n
            png_indexed(d / f"{names[tag]}.PNG", bytes(px), ramp_palette())
            manifest.append((part, None, None, len(tab), f"part{part}/{names[tag]}.PNG",
                             f"{tag} coverage of the scatter blit, {hits:,} distinct pixels"))


def render_sprites(manifest):
    for part, names, w, h, palname in SPRITE_SETS:
        d = OUT / f"part{part}"
        pal = (d / f"{palname}.PAL").read_bytes()
        for name in names:
            data = (d / f"{name}.BIN").read_bytes()
            png_indexed(d / f"{name}.PNG", data[:w * h], pal, w, h)
            manifest.append((part, None, None, len(data), f"part{part}/{name}.PNG",
                             f"{w}x{h} sprite"))


def render_headered(manifest):
    for part, src, skip, w, h, palname, name in HEADERED_BITMAPS:
        d = OUT / f"part{part}"
        pal = (d / f"{palname}.PAL").read_bytes()
        data = (d / f"{src}.BIN").read_bytes()[skip:skip + w * h]
        png_indexed(d / f"{name}.PNG", data, pal, w, h)
        manifest.append((part, None, None, len(data), f"part{part}/{name}.PNG",
                         f"{w}x{h}, dimensions from code not header"))


def split_strips(manifest):
    for part, src, count, w, h, palname, prefix in SPRITE_STRIPS:
        d = OUT / f"part{part}"
        pal = (d / f"{palname}.PAL").read_bytes()
        data = (d / f"{src}.BIN").read_bytes()
        for i in range(count):
            frame = data[i * w * h:(i + 1) * w * h]
            png_indexed(d / f"{prefix}{i}.PNG", frame, pal, w, h)
            manifest.append((part, None, None, len(frame),
                             f"part{part}/{prefix}{i}.PNG", f"{w}x{h} frame {i}"))


def audit():
    """Report the tree against this script, classified. The check that was missing.

    Regenerates into a temporary directory rather than over the top, so nothing
    is at risk, and sorts every difference into one of four kinds. Only two of
    them are findings -- which is the point: a report where everything is a
    finding gets skimmed, and this drifted for months behind exactly that.
    """
    import hashlib
    import shutil
    import tempfile

    global OUT
    real = OUT
    tmp = Path(tempfile.mkdtemp())
    try:
        OUT = tmp
        main(write_readme=False)
    finally:
        OUT = real

    def index(root):
        return {p.relative_to(root).as_posix():
                hashlib.sha256(p.read_bytes()).hexdigest()
                for p in root.rglob("*") if p.is_file()
                and p.name not in NOT_ASSETS}

    tree, gen = index(real), index(tmp)
    by_hash = {}
    for k, v in gen.items():
        by_hash.setdefault(v, k)

    missing = sorted(set(gen) - set(tree))
    wrong = sorted(k for k in set(gen) & set(tree) if gen[k] != tree[k])
    extra = sorted(set(tree) - set(gen))
    dupes = [(k, by_hash[tree[k]]) for k in extra if tree[k] in by_hash]
    kept = [k for k in extra if k in KEPT and tree[k] not in by_hash]
    stray = [k for k in extra if k not in KEPT and tree[k] not in by_hash]
    shutil.rmtree(tmp, ignore_errors=True)

    print("%d file(s) in assets/, %d produced by this script"
          % (len(tree), len(gen)))
    print("  %d hand-made and declared in KEPT" % len(kept))
    bad = 0
    if missing:
        bad += len(missing)
        print("\n  MISSING -- this script writes these and the tree has not got")
        print("  them, so the tree was never regenerated after a change:")
        for k in missing:
            print("     ", k)
    if wrong:
        bad += len(wrong)
        print("\n  CONTENT DIFFERS -- same name, different bytes. Either the tree")
        print("  was edited by hand or a generator changed under it:")
        for k in wrong:
            print("     ", k)
    if dupes:
        bad += len(dupes)
        print("\n  DUPLICATE -- extra file whose bytes already exist under a")
        print("  generated name. Sediment, usually from a rename. Safe to delete:")
        for k, w in dupes:
            print("      %-28s == %s" % (k, w))
    if stray:
        bad += len(stray)
        print("\n  UNDECLARED -- unique content that nothing generates and KEPT")
        print("  does not mention. Either it is somebody's work, in which case add")
        print("  a KEPT row saying what it is, or it is sediment. DO NOT GUESS:")
        for k in stray:
            print("     ", k)
    if not bad:
        print("\n  the tree and this script agree, and every extra file is declared")
    return 1 if bad else 0


def main(write_readme=True):
    OUT.mkdir(exist_ok=True)
    manifest = []
    carve_dat(manifest)
    carve_music(manifest)
    render_headered(manifest)
    render_sprites(manifest)
    split_strips(manifest)
    carve_embedded_palettes(manifest)   # must precede composites -- they use it
    build_composites(manifest)
    visualise_offset_tables(manifest)
    carve_embedded(manifest)
    carve_solid_models(manifest)

    lines = [
        "# Extracted assets",
        "",
        "Generated by `tools/build_assets.py`, except for the files listed at",
        "the bottom. **Deleting the whole directory loses those**, because",
        "nothing reproduces them -- run `--audit` before deleting anything.",
        "",
        "Sources: `bin/NEUROSIS.DAT` sliced with the recovered region map, plus",
        "data compiled into the executables' DGROUP. See",
        "`docs/04-neurosis-dat.md` for how the map was recovered.",
        "",
        "| Part | DAT offset | # | Bytes | File | Notes |",
        "|---|---|---|---:|---|---|",
    ]
    for part, seek, idx, size, path, note in manifest:
        off = f"`${seek:06X}`" if seek is not None else "(embedded)"
        n = "" if idx is None else str(idx)
        lines.append(f"| {part} | {off} | {n} | {size:,} | `{path}` | {note} |")
    lines += [
        "",
        "## Hand-made, with no generator",
        "",
        "These arrived in the first commit and nothing in `build_assets.py`",
        "produces them. They are listed in its `KEPT` table so `--audit` can",
        "tell somebody's work from sediment left behind by a rename.",
        "",
        "| File | What it is |",
        "|---|---|",
    ]
    for k in sorted(KEPT):
        lines.append(f"| `{k}` | {KEPT[k]} |")
    if not write_readme:
        return
    (OUT / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8",
                                   newline="\n")

    print(f"wrote {len(manifest)} assets to {OUT}/")


if __name__ == "__main__":
    if "--audit" in sys.argv:
        sys.exit(audit())
    main()
