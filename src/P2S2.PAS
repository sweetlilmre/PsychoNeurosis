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

  { The clip box moved to a TYPED constant block beside Tri_Fill, which
    is the only reader and reads it FROM MEMORY. }

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
  { Named so a renderer's local copy can be ASSIGNED from the field: an
    anonymous array type is not assignment-compatible with another. }
  TFaceArray = array[1..MaxFaces] of TFace;
  TVec3 = record X, Y, Z : LongInt end;   { +0, +4, +8 }
  TObj = record
    VertCount : Integer;                        { +$000 }
    FaceCount : Integer;                        { +$002 }
    Vert  : array[1..MaxVerts] of TVertex;      { +$004 }
    Scr   : array[1..MaxVerts] of TScreen;      { +$388 }
    Face  : TFaceArray;                         { +$54A }
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
  { FOUR FIXED DGROUP BLOCKS, and $B51 apart at $5A56, $65A7, $70F8 and
    $7C49 -- which is contiguous, so it is one array of four and not four
    separate variables. The reconstruction had them as heap pointers and
    New()'d them, so every call site loaded a far pointer out of a variable
    where the original has an immediate: 108b:1287 is `MOV DI, $5A56 /
    PUSH DS / PUSH DI`, and no pointer is read at all. }
  Obj    : array[1..4] of TObj;
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
  { DS:$A0C7 and DS:$A0C8 -- two BYTES, and they are GLOBALS, not locals of
    Scene2. The volume ramp at 108b:2564 stores every GetVolume result to a
    fixed address rather than to a stack slot, and they sit immediately before
    RowOfs, which is what puts them here in the var block. }
  SaveVol : Byte;
  CurVol  : Byte;
  { DS:$A0CA -- RowOfs80[I] = I * 80. }
  RowOfs : array[0..Rows - 1] of Word;
  { the snapshot Obj_SortFaces works from }
  FaceCopy : array[1..MaxFaces] of TFace;
  { Tri_Fill's per-scanline span buffer, DS:$A2AA, immediately after
    RowOfs -- which ends at $A2A9, 240 words from $A0CA. ONE
    INTERLEAVED array of (left, right) pairs, not two arrays: the
    walk stores a word and advances its byte index by 2 each time. }
  Span : array[0..2 * Rows + 1] of Integer;

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
procedure ObjTranslate(var O : TObj; DX, DY, DZ : LongInt);     { 108b:03be }
begin
  { ENTER $04 is FOUR BYTES OF FRAME AND NO DECLARED LOCAL, so the whole
    frame is one far-pointer temp: 108b:03c5 does `ADD DI, $B2D` once, spills
    the result to [BP-$04]/[BP-$02], and every access afterwards is
    es:[di], es:[di+4], es:[di+8] -- offsets 0, 4 and 8 from the Trans base
    rather than $B2D, $B31 and $B35 from @O. That is `with O.Trans`, and
    without it the compiler recomputes the address per statement and the
    frame is empty. probe/WITHTMP.PAS settled the general rule.

    DX, DY and DZ are LongInt because `RET $10` is sixteen bytes of
    parameters -- the far pointer plus three four-byte values, at [BP+$04],
    [BP+$08] and [BP+$0c]. Each is read as a single WORD and handed to
    IntToFixed, whose parameter is an Integer; Turbo Pascal's integer types
    are assignment-compatible so the compiler truncates, which is exactly the
    `PUSH WORD PTR [BP+$0c]` at 108b:03cf. }
  with O.Trans do
  begin
    { `X := X + e`, NOT `Inc(X, e)`, and this unit already had the rule
      written down for Obj_SetRotation without applying it here. The original
      loads the pair into AX:DX, adds, and stores back -- 108b:03da is
      `ADD AX, es:[DI]` / `ADC DX, es:[DI+2]` / `MOV es:[DI], AX` /
      `MOV es:[DI+2], DX` -- where Inc compiles to an in-place ADD/ADC on
      memory in two instructions. Same arithmetic, and it was the whole
      remaining 50-byte difference in this routine. }
    X := X + IntToFixed(DX);
    Y := Y + IntToFixed(DY);
    Z := Z + IntToFixed(DZ);
  end;
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
      { ON THE FIELDS, not on the parameters. 108b:024f is
        `PUSH WORD PTR ES:[DI]` and 108b:0262 is `ES:[DI+4]` -- the values the
        three lines above just stored, read back through the `with` temp. The
        values are identical either way, so this is shape and not behaviour;
        it was the last divergence in ObjTransform. }
      SinCos(X, MCos1, MSin1);
      SinCos(Y, MCos2, MSin2);
      SinCos(Z, MCos3, MSin3);
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
  { ENTER $1136 is 4,406 bytes and the seven scalars are the DEEPEST slots,
    so 4,392 bytes of aggregate are declared before them. 4,392 is
    2,897 + 1,495 exactly -- one whole TObj and one array[1..MaxFaces] of
    TFace -- and only the first of those is ever addressed.

    THE WHOLE OBJECT IS COPIED INTO THE FRAME. 108b:0e0c takes
    `LEA DI, [BP-$0B51]`, pushes $B51 and calls the runtime's Move, and every
    access afterwards is SS-relative off BP: `[BP+DI-$61E]` is
    Tmp.Face[F].Count, `[BP+DI-$609]` is its Depth at field offset $15, and
    `[BP+DI-$7CB]` is Tmp.Scr[Idx].D. Nothing in the body reads through the
    var parameter at all after the copy.

    That is worth more than the byte count. The reconstruction worked through
    the far `var` pointer for every read, which costs an ES: override and a
    segment load per access; the original pays one bulk copy and then uses
    near addressing throughout. It is a candidate mechanism for the pacing
    investigation -- ours slower wherever 3-D code runs -- and it is the
    opposite of what a bulk copy looks like from the outside. }
  Tmp     : TObj;                             { [BP-$0b51] }
  { 1,495 BYTES DECLARED AND NEVER ADDRESSED. The arithmetic does not close
    without them and no instruction in 108b:0e03..0f66 reaches that range.
    Transcribed for the same reason the dead scalars elsewhere in this unit
    are: it is what the author declared. }
  Unused  : array[1..MaxFaces] of TFace;      { [BP-$1128] }
  F       : Integer;                          { [BP-$112a], 17 references }
  K       : Integer;                          { [BP-$112c] }
  BestKey : Integer;                          { [BP-$112e] -- INTEGER, not LongInt }
  Best    : Integer;                          { [BP-$1130] }
  Slot    : Integer;                          { [BP-$1132] }
  { AND NOTHING BELOW SLOT. [BP-$1134] and [BP-$1136] are the CODE
    GENERATOR'S loop-bound temporaries, not declarations -- 108b:0e1a reads
    Tmp.FaceCount into [BP-$1134] and then compares against it, which is
    what a `for` limit that is not a constant costs. Declaring them produced
    both ours and the compiler's and put the frame over at $113c. The same
    mistake was made in all three renderers; see the note there. }
begin
  Tmp := O;                                   { 108b:0e15, Move of $B51 bytes }
  for F := 1 to Tmp.FaceCount do              { the limit temp is 108b:0e1a }
  begin
    { THE ACCUMULATOR IS THE DEPTH FIELD ITSELF and it is SIXTEEN BIT. The
      reconstruction summed into a LongInt and divided that; the original adds
      each vertex's D straight into Tmp.Face[F].Depth with a word ADD at
      108b:0e85 and stores it back each time. }
    Tmp.Face[F].Depth := 0;                   { 108b:0e3f }
    for K := 1 to Tmp.Face[F].Count do        { the limit temp is 108b:0e48 }
      Tmp.Face[F].Depth := Tmp.Face[F].Depth
                         + Tmp.Scr[Tmp.Face[F].Idx[K]].D;
    { AND THE DIVISOR IS THE FIELD, NOT C. 108b:0eab is
      `IDIV WORD PTR [BP+DI-$61E]`, a fresh read of Tmp.Face[F].Count, and
      there is NO ZERO GUARD -- the reconstruction had `if Count <> 0`, which
      the original does not. A face with no vertices would divide-error here
      in 1994 too, so the data never has one. }
    Tmp.Face[F].Depth := Tmp.Face[F].Depth div Tmp.Face[F].Count;
  end;

  Slot := 1;                                  { 108b:0ec5 }
  repeat
    BestKey := 0;                             { 108b:0ecb }
    Best    := 0;                             { 108b:0ed3 }
    for F := 1 to Tmp.FaceCount do            { re-read per pass, 108b:0ed7 }
      if Tmp.Face[F].Depth < BestKey then     { 108b:0eff, smallest key wins }
      begin
        BestKey := Tmp.Face[F].Depth;
        Best    := F;
      end;
    if Best > 0 then                          { 108b:0f20 }
    begin
      O.Face[Slot] := Tmp.Face[Best];         { 108b:0f44, Move of 23 bytes }
      Tmp.Face[Best].Depth := 0;
      Inc(Slot);
    end;
  until Best = 0;
end;

{ --------------------------------------------------------------------------
  108b:0461 -- Tri_Fill, and it is HAND-WRITTEN ASSEMBLER

  It had been transcribed as Pascal with a nested Edge procedure and a
  different algorithm, which is why all 1,276 bytes of 108b:0442..093e were
  the largest unaligned span anywhere. Four things say assembler, and no
  Borland Pascal code generator does any of them:

    108b:092b  PUSH BP  ...  MOV BP, $50 / SUB BP, CX  ...  POP BP
        BP used as a scratch register inside a framed routine. Every
        BP-relative operand in that stretch is read BEFORE the clobber.
    108b:0992  SHR CX,1 / REP STOSW / ADC CX,CX / REP STOSB
        the word-then-odd-byte fill inline. FillChar is a far call into the
        RTL and is never inlined.
    108b:05c5  MOV ES,BX / MOV BX,DX / MOV [BX+..],DI / MOV BX,ES
        a general-purpose value parked in a SEGMENT register so BX can be
        borrowed as an index. All eight registers are live here.
    the calling convention below -- four arguments in registers.

  And one MEASUREMENT, which is the one that does not rely on reading style.
  Of the 62 two-byte register-to-register ALU and MOV ops in this routine, 62
  use the store direction (`MOV AX,BX` as 89 D8) and NONE the load direction
  (8B C3). Every compiled-Pascal routine in this same segment is mixed --
  DrawText 56%, Obj_SortFaces 57%, Scene2_Setup 36%, Obj_SetRotation 27% --
  and so is DEMOMATH.OBJ at 30%, which TASM assembled. A 62-of-62 split is
  not a tendency, it is a tool that only ever emits one form.

  WHICH tool the rebuild then answered, and it is worth recording that the
  first reading of that measurement was WRONG. Because TASM came out mixed
  too, the inference drawn from it was that Tri_Fill's producer was neither
  the Pascal code generator nor TASM -- something foreign -- and that
  transcribing it through Borland's own assembler would therefore cost
  roughly 62 one-bit differences. Both halves of that were wrong. Borland's
  BASM emits the store direction consistently, so the split identifies BASM
  rather than excluding it, and the rebuild is byte-for-byte identical
  through all 64 bytes of the prologue and sort chain, `89 D8` and `89 D1`
  and `89 F2` included.

  WHAT THE REBUILD MEASURES, and it is the reason to believe the rest of this
  comment: 1,250 of 1,360 bytes identical, 91.9%, in 56 differing runs of
  which NONE is longer than two bytes and none is an opcode. Fifty-four are
  DGROUP addresses, which is what the coverage walk's default rule exists to
  forgive -- $066E against our clip box, $A2AA against our Span, $A0CA
  against RowOfs, $A69A against WritePage. The other two are single bytes at
  108b:04b6 and 108b:04ce, where a conditional has to bridge to a target too
  far for a short jump and BASM picks the opposite sense to the original's:
  ours is `JL` to a bridge that jumps to the flat-top walk, the original's is
  `JGE` to a bridge that jumps to the exit. The two are the same branch and
  the same behaviour. Poly_FillFan below rebuilds byte-identical, all 88.

  THE CALLING CONVENTION. Four arguments arrive in registers and three on
  the stack, and Poly_FillFan below is the only caller and cooperates:

      BX = X1   CX = Y1   DX = X2   SI = Y2
      [BP+$08] = X3   [BP+$06] = Y3   [BP+$04] = Colour     RET 6

  so only the last three can be declared. X1, Y1, X2 and Y2 are spilled to
  the first four locals immediately and then live in AX, BX, CX, DX.

  WHAT IT DOES. A scanline triangle filler. It sorts the three vertices by
  Y, computes each edge's step as a floor division -- quotient and remainder
  kept separately, with the `if numerator < 0 then Dec(quotient);
  Inc(remainder, denominator)` correction spelled out at 108b:0516 and
  five more places -- then walks two edges down the triangle writing an
  (XL, XR) pair per scanline into the buffer at DS:$A2AA, and finally fills
  the spans BACKWARDS from the last scanline through the Map Mask.

  There are FOUR walk variants, not one, and which runs is decided by shape:

      108b:0715   Y1 = Y2, a flat top
      108b:07fb   Y2 = Y3, a flat bottom
      108b:0595   the general case, third vertex on one side
      108b:0653   the general case, third vertex on the other

  and the two general ones are chosen by a 32-bit cross product at
  108b:0570 -- (X2-X1)*(Y3-Y1) against (X3-X1)*(Y2-Y1), high words compared
  signed and low words unsigned, with equality meaning degenerate and
  exiting. Each general variant is itself two loops: the first runs to Y2
  with the short edge, the second to Y3 with the third edge swapped in.

  Two instructions in the fill loop are DEAD in the original and are kept,
  for the same reason the dead declared locals are kept -- they are what the
  author wrote: `MOV SI, FillY` at 108b:0976 and the `MOV BP,$50 /
  SUB BP,CX / DEC BP` at 108b:097c, whose result is never read before
  POP BP restores it.
  -------------------------------------------------------------------------- }
const
  { DS:$066E..$067D, initialised data, and contiguous in exactly this order.
    TYPED constants, not plain ones: the code reads them FROM MEMORY
    (`CMP DI, [$066E]` at 108b:04eb), so a plain const would fold into the
    instruction as an immediate and the reads would vanish. Verified against
    the binary by pattern rather than by arithmetic -- the eight clip bytes
    00 00 EF 00 00 00 3F 01 occur ONCE in the file, at 0x90ce, which puts
    DGROUP's initialised data at 0x8a60, and MViewW/MViewH at DS:$046A and
    the mask pair at DS:$0676 both land where that base predicts. }
  ClipYMin : Integer = 0;
  ClipYMax : Integer = 239;
  ClipXMin : Integer = 0;
  ClipXMax : Integer = 319;
  { The same four values P2View's FillRect uses, but a SECOND COPY in this
    unit's own data -- P2View's pair is at DS:$0CF0/$0CF4. Tri_Fill reads
    these, at $0676 and $067A. }
  LeftMask4  : array[0..3] of Byte = ($0F, $0E, $0C, $08);
  RightMask4 : array[0..3] of Byte = ($0F, $01, $03, $07);

{ @asm 002 108b:0461 }
procedure TriFill(X3, Y3 : Integer; Colour : Byte); assembler;
var
  { Twenty Integers, 40 bytes, and ENTER $28 is the whole frame -- the slot
    walk finds nothing below [BP-$28], so there is no compiler temporary.
    First declared is nearest BP, so the order here IS the original's. }
  SX1, SY1, SX2, SY2 : Integer;     { [BP-$02]..[BP-$08], the sorted vertices }
  NumA, NumB, NumC   : Integer;     { [BP-$0A]..[BP-$0E], the three dividends }
  DenA, DenB, DenC   : Integer;     { [BP-$10]..[BP-$14], the three divisors  }
  RemA, RemB, RemC   : Integer;     { [BP-$16]..[BP-$1A], floored remainders  }
  StepA, StepB, StepC : Integer;    { [BP-$1C]..[BP-$20], floored quotients   }
  FillL, FillR       : Integer;     { [BP-$22], [BP-$24], the clipped span    }
  FillY              : Integer;     { [BP-$26], the scanline being filled     }
  SpanIdx            : Integer;     { [BP-$28], a BYTE index into Span        }
(* EQUIVALENT PASCAL -- REFERENCE ONLY, and it is NOT what is compiled. The
  assembler below is the transcription; this says what it means, so that a
  reader can follow the four walk variants without holding the register
  allocation in their head. It is deliberately not a working procedure: the
  four register arguments cannot be expressed, and the two dead instructions
  and the clip-clamped loop bounds are elided here but present below.

    procedure TriFill(X1, Y1, X2, Y2, X3, Y3 : Integer; Colour : Byte);
    var Step, Rem, Den : array['A'..'C'] of Integer;
        L, R, EL, ER, Y, Idx : Integer;

      procedure Edge(var Step, Rem, Den : Integer; DX, DY : Integer);
      begin                             { one edge's floored DDA setup      }
        Den  := DY;
        Step := DX div DY;              { truncated ...                     }
        Rem  := DX mod DY;
        if DX < 0 then                  { ... then floored, by hand         }
        begin Dec(Step); Inc(Rem, Den) end;
      end;

      procedure Walk(var AL, AR : Integer; SL, SR : Char);
      begin                             { one scanline of both edges        }
        if Y >= ClipYMin then
        begin
          Span[Idx] := AL; Span[Idx + 1] := AR; Inc(Idx, 2);
        end;
        Inc(EL, Rem[SL]);
        if EL > 0 then begin Dec(EL, Den[SL]); Inc(AL) end;
        Inc(AL, Step[SL]);
        Inc(ER, Rem[SR]);
        if ER > 0 then begin Dec(ER, Den[SR]); Inc(AR) end;
        Inc(AR, Step[SR]);
        Inc(Y);
      end;

    begin
      if (X1 = X2) and (X2 = X3) then Exit;
      SortThreeByY(X1, Y1, X2, Y2, X3, Y3);
      if (Y1 = Y2) and (Y2 = Y3) then Exit;
      if Y3 < ClipYMin then Exit;
      if Y1 > ClipYMax then Exit;

      Edge(Step['A'], Rem['A'], Den['A'], X2 - X1, Y2 - Y1);
      Edge(Step['B'], Rem['B'], Den['B'], X3 - X1, Y3 - Y1);
      if Y3 - Y2 > 0 then
        Edge(Step['C'], Rem['C'], Den['C'], X3 - X2, Y3 - Y2);

      { which side the middle vertex falls on, as a 32-bit cross product }
      if LongInt(X2 - X1) * (Y3 - Y1) = LongInt(X3 - X1) * (Y2 - Y1) then
        Exit;                           { collinear                         }
      if LongInt(X2 - X1) * (Y3 - Y1) > LongInt(X3 - X1) * (Y2 - Y1) then
      begin                             { 108b:0595 -- A then C on the right }
        L := X1; R := X1; Y := Y1; Idx := 0; EL := 0; ER := 0;
        while Y < Y2 do Walk(L, R, 'B', 'A');
        while Y < Y3 do Walk(L, R, 'B', 'C');
      end
      else
      begin                             { 108b:0653 -- A then C on the left  }
        L := X1; R := X1; Y := Y1; Idx := 0; EL := 0; ER := 0;
        while Y < Y2 do Walk(L, R, 'A', 'B');
        while Y < Y3 do Walk(L, R, 'C', 'B');
      end;
      { and 108b:0715 / 108b:07fb are the Y1=Y2 and Y2=Y3 cases, which need
        only one loop each and start L and R on the two ends of the flat edge }

      for Y := Y3 downto Y1 + 1 do      { 108b:08dd -- BACKWARDS            }
      begin
        Dec(Idx, 2);
        R := Span[Idx + 1];  if R > ClipXMax then R := ClipXMax;
        L := Span[Idx];      if L < ClipXMin then L := ClipXMin;
        if (Y < ClipYMin) or (Y > ClipYMax) then Continue;
        D    := RowOfs[Y] + (L shr 2) + WritePage;
        Mid  := ((R - 1) - (L and $FFFC)) shr 2;
        LM   := LeftMask4[L and 3];
        RM   := RightMask4[R and 3];
        if R <= L then Continue;
        if Mid = 0 then LM := LM and RM;
        Port[$3C4] := 2;
        Port[$3C5] := LM;  Mem[$A000 : D] := Colour;
        if Mid > 0 then
        begin
          if Mid > 1 then
          begin
            Port[$3C5] := $0F;
            FillChar(Mem[$A000 : D + 1], Mid - 1, Colour);
          end;
          Port[$3C5] := RM;  Mem[$A000 : D + Mid] := Colour;
        end;
      end;
    end;
    EQUIVALENT PASCAL ends here -- REFERENCE ONLY, none of it compiled  *)
asm
  { ---- 108b:0465 spill the four register arguments, keeping a copy ------- }
  MOV  SX1, BX            { SX1 := X1                                       }
  MOV  AX, BX             { AX now carries X1                               }
  MOV  SY1, CX            { SY1 := Y1                                       }
  MOV  BX, CX             { BX now carries Y1                               }
  MOV  SX2, DX            { SX2 := X2                                       }
  MOV  CX, DX             { CX now carries X2                               }
  MOV  SY2, SI            { SY2 := Y2                                       }
  MOV  DX, SI             { DX now carries Y2                               }
                          { from here AX=X1 BX=Y1 CX=X2 DX=Y2               }
  { ---- 108b:0479 degenerate: all three X equal is a zero-width sliver ---- }
  CMP  AX, CX             { X1 against X2                                   }
  JNE  @@SortY            { differ -- not that degeneracy                   }
  CMP  CX, X3             { X2 against X3                                   }
  JNE  @@SortY            { differ                                          }
  JMP  @@Done             { X1 = X2 = X3, nothing to fill                   }

  { ---- 108b:0485 sort the three vertices by Y, three compare-and-swap ---- }
@@SortY:                  { <- SortY                                      }
  CMP  BX, DX             { Y1 against Y2                                   }
  JG   @@Swap12           { out of order                                    }
  JMP  @@Test23           { in order                                        }
@@Swap12:                 { <- Swap12                                     }
  XCHG CX, AX             { swap X1 and X2                                  }
  XCHG BX, DX             { swap Y1 and Y2                                  }
@@Test23:                 { <- Test23                                     }
  CMP  DX, Y3             { Y2 against Y3                                   }
  JG   @@Swap23           { out of order                                    }
  JMP  @@Flat1            { in order -- the sort is finished                }
@@Swap23:                 { <- Swap23                                     }
  XCHG X3, CX             { swap X2 and X3, X3 being on the stack           }
  XCHG Y3, DX             { swap Y2 and Y3                                  }
  CMP  BX, DX             { Y1 against the new Y2                           }
  JG   @@Swap12b          { out of order again                              }
  JMP  @@Flat1            { sorted                                          }
@@Swap12b:                { <- Swap12b                                    }
  XCHG CX, AX             { swap X1 and X2                                  }
  XCHG BX, DX             { swap Y1 and Y2                                  }

  { ---- 108b:04a4 pick the variant: flat top, flat bottom, or general ----- }
@@Flat1:                  { <- Flat1                                      }
  CMP  BX, DX             { Y1 = Y2 ?                                       }
  JE   @@IsFlatTop        { yes -- the flat-top walk                        }
  JMP  @@Flat2            { no                                              }
@@IsFlatTop:              { <- IsFlatTop                                  }
  CMP  DX, Y3             { Y2 = Y3 as well ?                               }
  JNE  @@FlatTopOrder     { no -- a real flat top                           }
  JMP  @@Done             { all three Y equal, nothing to fill              }
@@FlatTopOrder:           { <- FlatTopOrder                               }
  CMP  AX, CX             { X1 against X2, the flat edge                    }
  JG   @@FlatTopSwap      { X1 > X2, swap so X1 is the left end             }
  JGE  @@Done             { equal -- zero-width, nothing to fill            }
  JMP  @@FlatTop          { already left-to-right                           }
@@FlatTopSwap:            { <- FlatTopSwap                                }
  XCHG CX, AX             { swap X1 and X2                                  }
  JMP  @@FlatTop          { to FlatTop                                    }

@@Flat2:                  { <- Flat2                                      }
  CMP  DX, Y3             { Y2 = Y3 ?                                       }
  JE   @@IsFlatBot        { yes -- the flat-bottom walk                     }
  JMP  @@General          { no -- the general case                          }
@@IsFlatBot:              { <- IsFlatBot                                  }
  CMP  CX, X3             { X2 against X3, the flat edge                    }
  JG   @@FlatBotSwap      { X2 > X3, swap so X2 is the left end             }
  JGE  @@Done             { equal -- zero-width                             }
  JMP  @@FlatBot          { already left-to-right                           }
@@FlatBotSwap:            { <- FlatBotSwap                                }
  XCHG X3, CX             { swap X2 and X3                                  }
  JMP  @@FlatBot          { to FlatBot                                    }

  { ======== 108b:04dc THE GENERAL CASE ==================================== }
@@General:                { <- General                                    }
  MOV  SX1, AX            { re-spill, the sort moved them                   }
  MOV  SY1, BX            { SY1 := BX                                     }
  MOV  SX2, CX            { SX2 := CX                                     }
  MOV  SY2, DX            { SY2 := DX                                     }
  MOV  DI, Y3             { the bottom vertex                               }
  CMP  DI, ClipYMin       { entirely above the clip box ?                   }
  JGE  @@GenInBox         { >= : to GenInBox                              }
  JMP  @@Done             { to Done                                       }
@@GenInBox:               { <- GenInBox                                   }
  MOV  DI, SY1            { the top vertex                                  }
  CMP  DI, ClipYMax       { entirely below the clip box ?                   }
  JLE  @@GenEdges         { <= : to GenEdges                              }
  JMP  @@Done             { to Done                                       }

  { ---- 108b:0500 edge A, vertex 1 to vertex 2 --------------------------- }
@@GenEdges:               { <- GenEdges                                   }
  MOV  BX, DX             { Y2                                              }
  SUB  BX, SY1            { DenA := Y2 - Y1                                 }
  MOV  DenA, BX           { DenA := BX                                    }
  MOV  AX, SX2            { AX := SX2                                     }
  SUB  AX, SX1            { NumA := X2 - X1                                 }
  MOV  NumA, AX           { NumA := AX                                    }
  MOV  CX, AX             { keep the numerator's sign                       }
  CWD                     { sign-extend AX into DX:AX                       }
  IDIV BX                 { AX := quotient, DX := remainder, both truncated }
  CMP  CX, 0              { was the numerator negative ?                    }
  JGE  @@GenAOk           { no -- truncation was already floor              }
  DEC  AX                 { floor the quotient                              }
  ADD  DX, BX             { and bring the remainder back positive           }
@@GenAOk:                 { <- GenAOk                                     }
  MOV  StepA, AX          { StepA := AX                                   }
  MOV  RemA, DX           { RemA := DX                                    }

  { ---- 108b:0524 edge B, vertex 1 to vertex 3, the long edge ------------ }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY1            { DenB := Y3 - Y1                                 }
  MOV  DenB, BX           { DenB := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX1            { NumB := X3 - X1                                 }
  MOV  NumB, AX           { NumB := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@GenBOk           { >= : to GenBOk                                }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@GenBOk:                 { <- GenBOk                                     }
  MOV  StepB, AX          { StepB := AX                                   }
  MOV  RemB, DX           { RemB := DX                                    }

  { ---- 108b:0549 edge C, vertex 2 to vertex 3, skipped when flat -------- }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY2            { Y3 - Y2                                         }
  JLE  @@GenCross         { not positive -- edge C is never walked          }
  MOV  DenC, BX           { DenC := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX2            { NumC := X3 - X2                                 }
  MOV  NumC, AX           { NumC := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@GenCOk           { >= : to GenCOk                                }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@GenCOk:                 { <- GenCOk                                     }
  MOV  StepC, AX          { StepC := AX                                   }
  MOV  RemC, DX           { RemC := DX                                    }

  { ---- 108b:0570 the winding test, 32-bit, decides which side is which -- }
@@GenCross:               { <- GenCross                                   }
  MOV  AX, NumA           { X2 - X1                                         }
  IMUL DenB               { * (Y3 - Y1), signed, into DX:AX                 }
  MOV  BX, AX             { park the low word                               }
  MOV  CX, DX             { park the high word                              }
  MOV  AX, NumB           { X3 - X1                                         }
  IMUL DenA               { * (Y2 - Y1), into DX:AX                         }
  CMP  CX, DX             { high words, SIGNED                              }
  JG   @@WalkAC           { first product is the greater                    }
  JGE  @@CrossLow         { equal -- the low words decide                   }
  JMP  @@WalkBB           { to WalkBB                                     }
@@CrossLow:               { <- CrossLow                                   }
  CMP  BX, AX             { low words, UNSIGNED, as a 32-bit compare needs  }
  JA   @@WalkAC           { above, unsigned : to WalkAC                   }
  JAE  @@GenDegenerate    { both products equal -- the three are collinear  }
  JMP  @@WalkBB           { to WalkBB                                     }
@@GenDegenerate:          { <- GenDegenerate                              }
  JMP  @@Done             { to Done                                       }

  { ======== 108b:0595 general walk, edges A then C on the RIGHT ==========
    DI is the left X and steps edge B; SI is the right X and steps edge A,
    then edge C once Y passes Y2. AX is DI's error, BX is SI's error, CX is
    the scanline, DX is the byte index into Span. -------------------------- }
@@WalkAC:                 { <- WalkAC                                     }
  MOV  AX, 0              { DI's error accumulator                          }
  MOV  BX, 0              { SI's error accumulator                          }
  MOV  CX, SY1            { start at the top vertex                         }
  MOV  DI, SX1            { both edges start at X1                          }
  MOV  SI, DI             { SI := DI                                      }
  XOR  DX, DX             { Span is written from the beginning              }
  CMP  CX, ClipYMin       { does the walk start above the clip box ?        }
  JGE  @@AC1              { >= : to AC1                                   }
  MOV  DX, ClipYMin       { it does -- the first STORED scanline is the top }
  MOV  SY1, DX            { of the box, and SY1 is where the fill will stop }
  MOV  DX, SY1            { DX := SY1                                     }
  CMP  DX, Y3             { is the whole triangle above the box ?           }
  JNE  @@AC1a             { <> : to AC1a                                  }
  JMP  @@Done             { to Done                                       }
@@AC1a:                   { <- AC1a                                       }
  XOR  DX, DX             { DX := 0                                       }
@@AC1:                    { <- AC1                                        }
  CMP  CX, ClipYMin       { above the box -- step the edges but store nothing }
  JL   @@AC1Step          { < : to AC1Step                                }
  MOV  ES, BX             { park SI's error so BX can index Span            }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI      { the left end                           }
  MOV  BX, ES             { unpark                                          }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI      { the right end                          }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@AC1Step:                { <- AC1Step                                    }
  ADD  AX, RemB           { DI's error += edge B's remainder                }
  JLE  @@AC1StepDI        { <= : to AC1StepDI                             }
  SUB  AX, DenB           { crossed -- pull it back                         }
  INC  DI                 { and take the extra pixel                        }
@@AC1StepDI:              { <- AC1StepDI                                  }
  ADD  DI, StepB          { DI := DI + StepB                              }
  ADD  BX, RemA           { SI's error += edge A's remainder                }
  JLE  @@AC1StepSI        { <= : to AC1StepSI                             }
  SUB  BX, DenA           { BX := BX - DenA                               }
  INC  SI                 { SI := SI + 1                                  }
@@AC1StepSI:              { <- AC1StepSI                                  }
  ADD  SI, StepA          { SI := SI + StepA                              }
  INC  CX                 { next scanline                                   }
  CMP  CX, ClipYMax       { off the bottom of the box ?                     }
  JL   @@AC1More          { < : to AC1More                                }
  MOV  Y3, CX             { yes -- the fill starts here instead of at Y3    }
  JMP  @@Fill             { to Fill                                       }
@@AC1More:                { <- AC1More                                    }
  CMP  CX, SY2            { still in the first half ?                       }
  JL   @@AC1              { < : to AC1                                    }
  { ---- 108b:0609 second half: SI switches from edge A to edge C --------- }
@@AC2:                    { <- AC2                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@AC2Step          { < : to AC2Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@AC2Step:                { <- AC2Step                                    }
  ADD  AX, RemB           { AX := AX + RemB                               }
  JLE  @@AC2StepDI        { <= : to AC2StepDI                             }
  SUB  AX, DenB           { AX := AX - DenB                               }
  INC  DI                 { DI := DI + 1                                  }
@@AC2StepDI:              { <- AC2StepDI                                  }
  ADD  DI, StepB          { DI := DI + StepB                              }
  ADD  BX, RemC           { edge C now                                      }
  JLE  @@AC2StepSI        { <= : to AC2StepSI                             }
  SUB  BX, DenC           { BX := BX - DenC                               }
  INC  SI                 { SI := SI + 1                                  }
@@AC2StepSI:              { <- AC2StepSI                                  }
  ADD  SI, StepC          { SI := SI + StepC                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@AC2More          { < : to AC2More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
@@AC2More:                { <- AC2More                                    }
  CMP  CX, Y3             { compare CX with Y3                            }
  JL   @@AC2              { < : to AC2                                    }
  JMP  @@Fill             { to Fill                                       }

  { ======== 108b:0653 general walk, edges A then C on the LEFT ===========
    The mirror of the above: DI steps edge A then edge C, SI steps edge B
    the whole way down. ---------------------------------------------------- }
@@WalkBB:                 { <- WalkBB                                     }
  MOV  AX, 0              { AX := 0                                       }
  MOV  BX, 0              { BX := 0                                       }
  MOV  CX, SY1            { CX := SY1                                     }
  MOV  DI, SX1            { DI := SX1                                     }
  MOV  SI, SX1            { SI := SX1                                     }
  XOR  DX, DX             { DX := 0                                       }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JGE  @@BB1              { >= : to BB1                                   }
  MOV  DX, ClipYMin       { DX := ClipYMin                                }
  MOV  SY1, DX            { SY1 := DX                                     }
  MOV  DX, SY1            { DX := SY1                                     }
  CMP  DX, Y3             { compare DX with Y3                            }
  JNE  @@BB1a             { <> : to BB1a                                  }
  JMP  @@Done             { to Done                                       }
@@BB1a:                   { <- BB1a                                       }
  XOR  DX, DX             { DX := 0                                       }
@@BB1:                    { <- BB1                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@BB1Step          { < : to BB1Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@BB1Step:                { <- BB1Step                                    }
  ADD  AX, RemA           { DI takes edge A here                            }
  JLE  @@BB1StepDI        { <= : to BB1StepDI                             }
  SUB  AX, DenA           { AX := AX - DenA                               }
  INC  DI                 { DI := DI + 1                                  }
@@BB1StepDI:              { <- BB1StepDI                                  }
  ADD  DI, StepA          { DI := DI + StepA                              }
  ADD  BX, RemB           { SI takes the long edge B                        }
  JLE  @@BB1StepSI        { <= : to BB1StepSI                             }
  SUB  BX, DenB           { BX := BX - DenB                               }
  INC  SI                 { SI := SI + 1                                  }
@@BB1StepSI:              { <- BB1StepSI                                  }
  ADD  SI, StepB          { SI := SI + StepB                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@BB1More          { < : to BB1More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
  JMP  @@Fill             { to Fill                                       }
@@BB1More:                { <- BB1More                                    }
  CMP  CX, SY2            { compare CX with SY2                           }
  JL   @@BB1              { < : to BB1                                    }
  { ---- 108b:06c8 second half: DI switches from edge A to edge C --------- }
@@BB2:                    { <- BB2                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@BB2Step          { < : to BB2Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@BB2Step:                { <- BB2Step                                    }
  ADD  AX, RemC           { AX := AX + RemC                               }
  JLE  @@BB2StepDI        { <= : to BB2StepDI                             }
  SUB  AX, DenC           { AX := AX - DenC                               }
  INC  DI                 { DI := DI + 1                                  }
@@BB2StepDI:              { <- BB2StepDI                                  }
  ADD  DI, StepC          { DI := DI + StepC                              }
  ADD  BX, RemB           { BX := BX + RemB                               }
  JLE  @@BB2StepSI        { <= : to BB2StepSI                             }
  SUB  BX, DenB           { BX := BX - DenB                               }
  INC  SI                 { SI := SI + 1                                  }
@@BB2StepSI:              { <- BB2StepSI                                  }
  ADD  SI, StepB          { SI := SI + StepB                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@BB2More          { < : to BB2More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
  JMP  @@Fill             { to Fill                                       }
@@BB2More:                { <- BB2More                                    }
  CMP  CX, Y3             { compare CX with Y3                            }
  JL   @@BB2              { < : to BB2                                    }
  JMP  @@Fill             { to Fill                                       }

  { ======== 108b:0715 flat top: Y1 = Y2, so two edges leave the top ====== }
@@FlatTop:                { <- FlatTop                                    }
  MOV  SX1, AX            { SX1 := AX                                     }
  MOV  SY1, BX            { SY1 := BX                                     }
  MOV  SX2, CX            { SX2 := CX                                     }
  MOV  SY2, DX            { SY2 := DX                                     }
  MOV  DI, Y3             { DI := Y3                                      }
  CMP  DI, ClipYMin       { compare DI with ClipYMin                      }
  JGE  @@FTInBox          { >= : to FTInBox                               }
  JMP  @@Done             { to Done                                       }
@@FTInBox:                { <- FTInBox                                    }
  MOV  DI, SY1            { DI := SY1                                     }
  CMP  DI, ClipYMax       { compare DI with ClipYMax                      }
  JLE  @@FTEdges          { <= : to FTEdges                               }
  JMP  @@Done             { to Done                                       }
@@FTEdges:                { <- FTEdges                                    }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY1            { DenA := Y3 - Y1                                 }
  MOV  DenA, BX           { DenA := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX1            { NumA := X3 - X1, the left edge                   }
  MOV  NumA, AX           { NumA := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@FTAOk            { >= : to FTAOk                                 }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@FTAOk:                  { <- FTAOk                                      }
  MOV  StepA, AX          { StepA := AX                                   }
  MOV  RemA, DX           { RemA := DX                                    }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY2            { DenB := Y3 - Y2                                 }
  MOV  DenB, BX           { DenB := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX2            { NumB := X3 - X2, the right edge                 }
  MOV  NumB, AX           { NumB := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@FTBOk            { >= : to FTBOk                                 }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@FTBOk:                  { <- FTBOk                                      }
  MOV  StepB, AX          { StepB := AX                                   }
  MOV  RemB, DX           { RemB := DX                                    }
  MOV  AX, 0              { AX := 0                                       }
  MOV  BX, 0              { BX := 0                                       }
  MOV  CX, SY1            { CX := SY1                                     }
  MOV  DI, SX1            { the left end starts at X1                       }
  MOV  SI, SX2            { the right end at X2 -- the flat edge            }
  XOR  DX, DX             { DX := 0                                       }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JGE  @@FT1              { >= : to FT1                                   }
  MOV  DX, ClipYMin       { DX := ClipYMin                                }
  MOV  SY1, DX            { SY1 := DX                                     }
  MOV  DX, SY1            { DX := SY1                                     }
  CMP  DX, Y3             { compare DX with Y3                            }
  JNE  @@FT1a             { <> : to FT1a                                  }
  JMP  @@Done             { to Done                                       }
@@FT1a:                   { <- FT1a                                       }
  XOR  DX, DX             { DX := 0                                       }
@@FT1:                    { <- FT1                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@FT1Step          { < : to FT1Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@FT1Step:                { <- FT1Step                                    }
  ADD  AX, RemA           { AX := AX + RemA                               }
  JLE  @@FT1StepDI        { <= : to FT1StepDI                             }
  SUB  AX, DenA           { AX := AX - DenA                               }
  INC  DI                 { DI := DI + 1                                  }
@@FT1StepDI:              { <- FT1StepDI                                  }
  ADD  DI, StepA          { DI := DI + StepA                              }
  ADD  BX, RemB           { BX := BX + RemB                               }
  JLE  @@FT1StepSI        { <= : to FT1StepSI                             }
  SUB  BX, DenB           { BX := BX - DenB                               }
  INC  SI                 { SI := SI + 1                                  }
@@FT1StepSI:              { <- FT1StepSI                                  }
  ADD  SI, StepB          { SI := SI + StepB                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@FT1More          { < : to FT1More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
  JMP  @@Fill             { to Fill                                       }
@@FT1More:                { <- FT1More                                    }
  CMP  CX, Y3             { compare CX with Y3                            }
  JL   @@FT1              { < : to FT1                                    }
  JMP  @@Fill             { to Fill                                       }

  { ======== 108b:07fb flat bottom: Y2 = Y3, two edges meet at the top ==== }
@@FlatBot:                { <- FlatBot                                    }
  MOV  SX1, AX            { SX1 := AX                                     }
  MOV  SY1, BX            { SY1 := BX                                     }
  MOV  SX2, CX            { SX2 := CX                                     }
  MOV  SY2, DX            { SY2 := DX                                     }
  MOV  DI, Y3             { DI := Y3                                      }
  CMP  DI, ClipYMin       { compare DI with ClipYMin                      }
  JGE  @@FBInBox          { >= : to FBInBox                               }
  JMP  @@Done             { to Done                                       }
@@FBInBox:                { <- FBInBox                                    }
  MOV  DI, SY1            { DI := SY1                                     }
  CMP  DI, ClipYMax       { compare DI with ClipYMax                      }
  JLE  @@FBEdges          { <= : to FBEdges                               }
  JMP  @@Done             { to Done                                       }
@@FBEdges:                { <- FBEdges                                    }
  MOV  BX, SY2            { BX := SY2                                     }
  SUB  BX, SY1            { DenA := Y2 - Y1                                 }
  MOV  DenA, BX           { DenA := BX                                    }
  MOV  AX, SX2            { AX := SX2                                     }
  SUB  AX, SX1            { NumA := X2 - X1, the left edge                  }
  MOV  NumA, AX           { NumA := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@FBAOk            { >= : to FBAOk                                 }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@FBAOk:                  { <- FBAOk                                      }
  MOV  StepA, AX          { StepA := AX                                   }
  MOV  RemA, DX           { RemA := DX                                    }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY1            { DenB := Y3 - Y1                                 }
  MOV  DenB, BX           { DenB := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX1            { NumB := X3 - X1, the right edge                 }
  MOV  NumB, AX           { NumB := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@FBBOk            { >= : to FBBOk                                 }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@FBBOk:                  { <- FBBOk                                      }
  MOV  StepB, AX          { StepB := AX                                   }
  MOV  RemB, DX           { RemB := DX                                    }
  MOV  AX, 0              { AX := 0                                       }
  MOV  BX, 0              { BX := 0                                       }
  MOV  CX, SY1            { CX := SY1                                     }
  MOV  DI, SX1            { both edges leave the same apex                  }
  MOV  SI, SX1            { SI := SX1                                     }
  XOR  DX, DX             { DX := 0                                       }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JGE  @@FB1              { >= : to FB1                                   }
  MOV  DX, ClipYMin       { DX := ClipYMin                                }
  MOV  SY1, DX            { SY1 := DX                                     }
  MOV  DX, SY1            { DX := SY1                                     }
  CMP  DX, Y3             { compare DX with Y3                            }
  JNE  @@FB1a             { <> : to FB1a                                  }
  JMP  @@Done             { to Done                                       }
@@FB1a:                   { <- FB1a                                       }
  XOR  DX, DX             { DX := 0                                       }
@@FB1:                    { <- FB1                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@FB1Step          { < : to FB1Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@FB1Step:                { <- FB1Step                                    }
  ADD  AX, RemA           { AX := AX + RemA                               }
  JLE  @@FB1StepDI        { <= : to FB1StepDI                             }
  SUB  AX, DenA           { AX := AX - DenA                               }
  INC  DI                 { DI := DI + 1                                  }
@@FB1StepDI:              { <- FB1StepDI                                  }
  ADD  DI, StepA          { DI := DI + StepA                              }
  ADD  BX, RemB           { BX := BX + RemB                               }
  JLE  @@FB1StepSI        { <= : to FB1StepSI                             }
  SUB  BX, DenB           { BX := BX - DenB                               }
  INC  SI                 { SI := SI + 1                                  }
@@FB1StepSI:              { <- FB1StepSI                                  }
  ADD  SI, StepB          { SI := SI + StepB                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@FB1More          { < : to FB1More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
  JMP  @@Fill             { to Fill                                       }
@@FB1More:                { <- FB1More                                    }
  CMP  CX, Y3             { compare CX with Y3                            }
  JL   @@FB1              { < : to FB1                                    }

  { ======== 108b:08dd fill the collected spans, LAST scanline first ======
    DX still holds one past the last word written, so the walk backwards is
    free. Direction matters to the bytes even though it cannot matter to a
    solid fill, so it is kept. -------------------------------------------- }
@@Fill:                   { <- Fill                                       }
  CLD                     { STOSB/STOSW forwards within a span              }
  MOV  CX, Y3             { the last scanline the walk actually stored      }
  MOV  AX, $A000          { AX := $A000                                   }
  MOV  ES, AX             { ES:DI addresses video memory from here          }
  SUB  DX, 2              { step back onto the last word                    }
  MOV  SpanIdx, DX        { SpanIdx := DX                                 }
@@FillRow:                { <- FillRow                                    }
  MOV  FillY, CX          { FillY := CX                                   }
  MOV  BX, SpanIdx        { BX := SpanIdx                                 }
  MOV  DX, [BX + OFFSET Span]      { the right end                          }
  CMP  DX, ClipXMax       { compare DX with ClipXMax                      }
  JLE  @@FillRIn          { <= : to FillRIn                               }
  MOV  DX, ClipXMax       { clip right                                      }
@@FillRIn:                { <- FillRIn                                    }
  MOV  FillR, DX          { FillR := DX                                   }
  SUB  SpanIdx, 2         { SpanIdx := SpanIdx - 2                        }
  MOV  BX, SpanIdx        { BX := SpanIdx                                 }
  MOV  DX, [BX + OFFSET Span]      { the left end                           }
  CMP  DX, ClipXMin       { compare DX with ClipXMin                      }
  JGE  @@FillLIn          { >= : to FillLIn                               }
  MOV  DX, ClipXMin       { clip left                                       }
@@FillLIn:                { <- FillLIn                                    }
  MOV  FillL, DX          { FillL := DX                                   }
  SUB  SpanIdx, 2         { SpanIdx := SpanIdx - 2                        }
  CMP  CX, ClipYMin       { the scanline itself may be outside the box      }
  JL   @@FillNext         { < : to FillNext                               }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JG   @@FillNext         { > : to FillNext                               }
  PUSH BP                 { BP becomes a scratch register below             }
  MOV  BX, CX             { BX := CX                                      }
  ADD  BX, BX             { Y * 2, a word index                             }
  MOV  DI, [BX + OFFSET RowOfs]    { DI := RowOfs[Y], the 80-byte row table }
  MOV  BX, FillL          { BX := FillL                                   }
  SHR  BX, 2              { X div 4 -- four pixels to the byte in Mode X    }
  ADD  DI, BX             { DI := DI + BX                                 }
  ADD  DI, WritePage      { and the page being drawn on                     }
  MOV  DX, $3C4           { Sequencer address register                      }
  MOV  AL, 2              { register 2 -- Map Mask                          }
  OUT  DX, AL             { write AL to port DX                           }
  INC  DX                 { DX now addresses the data register              }
  MOV  SI, FillL          { SI := FillL                                   }
  AND  SI, 3              { the left end's plane                            }
  MOV  BH, [SI + OFFSET LeftMask4]     { both masks packed into one register }
  MOV  SI, FillR          { SI := FillR                                   }
  AND  SI, 3              { the right end's plane                           }
  MOV  BL, [SI + OFFSET RightMask4] { BL := [SI + OFFSET RightMask4]                }
  MOV  CX, FillR          { CX := FillR                                   }
  MOV  SI, FillL          { SI := FillL                                   }
  CMP  CX, SI             { empty or inverted span ?                        }
  JLE  @@FillPop          { <= : to FillPop                               }
  DEC  CX                 { the last pixel is exclusive                     }
  AND  SI, $FFFC          { back to the byte the left end sits in           }
  SUB  CX, SI             { CX := CX - SI                                 }
  SHR  CX, 1              { CX := CX shr 1                                }
  SHR  CX, 1              { CX := how many whole bytes past the first       }
  JNE  @@FillWide         { <> : to FillWide                              }
  AND  BH, BL             { one byte only -- both masks apply to it         }
@@FillWide:               { <- FillWide                                   }
  MOV  SI, FillY          { DEAD in the original: SI is never read again    }
  MOV  AH, Colour         { AH carries the colour for every store below     }
  MOV  BP, $50            { DEAD in the original: 80, the row stride, minus }
  SUB  BP, CX             { the byte count, less one -- and never read      }
  DEC  BP                 { before POP BP puts the frame pointer back       }
  MOV  AL, BH             { the left mask                                   }
  OUT  DX, AL             { write AL to port DX                           }
  MOV  AL, AH             { AL := AH                                      }
  STOSB                   { the first, partly-masked byte                   }
  DEC  CX                 { CX := CX - 1                                  }
  JS   @@FillPop          { that was the whole span                         }
  JE   @@FillRight        { nothing in the middle                          }
  MOV  AL, $0F            { all four planes for the middle                  }
  OUT  DX, AL             { write AL to port DX                           }
  MOV  AL, AH             { AL := AH                                      }
  SHR  CX, 1              { bytes to words                                  }
  REP  STOSW              { fill CX words with AX                         }
  ADC  CX, CX             { the carry out of SHR is the odd byte            }
  REP  STOSB              { fill CX bytes with AL                         }
@@FillRight:              { <- FillRight                                  }
  MOV  AL, BL             { the right mask                                  }
  OUT  DX, AL             { write AL to port DX                           }
  MOV  AL, AH             { AL := AH                                      }
  STOSB                   { the last, partly-masked byte                    }
@@FillPop:                { <- FillPop                                    }
  POP  BP                 { the frame pointer is a frame pointer again      }
@@FillNext:               { <- FillNext                                   }
  MOV  CX, FillY          { CX := FillY                                   }
  DEC  CX                 { upwards, one scanline at a time                 }
  CMP  CX, SY1            { back at the top vertex ?                        }
  JLE  @@Done             { <= : to Done                                  }
  JMP  @@FillRow          { to FillRow                                    }
@@Done:                   { <- Done                                       }
end;

{ --------------------------------------------------------------------------
  108b:09b1 -- Poly_FillFan(Pts, Count, Colour, Page), ALSO assembler

  It is the only caller of Tri_Fill and it cooperates with that private
  register interface -- BX, CX, DX and SI loaded, three words pushed -- which
  no Pascal caller could do, so it is assembler too. It takes its own
  arguments the ordinary Pascal way.

  `RET $0A` is ten bytes of parameters where the body reads only eight, and
  the unread pair is the LOWEST, at [BP+$04]: Page is declared and never
  looked at, because Tri_Fill takes the page from the WritePage global
  instead. That parameter had been left out of the reconstruction's
  signature, which made the epilogue RET 8.

  Count - 3 into the counter and `DEC` / `JNS` runs it Count-2 times, one
  triangle per step, all of them sharing Pts[1]. ES:DI is saved into locals
  across each call and restored after, because Tri_Fill uses both.
  -------------------------------------------------------------------------- }
type
  TPointList = array[1..FaceVerts] of record X, Y : Integer end;

{ @asm 002 108b:09b1 }
procedure FillFan(var Pts : TPointList; Count : Integer; Colour : Byte;
                  Page : Word); assembler;
var
  FanX1, FanY1 : Integer;     { [BP-$02], [BP-$04], the shared first vertex }
  FanLeft      : Integer;     { [BP-$06], triangles still to do             }
  FanSeg, FanOfs : Word;      { [BP-$08], [BP-$0A], ES:DI across the call   }
(* EQUIVALENT PASCAL -- REFERENCE ONLY, and it is NOT what is compiled. The
  assembler below is the transcription. This cannot be a working procedure
  either, because the call it makes passes four arguments in registers.

    procedure FillFan(var Pts : TPointList; Count : Integer;
                      Colour : Byte; Page : Word);
    var I : Integer;
    begin
      if Count < 3 then Exit;           { a fan needs three points          }
      for I := 2 to Count - 1 do        { Count-2 triangles, DEC/JNS below  }
        TriFill(Pts[1].X, Pts[1].Y,     { the shared first vertex           }
                Pts[I].X, Pts[I].Y,
                Pts[I + 1].X, Pts[I + 1].Y, Colour);
      { Page is declared and never read -- TriFill takes the page from the
        WritePage global. It is what makes the epilogue RET $0A and not 8. }
    end;
    EQUIVALENT PASCAL ends here -- REFERENCE ONLY, none of it compiled  *)
asm
  MOV  CX, Count          { CX := Count                                   }
  CMP  CX, 3              { a fan needs three points                        }
  JL   @@FanDone          { < : to FanDone                                }
  SUB  CX, 3              { CX := CX - 3                                  }
  MOV  FanLeft, CX        { Count-3, so DEC/JNS turns Count-2 times         }
  LES  DI, Pts            { ES:DI := the point list                         }
  MOV  AX, ES:[DI]        { AX := ES:[DI]                                 }
  MOV  FanX1, AX          { the vertex every triangle shares                }
  MOV  AX, ES:[DI + 2]    { AX := ES:[DI + 2]                             }
  MOV  FanY1, AX          { FanY1 := AX                                   }
@@FanTri:                 { <- FanTri                                     }
  ADD  DI, 4              { on to the next pair                             }
  MOV  BX, FanX1          { Tri_Fill's X1, in a register                    }
  MOV  CX, FanY1          { Y1                                              }
  MOV  DX, ES:[DI]        { X2                                              }
  MOV  SI, ES:[DI + 2]    { Y2                                              }
  MOV  AX, ES:[DI + 4]    { AX := ES:[DI + 4]                             }
  PUSH AX                 { X3, on the stack                                }
  MOV  AX, ES:[DI + 6]    { AX := ES:[DI + 6]                             }
  PUSH AX                 { Y3                                             }
  MOV  AX, WORD PTR Colour  { the WORD, as 108b:09ed does -- a Byte value    }
  PUSH AX                 { parameter still occupies a whole stack word     }
  MOV  FanSeg, ES         { Tri_Fill uses ES:DI, so keep them               }
  MOV  FanOfs, DI         { FanOfs := DI                                  }
  CALL TriFill            { call TriFill                                  }
  MOV  ES, FanSeg         { ES := FanSeg                                  }
  MOV  DI, FanOfs         { DI := FanOfs                                  }
  DEC  FanLeft            { FanLeft := FanLeft - 1                        }
  JNS  @@FanTri           { not negative : to FanTri                      }
@@FanDone:                { <- FanDone                                    }
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
  { FOUR Integers, not five. `ENTER $10a` is 266 bytes: 256 for the String
    value parameter's own copy at [BP-$100], then five word slots -- and the
    DEEPEST of them, [BP-$10a], is the code generator's. 108b:0021 reads the
    copy's length byte into it and 108b:002e compares against it, so it is
    the `for I := 1 to Length(S)` limit temporary. Declaring a fifth variable
    put the frame 2 bytes over at $10c. }
  I, R, C, Pen : Integer;    { [BP-$102], [BP-$104], [BP-$106], [BP-$108] }
begin
  Pen := 0;
  for I := 1 to Length(S) do
  begin
    { NO `G` AND NO RANGE TEST. 108b:006b loads S[I] and 108b:0075 is
      `IMUL DI, AX, $19` on Ord(S[I]) itself -- the subtraction of FontFirst
      is folded into the base displacement along with the row and column
      bias, which is why the font is addressed at $5122 and not at its own
      $5448: $5448 - 32*25 - 5 - 1 = $5122 exactly. The reconstruction's
      `if (G >= 0) and (G < FontCount)` has no counterpart in the bytes; the
      original trusts its two messages to be inside the glyph table. }
    for R := 1 to GlyphSide do
      for C := 1 to GlyphSide do
        if Font^[(Ord(S[I]) - FontFirst) * 25
                 + (R - 1) * GlyphSide + (C - 1)] <> 0 then
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
  { ENTER $04 is TWO Integers, not three: 108b:1105 runs the palette loop on
    [BP-$02] and so does the column loop after it, so the reconstruction's
    separate `Col` was a third variable the original does not have. Note also
    `MOV AL, BYTE PTR [BP-$02]` at 108b:110f -- the loop counter's low byte
    is what reaches SetRGB, because its first parameter is a Byte. }
  X, Y : Integer;                      { [BP-$02] 14 refs, [BP-$04] 7 refs }
begin
  for X := 100 to 200 do
    SetRGB(X, Pal[X * 3], Pal[X * 3 + 1], Pal[X * 3 + 2]);

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
{ 108b:0f66 -- Present, and Emit is INLINED into it }
procedure Present;
begin
  { NO DECLARED LOCALS AT ALL. `ENTER $100` is 256 bytes and every one of them
    is the CODE GENERATOR'S: 108b:0fd4 takes `LEA DI,[BP-$100]` and hands it
    to the runtime helper at 14b1:3882, which is the Char-to-String
    conversion. Passing `Msg1[i]` -- a Char -- to DrawText's `S : String`
    parameter is what buys that temporary, and a declared String here would
    have produced a second one. Same lesson as the loop limits in the
    renderers: a frame slot is not evidence of a declaration.

    There is no `Emit` procedure in the original -- no prologue candidate
    exists between 108b:0f66 and 108b:1101 -- and no guard on the index
    either; the reconstruction's `if (Idx < 1) or (Idx > Length(S))` has no
    counterpart in the bytes.

    THE OUTER `Frame > 100` IS REDUNDANT AND IT IS REALLY THERE. Three tests
    precede the first message: 108b:0f6a and 108b:0f80 both compare Frame
    against 100 and 108b:0f96 against 150, and the first one's false branch
    goes to the procedure's end while the other two go to the second message.
    Two tests would be a plain `and`; the third is an outer guard the author
    wrote, so it is transcribed.

    The arithmetic is 32-bit throughout because Frame is a LongInt: 108b:0fc5
    is the runtime's LongInt multiply and 108b:0fca adds 15 with an ADC, then
    only the low word is pushed for DrawText's Integer parameter. }
  if Frame > 100 then
  begin
    if (Frame > 100) and (Frame < 150) then
    begin
      WritePage := PageBase[0];
      DrawText((Frame - 100) * 6 + 15, TextY1, Msg1[Frame - 100]);
      WritePage := PageBase[1];
      DrawText((Frame - 100) * 6 + 15, TextY1, Msg1[Frame - 100]);
    end;
    if (Frame > 250) and (Frame < 300) then
    begin
      WritePage := PageBase[0];
      DrawText((Frame - 250) * 6 + 15, TextY2, Msg2[Frame - 250]);
      WritePage := PageBase[1];
      DrawText((Frame - 250) * 6 + 15, TextY2, Msg2[Frame - 250]);
    end;
  end;
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
{ 108b:0b42 -- takes the object BY VALUE }
procedure RenderA(O : TObj);
var
  { ENTER $1154 = 4,436 bytes, and the FIRST 2,897 of them are the value
    parameter's own copy at [BP-$0b51] -- the compiler's, not ours. The
    declared locals start below it, so Pts is nearer BP than Faces. }
  Pts   : TPointList;                    { [BP-$0b71], 32 bytes }
  { A LOCAL COPY OF THE FACE ARRAY, taken before anything else runs:
    108b:0b6a pushes both addresses and $5D7 = 1,495 and calls the runtime
    Move. Count, Idx and Colour are all read from this copy afterwards, while
    the screen coordinates come from the value parameter's copy. }
  Faces : TFaceArray;                    { [BP-$1148], 1,495 bytes }
  F     : Integer;                       { [BP-$114a], 14 references }
  K     : Integer;                       { [BP-$114c] }
  { ONE declared Byte, written 0 at the top of every face and never read --
    108b:0bd7 is `MOV BYTE PTR [BP-$114f], 0`. It is a declaration and not a
    temporary because the frame does not close without it: the compiler's own
    temporaries come to six bytes here, and 2,897 + 1,531 + 6 rounds to
    $1152, two short of the original's $1154. With this byte the declared
    total is odd, the frame rounds up, and $1154 is exact. }
  Flag  : Byte;
  { AND NOTHING ELSE BEYOND IT. The eight bytes below K -- a byte at [BP-$114f] written
    0 and never read, and words at [BP-$1151] and [BP-$1153] -- are the CODE
    GENERATOR'S, not declarations. 108b:0bb9 reads O.FaceCount into
    [BP-$1151] and then compares against it: that is a `for` loop's upper
    bound evaluated once into a temporary, which is what a non-constant limit
    costs. Declaring them as locals produced BOTH ours and the compiler's and
    put the frame 8 bytes over at $115c.

    Two things follow that are worth keeping. A WORD AT AN ODD BP OFFSET IS
    NOT PROOF OF A ONE-BYTE LOCAL DECLARED BEFORE IT -- it can be a
    temporary, and here it is. And `prologue.py`'s note that no bytes lie
    beyond the lowest touched slot does NOT mean there are no temporaries:
    it cannot see a temporary that is touched, which every loop bound is. }
begin
  Faces := O.Face;
  { the starfield, inline -- 108b:0b6f reads Star[F] at stride 6 straight out
    of DGROUP, X at +0, Y at +2 and Z as the colour byte at +4 }
  for F := 1 to StarCount do
    Plot(Star[F].X, Star[F].Y, Star[F].Z);
  for F := 1 to O.FaceCount do
  begin
    Flag := 0;
    for K := 1 to Faces[F].Count do
    begin
      Pts[K].X := O.Scr[Faces[F].Idx[K]].X;
      Pts[K].Y := O.Scr[Faces[F].Idx[K]].Y;
    end;
    { Count is read AGAIN here rather than reusing C -- 108b:0c61 is a fresh
      `PUSH WORD PTR [BP+DI-$115F]` -- and the colour is a byte widened with
      XOR AH,AH. }
    FillFan(Pts, Faces[F].Count, Faces[F].Colour, WritePage);
  end;
  { FlipAndSwap, inline }
  FlipPage(WritePage);
  PageIndex := (PageIndex + 1) mod 2;
end;

{ 108b:0ca1 -- takes the object BY VALUE }
procedure RenderB(O : TObj);
var
  { ENTER $1154 = 4,436 bytes, and the FIRST 2,897 of them are the value
    parameter's own copy at [BP-$0b51] -- the compiler's, not ours. The
    declared locals start below it, so Pts is nearer BP than Faces. }
  Pts   : TPointList;                    { [BP-$0b71], 32 bytes }
  { A LOCAL COPY OF THE FACE ARRAY, taken before anything else runs:
    108b:0cc9 pushes both addresses and $5D7 = 1,495 and calls the runtime
    Move. Count, Idx and Colour are all read from this copy afterwards, while
    the screen coordinates come from the value parameter's copy. }
  Faces : TFaceArray;                    { [BP-$1148], 1,495 bytes }
  F     : Integer;                       { [BP-$114a], 14 references }
  K     : Integer;                       { [BP-$114c] }
  { ONE declared Byte, written 0 at the top of every face and never read --
    108b:0bd7 is `MOV BYTE PTR [BP-$114f], 0`. It is a declaration and not a
    temporary because the frame does not close without it: the compiler's own
    temporaries come to six bytes here, and 2,897 + 1,531 + 6 rounds to
    $1152, two short of the original's $1154. With this byte the declared
    total is odd, the frame rounds up, and $1154 is exact. }
  Flag  : Byte;
  { AND NOTHING ELSE BEYOND IT. The eight bytes below K -- a byte at [BP-$114f] written
    0 and never read, and words at [BP-$1151] and [BP-$1153] -- are the CODE
    GENERATOR'S, not declarations. 108b:0bb9 reads O.FaceCount into
    [BP-$1151] and then compares against it: that is a `for` loop's upper
    bound evaluated once into a temporary, which is what a non-constant limit
    costs. Declaring them as locals produced BOTH ours and the compiler's and
    put the frame 8 bytes over at $115c.

    Two things follow that are worth keeping. A WORD AT AN ODD BP OFFSET IS
    NOT PROOF OF A ONE-BYTE LOCAL DECLARED BEFORE IT -- it can be a
    temporary, and here it is. And `prologue.py`'s note that no bytes lie
    beyond the lowest touched slot does NOT mean there are no temporaries:
    it cannot see a temporary that is touched, which every loop bound is. }
begin
  Faces := O.Face;
  { the starfield, inline -- 108b:0cce reads Star[F] at stride 6 straight out
    of DGROUP, X at +0, Y at +2 and Z as the colour byte at +4 }
  for F := 1 to StarCount do
    Plot(Star[F].X, Star[F].Y, Star[F].Z);
  DrawRewind;
  for F := 1 to O.FaceCount do
  begin
    Flag := 0;
    for K := 1 to Faces[F].Count do
    begin
      Pts[K].X := O.Scr[Faces[F].Idx[K]].X;
      Pts[K].Y := O.Scr[Faces[F].Idx[K]].Y;
    end;
    { Count is read AGAIN here rather than reusing C -- 108b:0dc0 is a fresh
      `PUSH WORD PTR [BP+DI-$115F]` -- and the colour is a byte widened with
      XOR AH,AH. }
    FillFan(Pts, Faces[F].Count, Faces[F].Colour, WritePage);
  end;
  { FlipAndSwap, inline }
  FlipPage(WritePage);
  PageIndex := (PageIndex + 1) mod 2;
end;

{ 108b:0a2d -- takes the object BY VALUE }
procedure RenderC(O : TObj);
var
  { ENTER $1154 = 4,436 bytes, and the FIRST 2,897 of them are the value
    parameter's own copy at [BP-$0b51] -- the compiler's, not ours. The
    declared locals start below it, so Pts is nearer BP than Faces. }
  Pts   : TPointList;                    { [BP-$0b71], 32 bytes }
  { A LOCAL COPY OF THE FACE ARRAY, taken before anything else runs:
    108b:0a55 pushes both addresses and $5D7 = 1,495 and calls the runtime
    Move. Count, Idx and Colour are all read from this copy afterwards, while
    the screen coordinates come from the value parameter's copy. }
  Faces : TFaceArray;                    { [BP-$1148], 1,495 bytes }
  F     : Integer;                       { [BP-$114a], 14 references }
  K     : Integer;                       { [BP-$114c] }
  { ONE declared Byte, written 0 at the top of every face and never read --
    108b:0bd7 is `MOV BYTE PTR [BP-$114f], 0`. It is a declaration and not a
    temporary because the frame does not close without it: the compiler's own
    temporaries come to six bytes here, and 2,897 + 1,531 + 6 rounds to
    $1152, two short of the original's $1154. With this byte the declared
    total is odd, the frame rounds up, and $1154 is exact. }
  Flag  : Byte;
  { AND NOTHING ELSE BEYOND IT. The eight bytes below K -- a byte at [BP-$114f] written
    0 and never read, and words at [BP-$1151] and [BP-$1153] -- are the CODE
    GENERATOR'S, not declarations. 108b:0bb9 reads O.FaceCount into
    [BP-$1151] and then compares against it: that is a `for` loop's upper
    bound evaluated once into a temporary, which is what a non-constant limit
    costs. Declaring them as locals produced BOTH ours and the compiler's and
    put the frame 8 bytes over at $115c.

    Two things follow that are worth keeping. A WORD AT AN ODD BP OFFSET IS
    NOT PROOF OF A ONE-BYTE LOCAL DECLARED BEFORE IT -- it can be a
    temporary, and here it is. And `prologue.py`'s note that no bytes lie
    beyond the lowest touched slot does NOT mean there are no temporaries:
    it cannot see a temporary that is touched, which every loop bound is. }
begin
  Faces := O.Face;
  for F := 1 to O.FaceCount do
  begin
    Flag := 0;
    for K := 1 to Faces[F].Count do
    begin
      Pts[K].X := O.Scr[Faces[F].Idx[K]].X;
      Pts[K].Y := O.Scr[Faces[F].Idx[K]].Y;
    end;
    { Count is read AGAIN here rather than reusing C -- 108b:0b4c is a fresh
      `PUSH WORD PTR [BP+DI-$115F]` -- and the colour is a byte widened with
      XOR AH,AH. }
    FillFan(Pts, Faces[F].Count, Faces[F].Colour, WritePage);
  end;
  { FlipAndSwap, inline }
  FlipPage(WritePage);
  PageIndex := (PageIndex + 1) mod 2;
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
  { THREE Integers and the 128 dead bytes, and the frame closes at $8a rather
    than $86 because the two loop limits read out of the object at 108b:1cf3
    and 108b:1da1 become the code generator's temporaries at [BP-$88] and
    [BP-$8a]. Declaring them would produce both. }
  I : Integer;      { [BP-$02], 79 refs -- the outer index, and the palette
                      ramp counter earlier in the routine }
  K : Integer;      { [BP-$04], 16 refs -- the inner face-index counter }
  P : Integer;      { [BP-$06], 28 refs -- the flat face stream's position }
  Unused : array[1..128] of Byte;      { [BP-$86]..[BP-$07], never read }
begin
  { 108b:1bc1 -- a grey ramp with a period of 53 }
  for I := 1 to 255 do
    SetRGB(I, (I mod 53) + 10, (I mod 53) + 10, (I mod 53) + 10);

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

  { ONLY THE ENTERPRISE INCREMENTS ITS INDICES AND HALVES ITS COLOUR. The four
    loaders are NOT one template: 108b:1df6 has `INC AX` on object 1's face
    index and 108b:1e1d halves its colour, and objects 2, 3 and 4 have neither
    -- 108b:1fca reads the index and stores it straight. All four DO halve
    their vertex components. Writing all four the same way broke the revolver,
    the sailboat and the quad, and a watched run is what caught it.

    THERE IS NO FillChar EITHER. The objects are DGROUP, so they arrive zeroed,
    and the original writes only the fields it wants -- distinguishing a plain
    `:= 0` (XOR AX,AX and two stores) from `:= IntToFixed(0)` (a PUSH and a
    call). Both forms appear below because both are in the binary. }
  { 108b:1cc4 -- Enterprise. The counts are written as immediates before the
    loops and read back OUT of the object by them. }
  Obj[1].VertCount := NVertEnterprise;
  Obj[1].FaceCount := NFaceEnterprise;
  for I := 1 to Obj[1].VertCount do
  begin
    Obj[1].Vert[I].X := IntToFixed(VertEnterprise[I, 1] div 2);
    Obj[1].Vert[I].Y := IntToFixed(VertEnterprise[I, 2] div 2);
    Obj[1].Vert[I].Z := IntToFixed(VertEnterprise[I, 3] div 2);
  end;
  P := 0;
  for I := 1 to Obj[1].FaceCount do
  begin
    Obj[1].Face[I].Count := FaceEnterprise[P + 1];
    for K := 1 to Obj[1].Face[I].Count do
    begin
      Inc(P);
      Obj[1].Face[I].Idx[K] := FaceEnterprise[P + 1] + 1;
    end;
    Inc(P);
    Obj[1].Face[I].Colour := FaceEnterprise[P + 1] div 2;
    Obj[1].Face[I].Spare1 := 0;
    Obj[1].Face[I].Spare2 := 0;
    Inc(P);
  end;
  Obj[1].Angle.X := 0;
  Obj[1].Angle.Y := 0;
  Obj[1].Angle.Z := 0;
  Obj[1].Accum.X := 0;
  Obj[1].Accum.Y := 0;
  Obj[1].Accum.Z := 0;
  Obj[1].Trans.X := 0;
  Obj[1].Trans.Y := 0;
  Obj[1].Trans.Z := IntToFixed(-850);
  Obj[1].Pivot.X := IntToFixed(150);
  Obj[1].Pivot.Y := 0;
  Obj[1].Pivot.Z := IntToFixed(0);

  { 108b:1ec0 -- Revolver. The counts are written as immediates before the
    loops and read back OUT of the object by them. }
  Obj[2].VertCount := NVertRevolver;
  Obj[2].FaceCount := NFaceRevolver;
  for I := 1 to Obj[2].VertCount do
  begin
    Obj[2].Vert[I].X := IntToFixed(VertRevolver[I, 1] div 2);
    Obj[2].Vert[I].Y := IntToFixed(VertRevolver[I, 2] div 2);
    Obj[2].Vert[I].Z := IntToFixed(VertRevolver[I, 3] div 2);
  end;
  P := 0;
  for I := 1 to Obj[2].FaceCount do
  begin
    Obj[2].Face[I].Count := FaceRevolver[P + 1];
    for K := 1 to Obj[2].Face[I].Count do
    begin
      Inc(P);
      Obj[2].Face[I].Idx[K] := FaceRevolver[P + 1];
    end;
    Inc(P);
    Obj[2].Face[I].Colour := FaceRevolver[P + 1];
    Obj[2].Face[I].Spare1 := 0;
    Obj[2].Face[I].Spare2 := 0;
    Inc(P);
  end;
  Obj[2].Angle.X := 0;
  Obj[2].Angle.Y := 0;
  Obj[2].Angle.Z := 0;
  Obj[2].Accum.X := 0;
  Obj[2].Accum.Y := 0;
  Obj[2].Accum.Z := 0;
  Obj[2].Trans.X := IntToFixed(1500);
  Obj[2].Trans.Y := 0;
  Obj[2].Trans.Z := IntToFixed(-1500);
  Obj[2].Pivot.X := IntToFixed(150);
  Obj[2].Pivot.Y := 0;
  Obj[2].Pivot.Z := IntToFixed(0);

  { 108b:2096 -- Sailboat. The counts are written as immediates before the
    loops and read back OUT of the object by them. }
  Obj[3].VertCount := NVertSailboat;
  Obj[3].FaceCount := NFaceSailboat;
  for I := 1 to Obj[3].VertCount do
  begin
    Obj[3].Vert[I].X := IntToFixed(VertSailboat[I, 1] div 2);
    Obj[3].Vert[I].Y := IntToFixed(VertSailboat[I, 2] div 2);
    Obj[3].Vert[I].Z := IntToFixed(VertSailboat[I, 3] div 2);
  end;
  P := 0;
  for I := 1 to Obj[3].FaceCount do
  begin
    Obj[3].Face[I].Count := FaceSailboat[P + 1];
    for K := 1 to Obj[3].Face[I].Count do
    begin
      Inc(P);
      Obj[3].Face[I].Idx[K] := FaceSailboat[P + 1];
    end;
    Inc(P);
    Obj[3].Face[I].Colour := FaceSailboat[P + 1];
    Obj[3].Face[I].Spare1 := 0;
    Obj[3].Face[I].Spare2 := 0;
    Inc(P);
  end;
  Obj[3].Angle.X := 0;
  Obj[3].Angle.Y := 0;
  Obj[3].Angle.Z := 0;
  Obj[3].Accum.X := 0;
  Obj[3].Accum.Y := 0;
  Obj[3].Accum.Z := 0;
  Obj[3].Trans.X := IntToFixed(-1500);
  Obj[3].Trans.Y := 0;
  Obj[3].Trans.Z := IntToFixed(-1500);
  Obj[3].Pivot.X := IntToFixed(0);
  Obj[3].Pivot.Y := IntToFixed(0);
  Obj[3].Pivot.Z := IntToFixed(0);

  { 108b:2271 -- Quad. The counts are written as immediates before the
    loops and read back OUT of the object by them. }
  Obj[4].VertCount := NVertQuad;
  Obj[4].FaceCount := NFaceQuad;
  for I := 1 to Obj[4].VertCount do
  begin
    Obj[4].Vert[I].X := IntToFixed(VertQuad[I, 1] div 2);
    Obj[4].Vert[I].Y := IntToFixed(VertQuad[I, 2] div 2);
    Obj[4].Vert[I].Z := IntToFixed(VertQuad[I, 3] div 2);
  end;
  P := 0;
  for I := 1 to Obj[4].FaceCount do
  begin
    Obj[4].Face[I].Count := FaceQuad[P + 1];
    for K := 1 to Obj[4].Face[I].Count do
    begin
      Inc(P);
      Obj[4].Face[I].Idx[K] := FaceQuad[P + 1];
    end;
    Inc(P);
    Obj[4].Face[I].Colour := FaceQuad[P + 1];
    Obj[4].Face[I].Spare1 := 0;
    Obj[4].Face[I].Spare2 := 0;
    Inc(P);
  end;
  Obj[4].Angle.X := 0;
  Obj[4].Angle.Y := 0;
  Obj[4].Angle.Z := 0;
  Obj[4].Accum.X := 0;
  Obj[4].Accum.Y := 0;
  Obj[4].Accum.Z := 0;
  Obj[4].Trans.X := 0;
  Obj[4].Trans.Y := 0;
  Obj[4].Trans.Z := IntToFixed(-1000);
  Obj[4].Pivot.X := IntToFixed(0);
  Obj[4].Pivot.Y := IntToFixed(0);
  Obj[4].Pivot.Z := IntToFixed(0);
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
procedure Choreography;
var
  { 108b:11c1 opens ENTER $30e = 782 bytes, and the buffer is the last
    declaration, so it runs from [BP-$30e] to [BP-$0f] and fourteen bytes of
    scalars sit above it. PA, PB and PC are LOCALS here and INTEGERS, not the
    unit-level LongInts this had before: 108b:12a0 reads [BP-$02], [BP-$06]
    and [BP-$04] as words and widens each with CWD before the push, which is
    what an Integer actual for a LongInt formal compiles to.

    Declaration order is the slot order, first declared nearest BP, and the
    call at 108b:12a0 passes them as (PC, PA, PB) -- so PC is [BP-$02], PB is
    [BP-$04] and PA is [BP-$06], which fixes the order below. }
  PC, PB, PA : Integer;          { [BP-$02], [BP-$04], [BP-$06] }
  { SIX BYTES DECLARED AND NEVER READ. Nothing in 108b:11c1..1bbd addresses
    [BP-$08], [BP-$0a] or [BP-$0c] -- the slot walk's one-reference rows there
    are its disp16 scan matching inside immediates, which it warns about, and
    the disassembly has no such operand. They are transcribed because the
    frame is 782 bytes and the arithmetic does not close without them; what
    the author declared and never used is not recoverable, and three Integers
    is the shape that fits. }
  Dead1, Dead2, Dead3 : Integer; { [BP-$08], [BP-$0a], [BP-$0c] }
  I   : Integer;                 { [BP-$0e], 62 references }
  Buf : array[0..767] of Byte;   { [BP-$30e] }
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

  for I := 1 to 100 do
  begin
    ObjTranslate(Obj[1], 0, 0, 3);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Inc(Frame);
    Present;
  end;
  SyncPattern(2, 1);
  for I := 1 to  80 do
  begin
    ObjTranslate(Obj[1], 0, 0, 3);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Inc(Frame);
    Present;
  end;
  for I := 1 to  20 do
  begin
    ObjTranslate(Obj[1], -1, 0, 3);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Inc(Frame);
    Present;
  end;

  for I := 1 to 50 do
  begin
    Inc(PB, 5);  Dec(PC, 2);
    ObjTranslate(Obj[1], -2, 0, 2);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Inc(Frame);
    Present;
  end;
  for I := 1 to 50 do
  begin
    Dec(PB, 5);  Inc(PA, 20);  Inc(PC, 2);
    ObjTranslate(Obj[1], -3, 0, 0);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Inc(Frame);
    Present;
  end;
  for I := 1 to 50 do
  begin
    ObjTranslate(Obj[1], -3, 0, 0);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Inc(Frame);
    Present;
  end;

  { 108b:15ca -- the banner beat, inline: the original has no procedure here }
  SyncPattern(3, 1);
  WaitRetrace;
  DrawBanner;
  for I := 1 to 50 do WaitRetrace;
  { and the strip clear, also inline -- 108b:15f0 }
  WritePage := PageBase[0];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  WritePage := PageBase[1];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  Delay(300);
  { 108b:15ca -- the banner beat, inline: the original has no procedure here }
  SyncPattern(3, 1);
  WaitRetrace;
  DrawBanner;
  for I := 1 to 50 do WaitRetrace;
  { and the strip clear, also inline -- 108b:15f0 }
  WritePage := PageBase[0];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  WritePage := PageBase[1];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  Delay(300);
  { 108b:15ca -- the banner beat, inline: the original has no procedure here }
  SyncPattern(3, 1);
  WaitRetrace;
  DrawBanner;
  for I := 1 to 50 do WaitRetrace;
  { and the strip clear, also inline -- 108b:15f0 }
  WritePage := PageBase[0];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  WritePage := PageBase[1];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);

  for I := 1 to 12 do
  begin
    ObjTranslate(Obj[1], 12, 0, 0);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
    Inc(Frame);
    Present;
  end;
  SyncPattern(4, 1);
  for I := 1 to 12 do
  begin
    Inc(PB, 20);  Dec(PA, 80);  Dec(PC, 8);
    ObjTranslate(Obj[1], 12, 0, 0);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
    Inc(Frame);
    Present;
  end;
  for I := 1 to 12 do
  begin
    Dec(PB, 20);  Inc(PC, 8);
    ObjTranslate(Obj[1], 8, 0, -8);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
    Inc(Frame);
    Present;
  end;
  for I := 1 to  5 do
  begin
    ObjTranslate(Obj[1], 4, 0, -12);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
    Inc(Frame);
    Present;
  end;
  for I := 1 to 45 do
  begin
    ObjTranslate(Obj[1], 0, 0, -12);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
    Inc(Frame);
    Present;
  end;

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
    ObjTranslate(Obj[2], -20, 0, 10);
    ObjTransform(Obj[2], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, Rows, WritePage, 0);
    ObjSortFaces(Obj[2]);
    RenderC(Obj[2]);
  end;

  { 108b:1a26 }
  PA := 270;  PB := 180;  PC := 180;
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);
  ObjTransform(Obj[3], PC, PA, PB);

  for I := 1 to 120 do
  begin
    Inc(PA, 10);  Inc(PB, 10);  Inc(PC, 10);
    ObjTranslate(Obj[3], 20, 0, 10);
    ObjTransform(Obj[3], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, Rows, WritePage, 0);
    ObjSortFaces(Obj[3]);
    RenderC(Obj[3]);
  end;

  { 108b:1af2 }
  SetRGB($20, $3F, $3F, $3F);
  PA := 0;  PB := 0;  PC := 0;
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);

  for I := 1 to 99 do
  begin
    { 108b:1b53 -- here the nudge comes AFTER the translate, not before }
    ObjTranslate(Obj[4], 0, 0, 10);
    Inc(PA, 37);  Inc(PB, 10);
    ObjTransform(Obj[4], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, Rows, WritePage, 0);
    ObjSortFaces(Obj[4]);
    RenderC(Obj[4]);
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
  { ENTER $80 is 128 bytes and no BP-relative slot is touched at all: the
    whole frame is the untyped `file`, which is 128 bytes in Turbo Pascal.
    There was a `Vol : Byte` here that the routine wrote and never read, and
    it put the frame at $82. The saved volume is a global -- see SaveVol. }
  F : file;
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
  { 108b:2564 -- the ramp, and the body really is written out TWICE with a
    test between the halves. Every GetVolume result goes to CurVol and the
    sequence is: read, step down, read, and if that is not yet zero do the
    three again, then Delay and test. Reading it as a `while GetVolume > 0`
    loop gave one copy of the body and a different test. }
  SaveVol := GetVolume;
  repeat
    CurVol := GetVolume;
    SetVolume(CurVol - 1);
    CurVol := GetVolume;
    if CurVol <> 0 then
    begin
      CurVol := GetVolume;
      SetVolume(CurVol - 1);
      CurVol := GetVolume;
    end;
    Delay(10);
  until CurVol = 0;
  SyncPattern(1, 1);
  MusicStop;
  SetVolume(SaveVol);

  FreeMem(Banner, SizeOf(TBanner));
  Dispose(Font);
end;

begin
  { The two messages are Pascal strings in DGROUP at DS:$046E and DS:$056E. }
  Msg1 := 'CAPTAINS LOG, STARDATE 426987.2, SUPPLIMENTAL  :           ';
  Msg2 := '     PICTURE IT,   SICILY,   1942 ....               ';
end.
