{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 5.

  Transcribed from segment 12c5. Every routine carries the address it came
  from. What was previously inferred here got four things wrong, all of them
  visible: the translation axes were swapped, the object never got its start
  position, the projection scale was invented, and the closing wipe copied
  from the screen it had just blanked.
  =========================================================================== }

unit P1S5;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }
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

{$I gen/P1VECT.INC}      { const VecLogoA, VecGlobe : FLAT array[0..n*3-1] of Integer }

const
  { 100, and it is MEASURED, not chosen. 12c5:031a reaches the object's
    translation with ADD DI,$4B0 and the point array starts at the object's
    own address (12c5:0366 is IMUL AX,[BP-2],0C / ADD DI,AX / ADD DI,$FFF4).
    $4B0 is 1200 bytes, which is exactly one hundred twelve-byte points.

    It was 64, and that put every DGROUP address after the array wrong by 432
    bytes. With 100 the four addresses this file already recorded separately
    all fall out of one layout: Obj at $A106, ObjMeta at $A106+$4BC = $A5C2,
    Scr at $A5C2+52 = $A5F6 -- which is the pointer 12c5:0621 hands SortAll --
    and Scr's own 1200 bytes end at $AAC6, where WorkSeg is, with PtCount at
    $AAC8 right behind it. }
  MaxPoints    = 100;
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
  { A model point, and it needs a NAME because 12c5:01b0 takes one BY VALUE:
    12c5:01bb is LEA DI,[BP-0C] / LDS SI,[BP+1E] / MOV CX,0C / REP MOVSB, which
    is how Turbo Pascal hands a structured value parameter to a callee -- the
    caller pushes a pointer and the callee copies. Twelve bytes, 16.16 fixed. }
  TPoint3 = record
    X, Y, Z : LongInt;
  end;
  PPoint3 = ^TPoint3;

  { THE MODEL IS ONE RECORD, PASSED BY POINTER. Both 12c5:02e3 and 12c5:03a2
    open LES DI,[BP+0A] and RET $A -- a far pointer parameter and three
    Integers -- and 12c5:0785 calls the first of them as
    MOV DI,$A106 / PUSH DS / PUSH DI, so the record is a unit-level variable
    and the caller passes its address. The points sit at offset 0 and the
    translation at $4B0, which is what fixes MaxPoints at 100.

    This was three separate unit-level things here: a Pt array and three loose
    PosX/PosY/PosZ LongInts, with every routine reading them directly and
    taking no parameter at all. }
  TObj = record
    Pt  : array[1..MaxPoints] of TPoint3;   { offset 0, 1200 bytes }
    Pos : TPoint3;                          { offset $4B0 }
  end;
  PObj = ^TObj;

  TScreenPt = record
    X, Y, D : Integer;      { six bytes, matching the $A5F0 stride }
  end;

  { SortAll takes the array BY POINTER, so it needs a name and a pointer to it.
    12c5:0621 pushes DS and DI -- a far pointer -- and 12c5:0027 loads it back
    with LES DI, SS:[link+4]. Declared AFTER TScreenPt: an array of it cannot
    be named before the element type is. }
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
  Obj     : TObj;                                  { DS:$A106 }
  { DS:$A5C2 -- the 52-byte point sprite: a 2-byte (W, H) header and 50 px. }
  ObjMeta : array[0..51] of Byte;
  { DS:$A5F6, NOT $A5F0. The stores are `I * 6 - $5A10` and $A5F0 is the
    DISPLACEMENT a one-based array of six-byte records gets; the first element
    is six bytes further on. 12c5:0621 pushes $A5F6 to SortAll, which is the
    same number read the other way. }
  Scr     : TScrArr;                               { DS:$A5F6 }
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
  { DS:$AAA6..$AABD -- cos then sin, per axis, as SinCos leaves them. Scr's
    1200 bytes end at $AAA6, so this block follows it immediately. }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  { DS:$AABE -- the projection scale, 16.16. }
  MScale : LongInt;

  { And the rest of the unit's variables follow the maths block, which is why
    they are declared here rather than at the top. }
  { DS:$AAC2 -- the render target. Animate copies the clean gradient out of
    the virtual screen into it, draws, and blits it to video. }
  Work    : Pointer;
  WorkSeg : Word;                                   { DS:$AAC6 }
  PtCount : Integer;                                { DS:$AAC8 }
  { DS:$AACA, $AACC, $AACE -- THREE INTEGERS, and they ARE referenced. This
    said `six bytes declared and never read, so the type is a guess: Real`.
    The guess was wrong and the premise was too. The x87 traps had made the
    region unreadable to a plain disassembler -- INT $3A..$3E carry their
    operands inline, so the decoder resynchronised in the middle of them and
    printed nonsense. Decoding it with the kit's x87 disassembler shows all
    three being written:

      12c5:07db  MOV [$AACA],AX   after Round(Cos(Local * Pi / 180) * 5)
      12c5:0802  MOV [$AACC],AX   after Round(Sin(Orbit * Pi / 180) * 20)
      12c5:0828  MOV [$AACE],AX   after Round(Sin(Local * Pi / 180) * 500)

    and 12c5:0842..084a pushing all three to ObjTranslate. A trap-carrying
    region needs the x87 decoder before anything in it is called unreferenced. }
  Dx      : Integer;                                { DS:$AACA }
  Dy      : Integer;                                { DS:$AACC }
  Dz      : Integer;                                { DS:$AACE }
  { DS:$AAD0 spin, DS:$AAD2 orbit. Local lives in Animate's own frame. }
  Angle      : Integer;                             { DS:$AAD0 }
  OrbitAngle : Integer;                             { DS:$AAD2 }
  { DS:$AAD4 -- THE FILE RECORD IS A GLOBAL, not a local in Load. 12c5:0417
    pushes DS:$AAD4 to Assign, a data-segment address, where a local would be
    LEA'd off SS. It also closes this unit's block: 128 bytes from $AAD4 ends
    at $AB54, which is exactly where dsmap's next shift boundary is. }
  F : file;                                         { DS:$AAD4 }

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
  { DS:$0284 = $A640, AND IT IS NOT AN ADDRESS. The original's initialised image
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
  MirrorOfs : Word = ScrWidth * Horizon;            { DS:$0284 = $A640 }

{ 12c5:0AC6 -- the scene's own screen copy, 16,000 DWORDS in one REP MOVSD.
  386 code, so it cannot be an asm block; and it sits five bytes AFTER the
  unit's initialisation stub at 12c5:0AC1, which Turbo Pascal emits last, so it
  cannot have come from the Pascal at all. Linked FIRST of the two objects
  because its code lands before DEMOMATH's. See src/asm/COPY32.ASM. }
{$L COPY32.OBJ}
procedure Copy32(Src, Dest : Word);                       external;

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
    Obj.Pt[I].X := IntToFixed(Src^[I, 1]);
    Obj.Pt[I].Y := IntToFixed(Src^[I, 2]);
    Obj.Pt[I].Z := IntToFixed(Src^[I, 3]);
  end;
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
{ --------------------------------------------------------------------------
  12c5:01b0 -- TransformPoint, and it is A ROUTINE OF ITS OWN.

  This body was INLINED here, in ObjTransformAll's loop. A note further down
  this file already said 12c5:02e3 "fans out to 12c5:01b0" and the code did
  not do it; ten spans traced to this address.

  THE PARAMETER LIST IS RECOVERED FROM THE CALL SITE, not guessed. RET $1E, so
  30 bytes of parameters, and 12c5:0366..0393 pushes exactly that:

    ES:DI = Obj^ + I*12 - 12    4   [BP+1E]   the point, BY VALUE
    [bp+8] [bp+6] [bp+4] CWD   12   [BP+1A] [BP+16] [BP+12]
    three cached LongInts      12   [BP+0E] [BP+0A] [BP+06]
    [bp-2]                      2   [BP+04]   the loop index

  Pascal convention pushes left to right, so the first parameter declared is
  the one pushed first and it sits at the HIGHEST offset. Hence this order.

  A1, A2, A3 ARE PASSED AND NEVER READ -- the routine touches [BP+04], +06,
  +08, +0A, +0C, +0E, +10 and +1E and nothing in between. The three angles
  were already consumed by the SinCos calls before the loop, so they are dead
  here. They are transcribed anyway: they are three of the thirty bytes, and
  dropping them moves every parameter after them.

  The caller widens each angle with CWD, so the parameters are LongInt while
  the arguments are Integer.
  -------------------------------------------------------------------------- }
procedure TransformPoint(P          : TPoint3;
                         A1, A2, A3 : LongInt;
                         TX, TY, TZ : LongInt;
                         I          : Integer);
var
  { BOTH ARE LONGINT, and that is measured twice over. 12c5:0222 is
    MOV AX,[BP-0C] / CWD / MOV [BP-10],AX / MOV [BP-0E],DX -- a sign-extend
    into a FOUR-byte slot, which an Integer local would not need -- and every
    expression built on them is done in 32 bits: 12c5:024d is SUB AX,[BP-14]
    / SBB DX,[BP-12] and 12c5:029a is ADD AX,$85 / ADC DX,0. Declared as
    Integer, the whole routine is 24 bytes short and the arithmetic is 16-bit.

    Sx is [BP-10] and Sy is [BP-14], so Sx is the first local declared. }
  Sx, Sy : LongInt;

  { TWENTY BYTES DECLARED AND NEVER REFERENCED. ENTER $28 is 40 bytes; the
    twelve-byte value copy of P plus these two LongInts account for 20, and
    the routine touches no offset below [BP-14] at any width. So the 1994
    source declared 20 bytes more here and used none of it.

    They are transcribed for the same reason the three dead angle parameters
    are: a declaration that is not there moves every offset after it, and this
    routine's offsets are the whole reason its 300 bytes now align. The TYPE
    is a guess -- 20 bytes is five LongInts, or a twelve-byte point and two
    more, or ten Integers, and nothing in the binary distinguishes them
    because nothing reads them. LongInt is chosen only because every other
    local here is one. }
  Dead1, Dead2, Dead3, Dead4, Dead5 : LongInt;
begin
  { P IS the twelve-byte copy at [BP-0C], so there are no coordinate locals to
    load it into -- the copy the compiler makes for a value parameter is what
    the rest of the routine works on, and 12c5:01c9 pushes @P.X, @P.Y, @P.Z
    straight out of the frame. }
  RotatePoint(P.X, P.Y, P.Z);                     { 12c5:01d7 }

  { NOT Inc(). 12c5:01da is MOV AX,[BP-0C] / MOV DX,[BP-0A] / ADD AX,[BP+0E]
    / ADC DX,[BP+10] / MOV [BP-0C],AX / MOV [BP-0A],DX -- eighteen bytes that
    load the target into a register pair, add, and store back. Inc(P.X, TX)
    compiles to the read-modify-write form instead, MOV AX,[BP+0E] / MOV
    DX,[BP+10] / ADD [BP-0C],AX / ADC [BP-0A],DX, which is twelve. Six bytes
    per site, three sites, and every span after it in this segment was
    displaced by the difference. }
  P.X := P.X + TX;                                { 12c5:01da }
  P.Y := P.Y + TY;
  P.Z := P.Z + TZ;

  Project(P.X, P.Y, P.Z);                         { 12c5:021f }

  { 12c5:0222 -- both come back zero-extended, so the low word carries the
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
  Scr[I].D := FixedToIntTrunc(P.Z);   { 12c5:0268 -> 1483:0071 }

  Scr[I + PtCount].X := Integer(Sx);           { and its reflection }
  { 12c5:029a -- TWO adds, ADD AX,$85 then ADD AX,1, not one ADD AX,$86.
    Borland Pascal emits one instruction per operator and does not fold
    adjacent constants, so this is `+ Horizon + 1` in the source and writing
    it as `+ 134` would be six bytes shorter than the original. }
  Scr[I + PtCount].Y := Integer(Sy + Horizon + 1);
  Scr[I + PtCount].D := FixedToIntTrunc(P.Z);
end;

procedure ObjTransformAll(AObj : PObj; A1, A2, A3 : Integer);
var
  { ENTER $12 is 18 bytes and the arithmetic closes WITHOUT a spare, once the
    `with` below is counted. A `with` on a pointer dereference costs FOUR bytes
    of frame -- it computes AObj^.Pos once into a hidden far-pointer temp, which
    is the whole reason 12c5:031a is a single ADD DI,$4B0 -- so the counter, the
    three LongInts and that temp are 2 + 12 + 4 = 18 exactly.

    This note used to read "the counter, three LongInts and the for-loop's own
    two-byte limit temp account for 16, so two bytes here are declared and never
    read", and declared a Spare on that basis. The `with`'s cost was not known
    when it was written; with it counted there is no room for a spare, and
    prologue.py read ours as ENTER $14 against the original's $12. }
  I          : Integer;
  TX, TY, TZ : LongInt;
begin
  { 12c5:02f4 -- SinCos(angle, var C, var S). The FIRST var parameter takes
    the COSINE. }
  SinCos(A1, MCos1, MSin1);
  SinCos(A2, MCos2, MSin2);
  SinCos(A3, MCos3, MSin3);

  { 12c5:0317..0344 -- the translation is read ONCE, before the loop, into
    three locals, and those are what get passed per point. Reading PosX, PosY
    and PosZ inside the loop is the same answer and not the same code. }
  { A `with`, AND THE ONE ADD SAYS SO. 12c5:031a is ADD DI,$4B0 and the three
    fields are then read at ES:[DI], [DI+4] and [DI+8] with no further
    displacement -- the record's address computed ONCE for three reads. Naming
    AObj^.Pos at each field folds the $4B0 into every displacement instead,
    which is what ours did: three reads at [DI+$4B0], [DI+$4B4], [DI+$4B8]. }
  with AObj^.Pos do
  begin
    TX := X;                                   { 12c5:031e }
    TY := Y;                                   { 12c5:032b }
    TZ := Z;                                   { 12c5:0339 }
  end;

  for I := 1 to PtCount do
    TransformPoint(AObj^.Pt[I], A1, A2, A3, TX, TY, TZ, I);   { 12c5:0393 }
end;

{ --------------------------------------------------------------------------
  12c5:03a2 -- Obj_Translate(Obj, D1, D2, D3)

  Reads straight off the three blocks: D1 goes to object+$4B0 (X), D2 to +$4B4
  (Y), D3 to +$4B8 (Z), each ADDED, each via IntToFixed. It accumulates.
  -------------------------------------------------------------------------- }
procedure ObjTranslate(AObj : PObj; DX_, DY_, DZ_ : Integer);
var
  { P IS AT [BP-5], WHICH IS ODD, AND A FOUR-BYTE POINTER DECLARED FIRST WOULD
    BE AT [BP-4]. So one byte is declared ahead of it and never touched: the
    frame is ENTER $06 -- 1 + 4 = 5, rounded to 6 -- and 12c5:03ad stores DI at
    [BP-5] with 12c5:03b0 storing ES at [BP-3]. An earlier note here blamed the
    odd offset on the unit's A-minus switch; alignment does not shift a pointer to an odd
    address, it only stops one being padded to an even one. }
  Spare : Byte;                           { [BP-$1], never touched }
begin
  { A `with`, AND NOT A DECLARED POINTER, and two bytes separate them. Both
    spellings put a four-byte address at [BP-5] and both give ENTER $06, so the
    frame cannot tell them apart -- the LOAD can. 12c5:03a9 is

        ADD  DI, $4B0        adjust the pointer LES already put in DI
        MOV  [BP-5], DI      and store DI and ES as they stand
        MOV  [BP-3], ES

    which is a `with` capturing the record's address in place. `P := @AObj^.Pos`
    with P a declared pointer has to produce the address as a VALUE, so it
    emits LEA AX, ES:[DI+$4B0] / MOV DX, ES and stores AX and DX instead --
    same four bytes at the same offset, two bytes longer, and it was the last
    difference in this segment.

    The Spare byte above is still needed: a `with` temp alone would sit at
    [BP-4]. }
  with AObj^.Pos do
  begin
    { The ORDER of the operands is visible here: 12c5:03b6 calls IntToFixed and
      then does ADD AX,ES:[DI], so the call is the LEFT operand and the field
      is added to its result. Written the other way round the compiler loads
      the field first and the two disagree. }
    X := IntToFixed(DX_) + X;
    Y := IntToFixed(DY_) + Y;
    Z := IntToFixed(DZ_) + Z;
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
procedure SortAll(Arr : PScrArr);
{ 12c5:0190 -- SORT-ONLY, and it takes the array BY POINTER. Ghidra's
  decompilation of this address is two DepthSort calls and a return, nothing
  else, so the drawing loops below it belong to RenderObject and not here.
  12c5:0621 calls it as MOV DI,$A5F6 / PUSH DS / PUSH DI / CALL 0x190, which
  for a near call puts the offset at [BP+4] and the segment at [BP+6].

  DepthSort IS NESTED INSIDE IT, and that is the whole point: 12c5:0024 is
  MOV DI,[BP+4] and 0027 is LES DI, SS:[DI+4] -- a static link followed to
  this routine's Pointer parameter. Its own layout is [BP+8] = Lo, [BP+6] =
  Hi, [BP+4] = the link, and RET 6 accounts for two Integers plus the link.
  Top-level with a unit-level Scr, none of its 292 bytes lined up and thirteen
  further spans downstream of it did not either. }
  procedure DepthSort(Lo, Hi : Integer);
  var
    I, J, P : Integer;      { [BP-2], [BP-4], [BP-6] }
    T       : TScreenPt;    { [BP-0C]..[BP-07] -- the swap temp }
    { TWO MORE BYTES, DECLARED AND NEVER READ. The frame is ENTER $0E and the
      four above it reach only $0C; nothing in the routine touches [BP-0E] or
      [BP-0D]. Omitting them left the prologue one byte wrong and that was the
      ONLY byte wrong in the first 64 -- everything else matched once the
      routine was nested. }
    Unread  : Integer;      { [BP-0E] }
  begin
    I := Lo;  J := Hi;
    P := Arr^[(Lo + Hi) div 2].D;
    repeat
      while Arr^[I].D < P do I := I + 1;   { 12c5:0051, an ASSIGNMENT }
      while Arr^[J].D > P do J := J - 1;   { not Dec: see below }
      if I <= J then
      begin
        if Arr^[I].D <> Arr^[J].D then
        begin
          T := Arr^[I];  Arr^[I] := Arr^[J];  Arr^[J] := T;
        end;
        { ASSIGNMENTS, NOT Inc AND Dec. 12c5:0051 is MOV AX,[BP-2] / INC AX /
        MOV [BP-2],AX -- seven bytes -- where Inc(I) is a three-byte INC WORD
        PTR. Ghidra reads the same statements as `local = local + 1`. Four
        sites: the two while bodies and these two. }
      I := I + 1;  J := J - 1;
      end;
    until I > J;
    if Lo < J then DepthSort(Lo, J);
    if I < Hi then DepthSort(I, Hi);
  end;
begin
  DepthSort(1, PtCount);                          { 12c5:0193 }
  DepthSort(PtCount + 1, PtCount * 2);            { 12c5:01a1 }
end;

{ --------------------------------------------------------------------------
  12c5:052a -- the point sprite. HAND ASSEMBLER, transcribed verbatim.

  IT IS ASSEMBLER AND THE PROLOGUE IS HOW YOU KNOW, twice over. 12c5:052a is
  PUSH BP / MOV BP,SP and NOTHING ELSE -- no ENTER, so no locals at all -- while
  ours declared seven and opened ENTER $02 after Turbo Pascal had folded most of
  them into registers. A routine that clips a sprite, walks two nested loops and
  swaps DS cannot be written in Pascal with no locals; it can be written in
  assembler with none, because the values live in registers.

  And the body is unmistakable once read: LODSB and STOSB for a byte at a time,
  DEC CL / JNE for the inner loop, MUL CX to skip whole rows, and DS pointed at
  the sprite so the source needs no segment override. Turbo Pascal emits none of
  those for this shape.

  THE REGISTERS, because the transcription is unreadable without them:

      ES:DI   destination, and DS:SI the sprite -- swapped at 12c5:0573
      CX      the sprite's width, from its own first byte
      DX      the rows still to draw, from its second
      BX      first the row, then the width again as the row-step correction
      CH/CL   the inner counter, reloaded from CH at the top of every row

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
{ @asm 001 12c5:052a +0 DrawPoint }
procedure DrawPoint(Src : Pointer; X, Y : Integer; Segment : Word); assembler;
asm
        PUSH    DS                      { 12c5:052d                          }
        LES     DI, Src                 { 052e  ES:DI := the sprite          }
        XOR     DX, DX                  { 0531                               }
        XOR     CX, CX                  { 0533                               }
        MOV     DL, ES:[DI+1]           { 0535  DX := height                 }
        XOR     CH, CH                  { 0539                               }
        MOV     CL, ES:[DI]             { 053b  CX := width                  }
        ADD     DI, 2                   { 053e  past the two size bytes      }
        MOV     SI, DI                  { 0541  SI := the first pixel        }
        MOV     BX, Y                   { 0543                               }
        XOR     AX, AX                  { 0546                               }
        SUB     AX, BX                  { 0548  AX := -Y                     }
        JLE     @@NoTopClip             { 054a                               }
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
        SUB     AX, BX                  { 055f                               }
        JLE     @@Done                  { 0561  wholly below it              }
        CMP     AX, DX                  { 0563                               }
        JGE     @@NoBotClip             { 0565                               }
        INC     AX                      { 0567  ONE MORE ROW than the gap,   }
        MOV     DX, AX                  { 0568    which is what the original }
@@NoBotClip:                            {         does; it is not an error   }
        ADD     BX, BX                  { 056a  BX := Y * 2                  }
        MOV     DI, [BX + OFFSET YOfs]  { 056c  DI := Y * 320                }
        ADD     DI, X                   { 0570                               }
        MOV     AX, ES                  { 0573  DS:SI is now the sprite      }
        MOV     DS, AX                  { 0575                               }
        MOV     AX, Segment             { 0577                               }
        MOV     ES, AX                  { 057a  ES:DI is now the screen      }
        MOV     BX, CX                  { 057c  keep the width for the step  }
        MOV     CH, CL                  { 057e    and for the row reload     }
@@Row:  MOV     CL, CH                  { 0580  <- once per row              }
@@Pixel:
        LODSB                           { 0582  one sprite byte              }
        OR      AL, AL                  { 0583                               }
        JNE     @@Opaque                { 0585                               }
        INC     DI                      { 0587  transparent: step over it    }
        DEC     CL                      { 0588                               }
        JNE     @@Pixel                 { 058a                               }
        JMP     @@NextRow               { 058c                               }
@@Opaque:
        STOSB                           { 058e                               }
        DEC     CL                      { 058f                               }
        JNE     @@Pixel                 { 0591                               }
@@NextRow:
        ADD     DI, 320                 { 0593  down one screen row...       }
        SUB     DI, BX                  { 0597    and back by the width      }
        DEC     DL                      { 0599                               }
        JNE     @@Row                   { 059b                               }
@@Done: POP     DS                      { 059d                               }
end;

{ --------------------------------------------------------------------------
  12c5:05a2 -- the REFLECTION blit. HAND ASSEMBLER, transcribed verbatim.

  The same routine as DrawPoint above, byte for byte, with exactly two changes
  and both of them are visible in the listing:

    * the clip is the OTHER SIDE of the mirror line. DrawPoint drops rows above
      Y = 0 and stops at 133; this drops rows above 133 and stops at 199, so the
      two together tile the screen at the horizon.
    * 12c5:0607 is ADD AL,$10 in front of the STOSB -- every pixel written
      sixteen entries further along the palette, which is what dims the
      reflection. Nothing else about the pixel loop differs.

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
{ @asm 001 12c5:05a2 +0 DrawReflection }
procedure DrawReflection(Src : Pointer; X, Y : Integer; Segment : Word); assembler;
asm
        PUSH    DS                      { 12c5:05a5                          }
        LES     DI, Src                 { 05a6                               }
        XOR     DX, DX                  { 05a9                               }
        XOR     CX, CX                  { 05ab                               }
        MOV     DL, ES:[DI+1]           { 05ad  DX := height                 }
        XOR     CH, CH                  { 05b1                               }
        MOV     CL, ES:[DI]             { 05b3  CX := width                  }
        ADD     DI, 2                   { 05b6                               }
        MOV     SI, DI                  { 05b9                               }
        MOV     BX, Y                   { 05bb                               }
        MOV     AX, Horizon             { 05be  133 -- the clip is from HERE }
        SUB     AX, BX                  { 05c1    downwards, not from zero   }
        JLE     @@NoTopClip             { 05c3                               }
        CMP     AX, DX                  { 05c5                               }
        JGE     @@Done                  { 05c7                               }
        SUB     DX, AX                  { 05c9                               }
        ADD     BX, AX                  { 05cb                               }
        MOV     DI, DX                  { 05cd  park the row count round MUL }
        MUL     CX                      { 05cf                               }
        MOV     DX, DI                  { 05d1                               }
        ADD     SI, AX                  { 05d3                               }
@@NoTopClip:
        MOV     AX, 199                 { 05d5  the bottom of the screen     }
        SUB     AX, BX                  { 05d8                               }
        JLE     @@Done                  { 05da                               }
        CMP     AX, DX                  { 05dc                               }
        JGE     @@NoBotClip             { 05de                               }
        INC     AX                      { 05e0                               }
        MOV     DX, AX                  { 05e1                               }
@@NoBotClip:
        ADD     BX, BX                  { 05e3                               }
        MOV     DI, [BX + OFFSET YOfs]  { 05e5                               }
        ADD     DI, X                   { 05e9                               }
        MOV     AX, ES                  { 05ec                               }
        MOV     DS, AX                  { 05ee                               }
        MOV     AX, Segment             { 05f0                               }
        MOV     ES, AX                  { 05f3                               }
        MOV     BX, CX                  { 05f5                               }
        MOV     CH, CL                  { 05f7                               }
@@Row:  MOV     CL, CH                  { 05f9                               }
@@Pixel:
        LODSB                           { 05fb                               }
        OR      AL, AL                  { 05fc                               }
        JNE     @@Opaque                { 05fe                               }
        INC     DI                      { 0600                               }
        DEC     CL                      { 0601                               }
        JNE     @@Pixel                 { 0603                               }
        JMP     @@NextRow               { 0605                               }
@@Opaque:
        ADD     AL, 10h                 { 0607  sixteen along the palette    }
        STOSB                           { 0609                               }
        DEC     CL                      { 060a                               }
        JNE     @@Pixel                 { 060c                               }
@@NextRow:
        ADD     DI, 320                 { 060e                               }
        SUB     DI, BX                  { 0612                               }
        DEC     DL                      { 0614                               }
        JNE     @@Row                   { 0616                               }
@@Done: POP     DS                      { 0618                               }
end;

{ [transcribed] 12c5:061d -- sort both halves, draw the reflections, then the
  points with their Y pulled up seven rows (12c5:06ab). }
procedure RenderObject;
var
  { A BYTE, NOT AN INTEGER. 12c5:0688 is MOV BYTE PTR [BP-1],AL and 068d is
    INC BYTE PTR [BP-1], so the counter is one byte; and the for limit's
    temporary is a byte too -- 12c5:067b loads PtCount into [BP-5] and 0683
    compares AL against that slot. ENTER $0A then decomposes as the counter,
    the temporary, and the four bytes a `with` gets for the record's address. }
  { AND FOUR MORE BYTES THAT NOTHING READS. The note above says ENTER $0A and
    then accounts for SIX -- one counter, one byte of for-limit temporary, four
    for the `with` -- which is its own refutation; prologue.py read ours as $06
    against the original's $0A. Both loops use a `with` and Turbo Pascal reuses
    the one hidden slot for sequential (non-nested) ones, so the second `with`
    is not where the four go. Nothing below the address pair at [BP-$9] is
    referenced at any width. }
  I     : Byte;                                   { [BP-$1] }
  Spare : LongInt;                                { never read }
begin
  SortAll(@Scr);                                  { 12c5:0626 }

  { A `with` IN BOTH LOOPS, and the two bytes at 12c5:06a3 say so: PUSH DS /
    POP ES puts the segment in ES before the address pair is stored at [BP-9],
    and every field then goes through LES DI,[BP-9]. Naming Scr[I] at each
    field recomputes I * 6 and the fold for every one of them. }
  for I := PtCount + 1 to PtCount * 2 do
    with Scr[I] do
      DrawReflection(@ObjMeta, X, Y, WorkSeg);    { 12c5:0670 }
  for I := 1 to PtCount do
    with Scr[I] do
    begin
      Dec(Y, 7);                                  { 12c5:06ab, SUB on memory }
      DrawPoint(@ObjMeta, X, Y, WorkSeg);         { 12c5:06c3 }
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
    Copy32(VirtScrSeg, WorkSeg);        { 12c5:0782 -- the clean gradient }
    ObjTransformAll(@Obj, Angle, Angle, Angle);   { 12c5:0796 }
    RenderObject;                       { 12c5:0799 }
    Copy32(WorkSeg, $A000);             { 12c5:07a3 }

    Inc(Angle, VectorStep);
    if Angle > VectorWrap then Angle := 0;

    { THE THREE ARE COMPUTED INTO VARIABLES, THEN THE ANGLES ADVANCE, THEN
      THE CALL. Passing the Round expressions as arguments is the same
      arithmetic in the wrong order: the original has both increments between
      the last Round and the call, so Local is already advanced by the time
      ObjTranslate runs but the values it passes were computed before. }
    Dx := Round(Cos(Local      * Pi / 180.0) *   5.0);   { 12c5:07b9 }
    Dy := Round(Sin(OrbitAngle * Pi / 180.0) *  20.0);   { 12c5:07df }
    Dz := Round(Sin(Local      * Pi / 180.0) * 500.0);   { 12c5:0806 }

    { 12c5:082b and 12c5:0834 are MOV AX / ADD AX,imm / MOV back -- the
      assignment form, not Inc's ADD [mem],reg. Six bytes each. }
    Local      := Local + LocalStep;                     { 12c5:082b }
    OrbitAngle := OrbitAngle + OrbitStep;                { 12c5:0834 }

    ObjTranslate(@Obj, Dx, Dy, Dz);                      { 12c5:084e }

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
  { ENTER $A is ten bytes and only TWO of them are declared. The frame reads as
    three Integers and a Pointer -- which is what this said -- and the BODY
    refutes that:

      [BP-$06] is the for-loop's LIMIT temp. 12c5:087d is
      MOV AX,[$AAC8] / DEC AX / MOV [BP-6],AX -- PtCount minus one, evaluated
      once before the loop, which is what a `for` does with a non-constant
      limit. It is not a declared Word.

      [BP-$0A] is a DECLARED four-byte POINTER to the point being filled.
      12c5:0897 computes IMUL DI,AX,0C / ADD DI,$A0FA, stores DI and ES into
      it, and then every field write goes LES DI,[BP-$0A] / MOV ES:[DI],AX.
      The record's address is taken ONCE, which three separate
      `Obj.Pt[I].X :=` statements do not do.

    AND THERE IS NO Src POINTER AT ALL. 12c5:08b3 is
    PUSH WORD PTR [DI+$1A8] -- an ABSOLUTE displacement, so the coordinate
    table is named directly. A table reached through a pointer variable would
    load the pointer into a register first. `Src := @VecGlobe` was inferred to
    explain a slot that turns out to be a compiler temp. }
  I      : Integer;                       { [BP-$02] }
  W      : Word;                          { [BP-$04] -- the slide-out counter }
  { AND THAT IS THE WHOLE VAR BLOCK: two words, and ENTER $0A is 4 declared plus
    6 of COMPILER TEMPORARIES. The frame's own ORDER proves the point pointer is
    not declared. Temps are allocated below every declared local, so a declared
    P would sit at [BP-$08] with the for-limit temp beneath it at [BP-$0A]. The
    original has them the other way round -- 12c5:087d writes the limit to
    [BP-$06] and 12c5:08a0 writes the pointer to [BP-$0A] -- which only happens
    if BOTH are temps, taken in the order the statements need them: the loop's
    limit first, then the record address.

    So the pointer is a `with`'s hidden slot, not a variable. The note that used
    to be here argued P was declared because "the record's address is taken
    ONCE, which three separate `Obj.Pt[I].X :=` statements do not do" -- true,
    and a `with` takes it once as well, for four bytes, without being named.
    A Spare was then added to push P down to the measured offset, which made the
    frame $0E against the original's $0A. }
begin
  { INLINE, both times. 12c5:0874 sets PtCount from an immediate and then runs
    the point loop in Vector_Run's own frame -- there is no call.

    THE LOOP IS ZERO-BASED, AND ONLY THE Pt SUBSCRIPT CARRIES THE +1. 12c5:0893
    is MOV AX,[BP-2] / INC AX / IMUL DI,AX,0C for the destination record, so the
    counter is one less than the point number there. But 12c5:08a6 scales the
    SAME counter by six for the source table with NO increment, and 12c5:08b3 is
    PUSH WORD PTR [DI+$1A8] -- and $01A8 is where VecGlobe BEGINS. A folded
    displacement equal to the array's own base means the first subscript
    contributes nothing to the fold, so its LOW BOUND IS ZERO and the source is
    `VecGlobe[I, n]`.

    This note used to read "both subscripts carry the +1 ... folding to
    base + I*6", which is arithmetically true of a one-based table and produced
    the wrong code: `VecGlobe[I + 1, n]` folds to $1A2, one 6-byte element low,
    and Turbo Pascal pays for the difference with an INC AX on every point. The
    two spellings reach the same element and only one of them is what shipped.
    The bound is set in tools/emit_pascal_data2.py, which generates the table. }
  PtCount := GlobePoints;                        { 12c5:0874 }
  for I := 0 to PtCount - 1 do
    with Obj.Pt[I + 1] do                        { 12c5:08a0 }
    begin
      X := IntToFixed(VecGlobe[I * 3]);          { 12c5:08b3 }
      Y := IntToFixed(VecGlobe[I * 3 + 1]);
      Z := IntToFixed(VecGlobe[I * 3 + 2]);
    end;


  { 12c5:0918 stores an ALREADY-ZERO AX twice with no call before it, so X is
    a direct zero. Y and Z below really do go through IntToFixed -- 12c5:091e
    pushes -70 and 12c5:092c pushes 1600. }
  Obj.Pos.X := 0;                              { 12c5:0918 }
  Obj.Pos.Y := IntToFixed(-70);                { 12c5:091e }
  Obj.Pos.Z := IntToFixed(1600);               { 12c5:092c }

  { 12c5:093b -- Scale := (ScreenWidth / 2.0) * 10.0, as 16.16.
    CS:$0868 = 2.0, CS:$086C = 10.0. }
  { 12c5:0947 -- RealToFixed, and MViewW is a WORD here where P1S4's is an
    Integer. The spill is the difference: `MOV [BP-8],AX / MOV [BP-6],DX` then
    FILD DWORD on the LongInt, which is how a Word reaches the x87. P1S4 does
    FILD WORD straight off the variable. Same expression, two declarations. }
  MScale := RealToFixed(MViewW / 2.0 * 10.0);

  OrbitAngle := -2042;                         { 12c5:096a }
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
    { LONGHAND: 12c5:0a4e is MOV AX,[BP-4] / ADD AX,$280 / MOV [BP-4],AX --
      loaded, added in the register, stored back -- where `Inc` on a local emits
      ADD WORD PTR in place. }
    W := W + 640;
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
  { ENTER $482 IS 1,154 BYTES AND EVERY PART OF IT IS PINNED, because Pal's
    base is the one local address the routine names. Only two slots are
    referenced in the whole routine: [BP-1], which 12c5:0495 sets to $64 and
    12c5:049b INCs -- a BYTE, and the counter of `for I := 100 to 255` -- and
    [BP-$481], which 12c5:045b and 12c5:046d LEA for the BlockRead and then for
    SetPalette768.

    First declared is nearest BP, so I is first at [BP-1]. Working forward:
    1 + 256 + 128 + 768 = 1,153, which puts Pal's base at exactly [BP-$481].
    That is the check -- no other arrangement of those sizes lands there, and
    ENTER rounds 1,153 up to the even 1,154.

    So there are 384 bytes here that nothing reads. Their SIZES are forced by
    Pal's address; their TYPES are a guess, and two strings are chosen because
    P1S4's loader has an unreferenced String[127] in the same position and a
    filename buffer is the obvious thing for a loader to declare and then take
    from a constant instead. }
  I      : Byte;                        { [BP-1] }
  Spare1 : String;                      { [BP-$101], 256, never read }
  Spare2 : String[127];                 { [BP-$181], 128, never read }
  { The palette IS a local -- 12c5:046d LEAs [BP-$481] straight into
    SetPalette768 (1491:01c2) and nothing keeps a copy. }
  Pal    : array[0..767] of Byte;       { [BP-$481] }
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
var
  { 12c5:0a60 opens ENTER 2 and the routine references no local at all in its
    forty bytes, so this is two bytes declared and never read. It has to be
    here or the frame is absent where the original has one. }
  Spare : Integer;
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

{ AN EMPTY INITIALISATION SECTION, AND THE ORIGINAL GIVES EVERY UNIT ONE. 12c5:0ac1
  is PUSH BP / MOV BP,SP / LEAVE / RETF -- five bytes, doing nothing -- and the
  main body opens with a chain of far calls that runs one per unit. The chain is
  twelve calls at 1000:0000..003b in the 1994 binary and was SEVEN in ours,
  because the five scene units ended `end.` with no `begin`, so TP7 emitted no
  section and the chain had nothing to call. Twenty-five bytes of stub and
  twenty-five of chain, and the body started twenty-five bytes early.

  Without the `begin` below this unit does not appear in that chain at all. }
begin
end.
