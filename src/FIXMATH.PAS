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

  THIS UNIT DOES NOT CONTAIN SetMode13h, although Ghidra shows one at
  1483:00E0 and 142a:00C0. Those are not in this unit at all: the unit is
  exactly $E0 bytes in part 001 and $C0 in part 002, so both addresses are
  one past its end -- and 1483:00E0 and 1491:0000 are the SAME SIX BYTES at
  linear $04910, as are 142a:00C0 and 1436:0000 at $04360. It is the VGA
  unit's SetMode13h, seen twice because Ghidra's segment ranges overlap.
  An earlier version of this file carried a copy of it on the strength of
  that, and reported the overlap as real duplication in the original.
  =========================================================================== }

unit FixMath;

interface

function IntToFixed(V : Integer) : LongInt;      far;   { 1483:0000 }
function RealToFixed(X : Real) : LongInt;        far;   { 1483:0034 }
function FixedToIntTrunc(V : LongInt) : Integer; far;   { 1483:0071 }
function FixedToInt(V : LongInt) : Integer;      far;   { 1483:0099 }

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


{ 142a:00a7 -- the unit's initialisation body is empty. }
begin
end.
