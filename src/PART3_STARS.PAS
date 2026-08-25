{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 2
  Reconstructed from NEUROSIS_003_fpu.exe.

  A depth-shaded 3-D star tube. 500 points sit on a circle of radius 40 at
  evenly spaced depths, fly toward the viewer, and are perspective-divided
  onto the screen. A 50-entry waypoint table pans the tube around while it
  runs, and the scene ends with every point collapsing into screen centre.

  Unlike Scene 1 (mode-X, hardware panning) this is plain mode 13h with a
  software virtual screen -- the two scenes use quite different machinery.

  Floating point is used ONCE, to generate the point cloud, and that happens
  in the UNIT INITIALISATION section (1000:0037 calls 10b8:05f2 directly),
  not in Scene2. The per-frame render is pure integer: a 32-bit shift and a
  32-bit divide.

  THE PAN. Each point carries its own screen origin, XOfs/YOfs. A point only
  picks up the current PanX/PanY when it recycles past the viewer, so the pan
  washes through the tube from the near end rather than moving it all at
  once. The waypoint table drives PanX/PanY: index 50 counting down to 0,
  each record holding a hold count that stalls the walk for that many frames.
  With 56 authored records and hold counts in them the scene runs for several
  hundred frames, not fifty.

  ADDRESS MAP (part 003)
    Demo_Scene2            10b8:0592     Stars_ProjectAndPlot  10b8:0000
    Stars_RunScene         10b8:0126     Stars_InitPalette     10b8:04c3
    Stars_Generate         10b8:05f2     DegToRad              10b8:0487
    Math_DivLong           10b8:07f4     VGA_PutPixel          12f8:0048
    VirtScr_Clear          12f8:00c9     VGA_CopyScreen        12f8:00ad
    RTL_Sin  137b:3252     RTL_Cos  137b:3257    RTL_Shl32  137b:36f2
  =========================================================================== }

unit Part3Stars;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

{$G+}   { 286: Stars_ProjectAndPlot 10b8:0000 opens ENTER 4; every framed
          routine in 10b8 does. }

{$N+}   { 80x87 CODE ON. The original's segment 10b8 carries 7 emulator
          traps -- INT $34..$3E, which is how an 80x87 instruction ships
          under $E+ -- and this unit had no N directive at all, so it took
          the command line's default and emitted NONE. $N- generates no
          80x87 instructions and therefore no traps either: floating point
          becomes far calls into the software six-byte-Real library, so a
          trap is positive evidence of $N+ rather than against it. Counted
          in 10b8. Nothing here gains a coprocessor --
          Turbo Pascal's emulator ran these in 1994 and runs them now. }

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

  ZStep        = 30;        { $1E per frame, toward the viewer }
  ZWrap        = -500;      { $1F4 subtracted -- recycle distance }
  ZNear        = -10;       { past this the point has flown by }
  ZPlotNear    = -3;        { nearer than this is not drawn }
  ZPlotFar     = -500;      { $FE0C }

  { The block really is 500 six-byte records; only 1..57 hold authored data
    and the scene walks 50 down to 1. See the note at the foot of the file. }
  NumWaypoints = 500;
  StartWaypoint = 50;       { $32 -- 10b8:012a }
  DataOfs      = $0C0276;   { NEUROSIS.DAT seek -- 787062 }
  DataSize     = 3000;      { $BB8 }

  ScrW = 320;  ScrH = 200;
  CentreX = 160;  CentreY = 100;

{ DS:$02A6. A typed constant, not a literal: the collapse loop's assembler
  divides by it in memory (10b8:0417 and 10b8:042d are IDIV [$02A6]), so it
  has to be addressable. }
const
  CollapseFrames : Integer = 32;

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

  { DS:$A888 and DS:$A88A. Both are unit-level in the original -- the loop
    counter is addressed as a bare global by every routine in the segment. }
  Angle        : Integer;
  Idx          : Integer;

  Display      : array[1..NumPoints] of TPlot;          { DS:$A88C }

  { DS:$B250. 500 six-byte records read straight off the DAT. The walk is
    Waypoints[50] down to Waypoints[1], and it reads Waypoints[0] once on the
    way out -- see RunScene -- so the array starts at zero. }
  { [1..500], AND THE SIX BYTES THAT USED TO ARGUE FOR A ZEROTH ENTRY WERE
    SOMEBODY ELSE'S. Declaring it [0..500] measured better for a long time and
    the reason has now been found and fixed: PART3_TUNNEL was missing 132 bytes
    -- a unit-level file record and four unread bytes -- so this unit's data
    started 132 bytes low and a 501-record array put six of them back by
    accident. With TUNNEL corrected this unit's variables land on the original's
    addresses exactly, and the extra record became six bytes of overshoot.

    The offsets were always the better argument: the table is at DS:$B250 and
    PanY at $BE08, which is 3,000 bytes, and DataSize says 3000 three lines
    above. It took the measurement agreeing with them to act on it. }
  Waypoints    : array[1..NumWaypoints] of TWaypoint;

  { PanY FIRST: the recorded addresses put it at $BE08 and PanX at $BE0A, so
    the lower of the two was declared second. }
  PanY, PanX   : Integer;                               { DS:$BE08, DS:$BE0A }
  DisplayCount : Integer;                               { DS:$BE0C }
  WaypointIdx  : Integer;                               { DS:$BE0E }

  { A SECOND 128-BYTE RECORD, UNIT-LEVEL AND NEVER REFERENCED, and it is here
    because two pieces of evidence that looked contradictory are both true.
    Demo_Scene2's own file record is a LOCAL -- 10b8:0592 opens ENTER $80,0 and
    10b8:0596 passes LEA DI,[BP-$80] to Assign -- so the handle the scene uses
    is in its frame. But there is ALSO a 128-byte gap between this unit's last
    referenced variable and PART3_MORPH's first, and removing it moved every
    variable in the part from $BE90 upward down by exactly 128. So the unit
    declares a second record it never opens, and the ENTER operand and the gap
    were measuring different things. }
  FUnused      : file;


{ --------------------------------------------------------------------------
  DegToRad (10b8:0487)
  -------------------------------------------------------------------------- }
function DegToRad(D : Real) : Real;
begin
  DegToRad := D * Pi / 180.0;
end;

{ --------------------------------------------------------------------------
  Stars_Generate (10b8:05f2) -- THE UNIT INITIALISATION SECTION.

  This is not called by Scene2. It is entry 14 in the unit-initialisation
  chain at 1000:0000, so the point cloud is built once when the program
  loads, long before the scene runs. RunScene frees both blocks at the end,
  which is why the scene cannot be run twice.

  The point cloud is NOT loaded from disk. Each point gets a random angle on
  a circle of radius 40 and a depth equal to minus its index, so the 500
  points spread evenly from Z=-1 to Z=-500: a tube. A point that rounds to
  dead centre is thrown away and re-rolled, otherwise it would sit on the
  vanishing point forever.

  The first point is written out longhand ahead of the loop (10b8:0613, with
  the field offsets constant-folded), with its Z set FIRST and no rejection
  test; every other point sets Z last, after the test. Reproduced as written.

  This is the only floating point in the scene.
  -------------------------------------------------------------------------- }
procedure Generate;
{ NO LOCAL COUNTER. 10b8:069d is `MOV WORD PTR [$A88A],2` and 10b8:06a5 is
  `INC WORD PTR [$A88A]` -- the loop runs on the UNIT-LEVEL Idx, which is
  already declared at that address and which the var block's own note says is
  unit-level in the original. A local gave [BP-2] and a frame, and the two
  never match however the body is written. }
begin
  GetMem(Live,   ArraySize);                  { 10b8:05f8 }
  GetMem(Source, ArraySize);                  { 10b8:0607 }

  Live^[1].Z := -1;                           { 10b8:0617 }
  Angle := Random(360);                       { 10b8:0620 }
  Live^[1].X := Round(Cos(DegToRad(Angle)) * TubeRadius);   { RTL_Cos 137b:3257 }
  Live^[1].Y := Round(Sin(DegToRad(Angle)) * TubeRadius);   { RTL_Sin 137b:3252 }
  Live^[1].XOfs := CentreX;
  Live^[1].YOfs := CentreY;

  for Idx := 2 to NumPoints do                  { 10b8:069d }
  begin
    repeat
      Angle := Random(360);
      Live^[Idx].X := Round(Cos(DegToRad(Angle)) * TubeRadius);
      Live^[Idx].Y := Round(Sin(DegToRad(Angle)) * TubeRadius);
      Live^[Idx].XOfs := CentreX;
      Live^[Idx].YOfs := CentreY;
    until (Live^[Idx].X <> 0) or (Live^[Idx].Y <> 0);   { 10b8:074e -- re-roll }
    Live^[Idx].Z := -Idx;                         { 10b8:077b }
  end;

  { 10b8:079c -- copied a record at a time, not in one 7,000-byte Move.
    Source is the reset template every recycled point is rebuilt from. }
  for Idx := 1 to NumPoints do
    Move(Live^[Idx], Source^[Idx], RecSize);
end;

{ --------------------------------------------------------------------------
  Stars_InitPalette (10b8:04c3)
  A 13-step blue depth ramp: colour 1 brightest, 13 black. Matches the
  shading term (-Z shr 6) + 1 used by the plotter.
  -------------------------------------------------------------------------- }
procedure InitPalette;
begin
  PanX := 0;  PanY := 0;  DisplayCount := 0;   { 10b8:04c6 -- before the mode }
  SetMode13h;                                  { 10b8:04d5 }
  SetRGB( 1, 0, 0, $3C);   SetRGB( 2, 0, 0, $37);
  SetRGB( 3, 0, 0, $32);   SetRGB( 4, 0, 0, $2D);
  SetRGB( 5, 0, 0, $28);   SetRGB( 6, 0, 0, $23);
  SetRGB( 7, 0, 0, $1E);   SetRGB( 8, 0, 0, $19);
  SetRGB( 9, 0, 0, $14);   SetRGB(10, 0, 0, $0F);
  SetRGB(11, 0, 0, $0A);   SetRGB(12, 0, 0, $05);
  SetRGB(13, 0, 0, $00);
end;

{ --------------------------------------------------------------------------
  Stars_ProjectAndPlot (10b8:0000)

  Fixed-point perspective: (X shl 8) div Z. The shift is done by RTL_Shl32
  (137b:36f2), a 32-bit DX:AX shl CX that branches on CPU type -- a loop on
  8086, a single shift on 386. The divide is Math_DivLong (10b8:07f4), which
  is three 386 instructions round an IDIV ESI, so scene 2 needs a 386 even
  though nothing else in the part does.

  THE BOUNDS TESTS ARE UNSIGNED. 10b8:00dd and 00e4 are JBE and JNC, not
  JLE and JGE, so a point that projects to a negative X or Y becomes a large
  positive and is rejected by the `>= 320` / `>= 200` half of the test rather
  than passing the `< 320` half. SX and SY are Word here for that reason.
  The display-list pass in RunScene is the other way round -- it really does
  use signed compares (10b8:035c is JLE) -- so the two are not interchangeable.
  -------------------------------------------------------------------------- }
procedure ProjectAndPlot(Dest : Word);
var
  SX, SY : Word;
begin
  for Idx := 1 to NumPoints do
    with Live^[Idx] do
      if (Z < ZPlotNear) and (Z > ZPlotFar) then
      begin
        SX := XOfs + ((X shl ProjShift) div Z);
        SY := YOfs + ((Y shl ProjShift) div Z);
        if (SX <> 0) and (SX < ScrW) and (SY <> 0) and (SY < ScrH) then
          PutPixel(SX, SY, ((-Z) shr 6) + 1, Dest);
      end;
end;

{ --------------------------------------------------------------------------
  Stars_RunScene (10b8:0126)

  Phase 3 -- the collapse -- has a hand-assembler inner loop. Everything
  round it (the frame loop, ClearVirtual, CopyScreen) is compiled Pascal, so
  only the plotting loop is transcribed.
  -------------------------------------------------------------------------- }
procedure RunScene;
var
  T      : Integer;      { [BP-2]  -- the collapse frame, read by the asm }
  SX, SY : Integer;      { [BP-4], [BP-6] -- signed here, see below }
  Col    : Byte;         { [BP-9]  -- ditto }
begin
  { ---- Phase 1: fly the tube, stepping back through the waypoint table ---- }
  WaypointIdx := StartWaypoint;                { 10b8:012a }
  repeat
    for Idx := 1 to NumPoints do
      with Live^[Idx] do
      begin
        Inc(Z, ZStep);                         { 10b8:014b }
        if Z > ZNear then                      { flown past -- recycle }
        begin
          Inc(Z, ZWrap);                       { 10b8:0183 -- push back 500 }
          XOfs := Source^[Idx].XOfs + PanX;    { 10b8:01a6 -- pick up the pan }
          YOfs := Source^[Idx].YOfs + PanY;    { 10b8:01ca }
          X    := Source^[Idx].X;              { 10b8:01ea }
          Y    := Source^[Idx].Y;              { 10b8:0210 }
        end;
      end;

    ClearVirtual;                              { 10b8:023c }
    ProjectAndPlot(VirtScrSeg);                { 10b8:0245 }
    CopyScreen(VirtScrSeg, $A000);             { 10b8:024f }

    { 10b8:0260 -- hold on this waypoint, or step to the next one }
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
  { Signed compares here (10b8:035c JLE, 0367 JGE, 036e JGE, 0374 JLE) --
    unlike ProjectAndPlot above. }
  DisplayCount := 0;
  for Idx := 1 to NumPoints do
    with Live^[Idx] do
    begin
      SX := XOfs + ((X shl ProjShift) div Z);
      SY := YOfs + ((Y shl ProjShift) div Z);
      if (SX > 0) and (SX < ScrW) and (SY < ScrH) and (SY > 0) then
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

    { ----------------------------------------------------------------------
      10b8:03f9 -- HAND ASSEMBLER, transcribed verbatim.

      One pass over the display list, moving every dot a fraction T/32 of
      the way from where it was to screen centre and plotting it. It walks
      the five-byte records with LODSB/LODSW rather than indexing them,
      counts down with LOOP, and writes through the row table itself instead
      of calling PutPixel -- so there is no call, no multiply and no bounds
      test in the loop at all.

      The interpolation is done in 32 bits: CWD sign-extends the difference
      before IMUL, so the product is DX:AX and the following IDIV divides
      the full 32-bit value. Writing it in Pascal with Integer operands
      would overflow -- (CentreY - Y) can reach 100 and T reaches 32, which
      is fine, but (CentreX - X) reaches 160 and 160*32 = 5120 is only safe
      by luck; the original never relies on that.

      There is no guard on DisplayCount being zero. LOOP with CX = 0 runs
      65,536 times, and the original has that hole too.

      EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

          for I := 1 to DisplayCount do
            with Display[I] do
              Mem[VirtScrSeg :
                  YOfs[Y + (LongInt(CentreY - Y) * T) div CollapseFrames]
                  + X + (LongInt(CentreX - X) * T) div CollapseFrames]
                := Colour;

      Where that is not the same thing: Colour is read FIRST, before either
      coordinate, because the records are walked in storage order by a
      pointer that only ever moves forward -- LODSB then LODSW then LODSW is
      one pass over the record with no addressing arithmetic whatsoever.
      ---------------------------------------------------------------------- }
    asm
      MOV  AX, OFFSET Display   { DS:$A88C -- the first display record       }
      MOV  SI, AX               { SI walks the list, one record per pass     }
      MOV  AX, [VirtScrSeg]     { DS:$E770                                   }
      MOV  ES, AX               { ES: is where the dots go                   }
      MOV  CX, [DisplayCount]   { DS:$BE0C -- the LOOP counter               }
    @@Dot:                    { <- once per display record                 }
      LODSB                     { AL := Colour; SI now points at X           }
      MOV  Col, AL              { stash it -- AX is needed for the maths     }

      LODSW                     { AX := X; SI now points at Y                }
      MOV  BX, AX               { BX := X, kept for the ADD below            }
      MOV  AX, 160              { CentreX                                    }
      SUB  AX, BX               { AX := CentreX - X, the distance to travel  }
      CWD                       { sign-extend it into DX:AX                  }
      IMUL T                    { DX:AX := (CentreX - X) * frame             }
      IDIV [CollapseFrames]     { AX := that / 32 -- the fraction covered    }
      ADD  AX, BX               { AX := X + the step = this frame's X        }
      MOV  BX, AX               { via BX, exactly as the original does        }
      MOV  DI, BX               { DI := screen X                             }

      LODSW                     { AX := Y; SI now points at the next record  }
      MOV  BX, AX               { BX := Y                                    }
      MOV  AX, 100              { CentreY                                    }
      SUB  AX, BX               { AX := CentreY - Y                          }
      CWD                       { sign-extend into DX:AX                     }
      IMUL T                    { DX:AX := (CentreY - Y) * frame             }
      IDIV [CollapseFrames]     { AX := that / 32                            }
      ADD  AX, BX               { AX := this frame's Y                       }
      MOV  BX, AX               { BX := screen Y                             }
      ADD  BX, BX               { BX := Y * 2, a word index                  }
      ADD  DI, [BX + OFFSET YOfs]  { + YOfs[Y] = Y*320, so DI is the offset  }
                                {   of the pixel. DS:$E772 is VGA's table.   }
      MOV  AL, Col              { get the colour back                        }
      MOV  ES:[DI], AL          { plot it                                    }
      LOOP @@Dot                { next record until CX runs out              }
    end;

    CopyScreen(VirtScrSeg, $A000);             { 10b8:044a }
  end;

  FreeMem(Live,   ArraySize);                  { 10b8:0462 }
  FreeMem(Source, ArraySize);                  { 10b8:0472 }
end;

{ --------------------------------------------------------------------------
  Demo_Scene2 (10b8:0592)

  ASSETS  NEUROSIS.DAT $0C0276, 3000 bytes:
            assets/part003/stars_waypoints.bin
          500 six-byte records (PanX, PanY, Hold); the scene walks indices
          50 down to 1. The point cloud is NOT an asset -- the unit's
          initialisation section builds it procedurally.
          See docs/07-part3-scene2-stars.md.
  -------------------------------------------------------------------------- }
procedure Scene2;
var
  { A LOCAL, and the frame settles it against the note this replaces. 10b8:0592
    opens ENTER $80,0 and 10b8:0596 passes LEA DI,[BP-$80] to Assign, so the
    file record is a frame slot -- 128 bytes of it, which is the whole frame.
    The note it replaces argued unit-level from a 128-byte GAP between this
    unit's last variable and the morph unit's first; a gap of the right size is
    circumstantial where an ENTER operand is not, so the gap belongs to
    something else and is still unaccounted for. }
  F : file;                     { [BP-$80] }
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  WaypointIdx := 4;             { 10b8:05c0 -- dead: RunScene sets it to 50
                                  before ever reading it. Kept because it is
                                  there. }
  BlockRead(F, Waypoints[1], DataSize);        { 10b8:05d7 -> DS:$B250 }
  Close(F);

  InitPalette;                                 { 10b8:05e6 }
  RunScene;                                    { 10b8:05e9 }
end;

begin
  { 1000:0037 -- the unit initialisation. The original has Generate's code
    directly in this section rather than in a procedure it calls; the extra
    call is the only difference. }
  Generate;
end.

{ ===========================================================================
  RESOLVED (values read from the listing, not the decompiler)

  * Tube radius   40.0     CS:$05EE, Single, multiplied into Cos/Sin at generate
  * Projection    shl 8    CX=8 passed to RTL_Shl32, so X*256 before div Z
  * Collapse      32       DS:$02A6, a typed constant -- the asm divides by it
  * Z range       -1..-500 Z is simply minus the point index
  * X uses RTL_Cos (137b:3257), Y uses RTL_Sin (137b:3252) -- read directly
    off the two CALLF targets in the generator, which also settles the
    Sin/Cos identification used by Scene 1.

  CORRECTIONS made after running it against ORIG3.EXE

  * THE WAYPOINT TABLE WAS NEVER BEING LOADED. The BlockRead went to a raw
    Mem[DSeg:$B250], which is where the block sits in the ORIGINAL's data
    segment and has nothing to do with where Turbo Pascal puts our array. So
    Waypoints stayed all zeros: every Hold read as 0, the walk stepped one
    index a frame and ended after fifty, and PanX/PanY stayed 0 so the tube
    never moved. Both reported symptoms -- "does not move around the screen"
    and "ends sooner" -- were this one bug. It now reads into the array.

  * ProjectAndPlot's bounds tests are UNSIGNED in the binary (JBE/JNC at
    10b8:00dd and 00e4). They had been transcribed as signed, which let a
    point projecting to a negative X or Y through the `< 320` test and
    plotted it wrapped onto the previous row. SX and SY are Word now. The
    display-list pass in phase 2 genuinely is signed (JLE/JGE at 10b8:035c
    onward), so the two differ on purpose.

  * The collapse loop is hand assembler (LODSB/LODSW, LOOP, the row table
    indexed inline) and had been rewritten as Pascal. It is back verbatim.

  * Generate is the unit INITIALISATION section, not part of Scene2 --
    1000:0037 calls 10b8:05f2 directly, as entry 14 of the init chain.

  * An earlier draft said the point cloud was loaded from NEUROSIS.DAT. It is
    not -- Generate builds it procedurally and copies it into the Source
    template. The 3000-byte block from the file is the waypoint data.

  RESOLVED -- THE UNWALKED TAIL OF THE PAN TABLE
  * The block is declared as 500 six-byte records but only 56 of them are
    non-zero. Records 1..57 hold real (PanX, PanY, Hold) data; from record 58
    to record 500 every byte is zero.
  * The scene walks indices 50 down to 1, so records 51..57 are authored data
    that is never reached, and the remaining 443 records are pure padding.
    The table was simply declared at a round 500 and filled as far as the
    choreography needed.
  * Index 0 IS read, once: the last time round the loop WaypointIdx drops to
    0 and PanX/PanY are loaded from Waypoints[0] before the test ends the
    loop. In the original that reads the six bytes below the block; here the
    array starts at 0 so it reads zeros. The values are never used either
    way -- the loop exits immediately afterwards.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
