{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 5.

  Transcribed from segment 12c5. Every routine carries the address it came
  from. What was previously inferred here got four things wrong, all of them
  visible: the translation axes were swapped, the object never got its start
  position, the projection scale was invented, and the closing wipe copied
  from the screen it had just blanked.
  =========================================================================== }

unit P1S5;
{$A-}   { data alignment off -- measured, see the note in P2S2.PAS }

{$G+}   { 286: the binary's Scene5 pushes immediates (68 00 A0 at 12c5:0a9c)
          and closes with LEAVE -- $G+ codegen throughout the segment. }
{$N+}   { the PER-FRAME translate trig is x87 in the binary -- 12c5:07b9,
          12c5:07df FILD and the $N+ RTL's Sin/Cos. Under the $N- default the
          same three calls a frame went through the software six-byte-Real
          RTL, slowing every frame of the vector scene (plan: pacing). }

interface

procedure Scene5;

implementation

uses VGA, Crt, DemoVT, FixMath;

{$I gen/P1VECT.INC}      { const VecLogoA, VecGlobe : array[.., 1..3] of Integer }

const
  MaxPoints    = 64;
  GlobePoints  = 36;       { $24 -- 12c5:0874 }
  LogoPoints   = 48;       { $30 -- 12c5:0973 }
  VectorFrames = 240;      { $F0 -- 12c5:085c }
  VectorStep   = 20;       { $14 -- 2.0 degrees per frame }
  VectorWrap   = 3590;     { $E06 -- and it RESETS to 0, it does not subtract }
  LocalStep    = 3;        { degrees per frame, 12c5:082e }
  OrbitStep    = 10;       { degrees per frame, 12c5:0837 }
  Horizon      = $85;      { 133 -- the mirror line }
  FadeSteps    = 40;       { $28 -- 12c5:073c }

  { The two words 12c5:1b2d halves to centre the projection. They are
    INITIALISED DATA in DGROUP -- nothing in the executable ever writes them,
    so they are whatever was compiled in:

        DS:$0280 = 320      12c5:1baa,  so the X centre is 160
        DS:$0282 =   0      12c5:1bb4,  so the Y centre is ZERO

  That zero is not a mistake to be tidied away. With it, sy = -round(Y/Z*S),
  and the caller's mirror at 12c5:0248 turns that into

        object      133 + round(Y/Z*S)
        reflection  134 - round(Y/Z*S)

  so the 133/134 line does ALL the vertical placement and the object hangs
  above it by however far the projection says. Substituting ScrHeight div 2
  here -- which is the obvious thing to assume, and what this file did --
  lifts the whole scene exactly 100 rows and floats it off the top. }
  { DS:$0280 and DS:$0282, initialised data. They are declared as typed
    constants below rather than here, because Project reads them FROM MEMORY
    and the shared maths object resolves them by name. }

type
  TScreenPt = record
    X, Y, D : Integer;      { six bytes, matching the $A5F0 stride }
  end;

var
  { DS:$AAD0 spin, DS:$AAD2 orbit. Local lives in Animate's own frame. }
  Angle      : Integer;
  OrbitAngle : Integer;
  { DS:$AAC6 -- the render target. Animate copies the clean gradient out of
    the virtual screen into it, draws, and blits it to video. }
  Work    : Pointer;
  WorkSeg : Word;

  PtCount : Integer;                                { DS:$AAC8 }
  { Model coordinates, 16.16 fixed point -- which is why the records are
    TWELVE bytes and not six. An earlier version held these as plain Integers
    because a Turbo Pascal LongInt multiply overflows before it can take the
    middle 32 bits of a 32x32 product; the rotation now goes through the
    shared 386 maths object, which does that properly, so the coordinates are
    the original's again. }
  Pt      : array[1..MaxPoints, 1..3] of LongInt;   { DS:$A106, 12 bytes each }
  Scr     : array[1..MaxPoints * 2] of TScreenPt;   { DS:$A5F0 }
  { DS:$A5B6/$A5BA/$A5BE -- object + $4B0, the translation. }
  PosX, PosY, PosZ : LongInt;
  { DS:$A5C2 -- the 52-byte point sprite: a 2-byte (W, H) header and 50 px. }
  ObjMeta : array[0..51] of Byte;
{ --------------------------------------------------------------------------
  THE SHARED 386 MATHS MODULE.

  SinCos, RotatePoint and Project are 386 code and cannot be written in Turbo
  Pascal's built-in assembler, which stops at the 286. They live in
  src/asm/DEMOMATH.ASM, are assembled by TASM and linked in here with the $L directive --
  which is what the original does: 12c5:192D, 12c5:19DF and 12c5:1B2D are the
  same code as scene 4's and part 002 scene 2's, once per unit.

  The nine names below are the module's EXTRNs, so they have to be declared
  BEFORE the $L directive and spelled exactly this way.
  -------------------------------------------------------------------------- }
var
  { DS:$AAA6..$AABD -- cos then sin, per axis, as SinCos leaves them. }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  { DS:$AABE -- the projection scale, 16.16. }
  MScale : LongInt;

const
  { DS:$0280 = 320, so the horizontal centre is 160.
    DS:$0282 = 0, so the vertical centre is ZERO.

    That zero is not a mistake to be tidied away. With it, sy = -round(Y/Z*S),
    and the caller's mirror at 12c5:0248 turns that into

        object      133 + round(Y/Z*S)
        reflection  134 - round(Y/Z*S)

    so the 133/134 line does ALL the vertical placement and the object hangs
    above it by however far the projection says. Substituting ScrHeight here
    -- the obvious thing to assume, and what this file once did -- lifts the
    whole scene exactly 100 rows and floats it off the top.

    Project halves both, so these are the FULL view size, not the centre. }
  MViewW : Word = 320;
  MViewH : Word = 0;

{$L DEMOMATH.OBJ}
procedure SinCos(A : Integer; var C, S : LongInt);        external; { 12c5:192D }
procedure RotatePoint(var X, Y, Z : LongInt);             external; { 12c5:19DF }
procedure Project(var X, Y, Z : LongInt);                 external; { 12c5:1B2D }

{ --------------------------------------------------------------------------
  1483:0000 -- Math_IntToReal is MISNAMED. It converts an Integer to 16.16
  FIXED POINT:  MOV AX,[BP+6] ; CWD ; MOV CX,16 ; XOR BX,BX ; <shift> -> DX:AX

  That is why the point records are TWELVE bytes -- three 32-bit fixed values
  -- and not the eighteen three 6-byte Borland Reals would need.
  -------------------------------------------------------------------------- }
{ IntToFixed and the two conversions back come from FixMath (segment 1483).
  This scene had local copies, and its FixedToInt was the ROUNDING one -- but
  12C5:0268 calls 1483:0071, which TRUNCATES. The calls below say so. }

{ [transcribed] Vector_Run's object copy, 12c5:088b and 12c5:098a -- integer
  triples out of DGROUP, IntToFixed into the 12-byte records. It does NOT
  touch the translation; Vector_Run sets that separately, once. }
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
    Pt[I, 1] := IntToFixed(Src^[I, 1]);
    Pt[I, 2] := IntToFixed(Src^[I, 2]);
    Pt[I, 3] := IntToFixed(Src^[I, 3]);
  end;
end;

{ --------------------------------------------------------------------------
  12c5:03a2 -- Obj_Translate(Obj, D1, D2, D3)

  Reads straight off the three blocks: D1 goes to object+$4B0 (X), D2 to +$4B4
  (Y), D3 to +$4B8 (Z), each ADDED, each via IntToFixed. It accumulates.
  -------------------------------------------------------------------------- }
procedure ObjTranslate(DX_, DY_, DZ_ : Integer);
begin
  Inc(PosX, IntToFixed(DX_));
  Inc(PosY, IntToFixed(DY_));
  Inc(PosZ, IntToFixed(DZ_));
end;

{ --------------------------------------------------------------------------
  12c5:1b2d -- Project(var X, Y, Z)

  Byte-for-byte the same routine as scene 4's 1107:1a04. The divisor is
  [BP+4], the LAST declared parameter, and 12c5:01b0 calls it (X, Y, Z) --
  so it divides by Z, the ordinary way round. (An earlier note here claimed it
  divided by X. That was Ghidra printing arguments in ascending [BP+n] order,
  which is the reverse of the declaration.)

      sx := round(X/Z * Scale) + [$0280] div 2      = +160
      sy := [$0282] div 2 - round(Y/Z * Scale)      = -round(...), see CentreY

  Scale is [$AABE], set by Vector_Run to (ScreenWidth / 2) * 10 = 1600.0 --
  the same expression scene 4 uses. The source previously had a hand-picked
  `160 + (X*128) div (Z+256)`, which is neither the right scale nor the right
  depth origin.
  -------------------------------------------------------------------------- }

{ --------------------------------------------------------------------------
  12c5:02e3 -- Obj_TransformAll(Obj, A1, A2, A3), which fans out to 12c5:01b0
  once per point. Per point: rotate (12c5:19df), add the translation, project,
  then store TWO six-byte screen records:

      Scr[I]           X,  $85 - sy       12c5:0244 / 12c5:024b
      Scr[I + Count]   X,  sy + $85 + 1   12c5:0290 / 12c5:029a

  A mirror pair about row 133.5 -- the floor, exactly where Vector_Load's
  gradient turns around. Both carry D = Trunc(Z) for the depth sort.
  -------------------------------------------------------------------------- }
procedure ObjTransformAll(A1, A2, A3 : Integer);
var
  I       : Integer;
  X, Y, Z : LongInt;
  Sx, Sy  : Integer;
begin
  { 12c5:02f4 -- SinCos(angle, var C, var S). The FIRST var parameter takes
    the COSINE. }
  SinCos(A1, MCos1, MSin1);
  SinCos(A2, MCos2, MSin2);
  SinCos(A3, MCos3, MSin3);

  for I := 1 to PtCount do
  begin
    { 12c5:01bb -- the twelve-byte point is copied into locals first, so the
      model is left untouched and can be transformed again next frame. }
    X := Pt[I, 1];  Y := Pt[I, 2];  Z := Pt[I, 3];

    RotatePoint(X, Y, Z);                         { 12c5:01d7 }

    Inc(X, PosX);                                 { 12c5:01da }
    Inc(Y, PosY);
    Inc(Z, PosZ);

    Project(X, Y, Z);                             { 12c5:021f }

    { 12c5:0222 -- both come back zero-extended, so the low word carries the
      sign and CWD is what puts it back. }
    Sx := Integer(X);
    Sy := Integer(Y);

    Scr[I].X := Sx;                     { the object }
    Scr[I].Y := Horizon - Sy;
    Scr[I].D := FixedToIntTrunc(Z);     { 12c5:0268 -> 1483:0071 }

    Scr[I + PtCount].X := Sx;           { and its reflection }
    Scr[I + PtCount].Y := Sy + Horizon + 1;
    Scr[I + PtCount].D := FixedToIntTrunc(Z);
  end;
end;

{ --------------------------------------------------------------------------
  12c5:0000 -- DepthSort(Lo, Hi), nested inside 12c5:0190

  The same Hoare quicksort as scene 4's, over the six-byte screen records and
  keyed on D -- but scene 5 sorts ASCENDING where scene 4 sorts descending.
  12c5:004c breaks the i-scan on `key >= pivot`, so i advances over elements
  BELOW the pivot. Near points are therefore drawn first and far ones over the
  top. That is back to front for a painter's algorithm, and it is what the
  code does; it barely shows because every point is the same sprite.

  12c5:0190 runs it twice -- Sort(1, N) for the object and Sort(N+1, 2N) for
  the reflection -- and RenderObject calls it before drawing anything. It was
  missing here entirely.
  -------------------------------------------------------------------------- }
procedure DepthSort(Lo, Hi : Integer);
var
  I, J, P : Integer;
  T       : TScreenPt;
begin
  I := Lo;  J := Hi;
  P := Scr[(Lo + Hi) div 2].D;
  repeat
    while Scr[I].D < P do Inc(I);
    while Scr[J].D > P do Dec(J);
    if I <= J then
    begin
      if Scr[I].D <> Scr[J].D then
      begin
        T := Scr[I];  Scr[I] := Scr[J];  Scr[J] := T;
      end;
      Inc(I);  Dec(J);
    end;
  until I > J;
  if Lo < J then DepthSort(Lo, J);
  if I < Hi then DepthSort(I, Hi);
end;

{ [transcribed] 12c5:052a -- transparent point sprite, W and H from its own
  first two bytes, clipped to rows 0..133. }
procedure DrawPoint(Src : Pointer; X, Y : Integer; Segment : Word);
var
  P          : ^Byte;
  W, H, R, C : Integer;
  D          : Word;
  V          : Byte;
begin
  P := Src;
  W := P^;  Inc(LongInt(P));
  H := P^;  Inc(LongInt(P));

  if -Y > 0 then
  begin
    if -Y >= H then Exit;
    Inc(LongInt(P), LongInt(-Y) * W);
    Dec(H, -Y);
    Y := 0;
  end;
  if Horizon - Y <= 0 then Exit;
  if Horizon - Y < H then H := Horizon - Y + 1;

  for R := 0 to H - 1 do
  begin
    D := (Y + R) * ScrWidth + X;
    for C := 0 to W - 1 do
    begin
      V := P^;
      if (V <> 0) and (X + C >= 0) and (X + C < ScrWidth) then
        Mem[Segment : D] := V;
      Inc(LongInt(P));
      Inc(D);
    end;
  end;
end;

{ --------------------------------------------------------------------------
  12c5:05a2 -- the REFLECTION blit. Same shape as DrawPoint, two differences:
  it clips to rows 133..199 rather than 0..133, and every pixel is written as
  `AL + $10` -- sixteen colours along the palette, which is what dims it.
  -------------------------------------------------------------------------- }
procedure DrawReflection(Src : Pointer; X, Y : Integer; Segment : Word);
var
  P          : ^Byte;
  W, H, R, C : Integer;
  D          : Word;
  V          : Byte;
begin
  P := Src;
  W := P^;  Inc(LongInt(P));
  H := P^;  Inc(LongInt(P));

  if Horizon - Y > 0 then
  begin
    if Horizon - Y >= H then Exit;
    Inc(LongInt(P), LongInt(Horizon - Y) * W);
    Dec(H, Horizon - Y);
    Y := Horizon;
  end;
  if 199 - Y <= 0 then Exit;
  if 199 - Y < H then H := 199 - Y + 1;

  for R := 0 to H - 1 do
  begin
    D := (Y + R) * ScrWidth + X;
    for C := 0 to W - 1 do
    begin
      V := P^;
      if (V <> 0) and (X + C >= 0) and (X + C < ScrWidth) then
        Mem[Segment : D] := V + $10;
      Inc(LongInt(P));
      Inc(D);
    end;
  end;
end;

{ [transcribed] 12c5:061d -- sort both halves, draw the reflections, then the
  points with their Y pulled up seven rows (12c5:06ab). }
procedure RenderObject;
var
  I : Integer;
begin
  DepthSort(1, PtCount);                          { 12c5:0193 }
  DepthSort(PtCount + 1, PtCount * 2);            { 12c5:01a1 }

  for I := PtCount + 1 to PtCount * 2 do
    DrawReflection(@ObjMeta, Scr[I].X, Scr[I].Y, WorkSeg);
  for I := 1 to PtCount do
  begin
    Dec(Scr[I].Y, 7);
    DrawPoint(@ObjMeta, Scr[I].X, Scr[I].Y, WorkSeg);
  end;
end;

{ --------------------------------------------------------------------------
  Vector_Animate (12c5:075e)

  Three angles run at once:

      Spin    DS:$AAD0   += 20 per frame, RESET to 0 past 3590   2.0 deg
      Local   [BP-7]     += 3  per frame                         degrees
      Orbit   DS:$AAD2   += 10 per frame                         degrees

  Spin is reset on entry (12c5:0764) and drives all three rotation axes with
  the same value, so the object tumbles about the diagonal. Local is reset too
  (12c5:0769). ORBIT IS NOT -- Vector_Run seeds it before each call, and
  Animate carries on from there.

  The three translation deltas, read off 12c5:07b8..12c5:0828 with the float
  constants at CS:$0752, $0756, $075A:

      [$AACA] := Round(Cos(Local * Pi / 180) *   5.0)
      [$AACC] := Round(Sin(Orbit * Pi / 180) *  20.0)
      [$AACE] := Round(Sin(Local * Pi / 180) * 500.0)

  and 12c5:083d pushes them in that order into Obj_Translate, which maps them
  to X, Y, Z respectively. THE PREVIOUS VERSION HAD X AND Z SWAPPED: it put
  the 500 on X and the 5 on Z, so the object slid across the screen instead of
  rushing toward and away from the camera. That is the wrong motion.

  Note these accumulate. Summing Sin at 3-degree steps is an integration, so
  the Z excursion reaches roughly 500 / (3 deg in radians) ~ 9,500 -- the
  object flies a long way out and comes back, twice, over the 240 frames.

  No delay and no retrace wait anywhere in the loop: on the original the two
  64,000-byte screen copies were the frame rate.
  -------------------------------------------------------------------------- }
{ THE FRAME IS ENTER $08 (12c5:075e) AND IT TAKES FOUR DECLARATIONS TO FILL,
  not two. What gives it away is that every local sits on an ODD offset --
  [BP-3] and [BP-7] -- which only happens if a ONE-BYTE local was declared
  first and pushed everything after it out of alignment. Turbo Pascal does not
  align locals, so the offsets recover the declaration order directly:

      [BP-1]  1 byte    written 0 at 12c5:076c and NEVER READ. One reference
                        in the whole routine, which is that store. It reads
                        like an exit flag the author stopped using -- Exit is
                        reached directly from the KeyPressed test at
                        12c5:0851 instead. Boolean, Byte and Char are
                        indistinguishable from `MOV BYTE PTR [BP-1],0`.
      [BP-3]  Integer   Frame, 1..240 -- seeded 12c5:0770, tested 12c5:085c
      [BP-5]  Integer   NEVER REFERENCED AT ALL, at any width
      [BP-7]  Integer   Local -- seeded 12c5:0769, read 12c5:07b9 and
                        12c5:0806, advanced by 3 at 12c5:082b

  Seven bytes declared, and ENTER $08 because the frame is rounded to even.
  Two of the four are dead, and they are transcribed anyway: they are what the
  1994 source declared, and leaving them out is what put every other local in
  this routine at the wrong offset. }
procedure Animate;
var
  Done   : Boolean;                     { [BP-1] -- assigned, never read }
  Frame  : Integer;                    { [BP-3] }
  Unused : Integer;                     { [BP-5] -- never referenced }
  Local  : Integer;                    { [BP-7] }
begin
  Angle := 0;                           { 12c5:0764 }
  Local := 0;                           { 12c5:0769 }
  Done  := False;                       { 12c5:076c }
  { OrbitAngle deliberately NOT reset -- Vector_Run seeds it. }

  for Frame := 1 to VectorFrames do
  begin
    CopyScreen(VirtScrSeg, WorkSeg);    { 12c5:0782 -- the clean gradient }
    ObjTransformAll(Angle, Angle, Angle);
    RenderObject;                       { 12c5:0799 }
    CopyScreen(WorkSeg, $A000);         { 12c5:07a3 }

    Inc(Angle, VectorStep);
    if Angle > VectorWrap then Angle := 0;

    ObjTranslate(Round(Cos(Local      * Pi / 180.0) *   5.0),
                 Round(Sin(OrbitAngle * Pi / 180.0) *  20.0),
                 Round(Sin(Local      * Pi / 180.0) * 500.0));

    Inc(Local, LocalStep);
    Inc(OrbitAngle, OrbitStep);

    if KeyPressed then Exit;            { 12c5:0851 }
  end;
end;

{ --------------------------------------------------------------------------
  12c5:06d0 -- FadeToWhite

  Forty passes. Each waits for retrace, then walks colours 1..255 doing
  GetRGB / bump every channel that is still below $3F / SetRGB. So the whole
  palette climbs to white before the wipe.

  The source had a "DrawStatic" here -- a redraw of the last frame. There is
  no such call in Vector_Run; this is what 12c5:0a1e actually reaches.
  -------------------------------------------------------------------------- }
procedure FadeToWhite;
var
  Pass, Col : Integer;
  R, G, B   : Byte;
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

{ ===========================================================================
  Scene 5 -- vector objects and wipe              Demo_Scene5  12c5:0a89
  =========================================================================== }

{ --------------------------------------------------------------------------
  Vector_Run (12c5:0870)

  Two objects in turn. The start position is set ONCE, before the globe, and
  is NOT reset before the logo -- so the logo begins wherever the globe's
  accumulated translation left it. The orbit angle IS reseeded between them,
  with two values that look arbitrary and are:

      12c5:091e   Pos := (0, IntToFixed(-70), IntToFixed(1600))
      12c5:096a   Orbit := $F806 = -2042        then Animate
      12c5:0a15   Orbit := $0011 = 17           then Animate

  The source had Pos zeroed inside LoadObject, so the object sat at the origin
  with no depth at all and the perspective divide had nothing to work with.

  ASSETS  Compiled into the executable, not in NEUROSIS.DAT:
            assets/part001/vector_globe.bin    DS:$01A8, 36 points
            assets/part001/vector_logo_a.bin   DS:$001C, 48 points
  -------------------------------------------------------------------------- }
procedure VectorRun;
var
  W : Word;
begin
  LoadObject(@VecGlobe, GlobePoints);          { 12c5:0874 }

  PosX := IntToFixed(0);                       { 12c5:0918 }
  PosY := IntToFixed(-70);                     { 12c5:091e }
  PosZ := IntToFixed(1600);                    { 12c5:092c }

  { 12c5:093b -- Scale := (ScreenWidth / 2.0) * 10.0, as 16.16.
    CS:$0868 = 2.0, CS:$086C = 10.0. }
  MScale := Round((ScrWidth / 2.0) * 10.0 * 65536.0);

  OrbitAngle := -2042;                         { 12c5:096a }
  Animate;

  LoadObject(@VecLogoA, LogoPoints);           { 12c5:0973 }
  OrbitAngle := 17;                            { 12c5:0a15 }
  Animate;

  FadeToWhite;                                 { 12c5:0a1e }
  Delay(1000);                                 { 12c5:0a21 }

  { --------------------------------------------------------------------
    12c5:0a29 -- the wipe.

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
    Inc(W, 640);
  until W >= 64000;
end;

{ --------------------------------------------------------------------------
  Vector_Load (12c5:0413) -- NEUROSIS.DAT $03BB02:

      52   the point sprite (a 2-byte W,H header and 50 pixels) -> DS:$A5C2
      768  palette

  Then it paints the backdrop the objects fly over:

      FillChar(VirtScr, 64000, 0)
      for I := 100 to 255 do SetRGB(I, 0, 0, (I - 50) shr 2)   (* blue ramp *)
      for I :=   2 to 133 do horizontal line, colour I + 122
      for I := 134 to 199 do horizontal line, colour 255 - (I - 133)
  -------------------------------------------------------------------------- }
procedure Load;
var
  F   : file;
  I   : Integer;
  { The palette is a LOCAL in the original -- Load's frame is ENTER $482 and
    the second BlockRead lands at [BP-$481], which then goes straight to
    VGA.SetPalette768 (12c5:0473 -> 1491:01c2). Nothing keeps a copy. }
  Pal : array[0..767] of Byte;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $03BB02);
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
  12c5:0a60 -- the work-buffer setup, a routine of its own in the binary.

  GetMem straight off (no nil test -- Scene5 frees it on the way out, so a
  second run allocates again), and the buffer is CLEARED before anything
  draws into it. Load used to allocate lazily here and never cleared, so the
  first frame blitted whatever the heap held.
  -------------------------------------------------------------------------- }
procedure AllocWork;
begin
  GetMem(Work, 64000);                 { 12c5:0a64 }
  WorkSeg := Seg(Work^);               { 12c5:0a73 }
  ClearScreen(WorkSeg, 0);             { 12c5:0a7c }
end;

{ --------------------------------------------------------------------------
  12c5:0a89 -- Demo_Scene5.

      while KeyPressed do ReadKey      12c5:0a8c -- its own flush, inline
      ClearScreen($A000, 0)            12c5:0a9c
      AllocWork                        12c5:0aa6 -> 0a60
      Load                             12c5:0aa9 -> 0413
      VectorRun                        12c5:0aac -> 0870
      FreeMem(Work, 64000)             12c5:0aaf

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

end.
