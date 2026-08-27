"""Generate the test programs -- one per scene, and one per part.

Splitting the parts into scene units only helps if the harnesses exist, so
they are generated rather than written by hand.

    TPxSy      one scene on its own. If it misbehaves the fault is in that
               scene's unit or in the units beneath it, and nowhere else.
    TPARTx     the whole part through its real driver, so the scenes can be
               checked in sequence and in context.

Names are 8.3 and uniform: part number, scene number. dosbuild.py registers
anything matching src/test/TP*.PAS automatically, so adding a row here is the only
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

# Scene 6 of part 003 needs no palette help: an earlier version of this file
# recreated scene 5's ramp here, on the belief that the waves inherit it. They
# do not -- Waves_LoadCurves (120f:0017) builds the scene's OWN blue triangle
# over colours 1..178 after reading the curve table, so the unit is
# self-sufficient in isolation.

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

    # PART 004 HAS NO HARNESS ANY MORE. src/NEUR4.PAS is the real program, and
    # unlike part 007's it is a CALL rather than a body: the original's
    # Demo_Main sits inside the scene unit at 1005:1cd6 and its segment 1000
    # holds only the eighty bytes that reach it. 99.4% to 100.0%.

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
# THE ORDER OF A PART HARNESS'S `uses` CLAUSE IS A MEASUREMENT, not a style.
# Turbo Pascal's link order is a reverse DFS post-order over the `uses` graph and
# THE WALK STARTS AT THE PROGRAM, so this clause -- not the part unit's -- decides
# where the shared units land. `Crt, VGA, DemoVT` visits Crt first, so Crt
# finishes first and ends up LAST in code; the original finishes DemoVT first,
# which needs `DemoVT, Crt, VGA`. Checked by pairing each part's inter-unit call
# targets: with the clause this way round every part's segment order matches the
# 1994 file, and with Crt first parts 001, 003, 005 and 006 all had one unit
# displaced. Changing the part unit's own clause does nothing, which is the
# evidence for the walk starting here.
PARTS = [
    # PART 001 HAS NO HARNESS ANY MORE. src/NEUR1.PAS is the real program and
    # its segment matches the original's 288 bytes; P1INTRO.PAS is gone with it.
    # Reading those 288 bytes first is what made the rest possible -- both of the
    # things recorded as blocking part 001's program turned out to be readings of
    # something else, and the segment says so in one pass.
    # PART 002 HAS NO HARNESS ANY MORE. src/NEUR2.PAS is the real program and
    # its segment matches the original's 128 bytes exactly. The walk did not
    # move, and that was PREDICTED before the work rather than discovered after:
    # our P2S1 is 32 bytes small and P2S2 112 large, a net +80 that displaces
    # the runtime whatever the program does. Part 002's 11 bytes are downstream
    # of those two, not of the harness.
    # PART 003 HAS NO HARNESS ANY MORE. src/NEUR3.PAS is the real program, and
    # its segment now matches the original's 336 bytes exactly -- but the walk
    # did not move, because our P3Tunnel is 144 bytes LARGER than the original's
    # 2,608 and that moves the runtime just as a harness did. Part 003's 34
    # far-call bytes are downstream of that, not of the harness.
    # PART 005 HAS NO HARNESS ANY MORE, AND IT WAS THE LAST ONE. src/NEUR5.PAS
    # is the real program; P5MAIN.PAS is gone with it. Its 224-byte segment came
    # out BYTE-IDENTICAL to the original's, the first program segment in this
    # corpus to do so, and the part went from 10,980 of 11,440 to every byte.
    #
    # SO THIS LIST IS EMPTY, and that is the finished state rather than a gap.
    # Every part now builds as its own program and RUNPART.BAT launches it; the
    # per-SCENE harnesses in SCENES above are still generated and still useful,
    # because a scene is not a program in the original either.
    # PART 006 HAS NO HARNESS ANY MORE. src/NEUR6.PAS is the real program --
    # the main body that P6MAIN.PAS held as a unit -- and part 006 went 99.6% to
    # 100.0% with 32 far-call bytes closing at once. Its one remaining byte is
    # the recorded je-form floor at 100f:07b7.
    # PART 007 HAS NO HARNESS ANY MORE. src/NEUR7.PAS is the real program --
    # the main body that P7MAIN.PAS held as a unit -- so the harness program and
    # the driver unit, neither of which the original has, are gone. That was
    # worth 10 of part 007's 12 unaligned bytes: 4,100 of 4,112 to 4,110, 99.7%
    # to 100.0%, because the runtime finally sits on its own paragraph and every
    # far call into it resolves. run/RUNPART.BAT launches it.

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
# AND IT DECLARES NOTHING, which is not tidiness. A PROGRAM's globals land at
# the FRONT of DGROUP's uninitialised region, ahead of every unit's, so anything
# a harness declares moves the part's first variable and every absolute
# reference in the part with it. Measured on part 004: `PrevExit : Pointer` and
# `F : file` between them put ColOfs at $01F6 where the original has $0172, and
# removing both took the coverage walk from 94.6% to 96.5%. A harness that
# declares one file record is measuring itself.
#
# So F is a local of the check below, and the handler ENDS the exit chain
# instead of restoring it -- which needs no saved pointer. The cost is that any
# handler installed before this one is skipped, which here means Crt's; this one
# does the substantive half of its job by putting the BIOS back in mode 3.
EXIT_PROC = """{ Runs on the way out of Halt, of a run-time error, or of a normal end --
  see the note in mktests.py, including why this ends the chain rather than
  restoring it. }
procedure RestoreTextMode; far;
begin
  ExitProc := nil;
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

{ No $E- here, deliberately: the _fpu originals' raw 9B+ESC x87 encodings
  are a post-build PATCH of the CD 3x emulator interrupts TP7 always emits
  -- the two variants are byte-identical apart from exactly those pairs --
  so the faithful build keeps the $E+ default. See dosbuild.py. }

uses %(uses)s, %(unit)s;

%(exit)s%(sayproc)s{ F IS A LOCAL. See the note on EXIT_PROC in mktests.py: a program-level file
  record displaces every variable in the part under test. }
procedure CheckData;
var
  F : file;
begin
  Assign(F, 'neurosis.dat');
  {$I-} Reset(F, 1); {$I+}
  if IOResult <> 0 then
  begin
    %(say)s('%(prog)s: neurosis.dat not found in the current directory.');
    %(say)s('%(pad)s  Run this from the run\\ folder.');
    Halt(1);
  end;
  Close(F);
end;

%(vars)sbegin
  CheckData;

  %(say)s('%(what)s');
  %(say)s('Press a key to start.');
  ReadKey;
%(hook)s
"""

TAIL = """
  %(say)s('Done.');
end.
"""


HOOK = """
  ExitProc := @RestoreTextMode;
"""


# Harnesses whose opening needs a variable of its own beyond the file check's
# F. Keyed by program name; the declaration lands in the main var block.
# Empty at present -- TP3S6 briefly used it for a palette loop that turned out
# to belong in Waves_LoadCurves itself.
# WHICH HARNESSES MUST PRINT THROUGH THE TEXT RTL, and it is a fact about the
# ORIGINALS rather than a preference. A Write or WriteLn anywhere puts a
# two-byte `0D 0A` constant in DGROUP, and the uninitialised region begins where
# the initialised one ENDS -- so its presence or absence moves every variable in
# the part under test by two. Measured across the nine shipped parts on 25 Aug
# 2026: only 000, 004 and 007 carry that constant. The other six do not, and a
# harness that writes text puts a byte in their data segment that the original
# has not got.
#
# So the default is `Say`, which prints through BIOS teletype (INT $10 function
# $0E) and touches no runtime -- the prompt survives and DGROUP is untouched.
# The parts below keep WriteLn because their originals DO link text output.
#
# PART 004 IS A STAND-IN AND IS RECORDED AS ONE. Its original writes text from
# somewhere our sources do not reproduce -- only the RTL references the constant,
# so the call site is not in a user segment we have read -- and until that is
# found the harness supplies the two bytes the original really has. Parts 000 and
# 007 keep it for the same reason, and both already rebuild with their data
# byte-identical. If the real call site turns up, remove the part from this set
# in the same commit that adds it.
# TPART7 is gone from this set with its harness; NEUR7 is a real program and
# prints nothing.
TEXT_RTL = {"TPART0"}

SAY_PROC = """{ PRINTS WITHOUT THE TEXT RTL, and that is the whole point of it. A single
  WriteLn anywhere in a harness puts a two-byte constant at the END of the
  initialised data segment, and the uninitialised region begins where the
  initialised one ENDS rather than where its paragraph padding ends -- so those
  two bytes move EVERY VARIABLE IN THE PART UNDER TEST by two. On part 003 that
  cost 752 bytes of the coverage walk, 90.6%% against 85.2%%, once the variable
  layout was otherwise correct, and it made the initialised image differ where
  it is otherwise byte-identical.

  Measured, 25 Aug 2026: `Write(s, #13, #10)` does NOT avoid it -- the same two
  bytes land at the same address. BIOS teletype does. INT $10 function $0E
  writes a character and touches no runtime, and the string literal itself
  lives in the CODE segment, where literals passed to Write already live.

  So the harness keeps its prompt AND leaves the data segment alone, which is
  why this is a generated helper rather than a choice between the two. }
procedure Say(const S : String);
var
  I, C : Byte;
begin
  for I := 1 to Length(S) do
  begin
    C := Ord(S[I]);        { BASM cannot index a reference parameter }
    asm
      MOV  AH, $0E
      MOV  AL, C
      XOR  BH, BH
      INT  $10
    end;
  end;
  asm
    MOV  AX, $0E0D       { carriage return }
    XOR  BH, BH
    INT  $10
    MOV  AX, $0E0A       { line feed }
    XOR  BH, BH
    INT  $10
  end;
end;

"""

EXTRA_VARS = {}


def write(prog, unit, entry, uses, opening, closing, what):
    # A scene harness inherits its part's answer: TP3S4 is part 003.
    part = "TPART" + (prog[2] if prog.startswith("TP") and prog[2:3].isdigit()
                      else "")
    rtl = prog in TEXT_RTL or part in TEXT_RTL
    say = "WriteLn" if rtl else "Say"
    text = (HEAD % dict(prog=prog, unit=unit, uses=uses, what=what,
                        pad=" " * len(prog), exit=EXIT_PROC, hook=HOOK,
                        say=say, sayproc="" if rtl else SAY_PROC,
                        vars=EXTRA_VARS.get(prog, ""))
            + opening
            + "  %s;\n\n" % entry
            + closing
            + TAIL % dict(say=say))
    # src/test/, not src/: these are harnesses, not the demo. build.toml's
    # identity glob reads them from there.
    out = SRC / "test" / (prog + ".PAS")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="ascii", newline="\r\n")
    print("  %-12s %s" % (prog + ".PAS", what))


for prog, unit, entry, uses, opening, closing, what in SCENES:
    write(prog, unit, entry, uses, opening, closing, what)

print("")
for prog, unit, entry, uses, what in PARTS:
    write(prog, unit, entry, uses, "", "", what)

print("\n  %d scene harnesses, %d part harnesses."
      % (len(SCENES), len(PARTS)))
