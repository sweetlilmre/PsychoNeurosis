{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the driver.

  The main body only, transcribed from 1000:0032. Each scene is its own unit
  so it can be compiled and run in isolation:

      P2S1   the garage: a 1280-wide pan, the door, a starfield   1008:0724
      P2S2   solid 3-D objects, starfield, typed banner           108b:2454

  and the three units they share:

      VGA    segment 1436   palette, staging buffer, retrace
      ModeX  segment 107c   unchained 320x200 on a 1280-wide canvas
      P2View   segment 140c   unchained 320x400, two pages
      FixMath    segment 142a   16.16 fixed point, and SetMode13h
      DemoVT     segment 13f9   the resident tracker client

  This replaces the old single-file PART2.PAS, which predated the split and
  carried guessed versions of routines that have since been read out of the
  binary. Its analysis notes live in docs/15-part002.md and
  docs/22-part002-scene2.md.
  =========================================================================== }

unit P2Main;

interface

procedure RunPart2;

implementation

{ THE ORDER IS THE LINK ORDER, REVERSED, and the map says ours was wrong. The
  original's segments run P2S1 (1008), ModeX (107c), P2S2 (108b), DemoVT
  (13f9) ... Crt (144f); build/TPART2.MAP had ours as P2S2, P2S1, DemoVT,
  FixMath, P2View, ModeX, VGA, Crt -- a different order entirely, with ModeX
  eighth instead of second. The coverage walk cannot see this: it locates each
  segment by CONTENT, so it aligned every one of them and still read 99.9%.
  What DID see it was the initialised data image, where ModeX's LogicalWidth
  sat at DS:$0CDC against the original's DS:$0002. }
uses Crt, VGA, FixMath, P2View, DemoVT, P2S2, ModeX, P2S1;

{ --------------------------------------------------------------------------
  1000:0032 -- the main body.

      1000:0035   SetMode13h        1436:0000, which is the same physical
                                    bytes as 142a:00c0 -- the two segments
                                    overlap, so FixMath already has it
      1000:003a   VirtScrAlloc      1436:0006
      1000:003f   Demo_Scene1       1008:0724
      1000:0044   flush the keyboard
      1000:0054   Demo_Scene2       108b:2454
      1000:0059   flush the keyboard
      1000:0069   VirtScrFree       1436:0033
      1000:006f   Halt(0)

  Note what is NOT here: no music start or stop, and no palette fade. Each
  scene drives the tracker itself -- Scene1 detects and cues it, Scene2 starts
  it and ramps the volume down at the end.
  -------------------------------------------------------------------------- }
procedure FlushKeys;
begin
  while KeyPressed do ReadKey;
end;

procedure RunPart2;
begin
  SetMode13h;
  VirtScrAlloc;

  Scene1;
  FlushKeys;

  Scene2;
  FlushKeys;

  VirtScrFree;
  Halt(0);
end;

end.
