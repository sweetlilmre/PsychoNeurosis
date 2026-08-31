{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the program itself.

  THIS IS THE MAIN BODY, NOT A UNIT CALLED BY A HARNESS. Segment 1000 is 128
  bytes; the body starts at 1000:0032.

 SetMode13h        1436:0000, which is the same physical
                                    bytes as 142a:00c0 -- the two segments
                                    overlap, so FixMath already has it
 VirtScrAlloc      1436:0006
 Demo_Scene1       1008:0724
 flush the keyboard, INLINE
 Demo_Scene2       108b:2454
 flush the keyboard, INLINE
 VirtScrFree       1436:0033
 Halt(0)

  It replaces P2MAIN.PAS, which held this as a unit with a RunPart2 entry, and
  the generated TPART2.PAS that called it -- 64 and 496 bytes of segment the
  original does not have.

  THE DRAIN IS INLINE, NOT A FlushKeys CALL. 1000:0044 to 0053 is sixteen
  bytes where a call would be five, and part 003 taught this the expensive way:
  with the call its program came out 272 bytes against 336 and removing the
  harness bought nothing at all, because a program segment of the wrong SIZE
  moves the runtime exactly as an extra one does.

  Note what is NOT here: no music start or stop, and no palette fade. Each
  scene drives the tracker itself -- Scene1 detects and cues it, Scene2 starts
  it and ramps the volume down at the end. And no SetTextMode: part 002 left
  the adapter in mode 13h for whatever PSYCHO.EXE ran next, so RUNPART.BAT
  restores it with VIDMODE.

  THE USES CLAUSE IS THE LINK ORDER, REVERSED, and it is the harness's clause
  followed by P2MAIN's. P2SOLID BEFORE ModeX BEFORE P2GARAGE is load-bearing: the
  original's order is P2GARAGE (1008), ModeX (107c), P2SOLID (108b), DemoVT (13f9),
  P2View (140c), FixMath (142a), VGA (1436), Crt (144f), and ModeX lands second
  only because nothing names it directly -- P2GARAGE pulls it in there. Naming it
  in the clause put it sixth. Checked against build/NEUR2.MAP.
  =========================================================================== }

{$G+}   { 286, AND A PROGRAM IS A FILE -- nothing inherits $G from its units.
          Without it an immediate argument comes out MOV AX,imm / PUSH AX rather
          than PUSH imm8, and the frame teardown POP BP rather than LEAVE. }

program Neur2;

uses Crt, VGA, FixMath, P2View, DemoVT, P2SOLID, ModeX, P2GARAGE;

{ and it ends in Halt(0), exactly as the original's does. }
begin
  SetMode13h;                     { -> 1436:0000 }
  VirtScrAlloc;                   { -> 1436:0006 }

  Scene1;                         { -> 1008:0724 }
  while KeyPressed do ReadKey;

  Scene2;                         { -> 108b:2454 }
  while KeyPressed do ReadKey;

  VirtScrFree;                    { -> 1436:0033 }
  { NO Halt(0). `end.` already emits the exit -- LEAVE / XOR AX,AX /
    LCALL System:0116 -- so an explicit Halt(0) puts that sequence in TWICE,
    once for the statement and once for the end of the body. Seven bytes, and
    every program in this corpus except part 001's and part 005's had them:
    the comment that used to sit here pointed at the address of the single copy
    the original has, which is exactly what a doubled one looks like. }
end.
