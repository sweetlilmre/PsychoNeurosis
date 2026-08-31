{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.007, the program itself.

  THIS IS THE MAIN BODY, NOT A UNIT CALLED BY A HARNESS. Segment 1000, offsets
  $00..$bb: everything up to 1000:001d is Turbo Pascal's unit initialisation
  chain and the program starts at 1000:001e.

  It replaces P7MAIN.PAS, which held the same code as a unit with a RunPart7
  entry, plus TPART7.PAS, the generated harness that called it. Those two
  segments have no counterpart in the original -- its main body IS the program
  -- and their presence is why the runtime sat at a different paragraph and
  every far call into it differed. That was 10 of part 007's 12 unaligned
  bytes.

  THE USES CLAUSE IS THE LINK ORDER, REVERSED. Turbo Pascal's link walk is a
  reverse DFS post-order starting at the PROGRAM, so the last unit to finish
  comes first in code. The original's segments are VGA (100b), P7FLIC (100f),
  Crt (1099) and DemoVT (10fb), so VGA has to finish last and DemoVT first.
  Checked against build/NEUR7.MAP, not assumed.

  Part 007 is the last part of the demo, and it is the only one that tidies up
  after itself: after going back to text mode it issues INT 10h AH=1 with
  CX=$FF09, which hides the text cursor. Nothing else in Psycho Neurosis does
  that.

  There is no VirtScrAlloc here -- the FLI player writes straight to $A000, so
  part 007 never allocates a virtual screen.

  DEVIATION: the original keeps SetMode13h and SetTextMode in a two-routine
  unit of its own at segment 100b (1000:00b0 and 1000:00b6 in the listing).
  The reconstruction takes them from the shared VGA unit instead; they are the
  same three instructions.

  DGROUP
 the volume as we found it   DS:$0067  the fade's copy of it
  =========================================================================== }

{$G+}   { 286, AND A PROGRAM IS A FILE -- nothing inherits $G from its units.
          Without it an immediate argument comes out MOV AX,imm / PUSH AX rather
          than PUSH imm8, and the frame teardown POP BP rather than LEAVE. }

program Neur7;

uses DemoVT, Crt, P7FLIC, VGA;

var
  SavedVol : Byte;
  V        : Byte;

{ and it ends in Halt(0), exactly as the original's does. }
begin
  SetMode13h;                     { -> 100b:0000 }

  MusicDetect;                    { -> 10fb:0000 }
  MusicFunc3;                     { -> 10fb:006a }
  MusicCue;                       { -> 10fb:0093 }
  MusicStart;                     { -> 10fb:004e }

  Scene1;                         { -> 100f:084c }

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

  MusicStop;                      { -> 10fb:005c }
  SetVolume(SavedVol);            { -> 10fb:00d8 }
  SetTextMode;                    { -> 100b:0006 }

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
