"""Build the clean asset tree in assets/ from NEUROSIS.DAT and from DGROUP.

Everything here is derived -- assets/ can be deleted and rebuilt at any time.

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
    (0x00FD00, 3): "00FD00D",
    (0x02AEE0, 0): "INTROSCR",
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
    (0x1A047D, 0): "BLKORDER",
    (0x1228CE, 1): "LEMSPAL",
    (0x1228CE, 2): "LEMSPR1",
    (0x1228CE, 3): "LEMSPR2",
    (0x1549E5, 0): "P5PAL",
    (0x1549E5, 1): "P5SCREEN",
    (0x19117F, 0): "LEMEND",
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
    ("001", "COMETFRM", 10, 65, 48, "INTROPAL", "comet"),
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


def main():
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
        "Generated by `tools/build_assets.py`. Safe to delete and rebuild.",
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
    (OUT / "README.md").write_text("\n".join(lines) + "\n", encoding="utf-8",
                                   newline="\n")

    print(f"wrote {len(manifest)} assets to {OUT}/")


if __name__ == "__main__":
    main()
