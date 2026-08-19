{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.005, the main body.

  Segment 1000, offsets $00..$df. Everything up to 1000:0028 is Turbo
  Pascal's unit initialisation chain; the program itself starts at 1000:002d
  and is transcribed below in full.

  Note this part calls DemoVT FUNCTION 3 (12c8:006a). Before part 005 was
  read, part 001 was the only part known to use it.

  DGROUP
    DS:$2d7c  the volume as we found it     DS:$2d7d  the fade's copy of it
  =========================================================================== }

unit P5Main;

interface

procedure RunPart5;

implementation

uses Crt, VGA, DemoVT, P5S1, P5S2, P5S3;

var
  SavedVol : Byte;                { DS:$2d7c }
  V        : Byte;                { DS:$2d7d }

{ 1000:002d -- and it ends in Halt(0), exactly as the main body does. }
procedure RunPart5;
begin
  SetMode13h;                     { 1000:0030 -> 1252:0000 }
  VirtScrAlloc;                   { 1000:0035 -> 1252:0006 }

  MusicDetect;                    { 1000:003a -> 12c8:0000 }
  MusicFunc3;                     { 1000:003f -> 12c8:006a }
  MusicCue;                       { 1000:0044 -> 12c8:0093 }
  MusicStart;                     { 1000:0049 -> 12c8:004e }

  Scene1;                         { 1000:004e -> 100e:07a4 }
  while KeyPressed do ReadKey;    { 1000:0053 }
  Scene2;                         { 1000:0063 -> 1096:03d7 }
  while KeyPressed do ReadKey;    { 1000:0068 }
  Scene3;                         { 1000:0078 -> 1102:035a }
  while KeyPressed do ReadKey;    { 1000:007d }

  { 1000:008d -- ride the volume down to nothing, ten milliseconds a step.
    With no tracker resident GetVolume answers zero and this falls straight
    through, the same as part 004's ending. }
  SavedVol := GetVolume;
  repeat
    V := GetVolume;               { 1000:0095 }
    SetVolume(V - 1);             { 1000:00a4 }
    V := GetVolume;               { 1000:00a9 }
    Delay(10);                    { 1000:00b3 }
  until V = 0;                    { 1000:00b8 }

  MusicStop;                      { 1000:00bf }
  SetVolume(SavedVol);            { 1000:00c8 }
  VirtScrFree;                    { 1000:00cd }
  Halt(0);                        { 1000:00d3 }
end;

begin
end.
