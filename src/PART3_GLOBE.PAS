{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 4
  Reconstructed from NEUROSIS_003_fpu.exe, segment 119d.

  A picture show with cross-fades, alternating a title image with three
  others, and between each pair a rotating globe: a scrolling cloud band
  mapped onto a sphere through a precomputed scatter blit.

  There is no sphere maths at run time. Two 45,994-byte tables of 16-bit
  offsets are loaded from disk; rendering a frame is just

      for i := 1 to 22996 do
        Mem[$A000 : Dst[i]] := Mem[VirtScr : Src[i]];

  and then the source band is scrolled one pixel left. The scroll is what
  makes the globe appear to turn.

  ADDRESS MAP
    Demo_Scene4        119d:0211     Globe_LoadTables   119d:010f
    Palette_FadeIn     119d:0064     Palette_FadeOut    119d:0000
    Globe_RenderFrame  119d:018b
  =========================================================================== }

unit Part3Globe;

interface

procedure Scene4;

implementation

uses VGA, Crt;

const
  { All four screens share ONE palette, loaded once at the start of the scene.
    That is what lets them cross-fade into each other without a palette
    reload -- only the pixels change. }
  DataOfs     = $0C0E2E;      { palette + the two offset tables }
  PaletteSize = $300;         { 768 }
  TableSize   = $B3AA;        { 45994 bytes = 22997 words }
  Entries     = TableSize div 2;

  { The four full-screen images, in the order the scene uses them. }
  ImgTitle    = $0D7882;      { "ReAl TiMe" gold lettering -- shown 3 times }
  ImgCity     = $0E7282;      { city skyline against clouds }
  ImgFigures  = $0F6C82;      { two figures against clouds }
  ImgDeth     = $106682;      { fiery DETH logo }

  FadeSteps   = 64;           { $40 -- one DAC step per frame, 6-bit range }
  HoldMs      = 1000;

  { The scrolled band: rows 1..150, 300 bytes wide, inside the 320-wide
    virtual screen. Exactly the region the src offset table samples. }
  ScrollTop   = 1;
  ScrollRows  = 150;          { $96 }
  ScrollWords = 150;          { $96 -- 300 bytes }
  ScrollSkip  = 20;           { $14 -- rest of the 320-byte row }

type
  TOffsets = array[0..Entries - 1] of Word;

var
  SrcOfs, DstOfs : ^TOffsets;      { two GetMem'd 45994-byte tables }
  Target         : array[0..767] of Byte;   { fade-in destination palette }
  F              : file;           { NEUROSIS.DAT, open for the whole scene }

  { RenderFrame is hand assembler and reloads DS from these each pixel, so the
    two table segments have to be plain words it can MOV from. }
  SrcSeg, DstSeg : Word;

{ --------------------------------------------------------------------------
  Globe_LoadTables (119d:010f)

  ASSETS  NEUROSIS.DAT $0C0E2E, 92,756 bytes in three reads:
            assets/part003/scene4_palette.pal      768 B, shared by all four
                                                   images -- see note above
            assets/part003/globe_src_offsets.bin   45,994 B, source offsets
            assets/part003/globe_dst_offsets.bin   45,994 B, destination offsets
          Coverage maps (generated, not in the demo):
            assets/part003/globe_warp_dst.png      a filled disc, 22,996 px
            assets/part003/globe_warp_src.png      a 300x150 band, 16,316 px
          The destination is a disc and the source a rectangle sampled
          many-to-one at the edges: that is a sphere map.
          See docs/10-part3-scene4-globe.md.
  -------------------------------------------------------------------------- }
procedure LoadTables;
begin
  GetMem(SrcOfs, TableSize);
  GetMem(DstOfs, TableSize);
  SrcSeg := Seg(SrcOfs^);
  DstSeg := Seg(DstOfs^);
  BlockRead(F, Target,  PaletteSize);
  BlockRead(F, SrcOfs^, TableSize);
  BlockRead(F, DstOfs^, TableSize);
end;

{ --------------------------------------------------------------------------
  Palette_FadeIn (119d:0064)
  Read each DAC entry back, step any channel that is below its target up by
  one, write it out. Called 64 times, which is the full 6-bit range.
  -------------------------------------------------------------------------- }
procedure FadeIn;
var
  I          : Word;
  R, G, B    : Byte;
begin
  if KeyPressed then Exit;
  WaitRetrace;
  for I := 0 to 255 do
  begin
    GetRGB(I, R, G, B);
    if R < Target[I * 3 + 0] then Inc(R);
    if G < Target[I * 3 + 1] then Inc(G);
    if B < Target[I * 3 + 2] then Inc(B);
    SetRGB(I, R, G, B);
  end;
end;

{ --------------------------------------------------------------------------
  Palette_FadeOut (119d:0000)
  The same shape, but every non-zero channel steps down toward black. No
  target table needed.
  -------------------------------------------------------------------------- }
procedure FadeOut;
var
  I       : Word;
  R, G, B : Byte;
begin
  WaitRetrace;
  for I := 0 to 255 do
  begin
    GetRGB(I, R, G, B);
    if R <> 0 then Dec(R);
    if G <> 0 then Dec(G);
    if B <> 0 then Dec(B);
    SetRGB(I, R, G, B);
  end;
end;

{ --------------------------------------------------------------------------
  Globe_RenderFrame (119d:018b)

  Two passes, and the whole effect is in them.

  1. Scatter blit. Walk both offset tables in step and copy one byte each
     time, virtual screen -> $A000. Because the tables were precomputed, an
     arbitrary warp costs one MOVSB per pixel and no arithmetic at all.

  2. Scroll the source band one pixel left, wrapping the leading word to the
     end of the row. Next frame the same sphere map samples shifted texture,
     so the globe appears to rotate.

  Hand assembler: it juggles DS/ES per pixel to read an offset from one
  table's segment, another from the second, then move a byte between two
  further segments.
  -------------------------------------------------------------------------- }
procedure RenderFrame;
begin
  { 119d:018f -- the frame is abandoned the moment a key is down. }
  if KeyPressed then Exit;

  asm
  { ---- pass 1: precomputed scatter blit ----

    DS IS REPOINTED THREE TIMES PER PIXEL, so the segment values have to be in
    registers before the loop starts. Reading them by name inside it --
    `MOV DS,[DstSeg]` -- looks like Pascal and compiles, but by the second
    iteration DS is the virtual screen, so it fetches the "segment" out of
    video memory and the blit scatters bytes at random. 119d:01be caches both
    in CX and DX ahead of the loop for exactly this reason.

    The source offset is loaded straight into SI rather than through CX, which
    saves the reload the original needs at 119d:01d2 after using CX as
    scratch. }
  PUSH DS
  MOV  AX, $A000
  MOV  ES, AX                  { destination is always video }
  MOV  BX, 2                   { entry 0 is skipped }
  MOV  AX, [VirtScrSeg]        { DS is still DGROUP here -- read them now }
  MOV  CX, [SrcSeg]
  MOV  DX, [DstSeg]
@Blit:
  MOV  DS, DX                  { DS := the destination-offset table }
  MOV  SI, BX
  MOV  DI, [SI]                { DI := DstOfs[i] }
  MOV  DS, CX                  { DS := the source-offset table }
  MOV  SI, [SI]                { SI := SrcOfs[i] }
  MOV  DS, AX                  { DS := virtual screen }
  ADD  BX, 2
  MOVSB                        { ES:[DI] <- DS:[SI] }
  CMP  BX, TableSize
  JNZ  @Blit

  { ---- pass 2: scroll rows 1..150 left by one pixel, with wrap ---- }
  MOV  ES, AX
  MOV  DS, AX
  MOV  DI, 320                 { row 1, column 0 }
  MOV  SI, 321                 { one pixel along }
  MOV  BX, ScrollRows
@Row:
  MOV  AX, [SI]                { save the word about to be shifted off }
  MOV  CX, ScrollWords
  REP  MOVSW
  MOV  ES:[DI], AX             { and wrap it to the end of the row }
  ADD  DI, ScrollSkip
  ADD  SI, ScrollSkip
  DEC  BX
  JNZ  @Row
  POP  DS
  end;
end;

{ --------------------------------------------------------------------------
  Demo_Scene4 (119d:0211)

  The pattern repeats three times: show the title image, fade it up, hold,
  fade it down; then load the next image into the *virtual* screen, blank the
  visible screen, and fade in and out again -- this time with the globe
  running, so the new image is what wraps around the sphere.
  -------------------------------------------------------------------------- }
procedure Scene4;
var
  I : Integer;

  procedure ShowFlat(FileOfs : LongInt);      { straight to the visible screen }
  var I : Integer;
  begin
    Seek(F, FileOfs);
    BlockRead(F, VirtScr^, 64000);
    if not KeyPressed then CopyScreen(VirtScrSeg, $A000);
    ClearScreen(VirtScrSeg, 0);
    for I := 1 to FadeSteps do FadeIn;
    if not KeyPressed then Delay(HoldMs);
    for I := 1 to FadeSteps do FadeOut;
  end;

  procedure ShowGlobe(FileOfs : LongInt);         { texture for the sphere }
  var I : Integer;
  begin
    Seek(F, FileOfs);
    if not KeyPressed then BlockRead(F, VirtScr^, 64000);
    ClearScreen($A000, 0);
    for I := 1 to FadeSteps do begin FadeIn;  RenderFrame end;
    for I := 1 to FadeSteps do begin FadeOut; RenderFrame end;
  end;

begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  LoadTables;

  for I := 0 to 255 do SetRGB(I, 0, 0, 0);    { start from black }

  ShowFlat(ImgTitle);   ShowGlobe(ImgCity);
  ShowFlat(ImgTitle);   ShowGlobe(ImgFigures);
  ShowFlat(ImgTitle);   ShowGlobe(ImgDeth);

  Close(F);
  FreeMem(SrcOfs, TableSize);
  FreeMem(DstOfs, TableSize);
end;

end.

{ ===========================================================================
  NOTES

  * The globe costs one MOVSB per pixel and nothing else. All the geometry
    was baked into the two offset tables at build time, so the run-time code
    knows nothing about spheres.
  * 22,996 destination pixels drawn from 16,316 distinct source pixels: the
    same source pixel is read several times near the sphere's limb, which is
    exactly the foreshortening you want.
  * The scrolled band (rows 1..150, 300 bytes wide) matches the source
    coverage map exactly -- good evidence the two tables and the scroll were
    authored together.
  * Every loop is guarded by KeyPressed so the scene can be skipped mid-fade.

  RESOLVED
  * 119d:054f is an EMPTY PROCEDURE -- PUSH BP / MOV BP,SP / LEAVE / RETF and
    nothing else. A `procedure X; begin end;` that was never filled in.
  * The title image IS re-seeked and re-read from disk on every pass. That is
    simply what the code does; whether the authors meant it as a cheap way to
    reset the buffer or never noticed the cost is not a question the binary
    can answer.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
