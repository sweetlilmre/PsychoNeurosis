"""Split PART1_INTRO.PAS into one unit per scene, the way part 003 already is.

Each scene becomes a unit that can be compiled and run on its own, so a fault
can be located to a scene before the part is assembled.

    P1S1  logo and bouncing sprites      Demo_Scene1  1012:0678
    P1S2  "ASPHYXIA PRESENTS" + comet    Demo_Scene2  1082:056f
    P1S3  mosaic pixelate                Demo_Scene3  10e3:0206
    P1S4  rotating 3-D text              Demo_Scene4  1107:0977
    P1S5  vector objects and wipe        Demo_Scene5  12c5:0a89
    P1INTRO  the driver

Declarations follow their scene rather than sitting in one shared block, which
is what makes the units independent.
"""
import pathlib

SRC = pathlib.Path("src")
W = (SRC / "PART1_INTRO.PAS").read_text(encoding="ascii", errors="replace")


def at(anchor):
    """Index of the comment banner containing `anchor`."""
    i = W.index(anchor)
    j = W.rfind("{ ", 0, i)
    return j if j >= 0 else i


def seg(a, b=None):
    return W[at(a): at(b) if b else len(W)].rstrip() + "\n"


HEAD = """{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, %s

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit %s;

interface

procedure %s;

implementation

uses VGA, Crt, DemoVT;
"""

A_LOGO = "Scene 1 loads a 768-byte palette"
A_REVEAL = "1082:01d0 -- redraws the characters"
A_MOSAIC = "Mosaic block sampling."
A_TRAILS = "Scene 4's point machinery"
A_FIXED = "1483:0000 -- Math_IntToReal is MISNAMED."
A_S1 = "Scene 1 -- logo and bouncing sprites"
A_S2 = 'Scene 2 -- "ASPHYXIA PRESENTS"'
A_S3 = "Scene 3 -- mosaic pixelate"
A_S4 = "Scene 4 -- the welcome message"
A_S5 = "Scene 5 -- vector objects and wipe"
A_MAIN = "Main body (1000:003c)"

U = {}

U["P1S1.PAS"] = (HEAD % ("scene 1, the logo and bouncing sprites",
                         "P1S1", "Scene1")) + """
const
  NumBouncers = 10;
  BounceW     = 40;        { 1012:0311 blits 40 rows of 40 bytes }
  BounceH     = 40;
  BounceMinX  = 21;   BounceMaxX = 299;
  BounceMinY  = 21;   BounceMaxY = 179;

type
  TSpriteBank = array[1..NumBouncers, 0..BounceH * BounceW - 1] of Byte;

var
  Bouncer : ^TSpriteBank;
  Under   : ^TSpriteBank;

""" + seg(A_LOGO, A_REVEAL) + "\n" + seg(A_S1, A_S2) + "\nend.\n"

U["P1S2.PAS"] = (HEAD % ('scene 2, "ASPHYXIA PRESENTS"', "P1S2", "Scene2")) + """
const
  CometFrames = 10;
  CometW      = 65;
  CometH      = 48;
  CometSize   = CometW * CometH;   { 3120 -- the stride in the loaded buffer }
  RevealOfs   = 614;               { $266 -- where DrawRevealed lands }

type
  TWorkBuf = array[0..5199] of Byte;

var
  BackdropSeg : Word;
  WorkBuf     : ^TWorkBuf;
  CometBank   : array[0..CometFrames * CometSize - 1] of Byte;

""" + seg(A_REVEAL, A_MOSAIC) + "\n" + seg(A_S2, A_S3) + "\nend.\n"

U["P1S3.PAS"] = (HEAD % ("scene 3, the mosaic pixelate", "P1S3", "Scene3")) \
    + "\n" + seg(A_MOSAIC, A_TRAILS) + "\n" + seg(A_S3, A_S4) + "\nend.\n"

U["P1S4.PAS"] = (HEAD % ("scene 4, the welcome message as rotating 3-D text",
                         "P1S4", "Scene4")) + """
const
  MaxFontChar  = 58;        { the font holds 59 glyphs, 0..58 }
  AngleWrap    = 3600;      { angles are in TENTHS of a degree }
  BannerStep   = 60;        { 6.0 degrees per frame }
  BannerSteps  = 8;
  BannerDist   = 256;
  BannerScale  = 256;
  BannerColour = 15;

type
  { 13 bytes per trail entry, 18 entries per point -- $EA apart in DGROUP }
  TTrailEntry  = array[0..12] of Byte;
  TBannerPoint = record
    X, Y, Z : Integer;
    Visible : Boolean;
  end;

var
  Angle : Integer;
  Point : array[1..8] of TBannerPoint;
  Trail : array[0..7, 1..18] of TTrailEntry;   { DS:$5BD8 }
  Font  : array[0..MaxFontChar, 1..8, 1..8] of Byte;

""" + seg(A_TRAILS, A_FIXED) + "\n" + seg(A_S4, A_S5) + "\nend.\n"

U["P1S5.PAS"] = (HEAD % ("scene 5, the vector objects and wipe",
                         "P1S5", "Scene5")) + """
{$I gen/P1VECT.INC}      { const VecLogoA, VecGlobe : array[.., 1..3] of Integer }

const
  VectorStep  = 20;      { 2.0 degrees per frame }
  VectorWrap  = 3590;
  GlobePoints = 36;
  LogoPoints  = 48;

var
  Angle       : Integer;
  OrbitAngle  : Integer;
  BackdropSeg : Word;

""" + seg(A_FIXED, A_S5) + "\n" + seg(A_S5, A_MAIN) + "\nend.\n"

U["P1INTRO.PAS"] = '''{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, the intro.

  The driver only. Each scene is its own unit so it can be compiled and run in
  isolation:

      P1S1  logo and bouncing sprites      1012:0678
      P1S2  "ASPHYXIA PRESENTS" + comet    1082:056f
      P1S3  mosaic pixelate                10e3:0206
      P1S4  rotating 3-D text              1107:0977
      P1S5  vector objects and wipe        12c5:0a89

  Same architecture as part 003: a main body of scenes each followed by a
  keyboard flush, then the music fade.
  =========================================================================== }

unit P1Intro;

interface

procedure RunIntro;

implementation

uses VGA, Crt, DemoVT, P1S1, P1S2, P1S3, P1S4, P1S5;

procedure RunIntro;
var
  Saved : Byte;
begin
  SetMode13h;
  VirtScrAlloc;
  MusicInit;

  Scene1;      FlushKeys;
  Scene2;      FlushKeys;
  Scene3;      FlushKeys;
  Scene4;      FlushKeys;
  Scene5;      FlushKeys;

  { music fade -- identical to part 003 }
  Saved := GetVolume;
  repeat
    SetVolume(GetVolume - 1);
    Delay(10);
  until GetVolume = 0;
  MusicStop;
  SetVolume(Saved);

  VirtScrFree;
  SetRGB(0, 0, 0, 7);
  Halt(0);
end;

end.
'''

for name, text in U.items():
    (SRC / name).write_text(text, encoding="ascii", newline="\r\n")
    print("  wrote %-13s %4d lines" % (name, text.count("\n")))
