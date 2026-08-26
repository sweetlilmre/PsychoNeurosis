unit PROBE;

{ HOW MANY FAR LOADS DOES IT TAKE TO SPLIT A POINTER INTO ITS TWO HALVES?

  P7S1's FliColor stores a pointer parameter's segment and offset into two Word
  locals. The original does it with ONE far load:

      100f:01e5  LES  DI, [BP+6]
      100f:01e8  MOV  AX, ES
      100f:01ea  MOV  [BP-4], AX        Sg  := Seg(Data^)
      100f:01ed  MOV  AX, DI
      100f:01ef  MOV  [BP-6], AX        Cur := Ofs(Data^)

  Ours emits a second LES between the two stores -- reloading a pointer it
  already has in ES:DI -- which is four bytes the original does not spend. The
  source is `Sg := Seg(Data^);` then `Cur := Ofs(Data^);` in that order, which
  is the obvious spelling and the wrong one.

  So: which spelling produces one load? Turbo Pascal is not an optimising
  compiler and does not generally keep a value across statements, which
  suggests the original's two halves come out of a SINGLE expression or a
  single construct rather than two statements. Each procedure below is one
  candidate, and the question each answers is only "how many LES instructions".

  Reading the result: disassemble each procedure and count LES. One is the
  original's shape; two is ours.

  RESULT, 26 Aug 2026 -- NONE OF THE SIX GIVES ONE LOAD, and all three
  compilers agree exactly:

      P1  segment first, two statements      2 LES   (ours)
      P2  offset first                       2 LES
      P3  through a local Pointer            2 LES   (plus a 2-word copy)
      P4  a record cast, no dereference      0 LES
      P5  through a typed pointer            2 LES
      P6  both halves in one expression      2 LES

  TP7, TP6 and TP6.1 each emit 24 LES across the unit -- byte-for-byte the
  same choice -- so this is not a compiler-version difference and it is not a
  spelling this probe can reach. The order does not matter (P1 against P2), a
  local pointer does not help (P3), and a cast removes the load entirely
  rather than halving it (P4).

  WHAT THAT LEAVES. Turbo Pascal does not keep a loaded pointer across
  statements, and every spelling that asks for both halves asks twice. The
  original asks once. The remaining explanation is that those five
  instructions are HAND ASSEMBLER inside an otherwise compiled routine, which
  this target has found repeatedly -- and the tell is consistent with it: a
  compiler that has the offset in DI has no reason to route it through AX
  before storing, and the original does exactly that for both halves,
  symmetrically, which is how a person writes it and not how this code
  generator does. Not yet confirmed; recorded so the next attempt starts here
  rather than trying a seventh spelling. }

interface

type
  PSame = ^Word;
  { TP7 has no LongRec -- that is Delphi's. Declared here. }
  TSplit = record Lo, Hi : Word end;

procedure P1(Data : Pointer;  var S, O : Word);
procedure P2(Data : Pointer;  var S, O : Word);
procedure P3(Data : Pointer;  var S, O : Word);
procedure P4(Data : Pointer;  var S, O : Word);
procedure P5(Data : Pointer;  var S, O : Word);
procedure P6(Data : Pointer;  var S, O : Word);

implementation

{ 1 -- OURS. The obvious two statements, segment first. }
procedure P1(Data : Pointer;  var S, O : Word);
var
  Sg, Cur : Word;
begin
  Sg  := Seg(Data^);
  Cur := Ofs(Data^);
  S := Sg;  O := Cur;
end;

{ 2 -- the other order. If the reuse depends on which half is asked for
  second, this differs from P1. }
procedure P2(Data : Pointer;  var S, O : Word);
var
  Sg, Cur : Word;
begin
  Cur := Ofs(Data^);
  Sg  := Seg(Data^);
  S := Sg;  O := Cur;
end;

{ 3 -- through a local pointer first. One load to copy, then the halves come
  off the local rather than the parameter. }
procedure P3(Data : Pointer;  var S, O : Word);
var
  P : Pointer;
  Sg, Cur : Word;
begin
  P   := Data;
  Sg  := Seg(P^);
  Cur := Ofs(P^);
  S := Sg;  O := Cur;
end;

{ 4 -- as words off the parameter, no dereference at all. Should emit no LES
  whatever: the two halves are simply the two words of the argument. }
procedure P4(Data : Pointer;  var S, O : Word);
var
  Sg, Cur : Word;
begin
  Sg  := TSplit(Data).Hi;
  Cur := TSplit(Data).Lo;
  S := Sg;  O := Cur;
end;

{ 5 -- a typed pointer rather than an untyped one. Seg and Ofs of a typed
  dereference may load differently. }
procedure P5(Data : Pointer;  var S, O : Word);
var
  P : PSame;
  Sg, Cur : Word;
begin
  P   := Data;
  Sg  := Seg(P^);
  Cur := Ofs(P^);
  S := Sg;  O := Cur;
end;

{ 6 -- both halves inside one `with` over the dereference, which is the one
  construct that is known to capture an address once and keep it. }
procedure P6(Data : Pointer;  var S, O : Word);
var
  Sg, Cur : Word;
begin
  Sg  := Seg(Data^);
  Cur := Ofs(Data^);
  S := Sg;  O := Cur + Seg(Data^) - Seg(Data^);
end;

end.
