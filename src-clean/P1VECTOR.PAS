{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 5.

  PART 001'S CLOSING SCENE: a wireframe object spinning above its own
  reflection, and a wipe to finish. The scene draws in 16.16 fixed point
  throughout, projects each point through a perspective divide, sorts the faces
  by depth and fills them -- then mirrors the whole thing about a horizontal
  line to fake the reflection.

  It is the most arithmetic-heavy scene in part 001, which is why it links both
  386 objects: DEMOMATH for the fixed-point trigonometry and projection, and
  COPY32 for a screen copy done in dwords.

  =========================================================================== }

unit P1VECTOR;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }
{$A-}   { data alignment off -- measured, see the note in P2SOLID.PAS }

{$G+}
{ 80x87 CODE ON, and here it is a speed decision rather than a size one: the
  per-frame translation trigonometry calls Sin and Cos three times a frame, and
  under the software floating-point default those are far calls into a
  six-byte-Real library. With the coprocessor enabled they are instructions. }
{$N+}

interface

procedure Scene5;

implementation

uses VGA, Crt, DemoVT, FixMath;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

{$I gen/P1VECT.INC}      { const VecLogoA, VecGlobe : FLAT array[0..n*3-1] of Integer }

const
  { THE MOST POINTS ANY OBJECT IN THIS SCENE HAS, and it fixes the size of
    every buffer below -- a point is twelve bytes, so the arrays are 1,200.
    Neither object comes close to it: the globe has 36 and the logo 48. }
  MaxPoints    = 100;
  GlobePoints  = 36;       { points in the globe                            }
  LogoPoints   = 48;       { points in the logo                             }
  VectorFrames = 240;      { how long the scene runs                        }
  VectorStep   = 20;       { $14 -- 2.0 degrees per frame }
  VectorWrap   = 3590;     { $E06 -- and it RESETS to 0, it does not subtract }
  LocalStep    = 3;        { the object's own spin, degrees per frame       }
  OrbitStep    = 10;       { the orbit around the centre, degrees per frame }
  Horizon      = $85;      { 133 -- the mirror line }
  FadeSteps    = 40;       { steps in the closing fade                      }

  { THE PROJECTION'S VIEW SIZE, and the vertical half is DELIBERATELY ZERO.
    Project halves each of these to find the screen centre, so an X of 320
    gives a centre of 160 -- but a Y of 0 gives a centre of 0, which means the
    projection returns a negative offset from the top of the screen rather than
    a position on it.

    That is what makes the reflection work: the caller adds the projected Y to
    a fixed horizon line for the object and subtracts it for the reflection, so
    the horizon does ALL the vertical placement. Substituting a sensible
    ScrHeight div 2 here would break both halves at once.

  so the 133/134 line does ALL the vertical placement and the object hangs
  above it by however far the projection says. Substituting ScrHeight div 2
  here -- which is the obvious thing to assume, and what this file did --
  lifts the whole scene exactly 100 rows and floats it off the top. }
  { initialised data. They are declared as typed
    constants below rather than here, because Project reads them FROM MEMORY
    and the shared maths object resolves them by name. }

type
  { A point in the model, twelve bytes: three 16.16 fixed-point coordinates.
    Named rather than written out because it is passed BY VALUE in places, and
    Turbo Pascal copies a structured value parameter into the callee's frame. }
  TPoint3 = record
    X, Y, Z : LongInt;
  end;
  PPoint3 = ^TPoint3;

  { THE MODEL IS ONE RECORD -- its points and its position together -- and it
    is passed to the transform routines BY POINTER rather than read as a global.
    That is worth knowing because it means those routines could work on a second
    object; nothing in this scene has one. }
  TObj = record
    Pt  : array[1..MaxPoints] of TPoint3;   { offset 0, 1200 bytes }
    Pos : TPoint3;                          { offset $4B0 }
  end;
  PObj = ^TObj;

  TScreenPt = record
    X, Y, D : Integer;      { six bytes, matching the $A5F0 stride }
  end;

  { The projected points, twice MaxPoints because the reflection is projected
    as well as the object. Named because SortAll takes the array by pointer. }
  TScrArr = array[1..MaxPoints * 2] of TScreenPt;
  PScrArr = ^TScrArr;

{ ==========================================================================
  THE DECLARATION ORDER BELOW IS MEASURED, and it runs across three var blocks
  and the maths module's comment. Turbo Pascal lays a unit's DGROUP down in
  declaration order, so these addresses ARE the order:

      $A106  Obj        1212   the model: 100 points then the translation
      $A5C2  ObjMeta      52   the point sprite
      $A5F6  Scr        1200   200 six-byte screen records
      $AAA6  MCos1..MSin3 24   the maths module's sin/cos pairs
      $AABE  MScale        4
      $AAC2  Work          4
      $AAC6  WorkSeg       2
      $AAC8  PtCount       2
      $AACA  (six bytes)   6   declared, never referenced
      $AAD0  Angle         2
      $AAD2  OrbitAngle    2

  IT CLOSES WITHOUT A GAP, and that is the check on it: each address plus its
  size is the next address, from $A106 to $AAD4. The one that settles the
  shape is Scr -- 1200 bytes at $A5F6 ends at $AAA6, which is exactly where
  MCos1 is, so the maths declarations sit BETWEEN Scr and Work and not after
  everything. They were in a block of their own at the end here, and Angle,
  OrbitAngle, Work, WorkSeg and PtCount were all in front of the model, which
  put every one of these eleven addresses wrong.

  Reordering was not optional and not cosmetic: dsmap paired the original's
  $AAC6 with ours at a shift of -26018 and its $AAD0 at -26036, ten bytes
  apart in the original and twenty-eight in ours. Unequal shifts over a few
  bytes are an ORDER defect, not a block-placement one -- a block that had
  simply moved would carry one shift everywhere.
  ========================================================================== }
var
  Obj     : TObj;
  { the 52-byte point sprite: a 2-byte (W, H) header and 50 px. }
  ObjMeta : array[0..51] of Byte;
  { The projected screen points, filled by the transform and read by the sort. }
  Scr     : TScrArr;
{ --------------------------------------------------------------------------
  THE SHARED 386 MATHS MODULE.

  SinCos, RotatePoint and Project are 386 code and cannot be written in Turbo
  Pascal's built-in assembler, which stops at the 286. They live in
  src/asm/DEMOMATH.ASM, assembled separately and linked in below.

  THE NINE NAMES BELOW ARE THAT MODULE'S SHARED VARIABLES, and they must be
  declared BEFORE the link directive and spelled exactly as they are here --
  the assembler resolves them by name. }
var
  { Cosine then sine, per axis, in the order SinCos leaves them. RotatePoint
    reads all six; nothing else should write them. }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  { The projection scale, 16.16. }
  MScale : LongInt;

  { THE RENDER TARGET. Each frame copies the clean gradient out of the virtual
    screen into this buffer, draws the object and its reflection over it, and
    blits the result to video -- so the gradient never has to be redrawn. }
  Work    : Pointer;
  WorkSeg : Word;         { its segment; the offset is always zero }
  PtCount : Integer;      { how many points the current object has }
  { THE FRAME'S TRANSLATION, recomputed every frame from the two angles: a
    small vertical bob from the cosine of the spin, a wider horizontal swing
    from the sine of the orbit, and a large depth movement from the sine of the
    spin. The three magnitudes -- 5, 20 and 500 -- are what make the object
    appear to swing toward and away from the viewer rather than just rotate. }
  Dx      : Integer;
  Dy      : Integer;
  Dz      : Integer;
  { The object's own spin and its orbit around the centre, in tenths of a
    degree. Both advance every frame and wrap; the per-frame LOCAL angle used
    for the trigonometry above lives in Animate's own frame, not here. }
  Angle      : Integer;
  OrbitAngle : Integer;
  { The scene's file handle. Unit-level rather than local to the loader,
    which is the same split part 001 scene 1 uses. }
  F : file;


const
  { = 320, so the horizontal centre is 160.
 = 0, so the vertical centre is ZERO.

    so the 133/134 line does ALL the vertical placement and the object hangs
    above it by however far the projection says. Substituting ScrHeight here
    -- the obvious thing to assume, and what this file once did -- lifts the
    whole scene exactly 100 rows and floats it off the top.

    Project halves both, so these are the FULL view size, not the centre. }
  MViewW : Word = 320;
  MViewH : Word = 0;
  { = $A640, AND IT IS NOT AN ADDRESS. The original's initialised image
    holds `40 a6` here, immediately after MViewH, and ours held zero -- which is
    the -2 that dsmap reports across SIXTY-SEVEN paired references from $0286 to
    $ACFB, every one of them a byte of correct code measuring as wrong.

    $A640 is 42,560, and 42,560 is 320 * 133 -- the screen width times the
    mirror row, which is the byte offset of the horizon. Read as a DGROUP
    address it lands inside this unit's own Scr array at no element boundary, so
    the arithmetic reading is the one that survives.

    NOTHING IN THE PART REFERENCES IT. There is no absolute displacement of
    $0284 anywhere in the seven user segments, so it is a typed constant the
    original declares and never reads; it is here because the image says so and
    because every later byte of the image depends on it. }
  MirrorOfs : Word = ScrWidth * Horizon;            { = $A640 }

{ THE SCENE'S OWN SCREEN COPY, in dwords rather than words -- half the bus
  cycles of the shared VGA unit's version, which is why this scene carries its
  own. See src/asm/COPY32.ASM.

  LINKED FIRST OF THE TWO OBJECTS, and the order decides where each object's
  code lands in the segment. }
{$L COPY32.OBJ}
procedure Copy32(Src, Dest : Word);                       external;

{$L DEMOMATH.OBJ}
procedure SinCos(A : Integer; var C, S : LongInt);        external;
procedure RotatePoint(var X, Y, Z : LongInt);             external;
procedure Project(var X, Y, Z : LongInt);                 external;

{ --------------------------------------------------------------------------
  A POINT RECORD IS TWELVE BYTES -- three 32-bit fixed values -- and not the
  eighteen that three six-byte Borland Reals would need. Everything in this
  scene is 16.16, which is what makes that possible. }

procedure LoadObject(Coords : Pointer; Count : Integer);
type
  TTriples = array[1..MaxPoints, 1..3] of Integer;
var
  Src : ^TTriples;
  I   : Integer;
begin
  Src := Coords;
  PtCount := Count;
  for I := 1 to Count do
  begin
    Obj.Pt[I].X := IntToFixed(Src^[I, 1]);
    Obj.Pt[I].Y := IntToFixed(Src^[I, 2]);
    Obj.Pt[I].Z := IntToFixed(Src^[I, 3]);
  end;
end;

{ --------------------------------------------------------------------------
  Project(var X, Y, Z) -- perspective divide and screen offset

  Scale is [$AABE], set by Vector_Run to (ScreenWidth / 2) * 10 = 1600.0 --
  the same expression scene 4 uses. The source previously had a hand-picked
  `160 + (X*128) div (Z+256)`, which is neither the right scale nor the right
  depth origin.
  -------------------------------------------------------------------------- }

{ --------------------------------------------------------------------------
  Obj_TransformAll(Obj, A1, A2, A3), which fans out to TransformPoint

  A mirror pair about row 133.5 -- the floor, exactly where Vector_Load's
  gradient turns around. Both carry D = Trunc(Z) for the depth sort.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  TransformPoint, and it is A ROUTINE OF ITS OWN.

  Pascal convention pushes left to right, so the first parameter declared is
  the one pushed first and it sits at the HIGHEST offset. Hence this order.

  The caller widens each angle with CWD, so the parameters are LongInt while
  the arguments are Integer.
  -------------------------------------------------------------------------- }

procedure SortAll(Arr : PScrArr);
{ SORT ONLY -- the drawing loops belong to RenderObject, not here. It takes
  the array by pointer. }
  procedure DepthSort(Lo, Hi : Integer);
  var
    I, J, P : Integer;
    T       : TScreenPt;    { the swap temp }
    Unread  : Integer;
  begin
    I := Lo;  J := Hi;
    P := Arr^[(Lo + Hi) div 2].D;
    repeat
      while Arr^[I].D < P do I := I + 1;   { an ASSIGNMENT }
      while Arr^[J].D > P do J := J - 1;   { not Dec: see below }
      if I <= J then
      begin
        if Arr^[I].D <> Arr^[J].D then
        begin
          T := Arr^[I];  Arr^[I] := Arr^[J];  Arr^[J] := T;
        end;
      I := I + 1;  J := J - 1;
      end;
    until I > J;
    if Lo < J then DepthSort(Lo, J);
    if I < Hi then DepthSort(I, Hi);
  end;
begin
  DepthSort(1, PtCount);
  DepthSort(PtCount + 1, PtCount * 2);
end;

procedure TransformPoint(P          : TPoint3;
                         A1, A2, A3 : LongInt;
                         TX, TY, TZ : LongInt;
                         I          : Integer);
var
  Sx, Sy : LongInt;

  Dead1, Dead2, Dead3, Dead4, Dead5 : LongInt;
begin
  RotatePoint(P.X, P.Y, P.Z);

  P.X := P.X + TX;
  P.Y := P.Y + TY;
  P.Z := P.Z + TZ;

  Project(P.X, P.Y, P.Z);

  { both come back zero-extended, so the low word carries the
    sign and CWD is what puts it back. }
  Sx := Integer(P.X);
  Sy := Integer(P.Y);

  { ONE routine writes BOTH records. 133 - Y for the object and Y + 134 for
    the reflection, the same X and the same D. This was two separate stores
    in a single loop here, which is the same arithmetic but not the same
    routine boundary. }
  { The casts are where the 32-bit values meet the six-byte screen record's
    Integer fields, and each one is the low word of a register pair the
    original has already computed in full. }
  Scr[I].X := Integer(Sx);                     { the object }
  Scr[I].Y := Integer(Horizon - Sy);
  Scr[I].D := FixedToIntTrunc(P.Z);

  Scr[I + PtCount].X := Integer(Sx);           { and its reflection }
  { TWO adds, ADD AX,$85 then ADD AX,1, not one ADD AX,$86.
    Borland Pascal emits one instruction per operator and does not fold
    adjacent constants, so this is `+ Horizon + 1` in the source and writing
    it as `+ 134` would be six bytes shorter than the original. }
  Scr[I + PtCount].Y := Integer(Sy + Horizon + 1);
  Scr[I + PtCount].D := FixedToIntTrunc(P.Z);
end;

procedure ObjTransformAll(AObj : PObj; A1, A2, A3 : Integer);
var
  I          : Integer;
  TX, TY, TZ : LongInt;
begin
  { SinCos(angle, var C, var S). The FIRST var parameter takes
    the COSINE. }
  SinCos(A1, MCos1, MSin1);
  SinCos(A2, MCos2, MSin2);
  SinCos(A3, MCos3, MSin3);

  { the translation is read ONCE, before the loop, into
    three locals, and those are what get passed per point. Reading PosX, PosY
    and PosZ inside the loop is the same answer and not the same code. }
  with AObj^.Pos do
  begin
    TX := X;
    TY := Y;
    TZ := Z;
  end;

  for I := 1 to PtCount do
    TransformPoint(AObj^.Pt[I], A1, A2, A3, TX, TY, TZ, I);
end;

{ --------------------------------------------------------------------------
  Obj_Translate(Obj, D1, D2, D3)

  Reads straight off the three blocks: D1 goes to object+$4B0 (X), D2 to +$4B4
  (Y), D3 to +$4B8 (Z), each ADDED, each via IntToFixed. It accumulates.
  -------------------------------------------------------------------------- }
procedure ObjTranslate(AObj : PObj; DX_, DY_, DZ_ : Integer);
var
  Spare : Byte;                           { never touched }
begin
  with AObj^.Pos do
  begin
    X := IntToFixed(DX_) + X;
    Y := IntToFixed(DY_) + Y;
    Z := IntToFixed(DZ_) + Z;
  end;
end;

{ --------------------------------------------------------------------------
  DepthSort(Lo, Hi), nested inside SortAll

  The same Hoare quicksort as scene 4's, over the six-byte screen records and
  keyed on D -- but scene 5 sorts ASCENDING where scene 4 sorts descending.
 breaks the i-scan on `key >= pivot`, so i advances over elements
  BELOW the pivot. Near points are therefore drawn first and far ones over the
  top. That is back to front for a painter's algorithm, and it is what the
  code does; it barely shows because every point is the same sprite.

 runs it twice -- Sort(1, N) for the object and Sort(N+1, 2N) for
  the reflection -- and RenderObject calls it before drawing anything. It was
  missing here entirely.
  -------------------------------------------------------------------------- }

{ --------------------------------------------------------------------------
  Vector_Load -- what it reads out of NEUROSIS.DAT:

  Then it paints the backdrop the objects fly over:

      FillChar(VirtScr, 64000, 0)
      for I := 100 to 255 do SetRGB(I, 0, 0, (I - 50) shr 2)   (* blue ramp *)
      for I :=   2 to 133 do horizontal line, colour I + 122
      for I := 134 to 199 do horizontal line, colour 255 - (I - 133)
  -------------------------------------------------------------------------- }
procedure Load;
var
  {    So there are 384 bytes here that nothing reads. Their SIZES are forced by
    Pal's address; their TYPES are a guess, and two strings are chosen because
    P1BALLS's loader has an unreferenced String[127] in the same position and a
    filename buffer is the obvious thing for a loader to declare and then take
    from a constant instead. }
  I      : Byte;
  Spare1 : String;                      { 256, never read }
  Spare2 : String[127];                 { 128, never read }
  Pal    : array[0..767] of Byte;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DAT_P1_OBJMETA);                { was $03BB02 }
  BlockRead(F, ObjMeta, SizeOf(ObjMeta));
  BlockRead(F, Pal, 768);
  SetPalette768(@Pal);                 { before the Close, as the binary has it }
  Close(F);

  FillChar(Mem[VirtScrSeg : 0], 64000, 0);
  for I := 100 to 255 do
    SetRGB(I, 0, 0, (I - 50) shr 2);
  for I := 2 to $85 do
    DrawLine(0, I, $13F, I, I + $7A, VirtScrSeg);
  for I := $86 to 199 do
    DrawLine(0, I, $13F, I, $FF - (I - $85), VirtScrSeg);
end;

{ --------------------------------------------------------------------------
  The point sprite. HAND ASSEMBLER, transcribed verbatim.

  And the body is unmistakable once read: LODSB and STOSB for a byte at a time,
  DEC CL / JNE for the inner loop, MUL CX to skip whole rows, and DS pointed at
  the sprite so the source needs no segment override. Turbo Pascal emits none of
  those for this shape.

  THE REGISTERS, because the transcription is unreadable without them:

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      W := Src^[0];  H := Src^[1];  P := @Src^[2];
      if -Y > 0 then                      -- clipped off the top
      begin
        if -Y >= H then Exit;
        Inc(P, -Y * W);  Dec(H, -Y);  Y := 0;
      end;
      if Horizon - Y <= 0 then Exit;      -- wholly below the mirror line
      if Horizon - Y < H then H := Horizon - Y + 1;
      D := YOfs[Y] + X;
      for R := 1 to H do
      begin
        for C := 1 to W do
        begin
          if P^ <> 0 then Mem[Segment : D] := P^;   -- 0 is transparent
          Inc(P);  Inc(D);
        end;
        Inc(D, 320 - W);
      end;

  NO HORIZONTAL CLIP. The Pascal that was here tested `X + C >= 0` and
  `X + C < 320` per pixel; the original tests neither, so a sprite whose X puts
  it off either edge wraps onto the neighbouring row. That is behaviour, not an
  omission, and the reconstruction has to keep it.
  -------------------------------------------------------------------------- }
procedure DrawPoint(Src : Pointer; X, Y : Integer; Segment : Word); assembler;
asm
        PUSH    DS
        LES     DI, Src                 { 052e  ES:DI := the sprite          }
        XOR     DX, DX
        XOR     CX, CX
        MOV     DL, ES:[DI+1]           { 0535  DX := height                 }
        XOR     CH, CH
        MOV     CL, ES:[DI]             { 053b  CX := width                  }
        ADD     DI, 2                   { 053e  past the two size bytes      }
        MOV     SI, DI                  { 0541  SI := the first pixel        }
        MOV     BX, Y
        XOR     AX, AX
        SUB     AX, BX                  { 0548  AX := -Y                     }
        JLE     @@NoTopClip
        CMP     AX, DX                  { 054c  is the whole sprite above?   }
        JGE     @@Done                  { 054e    yes -- nothing to draw     }
        SUB     DX, AX                  { 0550  drop the clipped rows        }
        ADD     BX, AX                  { 0552  Y := 0                       }
        MOV     DI, DX                  { 0554  park the row count -- MUL is }
        MUL     CX                      { 0556    about to write DX          }
        MOV     DX, DI                  { 0558    and here it is back        }
        ADD     SI, AX                  { 055a  skip that many sprite bytes  }
@@NoTopClip:
        MOV     AX, Horizon             { 055c  133, the mirror line         }
        SUB     AX, BX
        JLE     @@Done                  { 0561  wholly below it              }
        CMP     AX, DX
        JGE     @@NoBotClip
        INC     AX                      { 0567  ONE MORE ROW than the gap,   }
        MOV     DX, AX                  { 0568    which is what the original }
@@NoBotClip:                            {         does; it is not an error   }
        ADD     BX, BX                  { 056a  BX := Y * 2                  }
        MOV     DI, [BX + OFFSET YOfs]  { 056c  DI := Y * 320                }
        ADD     DI, X
        MOV     AX, ES                  { 0573  DS:SI is now the sprite      }
        MOV     DS, AX
        MOV     AX, Segment
        MOV     ES, AX                  { 057a  ES:DI is now the screen      }
        MOV     BX, CX                  { 057c  keep the width for the step  }
        MOV     CH, CL                  { 057e    and for the row reload     }
@@Row:  MOV     CL, CH                  { 0580  <- once per row              }
@@Pixel:
        LODSB                           { 0582  one sprite byte              }
        OR      AL, AL
        JNE     @@Opaque
        INC     DI                      { 0587  transparent: step over it    }
        DEC     CL
        JNE     @@Pixel
        JMP     @@NextRow
@@Opaque:
        STOSB
        DEC     CL
        JNE     @@Pixel
@@NextRow:
        ADD     DI, 320                 { 0593  down one screen row...       }
        SUB     DI, BX                  { 0597    and back by the width      }
        DEC     DL
        JNE     @@Row
@@Done: POP     DS
end;

{ --------------------------------------------------------------------------
  The REFLECTION blit. HAND ASSEMBLER, transcribed verbatim.

  The same routine as DrawPoint above, byte for byte, with exactly two changes
  and both of them are visible in the listing:

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      W := Src^[0];  H := Src^[1];  P := @Src^[2];
      if Horizon - Y > 0 then             -- clipped off above the horizon
      begin
        if Horizon - Y >= H then Exit;
        Inc(P, (Horizon - Y) * W);  Dec(H, Horizon - Y);  Y := Horizon;
      end;
      if 199 - Y <= 0 then Exit;          -- wholly below the screen
      if 199 - Y < H then H := 199 - Y + 1;
      D := YOfs[Y] + X;
      for R := 1 to H do
      begin
        for C := 1 to W do
        begin
          if P^ <> 0 then Mem[Segment : D] := P^ + $10;
          Inc(P);  Inc(D);
        end;
        Inc(D, 320 - W);
      end;
  -------------------------------------------------------------------------- }
procedure DrawReflection(Src : Pointer; X, Y : Integer; Segment : Word); assembler;
asm
        PUSH    DS
        LES     DI, Src
        XOR     DX, DX
        XOR     CX, CX
        MOV     DL, ES:[DI+1]           { 05ad  DX := height                 }
        XOR     CH, CH
        MOV     CL, ES:[DI]             { 05b3  CX := width                  }
        ADD     DI, 2
        MOV     SI, DI
        MOV     BX, Y
        MOV     AX, Horizon             { 05be  133 -- the clip is from HERE }
        SUB     AX, BX                  { 05c1    downwards, not from zero   }
        JLE     @@NoTopClip
        CMP     AX, DX
        JGE     @@Done
        SUB     DX, AX
        ADD     BX, AX
        MOV     DI, DX                  { 05cd  park the row count round MUL }
        MUL     CX
        MOV     DX, DI
        ADD     SI, AX
@@NoTopClip:
        MOV     AX, 199                 { 05d5  the bottom of the screen     }
        SUB     AX, BX
        JLE     @@Done
        CMP     AX, DX
        JGE     @@NoBotClip
        INC     AX
        MOV     DX, AX
@@NoBotClip:
        ADD     BX, BX
        MOV     DI, [BX + OFFSET YOfs]
        ADD     DI, X
        MOV     AX, ES
        MOV     DS, AX
        MOV     AX, Segment
        MOV     ES, AX
        MOV     BX, CX
        MOV     CH, CL
@@Row:  MOV     CL, CH
@@Pixel:
        LODSB
        OR      AL, AL
        JNE     @@Opaque
        INC     DI
        DEC     CL
        JNE     @@Pixel
        JMP     @@NextRow
@@Opaque:
        ADD     AL, 10h                 { 0607  sixteen along the palette    }
        STOSB
        DEC     CL
        JNE     @@Pixel
@@NextRow:
        ADD     DI, 320
        SUB     DI, BX
        DEC     DL
        JNE     @@Row
@@Done: POP     DS
end;

procedure RenderObject;
var
  I     : Byte;
  Spare : array[1..3] of Byte;                    { never read }
begin
  SortAll(@Scr);

  for I := PtCount + 1 to PtCount * 2 do
    with Scr[I] do
      DrawReflection(@ObjMeta, X, Y, WorkSeg);
  for I := 1 to PtCount do
    with Scr[I] do
    begin
      Dec(Y, 7);                                  { SUB on memory }
      DrawPoint(@ObjMeta, X, Y, WorkSeg);
    end;
end;


{ --------------------------------------------------------------------------
  FadeToWhite

  Forty passes. Each waits for retrace, then walks colours 1..255 doing
  GetRGB / bump every channel that is still below $3F / SetRGB. So the whole
  palette climbs to white before the wipe. }
procedure FadeToWhite;
var
  Pass, Col : Integer;
  B, G, R   : Byte;
begin
  for Pass := 1 to FadeSteps do
  begin
    WaitRetrace;
    for Col := 1 to 255 do
    begin
      GetRGB(Col, R, G, B);
      if R < $3F then Inc(R);
      if G < $3F then Inc(G);
      if B < $3F then Inc(B);
      SetRGB(Col, R, G, B);
    end;
  end;
end;

{ --------------------------------------------------------------------------
  Vector_Animate

  Three angles run at once:

  Note these accumulate. Summing Sin at 3-degree steps is an integration, so
  the Z excursion reaches roughly 500 / (3 deg in radians) ~ 9,500 -- the
  object flies a long way out and comes back, twice, over the 240 frames.

  No delay and no retrace wait anywhere in the loop: on the original the two
  64,000-byte screen copies were the frame rate.
  -------------------------------------------------------------------------- }
procedure Animate;
var
  Done   : Boolean;                     { assigned, never read }
  Frame  : Integer;
  Unused : Integer;                     { never referenced }
  Local  : Integer;
begin
  Angle := 0;
  Local := 0;
  Done  := False;
  { OrbitAngle deliberately NOT reset -- Vector_Run seeds it. }

  for Frame := 1 to VectorFrames do
  begin
    Copy32(VirtScrSeg, WorkSeg);        { the clean gradient }
    ObjTransformAll(@Obj, Angle, Angle, Angle);
    RenderObject;
    Copy32(WorkSeg, $A000);

    Inc(Angle, VectorStep);
    if Angle > VectorWrap then Angle := 0;

    { THE THREE ARE COMPUTED INTO VARIABLES, THEN THE ANGLES ADVANCE, THEN
      THE CALL. Passing the Round expressions as arguments is the same
      arithmetic in the wrong order: the original has both increments between
      the last Round and the call, so Local is already advanced by the time
      ObjTranslate runs but the values it passes were computed before. }
    Dx := Round(Cos(Local      * Pi / 180.0) *   5.0);
    Dy := Round(Sin(OrbitAngle * Pi / 180.0) *  20.0);
    Dz := Round(Sin(Local      * Pi / 180.0) * 500.0);

    { are MOV AX / ADD AX,imm / MOV back -- the
      assignment form, not Inc's ADD [mem],reg. Six bytes each. }
    Local      := Local + LocalStep;
    OrbitAngle := OrbitAngle + OrbitStep;

    ObjTranslate(@Obj, Dx, Dy, Dz);

    if KeyPressed then Exit;
  end;
end;

{ ===========================================================================
  Scene 5 -- vector objects and wipe
  =========================================================================== }

{ --------------------------------------------------------------------------
  Vector_Run

  Two objects in turn. The start position is set ONCE, before the globe, and
  is NOT reset before the logo -- so the logo begins wherever the globe's
  accumulated translation left it. The orbit angle IS reseeded between them,
  with two values that look arbitrary and are:

 Pos := (0, IntToFixed(-70), IntToFixed(1600))
 Orbit := $F806 = -2042        then Animate
 Orbit := $0011 = 17           then Animate

  The source had Pos zeroed inside LoadObject, so the object sat at the origin
  with no depth at all and the perspective divide had nothing to work with. }
procedure VectorRun;
var
  { ENTER $A is ten bytes and only TWO of them are declared. The frame reads as
    three Integers and a Pointer -- which is what this said -- and the BODY
    refutes that: }
  I      : Integer;
  W      : Word;                          { the slide-out counter }
begin
  PtCount := GlobePoints;
  for I := 0 to PtCount - 1 do
    with Obj.Pt[I + 1] do
    begin
      X := IntToFixed(VecGlobe[I * 3]);
      Y := IntToFixed(VecGlobe[I * 3 + 1]);
      Z := IntToFixed(VecGlobe[I * 3 + 2]);
    end;


  { THE STARTING POSITION. X IS A DIRECT ZERO -- not IntToFixed(0), which would
    be a call -- while Y and Z do go through the conversion. Same values either
    way; different code. }
  Obj.Pos.X := 0;
  Obj.Pos.Y := IntToFixed(-70);
  Obj.Pos.Z := IntToFixed(1600);

  { THE PROJECTION SCALE, (screen width / 2) * 10 in 16.16. }
  MScale := RealToFixed(MViewW / 2.0 * 10.0);

  OrbitAngle := -2042;
  Animate;

  { The same shape a second time, on the other table. }
  PtCount := LogoPoints;
  for I := 0 to PtCount - 1 do
  begin
    with Obj.Pt[I + 1] do
    begin
      X := IntToFixed(VecLogoA[I * 3]);
      Y := IntToFixed(VecLogoA[I * 3 + 1]);
      Z := IntToFixed(VecLogoA[I * 3 + 2]);
    end;
  end;
  OrbitAngle := 17;
  Animate;

  FadeToWhite;
  Delay(1000);

  { --------------------------------------------------------------------
    The wipe.

        W := 0
        repeat
          ES := $A000 ; DS := WorkSeg ; SI := 0 ; DI := 0
          AL := 0 ; CX := W        ; REP STOSB      blank the top W bytes
          CX := $FA00 - W          ; REP MOVSB      then the picture, shifted
          W += $280
        until W >= $FA00

    The source read from the VIDEO segment at offset 0 -- which the FillChar
    on the line above had just zeroed -- so it smeared black over itself and
    the picture never moved. The source is the WORK buffer, always from
    offset 0, so the final frame slides down off the bottom with black
    filling in above it. 640 bytes a step is two rows.

    HAND ASSEMBLER, verbatim -- it is an asm block inside compiled Pascal,
    not a routine of its own, which is why it is inline here too. The frame
    loop and the W counter around it are the compiler's.

    EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

        FillChar(Mem[$A000 : 0], W, 0);
        Move(Mem[WorkSeg : 0], Mem[$A000 : W], 64000 - W);

    and that really is equivalent. It is written out because the original
    writes it out: one pair of segment registers serves both halves, so the
    blank and the copy run back to back with DI already in the right place.
    -------------------------------------------------------------------- }
  W := 0;
  repeat
    asm
      PUSH DS               { DS becomes the work buffer below              }
      MOV  AX, $A000        { video memory                                  }
      MOV  ES, AX           { ES:DI is the destination for both halves      }
      MOV  AX, [WorkSeg]    { the finished frame                            }
      MOV  DS, AX           { DS:SI is the source for the copy              }
      XOR  SI, SI           { always from the top of the work buffer        }
      XOR  DI, DI           { and to the top of the screen                  }
      MOV  BX, W            { how far down the picture has slid             }
      XOR  AX, AX           { the fill value: black                         }
      MOV  CX, BX           { that many bytes of black                      }
      REP  STOSB            { blank the top of the screen; DI ends at W     }
      MOV  CX, $FA00        { 64,000 -- the whole screen                    }
      SUB  CX, BX           {   less what was just blanked                  }
      REP  MOVSB            { and the picture follows, starting at row W/320 }
      POP  DS               { restore our data segment                      }
    end;
    W := W + 640;
  until W >= 64000;
end;

{ --------------------------------------------------------------------------
  The work-buffer setup, a routine of its own in the binary.

  GetMem straight off (no nil test -- Scene5 frees it on the way out, so a
  second run allocates again), and the buffer is CLEARED before anything
  draws into it. Load used to allocate lazily here and never cleared, so the
  first frame blitted whatever the heap held.
  -------------------------------------------------------------------------- }
procedure AllocWork;
var
  { opens ENTER 2 and the routine references no local at all in its
    forty bytes, so this is two bytes declared and never read. It has to be
    here or the frame is absent where the original has one. }
  Spare : Integer;
begin
  GetMem(Work, 64000);
  WorkSeg := Seg(Work^);
  ClearScreen(WorkSeg, 0);
end;

{ --------------------------------------------------------------------------
  Demo_Scene5.

  THE ORDER IS THE POINT (plan: part1-s4s5-palette). The screen is blanked
  to colour 0 BEFORE Load rewrites the whole DAC, so the palette swap
  happens over black and is invisible. This unit used to go straight into
  Load, which recoloured scene 4's still-displayed final frame and left it
  on show for the whole file read and backdrop build -- the glitch seen at
  the scene 4 to 5 transition.
  -------------------------------------------------------------------------- }
procedure Scene5;
begin
  while KeyPressed do ReadKey;
  ClearScreen(VGASeg, 0);
  AllocWork;
  Load;
  VectorRun;
  FreeMem(Work, 64000);
end;

begin
end.
