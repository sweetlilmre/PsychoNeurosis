{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 1, the logo and bouncing sprites

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit P1S1;

interface

procedure Scene1;

implementation

uses VGA, Crt, DemoVT;

const
  NumBouncers = 10;
  BounceW     = 40;        { 1012:0311 blits 40 rows of 40 bytes }
  BounceH     = 40;

type
  TSaveBank = array[1..NumBouncers, 0..BounceH * BounceW - 1] of Byte;
  TCell     = array[0..BounceH * BounceW - 1] of Byte;
  TLensTab  = array[0..BounceH * BounceW - 1] of Word;

var
  { The saved background under each bouncer. There is NO sprite bitmap: the
    bouncers are lenses over whatever they are sitting on. }
  Under   : ^TSaveBank;
  { DS:$4FD6 -- the single working cell the lens gathers into. }
  Cell    : TCell;
  { DS:$4304 -- the gather table, built once by BuildLens. }
  LensTab : TLensTab;

{ [transcribed] Scene 1 loads a 768-byte palette then a 320x200 screen
  straight into the virtual screen -- NEUROSIS.DAT $000000, 64,768 bytes. }
procedure LoadLogo;
var
  F : file;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, 0);
  BlockRead(F, Palette, SizeOf(Palette));
  SetPalette;
  BlockRead(F, Mem[VirtScrSeg : 0], 64000);
  Close(F);
end;

{ --------------------------------------------------------------------------
  The ten bouncing sprites -- Bounce_Run 1012:03e3, with the blit at
  1012:0311 and the matching save at 1012:02bc.

  Transcribed. An earlier reconstruction had the right IDEA -- save the
  background, draw, restore in reverse -- but the wrong numbers:

  * the sprites are 40 x 40, not 20 x 20;
  * they are drawn CENTRED, at (X - 20, Y - 20);
  * the blit is opaque (REP MOVSB), with no transparency test;
  * save and restore are the SAME routine, just with source and destination
    swapped -- restoring is a blit out of the saved-background buffer.

  The save slots are 1,641 bytes apart ($669) at DS:$FC81 + N * $669, which is
  more than the 1,600 a 40 x 40 block needs; the slack is not used.

  Erasing in REVERSE order is what makes overlapping sprites restore
  correctly, and is only necessary because of the save/restore scheme.
  -------------------------------------------------------------------------- }
procedure BlitSprite(X, Y : Integer; Src : Pointer; Segment : Word);
var
  Row : Integer;
  P   : ^Byte;
begin
  P := Src;
  for Row := 0 to BounceH - 1 do
  begin
    Move(P^, Mem[Segment : (Y - 20 + Row) * ScrWidth + X - 20], BounceW);
    Inc(LongInt(P), BounceW);
  end;
end;

procedure SaveUnder(X, Y : Integer; Dest : Pointer; Segment : Word);
var
  Row : Integer;
  P   : ^Byte;
begin
  P := Dest;
  for Row := 0 to BounceH - 1 do
  begin
    Move(Mem[Segment : (Y - 20 + Row) * ScrWidth + X - 20], P^, BounceW);
    Inc(LongInt(P), BounceW);
  end;
end;

{ --------------------------------------------------------------------------
  1012:0004 -- build the lens table.

  The bouncing objects are NOT sprites. Nothing in this scene loads any sprite
  data: Logo_Load reads a 768-byte palette and one 320x200 screen and stops.
  Each bouncer is a MAGNIFYING LENS over whatever it is sitting on.

  The table has one word per pixel of the 40 x 40 block, and EVERY pixel gets
  an entry -- that is the part an earlier reconstruction got wrong, which is
  why it drew a solid square with a lens inside it.

      X*X + Y*Y >  300   IDENTITY. The gather reads the pixel back from its
                         own position, the blit writes it straight back, and
                         the corner is invisible. There is no transparency
                         test anywhere: the blit is a flat REP MOVSB.

      X*X + Y*Y <= 300   the lens proper. Read off the x87 at 1012:0116:

                             Scale := R / (R + Sqrt(R*R - (X*X + Y*Y - 400)) + K)
                             SX    := Round(Scale * X)
                             SY    := Round(Scale * Y)

                         with R = 40 (the word at DS:$0002) and K = 1.0 (the
                         single at CS:$0000), so

                             Scale = 40 / (41 + Sqrt(2000 - (X*X + Y*Y)))

                         which runs from about 0.467 at the centre to 0.486 at
                         the rim -- a roughly even 2x magnification with a
                         slight barrel to it.

  The original walks X and Y from 0 up and writes all four quadrants each
  iteration; the formula is symmetric, so walking the full range once is the
  same thing and reads better.
  -------------------------------------------------------------------------- }
const
  LensR   = 40;        { DS:$0002 }
  LensK   = 1.0;       { CS:$0000 }
  LensCut = 300;       { the disc: X*X + Y*Y <= 300 }
  LensOfs = 400;       { the 20*20 term inside the square root }

procedure BuildLens;
var
  X, Y, D2, SX, SY : Integer;
  Scale            : Real;
begin
  for Y := -20 to 19 do
    for X := -20 to 19 do
    begin
      D2 := X * X + Y * Y;
      if D2 > LensCut then
      begin
        { outside the disc -- map the pixel to itself, so the blit is a no-op }
        SX := X;
        SY := Y;
      end
      else
      begin
        Scale := LensR / (LensR + Sqrt(LensR * LensR - (D2 - LensOfs)) + LensK);
        SX := Round(Scale * X);
        SY := Round(Scale * Y);
      end;
      LensTab[(Y + 20) * BounceW + (X + 20)] := (SY + 20) * BounceW + (SX + 20);
    end;
end;

{ [transcribed] 1012:0366 -- gather the working cell for bouncer N out of the
  background saved under it, through the lens table. 1,600 bytes, walked
  backwards. }
procedure BuildCell(N : Integer);
var
  I : Integer;
begin
  for I := BounceH * BounceW - 1 downto 0 do
    Cell[I] := Under^[N, LensTab[I]];
end;

{ Draw order per frame, from Bounce_Run: save the background, build the lens
  cell from it, blit it. Erasing is the same blit with the saved background as
  the source -- which is why the erase pass runs in REVERSE order. }
procedure DrawSprite(N, X, Y : Integer);
begin
  SaveUnder(X, Y, @Under^[N], VirtScrSeg);
  BuildCell(N);
  BlitSprite(X, Y, @Cell, VirtScrSeg);
end;

procedure EraseSprite(N, X, Y : Integer);
begin
  BlitSprite(X, Y, @Under^[N], VirtScrSeg);
end;

{ ===========================================================================
  Scene 1 -- logo and bouncing sprites            Demo_Scene1  1012:0678
  =========================================================================== }

const
  BounceMinX  = 21;   BounceMaxX = 299;
  BounceMinY  = 21;   BounceMaxY = 179;
  BounceFrames = 300;      { $12C -- 1012:05b1, the scene's whole lifetime }
  ScrollFrom   = 140;      { $8C  -- 1012:05a7, after which it slides out }
  ScrollStep   = 2;        { pixels per frame }

var
  BX, BY, BDX, BDY : array[1..NumBouncers] of Integer;

{ --------------------------------------------------------------------------
  1012:03bd -- ScrollLeft

  Slides the whole virtual screen two pixels to the left, one row at a time:

      DS = ES = VirtScrSeg ; DI = 0 ; SI = 2
      200 times:  REP MOVSW with CX = $9F      318 bytes = 159 words
                  SI += 2 ; DI += 2            318 + 2 = one 320-byte row

  The last two bytes of every row are deliberately NOT copied, so they hold
  whatever was there before -- and Demo_Scene1 drew two black vertical lines
  down x = 318 and x = 319 before the loop started. That black column is what
  feeds in from the right as the picture leaves.

  160 scrolling frames at 2 pixels is 320 -- exactly one screen, so the scene
  ends the instant the last of the logo clears the left edge. Leaving this out
  is why the scene simply sat there and bounced forever.
  -------------------------------------------------------------------------- }
procedure ScrollLeft;
var
  Row : Integer;
  D   : Word;
begin
  D := 0;
  for Row := 0 to ScrHeight - 1 do
  begin
    Move(Mem[VirtScrSeg : D + ScrollStep], Mem[VirtScrSeg : D],
         ScrWidth - ScrollStep);
    Inc(D, ScrWidth);
  end;
end;

{ --------------------------------------------------------------------------
  Demo_Scene1 (1012:0678)

  ASSETS  NEUROSIS.DAT $000000, 64,768 bytes:
            assets/part001/logo_palette.pal    768 B
            assets/part001/asphyxia_logo.png   64,000 B -- the chrome/green
                                               ASPHYXIA logo with reflection
          See docs/14-part001-intro.md.
  -------------------------------------------------------------------------- }
procedure Scene1;
var
  F     : file;
  I     : Integer;
  Frame : Integer;
begin
  GetMem(Under, SizeOf(TSaveBank));
  BuildLens;
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  LoadLogo;                             { palette + 320x200 screen }
  Close(F);

  { Two black vertical lines down the right edge -- the artwork evidently
    has rubbish in its last two columns. }
  DrawLine(319, 199, 319, 0, 0, VirtScrSeg);
  DrawLine(318, 199, 318, 0, 0, VirtScrSeg);
  CopyScreen(VirtScrSeg, $A000);

  for I := 1 to NumBouncers do
  begin
    BDX[I] := Random(3) + 2;
    BDY[I] := Random(3) + 2;
    BX[I]  := Random(250) + 30;
    BY[I]  := Random(150) + 30;
  end;

  { 1012:0442 -- a counted loop, not an open one. }
  Frame := 1;
  repeat
    for I := 1 to NumBouncers do DrawSprite(I, BX[I], BY[I]);
    CopyScreen(VirtScrSeg, $A000);
    { erase in REVERSE order so overlapping sprites restore correctly }
    for I := NumBouncers downto 1 do EraseSprite(I, BX[I], BY[I]);

    for I := 1 to NumBouncers do
    begin
      Inc(BX[I], BDX[I]);
      Inc(BY[I], BDY[I]);
      { four separate tests in the original, 1012:0518..1012:058b -- X and Y
        are checked against their own low and high bounds independently }
      if BX[I] < BounceMinX then BDX[I] := -BDX[I];
      if BX[I] > BounceMaxX then BDX[I] := -BDX[I];
      if BY[I] < BounceMinY then BDY[I] := -BDY[I];
      if BY[I] > BounceMaxY then BDY[I] := -BDY[I];
    end;

    if KeyPressed then                  { 1012:0597 }
    begin
      ReadKey;
      Exit;
    end;

    if Frame > ScrollFrom then ScrollLeft;    { 1012:05a7 }
    Inc(Frame);
  until Frame > BounceFrames;                 { 1012:05b1 }
end;

end.
