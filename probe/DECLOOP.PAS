{ ===========================================================================
  WHICH DECREMENT-AND-TEST LOOP EMITS `DEC [mem]` FOLLOWED STRAIGHT BY `JNE`?

  ASKED BECAUSE PART 003's MORPH SCENE DOES IT FOUR TIMES AND OURS DOES NOT.
  1139:0414 is DEC WORD PTR [$BEC2] / JNE, six bytes; ours emits DEC, then
  CMP WORD PTR [$BEC2],0, then JNE -- five bytes more, at each of four loops,
  and everything after each of them shifts.

  Same variable, same address, same apparent source. So the source is NOT the
  same, and the question is which spelling of "count down and stop at zero"
  lets Turbo Pascal keep the DEC's own flags.

  Each variant marks itself: MOV [Mark],n immediately before the loop, so the
  bytes can be paired to the variant without depending on emission order.
  Nothing here is meant to run.
  =========================================================================== }
unit DECLOOP;

{$N+}
{$G+}
{$S-}
{$R-}
{$I-}

interface

procedure V1; procedure V2; procedure V3; procedure V4;
procedure V5; procedure V6; procedure V7;

implementation

var
  Mark   : Integer;
  FramesI : Integer;
  FramesW : Word;
  FramesB : Byte;

procedure Tick; begin Mark := Mark + 0; end;

{ 1 -- repeat Dec(x) until x = 0, Integer, nothing between }
procedure V1;
begin
  Mark := 1;
  repeat Dec(FramesI); until FramesI = 0;
end;

{ 2 -- the same with a call in the body BEFORE the Dec }
procedure V2;
begin
  Mark := 2;
  repeat Tick; Dec(FramesI); until FramesI = 0;
end;

{ 3 -- until x <= 0 }
procedure V3;
begin
  Mark := 3;
  repeat Dec(FramesI); until FramesI <= 0;
end;

{ 4 -- an assignment instead of Dec }
procedure V4;
begin
  Mark := 4;
  repeat FramesI := FramesI - 1; until FramesI = 0;
end;

{ 5 -- Word rather than Integer }
procedure V5;
begin
  Mark := 5;
  repeat Dec(FramesW); until FramesW = 0;
end;

{ 6 -- until x <> 0 is false, spelled as a while }
procedure V6;
begin
  Mark := 6;
  while FramesI <> 0 do Dec(FramesI);
end;

{ 7 -- Byte }
procedure V7;
begin
  Mark := 7;
  repeat Dec(FramesB); until FramesB = 0;
end;

end.
