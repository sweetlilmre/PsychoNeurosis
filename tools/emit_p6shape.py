"""Extract part 006 scene 2's cell shape table out of the binary.

2,048 bytes of initialised data at DS:$000A, indexed at 100f:04b4 as
C*128 + A*8 + B - 127 -- so [1..16, 1..16, 1..8].

    python tools/emit_p6shape.py
"""
import struct, pathlib
B = pathlib.Path("work/split/NEUROSIS_006_fpu.exe").read_bytes()
DS = struct.unpack_from("<H", B, 8)[0] * 16 + (0x164E - 0x1000) * 16
T = B[DS + 0x0A:DS + 0x0A + 2048]
print("nonzero:", sum(1 for x in T if x))
