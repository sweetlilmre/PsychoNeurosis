"""Extract part 006 scene 4's credits text out of the binary.

The text is initialised data at DS:$0C8A -- 113 lines on a 256-byte stride,
of which 11bb:01a1 only ever reads bytes 1..12. Everything past line 100 is
off the end of the file image and reads as blank at run time.

    python tools/emit_p6text.py > src/gen/P6TEXT.INC
"""
import struct, pathlib, sys

B = pathlib.Path("work/split/NEUROSIS_006_fpu.exe").read_bytes()
DS = struct.unpack_from("<H", B, 8)[0] * 16 + (0x164E - 0x1000) * 16
for L in range(1, 114):
    o = DS + 0x0C8A + L * 256 + 1
    s = B[o:o + 12] if o + 12 <= len(B) else b" " * 12
    sys.stdout.write("%3d |%s|\n" % (L, s.decode("latin1").replace(chr(0), " ")))
