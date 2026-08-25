{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.005 scene 3, segment 1102.

  A 30 x 30 patch of a loaded picture, lifted into three dimensions and turned
  about one axis while the patch itself wanders around the picture and bounces
  off its edges. Each point is drawn in its own colour, and the pixel VALUE is
  added to the projected Y -- so the brighter a pixel, the further down the
  screen it lands, and the picture becomes a relief.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/26-part5-notes.md for the reading.

  ADDRESS MAP
    RenderPatch     1102:0000     Demo_Scene3     1102:035a
    Scene3_Run      1102:017e     (unit init)     1102:038c
    Setup           1102:02d1
    FixMul          1102:0391     SinCos          1102:11d9
    FixDiv          1102:03a5     RotatePoint     1102:128b
    the cosine table at CS:$03C5   Project         1102:13d9

  THE MATHS IS THE SAME OBJECT PARTS 001 AND 002 LINK. `SinCos`,
  `RotatePoint` and `Project` here are byte-identical to part 001's copies at
  1107:1804, 1107:18b6 and 1107:1a04 -- 16, 24 and 7 bytes differ across the
  three and every one of them is a DGROUP or table displacement. The table at
  CS:$03C5 is the same 901 entries of Round(cos(i/10 degrees) * 65536).

  It also showed that the module has FIVE routines and not three: FixMul at
  1102:0391 and FixDiv at 1102:03a5 sit ahead of the table in both binaries.
  Neither is called from Pascal in any part read so far -- they survive the
  link because an external OBJ is linked whole, not per procedure -- but they
  are part of the module and are now in src/asm/DEMOMATH.ASM.

  DGROUP
    DS:$a662  MCos1   DS:$a666  MSin1        DS:$a67a  MScale
    DS:$a66a  MCos2   DS:$a66e  MSin2        DS:$a67e  the picture, a Pointer
    DS:$a672  MCos3   DS:$a676  MSin3        DS:$a682  its segment
    DS:$a684  the palette, 768 bytes         DS:$a984  the file
    DS:$2d16  MViewH = 200   DS:$2d18  MViewW = 320  -- initialised data
  =========================================================================== }

{$S-}   { 1102:0000 opens ENTER $26,0 with no stack check. }

unit P5S3;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }
{$A-}   { data alignment off -- measured, see the note in P2S2.PAS }

{$G+}   { 286: RenderPatch 1102:0000 opens ENTER $26; the whole segment is
          ENTER-framed. }

interface

procedure Scene3;

implementation

uses Crt, VGA, FixMath;   { 124a:0000 IntToFixed, 124a:0034 RealToFixed }

const
  Patch    = 30;                  { 1102:0004 -- the patch is 30 x 30 }
  DataOfs  = $001646E5;           { 1102:030d pushes $0016 then $46E5 }
  ScaleR   = 1600.0;              { 1102:035d builds this Real in AX:BX:DX }
  DepthZ   = 200;                 { 1102:00f6 }
  LiftY    = -50;                 { 1102:00d7 pushes -$32 }
  YBias    = 500;                 { 1102:012f subtracts $1F4 }
  FullTurn = 3600;                { tenths of a degree }

type
  TPal768 = array[0..767] of Byte;
  { 1102:011f and 1102:012c subtract using AX alone, so only the LOW word of
    the projected coordinate is ever looked at. }
  TLongRec = record Lo, Hi : Word end;

var
  { The six words the maths module reads. The order here is the order in the
    binary: 1102:0025 fills the pair at $a662 and 1102:0022 the pair at $a66a,
    so the ANGLE goes into the SECOND pair and the other two are zeroed. }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  MScale : LongInt;                       { DS:$a67a }

  Pic    : Pointer;                       { DS:$a67e }
  PicSeg : Word;                          { DS:$a682 }
  Pal    : TPal768;                       { DS:$a684 }
  F      : file;                          { DS:$a984 }

const
  { DS:$2d16 and DS:$2d18, initialised data. Project halves both, so these are
    the FULL view size and not the centre.

    DECLARED H FIRST, and the addresses are the whole reason: the original
    puts MViewH at $2d16 and MViewW at $2d18, so W-then-H transposes them.
    They cannot move to P5S1 either -- DEMOMATH.OBJ's EXTRN resolves by
    Pascal scope in the unit that links it, and declaring them there gives
    `Undefined external (MViewW)`. }
  MViewH : Word = 200;
  MViewW : Word = 320;

{$L DEMOMATH.OBJ}
{ 19 bytes and then a NOP, which pads FixDiv up to 1102:03a5. The pad is
  the assembler aligning the next PROC, not part of the routine.
  @asm 005 1102:0391 +19 FixMul }
procedure FixMul(A, B : LongInt);                         external;
{ @asm 005 1102:03a5 +32 FixDiv }
procedure FixDiv(A, B : LongInt);                         external;
{ @asm 005 1102:11d9 +178 SinCos5 }
procedure SinCos(A : Integer; var C, S : LongInt);        external;
{ @asm 005 1102:128b +334 RotatePoint5 }
procedure RotatePoint(var X, Y, Z : LongInt);             external;
{ @asm 005 1102:13d9 +166 Project5 }
procedure Project(var X, Y, Z : LongInt);                 external;

{ --------------------------------------------------------------------------
  1102:0000 -- one frame of the patch.

  (CX, CY) is where the patch sits in the picture; Angle is in tenths of a
  degree. Every one of the 900 points is read out of the picture, turned, and
  plotted -- there is no mesh and no interpolation, so what you see is 900
  loose pixels.

  Two details that are easy to get wrong by inference. The patch coordinate is
  used TWICE and differently: `Col - 15` picks the pixel out of the picture
  when added to CX, and the SAME `Col - 15` is the 3-D X. And the height is
  not applied in three dimensions at all -- Y is the constant -50 going in,
  and the pixel value is added to the PROJECTED Y at 1102:0132, after the
  divide.
  -------------------------------------------------------------------------- }
{ EIGHT BYTES OF PARAMETERS -- 1102:017b is `RET 8`, and this build was
  emitting `RET $0A`. Four words, not three-plus-a-LongInt: dropping Seg_
  instead was tried and measured 13 bytes WORSE, because the pixel read
  through the parameter had been matching all along. So it is ANGLE that is
  two bytes here, and SinCos takes an Integer anyway. }
procedure RenderPatch(CX, CY : Integer; Angle : Integer; Seg_ : Word);
var
  { IN THE ORDER THE RECORDED OFFSETS GIVE. Locals go downward from BP in
    declaration order, so sorting the offsets ascending recovers the original's
    var block. Size and Half were declared first and took the slots nearest BP,
    which pushed X, Y and Z down four bytes each -- and the three pointers
    pushed for Project are where this part's largest span begins. }
  Col, Row       : Integer;       { [BP-2],   [BP-4]   }
  X, Y, Z        : LongInt;       { [BP-8], [BP-$0C], [BP-$10] }
  Pixel          : Byte;          { [BP-$11] }
  Size, Half     : Integer;       { [BP-$1B], [BP-$1D] }
  ScreenX        : Integer;       { [BP-$1F] }
  ScreenY        : Integer;       { [BP-$21] }
  LimY, LimX     : Integer;       { [BP-$23], [BP-$25] }
  { no recorded offset for these two, so they go last -- and nine bytes
    between Pixel and Size are still unaccounted for }
  SX, SY         : Integer;
begin
  Size := Patch;                                 { 1102:0004 }
  Half := Size div 2;                            { 1102:0010 }

  SinCos(Angle, MCos2, MSin2);                   { 1102:0022 -- the only turn }
  SinCos(0, MCos1, MSin1);                       { 1102:0031 }
  SinCos(0, MCos3, MSin3);                       { 1102:0040 }

  LimY := Size;
  for Row := 1 to LimY do
  begin
    LimX := Size;
    for Col := 1 to LimX do
    begin
      Pixel := 0;                                { 1102:0075 }
      SX := CX + Col - Half;                     { 1102:0079 }
      if (SX <= 319) and (SX >= 0) then          { 1102:0082, 1102:0087 }
      begin
        SY := CY + Row - Half;                   { 1102:008c }
        if (SY <= 199) and (SY >= 0) then        { 1102:0095, 1102:009b }
          Pixel := Mem[Seg_ : YOfs[SY] + SX];    { 1102:00ad }
      end;

      X := IntToFixed(Col - Half);               { 1102:00ba }
      Z := IntToFixed(Row - Half);               { 1102:00cc }
      Y := IntToFixed(LiftY);                    { 1102:00d9 }
      RotatePoint(X, Y, Z);                      { 1102:00f3 }
      Z := Z + IntToFixed(DepthZ);               { 1102:0101 }
      Project(X, Y, Z);                          { 1102:0119 }

      ScreenX := 320 - Integer(TLongRec(X).Lo);            { 1102:011c }
      ScreenY := Integer(TLongRec(Y).Lo) - YBias + Pixel;  { 1102:012c }

      if (ScreenX > 0) and (ScreenX < 319) and   { 1102:0137, 1102:013d }
         (ScreenY > 0) and (ScreenY < 199) then  { 1102:0144, 1102:014a }
        PutPixel(ScreenX, ScreenY, Pixel, VirtScrSeg);   { 1102:015f }
    end;
  end;
end;

{ --------------------------------------------------------------------------
  1102:017e -- the frame loop.

  The patch wanders diagonally at two pixels a frame and reflects off all four
  edges of the picture. At frame 100 it stops moving and the rotation jumps to
  three degrees a frame; at 220 it starts moving again and the rotation drops
  back to one degree. From frame 500 the palette dims a step each frame, and
  at 564 it stops. A keypress jumps the frame count straight to 500, so the
  fade-out is what a key buys you.
  -------------------------------------------------------------------------- }
procedure Run;
var
  { IN THE ORDER THE RECORDED OFFSETS GIVE -- $2, $4, $6, $8, $A, $C, $E, then
    the Boolean at $F, which is why Running goes LAST and not first. Seven
    words and a byte is fifteen, and the frame is ENTER $10.

    ANGLE IS TWO BYTES. It cannot be a LongInt: DY_ is at [BP-8] and Angle at
    [BP-$0A], so there is no room, and 1102:0190 zeroes it with a single word
    store. That agrees with RenderPatch, whose RET 8 leaves two bytes for it. }
  CX, CY   : Integer;             { [BP-2], [BP-4] }
  DX_, DY_ : Integer;             { [BP-6], [BP-8] }
  Angle    : Integer;             { [BP-$0A] }
  AngStep  : Integer;             { [BP-$0C] }
  Frame    : Integer;             { [BP-$0E] }
  Running  : Boolean;             { [BP-$0F] }
begin
  Running := True;                               { 1102:0182 }
  CX      := 160;                                { 1102:0186 }
  CY      := 100;                                { 1102:018b }
  Angle   := 0;                                  { 1102:0190 }
  AngStep := 0;                                  { 1102:0195 }
  Frame   := 0;                                  { 1102:019a }
  DX_     := 2;                                  { 1102:019f }
  DY_     := 2;                                  { 1102:01a4 }
  repeat
    { 1102:01a9 -- the test is in the binary and is redundant: the loop only
      goes round again while Running is set. Transcribed as it stands. }
    if Running then Inc(Frame);

    if KeyPressed then                           { 1102:01b2 }
    begin
      Frame := 500;                              { 1102:01bb }
      ReadKey;                                   { 1102:01c0 }
    end;
    if Frame = 100 then                          { 1102:01c5 }
    begin
      DX_ := 0;  DY_ := 0;  AngStep := 30;       { 1102:01cb }
    end;
    if Frame = 220 then                          { 1102:01da }
    begin
      DX_ := 2;  DY_ := 2;  AngStep := 10;       { 1102:01e1 }
    end;
    if Frame >= 500 then                         { 1102:01f0 }
    begin
      PaletteDim(@Pal);                          { 1102:01fc }
      SetPalette768(@Pal);                       { 1102:0206 }
    end;
    if Frame >= 564 then Running := False;       { 1102:020b }

    CX := CX + DX_;                              { 1102:0216 }
    CY := CY + DY_;                              { 1102:021c }
    Angle := (Angle + AngStep) mod FullTurn;     { 1102:0222 }

    if CX < 0   then begin CX := 0;   DX_ := -DX_ end;   { 1102:0244 }
    if CX > 319 then begin CX := 319; DX_ := -DX_ end;   { 1102:0257 }
    if CY < 0   then begin CY := 0;   DY_ := -DY_ end;   { 1102:026b }
    if CY > 199 then begin CY := 199; DY_ := -DY_ end;   { 1102:0283 }

    ClearScreen(VirtScrSeg, 0);                  { 1102:0298 }
    RenderPatch(CX, CY, Angle, PicSeg);          { 1102:02aa }
    CopyScreen(VirtScrSeg, $A000);               { 1102:02b4 }
  until not Running;                             { 1102:02b9 }
end;

{ --------------------------------------------------------------------------
  1102:02d1 -- the picture and its palette.

  ASSETS  NEUROSIS.DAT $001646E5:
            64,000 bytes  a 320 x 200 picture
            768 bytes     its palette
  -------------------------------------------------------------------------- }
procedure Setup;
begin
  GetMem(Pic, 64000);                            { 1102:02d5 }
  PicSeg := Seg(Pic^);                           { 1102:02e4 }
  Assign(F, 'neurosis.dat');                     { 1102:02f7 }
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Pic^, 64000);                     { 1102:0329 }
  BlockRead(F, Pal, SizeOf(Pal));                { 1102:033f }
  Close(F);                                      { 1102:0349 }
  SetPalette768(@Pal);                           { 1102:0353 }
end;

{ 1102:035a -- the scene. }
procedure Scene3;
begin
  MScale := RealToFixed(ScaleR);                 { 1102:035d -- 1600.0 }
  Setup;                                         { 1102:0374 }
  Run;                                           { 1102:0377 }
  FreeMem(Pic, 64000);                           { 1102:0385 }
end;

{ 1102:038c -- the unit's initialisation is empty. }
begin
end.
