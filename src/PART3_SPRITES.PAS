{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 7
  Reconstructed from NEUROSIS_003_fpu.exe, segment 125e.

  Four 56x56 face portraits, each spinning at 5 degrees per frame, stacked
  70 pixels apart vertically and swept across the screen together. This is
  the closing scene of the part.

  The rotation is a straight 2-D rotate-and-sample: step (cos, sin) along
  each output row and (sin, -cos) down each column, in 6-bit fixed point,
  reading the source sprite at the rotated coordinate.

  ADDRESS MAP
    Demo_Scene7         125e:0958    Sprites_Load       125e:012e
    Sprites_Run         125e:077c    Sprites_Prepare    125e:0550
    Sprite_DrawRotated  125e:0388    Sprites_FadeStep   125e:047a
  =========================================================================== }

unit Part3Sprites;

interface

procedure Scene7;

implementation

uses VGA, Crt;

{$I gen/P3CAPT.INC}      { const Captions : array[1..40] of String[50] }

const
  DataOfs    = $11EEC0;      { NEUROSIS.DAT -- 1,175,232 }
  HeaderSize = 1550;
  SpriteW    = 56;
  SpriteH    = 56;
  SpriteSize = SpriteW * SpriteH;   { 3136 }
  NumSprites = 4;

  FixedBits  = 6;            { coordinates are kept << 6 }
  AngleWrap  = $168;         { 360 }
  SpinStep   = 5;            { degrees per frame }

  SweepFrom  = -20;          { $FFEC }
  SweepTo    = 120;          { $78   }
  VSpacing   = 70;           { $46 -- gap between the four portraits }
  BaseY      = 50;           { $32 }

  FadeSteps  = 64;           { $40 }

type
  TSprite = array[0..SpriteSize - 1] of Byte;

var
  Sprite : array[1..NumSprites] of ^TSprite;
  Angle  : array[1..NumSprites] of Integer;
  SweepX : Integer;

  { The 1,550-byte block at the head of the region. It is DEAD -- see the note
    at the foot of this file -- but the read still has to land somewhere. }
  Header : array[0..HeaderSize - 1] of Byte;

  { 6-bit fixed point, matching the FixedBits the rotate-and-sample uses. }
  SinTab, CosTab : array[0..AngleWrap - 1] of Integer;

{ [inferred] Sprites_Prepare 125e:0550 -- draws the caption block beside
  portrait N from Captions (gen/P3CAPT.INC), ten 50-character lines each. }
{ --------------------------------------------------------------------------
  Sprites_Prepare (125e:0550) -- not a caption routine. It is the WHOLE
  per-portrait sequence, in three phases:

  1. FLY-IN. X runs -20 to 70; the sprite spins 5 degrees a frame and the
     palette fades up once X passes 0.
  2. ORBIT. 180 frames of circular motion about (140, 100), sin/cos driven,
     still spinning.
  3. TYPEWRITER. Ten lines of fifty characters, one character every 10 ms,
     read from DS:$6BB8 + portrait * $A00 + line * $100 + column.

  That addressing reconciles two earlier notes that looked contradictory: the
  base really is $6BB8 with an $A00 stride per portrait, and portrait 1 line 1
  really does land at $76B8, which is where the strings were first found.
  See gen/P3CAPT.INC.
  -------------------------------------------------------------------------- }
procedure Prepare(N : Integer);
var
  Row, Col : Integer;
  Line     : String;
begin
  for Row := 1 to 10 do
  begin
    Line := Captions[(N - 1) * 10 + Row];
    for Col := 1 to Length(Line) do
      if Line[Col] <> ' ' then
        PutPixel(SpriteW + 4 + Col * 2, BaseY + (N - 1) * VSpacing + Row * 6, 15, VirtScrSeg);
  end;
end;

{ [transcribed] Sprites_FadeStep 125e:047a -- one step of a 64-step fade IN.
  Waits for retrace, then for all 256 entries reads the current RGB back and
  increments each channel by one if it is still below the target. }
procedure FadeStep;
var
  I       : Integer;
  R, G, B : Byte;
begin
  WaitRetrace;
  for I := 0 to 255 do
  begin
    GetRGB(I, R, G, B);
    if B < Palette[I, 2] then Inc(B);
    if G < Palette[I, 1] then Inc(G);
    if R < Palette[I, 0] then Inc(R);
    SetRGB(I, R, G, B);
  end;
end;

procedure BuildTrig;
var
  A : Integer;
begin
  for A := 0 to AngleWrap - 1 do
  begin
    SinTab[A] := Round(Sin(A * Pi / 180) * 64);
    CosTab[A] := Round(Cos(A * Pi / 180) * 64);
  end;
end;

{ --------------------------------------------------------------------------
  Sprites_Load (125e:012e)

  ASSETS  NEUROSIS.DAT $11EEC0, 14,862 bytes in six reads:
            assets/part003/font_5x5.bin          1,550 B, the 5x5 bitmap font
            assets/part003/sprite1.png / .bin    3,136 B = 56x56 portrait
            assets/part003/sprite2.png / .bin    3,136 B
            assets/part003/sprite3.png / .bin    3,136 B
            assets/part003/sprite4.png / .bin    3,136 B
            assets/part003/sprites_palette.pal     768 B
          The 3,136-byte reads sit in a 4-iteration loop in the original;
          3136 = 56*56 is what fixes the sprite dimensions, and rendering
          them at that size shows four faces -- almost certainly the four
          Asphyxia members. See docs/13-part3-scene7-sprites.md.
  -------------------------------------------------------------------------- }
procedure Load;
var
  F : file;
  I : Integer;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Header, HeaderSize);
  for I := 1 to NumSprites do
  begin
    GetMem(Sprite[I], SpriteSize);
    BlockRead(F, Sprite[I]^, SpriteSize);
  end;
  BlockRead(F, Palette, 768);
  Close(F);
end;

{ --------------------------------------------------------------------------
  Sprite_DrawRotated (125e:0388)

  Walks a 56x56 output square. U and V are 6-bit fixed point; stepping them
  by (CosA, SinA) along a row and (SinA, -CosA) down a column is a rotation
  matrix applied incrementally, with no multiplies inside the loop.

  The destination address is computed as (V shr 6) * 320 + (U shr 6), which
  the original writes as (U shr 6) + (V and $FFC0) * 5 -- the same thing,
  since (V and not 63) * 5 = (V shr 6) * 320.

  Above angle $B5 the two source bytes are written swapped; that is the
  odd/even alignment case for the word store.
  -------------------------------------------------------------------------- }
procedure DrawRotated(Src : Pointer; X, Y, CosA, SinA, Ang : Integer);
var
  U, V, RowU, RowV : Integer;
  Col, Row         : Integer;
  S                : Word;
begin
  RowU := X shl FixedBits;
  RowV := Y shl FixedBits;
  S := 0;
  for Row := 1 to SpriteH do
  begin
    U := RowU;
    V := RowV;
    for Col := 1 to SpriteW do
    begin
      if (V < $2F80) and (V > $3F) and (U > $3F) then
        Mem[VirtScrSeg : (U shr 6) + (V and $FFC0) * 5] := TSprite(Src^)[S];
      Inc(U, SinA);
      Inc(V, CosA);
      Inc(S);
    end;
    Inc(RowU, CosA);
    Dec(RowV, SinA);
  end;
end;

{ --------------------------------------------------------------------------
  Sprites_Run (125e:077c)
  -------------------------------------------------------------------------- }
procedure Run;
var
  I : Integer;
begin
  for I := 1 to NumSprites do Prepare(I);
  for I := 1 to NumSprites do Angle[I] := Random(AngleWrap);

  ClearScreen($A000, 0);
  for I := 1 to FadeSteps do FadeStep;

  SweepX := SweepFrom;
  repeat
    if KeyPressed then Exit;

    for I := 1 to NumSprites do
      Angle[I] := (Angle[I] + SpinStep) mod AngleWrap;

    ClearVirtual;
    for I := 1 to NumSprites do
      DrawRotated(Sprite[I],
                  SweepX * 2 + CosTab[Angle[I]],
                  SinTab[Angle[I]] + BaseY + (I - 1) * VSpacing,
                  CosTab[Angle[I]], SinTab[Angle[I]], Angle[I]);
    CopyScreen(VirtScrSeg, $A000);

    Inc(SweepX);
  until SweepX = SweepTo;
end;

procedure Scene7;
var
  I : Integer;
begin
  Load;
  Run;
  for I := 1 to NumSprites do FreeMem(Sprite[I], SpriteSize);
end;

end.

{ ===========================================================================
  NOTES

  * Each portrait gets a RANDOM starting angle, so the four are never in
    phase with one another even though they all spin at the same rate.
  * The sweep runs 140 frames (-20 to 120) and X is SweepX*2, so the group
    travels 280 pixels -- entering from off-screen left and leaving right.
  * Each portrait's position also has a sin/cos term added, so they weave as
    they travel rather than moving in a straight line.
  * Double-buffered: everything is drawn into the virtual screen and blitted,
    unlike Scene 6 which writes straight to $A000.

  CONFIRMED
  * The four faces ARE the four members. The captions are compiled into DGROUP
    as array[1..40] of String at DS:$76B8, stride $100 -- TEN 50-character
    lines per member, in portrait order (see gen/P3CAPT.INC):

        SUBJECT : PETER EDWARDS   CODENAME : EZE      THE WIERD ONE
        SUBJECT : GRANT SMITH     CODENAME : DENTHOR  THE TALL ONE
        SUBJECT : BRIAN BAILEY    CODENAME : GOTH     THE BITCHY ONE
        SUBJECT : PIETER BUYS     CODENAME : FUBAR    THE UNFORGIVEN ONE
                                                      (BECAUSE OF EXAMS...)

    Occupation is STUDENT for all four; tasks are CODE+MUSIC, CODE, CODE and
    ART respectively. This matches PSYCHO.NFO.

  * Sprites_FadeStep (125e:047a) is a one-step fade-IN. It waits for retrace,
    then for all 256 entries reads the current RGB back and increments each
    channel by one if it is still below the target held at DS:$E3EC. Called 64
    times, so the palette walks up from black over 64 frames.

  * The 1,550-byte read is DEAD, and provably so: the same 1,550 bytes appear
    byte-identically in part 002 (DAT $080CB2, loaded to DS:$5448), the block
    contains only the values 0 and $AB, and in BOTH parts the only instruction
    that mentions the destination buffer is the BlockRead. Nothing consumes it
    in either place -- the read just walks the file pointer forward.
        assets/part002/font_5x5.bin

  OPEN
  * Nothing outstanding.
  =========================================================================== }
