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

  -- into eight row buffers, then walks them and emits one point per
  character. Eight rows of eighteen is exactly the 144.
  =========================================================================== }

{ 80x87 code on: the scene's projection scale is computed in floating point. }
{$N+}
{$A-}   { BYTE ALIGNMENT, AND IT IS NOW A NET GAIN. See TTrail and Tail3. }
{ 286 instructions are permitted -- the palette write uses REP OUTSB, which
  moves all 768 DAC bytes in one instruction. }
{$G+}

unit P1BALLS;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

interface

procedure Scene4;

implementation

{ ==========================================================================
  THIS UNIT'S ROUTINE ORDER, DERIVED AND NOT YET APPLIED. }

uses VGA, Crt, DemoVT, FixMath, P1STAR;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

{ --------------------------------------------------------------------------
SetPalette768(P). HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := 0;
      for I := 0 to 767 do Port[$3C9] := TPal768(P^)[I];

  Scene 4 is the only part 001 scene with its own copy; the others go through
  VGA.SetPalette.
  -------------------------------------------------------------------------- }
{$I SETPAL.INC}

const
  TrailRows  = 8;
  TrailLen   = 18;
  TrailCount = TrailRows * TrailLen;        { 144 }
  LastEntry  = TrailCount + 1;              { runs 1..145 }
  BlobW      = 7;
  BlobH      = 7;
  BlobPixels = BlobW * BlobH;               { 49 = $31 }
  FontChars  = 59;                          { chars $20..$5A }
  FontBias   = 32;                          { see DrawStep }
  AngleWrap  = 3600;                        { angles are TENTHS of a degree }
  BannerStep = 60;                          { $3C -- 6.0 degrees per column }
  GridPoint  = 'OOOOOOOOOOOOOOOOOO';
  MarkerA    = '*';
  MarkerB    = 'O';

  { The clip box the blitter reads. Four bounds, initialised data. }
  ClipTop    : Integer = 0;
  ClipBottom : Integer = 199;
  ClipLeft   : Integer = 0;
  ClipRight  : Integer = 319;

{ $A IS A GLOBAL DIRECTIVE, and in a single compiler run its state carries
  into the units compiled after the one that sets it. So $A- here silently
  recompiles P1LOGO and P1TITLE unaligned too, costing 11 bytes there to save 4
  here. Net -7, which is exactly what an earlier pass measured and recorded
  without knowing where the 7 went.

  AND THAT ROUTE IS WRONG -- IT IS NOT P1LOGO'S OR P1TITLE'S RECORDS. Pinning A-plus
  explicitly at the head of P1LOGO, P1TITLE and P1MOSAIC changed not one byte, so their
  spans come from THIS unit's block shrinking and moving what follows.

  WHAT A-MINUS ACTUALLY BUYS, measured: every address in this unit up to Blob
  becomes exactly right. Work at $5BCC is 2,913 bytes -- Trail 146 x 13 plus
  Outp 145 x 7 -- and 2,913 is ODD, so the original's Pal lands on the odd
  $672D with no padding, then Row $6A2D, Rows $6A33, Font $7233, Angle $80F3,
  Blob $80F5. Every one matches under A-minus and none under the default, and
  dsmap's +2 group at $5BCE and +3 at $6A2F both vanish. The original was
  compiled A-minus.

  WHAT IT COSTS IS EXACTLY FOUR BYTES OF DGROUP. The map says it: DATA is
  0AF62H with the switch off and 0AF5EH with it on. So four bytes of padding
  have been standing in for four bytes of real data we have never declared,
  somewhere in this unit after Work.

  AND THE OBVIOUS THREE-WAY CHECK CANNOT BE MADE. Comparing our DGROUP size
  against the original's needs the original's DATA start, which needs its
  System segment size -- and that is the one thing known to DIFFER: the runtime
  offset deltas of +104 say a different amount of runtime is linked. The
  original's EXE header gives SS=13EF against our 1405, which is a code AND
  data total and cannot be split without that same number.

  So three ticks have established what A-minus fixes, what it costs to the
  byte, and that the shortfall is real data rather than a trade-off -- and the
  four bytes themselves are not findable by arithmetic from here. They need
  either the original's own map, which does not exist, or a reference from its
  code to a variable in that range that we do not declare. dsmap pairs nothing
  between $5BCC and $AAC2, so that reference has not been found yet. }
type
  { A TRAIL ENTRY: a 16.16 point plus a flag, thirteen bytes.

    ENTRY 0 IS NOT A POINT. It holds the object's TRANSLATION vector, which is
    why Transform adds it to every rotated point and never rotates it -- so the
    array is zero-based and index 0 is special. }
  TTrail = record
    X, Y, Z : LongInt;          { 16.16 fixed point -- hence 13 bytes }
    Flag    : Byte;
  end;

  { The trail as a whole, ZERO-based -- see TTrail for why index 0 matters.
    Named because Transform takes it by pointer. }
  TTrailArr = array[0..LastEntry] of TTrail;
  PTrailArr = ^TTrailArr;

  { THE SAME RECORDS SEEN ONE-BASED, because ShiftTrails is handed
    @Trail[1] rather than @Trail -- it works on the points and must not touch
    entry 0, the translation. Two types over one array, which is the cheapest
    way to say "all of it" and "the points only". }
  TTrail1   = array[1..LastEntry] of TTrail;
  PTrail1   = ^TTrail1;

  { 7 bytes in the original: X, Y, D as words and the flag as a byte. }
  TOut = record
    X, Y, D : Integer;
    Flag    : Byte;
  end;

  { The projected output, one-based -- there is no entry 0 here, because the
    translation is not something you draw. }
  TOutArr = array[1..LastEntry] of TOut;
  POutArr = ^TOutArr;

  { TRAIL AND OUTP ARE ADJACENT MEMBERS OF ONE RECORD, and Transform relies on
    it: it is handed the trail's address and reaches the output array at a fixed
    offset from it rather than by name. Separating the two into loose variables
    would break that silently -- the code would compile and write somewhere
    else. }
  TWork = record
    Trail : array[0..LastEntry] of TTrail;   { offset 0,    1,898 bytes }
    Outp  : array[1..LastEntry] of TOut;     { offset $76A, 1,015 bytes }
  end;
  { PWork is no longer used: Transform takes `var Base : TWork` and there is no
    pointer to TWork anywhere in the unit. Kept because TWork's own note reads
    against it. }
  PWork = ^TWork;

  { 51 bytes in the original ($33): a two-byte (W, H) header the blitter reads
    out of the sprite itself, then 49 pixels. }
  TBlob = record
    W, H : Byte;
    Pix  : array[1..BlobPixels] of Byte;
  end;

  { THE FONT'S FIRST GLYPH IS CHARACTER 32, a space -- there are no glyphs
    below it, so the array starts at 32 and a character indexes it directly. }
  TFont = array[FontBias..FontBias + FontChars - 1, 1..8, 1..8] of Byte;

{ ==========================================================================
  THIS UNIT'S DGROUP, MEASURED FROM SEGMENT 1107 RATHER THAN INFERRED, and the
  declaration order below does NOT yet match it. Read this before moving
  anything.

  Two passes over the segment: every ABSOLUTE `ptr [0xNNNN]` displacement, and
  every FOLDED `[reg +/- 0xNNNN]` base. The absolute list is short and complete,
  because everything else in the unit is reached through a fold or a pointer:

      $5B52 $5B56 $5B5A $5B5E $5B62 $5B66     the six maths LongInts
      $5BCC $5BCE $5BD0 $5BD2 $5BD4 $5BD6     six words, once each
      $6A2D $6A2F $6A31                       Row, Col, Idx
      $80F3                                   Angle

  THE FOLDS NAME THE ARRAYS AND THEIR STRIDES:

      $5B69  di = Ord(ch)                 a 1-based BYTE array at $5B6A
      $5B9A  di = Ord(ch)                 a 1-based BYTE array at $5B9B
      $5BD8  IMUL AX,AX,$12 / IMUL DI,AX,$D, and IMUL DI,[$6A31],$D elsewhere
      $632F  IMUL DI,AX,7                 1-based 7-byte records at $6336
      $6933  MOV DI,[$6A2D] / SHL DI,8    1-based 256-byte elements at $6A33
      $6A2A  ADD DI,DX / ADD DI,CX        two subscripts whose bounds sum to 9
      $80C2  IMUL DI,AX,$33               1-based 51-byte records at $80F5

  TWO OF THOSE CLOSE COMPLETELY AND EACH CONFIRMS A RECORDED ADDRESS. $6933
  plus 256 is $6A33, so `Rows : array[1..TrailRows] of String` really is there.
  And $80C2 plus 51 is $80F5, so the 51-byte array starts THERE -- which puts
  Angle's two bytes at $80F3 immediately in front of it, exactly where the
  absolute list says Angle is. **Blob follows Angle. It does not precede it.**
  And $5B9B minus $5B6A is 49, which is BlobPixels, so those two byte arrays
  are ProfileA and ProfileB.

  THE ORDER, AS FAR AS IT IS MEASURED:

      $5B52  MCos1..MSin3      24
      $5B6A  ProfileA          49
      $5B9B  ProfileB          49
      $5BCC  six words         12
      $5BD8  strides 18 and 13, so 234 bytes an element
      $6336  seven-byte records
       ...
      $6A2D  Row, Col, Idx      6
      $6A33  Rows             256 an element
       ...
      $80F3  Angle              2
      $80F5  Blob              51 a record

  WHAT IS WRONG WITH THE LIST BELOW: the maths block is declared LAST and
  belongs FIRST. Ours puts MCos1 at $A0F0 against the original's $5B52 --
  eighteen thousand bytes -- and that displacement is what makes every absolute
  reference in this unit and the whole of scene 5's block measure wrong. It is
  also, on its own, the +4 that dsmap reports from $AAC2 upwards: scene 5's
  block sits four bytes high because this one ends four bytes late.

  STILL OPEN: what the six words at $5BCC are; what the 234-byte-element array
  at $5BD8 is (array[.., 1..18, 1..13] is the shape to try, since 18 x 13 is
  234); what starts at $6336 with seven-byte records; and where the block
  BEGINS -- P1TITLE's ends at $5A52 and MCos1 is at $5B52, so 256 bytes precede
  the maths block, which is either P1MOSAIC's whole block, or two 128-byte file
  records, or one String.
  ========================================================================== }
var
  { The scene's file handle, unit-level rather than local to the loader -- the
    same split part 001 scene 1 uses. }
  F : file;

{ --------------------------------------------------------------------------
  THE SHARED 386 MATHS MODULE, AND IT COMES SECOND IN THIS UNIT'S DGROUP.

  THE NINE NAMES HAVE TO BE DECLARED BEFORE THE $L DIRECTIVE, and for a long
  time that was read as "declare them near it", which put them LAST in the
  unit -- MCos1 at $A0F0 against the original's $5B52, eighteen thousand bytes
  out, and every absolute reference in this unit and the whole of scene 5's
  block wrong with it. The directive only has to come after the names; the
  names can be anywhere.
  -------------------------------------------------------------------------- }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  { THE ONE-BYTE FOLD DIFFERENCE HERE HAS SURVIVED FOUR ATTEMPTS, and they are
    recorded so nobody spends a fifth.

    What is wanted: the original folds these as [DI+$5B69] and [DI+$5B9A],
    three sites each, so they sit at $5B6A and $5B9B -- the second on an ODD
    boundary. Word alignment pads each 49-byte array to 50 and puts the second
    at $5B9C. A fold of $5B9A from a BARE subscript can only come from an array
    actually based at $5B9B, so nothing but true adjacency will do.

      byte alignment for the WHOLE unit    -7 bytes. The directive is not local
                                           to these two names and cost four
                                           other places what it gained.
      array[1..2, 1..BlobPixels]          -13 bytes. Reaches both folds on
                                           paper -- row 1 at base-1, row 2 at
                                           base+48 -- but a two-dimensional
                                           subscript is not the same code.
      array[1..98] with [BlobPixels + I]    0 bytes, and WRONG: the compiler
                                           adds 49 at RUN TIME and folds base-1
                                           for both halves, so ours emitted six
                                           sites at $5B69 and none at $5B9A.
                                           Flattening also drops the padding
                                           word, which took every reference from
                                           $AAC2 up to -2 across sixty-five
                                           sites until a spare Integer put it
                                           back -- at which point the totals are
                                           identical to doing nothing.
      the A directive scoped mid-block     REFUSED BY THE COMPILER: Error 17,
                                           Invalid compiler directive. Turbo
                                           Pascal will not take an A directive
                                           inside a var block, so alignment
                                           cannot be turned off for two
                                           declarations and back on after.

    So the byte is reachable only by finding what else in this block is two
    bytes larger than the original's, and leaving these two padded. }
  ProfileA, ProfileB : array[1..BlobPixels] of Byte;
  { the trail and the output list as ONE record, which is how
    Transform reaches the second through a pointer to the first. $5BCC plus
    1,898 is $6336, where the output list begins, so merging them changes
    nothing about the layout -- it only lets the source say what the code does. }
  Work  : TWork;
  { 768 bytes, ending exactly at Row below. }
  Pal   : array[0..767] of Byte;
  Row   : Integer;
  Col   : Integer;
  Idx   : Integer;
  Rows  : array[1..TrailRows] of String;
  { 3,776 bytes = 59 glyphs of 8 x 8, AND IT IS INLINE IN DGROUP, not
    on the heap. Declared as a pointer with New and Dispose round it, four bytes
    sat where the original has 3,776 and every variable after it moved --
    including the whole of scene 5's block, which sits above this one.

    $7233 AND NOT $6A2A. $6A2A is the FOLDED base of ShowString's subscript, not
    the array's address: $7233 - $809, where $809 is 2,057 = 32 * 64 + 9, the
    character bias of 32 glyphs plus the nine that array[0..58, 1..8, 1..8]
    folds for its low bounds. A folded displacement is never an address. And it
    tiles: the row buffers at $6A33 take 2,048 bytes and end exactly here. }
  Font  : TFont;
  Angle : Integer;
  { stride $33 }
  Blob  : array[1..LastEntry] of TBlob;
  { TWO BYTES HERE, AND THE THIRD MOVED NEXT DOOR. With A-minus set -- which
    every address in this unit up to Blob requires -- StarInit's fold reads
    $9DCF where the original has $9DD2, so three bytes have to stand at the end
    of this block or P1Star's Star begins early and everything after it slides.
    Two are here; the third is P1Star's own Lead, and the swap is what finally
    put Star at the odd $9DDB.

    The reason is in the note beside Star: our TP7 pads the FOLLOWING unit's
    block to a word. This block therefore has to END at $9DD9, so that pad
    lands on the even $9DDA and leaves P1Star free to spend a byte there and
    put Star at $9DDB. With three bytes here the block ended at $9DDA, the pad
    went to $9DDC, and Star could not reach $9DDB however P1Star was written.

    Types unknown, sizes measured. }
  Tail3 : array[1..2] of Byte;

const
  { THE VIEW SIZE Project halves to find the screen centre. }
  MViewW : Integer = 320;
  MViewH : Word = 200;
  { THE PROJECTION SCALE IS A TYPED CONSTANT, not a var, and that
    is what its ADDRESS says: $0018 is inside the initialised image, which runs
    to $02F0 in this part, and a plain `var` reserves space in the uninitialised
    region instead. The original holds four bytes of zero there -- the value is
    written at run time by Demo_Scene4 -- and ours had nothing, which shifted
    every initialised byte after it down by four.

    Scene 5's copy of the same variable IS a var, at $AABE, well past the end of
    the initialised region. Same name, same purpose, different storage class in
    the two units, and only the addresses say so. }
  MScale : LongInt = 0;

{$L DEMOMATH.OBJ}

{ --------------------------------------------------------------------------
SinCos(Angle : Integer; var C, S : LongInt)

Rotate(var X, Y, Z : LongInt)

Project(var X, Y, Z : LongInt)

      Sx := Round(X/Z * Scale) + MViewW div 2
      Sy := MViewH div 2 - Round(Y/Z * Scale)

  All three are in src/asm/DEMOMATH.ASM, commented there. An earlier version
  of this file had them as Pascal over Reals, which is a different program:
  the original's multiply is 32x32->64 taking the MIDDLE 32 bits, and its
  divide builds a 48-bit dividend so the quotient comes out 16.16.
  -------------------------------------------------------------------------- }
procedure SinCos(A : Integer; var C, S : LongInt);      external;
procedure RotatePoint(var X, Y, Z : LongInt);           external;
procedure Project(var X, Y, Z : LongInt);               external;

{ THE CONVERSIONS COME FROM FixMath, and this scene uses the ROUNDING one
  where scene 5 truncates -- not interchangeable, because rounding a
  depth-sort key can reorder two faces that were level. }

{ --------------------------------------------------------------------------
Banner_Load. NEUROSIS.DAT $03A8E0, four reads:

  Then blobs 2..144 get a copy of the UNLIT profile and blobs 1..144 get their
  (W, H) header set to 7, 7 -- which is where the 7 x 7 size comes from.

 is a pair of loops that read each profile byte and, if
  non-zero, write it straight back to itself. Dead code; left out.
  -------------------------------------------------------------------------- }
procedure Load;
var
  { THE FILE RECORD IS A GLOBAL, not a local -- declared beside the unit's
    other data below. }

  { ONE HUNDRED AND TWENTY-EIGHT BYTES DECLARED AND NEVER REFERENCED, and they
    have to be here: the routine's one live variable sits BELOW them in the
    frame, so removing them moves it.

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
  Seek(F, DAT_P1_BALLFONT);                { was $0003A8E0 }
  BlockRead(F, Font, SizeOf(TFont));
  BlockRead(F, Pal, 768);
  BlockRead(F, ProfileA, BlobPixels);
  BlockRead(F, ProfileB, BlobPixels);
  Close(F);

  { A LOOP THAT DOES NOTHING, AND IT IS IN THE ORIGINAL -- it reads each byte
    of the profile and writes the same byte straight back. A reconstruction
    would never invent this; only the bytes find it. Left as it is.

    Forty-nine iterations of two conditional self-assignments. It changes
    nothing, it is eighty-three bytes of the original, and leaving it out was
    the largest single hole left in this segment. }
  for I := 1 to BlobPixels do
  begin
    if ProfileA[I] <> 0 then ProfileA[I] := ProfileA[I];
    if ProfileB[I] <> 0 then ProfileB[I] := ProfileB[I];
  end;

  { BLOB 1 IS FILLED ON ITS OWN, BEFORE THE LOOP, and the loop then starts at
    2 -- so the first blob is a special case rather than the loop's first turn. }
  Move(ProfileA, Blob[1].Pix, BlobPixels);
  for I := 2 to TrailCount do
    { A STRUCTURED ASSIGNMENT, NOT A Move CALL, and it must stay one: Turbo
      Pascal copies a whole record inline through a different runtime routine
      from the one Move uses. Same bytes copied, different code.

      OUR RUNTIME IS BYTE-IDENTICAL TO THE ORIGINAL'S -- 15,184 bytes, no
      difference, same paragraph -- which is what ruled out the easy answer that
      these offsets were a smart-link artefact and made the source the only
      remaining explanation. }
    Blob[I].Pix := Blob[1].Pix;
  for I := 1 to TrailCount do
  begin
    Blob[I].W := BlobW;
    Blob[I].H := BlobH;
  end;

  ClearScreen(VirtScrSeg, 0);
  WaitRetrace;

  SetPalette768(@Pal);
end;

{ --------------------------------------------------------------------------
  The clipped transparent sprite blit. HAND ASSEMBLER, verbatim, and SHARED
  SOURCE: the routine is src/asm/BLITCLIP.INC, because part 006 scene 2
  compiles the same text. }
{$I BLITCLIP.INC}

{ Blit the 144 blobs, back to front. Entry 145 is transformed and sorted with
  the rest but never drawn. }
procedure DrawBlobs;
var
  I : Byte;
begin
  for I := 1 to TrailCount do
    Blit(@Blob[I], Work.Outp[I].X, Work.Outp[I].Y, VirtScrSeg);
end;

{ --------------------------------------------------------------------------
  DepthSort(Lo, Hi), nested inside SortOutp

  This was missing entirely from the earlier reconstruction, so the grid drew
  in index order and the depth cueing was wrong wherever the field folded over
  itself. The records are swapped whole -- three 7-byte Moves via a temporary.
  -------------------------------------------------------------------------- }
procedure SortOutp(var Arr : TOutArr);
{ A WRAPPER, and DepthSort is NESTED INSIDE IT.

  This is the same shape scene 5's SortAll turned out to be, in the same
  binary, and that one was worth 619 bytes. }
  procedure DepthSort(Lo, Hi : Integer);
  var
    I, J : Integer;
    P    : Integer;
    T    : TOut;
  begin
    I := Lo;  J := Hi;
    P := Arr[(Lo + Hi) div 2].D;
    repeat
      { The operand order was tried BOTH ways here and measures identically --
        `while P < Arr[I].D` emits the same bytes as this. So the 3 bytes at
 are not an operand-order difference, and the natural spelling
        stays. }
      while Arr[I].D > P do I := I + 1;
      while Arr[J].D < P do J := J - 1;
      if I <= J then
      begin
        if Arr[I].D <> Arr[J].D then
        begin
          T := Arr[I];  Arr[I] := Arr[J];  Arr[J] := T;
        end;
        I := I + 1;  J := J - 1;
      end;
    until I > J;
    if Lo < J then DepthSort(Lo, J);
    if I < Hi then DepthSort(I, Hi);
  end;
begin
  DepthSort(1, TrailCount);                 { PUSH 1 / PUSH $90 }
end;

{ --------------------------------------------------------------------------
BuildBlobs(Out)

  Sort by depth first, then give every
  record its sprite according to the flag the sort carried along with it: }
procedure BuildBlobs(Arr : POutArr);
var
  I : Integer;
begin
  SortOutp(Arr^);                           { LES DI / PUSH ES / PUSH DI }
  for I := 1 to LastEntry do
    if Arr^[I].Flag <> 0 then
      Move(ProfileB, Blob[I].Pix, BlobPixels)
    else
      Move(ProfileA, Blob[I].Pix, BlobPixels);
end;

{ --------------------------------------------------------------------------
Transform(Base; A1, A2, A3)

  For entries 1..145: copy the 13-byte record out, rotate it, add the
  TRANSLATION held in entry 0, project, and write the 7-byte output record.

  Note what is NOT rotated: entry 0. The loop starts at 1, and the add at
 reads ES:[DI], ES:[DI+4], ES:[DI+8] with DI still pointing at the
  base of the array -- entry 0. It is the object position, not a point.
  -------------------------------------------------------------------------- }
procedure Transform(var Base : TWork; A1, A2, A3 : Integer);
var
  I : Integer;
  T : TTrail;                           { the working copy }
begin
  {    AND HOW TO DIFF THIS. A masked instruction diff over a WHOLE UNIT anchors its
    "original" side at whatever offset the drift has reached, so its pairings
    across a defect are not counterparts -- that misread cost a full cycle here,
    and it also hid the fact that DepthSort's eight bytes and this routine's nine
    were CANCELLING. Use prologue offsets to find which routine, then diff that
    one routine anchored on its own prologue. }

  with Base do
  begin

    SinCos(A1, MCos1, MSin1);       { one call per axis, into the shared  }
    SinCos(A2, MCos2, MSin2);       {   cos/sin pairs the rotation reads  }
    SinCos(A3, MCos3, MSin3);

    for I := 1 to LastEntry do
    begin
      T := Trail[I];                            { thirteen bytes }
      RotatePoint(T.X, T.Y, T.Z);
      { THE TRANSLATION IS READ THROUGH THE POINTER, not from Trail absolutely,
        so the routine works on whatever trail it was handed. }
      T.X := T.X + Base.Trail[0].X;
      T.Y := T.Y + Base.Trail[0].Y;
      T.Z := T.Z + Base.Trail[0].Z;
      Project(T.X, T.Y, T.Z);
      { both come back zero-extended, so the low word carries the sign }
      Outp[I].X    := Integer(T.X);
      Outp[I].Y    := Integer(T.Y);
      Outp[I].D    := FixedToInt(T.Z);
      Outp[I].Flag := T.Flag;
    end;
  end;
end;

{ Advance one frame: pass the three angles straight through to the transform
  and the sort, then draw. There is no logic here. }

procedure FrameStep(A1, A2, A3 : Integer);
begin
  Transform(Work, A1, A2, A3);
  BuildBlobs(@Work.Outp[1]);
  StarStep;
  StarDraw(VirtScrSeg);
  DrawBlobs;
  CopyScreen(VirtScrSeg, $A000);
end;

{ --------------------------------------------------------------------------
ShiftTrails

  Moves the FLAG byte only, never the coordinates:

      for Row := 0 to 7 do
        for J := 2 to 18 do
          Work.Trail[Row*18 + J - 1].Flag := Work.Trail[Row*18 + J].Flag

  The grid is fixed in space; what travels along it is the lit state. That is
  why the message flows through the balls instead of the balls flying.
  -------------------------------------------------------------------------- }
procedure ShiftTrails(Arr : PTrail1);
var
  Row : Byte;                           { 0 .. 7 }
  J   : Byte;                           { 2 .. 18 }
begin
  for Row := 0 to TrailRows - 1 do
    for J := 2 to TrailLen do
      Arr^[Row * TrailLen + J - 1].Flag := Arr^[Row * TrailLen + J].Flag;
end;

{ --------------------------------------------------------------------------
ShowString(S)

  For every character, eight steps -- one per column of the 8 x 8 glyph. Each
  step lights the head of all eight rows from that column of the glyph, shifts
  every trail along, draws a frame and advances the angle by 6 degrees.

  THE FONT INDEX. The original computes

  -- a clean 8 x 8 glyph with a bias of 32, exactly like the font in scene 2.
  59 glyphs covers $20..$5A, space through 'Z'. The earlier reconstruction
  indexed by raw Ord and read 2K past the end of the font for any letter. }
procedure ShowString(S : String);
var
  {    Byte and not Integer: every read is MOV AL / XOR AH,AH, an UNSIGNED widen
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
          Work.Trail[Row * TrailLen].Flag := 1
        else
          Work.Trail[Row * TrailLen].Flag := 0;

      ShiftTrails(@Work.Trail[1]);
      FrameStep(0, Angle, Angle);           { note the ZERO }
      ClearScreen(VirtScrSeg, 0);

      Angle := Angle + BannerStep;
      if Angle > AngleWrap then Angle := Angle - AngleWrap;

      if KeyPressed then Exit;
    end;
end;


procedure BannerRun;
begin
  ShowString('HELLO AND WELCOME TO ASPHYXIAS FIRST');
  ShowString(' MEGADEMO, PSYCHO NEUROSIS!!! ');
  ShowString(' NOW SIT BACK AND ENJOY!!!     ');
end;

{ --------------------------------------------------------------------------
Banner_BuildPoints

  THE MISSING INITIALISER. Without it every trail coordinate is zero, all 144
  balls project to the same pixel, and the scene shows one ball.

  giving X over -90..80 in steps of 10 and Y over 32..-24 in steps of 8. The
  counter stops at $91, and then entry 0 -- the translation -- is set:

      Work.Trail[0] := (0, 0, 2000)     the translation, not a point
  -------------------------------------------------------------------------- }
procedure BuildPoints;
{  THE TEST USES Copy(), TWICE. `Rows[Row][Col]` would fetch one byte; the
  original builds a one-character STRING and compares it, twice, which is
  where 512 of the 514 frame bytes go. That is also why there is no Char local. }
begin
  Rows[1] := GridPoint;                           { and the seven }
  Rows[2] := GridPoint;                           { below are separate calls }
  Rows[3] := GridPoint;                           { in the original, not a }
  Rows[4] := GridPoint;                           { loop }
  Rows[5] := GridPoint;
  Rows[6] := GridPoint;
  Rows[7] := GridPoint;
  Rows[8] := GridPoint;

  Idx := 1;
  for Row := 1 to TrailRows do
  begin
    for Col := 1 to Length(Rows[Row]) do
    begin
      if (Copy(Rows[Row], Col, 1) = MarkerA)
      or (Copy(Rows[Row], Col, 1) = MarkerB) then
      begin
        Work.Trail[Idx].X    := IntToFixed((Col - 1) * 10 - 90);
        Work.Trail[Idx].Y    := IntToFixed(32 - (Row - 1) * 8);
        Work.Trail[Idx].Z    := 0;                 { XOR AX,AX }
        Work.Trail[Idx].Flag := 0;
        Inc(Idx);
        if Idx >= LastEntry then                   { CMP $91 }
        begin
          Col := Length(Rows[Row]);
          Row := TrailRows;
        end;
      end;
    end;
  end;

  { is XOR AX,AX then four stores of AX -- both are direct zeros,
    not IntToFixed(0), which would push and call. }
  Work.Trail[0].X := 0;
  Work.Trail[0].Y := 0;
  Work.Trail[0].Z := IntToFixed(2000);
end;

{ --------------------------------------------------------------------------
  Demo_Scene4 -- the scene's entry point, in the order it does things:

      Scale := (ScreenWidth / 2) * 10          = 1600.0
      StarInit(8, 9, 10, 1)
      Banner_Load
      Banner_BuildPoints
      Banner_Run }
procedure Scene4;

begin
  MScale := RealToFixed(MViewW / 2.0 * 10.0);
  StarInit(8, 9, 10, 1);
  Load;
  BuildPoints;
  BannerRun;

end;

begin
end.
