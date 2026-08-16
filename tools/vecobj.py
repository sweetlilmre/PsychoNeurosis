"""Extract and render the 3-D vector objects compiled into a part's DGROUP.

Parts 001, 002 and 003 all keep their geometry as typed constants rather than
in NEUROSIS.DAT. Part 002's format is the richest: a vertex array of signed
word triples plus a face list.

Face stream layout, read straight off the loader at 108b:1bbd:

    count, index1 .. indexN, colour      -- count + 2 words per face

Indices are stored zero-based and incremented on load; coordinates are halved
on load. Faces have 3, 4, 6 or 8 vertices.
"""
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from datcarve import png_indexed
from mzinfo import parse

# Axis pairs to render. A model is often unrecognisable from the "obvious"
# X/Y view -- the Enterprise only reads from above, and the revolver and the
# sailboat only once their long axis (Y) is horizontal. So each object names
# the view that identifies it, and the others are rendered too.
VIEWS = {
    "top":   (0, 2),      # X across, Z down
    "side":  (2, 1),      # Z across, Y down
    "front": (0, 1),      # X across, Y down
    "long":  (1, 0),      # Y across, X down -- for models built along Y
    "long2": (1, 2),      # Y across, Z down
}

# (part, dgroup seg, vertex off, count, face off, count, name, best view)
OBJECTS = [
    ("002", 0x1866, 0x0004, 75, 0x01C6, 55, "obj_enterprise", "top"),
    ("002", 0x1866, 0x067E, 68, 0x0816, 64, "obj_revolver",   "long"),
    ("002", 0x1866, 0x0B06, 32, 0x0BC6, 21, "obj_sailboat",   "long2"),
    ("002", 0x1866, 0x0CAE,  4, 0x0CC6,  1, "obj_quad",       "top"),
]

W, H = 320, 200


def ramp():
    return bytes(v for i in range(256) for v in (((i >> 2) & 63),) * 3)


def line(px, x0, y0, x1, y1, c):
    dx, dy = abs(x1 - x0), abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx - dy
    while True:
        if 0 <= x0 < W and 0 <= y0 < H:
            px[y0 * W + x0] = c
        if x0 == x1 and y0 == y1:
            break
        e2 = 2 * err
        if e2 > -dy:
            err -= dy
            x0 += sx
        if e2 < dx:
            err += dx
            y0 += sy


def main():
    out = Path("assets")
    for part, seg, voff, nv, foff, nf, name, best in OBJECTS:
        h = parse(Path(f"work/split/NEUROSIS_{part}.exe"))
        raw = h["raw"]
        base = h["hdrsize"] + seg * 16 - 0x10000

        pts = [struct.unpack_from("<hhh", raw, base + voff + i * 6) for i in range(nv)]

        faces, p = [], 0
        for _ in range(nf):
            cnt = struct.unpack_from("<h", raw, base + foff + p * 2)[0]
            idx = [struct.unpack_from("<h", raw, base + foff + (p + 1 + k) * 2)[0] + 1
                   for k in range(cnt)]
            faces.append(idx)
            p += cnt + 2

        # Orthographic, auto-scaled to fill the frame -- this is a preview for
        # identification, not what the demo draws.
        d = out / f"part{part}"
        d.mkdir(parents=True, exist_ok=True)
        (d / f"{name}.bin").write_bytes(raw[base + voff:base + voff + nv * 6])

        for tag, (ai, bi) in VIEWS.items():
            av = [q[ai] for q in pts]
            bv = [q[bi] for q in pts]
            sc = min((W - 20) / max(1, max(av) - min(av)),
                     (H - 20) / max(1, max(bv) - min(bv)))
            ca, cb = (max(av) + min(av)) / 2, (max(bv) + min(bv)) / 2
            px = bytearray(W * H)
            for idx in faces:
                poly = [(int((pts[i - 1][ai] - ca) * sc) + W // 2,
                         int((pts[i - 1][bi] - cb) * sc) + H // 2)
                        for i in idx if 1 <= i <= nv]
                for k in range(len(poly)):
                    a, b = poly[k], poly[(k + 1) % len(poly)]
                    line(px, a[0], a[1], b[0], b[1], 200)
            png_indexed(d / f"{name}_{tag}.png", bytes(px), ramp(), W, H)
        sizes = sorted({len(f) for f in faces})
        print(f"{name:<14} {nv:>3} verts {nf:>3} faces  sizes {sizes}  "
              f"best view: {name}_{best}.png")


if __name__ == "__main__":
    main()
