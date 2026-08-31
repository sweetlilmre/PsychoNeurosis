{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.006, the program itself.

  THIS IS THE MAIN BODY, NOT A UNIT CALLED BY A HARNESS. Segment 1000, offsets
  $00..$ef: everything up to 1000:0028 is Turbo Pascal's unit initialisation
  chain and the program starts at 1000:002d.

  It replaces P6MAIN.PAS, which held this code as a unit with a RunPart6 entry,
  and the generated TPART6.PAS that called it. Neither has a counterpart in the
  1994 binary -- its main body IS its program -- and carrying them put Turbo
  Pascal's runtime on a different paragraph, so every far call into it differed.

  THE SCENE ORDER IS NOT THE SEGMENT ORDER. The units initialise 100f last of
  the four, but the main body calls 1095 first. Segment number tells you the
  link order, not the running order.

  THE USES CLAUSE IS THE LINK ORDER, REVERSED, and P6TILES BEFORE P6WHOOSH IS
  LOAD-BEARING -- this note comes from P6MAIN and it still applies. The
  original's variable region opens with P6TILES's Cells at DS:$70EE and its block
  ends at $737D, exactly where P6WHOOSH's Path begins at $737E; its constants open
  with P6TILES's CellShape at DS:$000A too. Named the other way round, P6WHOOSH came
  first and every variable in the part was out. The walk is a reverse DFS
  post-order from the PROGRAM, so the whole clause reads backwards: DemoVT
  first here finishes first and lands last in code.

  THERE IS NO SetTextMode AT THE END, and that is the original's doing: the demo
  ran under PSYCHO.EXE and part 006 left the adapter in mode 13h for whatever
  came next. RUNPART.BAT restores it with VIDMODE.

  DGROUP
 the volume as we found it   DS:$70ed  the fade's copy of it
  =========================================================================== }

{$G+}   { 286, AND A PROGRAM IS A FILE -- nothing inherits $G from its units.
          Without it an immediate argument comes out MOV AX,imm / PUSH AX rather
          than PUSH imm8, and the frame teardown POP BP rather than LEAVE. }

program Neur6;

uses DemoVT, Crt, VGA, P6CREDIT, P6FIRE, P6WHOOSH, P6TILES;

var
  SavedVol : Byte;
  V        : Byte;

{ and it ends in Halt(0), exactly as the original's does. }
begin
  SetMode13h;                     { -> 11ee:0000 }
  VirtScrAlloc;                   { -> 11ee:0006 }

  MusicDetect;                    { -> 1279:0000 }
  MusicFunc3;                     { -> 1279:006a }
  MusicCue;                       { -> 1279:0093 }
  MusicStart;                     { -> 1279:004e }

  Scene1;                         { -> 1095:07d4 }
  while KeyPressed do ReadKey;
  Scene2;                         { -> 100f:07d5 }
  while KeyPressed do ReadKey;
  Scene3;                         { -> 1118:09df }
  while KeyPressed do ReadKey;
  Scene4;                         { -> 11bb:02c9 }
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

  MusicStop;                      { -> 1279:005c }
  SetVolume(SavedVol);
  VirtScrFree;                    { -> 11ee:0033 }
  { NO Halt(0). `end.` already emits the exit -- LEAVE / XOR AX,AX /
    LCALL System:0116 -- so an explicit Halt(0) puts that sequence in TWICE,
    once for the statement and once for the end of the body. Seven bytes, and
    every program in this corpus except part 001's and part 005's had them:
    the comment that used to sit here pointed at the address of the single copy
    the original has, which is exactly what a doubled one looks like. }
end.
