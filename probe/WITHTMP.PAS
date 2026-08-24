{ ===========================================================================
  PROBE -- what makes Turbo Pascal spill a var parameter's far pointer?

  THE QUESTION. Part 002's ObjTransform (108b:00bf) opens ENTER $36 = 54
  bytes. The reconstruction's declared locals now match the original's 46
  bytes exactly -- the loop counter lands at [BP-$0a] in both -- and the
  rebuild still opens ENTER $30. The six-byte gap is entirely COMPILER TEMP:
  the original spills TWO far pointers where ours spills none.

      [BP-$32]/[BP-$30]   @O, loaded once at 108b:00c3 from [BP+$10]
      [BP-$36]/[BP-$34]   a scratch field address, RECOMPUTED per group --
                          @O.Accum at 108b:00cc, @O.Angle at 108b:01b6

  and every access through the second reads es:[di], es:[di+4], es:[di+8] --
  offsets 0, 4, 8 from the temp rather than 0B45h, 0B49h, 0B4Dh from @O.

  THE HYPOTHESIS. That is nested `with` over RECORD-typed fields: an outer
  `with O do` holding @O, and an inner `with Accum do` holding @O.Accum, which
  would mean Accum/Angle/Pivot/Trans are three-field records in the 1994
  source rather than the array[1..3] of LongInt the reconstruction declares.

  WHY IT IS A PROBE AND NOT AN EDIT. Believing it means changing TObj's type
  model across a 1,400-line unit and every routine that touches it. Four
  variants below differ ONLY in with-scope and field shape; the declared
  locals are byte-identical in all four, so any frame difference is the
  construct and nothing else. Read the ENTER operands out of the built unit.

      $30  no spill            $34  one 4-byte spill
      $38  two spills          $36  is what we are looking for

  Nothing here is part of the demo. It exists to settle one measurement.
  =========================================================================== }

unit WithTmp;

{$G+}   { the subject is $G+; ENTER is the instruction being measured }
{$S-}

interface

type
  TVec3R = record
    X, Y, Z : LongInt;
  end;
  TVec3A = array[1..3] of LongInt;

  { Two objects with the same layout, differing only in whether the trailing
    vectors are records or arrays. The 2,850-byte body stands in for the real
    unit's vertex and face tables so the field offsets are far enough from
    zero to need a real displacement, as they are in the original. }
  TObjR = record
    Count : Integer;
    Bulk  : array[1..2848] of Byte;
    Angle : TVec3R;
    Trans : TVec3R;
    Pivot : TVec3R;
    Accum : TVec3R;
  end;
  TObjA = record
    Count : Integer;
    Bulk  : array[1..2848] of Byte;
    Angle : TVec3A;
    Trans : TVec3A;
    Pivot : TVec3A;
    Accum : TVec3A;
  end;

procedure ArraysPlain (var O : TObjA; A1, A2, A3 : LongInt);
procedure ArraysWith  (var O : TObjA; A1, A2, A3 : LongInt);
procedure RecordsPlain(var O : TObjR; A1, A2, A3 : LongInt);
procedure RecordsWith  (var O : TObjR; A1, A2, A3 : LongInt);

implementation

{ The declared locals are IDENTICAL in all four -- 8 dead bytes, the counter,
  12 dead bytes, then two three-LongInt vectors -- so the only thing that can
  move the frame is the construct under test. }

procedure ArraysPlain(var O : TObjA; A1, A2, A3 : LongInt);
var
  Unused1 : array[1..2] of LongInt;
  I       : Integer;
  Unused2 : array[1..3] of LongInt;
  V       : TVec3A;
  P       : TVec3A;
begin
  if O.Accum[1] < 0 then Inc(O.Accum[1], 3600);
  if O.Accum[2] < 0 then Inc(O.Accum[2], 3600);
  if O.Accum[3] < 0 then Inc(O.Accum[3], 3600);
  Move(O.Pivot, P, 12);
  O.Angle[1] := A1;  O.Angle[2] := A2;  O.Angle[3] := A3;
  for I := 1 to O.Count do
  begin
    Move(O.Bulk[I], V, 12);
    V[1] := V[1] + P[1] + O.Trans[1];
    V[2] := V[2] + P[2] + O.Trans[2];
    V[3] := V[3] + P[3] + O.Trans[3];
  end;
end;

procedure ArraysWith(var O : TObjA; A1, A2, A3 : LongInt);
var
  Unused1 : array[1..2] of LongInt;
  I       : Integer;
  Unused2 : array[1..3] of LongInt;
  V       : TVec3A;
  P       : TVec3A;
begin
  with O do
  begin
    if Accum[1] < 0 then Inc(Accum[1], 3600);
    if Accum[2] < 0 then Inc(Accum[2], 3600);
    if Accum[3] < 0 then Inc(Accum[3], 3600);
    Move(Pivot, P, 12);
    Angle[1] := A1;  Angle[2] := A2;  Angle[3] := A3;
    for I := 1 to Count do
    begin
      Move(Bulk[I], V, 12);
      V[1] := V[1] + P[1] + Trans[1];
      V[2] := V[2] + P[2] + Trans[2];
      V[3] := V[3] + P[3] + Trans[3];
    end;
  end;
end;

procedure RecordsPlain(var O : TObjR; A1, A2, A3 : LongInt);
var
  Unused1 : array[1..2] of LongInt;
  I       : Integer;
  Unused2 : array[1..3] of LongInt;
  V       : TVec3A;
  P       : TVec3A;
begin
  if O.Accum.X < 0 then Inc(O.Accum.X, 3600);
  if O.Accum.Y < 0 then Inc(O.Accum.Y, 3600);
  if O.Accum.Z < 0 then Inc(O.Accum.Z, 3600);
  Move(O.Pivot, P, 12);
  O.Angle.X := A1;  O.Angle.Y := A2;  O.Angle.Z := A3;
  for I := 1 to O.Count do
  begin
    Move(O.Bulk[I], V, 12);
    V[1] := V[1] + P[1] + O.Trans.X;
    V[2] := V[2] + P[2] + O.Trans.Y;
    V[3] := V[3] + P[3] + O.Trans.Z;
  end;
end;

procedure RecordsWith(var O : TObjR; A1, A2, A3 : LongInt);
var
  Unused1 : array[1..2] of LongInt;
  I       : Integer;
  Unused2 : array[1..3] of LongInt;
  V       : TVec3A;
  P       : TVec3A;
begin
  with O do
  begin
    with Accum do
    begin
      if X < 0 then Inc(X, 3600);
      if Y < 0 then Inc(Y, 3600);
      if Z < 0 then Inc(Z, 3600);
    end;
    Move(Pivot, P, 12);
    with Angle do
    begin
      X := A1;  Y := A2;  Z := A3;
    end;
    for I := 1 to Count do
    begin
      Move(Bulk[I], V, 12);
      V[1] := V[1] + P[1] + Trans.X;
      V[2] := V[2] + P[2] + Trans.Y;
      V[3] := V[3] + P[3] + Trans.Z;
    end;
  end;
end;

end.
