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

(* STACK CHECKING ON, AND THIS UNIT IS THE ONLY ONE THAT HAS IT. Every entry
  point in the original opens `MOV AX,<frame size>` then a far CALL to
  14b1:0530 BEFORE `SUB SP,n` -- 142a:0037 for RealToFixed, 142a:0074 for
  FixedToInt, 142a:0003 for IntToFixed -- which is what Turbo Pascal emits
  under {$S+}. build.toml passes /$S- on the command line for the whole
  project, so this unit has to say otherwise for itself.

  The hot routines elsewhere do NOT have it and must not get it: P2View's
  Plot at 140c:00b1 and FillRect at 140c:011e open `PUSH BP / MOV BP,SP` and
  go straight into the body, and P2SOLID's ObjTransform opens a bare ENTER.

  IT MAKES THE REBUILD SLOWER, and that is the right direction. FixedToInt is
  called once per vertex and calls RealToFixed once itself, so the original
  pays roughly 150 of these checks per frame that the reconstruction was
  skipping. A switch is set to match the emitted code, never to make the
  rebuild faster. *)
{$S+}
(* 286 CODE ON. 142a:00A3 is `LEAVE / RETF 4` and this unit had no G directive
   at all, so it took the command line's default and emitted MOV SP,BP / POP BP
   -- two bytes more, at the end of every routine in it. *)
{$G+}
(* 80x87 CODE ON. 142a:004b calls one runtime routine and then executes x87
   instructions -- 142a:0050 is INT $3C, which under E-plus is what an 80x87
   opcode ships as. This unit had NO N directive at all, so it took the
   N-minus default: floating point became far calls into the software
   six-byte Real library, which is a different instruction stream entirely
   and shows as `MOV CX,$91 / XOR SI,SI / XOR DI,DI` before the call.

   A trap is positive evidence OF 80x87 code, not against it -- the N-minus
   setting emits no 80x87 instructions and therefore no traps either. That
   has been got wrong three times in this corpus; the register's
   part5-386-trio resolution is the long form.

   THIS IS THE PER-VERTEX PATH: ObjTransform calls FixedToInt once per vertex
   and FixedToInt calls RealToFixed, so whichever way this compiles is paid
   about seventy-five times a frame. *)
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

  TRUNC, NOT ROUND, and the arithmetic and the binary agree. The half is
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
