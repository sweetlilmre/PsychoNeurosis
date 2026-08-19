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

NL = chr(10)

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
# adds ModeX, P2View and FixMath on top, and each of its two scenes sets up
# its own video mode.
P2S1_USES = "Crt, VGA, ModeX, DemoVT"
P2S1_OPEN = "  VirtScrAlloc;       { 1436:0006, what the main body does first }\n"
P2S1_CLOSE = "  VirtScrFree;\n  Port[$3C8] := 0;\n  TextMode(CO80);\n"

P2S2_USES = "Crt, VGA, P2View, FixMath, DemoVT"
P2S2_OPEN = ""
P2S2_CLOSE = "  Port[$3C8] := 0;\n  TextMode(CO80);\n"

# Part 004 is a single scene, and it has no driver unit of its own: its whole
# main body is three calls, so the harness stands in for it. Missing the FIRST
# of them is what made TP4S1 look like it hung -- part 004 sets its own video
# mode, nothing in RunPart4 does it, and a harness that only allocated the
# virtual screen ran the entire scene invisibly in 80x25 text.
#
#     1000:001c  CALLF 11e3:0000   SetMode13h
#     1000:0021  CALLF 11e3:0006   VirtScrAlloc
#     1000:0026  CALLF 1005:1cd6   RunPart4
#
# and afterwards it drains the keyboard buffer -- RunPart4 starts its ending on
# a keypress, so without this the keystroke falls straight through to DOS.
P4_USES  = "Crt, VGA, DemoVT"
P4_OPEN  = ("  SetMode13h;         { 1000:001c -- part 004 sets its own mode }\n"
            "  VirtScrAlloc;       { 1000:0021 -- the hillside lives here }\n")
P4_CLOSE = ("  while KeyPressed do ReadKey;   { 1000:002b }\n"
            "  VirtScrFree;                  { 1000:003b }\n")

# Part 005's main body is SetMode13h / VirtScrAlloc / the three scenes, with
# the music handling between them (1000:0030 onwards). A scene harness needs
# the first two; DrawMesh writes to the virtual screen and copies it up.
P5_USES  = "Crt, VGA, DemoVT"
P5_OPEN  = ("  SetMode13h;         { 1000:0030 }" + NL +
            "  VirtScrAlloc;       { 1000:0035 }" + NL)
P5_CLOSE = "  VirtScrFree;        { 1000:00cd }" + NL

# Part 007 has NO virtual screen -- the FLI player writes straight to $A000 --
# so its main body is just SetMode13h at 1000:0021 and then the scene. There
# is nothing to free on the way out.
P7_USES  = "Crt, VGA, DemoVT"
P7_OPEN  = "  SetMode13h;         { 1000:0021 }" + NL
P7_CLOSE = ""

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

    ("TP5S1", "P5S1", "Scene1", P5_USES, P5_OPEN, P5_CLOSE,
     "part 005 scene 1 -- the heightfield mesh"),
    ("TP5S2", "P5S2", "Scene2", P5_USES, P5_OPEN, P5_CLOSE,
     "part 005 scene 2 -- the rotozoomer and the scatter"),
    ("TP5S3", "P5S3", "Scene3", P5_USES, P5_OPEN, P5_CLOSE,
     "part 005 scene 3 -- the turning relief"),

    ("TP6S1", "P6S1", "Scene1", P5_USES, P5_OPEN, P5_CLOSE,
     "part 006 scene 1 -- the whooshtext"),
    ("TP6S2", "P6S2", "Scene2", P5_USES, P5_OPEN, P5_CLOSE,
     "part 006 scene 2 -- the rotating tile mesh"),
    ("TP6S3", "P6S3", "Scene3", P5_USES, P5_OPEN, P5_CLOSE,
     "part 006 scene 3 -- the fire"),
    ("TP6S4", "P6S4", "Scene4", P5_USES, P5_OPEN, P5_CLOSE,
     "part 006 scene 4 -- the credits scroller"),

    ("TP7S1", "P7S1", "Scene1", P7_USES, P7_OPEN, P7_CLOSE,
     "part 007 -- the FLI/FLC player"),
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
     "Crt, VGA, ModeX, P2View, FixMath, DemoVT",
     "part 002 -- both scenes, through the driver at 1000:0032"),
    ("TPART3", "P3Main", "RunPart3",
     "Crt, VGA, DemoVT",
     "part 003 -- all seven scenes, through the driver at 1000:0041"),
    ("TPART5", "P5Main", "RunPart5",
     "Crt, VGA, DemoVT",
     "part 005 -- all three scenes, through the main body at 1000:002d"),
    ("TPART6", "P6Main", "RunPart6",
     "Crt, VGA, DemoVT",
     "part 006 -- all four scenes, through the main body at 1000:002d"),
    ("TPART7", "P7Main", "RunPart7",
     "Crt, VGA, DemoVT",
     "part 007 -- the animation, through the main body at 1000:001e"),
]

# EVERY harness -- scene and part alike -- must hand the machine back usable.
# The scenes themselves may not, and the parts definitely do not: each part's
# driver ends in Halt(0) exactly as the original main body does, so nothing
# written after the call to it can run. Part 002 is the one that shows it: it
# exits in unchained 320x400 with the Miscellaneous Output register
# reprogrammed for 400 lines ($3C2 := $E3), and DOS carries on writing text
# nobody can read.
#
# An ExitProc is the only hook that survives all of it -- Turbo Pascal runs it
# on the way out of Halt, out of a run-time error, and out of a normal end.
# So it goes in every harness, and the scenes and drivers keep their faithful
# behaviour untouched.
EXIT_PROC = """var
  PrevExit : Pointer;

{ Runs on the way out of Halt, of a run-time error, or of a normal end --
  see the note in mktests.py. }
procedure RestoreTextMode; far;
begin
  ExitProc := PrevExit;
  asm
    MOV  AX, $0003      { BIOS mode 3: 80x25 colour text                    }
    INT  $10            { which also undoes Mode-X's CRTC and sequencer     }
  end;
end;

"""

HEAD = """{ ===========================================================================
  Test harness for %(what)s.

  Generated by tools/mktests.py -- do not edit; change the generator instead.
  Needs NEUROSIS.DAT in the current directory, so run it from run\\.

  Build:  python tools/dosbox/dosbuild.py %(prog)s
  =========================================================================== }

program %(prog)s;

uses %(uses)s, %(unit)s;

%(exit)svar
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
%(hook)s
"""

TAIL = """
  WriteLn('Done.');
end.
"""


HOOK = """
  PrevExit := ExitProc;
  ExitProc := @RestoreTextMode;
"""


def write(prog, unit, entry, uses, opening, closing, what):
    text = (HEAD % dict(prog=prog, unit=unit, uses=uses, what=what,
                        pad=" " * len(prog), exit=EXIT_PROC, hook=HOOK)
            + opening
            + "  %s;\n\n" % entry
            + closing
            + TAIL)
    (SRC / (prog + ".PAS")).write_text(text, encoding="ascii", newline="\r\n")
    print("  %-12s %s" % (prog + ".PAS", what))


for prog, unit, entry, uses, opening, closing, what in SCENES:
    write(prog, unit, entry, uses, opening, closing, what)

print("")
for prog, unit, entry, uses, what in PARTS:
    write(prog, unit, entry, uses, "", "", what)

print("\n  %d scene harnesses, %d part harnesses."
      % (len(SCENES), len(PARTS)))
