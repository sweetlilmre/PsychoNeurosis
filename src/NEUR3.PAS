{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003, the program itself.

  [re] THIS IS THE MAIN BODY, NOT A UNIT CALLED BY A HARNESS. It replaces
  P3MAIN.PAS, which held this code as a unit with a RunPart3 entry, and the
  generated TPART3.PAS that called it. Neither has a counterpart in the 1994
  binary -- its main body IS its program -- and carrying them put Turbo Pascal's
  runtime on a different paragraph, so every far call into it differed.

  [re] THE USES CLAUSE IS THE LINK ORDER, REVERSED, and it is the harness's clause
  followed by P3MAIN's, which is what the two of them produced between them:
  DemoVT, Crt and VGA finish first and so land LAST in code, and the seven
  scene units are named in reverse of their segments. The original's order is
  P3Tunnel (1015), P3Stars (10b8), P3Morph (1139), ModeX (1192), P3Globe
  (119d), P3Blocks (11f3), P3Waves (120f), P3Sprite (125e), VGA (12f8), Crt
  (1309), DemoVT (136b) -- with ModeX between Morph and Globe because nothing
  names it directly and the unit that needs it pulls it in there. Checked
  against build/NEUR3.MAP.

  THE KEYBOARD DRAIN IS INLINE AT EVERY SITE, not a called procedure.
  1000:0058 is CALLF Crt.KeyPressed / OR AL,AL / JZ / CALLF Crt.ReadKey / JMP,
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
{$G+}   { [re] 286, AND A PROGRAM IS A FILE -- nothing inherits $G from its units.
          Without it an immediate argument comes out MOV AX,imm / PUSH AX rather
          than PUSH imm8, and the frame teardown POP BP rather than LEAVE. }

program Neur3;

uses DemoVT, Crt, VGA,
     P3Sprite, P3Waves, P3Blocks, P3Globe,
     P3Morph, P3Stars, P3Tunnel;

var
  SavedVol : Word;      { DS:$9F1A }
  Vol      : Word;      { DS:$9F1C }

{ 1000:0041 -- the driver, and it ends in Halt(0) as the original does. }
begin
  SetMode13h;
  VirtScrAlloc;
  MusicDetect;

  Scene1;   while KeyPressed do ReadKey;

  MusicStart;               { 136b:004e -- dispatch function 0 }

  Scene2;   while KeyPressed do ReadKey;
  Scene3;   while KeyPressed do ReadKey;

  SetMode13h;               { 1000:0097 -- a second time, before scene 4 }

  Scene4;   while KeyPressed do ReadKey;
  Scene5;   while KeyPressed do ReadKey;
  Scene6;   while KeyPressed do ReadKey;
  Scene7;   while KeyPressed do ReadKey;

  { 1000:00f0 -- ramp the volume down, stop, then put it back }
  { THE FADE READS THE VOLUME TWICE A TURN, and the second reading is the one
    the test uses -- so this is a repeat..until with no test before the first
    turn. Collapsing it into a single read is a different program.

    [re] A REPEAT, and GetVolume is called TWICE a turn. 1000:00fa stores it into
    Vol, 1000:0109 passes Vol-1 to SetVolume, and 1000:010e stores it AGAIN
    before the Delay -- and that second value is what 1000:011f tests. There is
    no test before the first turn, so it is repeat..until and not while. }
  SavedVol := GetVolume;              { 1000:00f0 }
  repeat
    Vol := GetVolume;                 { 1000:00fa }
    SetVolume(Vol - 1);               { 1000:0109 }
    Vol := GetVolume;                 { 1000:010e }
    Delay(10);                        { 1000:011a }
  until Vol = 0;                      { 1000:011f }
  MusicStop;                          { 1000:0126 }
  SetVolume(SavedVol);                { 1000:012f }

  VirtScrFree;
  { NO Halt(0). `end.` already emits the exit -- LEAVE / XOR AX,AX /
    LCALL System:0116 -- so an explicit Halt(0) puts that sequence in TWICE,
    once for the statement and once for the end of the body. Seven bytes, and
    every program in this corpus except part 001's and part 005's had them:
    the comment that used to sit here pointed at the address of the single copy
    the original has, which is exactly what a doubled one looks like. }
end.
