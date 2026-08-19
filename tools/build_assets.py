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
from mzinfo import parse

DAT = Path("bin/NEUROSIS.DAT")
OUT = Path("assets")
PALETTE, SCREEN = 768, 64000

# Human names for reads we have identified. Key: (seek, index within the region).
NAMES = {
    (0x000000, 0): "logo_palette",
    (0x000000, 1): "asphyxia_logo",
    (0x00FD00, 0): "intro_palette",
    (0x00FD00, 1): "comet_frames",
    (0x00FD00, 2): "intro_backdrop",
    (0x00FD00, 3): "00FD00_03",
    (0x02AEE0, 0): "intro_screen",
    (0x03BE36, 0): "house_palette",
    (0x03BE36, 1): "house_plane0",
    (0x03BE36, 2): "house_plane1",
    (0x03BE36, 3): "house_plane2",
    (0x03BE36, 4): "house_plane3",
    (0x03BE36, 5): "garage_door",
    (0x07D9B2, 0): "banner_strip",
    (0x07D9B2, 1): "font_5x5",
    (0x07D9B2, 2): "objects_palette",
    (0x07D9B2, 3): "rewind_button",
    (0x081A76, 0): "tunnel_plane0",
    (0x081A76, 1): "tunnel_plane1",
    (0x081A76, 2): "tunnel_plane2",
    (0x081A76, 3): "tunnel_plane3",
    (0x0C0276, 0): "stars_waypoints",
    (0x0C0E2E, 0): "scene4_palette",
    (0x0C0E2E, 1): "globe_src_offsets",
    (0x0C0E2E, 2): "globe_dst_offsets",
    (0x0D7882, 0): "scene4_screen1",
    (0x0E7282, 0): "scene4_screen2",
    (0x0F6C82, 0): "scene4_screen3",
    (0x106682, 0): "scene4_screen4",
    (0x116082, 0): "waves_curves",
    (0x11EEC0, 0): "font_5x5",
    (0x11EEC0, 1): "sprite1",
    (0x11EEC0, 2): "sprite2",
    (0x11EEC0, 3): "sprite3",
    (0x11EEC0, 4): "sprite4",
    (0x11EEC0, 5): "sprites_palette",
    (0x1A047D, 0): "blocks_order",
    (0x1228CE, 1): "lemmings_palette",
    (0x1228CE, 2): "lemming_sprite1",
    (0x1228CE, 3): "lemming_sprite2",
    (0x1549E5, 0): "part5_palette",
    (0x1549E5, 1): "part5_screen",
    (0x19117F, 0): "lemend_flc",
}

# Data compiled into an executable rather than stored in the blob.
# (part, dgroup segment, offset, count, stride, name)
EMBEDDED = [
    ("001", 0x18F8, 0x01A8, 36, 6, "vector_globe"),
    ("001", 0x18F8, 0x001C, 48, 6, "vector_logo_a"),
    ("003", 0x1761, 0x0636, 765, 6, "shape_sphere"),
    ("003", 0x1761, 0x5136, 765, 6, "shape_cube"),
    ("003", 0x1761, 0x63F6, 765, 6, "shape_grid"),
]

# Screens whose palette is loaded by a different region than their own. A
# carried-forward palette is a guess; these are known. Scene 4's four screens
# all fade to one palette loaded once at the start of the scene.
# Key: (part, screen asset name) -> palette asset name.
PALETTE_OVERRIDES = {
    ("003", "scene4_screen1"): "scene4_palette",
    ("003", "scene4_screen2"): "scene4_palette",
    ("003", "scene4_screen3"): "scene4_palette",
    ("003", "scene4_screen4"): "scene4_palette",
}

# Mode-X plane sets: four 64000-byte planes that are really one wide image.
# A per-plane PNG is actively misleading -- reading a plane at 320 wide shows
# a phantom second centre -- so those are suppressed and a de-interleaved
# composite is written instead.
PLANE_SETS = [
    ("002", ["house_plane0", "house_plane1", "house_plane2", "house_plane3"],
     "panorama_1280x200", 1280, 200, "house_palette"),
    ("003", ["tunnel_plane0", "tunnel_plane1", "tunnel_plane2", "tunnel_plane3"],
     "tunnel_640x400", 640, 400, "tunnel_palette"),
]

# Pairs of 16-bit offset tables that drive a precomputed scatter blit:
# for each entry, copy one byte from src[i] in the source buffer to dst[i] in
# video memory. (part, src asset, dst asset, name)
OFFSET_TABLES = [
    ("003", "globe_src_offsets", "globe_dst_offsets", "globe_warp"),
]

# Square sprites carved as raw .bin by the region pass; render them at their
# real dimensions with the palette from the same region.
# (part, [asset names], width, height, palette asset)
SPRITE_SETS = [
    ("003", ["sprite1", "sprite2", "sprite3", "sprite4"], 56, 56, "sprites_palette"),
]

# One .bin holding N frames back to back; split and render each.
# (part, source asset, count, width, height, palette asset, name prefix)
SPRITE_STRIPS = [
    ("001", "comet_frames", 10, 65, 48, "intro_palette", "comet"),
]

# Bitmaps stored with a 2-byte (width, height) header. In part 002 the header
# bytes are zero in the file and the code writes 146/85 into them after load,
# so the dimensions have to come from the code, not the data.
# (part, asset, skip, width, height, palette, name)
HEADERED_BITMAPS = [
    ("002", "garage_door",  2, 146, 85, "house_palette",   "garage_door"),
    ("002", "banner_strip", 0, 320, 40, "objects_palette", "banner_320x40"),
    ("002", "rewind_button", 0,  34, 43, "objects_palette", "rewind_button"),
]

# Palettes compiled into a part's DGROUP rather than shipped in the blob.
# Borland keeps R, G and B as three separate tables, not interleaved triples.
# (part, dgroup seg, R off, G off, B off, count, first DAC index, name)
EMBEDDED_PALETTES = [
    ("003", 0x1761, 0x0002, 0x00E3, 0x01C4, 225, 1, "tunnel_palette"),
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
            name = NAMES.get((seek, i)) or f"{seek:06X}_{i:02d}"

            if sz == PALETTE:
                pal = last_pal = data
                (d / f"{name}.pal").write_bytes(data)
                manifest.append((part, seek, i, sz, f"part{part}/{name}.pal", "VGA palette, 6-bit"))
            elif sz == SCREEN and (pal or last_pal):
                (d / f"{name}.raw").write_bytes(data)
                if any(name in s[1] for s in PLANE_SETS):
                    manifest.append((part, seek, i, sz, f"part{part}/{name}.raw",
                                     "Mode-X plane; see the composite below"))
                else:
                    ovr = PALETTE_OVERRIDES.get((part, name))
                    if ovr:
                        use, note = (d / f"{ovr}.pal").read_bytes(), f"320x200 screen ({ovr})"
                    else:
                        use = pal or last_pal
                        note = "320x200 screen" + ("" if pal else " (palette carried forward)")
                    png_indexed(d / f"{name}.png", data, use)
                    manifest.append((part, seek, i, sz, f"part{part}/{name}.png", note))
            else:
                ext = ".flc" if name.endswith("_flc") else ".bin"
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
        (d / f"{name}.bin").write_bytes(raw)

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
        png_indexed(d / f"{name}.png", bytes(px), ramp_palette(), W, H)
        manifest.append((part, None, None, len(raw), f"part{part}/{name}.png",
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
        (d / f"{name}.pal").write_bytes(bytes(pal))
        manifest.append((part, None, None, 768, f"part{part}/{name}.pal",
                         f"embedded: R DS:${ro:04X} G DS:${go:04X} B DS:${bo:04X}, "
                         f"{count} entries from index {first}"))


def build_composites(manifest):
    """De-interleave Mode-X plane sets into the image they actually represent."""
    from modex import deinterleave
    for part, planes, name, w, h, palname in PLANE_SETS:
        d = OUT / f"part{part}"
        data = [(d / f"{p}.raw").read_bytes() for p in planes]
        px = deinterleave(data, w, h)
        palfile = d / f"{palname}.pal"
        pal = palfile.read_bytes() if palfile.exists() else ramp_palette()
        png_indexed(d / f"{name}.png", px, pal, w, h)
        manifest.append((part, None, None, w * h, f"part{part}/{name}.png",
                         f"{w}x{h} de-interleaved from {len(planes)} Mode-X planes"))


def visualise_offset_tables(manifest):
    """Render where a scatter blit reads from and writes to, as coverage maps."""
    for part, srcname, dstname, name in OFFSET_TABLES:
        d = OUT / f"part{part}"
        for tag, asset in (("src", srcname), ("dst", dstname)):
            tab = (d / f"{asset}.bin").read_bytes()
            n = len(tab) // 2
            px = bytearray(64000)
            hits = 0
            for i in range(1, n):               # the blit starts at index 1
                o = struct.unpack_from("<H", tab, i * 2)[0]
                if o < 64000:
                    if not px[o]:
                        hits += 1
                    px[o] = 40 + (i * 200) // n
            png_indexed(d / f"{name}_{tag}.png", bytes(px), ramp_palette())
            manifest.append((part, None, None, len(tab), f"part{part}/{name}_{tag}.png",
                             f"{tag} coverage of the scatter blit, {hits:,} distinct pixels"))


def render_sprites(manifest):
    for part, names, w, h, palname in SPRITE_SETS:
        d = OUT / f"part{part}"
        pal = (d / f"{palname}.pal").read_bytes()
        for name in names:
            data = (d / f"{name}.bin").read_bytes()
            png_indexed(d / f"{name}.png", data[:w * h], pal, w, h)
            manifest.append((part, None, None, len(data), f"part{part}/{name}.png",
                             f"{w}x{h} sprite"))


def render_headered(manifest):
    for part, src, skip, w, h, palname, name in HEADERED_BITMAPS:
        d = OUT / f"part{part}"
        pal = (d / f"{palname}.pal").read_bytes()
        data = (d / f"{src}.bin").read_bytes()[skip:skip + w * h]
        png_indexed(d / f"{name}.png", data, pal, w, h)
        manifest.append((part, None, None, len(data), f"part{part}/{name}.png",
                         f"{w}x{h}, dimensions from code not header"))


def split_strips(manifest):
    for part, src, count, w, h, palname, prefix in SPRITE_STRIPS:
        d = OUT / f"part{part}"
        pal = (d / f"{palname}.pal").read_bytes()
        data = (d / f"{src}.bin").read_bytes()
        for i in range(count):
            frame = data[i * w * h:(i + 1) * w * h]
            png_indexed(d / f"{prefix}{i}.png", frame, pal, w, h)
            manifest.append((part, None, None, len(frame),
                             f"part{part}/{prefix}{i}.png", f"{w}x{h} frame {i}"))


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
