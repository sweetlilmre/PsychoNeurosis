{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 3, the mosaic pixelate

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit P1S3;

interface

procedure Scene3;

implementation

uses VGA, Crt, DemoVT;

{ [transcribed] Mosaic block sampling.

  The point an earlier reconstruction missed: the sum is read from the VIRTUAL
  screen and the average is written straight to VIDEO --

      MOV AX,$A000 ; MOV ES,AX        destination
      MOV AX,[$AB58] ; MOV DS,AX      source

  so the clean image is never modified and each level re-averages from it
  rather than compounding the previous one. Reading and writing the same
  buffer, as the first version did, blurs the image away and shows nothing,
  because only level 0 ever blits.

  The shift IS the block area, so there is no division: 4x4 shr 4, 8x8 shr 6,
  16x16 shr 8, 32x32 shr 10, 64x64 shr 12.

  The accumulator is a 16-bit AX in the original, so the 64x64 level overflows
  on a bright image. That is the original's behaviour and is kept. }

{ ===========================================================================
  Scene 3 -- mosaic pixelate                      Demo_Scene3  10e3:0206
  =========================================================================== }

const
  MosaicLevels = 5;

{ --------------------------------------------------------------------------
  Mosaic_Run (10e3:00bb)

  Progressive pixelate, in and out. For each level the block size doubles and
  the shift grows by 2, so `sum shr Shift` is exactly the block average and
  there is no division anywhere:

      4x4    16 px   shr 4
      8x8    64 px   shr 6
     16x16  256 px   shr 8
     32x32 1024 px   shr 10
     64x64 4096 px   shr 12

  ASSETS  NEUROSIS.DAT $02AEE0, 64,000 bytes:
            assets/part001/intro_screen.png
  -------------------------------------------------------------------------- }
procedure MosaicRun;
var
  Size, Shift          : array[1..MosaicLevels] of Byte;
  I, Sh, Level, Dir    : Integer;
  Rows, Cols, Row, Col : Integer;
  BY, BX               : Integer;
  Ofs, P               : Word;
  Sum                  : Word;
begin
  I := 4;  Sh := 4;
  for Level := 1 to MosaicLevels do
  begin
    Size[Level]  := I;
    Shift[Level] := Sh;
    Inc(Sh, 2);
    I := I shl 1;
  end;

  Dir   := -1;
  Level := MosaicLevels;
  ClearScreen($A000, 0);

  repeat
    if Level = 0 then
      CopyScreen(VirtScrSeg, $A000)     { level 0 = the unpixelated image }
    else
    begin
      Ofs  := 0;
      Rows := 200 div Size[Level];
      Cols := 320 div Size[Level];

      for Row := 1 to Rows do
      begin
        for Col := 1 to Cols do
        begin
          { Sum from the VIRTUAL screen ... }
          Sum := 0;
          P   := Ofs;
          for BY := 1 to Size[Level] do
          begin
            for BX := 1 to Size[Level] do
            begin
              Inc(Sum, Mem[VirtScrSeg : P]);
              Inc(P);
            end;
            Inc(P, ScrWidth - Size[Level]);
          end;

          { ... and write the average straight to VIDEO. }
          Sum := Sum shr Shift[Level];
          P   := Ofs;
          for BY := 1 to Size[Level] do
          begin
            for BX := 1 to Size[Level] do
            begin
              Mem[$A000 : P] := Sum;
              Inc(P);
            end;
            Inc(P, ScrWidth - Size[Level]);
          end;

          Inc(Ofs, Size[Level]);
        end;
        Inc(Ofs, (Size[Level] - 1) * ScrWidth);
      end;
    end;

    Delay(20);
    Inc(Level, Dir);
    if Level = -1 then
    begin
      Dir := -Dir;                      { turn around at the coarsest level }
      Inc(Level, Dir);
      Delay(5000);                      { hold on the clear image }
    end;
  until Level = MosaicLevels + 1;
end;

{ --------------------------------------------------------------------------
  Mosaic_Load (10e3:0017)

  This was missing, which is why the scene ran to completion and drew nothing:
  it was pixelating an empty screen through a black palette.

      Seek $02AEE0, read 64,000 bytes into the VIRTUAL screen
      for I := 1 to 255 do SetRGB(I, Round(I*K), Round(I*K), Round(I*K))

  All three channels take the SAME value, so it is a neutral GREY ramp. K is
  the 80-bit constant at CS:$000D = 0.247, which puts I = 255 at 63 -- the top
  of the DAC exactly.
  -------------------------------------------------------------------------- }
procedure Load;
var
  F : file;
  I : Integer;
  V : Byte;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $02AEE0);
  BlockRead(F, Mem[VirtScrSeg : 0], 64000);
  Close(F);

  for I := 1 to 255 do
  begin
    V := Round(I * 0.247);
    SetRGB(I, V, V, V);
  end;
end;

{ [transcribed] Demo_Scene3 (10e3:0206) -- clear both screens, load, run,
  clear both again. }
procedure Scene3;
begin
  ClearScreen($A000, 0);
  ClearScreen(VirtScrSeg, 0);
  Load;
  MosaicRun;
  ClearScreen($A000, 0);
  ClearScreen(VirtScrSeg, 0);
end;

end.
