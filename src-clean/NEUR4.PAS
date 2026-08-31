{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.004, the program itself.

  It replaces the generated TPART4.PAS harness, which called the same routine
  but wrapped it in a NEUROSIS.DAT check, a Say procedure and an exit handler.
  None of those exist in the original, and carrying them put Turbo Pascal's
  runtime on a different paragraph, so every far call into it differed. That
  check now lives outside the part, in RUNPART.BAT. }

{ 286 instructions are permitted. This setting is PER FILE and a program is a
  file, so nothing here inherits it from the units. }
{$G+}

program Neur4;

uses Crt, VGA, DemoVT, P4Lems;

{  And a first attempt had
  the body as `RunPart4` alone, which came out 48 bytes against the original's
  80 and cost 23 bytes on the walk, because a short program segment moves the
  runtime just as a long one does. }
begin
  SetMode13h;
  VirtScrAlloc;
  RunPart4;                       { Demo_Main }
  while KeyPressed do ReadKey;
  VirtScrFree;
  { NO Halt(0). `end.` already emits the exit -- LEAVE / XOR AX,AX /
    LCALL System:0116 -- so an explicit Halt(0) puts that sequence in TWICE,
    once for the statement and once for the end of the body. Seven bytes, and
    every program in this corpus except part 001's and part 005's had them:
    the comment that used to sit here pointed at the address of the single copy
    the original has, which is exactly what a doubled one looks like. }
end.
