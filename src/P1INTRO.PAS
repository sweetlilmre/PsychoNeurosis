{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, the intro.

  The driver only. Each scene is its own unit so it can be compiled and run in
  isolation:

      P1S1  logo and bouncing sprites      1012:0678
      P1S2  "ASPHYXIA PRESENTS" + comet    1082:056f
      P1S3  mosaic pixelate                10e3:0206
      P1S4  rotating 3-D text              1107:0977
      P1S5  vector objects and wipe        12c5:0a89

  Same architecture as part 003: a main body of scenes each followed by a
  keyboard flush, then the music fade.
  =========================================================================== }

unit P1Intro;

interface

procedure RunIntro;

implementation

uses VGA, Crt, DemoVT, P1S1, P1S2, P1S3, P1S4, P1S5;

procedure RunIntro;
var
  Saved : Byte;
begin
  SetMode13h;
  VirtScrAlloc;
  MusicInit;

  Scene1;      FlushKeys;
  Scene2;      FlushKeys;
  Scene3;      FlushKeys;
  Scene4;      FlushKeys;
  Scene5;      FlushKeys;

  { music fade -- identical to part 003 }
  Saved := GetVolume;
  repeat
    SetVolume(GetVolume - 1);
    Delay(10);
  until GetVolume = 0;
  MusicStop;
  SetVolume(Saved);

  VirtScrFree;
  SetRGB(0, 0, 0, 7);
  Halt(0);
end;

end.
