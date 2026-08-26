{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.007, the main body.

  Segment 1000, offsets $00..$bb. Everything up to 1000:001d is Turbo Pascal's
  unit initialisation chain; the program starts at 1000:001e.

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
    DS:$0066  the volume as we found it   DS:$0067  the fade's copy of it
  =========================================================================== }

unit P7Main;

interface

procedure RunPart7;

implementation

{ THE HARNESS DECIDES THIS, NOT THIS CLAUSE. build/TPART7.MAP has ours as
  P7S1, DemoVT, VGA, Crt where the original is VGA (100b), P7S1 (100f), Crt
  (1099), DemoVT (10fb). Reordering here changes NOTHING -- the link walk is a
  reverse DFS post-order starting at the PROGRAM, and TPART7.PAS names Crt,
  VGA and DemoVT itself, which pins them before this unit is reached. Fixing
  part 007's order means changing the harness's clause in tools/mktests.py, the
  way part 002's was. Measured, not assumed: this clause was reversed and the
  map came out identical. }
uses Crt, VGA, DemoVT, P7S1;

var
  SavedVol : Byte;                { DS:$0066 }
  V        : Byte;                { DS:$0067 }

{ 1000:001e -- and it ends in Halt(0), exactly as the main body does. }
procedure RunPart7;
begin
  SetMode13h;                     { 1000:0021 -> 100b:0000 }

  MusicDetect;                    { 1000:0026 -> 10fb:0000 }
  MusicFunc3;                     { 1000:002b -> 10fb:006a }
  MusicCue;                       { 1000:0030 -> 10fb:0093 }
  MusicStart;                     { 1000:0035 -> 10fb:004e }

  Scene1;                         { 1000:003a -> 100f:084c }

  while KeyPressed do ReadKey;    { 1000:003f }

  { 1000:004f -- ride the volume down, ten milliseconds a step. With no
    tracker resident GetVolume answers zero and this falls straight through. }
  SavedVol := GetVolume;
  repeat
    V := GetVolume;               { 1000:0057 }
    SetVolume(V - 1);             { 1000:0066 }
    V := GetVolume;               { 1000:006b }
    Delay(10);                    { 1000:0075 }
  until V = 0;                    { 1000:007a }

  MusicStop;                      { 1000:0081 -> 10fb:005c }
  SetVolume(SavedVol);            { 1000:008a -> 10fb:00d8 }
  SetTextMode;                    { 1000:008f -> 100b:0006 }

  { 1000:0094 -- AH=1 sets the cursor shape, and a start line above the end
    line turns the cursor off. The demo is over; leave DOS looking clean. }
  asm
    MOV  AH, 1             { 1000:0094 }
    MOV  CH, 0FFh          { 1000:0096 }
    MOV  CL, 9             { 1000:0098 }
    INT  10h               { 1000:009a }
  end;

  Halt(0);                        { 1000:009f }
end;

begin
end.
