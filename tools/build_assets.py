"""Build the clean asset tree in assets/ from NEUROSIS.DAT and from DGROUP.

MOST of assets/ is derived and can be rebuilt at any time. NOT ALL OF IT, and
saying otherwise is what let the tree drift for months: this script produced 128
files where the tree held 163, and nothing measured the difference, so the claim
in the old first line went on being false and unread.

Twenty-eight of those files are HAND-MADE -- five projections of each of part
002's four 3-D models, a panel view and its palette, a curve composite, and one
1,550-byte block nobody has identified. They are listed in KEPT below, they have
no generator, and they are somebody's work. `--audit` is what keeps that honest:
it regenerates into a temporary directory and reports every difference between
the tree and this script, classified, so a NEW extra file is a finding rather
than sediment.

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
    "part002/DEAD1550.BIN": "1,550 bytes, unidentified. The size matches the "
                            "5x5 font, so it may be an earlier carve of it.",
    "part002/OBJENTER.BIN": "part 002's Enterprise model, extracted from DGROUP",
    "part002/OBJQUAD.BIN":  "the quad model",
    "part002/OBJREVLV.BIN": "the revolver model",
    "part002/OBJSAIL.BIN":  "the sailboat model",
    "part002/S2PANEL.PAL":  "the palette the panel view below is rendered with",
    "part002/S2PANEL.PNG":  "the banner strip rendered with S2PANEL.PAL",
    "part003/WAVECRVA.PNG": "all of the waves curves in one composite",
}
# Five projections of each model, rendered by hand: front, long, long2, side, top.
for _m in ("OBJENT", "OBJQUA", "OBJREV", "OBJSAI"):
    for _v in ("FR", "LG", "L2", "SD", "TP"):
        KEPT["part002/%s%s.PNG" % (_m, _v)] = "a projection of the model above"

# Files that are inputs to the build rather than outputs of this script.
NOT_ASSETS = ("NEUROSIS.MAN", "README.md")

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
    render_headered(manifest)
    render_sprites(manifest)
    split_strips(manifest)
    carve_embedded_palettes(manifest)   # must precede composites -- they use it
    build_composites(manifest)
    visualise_offset_tables(manifest)
    carve_embedded(manifest)

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
