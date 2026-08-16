{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.005
  Reconstructed from NEUROSIS_005_fpu.exe.

  Three scenes. The middle one is a rotozoomer using the neatest trick in the
  demo: the texture is addressed by building a far pointer straight out of the
  fixed-point coordinates.

  ADDRESS MAP
    Demo_Scene1  100e:07a4    Demo_Scene2_Rotozoom  1096:03d7
    Demo_Scene3  1102:035a    Rotozoom_Frame        1096:0000
    Scene3_Run   1102:017e    Heightmap_Draw        1102:0000
  =========================================================================== }

unit Part5;

interface

procedure RunPart5;

implementation

uses VGA, Crt, DemoVT;

{$I gen/P5MESH.INC}      { const MeshTris : array[1..1922, 1..3] of Word }

{ ===========================================================================
  Scene 2 -- the rotozoomer
  =========================================================================== }

{ ===========================================================================
  RECONSTRUCTION SCAFFOLDING -- see the note in PART1_INTRO.PAS.
    [transcribed] read out of the binary   [inferred] implied by call sites
    [stub] signature only
  =========================================================================== }

const
  GridSide  = 32;                       { the heightfield is 32 x 32 }
  GridVerts = GridSide * GridSide;      { 1024, matching MeshTris indices }
  NumTris   = 1922;                     { 2 * 31 * 31 }
  PatchSide = 30;                       { scene 3's rotating patch }

type
  TVertexRec = record
    X, Y, Z : Integer;
    Colour  : Byte;
  end;
  TTri = record
    A, B, C : Integer;
  end;
  { Typed so the scenes can index them; TP7 will not qualify a bare Pointer. }
  TBuf = array[0..65534] of Byte;

var
  Texture    : ^TBuf;
  TextureSeg : Word;
  Screen     : ^TBuf;
  Finished   : Boolean;

  { the heightfield, its projection and its shading }
  Height : array[0..GridVerts - 1] of Byte;
  Vertex : array[0..GridVerts - 1] of TVertexRec;
  Tri    : array[1..NumTris] of TTri;
  SX, SY : array[0..GridVerts - 1] of Integer;
  SC     : array[0..GridVerts - 1] of Byte;
  { Scene 1's per-vertex grid coordinates. Scene 3 works on ONE point at a
    time and uses the RX/RY/RZ scalars below instead. }
  X, Y, Z : array[0..GridVerts - 1] of Integer;
  { 16.16 fixed point -- the rotator and the projector are LongInt throughout }
  RX, RY, RZ       : LongInt;
  RotX, RotY, RotZ : Integer;
  SinX, CosX       : LongInt;   { DS:$A672 / $A676 }
  SinY, CosY       : LongInt;   { DS:$A66A / $A66E }
  SinZ, CosZ       : LongInt;   { DS:$A662 / $A666 }
  ProjScale        : LongInt;   { DS:$A67A }


  { scene 2's tables, 2001 entries over angle I + 270 -- see the note at the
    foot of this file for where the 256 comes from }
  SinTab, CosTab : array[0..2000] of Integer;
  DX, DY         : array[0..2000] of Integer;

{ [inferred] palette then a 320x200 screen, straight from NEUROSIS.DAT. }
procedure LoadPaletteAndScreen(FileOfs : LongInt);
var
  F : file;
begin
  if Screen = nil then GetMem(Screen, 64000);
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, FileOfs);
  BlockRead(F, Palette, SizeOf(Palette));
  SetPalette;
  BlockRead(F, Screen^, 64000);
  Close(F);
end;

{ [stub] scene 1: three 1,024-byte heightmaps from $153DE5. }
{ --------------------------------------------------------------------------
  Scene 1's data layout, read off Demo_Scene1 (100e:07a4) and the routines it
  calls. Two separate arrays, not one:

    Vertex   DS:$317E   6 bytes -- X, Y, Z as words
    Projected DS:$497E  5 bytes -- X, Y as words then a colour BYTE

  An earlier reconstruction had them as one record with all four fields; that
  is not what the code indexes (it multiplies the triangle index by 5, not 8).
  -------------------------------------------------------------------------- }

const
  { DS:$2D0E..$2D15 -- the triangle filler's clip box. Y stops at 199 here,
    unlike part 002's 239: this scene is plain mode 13h, not 320x240. }
  ClipY1 = 0;    ClipY2 = 199;
  ClipX1 = 0;    ClipX2 = 319;
  ScreenH = 200;                { DS:$2D16 }
  ScreenW = 320;                { DS:$2D18 }

var
  { DS:$5DFE -- linear row offsets, y * 320. Built by 100e:04e6. }
  RowOfs : array[0..199] of Word;
  { DS:$5FDE -- the span list the filler builds before drawing. }
  SpanX  : array[0..511] of Integer;

{ [transcribed] 100e:04e6 }
{ 16.16 sine and cosine, the format the rotator wants. }
function FixSin(A : Integer) : LongInt;
begin
  FixSin := Round(Sin(A * Pi / 180) * 65536.0);
end;

function FixCos(A : Integer) : LongInt;
begin
  FixCos := Round(Cos(A * Pi / 180) * 65536.0);
end;

procedure BuildRowTable;
var
  Y : Integer;
begin
  for Y := 0 to 199 do RowOfs[Y] := Y * 320;
end;

{ [transcribed] 100e:050b -- lay out the 32 x 32 grid. Spacing is 20 units and
  Z starts at 300; Heights immediately overwrites Z, so the 300 only matters
  for the very first frame. }
procedure BuildGrid;
var
  I : Integer;
begin
  for I := 0 to GridVerts - 1 do
  begin
    X[I] := (I mod GridSide - 16) * 20;
    Y[I] := (I div GridSide - 16) * 20;
    Z[I] := 300;
  end;
end;

{ [transcribed] one 1,024-byte heightmap into DS:$2D7E. Demo_Scene1 reads the
  three maps ONE AT A TIME, each immediately before the sweep that uses it --
  not all three up front, which is what an earlier version assumed. }
procedure LoadHeightmap(var F : file);
begin
  BlockRead(F, Height, GridVerts);
end;

{ --------------------------------------------------------------------------
  FUN_100e_0000 -- the terrain triangle filler.

  Same architecture as part 002's Tri_Fill and equally unlike a naive
  scanline fill: sort the vertices by Y, step the edges with integer DDA and
  an error accumulator, build a span list, then draw the list BACKWARDS.

  Two differences from part 002's copy. This one is LINEAR mode 13h rather
  than Mode-X, so a span is one REP STOSW with no plane juggling; and its clip
  box stops at Y = 199 rather than 239.

  The original takes the destination segment and colour on the stack and is
  called 1,922 times a frame -- once per triangle in the compiled-in list.
  -------------------------------------------------------------------------- }
procedure FillTriangle(X1, Y1, X2, Y2, X3, Y3 : Integer;
                       Colour : Byte; Segment : Word);
var
  T, Row, Bot          : Integer;
  XA, XB, WA, RA, WB, RB : Integer;
  ErrA, ErrB, DYA, DYB : Integer;
  N, L, R              : Integer;

  procedure Setup(var Whole, Rem : Integer; DX, DY : Integer);
  begin
    if DY = 0 then begin Whole := 0; Rem := 0; Exit end;
    Whole := DX div DY;
    Rem   := DX mod DY;
    if DX < 0 then begin Dec(Whole); Inc(Rem, DY) end;
  end;

  procedure Step(var Xc, Err : Integer; Whole, Rem, Den : Integer);
  begin
    Inc(Err, Rem);
    if Err > 0 then begin Dec(Err, Den); Inc(Xc) end;
    Inc(Xc, Whole);
  end;

begin
  if (Y1 = Y2) and (Y2 = Y3) then Exit;

  if Y2 < Y1 then begin T := Y1; Y1 := Y2; Y2 := T; T := X1; X1 := X2; X2 := T end;
  if Y3 < Y1 then begin T := Y1; Y1 := Y3; Y3 := T; T := X1; X1 := X3; X3 := T end;
  if Y3 < Y2 then begin T := Y2; Y2 := Y3; Y3 := T; T := X2; X2 := X3; X3 := T end;

  if (Y3 < ClipY1) or (Y1 > ClipY2) then Exit;

  DYA := Y3 - Y1;  Setup(WA, RA, X3 - X1, DYA);
  DYB := Y2 - Y1;  Setup(WB, RB, X2 - X1, DYB);
  XA := X1;  XB := X1;  ErrA := 0;  ErrB := 0;  N := 0;

  for Row := Y1 to Y3 - 1 do
  begin
    if Row = Y2 then
    begin
      DYB := Y3 - Y2;  Setup(WB, RB, X3 - X2, DYB);
      XB := X2;  ErrB := 0;
    end;
    if (Row >= ClipY1) and (Row <= ClipY2) and (N < 510) then
    begin
      SpanX[N] := XA;  SpanX[N + 1] := XB;  Inc(N, 2);
    end;
    Step(XA, ErrA, WA, RA, DYA);
    if DYB <> 0 then Step(XB, ErrB, WB, RB, DYB);
  end;

  { draw the list backwards, bottom scanline first }
  Bot := Y3 - 1;  if Bot > ClipY2 then Bot := ClipY2;
  Row := Bot;
  while (N >= 2) and (Row >= ClipY1) do
  begin
    Dec(N, 2);
    R := SpanX[N + 1];  L := SpanX[N];
    if L > R then begin T := L; L := R; R := T end;
    if R > ClipX2 then R := ClipX2;
    if L < ClipX1 then L := ClipX1;
    if R > L then
      FillChar(Mem[Segment : RowOfs[Row] + L], R - L, Colour);
    Dec(Row);
  end;
end;

{ [inferred] FUN_1102_02d1 -- latch the three rotation angles. The trig pairs
  the rotator reads live at DS:$A662/$A666 (Z), $A66A/$A66E (Y) and
  $A672/$A676 (X), all as 16.16 fixed point LongInts. Only the setter is
  inferred; the rotator that consumes them (1102:128b) is transcribed. }
procedure SetRotation(AX_, AY_, AZ_ : Integer);
begin
  RotZ := AZ_;  SinZ := FixSin(AZ_);  CosZ := FixCos(AZ_);
  RotY := AY_;  SinY := FixSin(AY_);  CosY := FixCos(AY_);
  RotX := AX_;  SinX := FixSin(AX_);  CosX := FixCos(AX_);
end;

{ [transcribed] FUN_1102_11d9 -- the clip test. }
function InBounds(X, Y : Integer) : Boolean;
begin
  InBounds := (X >= ClipX1) and (X <= ClipX2) and (Y >= ClipY1) and (Y <= ClipY2);
end;

{ --------------------------------------------------------------------------
  FUN_1102_128b -- rotate one point about all THREE axes.

  16.16 fixed point throughout: every product is a 32x32 multiply taken from
  the high half (`>> 16`), and the coordinates are LongInts, not Integers.
  An earlier reconstruction had this as a single-axis rotation in 8-bit fixed
  point, which is wrong on both counts.

  The order is Z, then Y, then X:

      Y1 := (Y*SinZ + X*CosZ) >> 16
      X1 := (X*SinZ - Y*CosZ) >> 16
      Z1 := (Z*SinY - X1*CosY) >> 16
      X' := (X1*SinY + Z*CosY) >> 16
      Z' := (Z1*SinX + Y1*CosX) >> 16
      Y' := (Y1*SinX - Z1*CosX) >> 16
  -------------------------------------------------------------------------- }
procedure Rotate(PX, PY, PZ : LongInt);
var
  X1, Y1, Z1 : LongInt;
begin
  Y1 := (PY * SinZ + PX * CosZ) div 65536;
  X1 := (PX * SinZ - PY * CosZ) div 65536;
  Z1 := (PZ * SinY - X1 * CosY) div 65536;
  RX := (X1 * SinY + PZ * CosY) div 65536;
  RZ := (Z1 * SinX + Y1 * CosX) div 65536;
  RY := (Y1 * SinX - Z1 * CosX) div 65536;
end;

{ --------------------------------------------------------------------------
  FUN_1102_13d9 -- perspective divide.

      Sx :=  round((X / D) * Scale) + ScreenW div 2
      Sy :=  ScreenH div 2 - round((Y / D) * Scale)

  Scale is a 16.16 LongInt at DS:$A67A; ScreenH and ScreenW are the words at
  DS:$2D16 and DS:$2D18, which hold 200 and 320. The rounding is the classic
  fixed-point `+ $8000 then >> 16`, and note that Y is INVERTED -- screen
  centre minus, not plus. An earlier reconstruction inverted X instead and
  used a shl 6 in place of the divide.
  -------------------------------------------------------------------------- }
procedure Project;
var
  T : LongInt;
begin
  if RZ = 0 then RZ := 1;
  T  := ((RX * 65536) div RZ) * ProjScale;
  RX := ((T + $8000) div 65536) + ScreenW div 2;
  T  := ((RY * 65536) div RZ) * ProjScale;
  RY := ScreenH div 2 - ((T + $8000) div 65536);
end;

{ --------------------------------------------------------------------------
  FUN_1096_0042 -- NOT a palette effect. It is a PIXEL SCATTER transition, and
  the largest single routine in this part.

  Eight rounds. Each one draws a rotozoom frame, then scans the screen bottom
  to top collecting up to 1,500 non-zero pixels into ten-byte records:

      +0  step counter      +1  colour
      +2  random X          +4  source X
      +6  random Y          +8  source Y

  and then animates them over TWENTY-FIVE steps, each pixel interpolating
  between its random position and its true one:

      pos := dest + (src - dest) * step div 25

  Each step erases at the previous position (restoring from a 64,000-byte
  backup) and redraws at the new one, so the image assembles itself out of
  scattered dots. Two heap blocks: 64,000 for the backup and 15,000 for the
  1,500 records.
  -------------------------------------------------------------------------- }
procedure ScatterTransition;
const
  MaxDots  = 1500;
  Steps    = 25;
  Rounds   = 8;
type
  TDot = record
    Step   : Byte;
    Colour : Byte;
    RandX  : Integer;
    SrcX   : Integer;
    RandY  : Integer;
    SrcY   : Integer;
  end;
var
  Dots    : ^TDot;
  Backup  : Pointer;
  N, R, S : Integer;
begin
  GetMem(Backup, 64000);
  GetMem(Dots, MaxDots * SizeOf(TDot));
  { ... eight rounds of collect-then-interpolate, as described above ... }
  FreeMem(Dots, MaxDots * SizeOf(TDot));
  FreeMem(Backup, 64000);
end;

{ [stub] flat-fill one triangle of the terrain mesh. }

procedure MusicInit;
begin
  DemoVT.MusicInit;
end;

{ --------------------------------------------------------------------------
  The texture is copied out of the 320-wide screen into a 256-wide buffer
  that occupies a whole 64K segment:

      GetMem(Texture, $FFFF);
  TextureSeg := Seg(Texture^);
      for Y := 0 to 199 do
        for X := 0 to 255 do
          Texture^[Y * 256 + X] := Screen^[Y * 320 + 4 + X];

  That layout is the whole point. With 256 bytes per row inside a 64K segment,
  the high byte of a 16-bit fixed-point V is the row and the high byte of U is
  the column -- so the sample address is simply Hi(V):Hi(U) as a far pointer.
  Wrapping is free, and there is no mask, no bounds test and no multiply.

  ASSETS  NEUROSIS.DAT $1549E5:
            assets/part005/part5_palette.pal    768 B
            assets/part005/part5_screen.png     64,000 B -- the texture source
          See docs/17-part005.md.
  -------------------------------------------------------------------------- }
procedure RotozoomFrame(TexSeg : Word; dU, dV, U0, V0 : Integer); assembler;
asm
  { for Y := 0 to 194 do
      U := U0; V := V0
      for X := 0 to 319 do
        V := V + dV;  U := U + dU
        Dest^ := Mem[Hi(V) : Hi(U)]     <- the whole trick
        Inc(Dest)
      U0 := U0 + dV;  V0 := V0 - dU     <- incremental rotation, no multiply }
end;

procedure Scene2;
var
  X, Y, I, Step, Index : Integer;
begin
  LoadPaletteAndScreen($1549E5);

  GetMem(Texture, $FFFF);
  TextureSeg := Seg(Texture^);
  FillChar(Texture^, 0, 0);
  for Y := 0 to 199 do
    for X := 0 to 255 do
      Texture^[Y * 256 + X] := Screen^[Y * 320 + 4 + X];

  { Two 2001-entry tables over angle I + 270, then two motion tables scaled
    by 100 and 160 and NEGATED. Read instruction by instruction off 1096:03d7;
    see the note at the foot of this file about the 256. }
  for I := 0 to 2000 do
  begin
    SinTab[I] := Round(Sin((I + 270) * Pi / 180) * 256);   { 8.8 fixed point }
    CosTab[I] := Round(Cos((I + 270) * Pi / 180) * 256);
    DX[I]     := -(SinTab[I] * 100);
    DY[I]     := -(CosTab[I] * 160);
  end;

  Step  := 10;                             { 10 degrees per frame }
  Index := 270;
  repeat
    Inc(Index, Step);
    { note the mismatched indices -- Cos is read at Index, Sin at Index+1,
      DX at Index and DY at Index+1. That one-entry skew is what stops the
      path being a plain circle. }
    RotozoomFrame(TextureSeg,
                  CosTab[Index], SinTab[Index + 1],
                  DX[Index] + 16000, DY[Index + 1] + 23000);
    CopyScreen(VirtScrSeg, $A000);
    if KeyPressed then ReadKey;
  until Finished or (Index >= 1980);

  ClearScreen($A000, 0);
  ClearScreen(VirtScrSeg, 0);
  FreeMem(Texture, $FFFF);
end;

{ ===========================================================================
  Scene 3 -- a rotating 3-D heightmap patch
  =========================================================================== }

{ --------------------------------------------------------------------------
  Heightmap_Draw (1102:0000)

  A 30x30 patch of the source image around (CX, CY). Each cell's pixel value
  is used BOTH as its colour and as its height, so the picture embosses itself
  into the surface.
  -------------------------------------------------------------------------- }
procedure HeightmapDraw(Angle, CY, CX : Integer);
var
  I, J, H, SXp, SYp : Integer;
begin
  SetRotation(Angle, 0, 0);
  for J := 1 to 30 do
    for I := 1 to 30 do
    begin
      H := 0;
      if InBounds(CX + I - 15, CY + J - 15) then
        { the source image is the loaded screen, on the heap -- a 64,000
          byte global would not fit in DGROUP }
        H := Screen^[(CY + J - 15) * 320 + CX + I - 15];

      Rotate(I - 15, J - 15, -50);
      RZ := RZ + 200;
      Project;
      SXp := RX;
      SYp := RY + H;        { the height term }                  { the height term }
      if (SXp > 0) and (SXp < 319) and (SYp > 0) and (SYp < 199) then
        PutPixel(SXp, SYp, H, VirtScrSeg);   { (Segment, Colour, Y, X) }
    end;
end;

{ --------------------------------------------------------------------------
  Scene3_Run (1102:017e) -- the patch centre bounces around the screen, with
  a scripted pause in the middle.
  -------------------------------------------------------------------------- }
procedure Scene3;
var
  X, Y, DX, DY, Frame : Integer;
  Running : Boolean;
begin
  X := 160;  Y := 100;  DX := 2;  DY := 2;
  Frame := 0;  Running := True;
  repeat
    if Running then Inc(Frame);
    if KeyPressed then begin Frame := 500; ReadKey end;
    if Frame = 100 then begin DX := 0; DY := 0 end;   { hold still }
    if Frame = 220 then begin DX := 2; DY := 2 end;   { drift again }
    if Frame > 499 then ScatterTransition;
    if Frame > 563 then Running := False;

    Inc(X, DX);  Inc(Y, DY);
    if X < 0   then begin X := 0;   DX := -DX end;
    if X > 319 then begin X := 319; DX := -DX end;
    if Y < 0   then begin Y := 0;   DY := -DY end;
    if Y > 199 then begin Y := 199; DY := -DY end;

    ClearScreen(VirtScrSeg, 0);
    HeightmapDraw(3600, Y, X);
    CopyScreen(VirtScrSeg, $A000);
  until not Running;
end;

{ ===========================================================================
  Scene 1 -- table-driven sweep
  =========================================================================== }

{ --------------------------------------------------------------------------
  Demo_Scene1 (100e:07a4) -- a 32x32 heightfield drawn as solid triangles.

  The three 1024-byte tables from $153DE5 are heightmaps (1024 = 32 x 32).
  Animation is a threshold sweep: as the threshold moves, terrain rises out of
  the plane and sinks back.

  ASSETS  NEUROSIS.DAT $153DE5, 3 x 1024 bytes:
            assets/part005/153DE5_00.bin .. _02.bin
  -------------------------------------------------------------------------- }
procedure Heights(Threshold : Byte);       { 100e:056d }
var I : Integer;
begin
  for I := 0 to 1023 do
    if Threshold < Height[I] then
      Z[I] := 250 - (Height[I] - Threshold)
    else
      Z[I] := 250;
end;

procedure ProjectAll;                      { 100e:05d3 }
var I : Integer;
begin
  for I := 0 to 1023 do
  begin
    SX[I] := 160 - (X[I] shl 6) div Z[I];
    SY[I] := 100 + (Y[I] shl 6) div Z[I];
    SC[I] := ((250 - Z[I]) mod 255) + 1;   { depth shading }
  end;
end;

procedure DrawTerrain;                     { 100e:062a }
var I : Integer;
begin
  ClearScreen(VirtScrSeg, 0);
  for I := 1 to 1922 do                    { 2 x 31 x 31 -- a 32x32 grid }
    FillTriangle(SX[Tri[I].A], SY[Tri[I].A], SX[Tri[I].B], SY[Tri[I].B], SX[Tri[I].C], SY[Tri[I].C], SC[Tri[I].C], VirtScrSeg);
  CopyScreen(VirtScrSeg, $A000);
end;

{ [transcribed] FUN_100e_06ae -- sweep the threshold down and then back up.
  As it moves, terrain rises out of the plane and sinks back: the whole
  animation is one moving comparison.

  The original runs both sweeps to completion -- there is no key check inside
  them, which is why the scene cannot be skipped part way. }
procedure SweepDownAndUp(LoT, HiT : Byte);
var
  T : Integer;
begin
  for T := HiT downto LoT do
  begin
    Heights(T);  ProjectAll;  DrawTerrain;
  end;
  for T := LoT to HiT do
  begin
    Heights(T);  ProjectAll;  DrawTerrain;
  end;
end;

{ [transcribed] Demo_Scene1 100e:07a4 -- the real order. Note the heightmaps
  are read one at a time, each immediately before the sweep that uses it, and
  that a frame is drawn once at threshold 55 before any of them is loaded. }
procedure Scene1;
var
  F : file;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $153DE5);
  SetRGB(0, 0, 0, 1);

  BuildGrid;
  BuildRowTable;
  Heights($37);  ProjectAll;  DrawTerrain;

  LoadHeightmap(F);  SweepDownAndUp($14, $41);
  LoadHeightmap(F);  SweepDownAndUp($14, $41);
  LoadHeightmap(F);  SweepDownAndUp($05, $37);

  ClearScreen($A000, 0);
  Close(F);
end;

procedure RunPart5;
begin
  SetMode13h; VirtScrAlloc; MusicInit;
  Scene1;  FlushKeys;
  Scene2;  FlushKeys;
  Scene3;  FlushKeys;
end;

end.

{ ===========================================================================
  SCENE 2's FIXED-POINT SCALE

  The table build at 1096:03d7 reads, exactly:

      for i := 0 to 2000 do
        TabSin[i] := <fp>(i + 270)            (* RTL_32ad then RTL_3268 *)
        TabCos[i] := <fp>(i + 270)            (* RTL_32b2 then RTL_3268 *)
      for i := 0 to 2000 do
        DX[i] := -(TabSin[i] * 100)
        DY[i] := -(TabCos[i] * 160)

  and the frame loop runs Index from 270 in steps of 10 until $7BC (1980).
  RTL_32ad / RTL_32b2 are Sin / Cos -- the same contiguous stub pair, five
  bytes apart, that fixes 3252/3257 in part 003.

  The scale factor 256 is DERIVED, not read. Rotozoom_Frame (1096:0000) walks
  320 columns by 195 rows stepping U and V by the two table values and reads
  the texture at (Hi(V) shl 8) or Hi(U) -- so U and V are 8.8 fixed point over
  a 256x256 texture, and the values handed to it must therefore be sin/cos
  scaled by 256. Where exactly the multiply sits in the FP stream is not
  recoverable: these are emulator-trapped sequences and Ghidra models each
  trap as an opaque call, dropping the constants they load.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
