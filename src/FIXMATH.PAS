{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the shared fixed-point unit.

  ONE UNIT AGAIN. Segment 1483 in part 001, 142a in part 002, and present in
  part 005; the code is identical apart from the far-call fixups into the RTL.
  Turbo Pascal's smart linker drops what a part never calls, so:

      #  routine           001        002
      1  IntToFixed        1483:0000  142a:0000
      2  RealToFixed       1483:0034  142a:0034
      3  FixedToIntTrunc   1483:0071  --
      4  FixedToInt        1483:0099  142a:0071
      5  SetMode13h        1483:00E0  142a:00C0

  Part 002 never calls the truncating conversion, so it is absent and the
  rounding one moves up by exactly its length -- $99 - $71 = $28, and 142a's
  FixedToInt sits $28 below 1483's.

  THERE ARE TWO CONVERSIONS BACK TO INTEGER AND THEY ARE NOT THE SAME:

      FixedToIntTrunc(V) = V shr 16                     truncates
      FixedToInt(V)      = (V + RealToFixed(0.5)) shr 16  rounds

  and the callers pick deliberately. Part 001 scene 4 rounds (1107:052E calls
  1483:0099); part 001 scene 5 truncates (12C5:0268 calls 1483:0071). An
  earlier pass gave both scenes a local rounding copy, which was wrong for
  scene 5 -- it shifts the depth-sort key by up to one.

  SetMode13h at the end duplicates the VGA unit's, byte for byte, in a second
  unit. That is the original's doing, not a transcription artefact; the same
  is true of P2View's SetColour against VGA's SetRGB. Where a scene links both
  units the later one in the `uses` clause wins, and since the code is
  identical it makes no difference.
  =========================================================================== }

unit FixMath;

interface

function IntToFixed(V : Integer) : LongInt;      far;   { 1483:0000 }
function RealToFixed(X : Real) : LongInt;        far;   { 1483:0034 }
function FixedToIntTrunc(V : LongInt) : Integer; far;   { 1483:0071 }
function FixedToInt(V : LongInt) : Integer;      far;   { 1483:0099 }
procedure SetMode13h;                            far;   { 1483:00E0 }

implementation

const
  { 142a:0051 and 142a:0057 -- singles in the code segment. }
  FixedOne = 65536.0;      { CS:$002C }
  RoundBias = 0.5;         { CS:$0030 }

{ 142a:0000 -- CWD then a 64-bit shift left by CX = 16, so simply V shl 16.
  (Part 001's 1483:0000 is the same routine under a misleading name.) }
function IntToFixed(V : Integer) : LongInt;
begin
  IntToFixed := LongInt(V) shl 16;
end;

{ --------------------------------------------------------------------------
  142a:0034 -- load the Real, FMUL by $2C, FADD $30, round to a LongInt.

      RealToFixed(X) = Round(X * 65536.0 + 0.5)

  The parameter is six bytes (RETF 6) arriving in DX:BX:AX, so it is a Borland
  Real; the result is four (the frame reserves and returns only AX and DX).
  -------------------------------------------------------------------------- }
function RealToFixed(X : Real) : LongInt;
begin
  RealToFixed := Round(X * FixedOne + RoundBias);
end;

{ 1483:0071 -- the TRUNCATING conversion: no bias, just a 32-bit shift right
  by 16. Part 002 never calls it and it is absent from that build. }
function FixedToIntTrunc(V : LongInt) : Integer;
begin
  FixedToIntTrunc := V shr 16;
end;

{ --------------------------------------------------------------------------
  1483:0099 / 142a:0071 -- the ROUNDING conversion. Despite sitting between
  the two conversions in part 002's build, this is not a
  perspective divide. It builds the Real48 $000000000080 -- which is 0.5 --
  pushes it through RealToFixed to get $8000, adds that to the parameter, and
  shifts the 32-bit result right by 16:

      FixedToInt(V) = (V + RealToFixed(0.5)) shr 16

  That is a 16.16 value rounded to the nearest integer, the half being the
  usual rounding bias.
  -------------------------------------------------------------------------- }
function FixedToInt(V : LongInt) : Integer;
begin
  FixedToInt := (V + RealToFixed(0.5)) shr 16;
end;

{ --------------------------------------------------------------------------
  142a:00c0 -- MOV AX,$0013 / INT $10 and nothing else, with no stack frame.
  Sits past the unit's initialisation, which is empty.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      (none). Setting a video mode is a BIOS call; Turbo Pascal has no way to
      make one without an asm block or an Intr() call, and Intr() would push
      a Registers record the original does not have.
  -------------------------------------------------------------------------- }
procedure SetMode13h; assembler;
asm
  MOV  AX, $0013          { BIOS function 0, mode $13: 320x200, 256 colours }
  INT  $10                { the video BIOS                                  }
end;

{ 142a:00a7 -- the unit's initialisation body is empty. }
begin
end.
