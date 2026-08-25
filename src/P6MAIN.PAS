{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.006, the main body.

  Segment 1000, offsets $00..$ef. Everything up to 1000:0028 is Turbo Pascal's
  unit initialisation chain; the program starts at 1000:002d.

  THE SCENE ORDER IS NOT THE SEGMENT ORDER. The units initialise 100f last of
  the four, but the main body calls 1095 first. Segment number tells you the
  link order, not the running order.

  DGROUP
    DS:$70ec  the volume as we found it   DS:$70ed  the fade's copy of it
  =========================================================================== }

unit P6Main;

interface

procedure RunPart6;

implementation

{ P6S2 LAST, so it comes FIRST in DGROUP -- the data segment runs backwards
  down this clause. The original's variable region opens with P6S2's Cells at
  DS:$70EE and its block ends at $737D, exactly where P6S1's Path begins at
  $737E; its constants open with P6S2's CellShape at DS:$000A too. Named the
  other way round P6S1 came first and every variable in the part was out. }
uses Crt, VGA, DemoVT, P6S4, P6S3, P6S1, P6S2;

var
  SavedVol : Byte;                { DS:$70ec }
  V        : Byte;                { DS:$70ed }

{ 1000:002d -- and it ends in Halt(0), exactly as the main body does. }
procedure RunPart6;
begin
  SetMode13h;                     { 1000:0030 -> 11ee:0000 }
  VirtScrAlloc;                   { 1000:0035 -> 11ee:0006 }

  MusicDetect;                    { 1000:003a -> 1279:0000 }
  MusicFunc3;                     { 1000:003f -> 1279:006a }
  MusicCue;                       { 1000:0044 -> 1279:0093 }
  MusicStart;                     { 1000:0049 -> 1279:004e }

  Scene1;                         { 1000:004e -> 1095:07d4 }
  while KeyPressed do ReadKey;    { 1000:0053 }
  Scene2;                         { 1000:0063 -> 100f:07d5 }
  while KeyPressed do ReadKey;    { 1000:0068 }
  Scene3;                         { 1000:0078 -> 1118:09df }
  while KeyPressed do ReadKey;    { 1000:007d }
  Scene4;                         { 1000:008d -> 11bb:02c9 }
  while KeyPressed do ReadKey;    { 1000:0092 }

  { 1000:00a2 -- ride the volume down, ten milliseconds a step. With no
    tracker resident GetVolume answers zero and this falls straight through. }
  SavedVol := GetVolume;
  repeat
    V := GetVolume;               { 1000:00aa }
    SetVolume(V - 1);             { 1000:00b9 }
    V := GetVolume;               { 1000:00be }
    Delay(10);                    { 1000:00c8 }
  until V = 0;                    { 1000:00cd }

  MusicStop;                      { 1000:00d4 -> 1279:005c }
  SetVolume(SavedVol);            { 1000:00dd }
  VirtScrFree;                    { 1000:00e2 -> 11ee:0033 }
  Halt(0);                        { 1000:00e8 }
end;

begin
end.
