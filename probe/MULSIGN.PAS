unit PROBE;

{ WHICH SPELLING OF `(a - b) * t div d` EMITS  CWD / IMUL / IDIV ?

  Part 005's 1096:0331 does, in this order:

      mov ax,[X1] / sub ax,[X0] / cwd / imul word [T] / idiv word [Denom]

  and the reconstruction, written the obvious way with every variable declared
  Integer, emits instead:

      mov ax,[X1] / sub ax,[X0] / mul word [T] / cwd / idiv word [Denom]

  which is not merely different bytes -- it is WRONG. MUL leaves the product in
  DX:AX and the CWD that follows overwrites DX with the sign of AX, so the
  product's high half is discarded before the divide ever sees it. Any pair of
  operands whose product exceeds 16 bits divides from a truncated dividend.

  An earlier attempt cast the left operand to LongInt and measured worse, on the
  reasoning that the cast forces the runtime's 32-bit multiply. That was one
  spelling tried once against a whole-part percentage. This tries eight and
  reads the bytes. }

interface

procedure P1(X0, X1, T, Denom : Integer; var R : Integer);
procedure P2(X0, X1, T, Denom : Integer; var R : Integer);
procedure P3(X0, X1, T, Denom : Integer; var R : Integer);
procedure P4(X0, X1, T, Denom : Integer; var R : Integer);
procedure P5(X0, X1, T, Denom : Integer; var R : Integer);
procedure P6(X0, X1, T, Denom : Integer; var R : Integer);
procedure P7(X0, X1, T, Denom : Integer; var R : Integer);
procedure P8(X0, X1, T, Denom : Integer; var R : Integer);

implementation

{ the reconstruction's spelling, for the baseline }
procedure P1(X0, X1, T, Denom : Integer; var R : Integer);
begin
  R := (X1 - X0) * T div Denom + X0;
end;

{ the addend first -- does the statement's shape change the multiply? }
procedure P2(X0, X1, T, Denom : Integer; var R : Integer);
begin
  R := X0 + (X1 - X0) * T div Denom;
end;

{ the multiply's operands the other way round }
procedure P3(X0, X1, T, Denom : Integer; var R : Integer);
begin
  R := T * (X1 - X0) div Denom + X0;
end;

{ the left operand cast -- the attempt that measured worse, measured properly }
procedure P4(X0, X1, T, Denom : Integer; var R : Integer);
begin
  R := LongInt(X1 - X0) * T div Denom + X0;
end;

{ the difference parenthesised as its own term }
procedure P5(X0, X1, T, Denom : Integer; var R : Integer);
var
  D : Integer;
begin
  D := X1 - X0;
  R := D * T div Denom + X0;
end;

{ the whole quotient cast down }
procedure P6(X0, X1, T, Denom : Integer; var R : Integer);
begin
  R := Integer((X1 - X0) * T div Denom) + X0;
end;

{ the multiplier cast instead of the multiplicand }
procedure P7(X0, X1, T, Denom : Integer; var R : Integer);
begin
  R := (X1 - X0) * LongInt(T) div Denom + X0;
end;

{ both sides of the multiply plainly signed, divisor cast }
procedure P8(X0, X1, T, Denom : Integer; var R : Integer);
begin
  R := (X1 - X0) * T div LongInt(Denom) + X0;
end;

end.
