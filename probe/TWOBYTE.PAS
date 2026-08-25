{ ===========================================================================
  WHICH CONSTRUCTS COST TWO BYTES OF FRAME?

  ASKED BECAUSE THREE ROUTINES IN THREE PARTS ARE EXACTLY TWO BYTES TOO BIG and
  in every one of them our declarations total the original's frame exactly:

      P5S2 Shatter     1096:0042   ENTER $26,  ours $28   -- 17 locals sum 38
      P6S1 Whoosh      1095:067d   ENTER $112, ours $114  -- 256 + 9 words
      P7S1 UpCaseStr   100f:06f7   ENTER $104, ours $106  -- 256 + 2 + 2

  So the two bytes are a COMPILER TEMPORARY our bodies create and the originals
  do not.

  THE DESIGN, AND IT IS THE POINT: each routine pads itself to a DISTINCT size,
  so the frame IDENTIFIES the routine and a temporary shows up as +2 on a known
  base. A first attempt scanned the compiled unit for `ENTER` byte patterns and
  mapped them to routines by ORDER, which mis-paired: the scan picks up data
  bytes that happen to read as C8 xx yy 00, and anchoring on a preceding return
  did not fix it. Self-identifying frames need no scan order at all.

      routine n declares Pad : array[1..n*10] of Byte and one Integer,
      so its base frame is 10n + 2 and a temporary makes it 10n + 4.

  Nothing here is meant to run.
  =========================================================================== }
unit TWOBYTE;

{$N+}
{$G+}
{$S-}
{$R-}

interface

procedure P1(S : String);
procedure P2(S : String);
procedure P3;
procedure P4;
procedure P5;
procedure P6(S : String);
procedure P7;
procedure P8;
procedure P9(S : String);

implementation

type
  TRec = record A, B : Integer; end;
var
  G1, G2, G3, G4 : Integer;
  GB : Byte;
  GA : array[1..4] of TRec;

{ base 12 -- CONTROL: a String parameter and one local, nothing else }
procedure P1(S : String);
var Pad : array[1..10] of Byte; I : Integer;
begin
  I := 1; G1 := I; Pad[1] := 0;
end;

{ base 22 -- for over a GLOBAL limit }
procedure P2(S : String);
var Pad : array[1..20] of Byte; I : Integer;
begin
  for I := 1 to G1 do G2 := I;
  Pad[1] := 0;
end;

{ base 32 -- for over a LOCAL limit }
procedure P3;
var Pad : array[1..30] of Byte; I, L : Integer;
begin
  L := G1;
  for I := 1 to L do G2 := I;
  Pad[1] := 0;
end;

{ base 42 -- (a-b)*c div d + e, Shatter's shape }
procedure P4;
var Pad : array[1..40] of Byte; I : Integer;
begin
  I := (G1 - G2) * G3 div G4 + G1;
  Pad[1] := 0;
end;

{ base 52 -- case on a variable }
procedure P5;
var Pad : array[1..50] of Byte; I : Integer;
begin
  case G1 of
    0 : I := 1;
    1 : I := 2;
  else I := 3;
  end;
  G2 := I; Pad[1] := 0;
end;

{ base 62 -- a String parameter's element assigned through a function }
procedure P6(S : String);
var Pad : array[1..60] of Byte; I : Integer;
begin
  for I := 1 to 3 do S[I] := UpCase(S[I]);
  Pad[1] := 0;
end;

{ base 72 -- with over an array element }
procedure P7;
var Pad : array[1..70] of Byte; I : Integer;
begin
  I := 1;
  with GA[I] do begin A := 1; B := 2; end;
  Pad[1] := 0;
end;

{ base 82 -- an expression used as an array subscript }
procedure P8;
var Pad : array[1..80] of Byte; I : Integer;
begin
  I := GA[G1 * 2 - 1].A;
  G2 := I; Pad[1] := 0;
end;

{ base 92 -- UpCaseStr's exact shape: L := Length(S), then for over L }
procedure P9(S : String);
var Pad : array[1..90] of Byte; I, L : Integer;
begin
  L := Length(S);
  for I := 1 to L do S[I] := UpCase(S[I]);
  Pad[1] := 0;
end;

end.
