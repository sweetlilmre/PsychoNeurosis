{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 3
  Reconstructed from NEUROSIS_003_fpu.exe, segment 1139.

  A rotating 3-D point object that morphs between shapes, drawn in 320x400
  Mode-X with hardware page flipping, and faded to black at the end.

  Everything here is fixed-point integer -- 16.14 sin/cos from a lookup table
  and a 32-bit divide for the perspective. No floating point at all.

  THE SHAPE DATA IS NOT IN NEUROSIS.DAT. It is compiled into the executable as
  typed constants in DGROUP, which is why Scene 3 never appears in the DAT
  access map. Layout:

    DS:$02A8   sine table, 450 entries of 16.14 fixed point
               (cos is the same table read 90 entries in -- hence the $035C
                base, exactly 180 bytes = 90 words later)
    DS:$0636   shape data, slots of 4800 bytes (800 points x 6), of which the
               first 765 points of a slot are drawn

  Shapes used, identified by rendering the raw vertex data:

    slot 0  $0636   SPHERE     X,Y,Z all -800..800   (meridians + parallels)
    slot 4  $5136   CUBE       X,Y,Z all -400..400
    slot 5  $63F6   FLAT GRID  X,Z -1000..1000, Y -400..400

  So the scene runs sphere -> cube -> plane -> cube -> sphere. The clean
  symmetric ranges also confirm the 6-byte record is three signed words in
  X, Y, Z order.

  ADDRESS MAP
    Demo_Scene3       1139:03b4    Morph_InitScene       1139:02fe
    Morph_SetAngles   1139:0000    Morph_StepAngles      1139:0035
    Morph_TransformPoint 1139:0096 ModeX_PlotPixel       1139:01bb
    Morph_DrawShape   1139:01f9    Morph_DrawMorph       1139:021d
    ModeX_ClearPage   1139:02a2    ModeX_FlipPage        1139:02c3
    VGA_Set400Lines   1139:02f2    Morph_FadeStep        1139:0365
    VGA_SetPalette768 1139:0335    VGA_GetPalette768     1139:034d
  =========================================================================== }

unit Part3Morph;

interface

procedure Scene3;

implementation

uses VGA, Crt;

const
  NumPoints  = 765;        { $2FD -- points actually drawn per shape }
  SlotSize   = 4800;       { 800 points x 6 bytes -- spacing between shapes }
  ShapeBase  = $0636;
  Shape0     = $0636;
  Shape4     = $5136;      { ShapeBase + 4*SlotSize }
  Shape5     = $63F6;      { ShapeBase + 5*SlotSize }

  SinTable   = $02A8;      { 450 entries, 16.14 fixed point }
  CosTable   = $035C;      { = SinTable + 90 entries }
  FixedBits  = 14;         { products are shifted right by 14 }

  PageWidth  = 320;        { visible page }
  PageHeight = 400;        { double-scan disabled -- see VGA_Set400Lines }
  RowBytes   = 160;        { per plane; two 320-wide pages side by side }
  PageOfsA   = 0;
  PageOfsB   = 80;         { second page starts 80 bytes into each row }

{ These four live in DGROUP, not in the code -- the scene assigns them in
  Morph_InitScene -- so they are TYPED constants, which Borland Pascal puts in
  initialised data and allows you to write to. }
const
  MorphSteps : Integer = 45;     { DS:$BEB6 }
  ViewDist   : Integer = 2500;   { DS:$BEB4 }
  ProjScale  : Integer = 256;    { DS:$BEB2 }
  CentreY    : Integer = 200;    { added after the perspective divide }

const

  AngleWrap  = 360;        { $168 }
  SpinX      = 3;          { degrees per frame, all three axes }
  SpinY      = 3;
  SpinZ      = 3;

  SegFrames  = 45;         { $2D -- frames per scripted segment }
  LastFrames = 63;         { $3F -- the closing fade segment }


  DotColour  = $0E;        { yellow }

type
  { 765 points of (X, Y, Z). Declared two-dimensional because that is what
    the data is; Morph_DrawMorph walks it with pointer arithmetic (six
    bytes per point) and does not care either way. }
  TShape = array[1..NumPoints, 1..3] of Integer;

{ Both of these are TYPED CONSTANTS living in the executable's initialised
  data, not tables built at run time -- a plain `var` would land in BSS and
  would not appear in the file image at all.

  Verified: SinTab[i] = round(sin(i degrees) * 16384) to within 1, and
  SinTab[90 + a] = round(cos(a) * 16384) exactly, which is what lets one
  table serve both functions. }
{$I gen/P3SINE.INC}      { const SinTab : array[0..449] of Integer = (...) }

{ ===========================================================================
  RECONSTRUCTION SCAFFOLDING -- see the note in PART1_INTRO.PAS.
  =========================================================================== }

var
  { [transcribed] The projection centre, DS:$BEB0-ish. Morph_InitScene zeroes
    both before the first shape and they stay put for this scene. }
  XCentre, YCentre : Integer;

  { [inferred] The shape currently being drawn. The original addresses shapes
    by their DGROUP offset (CurShape, MorphFrom, MorphTo are Words holding
    $0636, $5136, $63F6) and walks them with pointer arithmetic; a working
    copy is the readable equivalent. }
  Work : TShape;

  { the morph loop's point counter -- a DGROUP word because the
    assembler block below decrements it directly }
  Count : Word;

{ [inferred] The three components of point P of the current working shape.
  Written as functions because the original reaches them by pointer
  arithmetic (six bytes per point) rather than by name. }
function PointX(P : Integer) : Integer;
begin
  PointX := Work[P, 1];
end;

function PointY(P : Integer) : Integer;
begin
  PointY := Work[P, 2];
end;

function PointZ(P : Integer) : Integer;
begin
  PointZ := Work[P, 3];
end;

{ [transcribed] VGA_GetPalette768 1139:034d / VGA_SetPalette768 1139:0335 --
  the whole DAC in one burst through ports $3C7/$3C8/$3C9. }
procedure GetPalette768(var P);
var
  I : Integer;
  B : array[0..767] of Byte absolute P;
begin
  Port[$3C7] := 0;
  for I := 0 to 255 do
  begin
    B[I * 3    ] := Port[$3C9];
    B[I * 3 + 1] := Port[$3C9];
    B[I * 3 + 2] := Port[$3C9];
  end;
end;

procedure SetPalette768(var P);
var
  I : Integer;
  B : array[0..767] of Byte absolute P;
begin
  WaitRetrace;
  Port[$3C8] := 0;
  for I := 0 to 255 do
  begin
    Port[$3C9] := B[I * 3    ];
    Port[$3C9] := B[I * 3 + 1];
    Port[$3C9] := B[I * 3 + 2];
  end;
end;

{$I gen/P3SHAPE.INC}     { const ShapeSphere, ShapeCube, ShapeGrid : TShape }

var
  AngX, AngY, AngZ    : Integer;   { DS:$BE9C, $BE9E, $BEA0 }
  StepX, StepY, StepZ : Integer;   { DS:$BEA2, $BEA4, $BEA6 }
  SinX, CosX          : Integer;   { DS:$BE92, $BE90 }
  SinY, CosY          : Integer;   { DS:$BE96, $BE94 }
  SinZ, CosZ          : Integer;   { DS:$BE98, $BE9A }
  CurShape            : Word;      { DS:$BEBA -- shape being drawn }
  MorphFrom, MorphTo  : Word;      { DS:$BEBC, $BEBE }
  MorphStep           : Integer;   { DS:$BEB8 }
  PageOfs             : Word;      { DS:$BEC0 -- 0 or 80 }
  Frames              : Integer;   { DS:$BEC2 }
  { DS:$BEC6 -- EIGHT HUNDRED entries, not PageHeight. 1192:0000 fills
    0..$31F regardless of how many rows the mode actually shows. }
  RowOfs              : array[0..799] of Word;

{ --------------------------------------------------------------------------
  VGA_Set400Lines (1139:02f2)
  CRTC register 9, low five bits cleared: maximum scan line = 0, i.e. no
  double scanning. That turns the 320x200 Mode-X screen into 320x400.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  1192:0000 -- the Mode-X row table

      for I := 0 to $31F do
        RowOfs[I] := (LogicalWidth * I) shl 1

  LogicalWidth is the byte at DS:$76B6, which InitScene sets to 80, so the
  stride is 160 bytes per row -- one plane of a 640-pixel logical line.

  THIS IS NOT VGA.BuildRowTable. That one fills VGA's own YOfs with y * 320
  for the 200 rows of mode 13h, and it is what InitScene used to call: the
  table below stayed all zeros, every dot landed on row 0, and the scene drew
  nothing. The two tables coexist and must not be conflated -- the note at the
  bottom of VGA.PAS says exactly that.

  The code lives in segment 1192 with the rest of the VGA unit, but the table
  it fills is at DS:$BEC6, in this scene's own data, which is why it is here.
  -------------------------------------------------------------------------- }
procedure BuildModeXRows;
var
  I : Integer;
begin
  for I := 0 to 799 do
    RowOfs[I] := Word(LogicalWidth) * Word(I) shl 1;
end;

procedure Set400Lines; assembler;
asm
  MOV  DX, $3D4
  MOV  AL, 9
  OUT  DX, AL
  INC  DX
  IN   AL, DX
  AND  AL, $E0
  OUT  DX, AL
end;

{ --------------------------------------------------------------------------
  Morph_SetAngles (1139:0000)
  One sine table serves both functions: cos(a) is sin(a + 90), so CosTable is
  simply SinTable advanced by 90 entries.
  -------------------------------------------------------------------------- }
procedure SetAngles(AX_, AY, AZ : Integer);
begin
  SinX := SinTab[AX_];  CosX := SinTab[AX_ + 90];
  SinY := SinTab[AY];   CosY := SinTab[AY  + 90];
  SinZ := SinTab[AZ];   CosZ := SinTab[AZ  + 90];
end;

{ --------------------------------------------------------------------------
  Morph_StepAngles (1139:0035)
  Advance each axis and wrap into 0..360. Degrees again, as in Scene 1.
  -------------------------------------------------------------------------- }
procedure StepAngles;

  function Wrap(A : Integer) : Integer;
  begin
    if A < 0          then A := A + AngleWrap;
    if A > AngleWrap  then A := A - AngleWrap;
    Wrap := A;
  end;

begin
  AngX := Wrap(AngX + StepX);
  AngY := Wrap(AngY + StepY);
  AngZ := Wrap(AngZ + StepZ);
  SetAngles(AngX, AngY, AngZ);
end;

{ --------------------------------------------------------------------------
  Morph_TransformPoint (1139:0096)

  Three successive 2-D rotations in 16.14 fixed point, then a perspective
  divide. Each product is a 32-bit multiply shifted right by 14.

  Registers on entry: BX = X, CX = Y, DX = Z (read straight from the 6-byte
  record). On exit DI = screen X, BX = screen Y, for ModeX_PlotPixel.
  -------------------------------------------------------------------------- }
procedure TransformPoint(X, Y, Z : Integer; var SX, SY : Integer);
var
  T, U, V, D : LongInt;
begin
  { rotate about the first axis }
  T := (LongInt(Z) * SinX + LongInt(Y) * CosX) shr FixedBits;
  U := (LongInt(Z) * CosX - LongInt(Y) * SinX) shr FixedBits;

  { second axis }
  V := (LongInt(X) * CosY - U * SinY) shr FixedBits;
  U := (U * CosY + LongInt(X) * SinY) shr FixedBits;

  { third axis }
  X := (V * CosZ + T * SinZ) shr FixedBits;
  Y := (T * CosZ - V * SinZ) shr FixedBits;

  D := ViewDist - U;
  if D >= 0 then
  begin
    SX := ((X - XCentre) * ProjScale) div D;
    SY := ((Y - YCentre) * ProjScale) div D + CentreY;
  end;
end;

{ --------------------------------------------------------------------------
  ModeX_PlotPixel (1139:01bb)
  Map Mask selects the plane from x mod 4; the byte address is x div 4 plus
  the row offset plus the current back-page offset.
  -------------------------------------------------------------------------- }
procedure PlotPixel(X, Y : Integer);
begin
  if (X >= 0) and (X < PageWidth) and (Y >= 0) and (Y < PageHeight) then
  begin
    PortW[$3C4] := (Word($01 shl (X and 3)) shl 8) or 2;
    Mem[VGASeg : (X shr 2) + RowOfs[Y] + PageOfs] := DotColour;
  end;
end;

{ --------------------------------------------------------------------------
  ModeX_ClearPage (1139:02a2)
  All four planes at once, then 40 words cleared and 40 words skipped per
  row -- i.e. it wipes the 80-byte half of each 160-byte row belonging to the
  back page, leaving the visible page untouched.
  -------------------------------------------------------------------------- }
procedure ClearPage;
var
  P : Word;
  I, Y : Integer;
begin
  P := PageOfs;
  PortW[$3C4] := $0F02;                { Map Mask: all planes }
  for Y := 1 to PageHeight - 1 do
  begin
    for I := 1 to RowBytes div 4 do    { 40 words = 80 bytes = 320 pixels }
    begin
      MemW[VGASeg : P] := 0;
      Inc(P, 2);
    end;
    Inc(P, RowBytes div 2);            { skip the other page's half }
  end;
end;

{ --------------------------------------------------------------------------
  ModeX_FlipPage (1139:02c3)
  Show the page we just drew, then make the other one current.
  -------------------------------------------------------------------------- }
procedure FlipPage;
begin
  Port[$3D4] := $0C;  Port[$3D5] := Hi(PageOfs);
  Port[$3D4] := $0D;  Port[$3D5] := Lo(PageOfs);
  PageOfs := PageOfsB - PageOfs;       { 0 <-> 80 }
end;

{ --------------------------------------------------------------------------
  Morph_DrawShape (1139:01f9) -- draw one shape straight.

  ASSETS  The shapes are compiled into the EXE, not in NEUROSIS.DAT.
          Extracted from DGROUP to:
            assets/part003/shape_sphere.bin / .png    DS:$0636
            assets/part003/shape_cube.bin   / .png    DS:$5136
            assets/part003/shape_grid.bin   / .png    DS:$63F6
          765 points x 6 bytes, three signed words (X, Y, Z).
          The .png files are previews rendered with the constants below.
          See docs/08-part3-scene3-morph.md.
  -------------------------------------------------------------------------- }
procedure DrawShape(Shape : Word);
var
  I, SX, SY : Integer;
  P : Word;
begin
  P := Shape;
  for I := 1 to NumPoints do
  begin
    TransformPoint(PointX(P), PointY(P), PointZ(P), SX, SY);
    PlotPixel(SX, SY);
    Inc(P, 6);
  end;
end;

{ --------------------------------------------------------------------------
  Morph_DrawMorph (1139:021d)

  Transcribed instruction by instruction. There is NO floating point here --
  the blend is plain 16-bit integer linear interpolation done with IMUL/IDIV
  through a 32-bit intermediate (CWD before each IMUL), which is exactly why
  it survives at full frame rate:

      P := A + (B - A) * MorphStep div MorphSteps

  applied to each of X, Y and Z in turn. The two shape pointers advance two
  bytes between components and six bytes between points; they are PUSHed
  before the per-point calls and POPped after, so the calls are free to use
  SI and DI.

  The three blended components are handed to Morph_TransformPoint in
  REGISTERS -- X in BX, Y in CX, Z in DX -- not on the stack. That is a
  register-convention call and has to be preserved as assembler.

  Once MorphStep passes MorphSteps the morph is complete: it copies MorphTo
  over CurShape and just draws the destination shape from then on.
  -------------------------------------------------------------------------- }
procedure DrawMorph; assembler;
asm
        MOV     BX, [MorphStep]
        CMP     BX, [MorphSteps]
        JLE     @@Blend
        MOV     BX, [MorphTo]              { morph finished -- }
        MOV     [CurShape], BX             {   latch the destination }
        CALL    DrawShape
        JMP     @@Done

@@Blend:
        MOV     WORD PTR [Count], 765      { $2FD points }
        MOV     SI, [MorphFrom]
        MOV     DI, [MorphTo]
@@Point:
        PUSH    DI
        PUSH    SI

        MOV     AX, [DI]                   { X := A.X + (B.X-A.X)*Step div Steps }
        SUB     AX, [SI]
        CWD
        IMUL    WORD PTR [MorphStep]
        IDIV    WORD PTR [MorphSteps]
        ADD     AX, [SI]
        MOV     BX, AX                     { X -> BX }
        ADD     SI, 2
        ADD     DI, 2

        MOV     AX, [DI]                   { Y }
        SUB     AX, [SI]
        CWD
        IMUL    WORD PTR [MorphStep]
        IDIV    WORD PTR [MorphSteps]
        ADD     AX, [SI]
        MOV     CX, AX                     { Y -> CX }
        ADD     SI, 2
        ADD     DI, 2

        MOV     AX, [DI]                   { Z }
        SUB     AX, [SI]
        CWD
        IMUL    WORD PTR [MorphStep]
        IDIV    WORD PTR [MorphSteps]
        ADD     AX, [SI]
        MOV     DX, AX                     { Z -> DX }
        ADD     SI, 2
        ADD     DI, 2

        CALL    TransformPoint             { 1139:0096 -- takes BX, CX, DX }
        CALL    PlotPixel                  { 1139:01bb }

        POP     SI
        POP     DI
        ADD     DI, 6
        ADD     SI, 6
        DEC     WORD PTR [Count]
        JNZ     @@Point

        INC     WORD PTR [MorphStep]
@@Done:
end;

{ --------------------------------------------------------------------------
  Morph_FadeStep (1139:0365)
  Read the whole DAC back, decrement every non-zero component by one, wait
  for retrace and write it out again -- a one-step fade toward black, called
  once per frame during the closing segment.
  -------------------------------------------------------------------------- }
procedure FadeStep;
var
  Pal : array[0..767] of Byte;
  I   : Integer;
begin
  GetPalette768(Pal);
  I := $300;
  repeat
    if Pal[I]     <> 0 then Dec(Pal[I]);
    if Pal[I - 1] <> 0 then Dec(Pal[I - 1]);
    if Pal[I - 2] <> 0 then Dec(Pal[I - 2]);
    Dec(I, 3);
  until I < 0;
  WaitRetrace;
  SetPalette768(Pal);
end;

{ --------------------------------------------------------------------------
  Morph_InitScene (1139:02fe)
  -------------------------------------------------------------------------- }
procedure InitScene;
begin
  LogicalWidth := 80;          { DS:$76B6 -- 640 logical pixels per row }
  SetMode;                     { mode 13h -> Mode-X }
  Set400Lines;                 { and now 320x400 }
  BuildModeXRows;              { 1192:0000 -- NOT VGA's BuildRowTable }
  MorphStep := 0;
  MorphSteps := 45;
  XCentre := 0;  YCentre := 0;
  ProjScale := 256;
  ViewDist  := 2500;
end;

{ --------------------------------------------------------------------------
  Demo_Scene3 (1139:03b4)

  Eight scripted segments of 45 frames (63 for the last). Odd segments hold a
  shape, even segments morph to the next one. The closing segment also fades.
  -------------------------------------------------------------------------- }
procedure Scene3;

  { one frame of the common loop; returns True if a key was pressed }
  function Frame(Morphing : Boolean) : Boolean;
  begin
    ClearPage;
    if Morphing then DrawMorph else DrawShape(CurShape);
    FlipPage;
    WaitRetrace;
    StepAngles;
    Frame := KeyPressed;
  end;

  procedure Hold(N : Integer);
  begin
    Frames := N;
    repeat
      if Frame(False) then Exit;
      Dec(Frames);
    until Frames = 0;
  end;

  procedure MorphTo_(FromShape, ToShape : Word; N : Integer);
  begin
    MorphFrom := FromShape;
    MorphTo   := ToShape;
    MorphStep := 0;
    Frames    := N;
    repeat
      if Frame(True) then Exit;
      Dec(Frames);
    until Frames = 0;
    CurShape := MorphTo;
  end;

begin
  InitScene;
  PageOfs := PageOfsB;
  CurShape  := Shape0;
  MorphFrom := Shape0;
  MorphTo   := Shape4;
  StepX := SpinX;  StepY := SpinY;  StepZ := SpinZ;
  AngX  := 0;      AngY  := 0;      AngZ  := 0;

  Hold(SegFrames);                          { 1: shape 0 }
  MorphTo_(Shape0, Shape4, SegFrames);      { 2: 0 -> 4  }
  Hold(SegFrames);                          { 3: shape 4 }
  MorphTo_(Shape4, Shape5, SegFrames);      { 4: 4 -> 5  }
  Hold(SegFrames);                          { 5: shape 5 }
  MorphTo_(Shape5, Shape4, SegFrames);      { 6: 5 -> 4  }
  Hold(SegFrames);                          { 7: shape 4 }

  { 8: morph back to shape 0 while fading the palette out }
  MorphFrom := Shape4;
  MorphTo   := Shape0;
  MorphStep := 0;
  Frames    := LastFrames;
  repeat
    FadeStep;
    if Frame(True) then Exit;
    Dec(Frames);
  until Frames = 0;
end;

end.

{ ===========================================================================
  HAND-WRITTEN ASSEMBLER IN THIS SCENE

  * VGA_SetPalette768 (1139:0335) -- LDS SI / MOV CX,$300 / REP OUTSB. The
    whole DAC written with one string instruction; unmistakably asm.
  * VGA_GetPalette768 (1139:034d) -- the matching read.
  * VGA_Set400Lines (1139:02f2) -- bare CRTC read-modify-write.
  * Morph_TransformPoint (1139:0096) takes its arguments in BX/CX/DX and
    leaves results in DI/BX for the plotter, which is not a Pascal calling
    convention -- this is an asm routine, and the Pascal above is a
    behavioural description of it rather than a literal translation.
  * ModeX_PlotPixel (1139:01bb) likewise consumes DI/BX directly.

  RESOLVED VALUES
    view distance 2500 ($BEB4)   projection scale 256 ($BEB2)
    spin 3 deg/frame on all three axes    segment 45 frames, closing 63
    morph length 45 steps        dot colour $0E     angle wrap 360

  VERIFIED BY RENDERING
  * Extracting the vertex data straight from DGROUP and projecting it with
    the constants above produces a recognisable dotted sphere (slot 0), cube
    (slot 4) and flat grid (slot 5) -- see work/assets/003_shape*.png. That
    independently confirms the record layout, the shape base addresses, the
    slot spacing, the view distance and the projection scale.

  RESOLVED
  * 1192:0000 is VGA_BuildRowTable, part of the VGA unit rather than this
    scene: RowOfs[i] := 160 * i for i = 0..799, at DS:$BEC6. The multiplier is
    the byte at DS:$76B6 (= 80, the Mode-X plane stride for 320 pixels) shifted
    left once. A 160-byte row stride is 640 pixels in Mode-X, and 400 such rows
    are exactly 64,000 bytes -- one full plane. See docs/05-vga-unit.md.
  * Shape slots 1, 2 and 3 exist in DGROUP but are unused by this scene. The
    three that ARE used (Sphere, Cube, Grid) are emitted in gen/P3SHAPE.INC.

  * Morph_DrawMorph is now transcribed rather than described. The blend is
    integer linear interpolation, P := A + (B - A) * Step div Steps, done with
    IMUL/IDIV through a 32-bit intermediate -- no floating point anywhere in
    the morph. Coordinates reach Morph_TransformPoint in BX, CX and DX, so it
    is a register-convention call and is kept as assembler.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
