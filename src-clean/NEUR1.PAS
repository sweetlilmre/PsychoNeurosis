{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, the program itself.

  PART 001 IN THIRTY LINES: get a virtual screen, set mode 13h, find the music
  player and start it, run five scenes in order, fade the music out, give the
  screen back and leave. There is no scene logic here at all -- each Scene*n*
  lives in its own unit and this file only says what order they run in.

  THE FIVE SCENES ARE SEPARATED BY A KEYBOARD DRAIN, written inline at every
  one of the five sites rather than as a procedure. Each scene may end early on
  a keypress, and the drain throws away whatever ended it so the next scene does
  not immediately see the same key and skip itself.

  ALLOCATE BEFORE SETTING THE MODE -- and this part is the ONLY one that does.
  Parts 002, 003 and 004 all set mode 13h first and then allocate. **Do not
  tidy this into the usual order.**

  THE MUSIC FADE READS THE VOLUME TWICE A TURN, and the shape is deliberate: it
  reads, sets one lower, then reads AGAIN and tests that second reading. So the
  loop is a repeat..until with no test before the first turn. Collapsing it to
  `SetVolume(GetVolume - 1)` with `until GetVolume = 0` is a different program.

  SetRGB(7, 0, 0, 0) BLACKS OUT DAC ENTRY 7. The first argument is the DAC
  index, not a colour component -- reversing them sets entry 0 to a dim blue,
  which is a visible difference on the final frame.

  AND IT DOES NOT RESTORE TEXT MODE: part 001 leaves the adapter in mode 13h
  for whatever the launcher runs next. RUNPART.BAT is what puts it back.

  =========================================================================== }

{ 286 instructions are permitted. Note that this setting is PER FILE and a
  program is a file -- nothing here inherits it from the units. }
{$G+}

program Neur1;

{ THE SCENES ARE NAMED IN REVERSE ORDER HERE, and that is not a mistake to be
  sorted. Turbo Pascal walks the clause depth first, so the unit named FIRST is
  finished first and lands LAST in the executable -- the clause is the link
  order backwards. FixMath is deliberately absent: the scene that needs it pulls
  it in, which is where it belongs. }
uses DemoVT, Crt, VGA,
     P1VECTOR, P1STAR, P1BALLS, P1MOSAIC, P1TITLE, P1LOGO;

var
  { Unit-level rather than local: the original's body has a frame with no
    locals at all, so both of these live in the data segment. }
  Saved : Byte;         { the volume to restore when the fade is done }
  Vol   : Byte;         { the fade's working value }

begin
  VirtScrAlloc;                   { before the mode change -- see the header }
  SetMode13h;

  MusicDetect;                    { is the player resident?                  }
  MusicFunc3;                     { resync its clock before anything plays   }
  MusicCue;
  MusicStart;

  { Each scene returns when it ends or when a key is pressed; the drain throws
    that key away so the next scene does not see it and skip itself. }
  Scene1;   while KeyPressed do ReadKey;
  Scene2;   while KeyPressed do ReadKey;
  Scene3;   while KeyPressed do ReadKey;
  Scene4;   while KeyPressed do ReadKey;
  Scene5;   while KeyPressed do ReadKey;

  { Ramp the volume down a step at a time, stop the music, then hand the
    player's volume back as it was found. }
  Saved := GetVolume;
  repeat
    Vol := GetVolume;
    SetVolume(Vol - 1);
    Vol := GetVolume;             { read AGAIN -- this is what the test uses }
    Delay(10);
  until Vol = 0;
  MusicStop;
  SetVolume(Saved);

  VirtScrFree;
  SetRGB(7, 0, 0, 0);             { black out DAC entry 7                    }

  { NO Halt(0) HERE, deliberately: `end.` already emits the exit, so writing
    Halt(0) as well emits it twice. }
end.
