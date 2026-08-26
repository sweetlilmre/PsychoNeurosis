unit PROBE;

{ WHEN DOES TURBO PASCAL REFUSE AN ASSIGNMENT TO A `for` CONTROL VARIABLE?

  The wiki's `loop-variable-assigned-is-not-local` says it refuses one declared
  in the same routine and allows one declared outside, and concludes that a
  store into the counter proves the counter is not a local. Part 004's Spawn
  contradicts that: N is a local at [BP-$02], the routine opens ENTER $06, and
  `N := MaxLem` inside the loop compiled and emitted MOV WORD PTR [BP-2],$19 --
  the same instruction the original has at 1005:07c4.

  The assignment there sits inside a `with` block, so the question is whether
  that is what defeats the check. Each procedure below is one placement; the
  ones that do not compile have to be commented out to get a build at all, so
  the RESULT IS WHICH LINES HAD TO BE COMMENTED, recorded here as they are
  found rather than inferred. }

interface

procedure P1(var R : Integer);
procedure P2(var R : Integer);
procedure P3(var R : Integer);

implementation

type
  TRec = record A, B : Integer end;

var
  G : Integer;                     { declared OUTSIDE, for the control case }
  Rec : TRec;

{ (a) assignment to a local control variable, directly in the loop body }
procedure P1(var R : Integer);
var
  N : Integer;
begin
  for N := 1 to 25 do
  begin
    R := N;
    N := 25;
  end;
end;

{ (b) the same, but inside a `with` block -- which is Spawn's shape }
procedure P2(var R : Integer);
var
  N : Integer;
begin
  for N := 1 to 25 do
    with Rec do
    begin
      A := N;
      N := 25;
    end;
end;

{ (c) the control case: a counter declared outside the routine }
procedure P3(var R : Integer);
begin
  for G := 1 to 25 do
  begin
    R := G;
    G := 25;
  end;
end;

end.
