{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 4.

  Transcribed from the disassembly of segment 1107 and 12b2, not inferred.
  Every routine below carries the address it was read from.

  WHAT THE SCENE ACTUALLY IS
  --------------------------
  A field of 144 balls arranged as a flat 18 x 8 grid, tumbling in 3-D over a
  scrolling starfield, with the message written across the grid one column at
  a time -- the letters flow leftwards through the balls because the LIT flag
  marches along each row's trail while the coordinates stay put.

  An earlier reconstruction had this as "rotating 3-D text" built from glyph
  outlines. It is not. Banner_BuildPoints (1107:07a2) copies the same literal
  string eight times --

      CS:$078B  'OOOOOOOOOOOOOOOOOO'   18 characters

  -- into eight row buffers at DS:$6A33 stride $100, then walks them and emits
  one point per character. Eight rows of eighteen is exactly the 144.
  =========================================================================== }

{$N+}   { Demo_Scene4's scale arithmetic is x87 -- 1107:097b FILD/FDIV/FMUL. }
{$G+}   { 286 instructions: REP OUTSB in SetPalette768 (1107:0011). The
          original targets 386 and above. }

unit P1S4;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

interface

procedure Scene4;

implementation

uses VGA, Crt, DemoVT, FixMath;

{ --------------------------------------------------------------------------
  1107:0000 -- SetPalette768(P). HAND ASSEMBLER, verbatim.

  Byte for byte VGA.SetPalette768 -- 1436:0083 in part 002, 11e3:0230 in
  part 004. Part 004 scene 4 keeps its own copy because it is a separate
  unit; the shared one is stripped from this part.
  point the DAC write index at colour 0 and let REP OUTSB stream all 768
  components at it, the hardware auto-incrementing between entries.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := 0;
      for I := 0 to 767 do Port[$3C9] := TPal768(P^)[I];

  Scene 4 is the only part 001 scene with its own copy; the others go through
  VGA.SetPalette.
  -------------------------------------------------------------------------- }
{ @asm 001 1107:0000 }
procedure SetPalette768(P : Pointer); assembler;
asm
  PUSH DS                 { DS is about to point at the caller's buffer    }
  LDS  SI, P              { DS:SI := the 768-byte palette                  }
  MOV  DX, $3C8           { the DAC WRITE index register                   }
  MOV  AL, 0              { start at colour 0                              }
  OUT  DX, AL             { select it -- the DAC auto-increments from here }
  INC  DX                 { DX := $3C9, the DAC data register              }
  MOV  CX, $300           { 768 bytes = 256 entries of R, G, B             }
  REP  OUTSB              { write them all out from DS:SI                  }
  POP  DS                 { restore our data segment                       }
end;

const
  TrailRows  = 8;
  TrailLen   = 18;
  TrailCount = TrailRows * TrailLen;        { 144 }
  LastEntry  = TrailCount + 1;              { 1107:0446 runs 1..145 }
  BlobW      = 7;
  BlobH      = 7;
  BlobPixels = BlobW * BlobH;               { 49 = $31 }
  StarCount  = 90;                          { $5A }
  FontChars  = 59;                          { chars $20..$5A }
  FontBias   = 32;                          { see DrawStep }
  AngleWrap  = 3600;                        { angles are TENTHS of a degree }
  BannerStep = 60;                          { $3C -- 6.0 degrees per column }
  GridPoint  = 'OOOOOOOOOOOOOOOOOO';        { CS:$078B }
  MarkerA    = '*';                         { CS:$079E }
  MarkerB    = 'O';                         { CS:$07A0 }

  { The clip box the blitter reads from DS:$000C..$0013. }
  { DS:$000C..$0013 -- INITIALISED DATA, read straight out of the image:
    00 00  C7 00  00 00  3F 01, the full 320 x 200 screen. The blit reads all
    four from DGROUP, so they are typed constants rather than plain consts: a
    plain const folds into the instruction and stops matching. The order is
    the binary's -- top, bottom, left, right. }
  ClipTop    : Integer = 0;        { DS:$000C }
  ClipBottom : Integer = 199;      { DS:$000E }
  ClipLeft   : Integer = 0;        { DS:$0010 }
  ClipRight  : Integer = 319;      { DS:$0012 }

type
  { 13 bytes in the original: three 16.16 fixed values and a flag byte.
    Entry 0 is not a point -- it is the object's TRANSLATION vector, which is
    why 1107:0446 adds it to every rotated point and never rotates it. }
  TTrail = record
    X, Y, Z : LongInt;          { 16.16 fixed point -- hence 13 bytes }
    Flag    : Byte;
  end;

  { Transform takes the whole trail BY POINTER, so the array needs a name.
    1107:044a is LES DI,[BP+0A] -- a far pointer parameter -- and 1107:048d
    indexes it as base + I * 13 with no adjustment, which is a ZERO-based
    array. }
  TTrailArr = array[0..LastEntry] of TTrail;
  PTrailArr = ^TTrailArr;

  { ShiftTrails is handed @Trail[1] rather than @Trail, so it needs a ONE-based
    view of the same records: 1107:06aa is MOV DI,$5BD9, which is Trail plus one
    record, and 1107:05ce reads ES:[DI-1] after DI += K*13 -- the low bound and
    the Flag field's offset 12 folded together into the minus one. }
  TTrail1   = array[1..LastEntry] of TTrail;
  PTrail1   = ^TTrail1;

  { 7 bytes in the original: X, Y, D as words and the flag as a byte. }
  TOut = record
    X, Y, D : Integer;
    Flag    : Byte;
  end;

  { The output array is passed by pointer too, and ONE-based: 1107:03fd is
    IMUL AX,[BP-2],7 / LES DI,[BP+4] / ADD DI,AX / CMP BYTE PTR ES:[DI-1] --
    the minus one is the low bound folded into the displacement, so P^[I]
    lands at P + (I-1)*7 and the caller passes @Outp[1]. }
  TOutArr = array[1..LastEntry] of TOut;
  POutArr = ^TOutArr;

  { 51 bytes in the original ($33): a two-byte (W, H) header the blitter reads
    out of the sprite itself, then 49 pixels. }
  TBlob = record
    W, H : Byte;
    Pix  : array[1..BlobPixels] of Byte;
  end;

  { 9 bytes in the original. }
  TStar = record
    X, Y, DX, Spare : Integer;
    Colour          : Byte;
  end;

  { THE LOW BOUND IS 32, NOT 0, and the subscript arithmetic proves it.
    1107:0669..0678 is MOV AL,[BP+DI-$100] / XOR AH,AH / SHL DI,6 / ADD DI,DX /
    ADD DI,CX / CMP BYTE PTR [DI+$6A2A] -- it multiplies the RAW Ord by 64 with
    no subtraction anywhere, and the displacement $6A2A absorbs the bias. Font
    is at $7233, so the folded amount is $809 = 2,057 = 32 * 64 + 9: thirty-two
    glyphs of bias plus the nine that the two one-based dimensions fold. A low
    bound of 0 would need a SUB the original does not have. }
  TFont = array[FontBias..FontBias + FontChars - 1, 1..8, 1..8] of Byte;

var
  { DS:$5AD2 -- unit-level, see Load. THIS ADDRESS IS THE MEASUREMENT THAT SAYS
    part 001 is data-blocked, and it is worth writing down because every span in
    segment 1107 turns on it. The routine's CODE now matches -- same calls, same
    order, no I/O check -- and the two operands differ: the original pushes
    DS:$5AD2 for the file and DS:$5B6A for the buffer, this build $0952 and
    $354C. The two gaps are 20,864 and 9,758, and their being DIFFERENT rules
    out a uniform shift: it is the sizes of what comes before, not a single
    missing block.

    Where it comes from is partly mapped. This part's DGROUP order is right --
    reverse of P1Intro's uses clause puts P1S5 first, and P1S5's constants are
    at $001C and $01A8 exactly as recorded. But P1S5's VARIABLES are at
    $A5B6..$AB58 in the original, and nothing declared in that unit accounts for
    the distance. The load image is 1,536 bytes BIGGER here than the original's
    while the BSS is 23,520 bytes SMALLER, so there is initialised data here
    that belongs in BSS and a large block of variables that is missing
    altogether. }
  F : file;
  { DS:$5BCC -- entry 0 is the translation, 1..144 are the grid. }
  Trail : array[0..LastEntry] of TTrail;
  { DS:$632F, stride 7 }
  Outp  : array[0..LastEntry] of TOut;
  { DS:$80C2, stride $33 }
  Blob  : array[1..LastEntry] of TBlob;
  { DS:$9DDB, stride 9 }
  Star  : array[1..StarCount] of TStar;

  { DS:$7233, 3,776 bytes = 59 glyphs of 8 x 8, AND IT IS INLINE IN DGROUP,
    not on the heap. It was declared here as a pointer with New and Dispose
    around it, which put four bytes where the original has 3,776 and moved
    every variable after it -- including the whole of P1S5's block, which sits
    above this one.

    $7233 AND NOT $6A2A, and the difference is worth writing down because this
    comment said $6A2A for one session and that was wrong. $6A2A is the FOLDED
    base of ShowString's subscript, not the array's address: ShowString's own
    note below works it out as $7233 - $809, where $809 is 2,057 = 32 * 64 + 9,
    the character bias of 32 glyphs plus the nine that array[0..58, 1..8, 1..8]
    folds for its low bounds. A folded displacement is never an address.

    With $7233 the unit tiles: the row buffers at $6A33 take 2,048 bytes and
    end exactly here. }
  Font  : TFont;
  { DS:$5B6A and DS:$5B9B, 49 bytes each }
  ProfileA, ProfileB : array[1..BlobPixels] of Byte;
  { DS:$672D }
  Pal   : array[0..767] of Byte;
  { DS:$6A2D, $6A2F, $6A31 -- BuildPoints' THREE COUNTERS ARE UNIT-LEVEL, and
    that is what leaves the routine with no declared locals at all. The
    original reads and writes them absolutely: 1107:0848 is
    MOV DI,[$6A2D] for the row, 1107:087f pushes [$6A2F] for the column, and
    1107:08d0 is IMUL DI,[$6A31],0D for the trail index.

    They also tile: Pal at $672D is 768 bytes and ends exactly here, and these
    six bytes end exactly at $6A33 where the row buffers begin. }
  Row   : Integer;                                { DS:$6A2D }
  Col   : Integer;                                { DS:$6A2F }
  Idx   : Integer;                                { DS:$6A31 }
  { DS:$6A33, stride $100 -- THE EIGHT ROW BUFFERS, and they are UNIT-LEVEL.
    They were declared as locals inside BuildPoints, which is eight 256-byte
    strings on the stack and 2,048 bytes of DGROUP the original has and we did
    not. Two measurements say unit-level: 1107:07ab is MOV DI,$6A33 / PUSH DS,
    which is a DS address and not a frame one, and BuildPoints opens
    ENTER $202 -- 514 bytes, which cannot hold them. }
  Rows  : array[1..TrailRows] of String;            { DS:$6A33 }

{ --------------------------------------------------------------------------
  THE SHARED 386 MATHS MODULE.

  SinCos, Rotate and Project are 386 code and cannot be written in Turbo
  Pascal's built-in assembler, which stops at the 286. They live in
  src/asm/DEMOMATH.ASM, are assembled by TASM and linked in here with the $L directive --
  which is what the original does: 1107:1804, 1107:18B6 and 1107:1A04 are the
  same code as scene 5's and part 002 scene 2's, once per unit.

  The nine names below are the module's EXTRNs, so they have to be declared
  BEFORE the $L directive and spelled exactly this way.
  -------------------------------------------------------------------------- }
  { DS:$5B52/$5B56, $5B5A/$5B5E, $5B62/$5B66 -- cos then sin, per axis }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  { DS:$0018 -- the projection scale, 16.16, set by Demo_Scene4 }
  MScale : LongInt;
  { DS:$80F3 }
  Angle : Integer;

const
  { DS:$0014 = 320 and DS:$0016 = 200, initialised data. Project halves both,
    so these are the FULL view size and not the centre. }
  MViewW : Integer = 320;   { INTEGER here, not Word: 1107:097b is FILD WORD
                              with no XOR DX,DX spill ahead of it, and a Word in
                              a Real expression is widened through a LongInt
                              spill and FILD DWORD. Part 002's is a Word and does
                              have the spill, so the two units differ. }
  MViewH : Word = 200;

{$L DEMOMATH.OBJ}

{ --------------------------------------------------------------------------
  1107:1804 -- SinCos(Angle : Integer; var C, S : LongInt)

  The angle is in tenths of a degree, wrapped into 0..3600. The table is 901
  entries of 16.16 COSINE and one quadrant of it serves both functions, read
  forwards or backwards with the signs flipped per quadrant. The FIRST var
  parameter receives the COSINE -- checked against 1107:18b6, which needs
  DS:$5B52 in the cosine position for the matrix to come out orthogonal.

  1107:18b6 -- Rotate(var X, Y, Z : LongInt)

  Three concatenated 2-D rotations in 16.16, using the six values SinCos left
  in DS:$5B52..$5B69:

      about X, by A1       Y1 := Y*C1 + Z*S1        Z1 := Z*C1 - Y*S1
      about Y, by A2       X2 := X*C2 - Z1*S2       Z2 := Z1*C2 + X*S2
      about Z, by A3       X3 := X2*C3 + Y1*S3      Y3 := Y1*C3 - X2*S3

  1107:1a04 -- Project(var X, Y, Z : LongInt)

      Sx := Round(X/Z * Scale) + MViewW div 2
      Sy := MViewH div 2 - Round(Y/Z * Scale)

  All three are in src/asm/DEMOMATH.ASM, commented there. An earlier version
  of this file had them as Pascal over Reals, which is a different program:
  the original's multiply is 32x32->64 taking the MIDDLE 32 bits, and its
  divide builds a 48-bit dividend so the quotient comes out 16.16.
  -------------------------------------------------------------------------- }
procedure SinCos(A : Integer; var C, S : LongInt);      external; { 1107:1804 }
procedure RotatePoint(var X, Y, Z : LongInt);           external; { 1107:18B6 }
procedure Project(var X, Y, Z : LongInt);               external; { 1107:1A04 }

{ IntToFixed and FixedToInt come from FixMath (segment 1483) -- this scene
  had local copies of both. 1107:052E calls 1483:0099, the ROUNDING one. }

{ --------------------------------------------------------------------------
  1107:0446 -- Transform(Base; A1, A2, A3)

  For entries 1..145: copy the 13-byte record out, rotate it, add the
  TRANSLATION held in entry 0, project, and write the 7-byte output record.

  Note what is NOT rotated: entry 0. The loop starts at 1, and the add at
  1107:04bf reads ES:[DI], ES:[DI+4], ES:[DI+8] with DI still pointing at the
  base of the array -- entry 0. It is the object position, not a point.
  -------------------------------------------------------------------------- }
procedure Transform(Base : Pointer; A1, A2, A3 : Integer);
var
  { TWENTY BYTES, AND THE EARLIER READING OF THEM WAS WRONG. It said a Byte
    then three LongInts then three Integers, because every referenced offset
    below the first is odd and a one-byte local is the usual cause. The frame
    was right and the parts were not: [BP-2] is written with MOV WORD PTR at
    1107:0483, so the counter is an INTEGER, and the odd offsets come from a
    THIRTEEN-byte record sitting after it.

    2 + 13 + 4 = 19, rounded to 20:

      [BP-2]     I, an Integer -- MOV WORD PTR [BP-2],1 and INC WORD PTR
      [BP-$0F]   a TTrail, 13 bytes, copied in whole by Move at 1107:049f.
                 Its three LongInt fields are at [BP-$0F], [BP-$0B] and
                 [BP-7], which is exactly what 1107:04a4..04b3 pushes to
                 RotatePoint, and the Flag byte is the odd [BP-3].
      [BP-$13]   a four-byte pointer, loaded from the parameter at 1107:044a.

    THE RECORD IS COPIED, NOT READ FIELD BY FIELD. 1107:049f is
    Move(P^[I], T, 13) -- one call -- where this read three fields into three
    LongInt locals. That is why there are no X, Y, Z locals to declare. }
  I : Integer;                          { [BP-2] }
  T : TTrail;                           { [BP-$0F], the working copy }
  P : PTrailArr;                        { [BP-$13], from Base }
begin
  P := Base;                                { 1107:044a }

  SinCos(A1, MCos1, MSin1);                 { -> DS:$5B52, $5B56 }
  SinCos(A2, MCos2, MSin2);                 { -> DS:$5B5A, $5B5E }
  SinCos(A3, MCos3, MSin3);                 { -> DS:$5B62, $5B66 }

  for I := 1 to LastEntry do
  begin
    Move(P^[I], T, SizeOf(TTrail));         { 1107:049f, thirteen bytes }
    RotatePoint(T.X, T.Y, T.Z);             { 1107:04b3 }
    { THE TRANSLATION IS READ THROUGH THE POINTER, not from Trail absolutely.
      1107:04bc is LES DI,[BP+0A] -- the parameter again -- and the three adds
      take es:[di], es:[di+4] and es:[di+8], which is element ZERO of whatever
      was passed. Reading Trail[0] by name is the same value and an absolute
      displacement instead of a register indirection. }
    T.X := T.X + P^[0].X;                   { 1107:04bf }
    T.Y := T.Y + P^[0].Y;
    T.Z := T.Z + P^[0].Z;
    Outp[I].D := FixedToInt(T.Z);           { 1107:052e }
    Project(T.X, T.Y, T.Z);
    { both come back zero-extended, so the low word carries the sign }
    Outp[I].X    := Integer(T.X);
    Outp[I].Y    := Integer(T.Y);
    Outp[I].Flag := T.Flag;
  end;
end;

{ --------------------------------------------------------------------------
  1107:0287 -- DepthSort(Lo, Hi), nested inside 1107:03d7

  A Hoare quicksort over the 7-byte output records, keyed on the D field, and
  it sorts DESCENDING: the scan at 1107:02c7 advances while key[i] > pivot.
  Far balls are therefore drawn first and near ones over the top of them.

  This was missing entirely from the earlier reconstruction, so the grid drew
  in index order and the depth cueing was wrong wherever the field folded over
  itself. The records are swapped whole -- three 7-byte Moves via a temporary.
  -------------------------------------------------------------------------- }
procedure SortOutp(Arr : POutArr);
{ 1107:03d7 -- A WRAPPER, and DepthSort is NESTED INSIDE IT. Four bytes of
  parameters and no locals: PUSH 1 / PUSH $90 / PUSH BP / CALL 0x287, and that
  PUSH BP is the STATIC LINK. So the sort reaches the array through this
  routine's pointer parameter rather than naming Outp, and the bounds 1 and 144
  are constants in the wrapper, not in the sort.

  This is the same shape scene 5's SortAll turned out to be, in the same
  binary, and that one was worth 619 bytes. }
  procedure DepthSort(Lo, Hi : Integer);
  var
    I, J : Integer;
    P    : Integer;
    T    : TOut;
  begin
    I := Lo;  J := Hi;
    P := Arr^[(Lo + Hi) div 2].D;
    repeat
      while Arr^[I].D > P do Inc(I);
      while Arr^[J].D < P do Dec(J);
      if I <= J then
      begin
        if Arr^[I].D <> Arr^[J].D then
        begin
          T := Arr^[I];  Arr^[I] := Arr^[J];  Arr^[J] := T;
        end;
        Inc(I);  Dec(J);
      end;
    until I > J;
    if Lo < J then DepthSort(Lo, J);
    if I < Hi then DepthSort(I, Hi);
  end;
begin
  DepthSort(1, TrailCount);                 { 1107:03da, PUSH 1 / PUSH $90 }
end;

{ --------------------------------------------------------------------------
  1107:03e7 -- BuildBlobs(Out)

  Sort by depth first (1107:03d7 calls DepthSort(1, 144)), then give every
  record its sprite according to the flag the sort carried along with it:

      flag <> 0  ->  DS:$5B9B   the lit profile
      flag  = 0  ->  DS:$5B6A   the unlit profile

  49 bytes each, into the 51-byte blob at DS:$80C4 + I*$33 -- past the (W, H)
  header, which Banner_Load already set to 7, 7.
  -------------------------------------------------------------------------- }
procedure BuildBlobs(Arr : POutArr);
var
  { ENTER 2, so one Integer -- 1107:03f3 is MOV WORD PTR [BP-2],1. }
  I : Integer;
begin
  SortOutp(Arr);                            { 1107:03f0, the SAME pointer }
  for I := 1 to LastEntry do
    if Arr^[I].Flag <> 0 then               { 1107:0406 }
      Move(ProfileB, Blob[I].Pix, BlobPixels)
    else
      Move(ProfileA, Blob[I].Pix, BlobPixels);
end;

{ --------------------------------------------------------------------------
  12b2:0000 -- StarInit(C0, C1, C2, Speed)

  Demo_Scene4 pushes 8, 9, 10, 1 in that order, so the three colours are 8, 9
  and 10 and the base speed is 1. Ninety stars, each given a random position
  and one of three depth bands:

      band 0   colour C0   dx := Speed
      band 1   colour C1   dx := Speed * 2
      band 2   colour C2   dx := Speed * 3

  The earlier reconstruction never called this at all, so every star sat at
  (0,0) in colour 0 and the starfield was invisible.
  -------------------------------------------------------------------------- }
procedure StarInit(C0, Ca, Cb, Speed : Byte);
var
  { ENTER 6, and it is a Byte plus a four-byte pointer: 12b2:0009 is
    MOV BYTE PTR [BP-1],1 and 12b2:000f INCs the same byte, so the counter is
    a Byte; 12b2:0020 stores DI and ES into [BP-6] and every field write then
    goes through LES DI,[BP-6]. 1 + 4 = 5, and ENTER rounds it to 6.

    The pointer is the same idiom scene 5's point loops use -- the record's
    address taken once per iteration rather than three subscript computations. }
  I : Byte;                             { [BP-1] }
  P : ^TStar;                           { [BP-6] }
begin
  Randomize;                            { 12b2:0004 }
  for I := 1 to StarCount do
  begin
    P := @Star[I];                      { 12b2:0017, IMUL DI,AX,9 + $9DD2 }
    P^.X     := Random(319);            { 12b2:0026, PUSH $13F }
    P^.Y     := Random(199);            { 12b2:0034, PUSH $C7 }
    P^.Spare := 0;                      { 12b2:0067, XOR AX,AX then store }
    case Random(3) of
      0 : begin P^.Colour := C0;  P^.DX := Speed;     end;
      1 : begin P^.Colour := Ca;  P^.DX := Speed * 2; end;
      2 : begin P^.Colour := Cb;  P^.DX := Speed * 3; end;
    end;
  end;
end;

{ [transcribed] 12b2:00c0 -- StarStep. X := X + DX, wrapping on 0 and 319. }
procedure StarStep;
var
  I, X : Integer;
begin
  for I := 1 to StarCount do
  begin
    X := Star[I].X + Star[I].DX;
    if X < 0 then Inc(X, 319)
    else if X > 319 then Dec(X, 319);
    Star[I].X := X;
  end;
end;

{ --------------------------------------------------------------------------
  12b2:00f1 -- StarDraw(Segment). HAND ASSEMBLER, verbatim.

  Every tell is present. There is no ENTER, only PUSH BP / MOV BP,SP, in a
  segment whose other Pascal routine opens ENTER 6 -- so this one was not
  compiled from Pascal. `MOV BX,0` is two bytes longer than the XOR the code
  generator emits for a zeroed register. The loop is `DEC CX / JNE` against a
  count loaded once with `MOV CX,$5A`, where a Pascal `for` would compare
  against a limit. And the write is a bare STOSB with ES:DI walked by hand.

  It is FAR: 12b2:011d is RETF 2, one Word of parameter.

  BX carries the byte offset into the star array and advances by 9 -- the
  record size -- so the three loads are one displacement apart from the array
  base rather than three subscript computations. DX holds BX across the row
  lookup, because BX is needed as the table index and there is no spare
  register.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 1 to StarCount do
        Mem[Segment : YOfs[Star[I].Y] + Star[I].X] := Star[I].Colour;

  Note the row TABLE, not a multiply: our previous transcription computed
  Y * ScrWidth, which is the same address by different code.
  -------------------------------------------------------------------------- }
procedure StarDraw(Segment : Word); far; assembler;
asm
  MOV  AX, Segment              { which screen -- $A000 or the virtual one   }
  MOV  ES, AX                   { ES:DI addresses the pixel                 }
  MOV  BX, 0                    { byte offset into Star; NOT xor, verbatim   }
  MOV  CX, StarCount            { $5A -- 90 stars, counted down             }
@Star:
  MOV  DX, BX                   { keep the offset; BX is about to be reused  }
  MOV  AL, [BX + OFFSET Star + 8]  { .Colour, offset 8 of the nine bytes     }
  MOV  DI, [BX + OFFSET Star]      { .X, offset 0                            }
  MOV  BX, [BX + OFFSET Star + 2]  { .Y, offset 2 -- BX now the row          }
  SHL  BX, 1                    { * 2, a word index into the row table       }
  ADD  DI, [BX + OFFSET YOfs]   { + YOfs[Y] = Y * 320 -- DS:$AB5A           }
  STOSB                         { one byte, and DI advances (unused)         }
  MOV  BX, DX                   { the offset back                            }
  ADD  BX, 9                    { next star, one record on                   }
  DEC  CX                       { 12b2:0119                                  }
  JNE  @Star                    { 12b2:011a                                  }
end;

{ --------------------------------------------------------------------------
  1107:0199 -- the clipped transparent sprite blit. HAND ASSEMBLER, verbatim,
  and SHARED SOURCE: the routine is src/asm/BLITCLIP.INC, because part 006
  scene 2 compiles the same text at 100f:0000 -- byte for byte, our addresses
  being that unit's plus $199. It sits here, between Banner_Load and
  DrawBlobs, rather than at the head of a segment of its own, which is how we
  know the original shared the SOURCE and let each unit compile its own copy.
  -------------------------------------------------------------------------- }
{ @asm 001 1107:0199 +170 Blit }
{$I BLITCLIP.INC}

{ [transcribed] 1107:0245 -- blit blobs 1..144. Note 145 is transformed and
  given a sprite but never drawn; the loop counter is a BYTE ([BP-1], CMP
  against $90 at 1107:027f) and so is declared one here. }
procedure DrawBlobs;
var
  I : Byte;
begin
  for I := 1 to TrailCount do
    Blit(@Blob[I], Outp[I].X, Outp[I].Y, VirtScrSeg);
end;

{ [transcribed] 1107:0562 -- FrameStep(A1, A2, A3). Straight pass-through to
  Transform with the array base DS:$5BCC, then the rest of the frame. }
procedure FrameStep(A1, A2, A3 : Integer);
begin
  Transform(@Trail, A1, A2, A3);    { 1107:0446 }
  BuildBlobs(@Outp[1]);             { 1107:0576, DS:$6336 = Outp + 7 }
  StarStep;                         { 12b2:00c0 }
  StarDraw(VirtScrSeg);             { 12b2:00f1 }
  DrawBlobs;                        { 1107:0245 }
  CopyScreen(VirtScrSeg, $A000);    { 1107:0596 }
end;

{ --------------------------------------------------------------------------
  1107:059f -- ShiftTrails

  Moves the FLAG byte only, never the coordinates:

      for Row := 0 to 7 do
        for J := 2 to 18 do
          Trail[Row*18 + J - 1].Flag := Trail[Row*18 + J].Flag

  The grid is fixed in space; what travels along it is the lit state. That is
  why the message flows through the balls instead of the balls flying.
  -------------------------------------------------------------------------- }
procedure ShiftTrails(Arr : PTrail1);
var
  { ENTER 2, so TWO BYTES and no third local. 1107:05a3 is
    MOV BYTE PTR [BP-1],0 and 1107:05ac MOV BYTE PTR [BP-2],2 -- both counters
    are Bytes, and the row index K is recomputed inline each time rather than
    kept, which is why there is no room for it. }
  Row : Byte;                           { [BP-1], 0 .. 7 }
  J   : Byte;                           { [BP-2], 2 .. 18 }
begin
  for Row := 0 to TrailRows - 1 do
    for J := 2 to TrailLen do
      Arr^[Row * TrailLen + J - 1].Flag := Arr^[Row * TrailLen + J].Flag;
end;

{ --------------------------------------------------------------------------
  1107:0600 -- ShowString(S)

  For every character, eight steps -- one per column of the 8 x 8 glyph. Each
  step lights the head of all eight rows from that column of the glyph, shifts
  every trail along, draws a frame and advances the angle by 6 degrees.

  THE FONT INDEX. The original computes

      Font[Ord(Ch) * 64 + Row * 8 + Step]     base DS:$6A2A

  but Banner_Load reads the glyphs to DS:$7233, which is $809 = 2,057 bytes
  higher. 2057 = 32*64 + 9, so the effective index is

      (Ord(Ch) - 32) * 64 + (Row - 1) * 8 + (Step - 1)

  -- a clean 8 x 8 glyph with a bias of 32, exactly like the font in scene 2.
  59 glyphs covers $20..$5A, space through 'Z'. The earlier reconstruction
  indexed by raw Ord and read 2K past the end of the font for any letter.

  THE TRAIL HEAD is entry Row*18, i.e. the LAST entry of each row -- 1107:0685
  computes Row * $12 * $D. New columns therefore enter at the right of the grid
  and march left.
  -------------------------------------------------------------------------- }
procedure ShowString(S : String);
var
  { THREE BYTES, IN THIS ORDER, and there is no fourth. 1107:0600 opens
    ENTER $104 -- 260, which is the 256-byte copy of the String value parameter
    at [BP-$100] plus four: three declared bytes and the loop's one-byte length
    temp at [BP-$104], written by MOV AL / MOV [BP-$104],AL at 1107:061b.

    The order comes from the offsets, first declared nearest BP: [BP-$101] is
    read as the string subscript at 1107:0661, [BP-$102] is what 1107:064a
    increments in the innermost loop and what 1107:0685 multiplies by 18, and
    [BP-$103] is the remaining term. So Ch, Row, Step -- which is NOT the order
    the loops are nested in, and declaring them in nesting order puts two of
    the three at the wrong offset.

    Byte and not Integer: every read is MOV AL / XOR AH,AH, an UNSIGNED widen
    from a one-byte slot. }
  Ch, Row, Step : Byte;
begin
  for Ch := 1 to Length(S) do
    for Step := 1 to 8 do
    begin
      { NO LOCAL AND NO GUARD. The original indexes with the raw Ord and lets
        the array's low bound of 32 do the biasing, which is why there is no
        SUB and no fourth local. The guard that was here -- clamping to 0
        outside 0..58 -- cannot fire for any character in the three strings
        this routine is called with, since all of them are $20 or above. }
      for Row := 1 to TrailRows do
        if Font[Ord(S[Ch]), Row, Step] <> 0 then
          Trail[Row * TrailLen].Flag := 1
        else
          Trail[Row * TrailLen].Flag := 0;

      ShiftTrails(@Trail[1]);               { 1107:06aa, DS:$5BD9 }
      FrameStep(0, Angle, Angle);           { 1107:06bc -- note the ZERO }
      ClearScreen(VirtScrSeg, 0);           { 1107:06c5 }

      Inc(Angle, BannerStep);
      if Angle > AngleWrap then Dec(Angle, AngleWrap);

      if KeyPressed then Exit;              { 1107:06e4 }
    end;
end;

{ [transcribed] 1107:076e -- the three lines, from CS:$070A, $072F and $074E. }
procedure BannerRun;
begin
  ShowString('HELLO AND WELCOME TO ASPHYXIAS FIRST');
  ShowString(' MEGADEMO, PSYCHO NEUROSIS!!! ');
  ShowString(' NOW SIT BACK AND ENJOY!!!     ');
end;

{ --------------------------------------------------------------------------
  1107:07a2 -- Banner_BuildPoints

  THE MISSING INITIALISER. Without it every trail coordinate is zero, all 144
  balls project to the same pixel, and the scene shows one ball.

  Eight row buffers at DS:$6A33 (stride $100) each get a copy of the SAME
  literal, CS:$078B = 'OOOOOOOOOOOOOOOOOO'. The walk then emits a point for
  every character equal to '*' (CS:$079E) or 'O' (CS:$07A0) -- and since every
  character is 'O', all 144 are emitted and the '*' arm never fires. Whatever
  the strings once spelled, by 1994 they were a plain rectangle.

      Trail[i].X := (Col - 1) * 10 - 90        1107:08c0
      Trail[i].Y := 32 - (Row - 1) * 8         1107:08dd
      Trail[i].Z := 0                          1107:08fe
      Trail[i].Flag := 0                       1107:090d

  giving X over -90..80 in steps of 10 and Y over 32..-24 in steps of 8. The
  counter stops at $91, and then entry 0 -- the translation -- is set:

      Trail[0] := (0, 0, 2000)                 1107:094e
  -------------------------------------------------------------------------- }
procedure BuildPoints;
{ NO DECLARED LOCALS, and the frame is how we know. ENTER $202 is 514 bytes and
  every one of them is a compiler temporary: [BP-2] holds the inner for-loop's
  length limit, and the two 256-byte blocks at [BP-$102] and [BP-$202] are the
  results of TWO Copy() calls -- 1107:0885 and 1107:08af, each followed by a
  comparison against a CS string constant. Row, Col and Idx are unit-level.

  Three shapes here are the original's and not the obvious transcription:

  THE EIGHT ASSIGNMENTS ARE UNROLLED. 1107:07a6..0800 is eight straight calls
  to the string assign with eight LITERAL destinations -- $6A33, $6B33, $6C33
  and so on -- not a loop with computed addressing. A `for Row := 1 to 8` loop
  is the same result and not the same code.

  THE TEST USES Copy(), TWICE. `Rows[Row][Col]` would fetch one byte; the
  original builds a one-character STRING and compares it, twice, which is
  where 512 of the 514 frame bytes go. That is also why there is no Char local.

  AND IT BREAKS BY ASSIGNING THE LOOP VARIABLES. 1107:0933 is
  MOV WORD PTR [$6A2D],8 -- Row is set to its limit, and Col to the row's
  length just before it -- where this had a Boolean flag and two Breaks. That
  is only legal because the counters are unit-level variables rather than the
  for-statement's own, which is a second reason they live outside. }
begin
  Rows[1] := GridPoint;                           { 1107:07a6, and the seven }
  Rows[2] := GridPoint;                           { below are separate calls }
  Rows[3] := GridPoint;                           { in the original, not a }
  Rows[4] := GridPoint;                           { loop }
  Rows[5] := GridPoint;
  Rows[6] := GridPoint;
  Rows[7] := GridPoint;
  Rows[8] := GridPoint;

  Idx := 1;                                       { 1107:0836 }
  for Row := 1 to TrailRows do                     { 1107:083c }
  begin
    for Col := 1 to Length(Rows[Row]) do          { limit into [BP-2] once }
    begin
      if (Copy(Rows[Row], Col, 1) = MarkerA)      { 1107:0885 }
      or (Copy(Rows[Row], Col, 1) = MarkerB) then { 1107:08af }
      begin
        Trail[Idx].X    := IntToFixed((Col - 1) * 10 - 90);
        Trail[Idx].Y    := IntToFixed(32 - (Row - 1) * 8);
        Trail[Idx].Z    := IntToFixed(0);
        Trail[Idx].Flag := 0;
        Inc(Idx);                                 { 1107:0917 }
        if Idx > TrailCount then                  { 1107:091b, CMP $91 }
        begin
          Col := Length(Rows[Row]);               { 1107:0930 }
          Row := TrailRows;                       { 1107:0933 }
        end;
      end;
    end;
  end;

  Trail[0].X := IntToFixed(0);
  Trail[0].Y := IntToFixed(0);
  Trail[0].Z := IntToFixed(2000);
end;

{ --------------------------------------------------------------------------
  1107:0025 -- Banner_Load. NEUROSIS.DAT $03A8E0, four reads:

      3,776   the font, 59 glyphs of 8 x 8         -> DS:$7233
        768   palette                              -> DS:$672D
         49   the unlit profile                    -> DS:$5B6A
         49   the lit profile                      -> DS:$5B9B

  Then blobs 2..144 get a copy of the UNLIT profile and blobs 1..144 get their
  (W, H) header set to 7, 7 -- which is where the 7 x 7 size comes from.

  1107:00b3..1107:0111 is a pair of loops that read each profile byte and, if
  non-zero, write it straight back to itself. Dead code; left out.
  -------------------------------------------------------------------------- }
procedure Load;
var
  { THE FILE RECORD IS A GLOBAL, not a local. 1107:007f pushes DS:$5AD2 as the
    file for the second BlockRead -- a data-segment address, where a local
    would be LEA'd off SS. It is declared beside the unit's other data below. }

  { ONE HUNDRED AND TWENTY-EIGHT BYTES DECLARED AND NEVER REFERENCED, and they
    have to be here or the counter is at the wrong offset. 1107:0025 opens
    ENTER $82 -- 130 bytes -- and the ONLY slot the routine touches in all 372
    bytes of it is [BP-$81], one byte, set to 1 at 1107:00b3 and INC'd at
    1107:00ba. First declared is nearest BP, so whatever occupies
    [BP-$80]..[BP-$01] comes first and is 128 bytes wide.

    String[127] is exactly 128 bytes and is the obvious thing for a loader to
    declare and then not use -- a filename it ended up taking from a constant
    instead. The TYPE is a guess and only the SIZE is measured; what is not a
    guess is that omitting it moves the counter, which is why an earlier frame
    of $02 here left this routine unaligned. }
  Spare : String[127];
  I     : Byte;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $0003A8E0);
  BlockRead(F, Font, SizeOf(TFont));
  BlockRead(F, Pal, 768);
  BlockRead(F, ProfileA, BlobPixels);
  BlockRead(F, ProfileB, BlobPixels);
  Close(F);

  for I := 2 to TrailCount do
    Move(ProfileA, Blob[I].Pix, BlobPixels);
  for I := 1 to TrailCount do
  begin
    Blob[I].W := BlobW;
    Blob[I].H := BlobH;
  end;
  Blob[LastEntry].W := BlobW;
  Blob[LastEntry].H := BlobH;

  ClearScreen(VirtScrSeg, 0);
  WaitRetrace;

  SetPalette768(@Pal);                { 1107:0000 }
end;

{ --------------------------------------------------------------------------
  1107:0977 -- Demo_Scene4

      Scale := (ScreenWidth / 2) * 10          = 1600.0, into DS:$0018
      StarInit(8, 9, 10, 1)                    12b2:0000
      Banner_Load                              1107:0025
      Banner_BuildPoints                       1107:07a2
      Banner_Run                               1107:076e

  The two constants are single-precision at CS:$096F = 2.0 and CS:$0973 = 10.0.
  With Z = 2000 that puts the grid across x 88..224 and y 74..119.
  -------------------------------------------------------------------------- }
procedure Scene4;
begin
  { 1107:097b -- RealToFixed, not Round(.. * 65536.0), and MViewW is READ FROM
    MEMORY rather than folded. FILD WORD [$0014] / FDIV the single at CS:$096F /
    FMUL the single at CS:$0973, then DX/BX/AX pushed into a far call into
    FixMath. Part 002's P2S2 landed on the same form at 108b:1cd4 after two
    refutations that both turned out to be confounded, so this is the shape the
    register already trusts. Note FILD WORD with no XOR DX,DX spill, where
    part 002 has one -- that is the difference between an Integer and a Word. }
  MScale := RealToFixed(MViewW / 2.0 * 10.0);
  Angle := 0;

  StarInit(8, 9, 10, 1);
  Load;
  BuildPoints;
  BannerRun;

end;

end.
