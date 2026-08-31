{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.005, the program itself.

  [re] THIS IS THE MAIN BODY, NOT A UNIT CALLED BY A HARNESS. It replaces
  P5MAIN.PAS, which held this code as a unit with a RunPart5 entry, and the
  generated TPART5.PAS that called it. Neither has a counterpart in the 1994
  binary -- the original's main body IS its program -- and carrying them put
  Turbo Pascal's runtime on a different paragraph. Part 005 was the last part
  still built this way.

  [re] THE PROGRAM SEGMENT IS 224 BYTES, 1000:0000..00df. Offsets $00..$28 are the
  unit-initialisation chain, nine far calls, and the body starts at 1000:002d.

      1000:0030   SetMode13h        1252:0000
      1000:0035   VirtScrAlloc      1252:0006
      1000:003a   MusicDetect       12c8:0000
      1000:003f   MusicFunc3        12c8:006a  -- and part 001 was the only
                                    other part known to call function 3
      1000:0044   MusicCue          12c8:0093
      1000:0049   MusicStart        12c8:004e
      1000:004e   Scene1            100e:07a4
      1000:0053   drain the keyboard, INLINE
      1000:0063   Scene2            1096:03d7
      1000:0078   Scene3            1102:035a
      1000:008d   the music fade
      1000:00cd   VirtScrFree       1252:0033
      1000:00d3   the exit

  MODE BEFORE ALLOC, which is the usual order -- part 001 is the odd one out
  and allocates first. Worth knowing before assuming the two parts share a
  startup sequence.

  [re] which is the usual order and NOT part 001's: 1000:0030
  sets mode 13h and 1000:0035 allocates. Part 001 does it the other way round,
  so neither order can be assumed from the other.

  [re] BOTH THE FADE'S VARIABLES ARE GLOBALS AND BOTH ARE BYTES. 1000:0092 is
  MOV BYTE PTR [$2D7C],AL, an absolute store, so they are not locals; and the
  fade reads GetVolume TWICE a turn, storing it into V both times, with
  1000:00b8 testing the second value. There is no test before the first turn,
  so it is repeat..until.

  AND THERE IS NO SetRGB AT THE END, unlike part 001's: the body goes straight
  from SetVolume to VirtScrFree and out. Part 005 leaves the adapter in mode 13h
  for whatever PSYCHO.EXE ran next; RUNPART.BAT restores it with VIDMODE.
  =========================================================================== }

{ 286 instructions are permitted. This setting is PER FILE and a program is a
  file, so nothing here inherits it from the units. }
{$G+}   { [re] 286, AND A PROGRAM IS A FILE -- nothing inherits $G from its units.
          1000:00b1 is PUSH $0A for Delay's argument and 1000:00d2 is LEAVE;
          without $G+ those become MOV AX,$000A / PUSH AX and POP BP, which is
          two bytes too many. Part 001's program taught this. }

program Neur5;

{ THE UNITS ARE NAMED IN REVERSE ORDER HERE, and that is deliberate: Turbo
  Pascal walks the clause depth first, so the unit named FIRST finishes first
  and lands LAST in the executable. The clause is the link order backwards, and
  sorting it into scene order would change the layout of the whole program.

  [re] THE USES CLAUSE IS THE LINK ORDER, REVERSED, and it is the harness's clause
  followed by P5Main's. DemoVT (12c8), Crt (1266) and VGA (1252) are named first
  and so land LAST in code. FixMath (124a) is NOT named -- nothing names it
  directly and the scene that needs it pulls it in there, which is where the
  original has it, between P5PATCH and VGA.

  THE THREE SCENE UNITS ARE BACKWARDS ON PURPOSE, carried from P5MAIN.PAS which
  this file replaces. That clause fixes BOTH layouts and they run opposite ways:
  code segments follow it, DGROUP runs back down it. Measured 25 Aug 2026 by
  building it both ways -- in scene order the code came out P5PATCH, P5ROTO, P5MESH,
  reversed, with 5,182 of 11,648 initialised bytes differing; as written below
  P5MESH lands first and the four trailing units are exact.

  [re] THE COVERAGE WALK CANNOT TELL THOSE APART. It reported 10,980 of 11,440
  aligned, the same number to the byte, for a build whose three scene units were
  in reverse order, because it locates a segment by CONTENT. Only dgimage.py and
  the segment sizes see it. }
uses DemoVT, Crt, VGA,
     P5PATCH, P5ROTO, P5MESH;

var
  SavedVol : Byte;                { DS:$2D7C -- a GLOBAL, and a Byte }
  V        : Byte;                { DS:$2D7D }

{ 1000:002d }
begin
  SetMode13h;                     { 1000:0030 -> 1252:0000 }
  VirtScrAlloc;                   { 1000:0035 -> 1252:0006 }

  MusicDetect;                    { 1000:003a -> 12c8:0000 }
  MusicFunc3;                     { 1000:003f -> 12c8:006a }
  MusicCue;                       { 1000:0044 -> 12c8:0093 }
  MusicStart;                     { 1000:0049 -> 12c8:004e }

  Scene1;   while KeyPressed do ReadKey;   { 1000:004e, drain at 0053 }
  Scene2;   while KeyPressed do ReadKey;   { 1000:0063, drain at 0068 }
  Scene3;   while KeyPressed do ReadKey;   { 1000:0078, drain at 007d }

  { 1000:008d -- ride the volume down to nothing, ten milliseconds a step.
    With no tracker resident GetVolume answers zero and this falls straight
    through, the same as part 004's ending. }
  SavedVol := GetVolume;          { 1000:008d }
  repeat
    V := GetVolume;               { 1000:0095 }
    SetVolume(V - 1);             { 1000:00a4 }
    V := GetVolume;               { 1000:00a9 }
    Delay(10);                    { 1000:00b3 }
  until V = 0;                    { 1000:00b8 }

  MusicStop;                      { 1000:00bf -> 12c8:005c }
  SetVolume(SavedVol);            { 1000:00c8 -> 12c8:00d8 }
  VirtScrFree;                    { 1000:00cd -> 1252:0033 }

  { NO Halt(0). `end.` already emits LEAVE / XOR AX,AX / LCALL System:0116 at
    1000:00d2, and an explicit Halt(0) emits that sequence twice -- seven bytes
    the original does not spend. P5MAIN.PAS carried one, with a comment pointing
    at the address of the single copy the original has. }
end.
