{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.005, the program itself.

  MODE BEFORE ALLOC, which is the usual order -- part 001 is the odd one out
  and allocates first. Worth knowing before assuming the two parts share a
  startup sequence.

  AND THERE IS NO SetRGB AT THE END, unlike part 001's: the body goes straight
  from SetVolume to VirtScrFree and out. Part 005 leaves the adapter in mode 13h
  for whatever PSYCHO.EXE ran next; RUNPART.BAT restores it with VIDMODE.
  =========================================================================== }

{ 286 instructions are permitted. This setting is PER FILE and a program is a
  file, so nothing here inherits it from the units. }
{$G+}

program Neur5;

{ THE UNITS ARE NAMED IN REVERSE ORDER HERE, and that is deliberate: Turbo
  Pascal walks the clause depth first, so the unit named FIRST finishes first
  and lands LAST in the executable. The clause is the link order backwards, and
  sorting it into scene order would change the layout of the whole program.

  THE THREE SCENE UNITS ARE BACKWARDS ON PURPOSE, carried from P5MAIN.PAS which
  this file replaces. That clause fixes BOTH layouts and they run opposite ways:
  code segments follow it, DGROUP runs back down it. Measured 25 Aug 2026 by
  building it both ways -- in scene order the code came out P5PATCH, P5ROTO, P5MESH,
  reversed, with 5,182 of 11,648 initialised bytes differing; as written below
  P5MESH lands first and the four trailing units are exact. }
uses DemoVT, Crt, VGA,
     P5PATCH, P5ROTO, P5MESH;

var
  SavedVol : Byte;                { a GLOBAL, and a Byte }
  V        : Byte;

begin
  SetMode13h;
  VirtScrAlloc;

  MusicDetect;
  MusicFunc3;
  MusicCue;
  MusicStart;

  Scene1;   while KeyPressed do ReadKey;   { drain at 0053 }
  Scene2;   while KeyPressed do ReadKey;   { drain at 0068 }
  Scene3;   while KeyPressed do ReadKey;   { drain at 007d }

  { ride the volume down to nothing, ten milliseconds a step.
    With no tracker resident GetVolume answers zero and this falls straight
    through, the same as part 004's ending. }
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

  { NO Halt(0) HERE. `end.` already emits the exit sequence, so an explicit
    Halt(0) emits it twice -- seven bytes the original does not spend. }
end.
