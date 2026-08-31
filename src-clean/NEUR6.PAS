{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.006, the program itself.

  It replaces P6MAIN.PAS, which held this code as a unit with a RunPart6 entry,
  and the generated TPART6.PAS that called it. Neither has a counterpart in the
  1994 binary -- its main body IS its program -- and carrying them put Turbo
  Pascal's runtime on a different paragraph, so every far call into it differed.

  THE SCENE ORDER IS NOT THE SEGMENT ORDER. The units initialise 100f last of
  the four, but the main body calls 1095 first. Segment number tells you the
  link order, not the running order.

  THERE IS NO SetTextMode AT THE END, and that is the original's doing: the demo
  ran under PSYCHO.EXE and part 006 left the adapter in mode 13h for whatever
  came next. RUNPART.BAT restores it with VIDMODE. }

{ 286 instructions are permitted. This setting is PER FILE and a program is a
  file, so nothing here inherits it from the units. }
{$G+}

program Neur6;

uses DemoVT, Crt, VGA, P6CREDIT, P6FIRE, P6WHOOSH, P6TILES;

var
  SavedVol : Byte;
  V        : Byte;

{ and it ends in Halt(0), exactly as the original's does. }
begin
  SetMode13h;
  VirtScrAlloc;

  MusicDetect;
  MusicFunc3;
  MusicCue;
  MusicStart;

  Scene1;
  while KeyPressed do ReadKey;
  Scene2;
  while KeyPressed do ReadKey;
  Scene3;
  while KeyPressed do ReadKey;
  Scene4;
  while KeyPressed do ReadKey;

  { ride the volume down, ten milliseconds a step. With no
    tracker resident GetVolume answers zero and this falls straight through. }
  SavedVol := GetVolume;
  repeat
    V := GetVolume;
    SetVolume(V - 1);
    V := GetVolume;
    Delay(10);
  until V = 0;

  MusicStop;
  SetVolume(SavedVol);
  VirtScrFree;
  { NO Halt(0). `end.` already emits the exit -- LEAVE / XOR AX,AX /
    LCALL System:0116 -- so an explicit Halt(0) puts that sequence in TWICE,
    once for the statement and once for the end of the body. Seven bytes, and
    every program in this corpus except part 001's and part 005's had them:
    the comment that used to sit here pointed at the address of the single copy
    the original has, which is exactly what a doubled one looks like. }
end.
