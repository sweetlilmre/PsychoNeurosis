{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, scene 2.

  Segment 108b, transcribed from the disassembly. No inference, no stubs.
  See docs/22-part002-scene2.md for the working notes.

  WHAT THE SCENE IS

  Solid-filled 3-D objects over a 500-point starfield, in unchained 320x400
  with two 320x240 pages, plus a 320x40 banner strip along the bottom that two
  lines of text type themselves onto a character at a time.

  ROUTINE MAP

      Demo_Scene2         108b:2454      Obj_SetRotation     108b:00bf
      Scene2_Setup        108b:1bbd      Obj_AddRotation     108b:03be
      Scene2_Choreography 108b:11c1      Obj_SortFaces       108b:0e03
      BuildRowTable80     108b:0a09      Obj_RenderA/B/C     108b:0b42/0ca1/0a2d
      DrawText            108b:0000      Poly_FillFan        108b:09b1
      DrawRewind          108b:0422      Tri_Fill            108b:0461
      DrawBanner          108b:1101      Present             108b:0f66
      Math_SinCos         108b:342f      Math_RotatePoint    108b:34e1
      Math_Project        108b:362f
  =========================================================================== }

unit P2S2;

{$G+}   { 286: the whole segment is ENTER-framed -- Obj_Transform 108b:0e03
          opens ENTER $1136, Tri_Fill 108b:0461 ENTER $28. Under the $G-
          default the compiler multiplies with MUL and doubles the shifts,
          which is measurably slower in exactly these per-frame routines
          (plan: pacing). }

interface

procedure Scene2;

implementation

uses Crt, VGA, P2View, FixMath, DemoVT;

{$I gen/P2OBJ.INC}

const
  { 108b:0a09 -- 240 rows of 80 bytes per plane. }
  Rows        = 240;
  { The object record is $B51 bytes and the sub-arrays tile it exactly:
    4 + 75*12 + 75*6 + 65*23 + 4*12 = 2897. }
  MaxVerts    = 75;
  MaxFaces    = 65;
  FaceVerts   = 8;

  { 108b:1bbd -- DS:$046A and DS:$046C, initialised data. The projection
    centre is (160, 120), the 320x240 field, NOT (160, 100). They are typed
    constants further down rather than consts here, because Project reads
    them FROM MEMORY and the shared maths object resolves them by name. }
  { Scale := RealToFixed(CentreX / 2.0 * 0.9), from CS:$1BAF = 2.0 and the
    extended at CS:$1BB3 = 0.9. That is 144.0. }
  ScaleDivisor = 2.0;
  ScaleFactor  = 0.9;

  { 108b:0461 -- DS:$066E..$0675, initialised data. }
  ClipYMin = 0;    ClipYMax = 239;
  ClipXMin = 0;    ClipXMax = 319;

  StarCount = 500;                { $1F4 }
  TextY1    = 210;                { $D2 }
  TextY2    = 217;                { $D9 }
  TextCol   = $42;                { 108b:0097, the green set by Scene2_Setup }
  RewindW   = 34;                 { $22 }
  RewindH   = 43;                 { $2B }
  BannerTop = 200;                { $C8 }
  BannerH   = 40;
  FontFirst = 32;                 { the glyph table starts at char $20 }
  FontCount = 62;                 { 1550 bytes / 25 }
  GlyphSide = 5;

  DataOfs   = $0007D9B2;          { 108b:247a }

type
  TVertex = record X, Y, Z : LongInt end;    { 16.16, hence 12 bytes }
  TScreen = record X, Y, D : Integer end;
  { 23 bytes in the original: count, eight indices, colour, two spare bytes,
    then the average depth the sort writes at +$15. }
  TFace = record
    Count  : Integer;
    Idx    : array[1..FaceVerts] of Integer;
    Colour : Byte;
    Spare1 : Byte;
    Spare2 : Byte;
    Depth  : Integer;
  end;
  TVec3 = record X, Y, Z : LongInt end;   { +0, +4, +8 }
  TObj = record
    VertCount : Integer;                        { +$000 }
    FaceCount : Integer;                        { +$002 }
    Vert  : array[1..MaxVerts] of TVertex;      { +$004 }
    Scr   : array[1..MaxVerts] of TScreen;      { +$388 }
    Face  : array[1..MaxFaces] of TFace;        { +$54A }
    { RECORDS, NOT array[1..3], and a probe settled it rather than an
      argument. ObjTransform's frame is ENTER $36 and the reconstruction's
      was $30 with the declared locals already matching byte for byte; the
      six-byte gap is two far-pointer spills the compiler makes for NESTED
      `with` over a RECORD. probe/WITHTMP.PAS compiles the same routine four
      ways with identical declarations -- arrays plain $30, arrays with $34,
      records plain $30, RECORDS WITH $36 -- so it takes both changes and
      neither alone. Confirmed in the rebuild: ObjTransform now opens
      ENTER $36 and part 002's coverage walk moved 51.0% to 53.0%. }
    Angle : TVec3;                              { +$B21 }
    Trans : TVec3;                              { +$B2D }
    Pivot : TVec3;                              { +$B39 }
    Accum : TVec3;                              { +$B45 }
  end;
  TObjPtr = ^TObj;

  TStar = record X, Y, Z : Integer end;         { DS:$9485, stride 6 }
  { DS:$5448, 1,550 bytes -- assets/part002/font_5x5.bin }
  TFont = array[0..FontCount * 25 - 1] of Byte;
  { the GetMem'd 12,800 bytes -- assets/part002/banner_320x40.png }
  TBanner = array[0..BannerH * ScrWidth - 1] of Byte;
  { DS:$8ED5, 1,462 bytes -- assets/part002/rewind_button.bin }
  TRewind = array[1..RewindW * RewindH] of Byte;

var
  { The four objects. In the original they are four fixed DGROUP blocks $B51
    apart at $5A56, $65A7, $70F8 and $7C49. }
  Obj    : array[1..4] of TObjPtr;
  Star   : array[1..StarCount] of TStar;
  Font   : ^TFont;
  Banner : ^TBanner;                            { the GetMem'd 12,800 bytes }
  Rewind : TRewind;
  Pal    : array[0..767] of Byte;               { DS:$5148 }

{ --------------------------------------------------------------------------
  THE SHARED 386 MATHS MODULE.

  SinCos, RotatePoint and Project are 386 code and cannot be written in Turbo
  Pascal's built-in assembler, which stops at the 286. They live in
  src/asm/DEMOMATH.ASM, are assembled by TASM and linked in here with the $L
  directive -- which is what the original does: 108b:342F, 108b:34E1 and
  108b:362F are the same code as part 001 scenes 4 and 5, once per unit.

  The nine names below are the module's EXTRNs, so they have to be declared
  BEFORE the $L directive and spelled exactly this way.
  -------------------------------------------------------------------------- }
  { DS:$87AC..$87C3 -- cos then sin per axis, as SinCos leaves them. }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  { DS:$87C4 -- the projection scale, 16.16 }
  MScale : LongInt;
  { DS:$8ED1 -- a LongInt frame counter, and what drives the text. }
  Frame  : LongInt;
  { DS:$A0CA -- RowOfs80[I] = I * 80. }
  RowOfs : array[0..Rows - 1] of Word;
  { the snapshot Obj_SortFaces works from }
  FaceCopy : array[1..MaxFaces] of TFace;
  { Tri_Fill's per-scanline edge buffer, DS:$A2AA }
  EdgeL, EdgeR : array[0..Rows] of Integer;

  { the two typed messages -- Pascal strings at DS:$046E and DS:$056E }
  Msg1 : String;
  Msg2 : String;

{ --------------------------------------------------------------------------
  108b:0a09 -- RowOfs[I] := I * 80, for I = 0..$EF.
  -------------------------------------------------------------------------- }
procedure BuildRowTable80;
var
  I : Integer;
begin
  for I := 0 to Rows - 1 do
    RowOfs[I] := I * PlaneWidth;
end;

const
  { DS:$046A = 320 and DS:$046C = 240. Project halves both, so these are the
    FULL view size and not the centre -- which is why the vertical centre is
    120 and not the 100 a 320x200 assumption would give. }
  MViewW : Word = 320;
  MViewH : Word = 240;

{$L DEMOMATH.OBJ}

{ --------------------------------------------------------------------------
  108b:342f -- SinCos(Angle : Integer; var C, S : LongInt)

  A 901-entry 16.16 COSINE table at CS:$261B, quadrant-folded. Angles are in
  tenths of a degree and wrap at $E10. The FIRST var parameter takes the
  cosine.

  108b:34e1 -- RotatePoint(var X, Y, Z : LongInt)

  Three concatenated 2-D rotations, X then Y then Z:

      y1 = y*C1 + z*S1      z1 = z*C1 - y*S1
      x2 = x*C2 - z1*S2     z2 = z1*C2 + x*S2
      x3 = x2*C3 + y1*S3    y3 = y1*C3 - x2*S3

  108b:362f -- Project(var X, Y, Z : LongInt)

      Sx := Round(X/Z * MScale) + MViewW div 2
      Sy := MViewH div 2 - Round(Y/Z * MScale)

  All three are in src/asm/DEMOMATH.ASM, commented there. An earlier version
  of this file had them as Pascal over Reals, which is a different program:
  the original's multiply is 32x32->64 taking the MIDDLE 32 bits, and its
  divide builds a 48-bit dividend so the quotient comes out 16.16. Neither
  fits in a Turbo Pascal LongInt.
  -------------------------------------------------------------------------- }
procedure SinCos(A : Integer; var C, S : LongInt);      external; { 108b:342F }
procedure RotatePoint(var X, Y, Z : LongInt);           external; { 108b:34E1 }
procedure Project(var X, Y, Z : LongInt);               external; { 108b:362F }

{ --------------------------------------------------------------------------
  108b:03be -- Obj_AddRotation(var Obj; DX, DY, DZ)

  Despite the name, it adds to the TRANSLATION at Obj+$B2D, one IntToFixed per
  component. The call sites pass sign-extended LongInts of which the routine
  reads only the low word.
  -------------------------------------------------------------------------- }
procedure ObjTranslate(var O : TObj; DX, DY, DZ : Integer);
begin
  Inc(O.Trans.X, IntToFixed(DX));
  Inc(O.Trans.Y, IntToFixed(DY));
  Inc(O.Trans.Z, IntToFixed(DZ));
end;

{ --------------------------------------------------------------------------
  108b:00bf -- Obj_SetRotation(var Obj; A1, A2, A3)

  Also badly named: this is the whole per-frame transform.

    1. wrap the three accumulated angles at Obj+$B45 -- if negative, +3600
    2. SinCos them into DS:$87AC..$87C3
    3. rotate the pivot Obj+$B39 with those
    4. wrap A1..A3, store them into Obj+$B21, and SinCos them into the SAME
       six globals -- overwriting step 2
    5. for every vertex: rotate, add the rotated pivot, add the translation,
       project, and store X, Y and Trunc(Z) into the screen record

  Step 2's sines and cosines are therefore used only for the pivot. That is
  what the code does.
  -------------------------------------------------------------------------- }
{ THE FRAME IS ENTER $36 -- 54 bytes -- AND IT TOOK FIVE DECLARATIONS TO FILL,
  two of which the routine never reads. 46 bytes are declared and 8 are the
  code generator's two far-pointer spills at [BP-$30] and [BP-$34]. Every
  BP-relative access in 108b:00bf..03bd was enumerated, in both the disp8 and
  the disp16 addressing forms, and this is the whole list:

      [BP-$02]..[BP-$08]   8 bytes   NEVER TOUCHED
      [BP-$0a]             I, the vertex counter -- 108b:02a3 IMUL by 12
      [BP-$0c]..[BP-$16]  12 bytes   NEVER TOUCHED
      [BP-$22]..[BP-$17]   V, and it is an ARRAY
      [BP-$2e]..[BP-$23]   P, likewise
      [BP-$30], [BP-$34]   the LES spills -- compiler temps, not declarations

  V AND P ARE ARRAYS, NOT SIX SCALARS, and one instruction proves it: the
  original loads a vertex with `Move(O.Vert[I], V, 12)` -- 108b:02b2 LEAs
  [BP-$22], pushes 12, and far-calls Move -- which only works if V[1], V[2]
  and V[3] are twelve consecutive bytes in that order. The pivot is loaded the
  same way at 108b:0198, `Move(O.Pivot, P, 12)`. Three separate assignments
  cannot produce that, and the reconstruction had three.

  THE TWO DEAD BLOCKS ARE TRANSCRIBED DELIBERATELY. Their sizes and positions
  are measured; their types are not recoverable, because nothing reads them --
  12 bytes in the same place as V and P is most likely a third vector the
  author stopped using. Leaving them out is not a tidier reconstruction, it is
  a wrong one: every local after them moves, and the frame stops being $36.

  THE WRAP IS INLINE, SIX TIMES. The reconstruction had a nested procedure
  called six times; the original has no call and no static link -- the
  test-and-add is written out at 108b:00d6, 0100, 012c for the accumulators
  and 01c3, 01e3, 0203 for the parameters.

  AND THE DEPTH KEY IS TAKEN AFTER Project, NOT BEFORE. The original projects,
  stores X and Y, and only then computes D from V[3] (108b:0393). That reads
  like a behavioural difference and is NOT one: Project writes back only its
  first two var parameters -- 108b:36c4 and 36ce store through [BP+$0c] and
  [BP+$08] and nothing stores through [BP+$04] -- so Z is unchanged across the
  call and either order gives the same key. Recorded because the next reader
  will have the same doubt, and the answer cost a disassembly. }
procedure ObjTransform(var O : TObj; A1, A2, A3 : LongInt);
var
  Unused1 : array[1..2] of LongInt;   { [BP-$08]..[BP-$01], never read }
  I       : Integer;                  { [BP-$0a] }
  Unused2 : array[1..3] of LongInt;   { [BP-$16]..[BP-$0b], never read }
  V       : array[1..3] of LongInt;   { [BP-$22] -- the working vertex }
  P       : array[1..3] of LongInt;   { [BP-$2e] -- the rotated pivot }
begin
  with O do                             { 108b:00c3 -- @O into [BP-$32] }
  begin
    with Accum do                       { 108b:00cc -- @O.Accum into [BP-$36] }
    begin
      { X := X + 3600, NOT Inc(X, 3600). The original loads the pair into
        AX:DX, adds, and stores back (108b:00e8..00f8); Inc compiles to an
        in-place ADD/ADC on memory. Same arithmetic, four bytes apart. }
      if X < 0 then X := X + 3600;      { 108b:00d6 }
      if Y < 0 then Y := Y + 3600;      { 108b:0100 }
      if Z < 0 then Z := Z + 3600;      { 108b:012c }
      SinCos(X, MCos1, MSin1);          { 108b:0154, through the same temp }
      SinCos(Y, MCos2, MSin2);
      SinCos(Z, MCos3, MSin3);
    end;

    { Pivot is reached through @O, not through a temp of its own -- 108b:018f
      reloads [BP-$32] and adds $B39 -- so it is NOT inside a `with`. }
    Move(Pivot, P, 12);                 { 108b:0198 }
    RotatePoint(P[1], P[2], P[3]);

    with Angle do                       { 108b:01b6 -- @O.Angle into [BP-$36] }
    begin
      { the scratch temp is set up BEFORE these wraps, which is what says the
        `with` opens here rather than after them }
      if A1 < 0 then A1 := A1 + 3600;   { 108b:01c3 }
      if A2 < 0 then A2 := A2 + 3600;   { 108b:01e3 }
      if A3 < 0 then A3 := A3 + 3600;   { 108b:0203 }
      X := A1;  Y := A2;  Z := A3;
      SinCos(A1, MCos1, MSin1);
      SinCos(A2, MCos2, MSin2);
      SinCos(A3, MCos3, MSin3);
    end;

    for I := 1 to VertCount do
    begin
      Move(Vert[I], V, 12);             { 108b:02b2 }
      RotatePoint(V[1], V[2], V[3]);
      V[1] := V[1] + P[1] + Trans.X;
      V[2] := V[2] + P[2] + Trans.Y;
      V[3] := V[3] + P[3] + Trans.Z;    { 108b:033b }
      Project(V[1], V[2], V[3]);        { 108b:035a }
      { both come back zero-extended, so the low word carries the sign }
      Scr[I].X := Integer(V[1]);        { 108b:0370 }
      Scr[I].Y := Integer(V[2]);        { 108b:0388 }
      Scr[I].D := FixedToInt(V[3]);     { 108b:0393 -- AFTER Project }
    end;
  end;
end;

{ --------------------------------------------------------------------------
  108b:0e03 -- Obj_SortFaces(var Obj)

  Copies the object, keys every face with the average of its vertices' D, then
  selection-sorts back into the ORIGINAL, farthest first:

      repeat
        find the face with the SMALLEST key   (108b:0eff, best starts at 0)
        if none is below zero then stop
        copy it into the next slot and zero its key
      until done

  Two consequences worth stating, because both are visible and both are the
  original's behaviour:

    * anything with D >= 0 is culled -- the objects sit at negative Z, so this
      is a near-plane cull;
    * the number of faces that survived is NEVER written back to Obj+2, so the
      renderers still walk FaceCount faces and the tail of the array holds
      whatever the previous frame left there.
  -------------------------------------------------------------------------- }
procedure ObjSortFaces(var O : TObj);
var
  F, K, Slot, Best : Integer;
  BestKey, Sum     : LongInt;
begin
  for F := 1 to O.FaceCount do
  begin
    FaceCopy[F] := O.Face[F];
    Sum := 0;
    for K := 1 to FaceCopy[F].Count do
      Inc(Sum, O.Scr[FaceCopy[F].Idx[K]].D);
    if FaceCopy[F].Count <> 0 then
      FaceCopy[F].Depth := Sum div FaceCopy[F].Count
    else
      FaceCopy[F].Depth := 0;
  end;

  Slot := 1;
  repeat
    Best    := 0;
    BestKey := 0;
    for F := 1 to O.FaceCount do
      if FaceCopy[F].Depth < BestKey then
      begin
        BestKey := FaceCopy[F].Depth;
        Best    := F;
      end;
    if Best > 0 then
    begin
      O.Face[Slot] := FaceCopy[Best];
      FaceCopy[Best].Depth := 0;
      Inc(Slot);
    end;
  until Best = 0;
end;

{ --------------------------------------------------------------------------
  108b:0461 -- Tri_Fill(X1, Y1, X2, Y2, X3, Y3, Colour)

  A scanline triangle filler writing through the Map Mask, with the clip box
  from DS:$066E..$0675 and the same two nibble-mask tables the rectangle fill
  in P2View uses. The original passes the first two vertices in BX/CX and
  DX/SI and the rest on the stack, sorts the three by Y with a chain of XCHGs,
  walks two edges into a per-scanline buffer at DS:$A2AA, then fills the spans
  backwards from the last scanline. Direction does not matter for a solid
  fill, so it is written forwards here.

  It writes to WritePage through the 80-byte row table BuildRowTable80 fills.
  -------------------------------------------------------------------------- }
procedure TriFill(X1, Y1, X2, Y2, X3, Y3 : Integer; Colour : Byte);
var
  T, Y     : Integer;
  XL, XR   : Integer;
  D        : Word;
  LM, RM   : Byte;
  Mid, I   : Integer;

  procedure Edge(AX, AY, BX_, BY : Integer);
  var
    Row  : Integer;
    Num  : LongInt;
  begin
    if BY = AY then Exit;
    for Row := AY to BY - 1 do
    begin
      if (Row >= 0) and (Row <= Rows) then
      begin
        Num := LongInt(BX_ - AX) * (Row - AY);
        T := AX + Num div (BY - AY);
        if T < EdgeL[Row] then EdgeL[Row] := T;
        if T > EdgeR[Row] then EdgeR[Row] := T;
      end;
    end;
  end;

begin
  { degenerate: all three the same point, or two identical Y with equal X }
  if (X1 = X2) and (X2 = X3) then Exit;
  if (Y1 = Y2) and (Y2 = Y3) then Exit;

  { sort by Y, the XCHG chain at 108b:0485..108b:04a2 }
  if Y1 > Y2 then
  begin
    T := X1; X1 := X2; X2 := T;  T := Y1; Y1 := Y2; Y2 := T;
  end;
  if Y2 > Y3 then
  begin
    T := X2; X2 := X3; X3 := T;  T := Y2; Y2 := Y3; Y3 := T;
  end;
  if Y1 > Y2 then
  begin
    T := X1; X1 := X2; X2 := T;  T := Y1; Y1 := Y2; Y2 := T;
  end;

  if Y3 < ClipYMin then Exit;
  if Y1 > ClipYMax then Exit;

  for Y := Y1 to Y3 do
    if (Y >= 0) and (Y <= Rows) then
    begin
      EdgeL[Y] := 32767;
      EdgeR[Y] := -32768;
    end;

  Edge(X1, Y1, X3, Y3);
  Edge(X1, Y1, X2, Y2);
  Edge(X2, Y2, X3, Y3);

  for Y := Y1 to Y3 - 1 do
  begin
    if (Y < ClipYMin) or (Y > ClipYMax) then Continue;
    XL := EdgeL[Y];
    XR := EdgeR[Y];
    if XL > XR then Continue;
    if XR > ClipXMax then XR := ClipXMax;       { 108b:08f6 }
    if XL < ClipXMin then XL := ClipXMin;       { 108b:090e }
    if XR <= XL then Continue;

    D   := RowOfs[Y] + (Word(XL) shr 2) + WritePage;
    LM  := LeftMaskOf(XL);
    RM  := RightMaskOf(XR);
    Mid := ((XR - 1) - (XL and $FFFC)) shr 2;
    if Mid = 0 then LM := LM and RM;

    Port[$3C4] := 2;
    Port[$3C5] := LM;
    Mem[$A000 : D] := Colour;
    if Mid > 0 then
    begin
      Port[$3C5] := $0F;
      for I := 1 to Mid - 1 do
        Mem[$A000 : D + I] := Colour;
      Port[$3C5] := RM;
      Mem[$A000 : D + Mid] := Colour;
    end;
  end;
end;

{ --------------------------------------------------------------------------
  108b:09b1 -- Poly_FillFan(Pts, Count, Colour, Page)

  `if Count < 3 then exit`, then Count-2 triangles all sharing the first
  point. The Page parameter is passed but never read -- Tri_Fill takes the
  page from the global instead.
  -------------------------------------------------------------------------- }
type
  TPointList = array[1..FaceVerts] of record X, Y : Integer end;

procedure FillFan(var Pts : TPointList; Count : Integer; Colour : Byte);
var
  I : Integer;
begin
  if Count < 3 then Exit;
  for I := 2 to Count - 1 do
    TriFill(Pts[1].X, Pts[1].Y,
            Pts[I].X, Pts[I].Y,
            Pts[I + 1].X, Pts[I + 1].Y, Colour);
end;

{ [transcribed] 108b:0b42 star loop -- 500 points through P2View's Plot. }
procedure DrawStars;
var
  I : Integer;
begin
  for I := 1 to StarCount do
    Plot(Star[I].X, Star[I].Y, Star[I].Z);
end;

{ --------------------------------------------------------------------------
  108b:0422 -- DrawSprite

  A 34 x 43 image plotted a pixel at a time at the top-left corner, from the
  1,462-byte block the loader puts at DS:$8ED5. The indexing at 108b:0443 is
  `Y * $22 + X` off a base $23 lower, which makes it one-based in both axes.
  -------------------------------------------------------------------------- }
procedure DrawRewind;
var
  X, Y : Integer;
begin
  for Y := 1 to RewindH do
    for X := 1 to RewindW do
      Plot(X, Y, Rewind[(Y - 1) * RewindW + X]);
end;

{ --------------------------------------------------------------------------
  108b:0000 -- DrawText(X, Y, S)

  A 5 x 5 bitmap font. For each character, for R and C both 1..5, the glyph
  byte is at `Char * 25 + R * 5 + C` off DS:$5122 -- and the loader reads the
  glyphs to DS:$5448, which is 806 bytes higher, so the effective index is

      (Ord(Ch) - 32) * 25 + (R - 1) * 5 + (C - 1)

  a clean 5 x 5 glyph biased by 32, the same shape as the fonts in part 001.
  R is the horizontal axis and C the vertical; the pen steps 6 per character.
  Every pixel is drawn in colour $42.
  -------------------------------------------------------------------------- }
procedure DrawText(X, Y : Integer; S : String);
var
  I, R, C, G, Pen : Integer;
begin
  Pen := 0;
  for I := 1 to Length(S) do
  begin
    G := Ord(S[I]) - FontFirst;
    if (G >= 0) and (G < FontCount) then
      for R := 1 to GlyphSide do
        for C := 1 to GlyphSide do
          if Font^[G * 25 + (R - 1) * GlyphSide + (C - 1)] <> 0 then
            Plot(R + X + Pen, C + Y, TextCol);
    Inc(Pen, 6);
  end;
end;

{ --------------------------------------------------------------------------
  108b:1101 -- DrawBanner

  Colours 100..200 are loaded from the 768-byte palette at DS:$5148, then the
  12,800-byte block read into the heap is plotted into rows 200..239 -- of
  BOTH pages, a pixel at a time. 12,800 is 320 x 40, exactly that strip.
  -------------------------------------------------------------------------- }
procedure DrawBanner;
var
  X, Y, Col : Integer;
begin
  for Col := 100 to 200 do
    SetRGB(Col, Pal[Col * 3], Pal[Col * 3 + 1], Pal[Col * 3 + 2]);

  for X := 0 to ScrWidth - 1 do
    for Y := BannerTop to Rows - 1 do
    begin
      WritePage := PageBase[0];
      Plot(X, Y, Banner^[(Y - BannerTop) * ScrWidth + X]);
      WritePage := PageBase[1];
      Plot(X, Y, Banner^[(Y - BannerTop) * ScrWidth + X]);
    end;
end;

{ --------------------------------------------------------------------------
  108b:0f66 -- Present

  The typewriter. Driven entirely by the frame counter at DS:$8ED1:

      100 < Frame < 150     message 1, character Frame-100
      250 < Frame < 300     message 2, character Frame-250

  and the X position is `(index * 6) + 15` -- the RTL helper at 14b1:3651 is a
  LongInt MULTIPLY (its operand arrives in BX:CX), not a divide, so the pen
  really does step six pixels a character. Each character is drawn into BOTH
  pages so it survives the flip.
  -------------------------------------------------------------------------- }
procedure Emit(S : String; Idx, Y : Integer);
var
  X : Integer;
begin
  if (Idx < 1) or (Idx > Length(S)) then Exit;
  X := Idx * 6 + 15;
  WritePage := PageBase[0];
  DrawText(X, Y, S[Idx]);
  WritePage := PageBase[1];
  DrawText(X, Y, S[Idx]);
end;

procedure Present;
begin
  if (Frame > 100) and (Frame < 150) then
    Emit(Msg1, Frame - 100, TextY1);
  if (Frame > 250) and (Frame < 300) then
    Emit(Msg2, Frame - 250, TextY2);
end;

{ --------------------------------------------------------------------------
  108b:0b42 / 108b:0ca1 / 108b:0a2d -- the three renderers

  All three share a body: gather each face's vertices' screen X and Y into an
  interleaved list, fill the fan, then flip the page and toggle DS:$0CEC.
  They differ only in what is drawn underneath:

      A   500 stars
      B   500 stars, then the badge
      C   nothing
  -------------------------------------------------------------------------- }
procedure RenderFaces(var O : TObj);
var
  F, K : Integer;
  Pts  : TPointList;
begin
  for F := 1 to O.FaceCount do
  begin
    for K := 1 to O.Face[F].Count do
    begin
      Pts[K].X := O.Scr[O.Face[F].Idx[K]].X;
      Pts[K].Y := O.Scr[O.Face[F].Idx[K]].Y;
    end;
    FillFan(Pts, O.Face[F].Count, O.Face[F].Colour);
  end;
end;

procedure FlipAndSwap;
begin
  FlipPage(WritePage);
  PageIndex := (PageIndex + 1) mod 2;
end;

procedure RenderA(var O : TObj);
begin
  DrawStars;
  RenderFaces(O);
  FlipAndSwap;
end;

procedure RenderB(var O : TObj);
begin
  DrawStars;
  DrawRewind;                          { 108b:0d18 }
  RenderFaces(O);
  FlipAndSwap;
end;

procedure RenderC(var O : TObj);
begin
  RenderFaces(O);
  FlipAndSwap;
end;

{ --------------------------------------------------------------------------
  108b:1bbd -- Scene2_Setup

  Palette, then the four objects out of the compiled-in tables. Every vertex
  component and every face colour is HALVED and every face vertex index is
  stored PLUS ONE; tools/p2obj.py has already done all three when it generated
  gen/P2OBJ.INC, so the loops here just copy.
  -------------------------------------------------------------------------- }
{ 108b:1e4c and its three siblings zero the angle, translation and pivot
  blocks before writing whichever components the object needs.

  WHICH BLOCK BELONGS TO WHICH OBJECT is not what the source order suggests.
  Each block sits AFTER its object's face loop and BEFORE the next object's
  vertex loop, so the one at 108b:201b reads as though it introduced object 3
  when its addresses ($70C8 and up) are object 2's base $65A7 plus $B21. Take
  the base from the address, not from the position:

      108b:1e4c  ->  $6577 - $B21 = $5A56   object 1
      108b:201b  ->  $70C8 - $B21 = $65A7   object 2
      108b:21f1  ->  $7C19 - $B21 = $70F8   object 3
      108b:23cc  ->  $876A - $B21 = $7C49   object 4 }
procedure BuildObject(N, NV, NF : Integer);
begin
  New(Obj[N]);
  FillChar(Obj[N]^, SizeOf(TObj), 0);
  Obj[N]^.VertCount := NV;
  Obj[N]^.FaceCount := NF;
end;

{ THE FRAME IS ENTER $8a -- 138 bytes -- AND ONLY SIX OF THEM ARE READ.
  Every BP-relative access in 108b:1bbd..2453 was enumerated in both
  addressing forms (kit/tools/pascal/prologue.py), and the whole list is:

      [BP-$02]  79 references     the palette ramp counter, and the same
                                  variable again as an inner face-index
                                  counter at 108b:1db4 -- ONE variable, two
                                  roles, which is why the reconstruction's
                                  separate Col and K are wrong about the
                                  original even though they compute the same
                                  thing
      [BP-$04]  16 references
      [BP-$06]  28 references
      [BP-$08]..[BP-$86]   128 bytes, NEVER TOUCHED
      [BP-$88], [BP-$8a]   the code generator's, not declarations: a LongInt
                           spilled for `FILD DWORD` at 108b:1cc1 and a for-loop
                           upper bound at 108b:1da4

  So 134 bytes are declared and 128 of them are dead. The type is NOT
  recoverable -- nothing reads it, so nothing constrains it beyond its size
  and position; 128 bytes here is the size of a `String[127]`, which would be
  a natural thing for an asset loader to declare and then not use. It is
  transcribed as bytes because that is what is measured.

  Leaving it out is not a tidier reconstruction. It is the reason this routine
  opened ENTER $06 against the original's $8a. }
procedure Setup;
var
  I, K, Col : Integer;
  Unused    : array[1..128] of Byte;   { [BP-$86]..[BP-$07], never read }
begin
  { 108b:1bc1 -- a grey ramp with a period of 53 }
  for Col := 1 to 255 do
    SetRGB(Col, (Col mod 53) + 10, (Col mod 53) + 10, (Col mod 53) + 10);

  { 108b:1c05 -- the thirteen overrides, in the order the code writes them }
  SetRGB($18, $0A, $00, $3C);
  SetRGB($30, $0A, $00, $3C);
  SetRGB($42, $00, $32, $00);
  SetRGB($D5, $32, $28, $1E);
  SetRGB($D6, $3C, $32, $28);
  SetRGB($D7, $37, $2D, $23);
  SetRGB($D8, $2D, $23, $19);
  SetRGB($D9, $28, $1E, $14);
  SetRGB($D1, $32, $28, $1E);
  SetRGB($D2, $3C, $32, $28);
  SetRGB($D3, $37, $2D, $23);
  SetRGB($D4, $2D, $23, $19);
  SetRGB($D5, $28, $1E, $14);

  { 108b:1cb3 -- Scale := CentreX / 2.0 * 0.9 = 144.0.

    WITHDRAWN, 24 Aug 2026, and kept here because the argument was good and
    the measurement still said no. The original reads MViewW from memory and
    widens it with `XOR DX,DX` (108b:1cb6, unsigned -- the Word typed constant
    at DS:$046A), does `FILD DWORD` on the spill, divides by the single 2.0 at
    CS:$1baf, multiplies by the extended 0.9 at CS:$1bb3, and then pushes
    DX/BX/AX into a far call -- a six-byte Real handed to a FUNCTION, which
    reads exactly like RealToFixed rather than Round(.. * 65536.0).

    So `MScale := RealToFixed(MViewW / ScaleDivisor * ScaleFactor)` was tried.
    It made a specific prediction -- the LongInt spill would appear and the
    frame would go from $86 to the original's $8a -- and the prediction FAILED:
    the frame did not move and part 002's walk went 57.3% to 57.2%. Whatever
    produces that spill, this is not it. The Round form is kept because it is
    the one that measures better, not because it is believed. }
  MScale := Round(MViewW / ScaleDivisor * ScaleFactor * 65536.0);

  BuildObject(1, EnterpriseVertCount, EnterpriseFaceCount);
  for I := 1 to EnterpriseVertCount do
  begin
    Obj[1]^.Vert[I].X := IntToFixed(EnterpriseVerts[I, 1]);
    Obj[1]^.Vert[I].Y := IntToFixed(EnterpriseVerts[I, 2]);
    Obj[1]^.Vert[I].Z := IntToFixed(EnterpriseVerts[I, 3]);
  end;
  for I := 1 to EnterpriseFaceCount do
  begin
    Obj[1]^.Face[I].Count := EnterpriseFaces[I, 0];
    for K := 1 to FaceVerts do Obj[1]^.Face[I].Idx[K] := EnterpriseFaces[I, K];
    Obj[1]^.Face[I].Colour := EnterpriseFaces[I, FaceVerts + 1];
  end;
  { 108b:1e8c -- translation (0, 0, -850), pivot (150, 0, 0) }
  Obj[1]^.Trans.Z := IntToFixed(-850);
  Obj[1]^.Pivot.X := IntToFixed(150);

  BuildObject(2, RevolverVertCount, RevolverFaceCount);
  for I := 1 to RevolverVertCount do
  begin
    Obj[2]^.Vert[I].X := IntToFixed(RevolverVerts[I, 1]);
    Obj[2]^.Vert[I].Y := IntToFixed(RevolverVerts[I, 2]);
    Obj[2]^.Vert[I].Z := IntToFixed(RevolverVerts[I, 3]);
  end;
  for I := 1 to RevolverFaceCount do
  begin
    Obj[2]^.Face[I].Count := RevolverFaces[I, 0];
    for K := 1 to FaceVerts do Obj[2]^.Face[I].Idx[K] := RevolverFaces[I, K];
    Obj[2]^.Face[I].Colour := RevolverFaces[I, FaceVerts + 1];
  end;
  { 108b:204b }
  Obj[2]^.Trans.X := IntToFixed(1500);
  Obj[2]^.Trans.Z := IntToFixed(-1500);
  Obj[2]^.Pivot.X := IntToFixed(150);

  BuildObject(3, SailboatVertCount, SailboatFaceCount);
  for I := 1 to SailboatVertCount do
  begin
    Obj[3]^.Vert[I].X := IntToFixed(SailboatVerts[I, 1]);
    Obj[3]^.Vert[I].Y := IntToFixed(SailboatVerts[I, 2]);
    Obj[3]^.Vert[I].Z := IntToFixed(SailboatVerts[I, 3]);
  end;
  for I := 1 to SailboatFaceCount do
  begin
    Obj[3]^.Face[I].Count := SailboatFaces[I, 0];
    for K := 1 to FaceVerts do Obj[3]^.Face[I].Idx[K] := SailboatFaces[I, K];
    Obj[3]^.Face[I].Colour := SailboatFaces[I, FaceVerts + 1];
  end;
  { 108b:2221 -- writes $7C25 and $7C2D, which are $70F8 + $B2D + 0 and + 8.
    X and Z, NOT X and Y: leaving Z at zero puts the object on the projection
    plane and the divide at 108b:3656 blows the whole thing across the screen. }
  Obj[3]^.Trans.X := IntToFixed(-1500);
  Obj[3]^.Trans.Z := IntToFixed(-1500);

  BuildObject(4, QuadVertCount, QuadFaceCount);
  for I := 1 to QuadVertCount do
  begin
    Obj[4]^.Vert[I].X := IntToFixed(QuadVerts[I, 1]);
    Obj[4]^.Vert[I].Y := IntToFixed(QuadVerts[I, 2]);
    Obj[4]^.Vert[I].Z := IntToFixed(QuadVerts[I, 3]);
  end;
  for I := 1 to QuadFaceCount do
  begin
    Obj[4]^.Face[I].Count := QuadFaces[I, 0];
    for K := 1 to FaceVerts do Obj[4]^.Face[I].Idx[K] := QuadFaces[I, K];
    Obj[4]^.Face[I].Colour := QuadFaces[I, FaceVerts + 1];
  end;
  { 108b:240c -- writes $877E = $7C49 + $B2D + 8, so this is Z. }
  Obj[4]^.Trans.Z := IntToFixed(-1000);
end;

{ ===========================================================================
  108b:11c1 -- Scene2_Choreography

  Fourteen phases. The body of a phase frame is always the same shape:

      ObjTranslate(O, dx, dy, dz)
      ObjTransform(O, PC, PA, PB)
      WritePage := PageBase[PageIndex]
      FillRect(0, 0, 320, H, WritePage, 0)          H = 200 or 240
      ObjSortFaces(O)
      RenderA / RenderB / RenderC
      Inc(Frame)                                    phases 1..11 only
      Present                                       phases 1..11 only

  PA, PB and PC are the three angle accumulators the phases nudge; they are
  passed to ObjTransform in the order (PC, PA, PB), which is how 108b:12a0
  pushes them.
  =========================================================================== }
var
  PA, PB, PC : LongInt;

procedure PhaseFrame(var O : TObj; DX, DY, DZ : Integer;
                     ClearH : Integer; Kind : Integer; Counted : Boolean);
begin
  ObjTranslate(O, DX, DY, DZ);
  ObjTransform(O, PC, PA, PB);
  WritePage := PageBase[PageIndex];
  FillRect(0, 0, ScrWidth, ClearH, WritePage, 0);
  ObjSortFaces(O);
  case Kind of
    0 : RenderA(O);
    1 : RenderB(O);
    2 : RenderC(O);
  end;
  if Counted then
  begin
    Inc(Frame);
    Present;
  end;
end;

procedure ClearBannerStrip;
begin
  WritePage := PageBase[0];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  WritePage := PageBase[1];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
end;

procedure BannerBeat;
var
  I : Integer;
begin
  SyncPattern(3, 1);                  { 108b:15ca }
  WaitRetrace;
  DrawBanner;
  for I := 1 to 50 do WaitRetrace;
  ClearBannerStrip;
end;

procedure Choreography;
var
  I   : Integer;
  Buf : array[0..767] of Byte;
begin
  { 108b:11c5 -- a blue ramp into colours 70..90 }
  for I := $46 to $5A do
    SetRGB(I, 0, 0, (I - $46) * 3);

  { 108b:11ef }
  for I := 1 to StarCount do
  begin
    Star[I].X := Random(320);
    Star[I].Y := Random(200);
    Star[I].Z := Random(20) + 70;
  end;

  PA := 0;  PB := 0;  PC := 0;
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);

  for I := 1 to 100 do PhaseFrame(Obj[1]^,  0, 0,  3, 200, 0, True);
  SyncPattern(2, 1);
  for I := 1 to  80 do PhaseFrame(Obj[1]^,  0, 0,  3, 200, 0, True);
  for I := 1 to  20 do PhaseFrame(Obj[1]^, -1, 0,  3, 200, 0, True);

  for I := 1 to 50 do
  begin
    Inc(PB, 5);  Dec(PC, 2);
    PhaseFrame(Obj[1]^, -2, 0, 2, 200, 0, True);
  end;
  for I := 1 to 50 do
  begin
    Dec(PB, 5);  Inc(PA, 20);  Inc(PC, 2);
    PhaseFrame(Obj[1]^, -3, 0, 0, 200, 0, True);
  end;
  for I := 1 to 50 do PhaseFrame(Obj[1]^, -3, 0, 0, 200, 0, True);

  BannerBeat;                          { 108b:15ca }
  Delay(300);
  BannerBeat;                          { 108b:1630 }
  Delay(300);
  BannerBeat;                          { 108b:1696 }

  for I := 1 to 12 do PhaseFrame(Obj[1]^, 12, 0, 0, 200, 1, True);
  SyncPattern(4, 1);
  for I := 1 to 12 do
  begin
    Inc(PB, 20);  Dec(PA, 80);  Dec(PC, 8);
    PhaseFrame(Obj[1]^, 12, 0, 0, 200, 1, True);
  end;
  for I := 1 to 12 do
  begin
    Dec(PB, 20);  Inc(PC, 8);
    PhaseFrame(Obj[1]^, 8, 0, -8, 200, 1, True);
  end;
  for I := 1 to  5 do PhaseFrame(Obj[1]^, 4, 0, -12, 200, 1, True);
  for I := 1 to 45 do PhaseFrame(Obj[1]^, 0, 0, -12, 200, 1, True);

  { 108b:1941 }
  PA := 0;  PB := 0;  PC := 0;
  SyncPattern(6, 1);
  GetPalette768(@Buf);
  PaletteFadeOut(10);
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);
  SetPalette768(@Buf);
  SetRGB($18, $1E, $1E, $1E);

  for I := 1 to 120 do
  begin
    Inc(PB, 10);  Dec(PA, 40);  Dec(PC, 8);
    PhaseFrame(Obj[2]^, -20, 0, 10, Rows, 2, False);
  end;

  { 108b:1a26 }
  PA := 270;  PB := 180;  PC := 180;
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);
  ObjTransform(Obj[3]^, PC, PA, PB);

  for I := 1 to 120 do
  begin
    Inc(PA, 10);  Inc(PB, 10);  Inc(PC, 10);
    PhaseFrame(Obj[3]^, 20, 0, 10, Rows, 2, False);
  end;

  { 108b:1af2 }
  SetRGB($20, $3F, $3F, $3F);
  PA := 0;  PB := 0;  PC := 0;
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);

  for I := 1 to 99 do
  begin
    { 108b:1b53 -- here the nudge comes AFTER the translate, not before }
    ObjTranslate(Obj[4]^, 0, 0, 10);
    Inc(PA, 37);  Inc(PB, 10);
    ObjTransform(Obj[4]^, PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, Rows, WritePage, 0);
    ObjSortFaces(Obj[4]^);
    RenderC(Obj[4]^);
  end;
end;

{ --------------------------------------------------------------------------
  108b:2454 -- Demo_Scene2

  NEUROSIS.DAT from $0007D9B2, in four reads:

      12,800   the 320 x 40 banner strip   -> the heap
       1,550   the 5 x 5 font, 62 glyphs   -> DS:$5448
         768   palette                      -> DS:$5148
       1,462   the 34 x 43 badge            -> DS:$8ED5

  with the mode set and the first two objects built between the second and
  third reads, exactly as below.
  -------------------------------------------------------------------------- }
procedure Scene2;
var
  F   : file;
  Vol : Byte;
begin
  New(Font);
  GetMem(Banner, SizeOf(TBanner));

  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Banner^, SizeOf(TBanner));
  BlockRead(F, Font^, SizeOf(TFont));

  MusicStart;                          { 108b:24be }
  Frame := 0;                          { 108b:24c3 }
  SetMode400;                          { 108b:24cb }
  BuildRowTable80;                     { 108b:24d0 }
  FlipPage(0);                         { 108b:24d5 }

  BlockRead(F, Pal, 768);
  Setup;                               { 108b:24f0 }
  BlockRead(F, Rewind, SizeOf(TRewind));
  Close(F);

  { 108b:2513 -- six fixed colours before the choreography }
  SetRGB(1, $3F, $3F, $3F);
  SetRGB(2, $1B, $1B, $1B);
  SetRGB(3, $27, $27, $27);
  SetRGB(4, $03, $33, $03);
  SetRGB(5, $0F, $27, $0F);
  SetRGB(6, $16, $16, $16);

  Choreography;                        { 108b:2561 }

  { 108b:2564 -- ramp the volume to zero, then stop }
  Vol := GetVolume;
  while GetVolume > 0 do
  begin
    SetVolume(GetVolume - 1);
    Delay(10);
  end;
  SyncPattern(1, 1);
  MusicStop;
  SetVolume(Vol);

  FreeMem(Banner, SizeOf(TBanner));
  Dispose(Font);
end;

begin
  { The two messages are Pascal strings in DGROUP at DS:$046E and DS:$056E. }
  Msg1 := 'CAPTAINS LOG, STARDATE 426987.2, SUPPLIMENTAL  :           ';
  Msg2 := '     PICTURE IT,   SICILY,   1942 ....               ';
end.
