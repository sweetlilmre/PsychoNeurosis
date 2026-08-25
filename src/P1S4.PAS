{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 4.

  Transcribed from the disassembly of segment 1107 and 12b2, not inferred.
  Every routine below carries the address it was read from.

  WHAT THE SCENE ACTUALLY IS
  --------------------------
  A field of 144 balls arranged as a flat 18 x 8 grid, tumbling in 3-D over a
  scrolling starfield, with the message written across the grid one column at
  a time -- the letters flow leftwards through the balls because the LIT flag
  marches along each row's trail while the coordinates stay put.

  An earlier reconstruction had this as "rotating 3-D text" built from glyph
  outlines. It is not. Banner_BuildPoints (1107:07a2) copies the same literal
  string eight times --

      CS:$078B  'OOOOOOOOOOOOOOOOOO'   18 characters

  -- into eight row buffers at DS:$6A33 stride $100, then walks them and emits
  one point per character. Eight rows of eighteen is exactly the 144.
  =========================================================================== }

{$N+}   { Demo_Scene4's scale arithmetic is x87 -- 1107:097b FILD/FDIV/FMUL. }
{$G+}   { 286 instructions: REP OUTSB in SetPalette768 (1107:0011). The
          original targets 386 and above. }

unit P1S4;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

interface

procedure Scene4;

implementation

uses VGA, Crt, DemoVT, FixMath;

{ --------------------------------------------------------------------------
  1107:0000 -- SetPalette768(P). HAND ASSEMBLER, verbatim.

  Byte for byte VGA.SetPalette768 -- 1436:0083 in part 002, 11e3:0230 in
  part 004. Part 004 scene 4 keeps its own copy because it is a separate
  unit; the shared one is stripped from this part.
  point the DAC write index at colour 0 and let REP OUTSB stream all 768
  components at it, the hardware auto-incrementing between entries.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := 0;
      for I := 0 to 767 do Port[$3C9] := TPal768(P^)[I];

  Scene 4 is the only part 001 scene with its own copy; the others go through
  VGA.SetPalette.
  -------------------------------------------------------------------------- }
{ @asm 001 1107:0000 }
procedure SetPalette768(P : Pointer); assembler;
asm
  PUSH DS                 { DS is about to point at the caller's buffer    }
  LDS  SI, P              { DS:SI := the 768-byte palette                  }
  MOV  DX, $3C8           { the DAC WRITE index register                   }
  MOV  AL, 0              { start at colour 0                              }
  OUT  DX, AL             { select it -- the DAC auto-increments from here }
  INC  DX                 { DX := $3C9, the DAC data register              }
  MOV  CX, $300           { 768 bytes = 256 entries of R, G, B             }
  REP  OUTSB              { write them all out from DS:SI                  }
  POP  DS                 { restore our data segment                       }
end;

const
  TrailRows  = 8;
  TrailLen   = 18;
  TrailCount = TrailRows * TrailLen;        { 144 }
  LastEntry  = TrailCount + 1;              { 1107:0446 runs 1..145 }
  BlobW      = 7;
  BlobH      = 7;
  BlobPixels = BlobW * BlobH;               { 49 = $31 }
  StarCount  = 90;                          { $5A }
  FontChars  = 59;                          { chars $20..$5A }
  FontBias   = 32;                          { see DrawStep }
  AngleWrap  = 3600;                        { angles are TENTHS of a degree }
  BannerStep = 60;                          { $3C -- 6.0 degrees per column }
  GridPoint  = 'OOOOOOOOOOOOOOOOOO';        { CS:$078B }
  MarkerA    = '*';                         { CS:$079E }
  MarkerB    = 'O';                         { CS:$07A0 }

  { The clip box the blitter reads from DS:$000C..$0013. }
  { DS:$000C..$0013 -- INITIALISED DATA, read straight out of the image:
    00 00  C7 00  00 00  3F 01, the full 320 x 200 screen. The blit reads all
    four from DGROUP, so they are typed constants rather than plain consts: a
    plain const folds into the instruction and stops matching. The order is
    the binary's -- top, bottom, left, right. }
  ClipTop    : Integer = 0;        { DS:$000C }
  ClipBottom : Integer = 199;      { DS:$000E }
  ClipLeft   : Integer = 0;        { DS:$0010 }
  ClipRight  : Integer = 319;      { DS:$0012 }

type
  { 13 bytes in the original: three 16.16 fixed values and a flag byte.
    Entry 0 is not a point -- it is the object's TRANSLATION vector, which is
    why 1107:0446 adds it to every rotated point and never rotates it. }
  TTrail = record
    X, Y, Z : LongInt;          { 16.16 fixed point -- hence 13 bytes }
    Flag    : Byte;
  end;

  { 7 bytes in the original: X, Y, D as words and the flag as a byte. }
  TOut = record
    X, Y, D : Integer;
    Flag    : Byte;
  end;

  { 51 bytes in the original ($33): a two-byte (W, H) header the blitter reads
    out of the sprite itself, then 49 pixels. }
  TBlob = record
    W, H : Byte;
    Pix  : array[1..BlobPixels] of Byte;
  end;

  { 9 bytes in the original. }
  TStar = record
    X, Y, DX, Spare : Integer;
    Colour          : Byte;
  end;

  TFont = array[0..FontChars - 1, 1..8, 1..8] of Byte;

var
  { DS:$5AD2 -- unit-level, see Load. THIS ADDRESS IS THE MEASUREMENT THAT SAYS
    part 001 is data-blocked, and it is worth writing down because every span in
    segment 1107 turns on it. The routine's CODE now matches -- same calls, same
    order, no I/O check -- and the two operands differ: the original pushes
    DS:$5AD2 for the file and DS:$5B6A for the buffer, this build $0952 and
    $354C. The two gaps are 20,864 and 9,758, and their being DIFFERENT rules
    out a uniform shift: it is the sizes of what comes before, not a single
    missing block.

    Where it comes from is partly mapped. This part's DGROUP order is right --
    reverse of P1Intro's uses clause puts P1S5 first, and P1S5's constants are
    at $001C and $01A8 exactly as recorded. But P1S5's VARIABLES are at
    $A5B6..$AB58 in the original, and nothing declared in that unit accounts for
    the distance. The load image is 1,536 bytes BIGGER here than the original's
    while the BSS is 23,520 bytes SMALLER, so there is initialised data here
    that belongs in BSS and a large block of variables that is missing
    altogether. }
  F : file;
  { DS:$5BCC -- entry 0 is the translation, 1..144 are the grid. }
  Trail : array[0..LastEntry] of TTrail;
  { DS:$632F, stride 7 }
  Outp  : array[0..LastEntry] of TOut;
  { DS:$80C2, stride $33 }
  Blob  : array[1..LastEntry] of TBlob;
  { DS:$9DDB, stride 9 }
  Star  : array[1..StarCount] of TStar;

  { DS:$7233, 3,776 bytes = 59 glyphs of 8 x 8 }
  Font  : ^TFont;
  { DS:$5B6A and DS:$5B9B, 49 bytes each }
  ProfileA, ProfileB : array[1..BlobPixels] of Byte;
  { DS:$672D }
  Pal   : array[0..767] of Byte;

{ --------------------------------------------------------------------------
  THE SHARED 386 MATHS MODULE.

  SinCos, Rotate and Project are 386 code and cannot be written in Turbo
  Pascal's built-in assembler, which stops at the 286. They live in
  src/asm/DEMOMATH.ASM, are assembled by TASM and linked in here with the $L directive --
  which is what the original does: 1107:1804, 1107:18B6 and 1107:1A04 are the
  same code as scene 5's and part 002 scene 2's, once per unit.

  The nine names below are the module's EXTRNs, so they have to be declared
  BEFORE the $L directive and spelled exactly this way.
  -------------------------------------------------------------------------- }
  { DS:$5B52/$5B56, $5B5A/$5B5E, $5B62/$5B66 -- cos then sin, per axis }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  { DS:$0018 -- the projection scale, 16.16, set by Demo_Scene4 }
  MScale : LongInt;
  { DS:$80F3 }
  Angle : Integer;

const
  { DS:$0014 = 320 and DS:$0016 = 200, initialised data. Project halves both,
    so these are the FULL view size and not the centre. }
  MViewW : Word = 320;
  MViewH : Word = 200;

{$L DEMOMATH.OBJ}

{ --------------------------------------------------------------------------
  1107:1804 -- SinCos(Angle : Integer; var C, S : LongInt)

  The angle is in tenths of a degree, wrapped into 0..3600. The table is 901
  entries of 16.16 COSINE and one quadrant of it serves both functions, read
  forwards or backwards with the signs flipped per quadrant. The FIRST var
  parameter receives the COSINE -- checked against 1107:18b6, which needs
  DS:$5B52 in the cosine position for the matrix to come out orthogonal.

  1107:18b6 -- Rotate(var X, Y, Z : LongInt)

  Three concatenated 2-D rotations in 16.16, using the six values SinCos left
  in DS:$5B52..$5B69:

      about X, by A1       Y1 := Y*C1 + Z*S1        Z1 := Z*C1 - Y*S1
      about Y, by A2       X2 := X*C2 - Z1*S2       Z2 := Z1*C2 + X*S2
      about Z, by A3       X3 := X2*C3 + Y1*S3      Y3 := Y1*C3 - X2*S3

  1107:1a04 -- Project(var X, Y, Z : LongInt)

      Sx := Round(X/Z * Scale) + MViewW div 2
      Sy := MViewH div 2 - Round(Y/Z * Scale)

  All three are in src/asm/DEMOMATH.ASM, commented there. An earlier version
  of this file had them as Pascal over Reals, which is a different program:
  the original's multiply is 32x32->64 taking the MIDDLE 32 bits, and its
  divide builds a 48-bit dividend so the quotient comes out 16.16.
  -------------------------------------------------------------------------- }
procedure SinCos(A : Integer; var C, S : LongInt);      external; { 1107:1804 }
procedure RotatePoint(var X, Y, Z : LongInt);           external; { 1107:18B6 }
procedure Project(var X, Y, Z : LongInt);               external; { 1107:1A04 }

{ IntToFixed and FixedToInt come from FixMath (segment 1483) -- this scene
  had local copies of both. 1107:052E calls 1483:0099, the ROUNDING one. }

{ --------------------------------------------------------------------------
  1107:0446 -- Transform(Base; A1, A2, A3)

  For entries 1..145: copy the 13-byte record out, rotate it, add the
  TRANSLATION held in entry 0, project, and write the 7-byte output record.

  Note what is NOT rotated: entry 0. The loop starts at 1, and the add at
  1107:04bf reads ES:[DI], ES:[DI+4], ES:[DI+8] with DI still pointing at the
  base of the array -- entry 0. It is the object position, not a point.
  -------------------------------------------------------------------------- }
procedure Transform(A1, A2, A3 : Integer);
var
  I       : Integer;
  X, Y, Z : LongInt;
begin
  SinCos(A1, MCos1, MSin1);                 { -> DS:$5B52, $5B56 }
  SinCos(A2, MCos2, MSin2);                 { -> DS:$5B5A, $5B5E }
  SinCos(A3, MCos3, MSin3);                 { -> DS:$5B62, $5B66 }

  for I := 1 to LastEntry do
  begin
    X := Trail[I].X;  Y := Trail[I].Y;  Z := Trail[I].Z;
    RotatePoint(X, Y, Z);
    X := X + Trail[0].X;
    Y := Y + Trail[0].Y;
    Z := Z + Trail[0].Z;
    Outp[I].D := FixedToInt(Z);             { 1107:052e }
    Project(X, Y, Z);
    { both come back zero-extended, so the low word carries the sign }
    Outp[I].X    := Integer(X);
    Outp[I].Y    := Integer(Y);
    Outp[I].Flag := Trail[I].Flag;
  end;
end;

{ --------------------------------------------------------------------------
  1107:0287 -- DepthSort(Lo, Hi), nested inside 1107:03d7

  A Hoare quicksort over the 7-byte output records, keyed on the D field, and
  it sorts DESCENDING: the scan at 1107:02c7 advances while key[i] > pivot.
  Far balls are therefore drawn first and near ones over the top of them.

  This was missing entirely from the earlier reconstruction, so the grid drew
  in index order and the depth cueing was wrong wherever the field folded over
  itself. The records are swapped whole -- three 7-byte Moves via a temporary.
  -------------------------------------------------------------------------- }
procedure DepthSort(Lo, Hi : Integer);
var
  I, J : Integer;
  P    : Integer;
  T    : TOut;
begin
  I := Lo;  J := Hi;
  P := Outp[(Lo + Hi) div 2].D;
  repeat
    while Outp[I].D > P do Inc(I);
    while Outp[J].D < P do Dec(J);
    if I <= J then
    begin
      if Outp[I].D <> Outp[J].D then
      begin
        T := Outp[I];  Outp[I] := Outp[J];  Outp[J] := T;
      end;
      Inc(I);  Dec(J);
    end;
  until I > J;
  if Lo < J then DepthSort(Lo, J);
  if I < Hi then DepthSort(I, Hi);
end;

{ --------------------------------------------------------------------------
  1107:03e7 -- BuildBlobs(Out)

  Sort by depth first (1107:03d7 calls DepthSort(1, 144)), then give every
  record its sprite according to the flag the sort carried along with it:

      flag <> 0  ->  DS:$5B9B   the lit profile
      flag  = 0  ->  DS:$5B6A   the unlit profile

  49 bytes each, into the 51-byte blob at DS:$80C4 + I*$33 -- past the (W, H)
  header, which Banner_Load already set to 7, 7.
  -------------------------------------------------------------------------- }
procedure BuildBlobs;
var
  I : Integer;
begin
  DepthSort(1, TrailCount);                 { 1107:03d7 -> 1107:0287 }
  for I := 1 to LastEntry do
    if Outp[I].Flag <> 0 then
      Move(ProfileB, Blob[I].Pix, BlobPixels)
    else
      Move(ProfileA, Blob[I].Pix, BlobPixels);
end;

{ --------------------------------------------------------------------------
  12b2:0000 -- StarInit(C0, C1, C2, Speed)

  Demo_Scene4 pushes 8, 9, 10, 1 in that order, so the three colours are 8, 9
  and 10 and the base speed is 1. Ninety stars, each given a random position
  and one of three depth bands:

      band 0   colour C0   dx := Speed
      band 1   colour C1   dx := Speed * 2
      band 2   colour C2   dx := Speed * 3

  The earlier reconstruction never called this at all, so every star sat at
  (0,0) in colour 0 and the starfield was invisible.
  -------------------------------------------------------------------------- }
procedure StarInit(C0, Ca, Cb, Speed : Byte);
var
  I : Integer;
begin
  Randomize;
  for I := 1 to StarCount do
  begin
    Star[I].X     := Random(319);
    Star[I].Y     := Random(199);
    Star[I].Spare := 0;
    case Random(3) of
      0 : begin Star[I].Colour := C0;  Star[I].DX := Speed;     end;
      1 : begin Star[I].Colour := Ca;  Star[I].DX := Speed * 2; end;
      2 : begin Star[I].Colour := Cb;  Star[I].DX := Speed * 3; end;
    end;
  end;
end;

{ [transcribed] 12b2:00c0 -- StarStep. X := X + DX, wrapping on 0 and 319. }
procedure StarStep;
var
  I, X : Integer;
begin
  for I := 1 to StarCount do
  begin
    X := Star[I].X + Star[I].DX;
    if X < 0 then Inc(X, 319)
    else if X > 319 then Dec(X, 319);
    Star[I].X := X;
  end;
end;

{ [transcribed] 12b2:00f1 -- StarDraw(Segment). One byte per star through the
  row-offset table at DS:$AB5A. No clipping: the ranges above guarantee it. }
procedure StarDraw(Segment : Word);
var
  I : Integer;
begin
  for I := 1 to StarCount do
    Mem[Segment : Star[I].Y * ScrWidth + Star[I].X] := Star[I].Colour;
end;

{ --------------------------------------------------------------------------
  1107:0199 -- the clipped transparent sprite blit. HAND ASSEMBLER, verbatim,
  and SHARED SOURCE: the routine is src/asm/BLITCLIP.INC, because part 006
  scene 2 compiles the same text at 100f:0000 -- byte for byte, our addresses
  being that unit's plus $199. It sits here, between Banner_Load and
  DrawBlobs, rather than at the head of a segment of its own, which is how we
  know the original shared the SOURCE and let each unit compile its own copy.
  -------------------------------------------------------------------------- }
{ @asm 001 1107:0199 +170 Blit }
{$I BLITCLIP.INC}

{ [transcribed] 1107:0245 -- blit blobs 1..144. Note 145 is transformed and
  given a sprite but never drawn; the loop counter is a BYTE ([BP-1], CMP
  against $90 at 1107:027f) and so is declared one here. }
procedure DrawBlobs;
var
  I : Byte;
begin
  for I := 1 to TrailCount do
    Blit(@Blob[I], Outp[I].X, Outp[I].Y, VirtScrSeg);
end;

{ [transcribed] 1107:0562 -- FrameStep(A1, A2, A3). Straight pass-through to
  Transform with the array base DS:$5BCC, then the rest of the frame. }
procedure FrameStep(A1, A2, A3 : Integer);
begin
  Transform(A1, A2, A3);            { 1107:0446 }
  BuildBlobs;                       { 1107:03e7 }
  StarStep;                         { 12b2:00c0 }
  StarDraw(VirtScrSeg);             { 12b2:00f1 }
  DrawBlobs;                        { 1107:0245 }
  CopyScreen(VirtScrSeg, $A000);    { 1107:0596 }
end;

{ --------------------------------------------------------------------------
  1107:059f -- ShiftTrails

  Moves the FLAG byte only, never the coordinates:

      for Row := 0 to 7 do
        for J := 2 to 18 do
          Trail[Row*18 + J - 1].Flag := Trail[Row*18 + J].Flag

  The grid is fixed in space; what travels along it is the lit state. That is
  why the message flows through the balls instead of the balls flying.
  -------------------------------------------------------------------------- }
procedure ShiftTrails;
var
  Row, J, K : Integer;
begin
  for Row := 0 to TrailRows - 1 do
    for J := 2 to TrailLen do
    begin
      K := Row * TrailLen + J;
      Trail[K - 1].Flag := Trail[K].Flag;
    end;
end;

{ --------------------------------------------------------------------------
  1107:0600 -- ShowString(S)

  For every character, eight steps -- one per column of the 8 x 8 glyph. Each
  step lights the head of all eight rows from that column of the glyph, shifts
  every trail along, draws a frame and advances the angle by 6 degrees.

  THE FONT INDEX. The original computes

      Font[Ord(Ch) * 64 + Row * 8 + Step]     base DS:$6A2A

  but Banner_Load reads the glyphs to DS:$7233, which is $809 = 2,057 bytes
  higher. 2057 = 32*64 + 9, so the effective index is

      (Ord(Ch) - 32) * 64 + (Row - 1) * 8 + (Step - 1)

  -- a clean 8 x 8 glyph with a bias of 32, exactly like the font in scene 2.
  59 glyphs covers $20..$5A, space through 'Z'. The earlier reconstruction
  indexed by raw Ord and read 2K past the end of the font for any letter.

  THE TRAIL HEAD is entry Row*18, i.e. the LAST entry of each row -- 1107:0685
  computes Row * $12 * $D. New columns therefore enter at the right of the grid
  and march left.
  -------------------------------------------------------------------------- }
procedure ShowString(S : String);
var
  Ch, Step, Row : Integer;
  G             : Integer;
begin
  for Ch := 1 to Length(S) do
    for Step := 1 to 8 do
    begin
      G := Ord(S[Ch]) - FontBias;
      if (G < 0) or (G >= FontChars) then G := 0;
      for Row := 1 to TrailRows do
        if Font^[G, Row, Step] <> 0 then
          Trail[Row * TrailLen].Flag := 1
        else
          Trail[Row * TrailLen].Flag := 0;

      ShiftTrails;                          { 1107:06af }
      FrameStep(0, Angle, Angle);           { 1107:06bc -- note the ZERO }
      ClearScreen(VirtScrSeg, 0);           { 1107:06c5 }

      Inc(Angle, BannerStep);
      if Angle > AngleWrap then Dec(Angle, AngleWrap);

      if KeyPressed then Exit;              { 1107:06e4 }
    end;
end;

{ [transcribed] 1107:076e -- the three lines, from CS:$070A, $072F and $074E. }
procedure BannerRun;
begin
  ShowString('HELLO AND WELCOME TO ASPHYXIAS FIRST');
  ShowString(' MEGADEMO, PSYCHO NEUROSIS!!! ');
  ShowString(' NOW SIT BACK AND ENJOY!!!     ');
end;

{ --------------------------------------------------------------------------
  1107:07a2 -- Banner_BuildPoints

  THE MISSING INITIALISER. Without it every trail coordinate is zero, all 144
  balls project to the same pixel, and the scene shows one ball.

  Eight row buffers at DS:$6A33 (stride $100) each get a copy of the SAME
  literal, CS:$078B = 'OOOOOOOOOOOOOOOOOO'. The walk then emits a point for
  every character equal to '*' (CS:$079E) or 'O' (CS:$07A0) -- and since every
  character is 'O', all 144 are emitted and the '*' arm never fires. Whatever
  the strings once spelled, by 1994 they were a plain rectangle.

      Trail[i].X := (Col - 1) * 10 - 90        1107:08c0
      Trail[i].Y := 32 - (Row - 1) * 8         1107:08dd
      Trail[i].Z := 0                          1107:08fe
      Trail[i].Flag := 0                       1107:090d

  giving X over -90..80 in steps of 10 and Y over 32..-24 in steps of 8. The
  counter stops at $91, and then entry 0 -- the translation -- is set:

      Trail[0] := (0, 0, 2000)                 1107:094e
  -------------------------------------------------------------------------- }
procedure BuildPoints;
var
  Rows  : array[1..TrailRows] of String;
  Row   : Integer;
  Col   : Integer;
  Idx   : Integer;
  C     : Char;
  Done  : Boolean;
begin
  for Row := 1 to TrailRows do
    Rows[Row] := GridPoint;

  Idx  := 1;
  Done := False;
  for Row := 1 to TrailRows do
  begin
    if Done then Break;
    for Col := 1 to Length(Rows[Row]) do
    begin
      C := Rows[Row][Col];
      if (C = MarkerA) or (C = MarkerB) then
      begin
        Trail[Idx].X    := IntToFixed((Col - 1) * 10 - 90);
        Trail[Idx].Y    := IntToFixed(32 - (Row - 1) * 8);
        Trail[Idx].Z    := IntToFixed(0);
        Trail[Idx].Flag := 0;
        Inc(Idx);
        if Idx > TrailCount then
        begin
          Done := True;
          Break;
        end;
      end;
    end;
  end;

  Trail[0].X := IntToFixed(0);
  Trail[0].Y := IntToFixed(0);
  Trail[0].Z := IntToFixed(2000);
end;

{ --------------------------------------------------------------------------
  1107:0025 -- Banner_Load. NEUROSIS.DAT $03A8E0, four reads:

      3,776   the font, 59 glyphs of 8 x 8         -> DS:$7233
        768   palette                              -> DS:$672D
         49   the unlit profile                    -> DS:$5B6A
         49   the lit profile                      -> DS:$5B9B

  Then blobs 2..144 get a copy of the UNLIT profile and blobs 1..144 get their
  (W, H) header set to 7, 7 -- which is where the 7 x 7 size comes from.

  1107:00b3..1107:0111 is a pair of loops that read each profile byte and, if
  non-zero, write it straight back to itself. Dead code; left out.
  -------------------------------------------------------------------------- }
procedure Load;
var
  { THE FILE RECORD IS A GLOBAL, not a local. 1107:007f pushes DS:$5AD2 as the
    file for the second BlockRead -- a data-segment address, where a local
    would be LEA'd off SS. It is declared beside the unit's other data below. }
  I : Integer;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $0003A8E0);
  BlockRead(F, Font^, SizeOf(TFont));
  BlockRead(F, Pal, 768);
  BlockRead(F, ProfileA, BlobPixels);
  BlockRead(F, ProfileB, BlobPixels);
  Close(F);

  for I := 2 to TrailCount do
    Move(ProfileA, Blob[I].Pix, BlobPixels);
  for I := 1 to TrailCount do
  begin
    Blob[I].W := BlobW;
    Blob[I].H := BlobH;
  end;
  Blob[LastEntry].W := BlobW;
  Blob[LastEntry].H := BlobH;

  ClearScreen(VirtScrSeg, 0);
  WaitRetrace;

  SetPalette768(@Pal);                { 1107:0000 }
end;

{ --------------------------------------------------------------------------
  1107:0977 -- Demo_Scene4

      Scale := (ScreenWidth / 2) * 10          = 1600.0, into DS:$0018
      StarInit(8, 9, 10, 1)                    12b2:0000
      Banner_Load                              1107:0025
      Banner_BuildPoints                       1107:07a2
      Banner_Run                               1107:076e

  The two constants are single-precision at CS:$096F = 2.0 and CS:$0973 = 10.0.
  With Z = 2000 that puts the grid across x 88..224 and y 74..119.
  -------------------------------------------------------------------------- }
procedure Scene4;
begin
  New(Font);
  MScale := Round((ScrWidth / 2.0) * 10.0 * 65536.0);
  Angle := 0;

  StarInit(8, 9, 10, 1);
  Load;
  BuildPoints;
  BannerRun;

  Dispose(Font);
end;

end.
