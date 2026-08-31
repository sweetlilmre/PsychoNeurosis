{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the shared fixed-point unit.

  THE 16.16 CONVERSIONS every 3-D scene uses: Integer to fixed, Real to fixed,
  and two ways back to Integer. Four short functions and nothing else. The
  arithmetic itself lives in src/asm/DEMOMATH.ASM, which needs 386
  instructions; this unit is the part that Pascal can express.

  A 16.16 fixed-point number is one signed 32-bit word holding a whole part in
  the top half and a 1/65536 fraction in the bottom. Converting in is a shift
  left by 16; converting out is a shift right, and the only question is what
  happens to the fraction that falls off.

  THERE ARE TWO CONVERSIONS BACK TO INTEGER AND THEY ARE NOT THE SAME:

      FixedToIntTrunc(V) = V shr 16                     truncates
      FixedToInt(V)      = (V + RealToFixed(0.5)) shr 16  rounds

  The callers pick deliberately, and it matters: part 001 scene 4 rounds while
  scene 5 truncates, because rounding a depth-sort key can move it by one and
  reorder two faces that were level. Giving both scenes the same conversion is
  a real behavioural change, not a tidy-up.

  Parts differ in which of the four they contain, because Turbo Pascal's smart
  linker drops what a part never calls -- part 002 has no use for the
  truncating conversion, so that build does not carry it.

  =========================================================================== }

unit FixMath;

(* STACK CHECKING IS ON FOR THIS UNIT ALONE, and it is on deliberately. The
  whole project builds with it off; only these four functions carry the check,
  which costs a call at every entry. That is not free -- FixedToInt runs once
  per vertex and calls RealToFixed itself, so it is paid on the order of a
  hundred times a frame.

  Read the comment form, not just the words: this paragraph uses the parenthesis
  form rather than braces so that it can NAME a directive without ending itself
  at the directive's own closing brace. *)
{$S+}
(* 286 CODE ON, so every routine here closes with one LEAVE instead of the
   two the 8086 needs. Two bytes a routine, and this unit is all short
   routines. *)
{$G+}
(* 80x87 CODE ON, which decides how RealToFixed's arithmetic is done at all:
   with it, coprocessor instructions; without it, far calls into Turbo
   Pascal's software floating-point library -- a completely different
   instruction stream for the same source line.

   THIS IS THE PER-VERTEX PATH, which is why the choice matters here more than
   anywhere: ObjTransform calls FixedToInt once per vertex and FixedToInt calls
   RealToFixed, so whichever way this compiles is paid about seventy-five times
   a frame. *)
{$N+}

interface

function IntToFixed(V : Integer) : LongInt;      far;
function RealToFixed(X : Real) : LongInt;        far;
function FixedToIntTrunc(V : LongInt) : Integer; far;
function FixedToInt(V : LongInt) : Integer;      far;

implementation

const
  { -- singles in the code segment. }
  FixedOne = 65536.0;
  RoundBias = 0.5;

{ Integer to 16.16: put the whole number in the top half and leave the
  fraction zero. That is all a shift left by 16 is. }
function IntToFixed(V : Integer) : LongInt;
begin
  IntToFixed := LongInt(V) shl 16;
end;

{ --------------------------------------------------------------------------
  A floating-point number to 16.16: multiply by 65536 to move the point, add
  a half, and truncate.

      RealToFixed(X) = Trunc(X * 65536.0 + 0.5)

  TRUNC AND NOT ROUND, and the half is why. Adding 0.5 and then truncating IS
  rounding; calling Round on top of it would round twice, and the second
  rounding would bias every conversion in the demo by half a bit.

  The parameter is a Borland six-byte Real, so it arrives in DX:BX:AX rather
  than on the stack. }
function RealToFixed(X : Real) : LongInt;
begin
  RealToFixed := Trunc(X * FixedOne + RoundBias);
end;

{ 16.16 back to Integer, TRUNCATING -- the fraction is simply dropped. Use
  this where a value must never move upwards: a depth-sort key rounded up can
  swap two faces that were level. }
function FixedToIntTrunc(V : LongInt) : Integer;
begin
  FixedToIntTrunc := V shr 16;
end;

{ --------------------------------------------------------------------------
  16.16 back to Integer, ROUNDING to the nearest. It gets its half by pushing
  0.5 through RealToFixed rather than by writing $8000 -- the same value, one
  more call.

      FixedToInt(V) = (V + RealToFixed(0.5)) shr 16

  This is the one on the per-vertex path, so it is also the reason the two
  directives above matter. }
function FixedToInt(V : LongInt) : Integer;
begin
  FixedToInt := (V + RealToFixed(0.5)) shr 16;
end;


begin
end.
