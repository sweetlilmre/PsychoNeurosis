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

  [re] ONE UNIT AGAIN. Segment 1483 in part 001, 142a in part 002, and present in
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

  [re] and the callers pick deliberately. Part 001 scene 4 rounds (1107:052E calls
  1483:0099); part 001 scene 5 truncates (12C5:0268 calls 1483:0071). An
  earlier pass gave both scenes a local rounding copy, which was wrong for
  scene 5 -- it shifts the depth-sort key by up to one.

  [re] THIS UNIT DOES NOT CONTAIN SetMode13h, although Ghidra shows one at
  1483:00E0 and 142a:00C0. Those are not in this unit at all: the unit is
  exactly $E0 bytes in part 001 and $C0 in part 002, so both addresses are
  one past its end -- and 1483:00E0 and 1491:0000 are the SAME SIX BYTES at
  linear $04910, as are 142a:00C0 and 1436:0000 at $04360. It is the VGA
  unit's SetMode13h, seen twice because Ghidra's segment ranges overlap.
  An earlier version of this file carried a copy of it on the strength of
  that, and reported the overlap as real duplication in the original.

  =========================================================================== }

unit FixMath;

(* STACK CHECKING IS ON FOR THIS UNIT ALONE, and it is on deliberately. The
  whole project builds with it off; only these four functions carry the check,
  which costs a call at every entry. That is not free -- FixedToInt runs once
  per vertex and calls RealToFixed itself, so it is paid on the order of a
  hundred times a frame.

  Read the comment form, not just the words: this paragraph uses the parenthesis
  form rather than braces so that it can NAME a directive without ending itself
  at the directive's own closing brace.

  [re] Every entry point in the original opens `MOV AX,<frame size>` then a far
  CALL to 14b1:0530 BEFORE `SUB SP,n` -- 142a:0037 for RealToFixed, 142a:0074
  for FixedToInt, 142a:0003 for IntToFixed -- which is what Turbo Pascal emits
  under {$S+}. build.toml passes /$S- on the command line for the whole
  project, so this unit has to say otherwise for itself.

  [re] The hot routines elsewhere do NOT have it and must not get it: P2View's
  Plot at 140c:00b1 and FillRect at 140c:011e open `PUSH BP / MOV BP,SP` and
  go straight into the body, and P2SOLID's ObjTransform opens a bare ENTER.

  [re] IT MAKES THE REBUILD SLOWER, and that is the right direction. FixedToInt is
  called once per vertex and calls RealToFixed once itself, so the original
  pays roughly 150 of these checks per frame that the reconstruction was
  skipping. A switch is set to match the emitted code, never to make the
  rebuild faster. *)
{$S+}
(* 286 CODE ON, so every routine here closes with one LEAVE instead of the
   two the 8086 needs. Two bytes a routine, and this unit is all short
   routines.

   [re] 142a:00A3 is `LEAVE / RETF 4` and this unit had no G directive
   at all, so it took the command line's default and emitted MOV SP,BP / POP BP
   -- two bytes more, at the end of every routine in it. *)
{$G+}
(* 80x87 CODE ON, which decides how RealToFixed's arithmetic is done at all:
   with it, coprocessor instructions; without it, far calls into Turbo
   Pascal's software floating-point library -- a completely different
   instruction stream for the same source line.

   THIS IS THE PER-VERTEX PATH, which is why the choice matters here more than
   anywhere: ObjTransform calls FixedToInt once per vertex and FixedToInt calls
   RealToFixed, so whichever way this compiles is paid about seventy-five times
   a frame.

   [re] 142a:004b calls one runtime routine and then executes x87
   instructions -- 142a:0050 is INT $3C, which under E-plus is what an 80x87
   opcode ships as. This unit had NO N directive at all, so it took the
   N-minus default: floating point became far calls into the software
   six-byte Real library, which is a different instruction stream entirely
   and shows as `MOV CX,$91 / XOR SI,SI / XOR DI,DI` before the call.

   [re] A trap is positive evidence OF 80x87 code, not against it -- the N-minus
   setting emits no 80x87 instructions and therefore no traps either. That
   has been got wrong three times in this corpus; the register's
   part5-386-trio resolution is the long form. *)
{$N+}

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

{ Integer to 16.16: put the whole number in the top half and leave the
  fraction zero. That is all a shift left by 16 is.

  [re] 142a:0000 -- CWD then a 64-bit shift left by CX = 16, so simply V shl 16.
  (Part 001's 1483:0000 is the same routine under a misleading name.) }
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
  than on the stack.

  [re] 142a:0034 -- load the Real, FMUL by $2C, FADD $30, round to a LongInt.
  The parameter is six bytes (RETF 6) arriving in DX:BX:AX, so it is a Borland
  Real; the result is four (the frame reserves and returns only AX and DX).

  [re] TRUNC, NOT ROUND, and the arithmetic and the binary agree. The half is
  already added by hand -- adding 0.5 and then truncating IS rounding, and
  rounding on top of it would round twice. 142a:005c calls System:$3249 and
  the rounding entry is $3268, thirty-one bytes on; part 003's pair sits the
  same distance apart, $31EE and $320D, which is how the two were told apart
  without a runtime library listing. It is one byte of the load image and a
  half-count on the last bit of every fixed-point conversion in the part.
  -------------------------------------------------------------------------- }
function RealToFixed(X : Real) : LongInt;
begin
  RealToFixed := Trunc(X * FixedOne + RoundBias);
end;

{ 16.16 back to Integer, TRUNCATING -- the fraction is simply dropped. Use
  this where a value must never move upwards: a depth-sort key rounded up can
  swap two faces that were level.

  [re] 1483:0071 -- the TRUNCATING conversion: no bias, just a 32-bit shift right
  by 16. Part 002 never calls it and it is absent from that build. }
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
  directives above matter.

  [re] 1483:0099 / 142a:0071 -- the ROUNDING conversion. Despite sitting between
  the two conversions in part 002's build, this is not a
  perspective divide. It builds the Real48 $000000000080 -- which is 0.5 --
  pushes it through RealToFixed to get $8000, adds that to the parameter, and
  shifts the 32-bit result right by 16.
  -------------------------------------------------------------------------- }
function FixedToInt(V : LongInt) : Integer;
begin
  FixedToInt := (V + RealToFixed(0.5)) shr 16;
end;


{ [re] 142a:00a7 -- the unit's initialisation body is empty. }
begin
end.
