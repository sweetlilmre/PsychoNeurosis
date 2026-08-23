#!/usr/bin/env python3
"""Read an Intel OMF .OBJ and report which bytes of its code are FIXUPS.

    from substrate import omf
    code, fixups = omf.code_and_fixups(path)
    fields = omf.fields(path)          # {offset: length}

WHY THIS EXISTS. A .TPU-shaped model of an unresolved reference is "the
byte is 00" -- true of a Turbo Pascal .TPU, where the compiler leaves a hole
for the linker. It is NOT true of an assembled module: TASM resolves what it
can and leaves an ADDEND. `DW OFFSET @@G1Table` inside the module comes out as
the offset from the module's own start, and `MOV AX,Volumes[2]` comes out as
the displacement 2 -- both correct, both waiting on a base the linker adds, and
both a flat mismatch against a binary where the linker already ran.

So for a unit that links an object module the fixup mask cannot be guessed from
the bytes; it has to be read from the object file, which records it exactly.
That is what this does, and it makes the measurement of 1a17's assembler half
stricter than the .TPU heuristic rather than looser: a byte is excused only if
the assembler said it was a relocation, not merely because it happens to be
zero.

Only the records needed for that are decoded, and unknown records are skipped
by their length field, which is what the format is designed for.

    80 THEADR    89 LNAMES    98 SEGDEF    A0/A1 LEDATA    9C/9D FIXUPP
"""
import sys
import pathlib


def records(blob):
    """Yield (type, payload) for each OMF record. The checksum byte is dropped."""
    i = 0
    while i + 3 <= len(blob):
        rectype = blob[i]
        length = int.from_bytes(blob[i + 1:i + 3], "little")
        payload = blob[i + 3:i + 2 + length]        # the last byte is the checksum
        yield rectype, payload
        i += 3 + length
    return


def code_and_fixups(path):
    """Return (code, fixups) for the object's first code segment.

    `code` is the concatenated LEDATA, `fixups` is a set of byte offsets inside
    it that a FIXUPP record covers. A FIXUPP's LOCAT field gives the location
    type (2 bits of the first byte plus the low nibble) and an offset relative
    to the LEDATA record it follows, which is why the two are tracked together.
    """
    blob = pathlib.Path(path).read_bytes()
    code = bytearray()
    fixups = set()
    data_start = 0                      # where the current LEDATA landed in `code`

    for rectype, p in records(blob):
        if rectype in (0xA0, 0xA1):                     # LEDATA
            wide = rectype == 0xA1
            j = 0
            j += 2 if wide else 1                       # segment index
            offset = int.from_bytes(p[j:j + 4 if wide else j + 2], "little")
            j += 4 if wide else 2
            data_start = offset
            if len(code) < offset:
                code.extend(b"\x00" * (offset - len(code)))
            code[offset:offset + len(p) - j] = p[j:]
        elif rectype in (0x9C, 0x9D):                   # FIXUPP
            j = 0
            while j < len(p):
                b = p[j]
                if not b & 0x80:                        # THREAD, not a fixup
                    j += 2 if (b & 0x40) else 2
                    # a thread's field is 1 byte plus an index; indices are
                    # 1 byte below 0x80 and 2 above, which the loop below reads
                    idx = p[j - 1]
                    if idx & 0x80:
                        j += 1
                    continue
                locat = (b << 8) | p[j + 1]
                loc = (locat >> 10) & 7
                data_off = locat & 0x3FF
                j += 2
                fixdat = p[j]
                j += 1
                if not fixdat & 0x80:                   # frame not a thread
                    frame = (fixdat >> 4) & 7
                    if frame in (0, 1, 2):
                        j += 2 if p[j] & 0x80 else 1
                if not fixdat & 0x08:                   # target not a thread
                    j += 2 if p[j] & 0x80 else 1
                if fixdat & 0x04:                       # P bit clear -> displacement
                    pass
                else:
                    j += 4 if (rectype == 0x9D) else 2
                size = {0: 1, 1: 2, 2: 2, 3: 4, 4: 1, 5: 2, 9: 4, 11: 6, 13: 4}.get(loc, 2)
                at = data_start + data_off
                for k in range(size):
                    fixups.add(at + k)
    return bytes(code), fixups


def fields(path):
    """{offset: length} -- each FIXUPP field as one entry rather than a byte
    set.

    A caller that has to know how LONG a field is used to get that by running
    this file and parsing its verbose output with a regex. The information was
    always here; only the shape was missing.
    """
    _, marked = code_and_fixups(path)
    out, run = {}, None
    for off in sorted(marked):
        if run is not None and off == run + out[run]:
            out[run] += 1
        else:
            run, out[run := off] = off, 1
    return out
