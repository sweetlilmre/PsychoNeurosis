{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.004, the program itself.

  [re] A DIFFERENT SHAPE FROM PART 007'S, AND THE ORIGINAL DECIDES IT. Part 007's
  main body is the program: forty lines of scene calls and a volume fade at
  segment 1000. Part 004's is not -- its Demo_Main sits INSIDE the scene unit
  at 1005:1cd6, and segment 1000 holds only eighty bytes whose whole job is to
  call it. So this program is a call and nothing else, where NEUR7.PAS carries
  a body.

  It replaces the generated TPART4.PAS harness, which called the same routine
  but wrapped it in a NEUROSIS.DAT check, a Say procedure and an exit handler.
  None of those exist in the original, and carrying them put Turbo Pascal's
  runtime on a different paragraph, so every far call into it differed. That
  check now lives outside the part, in RUNPART.BAT.

  [re] THE USES CLAUSE IS THE LINK ORDER, REVERSED. The link walk is a reverse DFS
  post-order starting at the program, so the last unit to finish comes first in
  code. The original's segments are P4Lems (1005), DemoVT (11d9), VGA (11e3)
  and Crt (1226), so P4Lems has to finish last and Crt first. Checked
  against build/NEUR4.MAP.
  =========================================================================== }

{ 286 instructions are permitted. This setting is PER FILE and a program is a
  file, so nothing here inherits it from the units. }
{$G+}   { [re] 286, AND A PROGRAM IS A FILE -- nothing inherits $G from its units.
          Without it an immediate argument comes out MOV AX,imm / PUSH AX rather
          than PUSH imm8, and the frame teardown POP BP rather than LEAVE. }

program Neur4;

uses Crt, VGA, DemoVT, P4Lems;

{ [re] 1000:001e -- and every instruction of it is accounted for:

      001c  CALLF 11e3:0000     SetMode13h
      0021  CALLF 11e3:0006     VirtScrAlloc
      0026  CALLF 1005:1cd6     Demo_Main, this part's RunPart4
      002b  CALLF 1226:0308     KeyPressed        0030  OR AL,AL / JZ 003b               > while KeyPressed do ReadKey
      0034  CALLF 1226:031a     ReadKey     /
      0039  JMP 002b                        /
      003b  CALLF 11e3:0033     VirtScrFree
      0040  LEAVE / XOR AX,AX
      0043  CALLF 1288:0116     Halt(0)

  [re] READ OFF THE ORIGINAL, AND THE FIRST TWO READINGS WERE WRONG. I took
  11e3:0006 for SetMode13h because 11e3:0000 disassembles as MOV AX,$13 / INT
  $10 / RETF, which IS SetMode13h -- but that is the routine BEFORE the one the
  program calls. 11e3:0006 pushes -$600, calls GetMem, stores the pointer at
  DS:$CF88 and its segment at $CF8C and then FillChars 64,000 bytes: it is
  VirtScrAlloc. Part 004 never changes video mode from its program; P4Lems does
  it.

  And a first attempt had
  the body as `RunPart4` alone, which came out 48 bytes against the original's
  80 and cost 23 bytes on the walk, because a short program segment moves the
  runtime just as a long one does. }
begin
  SetMode13h;                     { 1000:001c -> 11e3:0000 }
  VirtScrAlloc;                   { 1000:0021 -> 11e3:0006 }
  RunPart4;                       { 1000:0026 -> 1005:1cd6, Demo_Main }
  while KeyPressed do ReadKey;    { 1000:002b }
  VirtScrFree;                    { 1000:003b -> 11e3:0033 }
  { NO Halt(0). `end.` already emits the exit -- LEAVE / XOR AX,AX /
    LCALL System:0116 -- so an explicit Halt(0) puts that sequence in TWICE,
    once for the statement and once for the end of the body. Seven bytes, and
    every program in this corpus except part 001's and part 005's had them:
    the comment that used to sit here pointed at the address of the single copy
    the original has, which is exactly what a doubled one looks like. }
end.
