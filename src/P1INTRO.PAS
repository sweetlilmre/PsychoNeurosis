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

{ THE SCENES ARE NAMED BACKWARDS AND THAT IS THE MEASUREMENT. Do not tidy
  this into scene order -- the clause fixes the segment layout, and 25 Aug
  2026 segpair.py measured it both ways: in scene order SIX of the nine
  paired segments came out transposed, our order running P1S5, P1S4,
  FixMath, P1S3, P1S2, P1S1; as written below all nine match the original.
  The initialised data improved with it, 420 differing bytes to 393, and
  the first divergence moved from $0002 to $0018.

  spans.py CANNOT TELL THESE APART -- 16161 against 16159 aligned, two
  bytes of noise -- because it locates each segment by content. Read
  segpair.py and dgimage.py for this, never the walk. }
uses VGA, Crt, DemoVT, P1S5, P1S4, P1S3, P1S2, P1S1;

procedure RunIntro;
var
  Saved : Byte;
begin
  SetMode13h;                  { 1000:0044 -> 1491:0000 }
  VirtScrAlloc;
  MusicDetect;                 { 1000:0049 -> 1532:0000 }
  MusicFunc3;                  { 1000:004E -> 1532:006A, function 3 }
  MusicCue;                    { 1000:0053 -> 1532:0093 }
  MusicStart;                  { 1000:0058 -> 1532:004E, function 0 }

  Scene1;      FlushKeys;      { 1000:005D -> 1012:0678 }
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
