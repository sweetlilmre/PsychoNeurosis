{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, scene 1: the garage.

  Segment 1008 in NEUROSIS_002_fpu.exe, transcribed in full -- every routine
  the scene reaches, read from the disassembly. No inference, no stubs.

  WHAT THE SCENE IS

  A 1280 x 200 painting sits across the four Mode-X planes. The scene pans
  right across it for 960 pixels, then stops in front of a garage door, and
  the door rolls up to reveal a night sky with fifty stars drifting across it.
  Then the palette brightens, the screen is blanked plane by plane, and the
  palette fades out.

  The door is not composited with the sky. The sky IS the door bitmap: as the
  door scrolls up out of its own buffer, a row of colour $80 is fed in at the
  bottom, and the stars are plotted into that $80 area before each blit and
  taken back out again afterwards.

  ROUTINE MAP

      Demo_Scene1           1008:0724
      Scene1_Run            1008:066f
      Scene1_Init           1008:01c7
      Scene1_LoadFrames     1008:00b9
      Scene1_DoorLoop       1008:0362
      Bitmap_Blit           1008:0000
      Door_RaiseOneRow      1008:0086
      Palette_BrightenStep  1008:0246
      Palette_FadeOut       1008:02de
  =========================================================================== }

unit P2S1;

interface

procedure Scene1;

implementation

uses Crt, P2VGA, P2ModeX, P2VT;

const
  { 1008:023a / 1008:023f -- Scene1_Init stores these into the door bitmap's
    own two header bytes at DS:$0D46. }
  DoorW    = $92;               { 146 }
  DoorH    = $55;               { 85 }
  DoorSize = 2 + DoorW * DoorH; { $307C = 12,412, and that is the read length }

  SkyColour = $80;              { 1008:00a2 -- what Door_RaiseOneRow feeds in }

  NumStars  = $32;              { 50   -- 1008:0719 }
  StarMaxX  = $92;              { 146  -- 1008:06d1 and the wrap at 1008:0497 }
  StarMaxY  = $55;              { 85   -- 1008:06eb }
  StarCols  = 3;                { 1008:0700, plus the base below }
  StarCol0  = $19;              { 25   -- 1008:0707 }

  { 1008:0727 -- the CRTC Offset this scene runs at, giving a 1280-wide
    canvas. Scene1_Run pans X from 0 to $3C0 across it. }
  SceneWidth = $A0;
  PanEnd     = $3C0;            { 960 }

  { 1008:03ef -- where the door is blitted. Bitmap_Blit adds its two X
    parameters, so the door lands at 960 + 92 = 1052, which is 92 pixels in
    from the left of the screen once the pan has finished. }
  DoorX    = $5C;               { 92 }
  DoorY    = $5E;               { 94 }
  DoorBase = $3C0;              { 960 }

  RaiseFrames  = $55;           { 85 -- 1008:04b6, one row per frame }
  HoldFrames   = $19;           { 25 -- 1008:060a }

  { 1008:00df -- the seek, as a LongInt pushed high word first. }
  DataOfs = $0003BE36;

type
  TDoor = array[0..DoorSize - 1] of Byte;
  TStar = record
    X, Y : Integer;
    C    : Byte;
  end;

var
  { DS:$0D46 -- two header bytes then DoorW * DoorH pixels. The star plotting
    at 1008:03a4 indexes it as [$0CB5 + X + Y * $92] with X and Y both
    ONE-BASED, and $0D46 - $0CB5 = $91, so that lands on pixel (X, Y) with the
    two-byte header skipped. DoorPix below is that same arithmetic. }
  Door : TDoor;
  { DS:$40BD, $40BF, $40C1 -- stride 5, indices 1..50. }
  Star : array[1..NumStars] of TStar;
  { DS:$3DC2 -- 256 RGB triples. }
  Pal  : array[0..767] of Byte;

{ The one-based pixel index Scene1_DoorLoop uses. }
function DoorPix(X, Y : Integer) : Word;
begin
  DoorPix := 2 + (X - 1) + (Y - 1) * DoorW;
end;

{ --------------------------------------------------------------------------
  1008:0000 -- Bitmap_Blit(Src, XOfs, Y, XBase)

  A per-pixel Mode-X blit with colour 0 transparent. It takes the width and
  height out of the source's own first two bytes, then walks the row rotating
  the Map Mask one plane at a time and stepping the destination byte only when
  the mask wraps past plane 3.

      DI      := RowOfs[Y] + (X shr 2)
      X       := XBase + XOfs             1008:0013 adds BP+4 to BP+8
      plane   := X and 3
      per row : DI := DI + $140 - (bytes advanced)

  $140 is 320, the plane-row stride, so each row simply restarts at
  RowOfs[Y + row] + (X shr 2) -- which is how it is written here.

  PARAMETER ORDER. RET $A, so a pointer and three words. Taking the highest
  BP offset as the first declared: Src at BP+$A, XOfs at BP+8, Y at BP+6,
  XBase at BP+4. Scene1_DoorLoop calls it (@Door, $5C, $5E, $3C0).
  -------------------------------------------------------------------------- }
procedure BlitBitmapX(Src : Pointer; XOfs, Y, XBase : Integer);
var
  P     : ^Byte;
  W, H  : Integer;
  R, C  : Integer;
  X     : Word;
  D     : Word;
  Plane : Integer;
  V     : Byte;
begin
  P := Src;
  W := P^;  Inc(LongInt(P));
  H := P^;  Inc(LongInt(P));
  X := XBase + XOfs;

  for R := 0 to H - 1 do
  begin
    D     := RowOfs[Y + R] + (X shr 2);
    Plane := X and 3;
    for C := 0 to W - 1 do
    begin
      V := P^;
      if V <> 0 then                      { 1008:0050 -- colour 0 is skipped }
      begin
        SelectPlane(Plane);
        Mem[VGASeg : D] := V;
      end;
      Inc(LongInt(P));
      Inc(Plane);
      if Plane = 4 then
      begin
        Plane := 0;
        Inc(D);
      end;
    end;
  end;
end;

{ --------------------------------------------------------------------------
  1008:0086 -- Door_RaiseOneRow(Src)

      W  := lo(word at Src)            the header byte, $92
      copy $2FE8 bytes from Src+2+W to Src+2      all but the last row
      fill the last W bytes with $80              a fresh row of sky

  $2FE8 is 12,264 = 146 * 85 - 146. So the whole image shifts up one row and
  sky comes in at the bottom: the door rolling open.
  -------------------------------------------------------------------------- }
procedure DoorRaiseOneRow;
begin
  Move(Door[2 + DoorW], Door[2], DoorW * DoorH - DoorW);
  FillChar(Door[2 + DoorW * DoorH - DoorW], DoorW, SkyColour);
end;

{ --------------------------------------------------------------------------
  1008:0246 -- Palette_BrightenStep

  For every colour 0..255: GetRGB, then THREE rounds of "if the channel is
  below $3F, bump it" on each of R, G and B, then SetRGB. So +3 per call,
  clamped at $3F. The three rounds are written out longhand in the original
  (1008:026c through 1008:02ba) rather than looped.
  -------------------------------------------------------------------------- }
procedure PaletteBrightenStep;
var
  Col, K  : Integer;
  R, G, B : Byte;
begin
  for Col := 0 to 255 do
  begin
    GetRGB(Col, R, G, B);
    for K := 1 to 3 do
    begin
      if R < $3F then Inc(R);
      if G < $3F then Inc(G);
      if B < $3F then Inc(B);
    end;
    SetRGB(Col, R, G, B);
  end;
end;

{ --------------------------------------------------------------------------
  1008:02de -- Palette_FadeOut

      for Pass := 1 to $40 do
        WaitRetrace
        for Col := 0 to $FF do
          GetRGB; five rounds of "if above zero, drop by one"; SetRGB

  64 passes of -5 per channel.
  -------------------------------------------------------------------------- }
procedure PaletteFadeOut;
var
  Pass, Col, K : Integer;
  R, G, B      : Byte;
begin
  for Pass := 1 to $40 do
  begin
    WaitRetrace;
    for Col := 0 to 255 do
    begin
      GetRGB(Col, R, G, B);
      for K := 1 to 5 do
      begin
        if R > 0 then Dec(R);
        if G > 0 then Dec(G);
        if B > 0 then Dec(B);
      end;
      SetRGB(Col, R, G, B);
    end;
  end;
end;

{ --------------------------------------------------------------------------
  1008:00b9 -- Scene1_LoadFrames

  NEUROSIS.DAT from $0003BE36:

        768   palette                      -> DS:$3DC2
     64,000   plane 0                      -> the staging buffer, then $A000
     64,000   plane 1
     64,000   plane 2
     64,000   plane 3
     12,412   the door bitmap              -> DS:$0D46

  Four planes of 64,000 bytes is 1280 x 200: 320 bytes per plane-row, 200
  rows. Each plane is read into the staging buffer and pushed across with
  CopyToPlane while the Map Mask selects that plane.
  -------------------------------------------------------------------------- }
procedure LoadFrames;
var
  F : file;
  P : Integer;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Pal, 768);
  for P := 0 to 3 do
  begin
    SelectPlane(P);
    BlockRead(F, Buffer^, 64000);
    CopyToPlane(BufferSeg, VGASeg);
  end;
  BlockRead(F, Door, DoorSize);
  Close(F);
end;

{ --------------------------------------------------------------------------
  1008:01c7 -- Scene1_Init

      blank the DAC (every colour to 0, 0, 0)
      LoadFrames
      write the loaded palette out, colour by colour
      Door[0] := $92 ; Door[1] := $55

  The DAC is blanked BEFORE the load so the panorama does not appear while it
  is being pushed into the planes; Palette_BrightenStep is what brings it up
  later. The two header bytes are set here rather than trusted from the file.
  -------------------------------------------------------------------------- }
procedure Init;
var
  Col : Integer;
begin
  for Col := 0 to 255 do
    SetRGB(Col, 0, 0, 0);

  LoadFrames;

  for Col := 0 to 255 do
    SetRGB(Col, Pal[Col * 3], Pal[Col * 3 + 1], Pal[Col * 3 + 2]);

  Door[0] := DoorW;
  Door[1] := DoorH;
end;

{ --------------------------------------------------------------------------
  1008:0362 -- Scene1_DoorLoop

  Three phases, and the first two share the same body:

    1008:036d   85 frames: raise the door one row, plot the stars, blit,
                un-plot the stars, drift them right
    1008:04c6   25 frames: the same minus the raise, plus one call to
                Palette_BrightenStep per frame
    1008:0613   clear the staging buffer and push it to all four planes,
                then Palette_FadeOut

  The star plot is conditional both ways round, and that is the whole trick:

      draw    if Door[star] = $80 then Door[star] := star colour
      erase   if Door[star] = star colour then Door[star] := $80

  A star is only drawn where the sky already is, so it never lands on the
  door itself, and it is only erased where it is still the colour it was
  drawn in -- so a star that got covered is left alone rather than punching a
  hole in the artwork.
  -------------------------------------------------------------------------- }
procedure DrawStars;
var
  I : Integer;
begin
  for I := 1 to NumStars do
    if Door[DoorPix(Star[I].X, Star[I].Y)] = SkyColour then
      Door[DoorPix(Star[I].X, Star[I].Y)] := Star[I].C;
end;

procedure EraseStars;
var
  I : Integer;
begin
  for I := 1 to NumStars do
    if Door[DoorPix(Star[I].X, Star[I].Y)] = Star[I].C then
      Door[DoorPix(Star[I].X, Star[I].Y)] := SkyColour;
end;

procedure DriftStars;
var
  I : Integer;
begin
  for I := 1 to NumStars do
  begin
    Inc(Star[I].X);
    if Star[I].X > StarMaxX then Star[I].X := 1;
  end;
end;

procedure DoorLoop;
var
  Frame : Integer;
  P     : Integer;
begin
  { phase 1 -- the door rolls up, 85 rows }
  Frame := 0;
  repeat
    DoorRaiseOneRow;
    DrawStars;
    BlitBitmapX(@Door, DoorX, DoorY, DoorBase);
    EraseStars;
    DriftStars;
    Inc(Frame);
  until Frame = RaiseFrames;

  { phase 2 -- hold, and bring the palette up }
  Frame := 0;
  repeat
    DrawStars;
    BlitBitmapX(@Door, DoorX, DoorY, DoorBase);
    EraseStars;
    DriftStars;
    PaletteBrightenStep;
    Inc(Frame);
  until Frame = HoldFrames;

  { phase 3 -- blank all four planes, then fade the palette out }
  ClearSeg(BufferSeg, 0);                  { 1008:0619, once }
  for P := 0 to 3 do
  begin
    SelectPlane(P);
    CopyToPlane(BufferSeg, VGASeg);
  end;
  PaletteFadeOut;
end;

{ --------------------------------------------------------------------------
  1008:066f -- Scene1_Run

      Init
      ShowFrame(0, 0)
      Delay($7D0)                          2000 ms
      MusicDetect  /  MusicCue  /  SyncPattern(5, 1)
      for X := 0 to $3C0 do                the pan, 960 pixels
        MusicPoll
        ShowFrame(X, 0)
      MusicStart
      Delay($7D0)
      seed the fifty stars
      DoorLoop

  The pan has no delay in it: one MusicPoll and one ShowFrame per step, and
  ShowFrame waits for vertical retrace, so the pan runs at the refresh rate --
  960 frames, about sixteen seconds at 60 Hz.
  -------------------------------------------------------------------------- }
procedure Run;
var
  X, I : Integer;
begin
  Init;                                    { 1008:0673 }
  ShowFrame(0, 0);                         { 1008:067a }
  Delay($7D0);                             { 1008:0682 }

  MusicDetect;                             { 1008:0687 -> 13f9:0000 }
  MusicCue;                                { 1008:068c -> 13f9:0085 }
  SyncPattern(5, 1);                       { 1008:0695 -> 13f9:00ca }

  for X := 0 to PanEnd do
  begin
    MusicPoll;                             { 1008:06a4 -> 13f9:0040 }
    ShowFrame(X, 0);
  end;

  MusicStart;                              { 1008:06ba -> 13f9:004e }
  Delay($7D0);                             { 1008:06c2 }

  for I := 1 to NumStars do
  begin
    Star[I].X := Random(StarMaxX) + 1;     { 1008:06d1 }
    Star[I].Y := Random(StarMaxY) + 1;     { 1008:06eb }
    Star[I].C := Random(StarCols) + StarCol0;
  end;

  DoorLoop;                                { 1008:071f }
end;

{ --------------------------------------------------------------------------
  1008:0724 -- Demo_Scene1

      DS:$0002 := $A0        the wide canvas
      SetModeX               107c:006d, which writes that to CRTC $13
      BuildRowTable          107c:0000, which uses it as the row multiplier
      Run

  The order matters: the width has to be in place before either of the other
  two reads it.
  -------------------------------------------------------------------------- }
procedure Scene1;
begin
  LogicalWidth := SceneWidth;
  SetModeX;
  BuildRowTable;
  Run;
end;

end.
