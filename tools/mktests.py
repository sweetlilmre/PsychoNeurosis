"""Generate the test programs -- one per scene, and one per part.

Splitting the parts into scene units only helps if the harnesses exist, so
they are generated rather than written by hand.

    TPxSy      one scene on its own. If it misbehaves the fault is in that
               scene's unit or in the units beneath it, and nowhere else.
    TPARTx     the whole part through its real driver, so the scenes can be
               checked in sequence and in context.

Names are 8.3 and uniform: part number, scene number. dosbuild.py registers
anything matching src/TP*.PAS automatically, so adding a row here is the only
step.

    python tools/mktests.py                     write them all
    python tools/dosbox/dosbuild.py TP3S1       build one
    python tools/dosbox/dosbuild.py TPART3      build a whole part

Each needs NEUROSIS.DAT in the current directory, so run them from run/.
"""
import pathlib

SRC = pathlib.Path("src")

# The part 001 and 003 scenes share a prologue: the parts set the mode, take
# the virtual screen and shake hands with the music player before the first
# scene, and the scene units expect all three to have happened.
VGA_USES = "Crt, VGA, DemoVT"
VGA_OPEN = """  SetMode13h;
  VirtScrAlloc;
  MusicDetect;          { harmless with no player resident }
"""
# Scene 3 leaves the adapter in unchained 320x400, and the part's own driver
# calls SetMode13h again afterwards (1000:0097) rather than leaving the scene
# to tidy up. A scene harness stands in for the driver, so it does the same --
# without it TP3S3 exits into a graphics mode.
VGA_CLOSE = """  VirtScrFree;
  SetMode13h;         { 1000:0097 -- what the driver does after scene 3 }
  SetTextMode;
"""

# Part 002 links the same VGA and DemoVT units as everything else -- it just
# adds P2ModeX, P2View and P2Fix on top, and each of its two scenes sets up
# its own video mode.
P2S1_USES = "Crt, VGA, P2ModeX, DemoVT"
P2S1_OPEN = "  VirtScrAlloc;       { 1436:0006, what the main body does first }\n"
P2S1_CLOSE = "  VirtScrFree;\n  Port[$3C8] := 0;\n  TextMode(CO80);\n"

P2S2_USES = "Crt, VGA, P2View, P2Fix, DemoVT"
P2S2_OPEN = ""
P2S2_CLOSE = "  Port[$3C8] := 0;\n  TextMode(CO80);\n"

# Part 004 is a single scene and its driver does the VirtScrAlloc itself, so
# the harness only has to hand it NEUROSIS.DAT.
P4_USES  = "Crt, VGA, DemoVT"
P4_OPEN  = "  VirtScrAlloc;       { 11e3:0006 -- the hillside lives here }\n"
P4_CLOSE = "  VirtScrFree;\n  TextMode(CO80);\n"

# prog, unit, entry, uses, open, close, description
SCENES = [
    ("TP1S1", "P1S1", "Scene1", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 001 scene 1 -- the logo and the bouncing lenses"),
    ("TP1S2", "P1S2", "Scene2", VGA_USES, VGA_OPEN, VGA_CLOSE,
     'part 001 scene 2 -- "ASPHYXIA PRESENTS" and the comet'),
    ("TP1S3", "P1S3", "Scene3", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 001 scene 3 -- the mosaic pixelate"),
    ("TP1S4", "P1S4", "Scene4", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 001 scene 4 -- the tumbling ball grid and the message"),
    ("TP1S5", "P1S5", "Scene5", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 001 scene 5 -- the vector objects and the wipe"),

    ("TP2S1", "P2S1", "Scene1", P2S1_USES, P2S1_OPEN, P2S1_CLOSE,
     "part 002 scene 1 -- the garage: a 1280-wide pan, the door, a starfield"),
    ("TP2S2", "P2S2", "Scene2", P2S2_USES, P2S2_OPEN, P2S2_CLOSE,
     "part 002 scene 2 -- solid 3-D objects, starfield, typed banner"),

    ("TP3S1", "Part3Tunnel",  "Scene1", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 003 scene 1 -- the tunnel"),
    ("TP3S2", "Part3Stars",   "Scene2", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 003 scene 2 -- the star tube"),
    ("TP3S3", "Part3Morph",   "Scene3", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 003 scene 3 -- the morph"),
    ("TP3S4", "Part3Globe",   "Scene4", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 003 scene 4 -- the globe"),
    ("TP3S5", "Part3Blocks",  "Scene5", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 003 scene 5 -- the blocks"),
    ("TP3S6", "Part3Waves",   "Scene6", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 003 scene 6 -- the waves"),
    ("TP3S7", "Part3Sprites", "Scene7", VGA_USES, VGA_OPEN, VGA_CLOSE,
     "part 003 scene 7 -- the spinning portraits"),

    ("TP4S1", "Part4Lemmings", "RunPart4", P4_USES, P4_OPEN, P4_CLOSE,
     "part 004 -- the lemmings"),
]

# prog, driver unit, entry, uses (WITHOUT the driver -- the template appends
# it), description
#
# These call the part's real driver, transcribed from its main body, so the
# scene order, the mode changes between them and the music handling are the
# original's rather than this file's idea of them. Every driver ends in
# Halt(0), exactly as the main body does, so nothing after the call runs.
PARTS = [
    ("TPART1", "P1Intro", "RunIntro",
     "Crt, VGA, DemoVT",
     "part 001 -- all five scenes, through the driver at 1000:003c"),
    ("TPART2", "P2Main", "RunPart2",
     "Crt, VGA, P2ModeX, P2View, P2Fix, DemoVT",
     "part 002 -- both scenes, through the driver at 1000:0032"),
    ("TPART3", "P3Main", "RunPart3",
     "Crt, VGA, DemoVT",
     "part 003 -- all seven scenes, through the driver at 1000:0041"),
]

HEAD = """{ ===========================================================================
  Test harness for %(what)s.

  Generated by tools/mktests.py -- do not edit; change the generator instead.
  Needs NEUROSIS.DAT in the current directory, so run it from run\\.

  Build:  python tools/dosbox/dosbuild.py %(prog)s
  =========================================================================== }

program %(prog)s;

uses %(uses)s, %(unit)s;

var
  F : file;
begin
  Assign(F, 'neurosis.dat');
  {$I-} Reset(F, 1); {$I+}
  if IOResult <> 0 then
  begin
    WriteLn('%(prog)s: neurosis.dat not found in the current directory.');
    WriteLn('%(pad)s  Run this from the run\\ folder.');
    Halt(1);
  end;
  Close(F);

  WriteLn('%(what)s');
  WriteLn('Press a key to start.');
  ReadKey;

"""

TAIL = """
  WriteLn('Done.');
end.
"""


def write(prog, unit, entry, uses, opening, closing, what):
    text = (HEAD % dict(prog=prog, unit=unit, uses=uses, what=what,
                        pad=" " * len(prog))
            + opening
            + "  %s;\n\n" % entry
            + closing
            + TAIL)
    (SRC / (prog + ".PAS")).write_text(text)
    print("  %-12s %s" % (prog + ".PAS", what))


for prog, unit, entry, uses, opening, closing, what in SCENES:
    write(prog, unit, entry, uses, opening, closing, what)

print("")
for prog, unit, entry, uses, what in PARTS:
    write(prog, unit, entry, uses, "", "", what)

print("\n  %d scene harnesses, %d part harnesses."
      % (len(SCENES), len(PARTS)))
