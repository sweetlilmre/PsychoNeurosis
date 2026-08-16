{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 2
  Reconstructed from NEUROSIS_003_fpu.exe.

  A depth-shaded 3-D star tube. 500 points sit on a circle of radius 40 at
  evenly spaced depths, fly toward the viewer, and are perspective-divided
  onto the screen. A 50-entry waypoint table pans the tube around while it
  runs, and the scene ends with every point collapsing into screen centre.

  Unlike Scene 1 (mode-X, hardware panning) this is plain mode 13h with a
  software virtual screen -- the two scenes use quite different machinery.

  Floating point is used ONCE, to generate the point cloud at startup. The
  per-frame render is pure integer: a 32-bit shift and a 32-bit divide.

  ADDRESS MAP (part 003)
    Demo_Scene2            10b8:0592     Stars_ProjectAndPlot  10b8:0000
    Stars_RunScene         10b8:0126     Stars_InitPalette     10b8:04c3
    Stars_Generate         10b8:05f2     DegToRad              10b8:0487
    Math_DivLong           10b8:07f4     VGA_PutPixel          12f8:0048
    VirtScr_Clear          12f8:00c9     VGA_CopyScreen        12f8:00ad
    RTL_Sin  137b:3252     RTL_Cos  137b:3257    RTL_Shl32  137b:36f2
  =========================================================================== }

unit Part3Stars;

interface

procedure Scene2;

implementation

uses VGA, Crt;

const
  NumPoints    = 500;
  RecSize      = 14;                    { bytes per working record }
  ArraySize    = NumPoints * RecSize;   { 7000 -- GetMem'd twice }

  TubeRadius   = 40.0;      { CS:$05EE -- Single }
  ProjShift    = 8;         { CX passed to RTL_Shl32: X*256 before the divide }

  ZStep        = 30;        { per frame, toward the viewer }
  ZWrap        = -500;      { recycle distance }
  ZNear        = -10;       { past this the point has flown by }
  ZPlotNear    = -3;        { nearer than this is not drawn }
  ZPlotFar     = -500;

  NumWaypoints = 50;
  DataOfs      = $0C0276;   { NEUROSIS.DAT seek -- 787062 }
  DataSize     = 3000;      { 500 six-byte records; the scene walks 50 }
  DataAddr     = $B250;

  CollapseFrames = 32;      { DS:$02A6 }

  ScrW = 320;  ScrH = 200;
  CentreX = 160;  CentreY = 100;

type
  { 14 bytes. X and Y are LongInt because the generator scales them by 40 and
    the projector shifts them left by 8 before dividing -- both need the range. }
  TPoint = record
    X    : LongInt;        { +0  }
    Y    : LongInt;        { +4  }
    Z    : Integer;        { +8  }
    XOfs : Integer;        { +10 }
    YOfs : Integer;        { +12 }
  end;
  TPointArray = array[1..NumPoints] of TPoint;

  TWaypoint = record PanX, PanY, Hold : Integer; end;   { 6 bytes }
  TPlot     = record Colour : Byte; X, Y : Integer; end; { 5 bytes }

var
  Live, Source : ^TPointArray;                          { DS:$A880, DS:$A884 }
  Waypoints    : array[1..NumWaypoints] of TWaypoint;   { in the loaded block }
  Display      : array[1..NumPoints] of TPlot;          { DS:$A88C }
  DisplayCount : Integer;                               { DS:$BE0C }
  PanX, PanY   : Integer;                               { DS:$BE0A, DS:$BE08 }
  WaypointIdx  : Integer;                               { DS:$BE0E }

{ --------------------------------------------------------------------------
  Stars_Generate (10b8:05f2)

  The point cloud is NOT loaded from disk -- it is generated here. Each point
  gets a random angle on a circle of radius 40, and a depth equal to minus its
  index, so the 500 points are spread evenly from Z=-1 to Z=-500: a tube.

  This is the only floating point in the scene.
  -------------------------------------------------------------------------- }
procedure Generate;
var
  I     : Integer;
  A     : Real;
begin
  GetMem(Live,   ArraySize);
  GetMem(Source, ArraySize);

  I := 1;
  while I <= NumPoints do
  begin
    A := Random(360) * Pi / 180;              { DegToRad, 10b8:0487 }
    Live^[I].X := Round(Cos(A) * TubeRadius); { RTL_Cos 137b:3257 -> +0 }
    Live^[I].Y := Round(Sin(A) * TubeRadius); { RTL_Sin 137b:3252 -> +4 }
    Live^[I].XOfs := CentreX;
    Live^[I].YOfs := CentreY;

    { Reject a point that rounded to dead centre, otherwise it would sit on
      the vanishing point forever. }
    if (Live^[I].X <> 0) or (Live^[I].Y <> 0) then
    begin
      Live^[I].Z := -I;
      Inc(I);
    end;
  end;

  Move(Live^, Source^, ArraySize);            { Source is the reset template }
end;

{ --------------------------------------------------------------------------
  Stars_InitPalette (10b8:04c3)
  A 13-step blue depth ramp: colour 1 brightest, 13 black. Matches the
  shading term (-Z shr 6) + 1 used by the plotter.
  -------------------------------------------------------------------------- }
procedure InitPalette;
begin
  SetMode13h;
  SetRGB( 1, 0, 0, $3C);   SetRGB( 2, 0, 0, $37);
  SetRGB( 3, 0, 0, $32);   SetRGB( 4, 0, 0, $2D);
  SetRGB( 5, 0, 0, $28);   SetRGB( 6, 0, 0, $23);
  SetRGB( 7, 0, 0, $1E);   SetRGB( 8, 0, 0, $19);
  SetRGB( 9, 0, 0, $14);   SetRGB(10, 0, 0, $0F);
  SetRGB(11, 0, 0, $0A);   SetRGB(12, 0, 0, $05);
  SetRGB(13, 0, 0, $00);
  PanX := 0;  PanY := 0;  DisplayCount := 0;
end;

{ --------------------------------------------------------------------------
  Stars_ProjectAndPlot (10b8:0000)

  Fixed-point perspective: (X shl 8) div Z. The shift is done by RTL_Shl32
  (137b:36f2), a 32-bit DX:AX shl CX that branches on CPU type -- a loop on
  8086, a single shift on 386. The divide is Math_DivLong (10b8:07f4).
  -------------------------------------------------------------------------- }
procedure ProjectAndPlot(Dest : Word);
var
  I, SX, SY : Integer;
begin
  for I := 1 to NumPoints do
    with Live^[I] do
      if (Z < ZPlotNear) and (Z > ZPlotFar) then
      begin
        SX := XOfs + ((X shl ProjShift) div Z);
        SY := YOfs + ((Y shl ProjShift) div Z);
        if (SX <> 0) and (SX < ScrW) and (SY <> 0) and (SY < ScrH) then
          { PutPixel is (Segment, Colour, Y, X) -- see VGA.PAS, where the
            order is fixed by the transcribed assembler. }
          PutPixel(SX, SY, ((-Z) shr 6) + 1, Dest);
      end;
end;

{ --------------------------------------------------------------------------
  Stars_RunScene (10b8:0126)
  -------------------------------------------------------------------------- }
procedure RunScene;
var
  I, T, SX, SY : Integer;
begin
  { ---- Phase 1: fly the tube, stepping back through the waypoint table ---- }
  WaypointIdx := NumWaypoints;
  repeat
    for I := 1 to NumPoints do
      with Live^[I] do
      begin
        Inc(Z, ZStep);
        if Z > ZNear then                   { flown past -- recycle }
        begin
          Inc(Z, ZWrap);                    { push back 500 }
          XOfs := Source^[I].XOfs + PanX;
          YOfs := Source^[I].YOfs + PanY;
          X    := Source^[I].X;
          Y    := Source^[I].Y;
        end;
      end;

    ClearVirtual;
    ProjectAndPlot(VirtScrSeg);
    CopyScreen(VirtScrSeg, $A000);

    if Waypoints[WaypointIdx].Hold < 1 then
    begin
      Dec(WaypointIdx);
      PanX := Waypoints[WaypointIdx].PanX;
      PanY := Waypoints[WaypointIdx].PanY;
    end
    else
      Dec(Waypoints[WaypointIdx].Hold);
  until WaypointIdx = 0;

  { ---- Phase 2: freeze the visible points into a display list ---- }
  DisplayCount := 0;
  for I := 1 to NumPoints do
    with Live^[I] do
    begin
      SX := XOfs + ((X shl ProjShift) div Z);
      SY := YOfs + ((Y shl ProjShift) div Z);
      if (SX > 0) and (SX < ScrW) and (SY > 0) and (SY < ScrH) then
      begin
        Inc(DisplayCount);
        Display[DisplayCount].X      := SX;
        Display[DisplayCount].Y      := SY;
        Display[DisplayCount].Colour := ((-Z) shr 6) + 1;
      end;
    end;

  { ---- Phase 3: collapse everything into the centre over 32 frames ---- }
  for T := 1 to CollapseFrames do
  begin
    ClearVirtual;
    for I := 1 to DisplayCount do
      with Display[I] do
        PutPixel(X + (LongInt(CentreX - X) * T) div CollapseFrames,
                 Y + (LongInt(CentreY - Y) * T) div CollapseFrames,
                 Colour, VirtScrSeg);
    CopyScreen(VirtScrSeg, $A000);
  end;

  FreeMem(Live,   ArraySize);
  FreeMem(Source, ArraySize);
end;

{ --------------------------------------------------------------------------
  Demo_Scene2 (10b8:0592)

  ASSETS  NEUROSIS.DAT $0C0276, 3000 bytes:
            assets/part003/stars_waypoints.bin
          500 six-byte records (PanX, PanY, Hold); the scene walks indices
          50 down to 1. The point cloud is NOT an asset -- Generate builds
          it procedurally. See docs/07-part3-scene2-stars.md.
  -------------------------------------------------------------------------- }
procedure Scene2;
var
  F : file;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Mem[DSeg:DataAddr], DataSize);   { waypoint table }
  Close(F);

  Generate;
  InitPalette;
  RunScene;
end;

end.

{ ===========================================================================
  RESOLVED (values read from the listing, not the decompiler)

  * Tube radius   40.0     CS:$05EE, Single, multiplied into Cos/Sin at generate
  * Projection    shl 8    CX=8 passed to RTL_Shl32, so X*256 before div Z
  * Collapse      32       DS:$02A6
  * Z range       -1..-500 Z is simply minus the point index
  * X uses RTL_Cos (137b:3257), Y uses RTL_Sin (137b:3252) -- read directly
    off the two CALLF targets in the generator, which also settles the
    Sin/Cos identification used by Scene 1.

  CORRECTION
  * An earlier draft said the point cloud was loaded from NEUROSIS.DAT. It is
    not -- Stars_Generate builds it procedurally and then Moves it into the
    Source template. The 3000-byte block from the file is the waypoint data.

  RESOLVED -- THE UNWALKED TAIL OF THE PAN TABLE
  * The block is declared as 500 six-byte records but only 56 of them are
    non-zero. Records 1..57 hold real (PanX, PanY, Hold) data; from record 58
    to record 500 every byte is zero.
  * The scene walks indices 50 down to 1, so records 51..57 are authored data
    that is never reached, and the remaining 443 records are pure padding.
    The table was simply declared at a round 500 and filled as far as the
    choreography needed.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
