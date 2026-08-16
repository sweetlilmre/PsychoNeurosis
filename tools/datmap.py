"""Build a region map of NEUROSIS.DAT from the recovered Seek/BlockRead constants.

The file has no directory. Every part Assigns it, Seeks to a hardcoded absolute
offset and BlockReads fixed sizes, so those constants are the only map that
exists. Sorting the seek targets partitions the blob into regions, and the read
sizes say what each region holds (64000 = a 320x200 screen, 768 = a palette).
"""
import json
from pathlib import Path

DAT = Path("bin/NEUROSIS.DAT")

# (part, host routine, seek offset or None if the read starts at 0, [read sizes])
RECORDS = [
    # Assign/Seek and the BlockReads often sit in different routines. Where the
    # seek is elsewhere, the offset below is the one that makes the region tile
    # exactly against its neighbours -- confirmed by declared == gap.
    ("001", "FUN_1012_05bd", 0x000000, [768, 64000]),
    ("001", "FUN_1082_0000", 0x00FD00, [768, 31200, 64000, 15104]),
    ("001", "FUN_10e3_0017", 0x02AEE0, [64000]),
    ("001", "FUN_1107_0025", 0x03A8E0, [3776, 768, 49, 49]),
    ("001", "FUN_12c5_0413", 0x03BB02, [52, 768]),
    ("002", "FUN_1008_00b9", 0x03BE36, [768, 64000, 64000, 64000, 64000, 12412]),
    ("002", "FUN_108b_2454", 0x07D9B2, [12800, 1550, 768, 1462]),
    ("003", "FUN_1015_08a7", 0x081A76, [64000, 64000, 64000, 64000]),
    ("003", "Demo_Scene2",   0x0C0276, [3000]),
    # Scene4 seeks here; FUN_119d_010f does the reading (768 + 2 x 45994).
    ("003", "FUN_119d_010f", 0x0C0E2E, [768, 45994, 45994]),
    ("003", "Demo_Scene4",   0x0D7882, [64000]),
    ("003", "Demo_Scene4",   0x0E7282, [64000]),
    ("003", "Demo_Scene4",   0x0F6C82, [64000]),
    ("003", "Demo_Scene4",   0x106682, [64000]),
    ("003", "FUN_120f_0017", 0x116082, [36414]),
    # The 3136-byte read sits in a 4-iteration loop (Scene7 frees 4 such buffers).
    ("003", "FUN_125e_012e", 0x11EEC0, [1550, 3136, 3136, 3136, 3136, 768]),
    ("004", "FUN_1005_00a6", 0x1228CE, [23436, 768, 64000, 64000, 768, 768, 432,
                                        400, 480, 1326, 420, 800, 3096, 648, 720,
                                        3180, 10920, 840, 24255, 750]),
    ("005", "FUN_100e_07a4", 0x153DE5, [1024, 1024, 1024]),
    ("005", "FUN_1096_03d7", 0x1549E5, [768, 64000]),
    ("005", "FUN_1102_02d1", 0x1646E5, [64000, 768]),
    ("006", "FUN_1095_000d", 0x1743E5, [15104, 768]),
    # Seek is in FUN_100f_07d5; FUN_100f_03f8 and FUN_100f_00ac do the reading.
    ("006", "FUN_100f_03f8", 0x1781E5, [256, 256, 768, 45000]),
    ("006", "FUN_1118_0028", 0x1836AD, [29120, 210, 768, 768, 768]),
    ("006", "FUN_11bb_0015", 0x18B23F, [180, 23436, 768]),
    # lemend.flc -- only the 128-byte header is a fixed read; frames stream on
    # computed seeks, so the region runs to the next record.
    ("007", "FUN_100f_0453", 0x19117F, [62206]),
    ("003", "FUN_11f3_0017", 0x1A047D, [13104]),
]


def main():
    size = DAT.stat().st_size

    print(f"NEUROSIS.DAT = {size:,} bytes\n")
    print(f"{'offset':>10} {'hex':>9}  {'part':<5} {'declared':>9} {'to next':>9} "
          f"{'ok':>4}  routine")
    print("-" * 84)

    rows = sorted((r, p, h, sz) for p, h, r, sz in RECORDS)
    exact = 0
    for i, (off, part, host, sizes) in enumerate(rows):
        nxt = rows[i + 1][0] if i + 1 < len(rows) else size
        declared, gap = sum(sizes), nxt - off
        ok = "=" if declared == gap else f"{declared - gap:+,}"
        if declared == gap:
            exact += 1
        print(f"{off:>10,} {off:>9X}  {part:<5} {declared:>9,} {gap:>9,} {ok:>4}  {host}")

    accounted = sum(sum(s) for _, _, _, s in RECORDS)
    print(f"\n{exact}/{len(rows)} regions tile exactly against the next seek")
    print(f"declared bytes: {accounted:,} of {size:,} ({accounted / size:.1%})")

    Path("work/dat_records.json").write_text(json.dumps(
        [{"part": p, "host": h, "seek": r, "reads": s} for p, h, r, s in RECORDS],
        indent=1))


if __name__ == "__main__":
    main()
