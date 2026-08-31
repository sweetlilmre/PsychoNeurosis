{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 2
  Reconstructed from NEUROSIS_003_fpu.exe.

  A depth-shaded 3-D star tube. 500 points sit on a circle of radius 40 at
  evenly spaced depths, fly toward the viewer, and are perspective-divided
  onto the screen. A 50-entry waypoint table pans the tube around while it
  runs, and the scene ends with every point collapsing into screen centre.

  Unlike Scene 1 (mode-X, hardware panning) this is plain mode 13h with a
  software virtual screen -- the two scenes use quite different machinery.

  THE PAN. Each point carries its own screen origin, XOfs/YOfs. A point only
  picks up the current PanX/PanY when it recycles past the viewer, so the pan
  washes through the tube from the near end rather than moving it all at
  once. The waypoint table drives PanX/PanY: index 50 counting down to 0,
  each record holding a hold count that stalls the walk for that many frames.
  With 56 authored records and hold counts in them the scene runs for several
  hundred frames, not fifty. }

unit P3Stars;

{ Data alignment off -- a loop temporary sits at an odd offset, which only
  byte alignment produces. }
{$A-}
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

{ 286 instructions are permitted. }
{$G+}

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

{ Where each asset sits inside NEUROSIS.DAT. }
{$I gen/DATOFS.INC}

const
  NumPoints    = 500;
  RecSize      = 14;                    { bytes per working record }
  ArraySize    = NumPoints * RecSize;   { GetMem'd twice }

  TubeRadius   = 40.0;      { Single }
  ProjShift    = 8;         { CX passed to RTL_Shl32: X*256 before the divide }

  ZStep        = 30;        { $1E per frame, toward the viewer }
  ZWrap        =  500;      { $1F4 subtracted -- recycle distance }
  ZNear        = -10;       { past this the point has flown by }
  ZPlotNear    = -3;        { nearer than this is not drawn }
  ZPlotFar     = -500;      { $FE0C }

  { The block really is 500 six-byte records; only 1..57 hold authored data
    and the scene walks 50 down to 1. See the note at the foot of the file. }
  NumWaypoints = 500;
  StartWaypoint = 50;       { the waypoint the flight starts from }
  DataOfs      = DAT_P3_STARSWPT;   { $0C0276 -- NEUROSIS.DAT seek -- 787062 }
  DataSize     = 3000;      { $BB8 }

  ScrW = 320;  ScrH = 200;
  CentreX = 160;  CentreY = 100;

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
  Live, Source : ^TPointArray;

  { Both are unit-level in the original -- the loop
    counter is addressed as a bare global by every routine in the segment. }
  Angle        : Integer;
  Idx          : Integer;

  Display      : array[1..NumPoints] of TPlot;

  { 500 six-byte records read straight off the DAT. The walk is
    Waypoints[50] down to Waypoints[1], and it reads Waypoints[0] once on the
    way out -- see RunScene -- so the array starts at zero. }
  { [1..500], AND THE SIX BYTES THAT USED TO ARGUE FOR A ZEROTH ENTRY WERE
    SOMEBODY ELSE'S. Declaring it [0..500] measured better for a long time and
    the reason has now been found and fixed: PART3_TUNNEL was missing 132 bytes
    -- a unit-level file record and four unread bytes -- so this unit's data
    started 132 bytes low and a 501-record array put six of them back by
    accident. With TUNNEL corrected this unit's variables land on the original's
    addresses exactly, and the extra record became six bytes of overshoot. }
  Waypoints    : array[1..NumWaypoints] of TWaypoint;

  { PanY FIRST: the recorded addresses put it at $BE08 and PanX at $BE0A, so
    the lower of the two was declared second. }
  PanY, PanX   : Integer;
  DisplayCount : Integer;
  WaypointIdx  : Integer;

  FUnused      : file;



{ --------------------------------------------------------------------------
  Stars_ProjectAndPlot
  Fixed-point perspective: (X shl 8) div Z. The shift goes through a runtime
  helper that branches on processor type -- a loop on an 8086, a single
  instruction on a 386 -- and the divide is this unit's own 386 helper, which
  is why the scene needs a 386 even }
{$L STARMATH.OBJ}
function MulLong(A, B : LongInt) : LongInt;  external;
function DivLong(A, B : LongInt) : LongInt;  external;

procedure ProjectAndPlot(Dest : Word);
var
  SX, SY : Word;                       { the whole frame }
begin
  for Idx := 1 to NumPoints do
    if (Live^[Idx].Z < ZPlotNear) and (Live^[Idx].Z > ZPlotFar) then
    begin
      SX := Live^[Idx].XOfs
            + DivLong(Live^[Idx].X shl ProjShift, Live^[Idx].Z);
      SY := Live^[Idx].YOfs
            + DivLong(Live^[Idx].Y shl ProjShift, Live^[Idx].Z);
      if (SX > 0) and (SX < ScrW) and (SY > 0) and (SY < ScrH) then
        PutPixel(SX, SY, ((-Live^[Idx].Z) shr 6) + 1, Dest);
    end;
end;

{ --------------------------------------------------------------------------
  Stars_RunScene
  Phase 3 -- the collapse -- has a hand-assembler inner loop. Everything
  round it (the frame loop, ClearVirtual, CopyScreen) is compiled Pascal, so
  only the plotting loop is transcribed.
  -------------------------------------------------------------------------- }
procedure RunScene;
var
  { THE FRAME IS ELEVEN BYTES ROUNDED TO TWELVE, and every slot is accounted
    for now. ENTER $0C, and the references are

    THE EARLIER ELEVEN WERE A COINCIDENCE. This declared seven bytes and a
    `with` over Live^[Idx], and a `with` costs four for the record's address --
    seven plus four is also eleven, so the frame matched while both halves
    were wrong. }
  T      : Integer;      { the collapse frame, read by the asm }
  SX, SY : Integer;      { signed here, see below }
  Spare  : Integer;      { assigned 0 and never read }
  Col    : Byte;
begin
  { ---- Phase 1: fly the tube, stepping back through the waypoint table ---- }
  WaypointIdx := StartWaypoint;
  repeat
    for Idx := 1 to NumPoints do
    begin
      Live^[Idx].Z := Live^[Idx].Z + ZStep;
      if Live^[Idx].Z > ZNear then             { flown past -- recycle }
      begin
        Live^[Idx].Z := Live^[Idx].Z - ZWrap;  { push back 500 }
        Live^[Idx].XOfs := Source^[Idx].XOfs + PanX;   { pick up the pan }
        Live^[Idx].YOfs := Source^[Idx].YOfs + PanY;
        Live^[Idx].X    := Source^[Idx].X;
        Live^[Idx].Y    := Source^[Idx].Y;
      end;
    end;

    ClearScreen(VirtScrSeg, 0);
    ProjectAndPlot(VirtScrSeg);
    CopyScreen(VirtScrSeg, $A000);

    { hold on this waypoint, or step to the next one }
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
  for Idx := 1 to NumPoints do
  begin
    SX := Live^[Idx].XOfs
          + DivLong(Live^[Idx].X shl ProjShift, Live^[Idx].Z);
    SY := Live^[Idx].YOfs
          + DivLong(Live^[Idx].Y shl ProjShift, Live^[Idx].Z);
    if (SX > 0) and (SX < ScrW) and (SY < ScrH) and (SY > 0) then
    begin
      DisplayCount := DisplayCount + 1;
      Display[DisplayCount].X      := SX;
      Display[DisplayCount].Y      := SY;
      Display[DisplayCount].Colour := ((-Live^[Idx].Z) shr 6) + 1;
    end;
  end;

  Spare := 0;

  { ---- Phase 3: collapse everything into the centre over 32 frames ---- }
  for T := 1 to CollapseFrames do
  begin
    ClearScreen(VirtScrSeg, 0);

    { ----------------------------------------------------------------------
      HAND ASSEMBLER, transcribed verbatim.

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
      MOV  AX, OFFSET Display   { the first display record       }
      MOV  SI, AX               { SI walks the list, one record per pass     }
      MOV  AX, [VirtScrSeg]
      MOV  ES, AX               { ES: is where the dots go                   }
      MOV  CX, [DisplayCount]   { the LOOP counter               }
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
                                {   of the pixel, from VGA's row table.      }
      MOV  AL, Col              { get the colour back                        }
      MOV  ES:[DI], AL          { plot it                                    }
      LOOP @@Dot                { next record until CX runs out              }
    end;

    CopyScreen(VirtScrSeg, $A000);
  end;

  FreeMem(Live,   ArraySize);
  FreeMem(Source, ArraySize);
end;

{ --------------------------------------------------------------------------
  DegToRad
  -------------------------------------------------------------------------- }
function DegToRad(D : Real) : Real;  far;
begin
  DegToRad := D * Pi / 180.0;
end;

{ --------------------------------------------------------------------------
  Stars_InitPalette
  A 13-step blue depth ramp: colour 1 brightest, 13 black. Matches the
  shading term (-Z shr 6) + 1 used by the plotter.
  -------------------------------------------------------------------------- }
procedure InitPalette;
begin
  PanX := 0;  PanY := 0;  DisplayCount := 0;   { before the mode }
  SetMode13h;
  SetRGB( 1, 0, 0, $3C);   SetRGB( 2, 0, 0, $37);
  SetRGB( 3, 0, 0, $32);   SetRGB( 4, 0, 0, $2D);
  SetRGB( 5, 0, 0, $28);   SetRGB( 6, 0, 0, $23);
  SetRGB( 7, 0, 0, $1E);   SetRGB( 8, 0, 0, $19);
  SetRGB( 9, 0, 0, $14);   SetRGB(10, 0, 0, $0F);
  SetRGB(11, 0, 0, $0A);   SetRGB(12, 0, 0, $05);
  SetRGB(13, 0, 0, $00);
end;

{ --------------------------------------------------------------------------
  Demo_Scene2
  ASSETS  NEUROSIS.DAT $0C0276, 3000 bytes:
            assets/part003/STARSWPT.BIN
          500 six-byte records (PanX, PanY, Hold); the scene walks indices
          50 down to 1. The point cloud is NOT an asset -- the unit's
          initialisation section builds it procedurally.
          See docs/07-part3-scene2-stars.md.
  -------------------------------------------------------------------------- }
procedure Scene2;
var
  F : file;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  WaypointIdx := 4;             { dead: RunScene sets it to 50
                                  before ever reading it. Kept because it is
                                  there. }
  BlockRead(F, Waypoints[1], DataSize);
  Close(F);

  InitPalette;
  RunScene;
end;

{ --------------------------------------------------------------------------
  Stars_Generate -- THE UNIT INITIALISATION SECTION.

  The point cloud is NOT loaded from disk. Each point gets a random angle on
  a circle of radius 40 and a depth equal to minus its index, so the 500
  points spread evenly from Z=-1 to Z=-500: a tube. A point that rounds to
  dead centre is thrown away and re-rolled, otherwise it would sit on the
  vanishing point forever.

  This is the only floating point in the scene.
  -------------------------------------------------------------------------- }
begin
  GetMem(Live,   ArraySize);
  GetMem(Source, ArraySize);

  Live^[1].Z := -1;
  Angle := Random(360);
  Live^[1].X := Round(Cos(DegToRad(Angle)) * TubeRadius);
  Live^[1].Y := Round(Sin(DegToRad(Angle)) * TubeRadius);
  Live^[1].XOfs := CentreX;
  Live^[1].YOfs := CentreY;

  for Idx := 2 to NumPoints do
  begin
    repeat
      Angle := Random(360);
      Live^[Idx].X := Round(Cos(DegToRad(Angle)) * TubeRadius);
      Live^[Idx].Y := Round(Sin(DegToRad(Angle)) * TubeRadius);
      Live^[Idx].XOfs := CentreX;
      Live^[Idx].YOfs := CentreY;
    until (Live^[Idx].X <> 0) or (Live^[Idx].Y <> 0);   { re-roll }
    Live^[Idx].Z := -Idx;
  end;

  { copied a record at a time, not in one 7,000-byte Move, and
    the copy is a STRUCTURED ASSIGNMENT, not a Move call. The two compile to
    the same three pushes and one far call; they differ only in WHICH runtime
    routine they name. A structured assignment names a plain forward
    CLD / REP MOVSB helper, 24 bytes; Move names the overlap-safe one that
    compares SI against DI first. Writing Move here was worth 32 bytes in the
    load image -- this was part 003's ONLY reference to that helper, so the
    original never links it, its System segment is 24 bytes shorter, and after
    paragraph rounding every byte of the 40 KB data image sat two paragraphs
    early. Nothing in the user segments differed; the call operand did.
    Source is the reset template every recycled point is rebuilt from. }
  for Idx := 1 to NumPoints do
    Source^[Idx] := Live^[Idx];
end.

{ ===========================================================================
  RESOLVED (values read from the listing, not the decompiler)

  CORRECTIONS made after running it against ORIG3.EXE

  * THE WAYPOINT TABLE WAS NEVER BEING LOADED. The BlockRead went to a raw
    Mem[DSeg:$B250], which is where the block sits in the ORIGINAL's data
    segment and has nothing to do with where Turbo Pascal puts our array. So
    Waypoints stayed all zeros: every Hold read as 0, the walk stepped one
    index a frame and ended after fifty, and PanX/PanY stayed 0 so the tube
    never moved. Both reported symptoms -- "does not move around the screen"
    and "ends sooner" -- were this one bug. It now reads into the array.

  * The collapse loop is hand assembler (LODSB/LODSW, LOOP, the row table
    indexed inline) and had been rewritten as Pascal. It is back verbatim.

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
