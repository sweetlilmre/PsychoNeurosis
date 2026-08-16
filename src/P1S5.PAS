{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 5.

  Transcribed from segment 12c5. Every routine carries the address it came
  from. What was previously inferred here got four things wrong, all of them
  visible: the translation axes were swapped, the object never got its start
  position, the projection scale was invented, and the closing wipe copied
  from the screen it had just blanked.
  =========================================================================== }

unit P1S5;

interface

procedure Scene5;

implementation

uses VGA, Crt, DemoVT;

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
  CentreX = 320;           { DS:$0280 }
  CentreY = 0;             { DS:$0282 }

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
  { Model coordinates. The original holds these as 16.16 and rotates with a
    32x32->64 multiply taking the middle 32 bits; Turbo Pascal has no 64-bit
    type, so 32x32->32 would overflow catastrophically. The coordinates are
    small (+/-50), so plain integers multiplied by the 16.16 trig give the
    same screen result and fit. }
  Pt      : array[1..MaxPoints, 1..3] of Integer;   { DS:$A106, 12 bytes each }
  Scr     : array[1..MaxPoints * 2] of TScreenPt;   { DS:$A5F0 }
  { DS:$A5B6/$A5BA/$A5BE -- object + $4B0, the translation. }
  PosX, PosY, PosZ : LongInt;
  { DS:$A5C2 -- the 52-byte point sprite: a 2-byte (W, H) header and 50 px. }
  ObjMeta : array[0..51] of Byte;
  { DS:$AAA6..$AABD -- cos then sin, per axis, as SinCos leaves them. }
  CosA, SinA, CosB, SinB, CosC, SinC : LongInt;
  { DS:$AABE -- the projection scale, 16.16. }
  Scale   : LongInt;

{ --------------------------------------------------------------------------
  1483:0000 -- Math_IntToReal is MISNAMED. It converts an Integer to 16.16
  FIXED POINT:  MOV AX,[BP+6] ; CWD ; MOV CX,16 ; XOR BX,BX ; <shift> -> DX:AX

  That is why the point records are TWELVE bytes -- three 32-bit fixed values
  -- and not the eighteen three 6-byte Borland Reals would need.
  -------------------------------------------------------------------------- }
function IntToFixed(V : Integer) : LongInt;
begin
  IntToFixed := LongInt(V) shl 16;
end;

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
    Pt[I, 1] := Src^[I, 1];
    Pt[I, 2] := Src^[I, 2];
    Pt[I, 3] := Src^[I, 3];
  end;
end;

{ --------------------------------------------------------------------------
  12c5:03a2 -- Obj_Translate(Obj, D1, D2, D3)

  Reads straight off the three blocks: D1 goes to object+$4B0 (X), D2 to +$4B4
  (Y), D3 to +$4B8 (Z), each ADDED, each via IntToFixed. It accumulates.
  -------------------------------------------------------------------------- }
procedure ObjTranslate(DX_, DY_, DZ_ : Integer);
begin
  Inc(PosX, DX_);
  Inc(PosY, DY_);
  Inc(PosZ, DZ_);
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
  I          : Integer;
  X, Y, Z, T : LongInt;
  FX, FY, FZ : Real;
  Sx, Sy     : Integer;
begin
  { 12c5:02f4 -- Math_SinCos(angle, var C, var S). The FIRST var parameter
    takes the COSINE; see the note in P1S4. }
  CosA := Round(Cos(A1 / 10 * Pi / 180) * 65536.0);
  SinA := Round(Sin(A1 / 10 * Pi / 180) * 65536.0);
  CosB := Round(Cos(A2 / 10 * Pi / 180) * 65536.0);
  SinB := Round(Sin(A2 / 10 * Pi / 180) * 65536.0);
  CosC := Round(Cos(A3 / 10 * Pi / 180) * 65536.0);
  SinC := Round(Sin(A3 / 10 * Pi / 180) * 65536.0);

  for I := 1 to PtCount do
  begin
    X := Pt[I, 1];  Y := Pt[I, 2];  Z := Pt[I, 3];

    T := (Y * CosA + Z * SinA) div 65536;         { about X }
    Z := (Z * CosA - Y * SinA) div 65536;
    Y := T;
    T := (X * CosB - Z * SinB) div 65536;         { about Y }
    Z := (Z * CosB + X * SinB) div 65536;
    X := T;
    T := (X * CosC + Y * SinC) div 65536;         { about Z }
    Y := (Y * CosC - X * SinC) div 65536;
    X := T;

    Inc(X, PosX);  Inc(Y, PosY);  Inc(Z, PosZ);

    { The original would divide by zero here; Z passes near it because
      Obj_Translate accumulates a large Z swing. Guarded rather than faithful. }
    if Z = 0 then Z := 1;

    FX := X;  FY := Y;  FZ := Z;
    Sx := Round(FX / FZ * (Scale / 65536.0)) + CentreX div 2;
    Sy := CentreY div 2 - Round(FY / FZ * (Scale / 65536.0));

    Scr[I].X := Sx;                     { the object }
    Scr[I].Y := Horizon - Sy;
    Scr[I].D := Z;

    Scr[I + PtCount].X := Sx;           { and its reflection }
    Scr[I + PtCount].Y := Sy + Horizon + 1;
    Scr[I + PtCount].D := Z;
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
procedure Animate;
var
  Frame : Integer;
  Local : Integer;
begin
  Angle := 0;                           { 12c5:0764 }
  Local := 0;                           { 12c5:0769 }
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

  PosX := 0;                                   { 12c5:0918 }
  PosY := -70;                                 { 12c5:091e }
  PosZ := 1600;                                { 12c5:092c }

  { 12c5:093b -- Scale := (ScreenWidth / 2.0) * 10.0, as 16.16.
    CS:$0868 = 2.0, CS:$086C = 10.0. }
  Scale := Round((ScrWidth / 2.0) * 10.0 * 65536.0);

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
  F : file;
  I : Integer;
begin
  if Work = nil then GetMem(Work, 64000);
  WorkSeg := Seg(Work^);

  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $03BB02);
  BlockRead(F, ObjMeta, SizeOf(ObjMeta));
  BlockRead(F, Palette, 768);
  Close(F);
  SetPalette;

  FillChar(Mem[VirtScrSeg : 0], 64000, 0);
  for I := 100 to 255 do
    SetRGB(I, 0, 0, (I - 50) shr 2);
  for I := 2 to $85 do
    DrawLine(0, I, $13F, I, I + $7A, VirtScrSeg);
  for I := $86 to 199 do
    DrawLine(0, I, $13F, I, $FF - (I - $85), VirtScrSeg);
end;

procedure Scene5;
begin
  Load;
  VectorRun;
end;

end.
