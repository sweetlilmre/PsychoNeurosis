"""Unpack an LZEXE 0.91 ('LZ91') compressed MZ executable.

NEUROSIS.008 is the only file in Psycho Neurosis that is packed. It is not an
Asphyxia part -- it is JCAB's DemoVT player -- but nothing can be read out of
it until the image is expanded, so this is the first step for anything to do
with 008.

Only LZ91 is handled. LZ90 differs in the relocation table only, and no file
here needs it.
"""
import struct
import sys
import pathlib


class Bits:
    """LZEXE's bit stream: 16-bit words, little-endian, consumed LSB first."""

    def __init__(self, data, pos):
        self.d = data
        self.p = pos
        self._load()

    def _load(self):
        self.w = struct.unpack_from("<H", self.d, self.p)[0]
        self.p += 2
        self.n = 16

    def bit(self):
        """Extract, then refill IMMEDIATELY if that emptied the word.

        The refill cannot be left until the next call for one. The stub does

            SHR BP,1 / DEC DX / JNZ + / LODSW / MOV BP,AX / MOV DL,10h

        -- so when the sixteenth bit is taken the next word is pulled from the
        stream straight away, and a literal byte or a distance byte belonging
        to THAT bit is read from after it. Refilling lazily hands the literal
        the two bytes of the bit-word instead, and the stream drifts about
        seventy bytes in."""
        b = self.w & 1
        self.w >>= 1
        self.n -= 1
        if self.n == 0:
            self._load()
        return b

    def byte(self):
        b = self.d[self.p]
        self.p += 1
        return b


def unpack(data, start):
    bits = Bits(data, start)
    out = bytearray()
    while True:
        if bits.bit():                          # 1 -- one literal byte
            out.append(bits.byte())
            continue
        if not bits.bit():                      # 00 -- short match
            length = (bits.bit() << 1) | bits.bit()
            length += 2
            span = bits.byte() | 0xFF00
        else:                                   # 01 -- long match
            lo = bits.byte()
            hi = bits.byte()
            span = lo | ((hi & 0xF8) << 5) | 0xE000
            length = (hi & 0x07) + 2
            if length == 2:
                length = bits.byte()
                if length == 0:
                    break                       # end of the stream
                if length == 1:
                    continue                    # segment step -- flat here
                length += 1
        span -= 0x10000                         # it is a negative distance
        for _ in range(length):
            out.append(out[len(out) + span])
    return bytes(out), bits.p


def relocs91(data, pos):
    """LZ91's packed relocation table: runs of byte deltas, 0 escapes."""
    rel = []
    seg = 0
    off = 0
    while True:
        c = data[pos]
        pos += 1
        if c == 0:
            c = struct.unpack_from("<H", data, pos)[0]
            pos += 2
            if c == 0:
                seg += 0x0FFF
                continue
            if c == 1:
                break
            off += c
        else:
            off += c
        while off > 0xFFFF:
            off -= 0x10
            seg += 1
        rel.append((seg, off))
    return rel


def main(src, dst):
    d = pathlib.Path(src).read_bytes()
    if d[0x1C:0x20] != b"LZ91":
        sys.exit("not an LZ91 file")
    hdrpara = struct.unpack_from("<H", d, 8)[0]
    cs = struct.unpack_from("<H", d, 0x16)[0]
    stub = hdrpara * 16 + cs * 16
    ip, ocs, sp, oss, comp, inc, dec, _ = struct.unpack_from("<8H", d, stub)

    body, end = unpack(d, (hdrpara + cs - comp) * 16)
    rel = relocs91(d, stub + 0x158)

    # pad the image up to a paragraph, then build a fresh MZ around it
    body = bytearray(body)
    while len(body) % 16:
        body.append(0)

    nrel = len(rel)
    hsz = 0x1C + nrel * 4
    hsz = (hsz + 15) // 16 * 16
    if hsz < 32:
        hsz = 32
    total = hsz + len(body)

    hdr = bytearray(hsz)
    hdr[0:2] = b"MZ"
    struct.pack_into("<H", hdr, 2, total % 512)
    struct.pack_into("<H", hdr, 4, (total + 511) // 512)
    struct.pack_into("<H", hdr, 6, nrel)
    struct.pack_into("<H", hdr, 8, hsz // 16)
    # minalloc has to cover everything above the image that the program uses,
    # and the original stack is the deepest of it: SS:SP sits well past the
    # decompressed bytes. LZEXE keeps the original minalloc nowhere, so it is
    # recomputed from the stack instead of guessed at.
    need = (oss * 16 + sp + 15) // 16 - len(body) // 16
    if need < inc + 1:
        need = inc + 1
    struct.pack_into("<H", hdr, 10, need)             # minalloc
    struct.pack_into("<H", hdr, 12, 0xFFFF)           # maxalloc
    struct.pack_into("<H", hdr, 14, oss)
    struct.pack_into("<H", hdr, 16, sp)
    struct.pack_into("<H", hdr, 20, ip)
    struct.pack_into("<H", hdr, 22, ocs)
    struct.pack_into("<H", hdr, 24, 0x1C)
    for i, (s, o) in enumerate(rel):
        struct.pack_into("<HH", hdr, 0x1C + i * 4, o, s)

    pathlib.Path(dst).write_bytes(bytes(hdr) + bytes(body))
    print("%s -> %s" % (src, dst))
    print("  image      %d bytes (%d paragraphs)" % (len(body), len(body) // 16))
    print("  entry      %04x:%04x    stack %04x:%04x" % (ocs, ip, oss, sp))
    print("  relocs     %d" % nrel)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
