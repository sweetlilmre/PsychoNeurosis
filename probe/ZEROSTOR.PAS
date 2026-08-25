{ ===========================================================================
  Which form does an Integer set to zero compile to, and does any installed
  compiler disagree?

  ASKED BECAUSE THE COUNTS ARE EXACTLY SWAPPED. Part 003's original uses
  `MOV WORD PTR [x], 0` fifteen times and `XOR AX,AX / MOV [x], AX` five;
  our rebuild uses the immediate form five times and the xor form fifteen.
  Both builds contain both forms, so the compiler emits both and something in
  the source decides which.

  WHAT THIS PROBE ESTABLISHED, 25 Aug 2026:

    Integer := 0      ->  XOR AX,AX / MOV [x],AX      5 bytes
    Real    := 0.0    ->  three MOV WORD PTR [x],0    6 bytes each
    Integer := 3      ->  MOV WORD PTR [x],3          6 bytes

  and TP6, TP6.1 and TP7 emit IDENTICAL CODE for all of it. So the immediate
  form for a NON-zero constant is normal, the xor form for zero is normal, and
  a compiler-version difference is REFUTED -- which also follows from the
  original using the xor form five times itself.

  AND A LONGINT ASSIGNED A SMALL CONSTANT emits an immediate zero for its HIGH
  word:  `M := 45`  ->  MOV WORD PTR [M],45 / MOV WORD PTR [M+2],0.  So a lone
  immediate zero store CAN be a LongInt's high half, low word first.  `L := 0`
  is XOR AX,AX and then TWO register stores, not two immediates.

  WHAT IT DID NOT SETTLE: why the original's single-word zero stores at
  1139:0310 ($BEB8), 1139:031c ($BEAE) and 1139:0322 ($BEB0) use the immediate
  form when this probe says a plain Integer does not.  ELIMINATED so far:
  a compiler-version difference (all three agree, and the original uses the xor
  form five times itself); the variable's type being Word rather than Integer
  (not one byte changed); a named `= 0` constant instead of the literal (it
  folds and the xor form comes back); interleaving with non-zero immediate
  stores (`A := 0; B := 45; C := 0` still gives xor for both zeros); and the
  LongInt high-word case above, since the original's six stores at
  1139:0310..032e are one word each.

  THE UNTESTED CORRELATION worth trying next: the original's InitScene has NO
  STACK FRAME -- it ends `C3` where ours ends `C9 C3`, so there is no LEAVE and
  therefore no prologue -- while every procedure in this probe has one and every
  one of them uses the xor form.  Whether TP's zero peephole needs BP set up is
  a question a probe can answer, and the frame is a 4-byte difference in its own
  right.
  =========================================================================== }
unit ZEROSTOR;

interface

procedure ZeroThem;
procedure Interleaved;
procedure Longs;

implementation

var
  A, B, C : Integer;
  R       : Real;
  L, M    : LongInt;

procedure ZeroThem;
begin
  A := 0;
  B := 0;
  C := 0;
end;

{ The shape the original has: zeros INTERLEAVED with non-zero constants. }
procedure Interleaved;
begin
  A := 0;
  B := 45;
  C := 0;
  R := 0.0;
end;

{ Does a LongInt store as two immediate words, and in which order? The
  original does [$BEB8] := 0 BEFORE [$BEB6] := $2d, which reads as high word
  first for a LongInt based at $BEB6. }
procedure Longs;
begin
  L := 0;
  M := 45;
end;

end.
