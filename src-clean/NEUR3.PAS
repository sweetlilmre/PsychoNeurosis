{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003, the program itself.

  THE KEYBOARD DRAIN IS INLINE AT EVERY SITE, not a called procedure.
 is CALLF Crt.KeyPressed / OR AL,AL / JZ / CALLF Crt.ReadKey / JMP,
  written out where a call would be five bytes. P3MAIN had it as a procedure,
  and this program came out 272 bytes against the original's 336 because of it.
  A program segment of the wrong SIZE moves the runtime exactly as an extra
  segment does, so removing the harness bought nothing at all until this was
  fixed with it.

  THERE IS NO SetTextMode AT THE END: part 003 left the adapter as it was for
  whatever PSYCHO.EXE ran next. RUNPART.BAT restores it with VIDMODE.
  =========================================================================== }

{ 286 instructions are permitted. This setting is PER FILE and a program is a
  file, so nothing here inherits it from the units. }
{$G+}

program Neur3;

uses DemoVT, Crt, VGA,
     P3Sprite, P3Waves, P3Blocks, P3Globe,
     P3Morph, P3Stars, P3Tunnel;

var
  SavedVol : Word;
  Vol      : Word;

{ the driver, and it ends in Halt(0) as the original does. }
begin
  SetMode13h;
  VirtScrAlloc;
  MusicDetect;

  Scene1;   while KeyPressed do ReadKey;

  MusicStart;               { dispatch function 0 }

  Scene2;   while KeyPressed do ReadKey;
  Scene3;   while KeyPressed do ReadKey;

  SetMode13h;               { a second time, before scene 4 }

  Scene4;   while KeyPressed do ReadKey;
  Scene5;   while KeyPressed do ReadKey;
  Scene6;   while KeyPressed do ReadKey;
  Scene7;   while KeyPressed do ReadKey;

  { ramp the volume down, stop, then put it back }
  { THE FADE READS THE VOLUME TWICE A TURN, and the second reading is the one
    the test uses -- so this is a repeat..until with no test before the first
    turn. Collapsing it into a single read is a different program. }
  SavedVol := GetVolume;
  repeat
    Vol := GetVolume;
    SetVolume(Vol - 1);
    Vol := GetVolume;
    Delay(10);
  until Vol = 0;
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
