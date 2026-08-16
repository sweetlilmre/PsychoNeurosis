"""Identify the appended payload and toolchain fingerprints of each binary."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from mzinfo import parse

MOD_TAGS = {
    b"M.K.": "ProTracker 4ch",
    b"M!K!": "ProTracker 4ch (>64 pat)",
    b"FLT4": "StarTrekker 4ch",
    b"FLT8": "StarTrekker 8ch",
    b"6CHN": "FastTracker 6ch",
    b"8CHN": "FastTracker 8ch",
    b"CD81": "Oktalyzer 8ch",
    b"OKTA": "Oktalyzer",
}

FINGERPRINTS = [
    (b"Turbo Pascal", "Turbo/Borland Pascal runtime"),
    (b"Borland", "Borland"),
    (b"Runtime error", "BP runtime error handler"),
    (b"Error ", "error text"),
    (b"DemoVT", "JCAB DemoVT mod player"),
    (b"VangeliSTeam", "VangeliSTeam"),
    (b"Asphyxia", "Asphyxia"),
    (b"PKLITE", "PKLITE packer"),
    (b"LZ09", "LZEXE"),
    (b"diet", "DIET packer"),
]


def ascii_strings(buf, minlen=5):
    out, cur, start = [], bytearray(), 0
    for i, b in enumerate(buf):
        if 32 <= b < 127:
            if not cur:
                start = i
            cur.append(b)
        else:
            if len(cur) >= minlen:
                out.append((start, cur.decode("ascii")))
            cur = bytearray()
    if len(cur) >= minlen:
        out.append((start, cur.decode("ascii")))
    return out


def main(paths):
    for p in paths:
        h = parse(Path(p))
        raw = h["raw"]
        print(f"\n=== {h['file']} ===")
        print(f"  image {h['imagesize']}  overlay {h['overlay_bytes']}")

        tags = sorted({v for k, v in FINGERPRINTS if k in raw})
        if tags:
            print(f"  fingerprints: {', '.join(tags)}")

        if h["overlay_bytes"] > 0:
            ov = raw[h["imagesize"]:]
            # MOD files carry their 4-char tag at offset 1080
            tag = bytes(ov[1080:1084])
            name = ov[:20].split(b"\0")[0].decode("latin-1", "replace").strip()
            if tag in MOD_TAGS:
                print(f"  payload: MOD [{tag.decode()}] {MOD_TAGS[tag]}  title={name!r}")
            else:
                print(f"  payload: unknown, first16={ov[:16].hex(' ')}")
                s = ascii_strings(ov[:2048], 6)[:6]
                for off, txt in s:
                    print(f"    +{off:<6} {txt!r}")


if __name__ == "__main__":
    main(sys.argv[1:])
