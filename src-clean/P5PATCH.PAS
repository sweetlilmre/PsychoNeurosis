{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.005 scene 3, segment 1102.

  A 30 x 30 patch of a loaded picture, lifted into three dimensions and turned
  about one axis while the patch itself wanders around the picture and bounces
  off its edges. Each point is drawn in its own colour, and the pixel VALUE is
  added to the projected Y -- so the brighter a pixel, the further down the
  screen it lands, and the picture becomes a relief.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/26-part5-notes.md for the reading.

  THE MATHS IS THE SAME OBJECT PARTS 001 AND 002 LINK. `SinCos`,
  `RotatePoint` and `Project` here are byte-identical to part 001's copies at
 -- 16, 24 and 7 bytes differ across the
  three and every one of them is a DGROUP or table displacement. The table at
 is the same 901 entries of Round(cos(i/10 degrees) * 65536).

  The module has FIVE routines and not three. FixMul and FixDiv sit ahead of
  the table, and neither is called from Pascal in any part read so far -- they
  survive the link because an external OBJ is linked whole rather than per
  procedure. They are part of the module and are in src/asm/DEMOMATH.ASM. }

{$S-}   { opens ENTER $26,0 with no stack check. }

unit P5PATCH;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }
{$A-}   { data alignment off -- measured, see the note in P2SOLID.PAS }

{ 286 instructions are permitted. }
{$G+}

interface

procedure Scene3;

implementation

uses Crt, VGA, FixMath;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

const
  Patch    = 30;                  { the patch is 30 x 30 }
  DataOfs  = DAT_P5_PATCHPIC;   { where this scene's picture starts }
  ScaleR   = 1600.0;              { builds this Real in AX:BX:DX }
  DepthZ   = 200;
  LiftY    = -50;                 { pushes -$32 }
  YBias    = 500;                 { subtracts $1F4 }
  FullTurn = 3600;                { tenths of a degree }

type
  TPal768 = array[0..767] of Byte;
  { subtract using AX alone, so only the LOW word of
    the projected coordinate is ever looked at. }
  TLongRec = record Lo, Hi : Word end;

var
  { The six words the maths module reads, in the order the binary has them --
    the ANGLE goes into the SECOND pair and the other two are zeroed. }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  MScale : LongInt;

  Pic    : Pointer;
  PicSeg : Word;
  Pal    : TPal768;
  F      : file;

const
  { initialised data. Project halves both, so these are
    the FULL view size and not the centre.

    DECLARED H FIRST, and the addresses are the whole reason: the original
    puts MViewH at $2d16 and MViewW at $2d18, so W-then-H transposes them.
    They cannot move to P5MESH either -- DEMOMATH.OBJ's EXTRN resolves by
    Pascal scope in the unit that links it, and declaring them there gives
    `Undefined external (MViewW)`. }
  MViewH : Word = 200;
  MViewW : Word = 320;

{$L DEMOMATH.OBJ}
procedure FixMul(A, B : LongInt);                         external;
procedure FixDiv(A, B : LongInt);                         external;
procedure SinCos(A : Integer; var C, S : LongInt);        external;
procedure RotatePoint(var X, Y, Z : LongInt);             external;
procedure Project(var X, Y, Z : LongInt);                 external;

{ --------------------------------------------------------------------------
  one frame of the patch.

  (CX, CY) is where the patch sits in the picture; Angle is in tenths of a
  degree. Every one of the 900 points is read out of the picture, turned, and
  plotted -- there is no mesh and no interpolation, so what you see is 900
  loose pixels.

  Two details that are easy to get wrong by inference. The patch coordinate is
  used TWICE and differently: `Col - 15` picks the pixel out of the picture
  when added to CX, and the SAME `Col - 15` is the 3-D X. And the height is
  not applied in three dimensions at all -- Y is the constant -50 going in,
  and the pixel value is added to the PROJECTED Y, after the divide.
  -------------------------------------------------------------------------- }
{ EIGHT BYTES OF PARAMETERS -- four words, not three plus a LongInt. So the
  ANGLE is two bytes here, which is what SinCos takes anyway. }
{ THE PARAMETERS ARE PX AND PY, NOT CX AND CY, and the reason is the asm block
  below: inside BASM `CX` is a REGISTER, so `MOV AX, CX` would assemble as the
  register move and not the parameter load, silently. The caller's own variables
  keep their names -- only these two are renamed, and only because they are read
  from assembler. }
procedure RenderPatch(PX, PY : Integer; Angle : Integer; Seg_ : Word);
var
  { DECLARATION ORDER IS FRAME ORDER, and this block is in the original's.
    Locals go downward from BP as they are declared, so moving any of these
    moves every one below it. }
  { THE TWO SLOTS AT THE BOTTOM ARE NOT DECLARATIONS AT ALL -- they are the
    two `for` loops' upper bounds, each evaluated once into a temporary because
    neither limit is constant. Declaring LimY and LimX as variables produces
    both the variables AND the temporaries, which is four bytes too many. }
  Col, Row       : Integer;
  X, Y, Z        : LongInt;
  Pixel          : Byte;
  { EIGHT SPARE BYTES, AND THEY ARE ONE DEAD BLOCK. There are no SX and SY
    variables here: the clip-and-sample below is hand assembler and holds both
    coordinates in registers. }
  Spare          : array[1..8] of Byte;   { never read }
  Size, Half     : Integer;
  ScreenX        : Integer;
  ScreenY        : Integer;
  { the two slots below this are the compiler's, not ours }
begin
  Size := Patch;
  Half := Size div 2;

  SinCos(Angle, MCos2, MSin2);                   { the only turn }
  SinCos(0, MCos1, MSin1);
  SinCos(0, MCos3, MSin3);

  for Row := 1 to Size do
  begin
    for Col := 1 to Size do
    begin
      Pixel := 0;
      { ----------------------------------------------------------------------
clip the source point and sample it. HAND ASSEMBLER,
        transcribed verbatim, and THREE tells say so independently:

        And ours was wrong in a way that mattered beyond the byte count: with
        YOfs a Word array and SX an Integer, `YOfs[SY] + SX` promotes to LONGINT,
        so ours computed the screen offset in 32 bits (CWD, a CX:BX pair) where
        the original's ADD DI,AX is 16.

        EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

            SX := PX + Col - Half;
            if (SX <= 319) and (SX >= 0) then
            begin
              SY := PY + Row - Half;
              if (SY <= 199) and (SY >= 0) then
                Pixel := Mem[Seg_ : YOfs[SY] + SX];
            end;
        ---------------------------------------------------------------------- }
      asm
              MOV     AX, PX
              ADD     AX, Col
              SUB     AX, Half                { 007f  AX := the column, kept  }
              CMP     AX, 319
              JG      @@Skip
              CMP     AX, 0                   { 0087  the LONG form           }
              JL      @@Skip
              MOV     BX, PY
              ADD     BX, Row
              SUB     BX, Half                { 0092  BX := the row, kept     }
              CMP     BX, 199
              JG      @@Skip
              CMP     BX, 0                   { 009b  and the SHORT form      }
              JL      @@Skip
              ADD     BX, BX                  { 00a0  a word index            }
              MOV     DI, [BX + OFFSET YOfs]  { 00a2  DI := Row * 320         }
              ADD     DI, AX                  { 00a6    + the column, 16-bit  }
              MOV     AX, Seg_
              MOV     ES, AX
              MOV     AL, ES:[DI]             { 00ad  the source pixel        }
              MOV     Pixel, AL
      @@Skip:                                 { 00b3 is the next statement    }
      end;

      X := IntToFixed(Col - Half);
      Z := IntToFixed(Row - Half);
      Y := IntToFixed(LiftY);
      RotatePoint(X, Y, Z);
      Z := Z + IntToFixed(DepthZ);
      Project(X, Y, Z);

      ScreenX := 320 - Integer(TLongRec(X).Lo);
      ScreenY := Integer(TLongRec(Y).Lo) - YBias + Pixel;

      if (ScreenX > 0) and (ScreenX < 319) and
         (ScreenY > 0) and (ScreenY < 199) then
        PutPixel(ScreenX, ScreenY, Pixel, VirtScrSeg);
    end;
  end;
end;

{ --------------------------------------------------------------------------
  the frame loop.

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

    ANGLE IS TWO BYTES, not a LongInt -- which agrees with RenderPatch, whose
    eight bytes of parameters leave room for exactly two. }
  CX, CY   : Integer;
  DX_, DY_ : Integer;
  { A WORD, NOT AN INTEGER, and AngStep beside it is signed -- so the `mod`
    that follows is a 32-bit divide of a mixed sum rather than a plain one.

    THE OPERAND ORDER FOLLOWS FROM IT TOO. The Integer is the one PARKED in
    CX:BX and the Word is the one left in AX:DX, so the parked one is written
    SECOND: the source is `Angle + AngStep` and not the other way round. }
  Angle    : Word;
  AngStep  : Integer;
  { A WORD, NOT AN INTEGER, so the two comparisons below are unsigned. It
    makes no difference to behaviour -- Frame runs 0..564 and never goes
    negative -- but it is a different branch instruction either way. }
  Frame    : Word;
  Running  : Boolean;
begin
  Running := True;
  CX      := 160;
  CY      := 100;
  Angle   := 0;
  AngStep := 0;
  Frame   := 0;
  DX_     := 2;
  DY_     := 2;
  repeat
    { the test is in the binary and is redundant: the loop only
      goes round again while Running is set. Transcribed as it stands. }
    if Running then Inc(Frame);

    if KeyPressed then
    begin
      Frame := 500;
      ReadKey;
    end;
    if Frame = 100 then
    begin
      DX_ := 0;  DY_ := 0;  AngStep := 30;
    end;
    if Frame = 220 then
    begin
      DX_ := 2;  DY_ := 2;  AngStep := 10;
    end;
    if Frame >= 500 then
    begin
      PaletteDim(@Pal);
      SetPalette768(@Pal);
    end;
    if Frame >= 564 then Running := False;

    { `Inc`, NOT AN ASSIGNMENT -- and it is the opposite way round from
      P1LOGO, so the rule is per site rather than per unit. `Inc` adds straight
      into memory; `CX := CX + DX_` loads, adds and stores back.

      P1LOGO's two bouncer updates went the other way: there the ORIGINAL wrote
      the assignment and recomputed the subscript three times, and Inc was the
      shorter form we had to give up. The ADD's operand direction names which
      was written -- ADD [mem],reg is Inc, ADD reg,[mem] with a store after is
      the assignment -- and it has now been read in both directions in one
      corpus. }
    Inc(CX, DX_);
    Inc(CY, DY_);
    Angle := (Angle + AngStep) mod FullTurn;

    if CX < 0   then begin CX := 0;   DX_ := -DX_ end;
    if CX > 319 then begin CX := 319; DX_ := -DX_ end;
    if CY < 0   then begin CY := 0;   DY_ := -DY_ end;
    if CY > 199 then begin CY := 199; DY_ := -DY_ end;

    ClearScreen(VirtScrSeg, 0);
    RenderPatch(CX, CY, Angle, PicSeg);
    CopyScreen(VirtScrSeg, $A000);
  until not Running;
end;

{ --------------------------------------------------------------------------
  the picture and its palette.

  ASSETS  NEUROSIS.DAT $001646E5:
            64,000 bytes  a 320 x 200 picture
            768 bytes     its palette
  -------------------------------------------------------------------------- }
procedure Setup;
var
  { 130 BYTES OF FRAME AND NOT ONE OF THEM IS REFERENCED. The routine touches
    no local at all in its whole body, so this is pure declaration -- a file
    record and one more word, which is what part 005's and part 006's other
    scenes declare and leave unopened in the same position. The file this
    routine actually uses is the unit-level global.

    The TYPES are a guess and only the total is measured. }
  Unread : file;                  { never referenced }
  Spare  : Integer;               { never referenced }
begin
  GetMem(Pic, 64000);
  PicSeg := Seg(Pic^);
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Pic^, 64000);
  BlockRead(F, Pal, SizeOf(Pal));
  Close(F);
  SetPalette768(@Pal);
end;

{ the scene. }
procedure Scene3;
begin
  MScale := RealToFixed(ScaleR);                 { 1600.0 }
  Setup;
  Run;
  FreeMem(Pic, 64000);
end;

{ the unit's initialisation is empty. }
begin
end.
