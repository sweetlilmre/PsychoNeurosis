"""De-interleave four Mode-X planes into one linear image.

Unchained VGA splits a scanline across four planes: plane p holds the pixels
whose x satisfies x mod 4 == p. The loader writes 64000 bytes to each of the
four planes, so the underlying image is 256000 pixels; at 640 wide that is
640x400, of which mode 13h shows a 320x200 window.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from datcarve import png_indexed


def deinterleave(planes, width, height):
    bpp = width // 4                      # bytes per plane per scanline
    out = bytearray(width * height)
    for p, data in enumerate(planes):
        for y in range(height):
            row = y * bpp
            base = y * width + p
            for i in range(bpp):
                out[base + i * 4] = data[row + i]
    return bytes(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("planes", nargs=4, help="plane 0..3 in order")
    ap.add_argument("-p", "--palette", required=True)
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("-W", "--width", type=int, default=640)
    ap.add_argument("-H", "--height", type=int, default=400)
    args = ap.parse_args()

    planes = [Path(p).read_bytes() for p in args.planes]
    pal = Path(args.palette).read_bytes()
    need = args.width // 4 * args.height
    for i, d in enumerate(planes):
        if len(d) < need:
            sys.exit(f"plane {i}: {len(d)} bytes, need {need} for "
                     f"{args.width}x{args.height}")

    px = deinterleave(planes, args.width, args.height)
    png_indexed(Path(args.out), px, pal, args.width, args.height)
    print(f"wrote {args.out} ({args.width}x{args.height})")


if __name__ == "__main__":
    main()
