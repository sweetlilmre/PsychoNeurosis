{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003, the driver.

  The main body only, transcribed from 1000:0041 in NEUROSIS_003_fpu.exe.
  Every far call in it carries its target segment in the instruction bytes,
  so the seven scenes resolve without ambiguity -- and each address matches
  the one already recorded in the scene's own unit header:

      1015:098d   Scene1   the tunnel
      10b8:0592   Scene2   the star tube
      1139:03b4   Scene3   the morph
      119d:0211   Scene4   the globe
      11f3:01ac   Scene5   the blocks
      120f:04d0   Scene6   the waves
      125e:0958   Scene7   the spinning portraits

  Two things in here are not what a symmetric reading would predict:

    * the music is DETECTED before scene 1 but only STARTED after it, so the
      tunnel runs silent;
    * SetMode13h is called a SECOND time, between scene 3 and scene 4
      (1000:0097), because the first three scenes leave the adapter in a state
      scene 4 cannot use.
  =========================================================================== }

unit P3Main;

interface

procedure RunPart3;

implementation

uses Crt, VGA, DemoVT,
     Part3Tunnel, Part3Stars, Part3Morph, Part3Globe,
     Part3Blocks, Part3Waves, Part3Sprites;

procedure FlushKeys;
begin
  while KeyPressed do ReadKey;
end;

{ --------------------------------------------------------------------------
  1000:0041 -- the main body.

      SetMode13h        12f8:0000
      VirtScrAlloc      12f8:0006
      MusicDetect         136b:0000     the INT $2F handshake
      Scene1            1015:098d
      flush
      dispatch 0        136b:004e     see the note below
      Scene2            10b8:0592
      flush
      Scene3            1139:03b4
      flush
      SetMode13h        12f8:0000     again
      Scene4            119d:0211
      flush
      Scene5            11f3:01ac
      flush
      Scene6            120f:04d0
      flush
      Scene7            125e:0958
      flush
      save the volume, ramp it to zero with Delay(10) a step
      MusicStop         136b:005c
      restore the volume
      VirtScrFree       12f8:0033
      Halt(0)

  THE CALL AT 136b:004e. In part 002 the same slot in the same unit
  (13f9:004e) pushes dispatch function 0, and coming after the handshake and
  before the first scene that wants sound, it reads as "start playing".
  DemoVT calls that entry point MusicPoll -- see the naming note in its
  header. The call is made here through the name DemoVT exports so nothing is
  silently renamed; the two units disagree and that is worth resolving
  separately rather than papering over here.
  -------------------------------------------------------------------------- }
procedure RunPart3;
var
  Saved : Byte;
begin
  SetMode13h;
  VirtScrAlloc;
  MusicDetect;

  Scene1;   FlushKeys;

  MusicStart;               { 136b:004e -- dispatch function 0 }

  Scene2;   FlushKeys;
  Scene3;   FlushKeys;

  SetMode13h;               { 1000:0097 -- a second time, before scene 4 }

  Scene4;   FlushKeys;
  Scene5;   FlushKeys;
  Scene6;   FlushKeys;
  Scene7;   FlushKeys;

  { 1000:00f0 -- ramp the volume down, stop, then put it back }
  Saved := GetVolume;
  while GetVolume > 0 do
  begin
    SetVolume(GetVolume - 1);
    Delay(10);
  end;
  MusicStop;
  SetVolume(Saved);

  VirtScrFree;
  Halt(0);
end;

end.
