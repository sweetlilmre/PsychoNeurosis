{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the program itself.

  It replaces P2MAIN.PAS, which held this as a unit with a RunPart2 entry, and
  the generated TPART2.PAS that called it -- 64 and 496 bytes of segment the
  original does not have.

  THE KEYBOARD DRAIN IS WRITTEN INLINE at every site rather than as a
  procedure. Each scene can end on a keypress, and the drain throws that key
  away so the next scene does not see it and skip itself.

  Note what is NOT here: no music start or stop, and no palette fade. Each
  scene drives the tracker itself -- Scene1 detects and cues it, Scene2 starts
  it and ramps the volume down at the end. And no SetTextMode: part 002 left
  the adapter in mode 13h for whatever PSYCHO.EXE ran next, so RUNPART.BAT
  restores it with VIDMODE. }

{ 286 instructions are permitted. This setting is PER FILE and a program is a
  file, so nothing here inherits it from the units. }
{$G+}

program Neur2;

uses Crt, VGA, FixMath, P2View, DemoVT, P2SOLID, ModeX, P2GARAGE;

{ and it ends in Halt(0), exactly as the original's does. }
begin
  SetMode13h;
  VirtScrAlloc;

  Scene1;
  while KeyPressed do ReadKey;

  Scene2;
  while KeyPressed do ReadKey;

  VirtScrFree;
  { NO Halt(0). `end.` already emits the exit -- LEAVE / XOR AX,AX /
    LCALL System:0116 -- so an explicit Halt(0) puts that sequence in TWICE,
    once for the statement and once for the end of the body. Seven bytes, and
    every program in this corpus except part 001's and part 005's had them:
    the comment that used to sit here pointed at the address of the single copy
    the original has, which is exactly what a doubled one looks like. }
end.
