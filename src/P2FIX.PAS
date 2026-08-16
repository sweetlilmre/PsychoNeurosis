{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the fixed-point unit.

  Segment 142a in NEUROSIS_002_fpu.exe, transcribed in full -- all five
  routines, nothing inferred.

  Everything in scene 2's geometry is 16.16 fixed point. These are the three
  conversions between that and the ordinary types, plus the mode-13h setter
  that sits at the end of the segment.
  =========================================================================== }

unit P2Fix;

interface

function IntToFixed(V : Integer) : LongInt;      far;   { 142a:0000 }
function RealToFixed(X : Real) : LongInt;        far;   { 142a:0034 }
function FixedToInt(V : LongInt) : Integer;      far;   { 142a:0071 }
procedure SetMode13h;                            far;   { 142a:00c0 }

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

{ --------------------------------------------------------------------------
  142a:0071 -- despite sitting between the two conversions, this is not a
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

{ 142a:00c0 -- MOV AX,$0013 / INT $10 and nothing else. Sits past the unit's
  initialisation, which is empty. }
procedure SetMode13h; assembler;
asm
  mov ax, $0013
  int $10
end;

{ 142a:00a7 -- the unit's initialisation body is empty. }
begin
end.
