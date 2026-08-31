{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.007, the program itself.

  It replaces P7MAIN.PAS, which held the same code as a unit with a RunPart7
  entry, plus TPART7.PAS, the generated harness that called it. Those two
  segments have no counterpart in the original -- its main body IS the program
  -- and their presence is why the runtime sat at a different paragraph and
  every far call into it differed. That was 10 of part 007's 12 unaligned
  bytes.

  Part 007 is the last part of the demo, and it is the only one that tidies up
  after itself: after going back to text mode it issues INT 10h AH=1 with
  CX=$FF09, which hides the text cursor. Nothing else in Psycho Neurosis does
  that.

  There is no VirtScrAlloc here -- the FLI player writes straight to $A000, so
  part 007 never allocates a virtual screen. }

{ 286 instructions are permitted. This setting is PER FILE and a program is a
  file, so nothing here inherits it from the units. }
{$G+}

program Neur7;

uses DemoVT, Crt, P7FLIC, VGA;

var
  SavedVol : Byte;
  V        : Byte;

{ and it ends in Halt(0), exactly as the original's does. }
begin
  SetMode13h;

  MusicDetect;
  MusicFunc3;
  MusicCue;
  MusicStart;

  Scene1;

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
  SetTextMode;

  { AH=1 sets the cursor shape, and a start line above the end
    line turns the cursor off. The demo is over; leave DOS looking clean. }
  asm
    MOV  AH, 1
    MOV  CH, 0FFh
    MOV  CL, 9
    INT  10h
  end;

  { NO Halt(0). `end.` already emits the exit -- LEAVE / XOR AX,AX /
    LCALL System:0116 -- so an explicit Halt(0) puts that sequence in TWICE,
    once for the statement and once for the end of the body. Seven bytes, and
    every program in this corpus except part 001's and part 005's had them:
    the comment that used to sit here pointed at the address of the single copy
    the original has, which is exactly what a doubled one looks like. }
end.
