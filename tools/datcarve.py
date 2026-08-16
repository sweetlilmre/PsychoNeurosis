"""Carve NEUROSIS.DAT into its assets using the recovered read map.

Each record is a seek offset plus the exact BlockRead sizes that follow, so the
reads slice the region precisely. A 768-byte read is a VGA palette (256 x RGB,
6 bits per channel) and a 64000-byte read is a 320x200 mode-13h screen; when a
palette precedes images in the same region we pair them and emit a PNG.

PNG is written directly -- indexed colour, no third-party imaging library.
"""
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from datmap import RECORDS

DAT = Path("bin/NEUROSIS.DAT")
OUT = Path("work/assets")
PALETTE, SCREEN = 768, 64000
W, H = 320, 200


def png_indexed(path, pixels, palette6, width=W, height=H):
    """Write an 8-bit indexed PNG. palette6 is 768 bytes of 6-bit VGA values."""
    pal = bytes(min(255, (c << 2) | (c >> 4)) for c in palette6)  # 6-bit -> 8-bit

    raw = bytearray()
    for y in range(height):
        raw.append(0)                                    # filter type 0
        raw += pixels[y * width:(y + 1) * width]

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 3, 0, 0, 0)
    path.write_bytes(
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"PLTE", pal)
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def main():
    blob = DAT.read_bytes()
    OUT.mkdir(parents=True, exist_ok=True)

    n_png = n_bin = 0
    # Some routines read a screen whose palette was loaded by a different
    # routine, so carry the most recently seen palette forward through the file
    # in offset order. Such images are marked _fallbackpal.
    last_pal = None
    for part, host, seek, sizes in sorted(RECORDS, key=lambda r: r[2]):
        pos = seek
        pal = None
        for i, sz in enumerate(sizes):
            data = blob[pos:pos + sz]
            stem = f"{part}_{seek:06X}_{i:02d}_{sz}"

            if sz == PALETTE:
                pal = last_pal = data
                (OUT / f"{stem}.pal").write_bytes(data)
                n_bin += 1
            elif sz == SCREEN and (pal or last_pal):
                use = pal or last_pal
                tag = stem if pal else stem + "_fallbackpal"
                png_indexed(OUT / f"{tag}.png", data, use)
                n_png += 1
            else:
                (OUT / f"{stem}.bin").write_bytes(data)
                n_bin += 1
            pos += sz

    print(f"wrote {n_png} PNGs and {n_bin} raw chunks to {OUT}")


if __name__ == "__main__":
    main()
