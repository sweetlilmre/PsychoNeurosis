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
  { The scaling has to be a DIVIDE, not `shr FixedBits`.

    The original does `IMUL` then `SHL AX,1 / RCL DX,1` twice and keeps DX --
    the top word of the product times four, which is an ARITHMETIC shift right
    by 14 and preserves the sign. Turbo Pascal's `shr` on a LongInt is a
    LOGICAL shift, so any point whose intermediate went negative came out as a
    huge positive, landed far off screen and was dropped by PlotPixel's bounds
    test. What survived was the handful of points that stayed non-negative
    throughout -- a small block of dots near the centre instead of a rotating
    solid.

    `div` truncates toward zero where an arithmetic shift floors, so the two
    differ by one unit on negative values -- well under a pixel after the
    perspective divide. The original really does shift; there is simply no
    signed shift operator in Turbo Pascal to write it with. }
  FixedOne   = 16384;      { 1 shl FixedBits }
  ScreenCentreX = 160;     { $A0 -- 1139:019c }
  ScreenCentreY = 200;     { $C8 -- 1139:01ac, half of 400 rows }

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
{$I gen/P3SHAPE.INC}     { const ShapeSphere, ShapeCube, ShapeGrid : TShape }

{ --------------------------------------------------------------------------
  SHAPE ADDRESSING

  The original identifies a shape by its absolute DGROUP offset and walks it
  six bytes at a time: CurShape, MorphFrom and MorphTo all hold $0636, $5136
  or $63F6, and DrawShape does `MOV BX,[SI] / MOV CX,[SI+2] / MOV DX,[SI+4]`
  then `ADD SI,6`.

  The shapes are Pascal constants here, so those offsets have to be mapped
  onto them. An earlier version kept the offsets AND indexed a `Work` array
  with them -- Work[$0636] on a `array[1..765]` -- and the assembler morph
  loop dereferenced them as raw DS addresses, reading whatever Turbo Pascal
  happened to have put at $0636. That is what reduced the scene to a cluster
  of stray dots: the coordinates were never the shape data at all.
  -------------------------------------------------------------------------- }
type
  TShapePtr = ^TShape;

function ShapeOf(Slot : Word) : TShapePtr;
begin
  case Slot of
    Shape0 : ShapeOf := @ShapeSphere;      { $0636 }
    Shape4 : ShapeOf := @ShapeCube;        { $5136 }
    Shape5 : ShapeOf := @ShapeGrid;        { $63F6 }
  else
    ShapeOf := @ShapeSphere;
  end;
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
{ --------------------------------------------------------------------------
  The rotation's fixed-point scaling, as the original writes it.

  After each IMUL the 32-bit product sits in DX:AX, and 1139:00bd does

      SHL AX,1 / RCL DX,1        twice, then keeps DX

  -- the top word of the product times four, i.e. an arithmetic shift right by
  14. No divide. Turbo Pascal has no signed shift operator, but DX is just the
  high half of the shifted product, so casting the LongInt over a two-Integer
  record gets at it exactly, sign and all, with two shifts and no arithmetic:

      -16384 -> shl 2 = $FFFF0000 -> Hi = $FFFF = -1        ( -1.0 )
   16384000 -> shl 2 = $03E80000 -> Hi = $03E8 =  1000      ( 1000.0 )

  An earlier version of this used `div 16384`, which is numerically close but
  is not what the code does and rounds the other way on negatives.
  -------------------------------------------------------------------------- }
type
  TSplit = record Lo, Hi : Integer end;

function Scale14(P : LongInt) : Integer;
begin
  P := P shl 2;
  Scale14 := TSplit(P).Hi;
end;

procedure TransformPoint(X, Y, Z : Integer; var SX, SY : Integer);
var
  T, U, V, D : LongInt;
begin
  { rotate about the first axis }
  T := Scale14(LongInt(Z) * SinX + LongInt(Y) * CosX);
  U := Scale14(LongInt(Z) * CosX - LongInt(Y) * SinX);

  { second axis }
  V := Scale14(LongInt(X) * CosY - U * SinY);
  U := Scale14(U * CosY + LongInt(X) * SinY);

  { third axis }
  X := Scale14(V * CosZ + T * SinZ);
  Y := Scale14(T * CosZ - V * SinZ);

  D := ViewDist - U;
  if D >= 0 then
  begin
    { 1139:019c and 1139:01ac add the SCREEN centre as literals -- $A0 and
      $C8, i.e. 160 and 200, which is the middle of a 320 x 400 page. It is
      200 and not 100 because double scanning is off.

      XCentre and YCentre are something else: MODEL centres, subtracted from
      the coordinate before the divide, and InitScene sets both to zero. Using
      them as the screen centre left every point projected about (0, 0), which
      is what clustered the shape into the left edge. }
    { The LongInt cast is load-bearing. 1139:0191 is

          MOV AX,[BP-2] / SUB AX,[$BEAE] / IMUL CX / IDIV BX

      -- IMUL leaves a 32-BIT product in DX:AX and IDIV then divides that by
      BX. Written as `(X - XCentre) * ProjScale` with three Integers, Turbo
      Pascal evaluates the multiply in 16 bits, so any coordinate past +/-127
      overflows and wraps: the shapes reach +/-1000 and ProjScale is 256, so
      almost every point wrapped to a more or less arbitrary value. That is
      what scattered the scene into a rectangle of random dots. }
    SX := (LongInt(X - XCentre) * ProjScale) div D + ScreenCentreX;
    SY := (LongInt(Y - YCentre) * ProjScale) div D + ScreenCentreY;
  end
  else
  begin
    SX := -1;                     { 1139:01b3 -- behind the viewer }
    SY := -1;
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
{ 1139:01f9 -- 765 points ([$BEC4] := $2FD), read as three words with a
  stride of six, transformed and plotted. }
procedure DrawShape(Shape : Word);
var
  I, SX, SY : Integer;
  S : TShapePtr;
begin
  S := ShapeOf(Shape);
  for I := 1 to NumPoints do
  begin
    TransformPoint(S^[I, 1], S^[I, 2], S^[I, 3], SX, SY);
    PlotPixel(SX, SY);
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
  register-convention call. DrawMorph used to be assembler for that reason
  and is now Pascal -- see the note on it.

  Once MorphStep passes MorphSteps the morph is complete: it copies MorphTo
  over CurShape and just draws the destination shape from then on.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  1139:021d -- DrawMorph

      if MorphStep > MorphSteps then
        CurShape := MorphTo ; DrawShape(CurShape)
      else
        for I := 1 to 765 do
          P := A[I] + (B[I] - A[I]) * MorphStep div MorphSteps
          TransformPoint(P) ; PlotPixel
        Inc(MorphStep)

  The original walks both shapes with SI and DI six bytes at a time and does
  each component as `AX := B-A ; CWD ; IMUL MorphStep ; IDIV MorphSteps ;
  ADD AX,A` -- a 32-bit intermediate between the multiply and the divide,
  which is why the LongInt cast below is needed and a plain Integer
  expression would overflow on the wider shapes.

  This used to be an assembler block that dereferenced MorphFrom and MorphTo
  as raw DS offsets. Those offsets only mean anything in the original's data
  segment; here the shapes are Pascal constants, so it read rubbish. See the
  note on shape addressing above.
  -------------------------------------------------------------------------- }
procedure DrawMorph;
var
  I, SX, SY  : Integer;
  A, B       : TShapePtr;
  X, Y, Z    : Integer;

  function Blend(P, Q : Integer) : Integer;
  begin
    Blend := P + (LongInt(Q - P) * MorphStep) div MorphSteps;
  end;

begin
  if MorphStep > MorphSteps then
  begin
    CurShape := MorphTo;
    DrawShape(CurShape);
    Exit;
  end;

  A := ShapeOf(MorphFrom);
  B := ShapeOf(MorphTo);
  for I := 1 to NumPoints do
  begin
    X := Blend(A^[I, 1], B^[I, 1]);
    Y := Blend(A^[I, 2], B^[I, 2]);
    Z := Blend(A^[I, 3], B^[I, 3]);
    TransformPoint(X, Y, Z, SX, SY);
    PlotPixel(SX, SY);
  end;
  Inc(MorphStep);
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
    is a register-convention call in the original. DrawMorph is Pascal here.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
