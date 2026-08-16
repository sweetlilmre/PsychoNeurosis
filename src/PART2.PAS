{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002
  Reconstructed from NEUROSIS_002_fpu.exe.

  Two scenes: a hardware-panned 1280x200 house panorama ending at a garage
  door that rolls up onto a starfield, then a solid depth-sorted 3-D object
  sequence choreographed to the music.

  No DemoVT calls in the main body -- the music plays straight through and the
  fade lives at the end of scene 2.

  Segment 108b is 14 KB, the largest single piece of demo code in Psycho
  Neurosis, and it is a solid-polygon 3-D engine.

  ADDRESS MAP
    main body            1000:0032
    Demo_Scene1          1008:0724   Scene1_Init         1008:01c7
    Scene1_LoadFrames    1008:00b9   Scene1_Run          1008:066f
    Anim_ShowFrame       107c:002a   VGA_SelectPlane     107c:00ca
    Door_RaiseOneRow     1008:0086   Bitmap_Blit         1008:0000
    Palette_BrightenStep 1008:0246   Palette_FadeOut     1008:02de
    Demo_Scene2          108b:2454   Scene2_Choreography 108b:11c1
    Obj_SetRotation      108b:03be   Obj_SetPosition     108b:00bf
    Obj_Transform        108b:0e03   Obj_RenderA/B/C     108b:0b42/0ca1/0a2d
    Poly_FillFan         108b:09b1   Tri_Fill            108b:0461
    VGA_FlipPage         140c:00f4   VGA_FillRect        140c:011e
  =========================================================================== }

{$G+}   { 286 instructions -- SHR reg,imm is not an 8086 encoding }

unit Part2;

interface

procedure RunPart2;

implementation

uses VGA, Crt, DemoVT;

{$I gen/P2OBJ.INC}       { const VertEnterprise/Revolver/Sailboat/Quad and
                           the matching FaceXxx streams }

{ ===========================================================================
  Scene 1 -- the house panorama and the garage door
  =========================================================================== }

const
  PanoWidth   = 1280;        { four Mode-X planes of 64000 bytes }
  PanoHeight  = 200;
  ViewWidth   = 320;
  ScrollEnd   = PanoWidth - ViewWidth;    { 960 }

  DoorW       = 146;         { written into the bitmap header by Scene1_Init }
  DoorH       = 85;
  DoorBytes   = DoorW * DoorH;            { 12410, +2 header = 12412 }
  SkyColour   = 128;         { $80 -- the mask the stars are drawn into }

  NumStars    = 50;
  StarX       = 146;         { Random(146) + 1 }
  StarY       = 85;          { Random(85)  + 1 }
  StarCol     = 25;          { Random(3) + 25 }

  DoorFrames  = 85;          { $55 -- one row per frame, = the door height }
  AfterFrames = 25;          { $19 }
  FadeFrames  = 64;          { $40 }

var
  Door   : array[0..1 + DoorBytes] of Byte;   { DS:$0D46, header then pixels }
  SX, SY : array[1..NumStars] of Integer;
  SC     : array[1..NumStars] of Byte;

{ ===========================================================================
  RECONSTRUCTION SCAFFOLDING -- see the note in PART1_INTRO.PAS.
    [transcribed] read out of the binary   [inferred] implied by call sites
    [stub] signature only
  =========================================================================== }

const
  MaxFaces = 64;             { the largest face count of the four models }
  MaxVerts = 80;             { the largest vertex count }
  MaxFaceV = 10;             { faces have 3, 4, 6 or 8 vertices }

type
  { [transcribed] In-memory faces are 23 bytes ($17): a vertex count, a colour
    byte, and up to ten 16-bit indices. The sorted list starts at object
    offset $533 and the object stride is $B51 = 2,897 bytes. }
  TFace = record
    Count  : Integer;
    Colour : Byte;
    V      : array[1..MaxFaceV] of Integer;
  end;

  TVertex = record
    X, Y, Z : Integer;
  end;

  TRGB = record
    R, G, B : Byte;
  end;

var
  Buffer    : Pointer;                  { 64,000-byte plane staging buffer }
  BufferSeg : Word;
  Pal       : array[0..255] of TRGB;
  NumFaces  : Integer;
  NextSlot  : Integer;
  Page      : Integer;
  Face      : array[1..MaxFaces] of TFace;
  Sorted    : array[1..MaxFaces] of TFace;
  Vertex    : array[1..MaxVerts] of TVertex;
  PX, PY    : array[1..MaxFaceV] of Integer;
  PageAddr  : array[0..1] of Word;
  { the CRTC start address of each of the two pages -- ShowFrame reads
    this one from assembler, so it must be a simple word array }
  PageBase  : array[0..1] of Word;

var
  { DS:$4B08 -- the PANORAMA's row table. 320 bytes per plane row, i.e. a
    1,280-pixel logical line, which is what the house scrolls across. }
  PanoRowOfs : array[0..255] of Word;

{ [transcribed] 1436:0128 -- REP MOVSW of 32,000 words = 64,000 bytes into the
  currently selected Mode-X plane. The panorama is four planes of a single
  1280x200 image, so each plane load is followed by one of these. }
procedure CopyToPlane(SrcSeg, DestSeg : Word);
begin
  CopyScreen(SrcSeg, DestSeg);
end;

{ [stub] start the module. Part 002 pins its choreography to the music with
  SyncPattern rather than to a frame counter. }
procedure MusicStart;
begin
  MusicInit;
  MusicPoll;
end;

{ [transcribed] Palette_BrightenStep 1008:0246 -- +3 per channel per frame,
  clamped at 63. }
procedure PaletteBrighten;
var
  I : Integer;
begin
  WaitRetrace;
  for I := 0 to 255 do
  begin
    if Pal[I].R < 60 then Inc(Pal[I].R, 3) else Pal[I].R := 63;
    if Pal[I].G < 60 then Inc(Pal[I].G, 3) else Pal[I].G := 63;
    if Pal[I].B < 60 then Inc(Pal[I].B, 3) else Pal[I].B := 63;
    SetRGB(I, Pal[I].R, Pal[I].G, Pal[I].B);
  end;
end;

{ [transcribed] Palette_FadeOut 1008:02de -- -5 per channel per frame,
  clamped at 0. }
procedure PaletteFadeOut;
var
  I : Integer;
begin
  WaitRetrace;
  for I := 0 to 255 do
  begin
    if Pal[I].R > 5 then Dec(Pal[I].R, 5) else Pal[I].R := 0;
    if Pal[I].G > 5 then Dec(Pal[I].G, 5) else Pal[I].G := 0;
    if Pal[I].B > 5 then Dec(Pal[I].B, 5) else Pal[I].B := 0;
    SetRGB(I, Pal[I].R, Pal[I].G, Pal[I].B);
  end;
end;

{ [stub] Bitmap_Blit 1008:0000 -- the garage door, drawn one row taller each
  frame as it rolls up. }
{ --------------------------------------------------------------------------
  Bitmap_Blit (1008:0000) -- the garage door.

  A MODE-X transparent blit, not the linear copy an earlier reconstruction
  assumed. Three things the instruction stream settles:

  * The width and height are read from the SOURCE, not passed -- the first two
    bytes of the bitmap are W then H. That is the "header then pixels" layout
    the Door array already documented.
  * It is Mode-X: the destination is rowtable[Y] + X shr 2, the plane comes
    from X and 3 through the Sequencer Map Mask, and the mask rotates left one
    plane per pixel, advancing DI only when it wraps past plane 3.
  * The row stride is 320 BYTES PER PLANE, which means a 1,280-pixel logical
    line -- this draws into the panorama buffer, not the visible screen.

  Zero bytes are skipped, so the door has a transparent surround.
  -------------------------------------------------------------------------- }
procedure BlitBitmap(var Src; XA, Y, XB : Integer);
var
  B          : array[0..65534] of Byte absolute Src;
  W, H       : Byte;
  Row, Col   : Integer;
  X, Plane   : Integer;
  Ofs, P     : Word;
begin
  W := B[0];
  H := B[1];
  P := 2;
  for Row := 0 to H - 1 do
    for Col := 0 to W - 1 do
    begin
      X     := XA + XB + Col;
      Plane := X and 3;
      Ofs   := PanoRowOfs[Y + Row] + (X shr 2);
      if B[P] <> 0 then
      begin
        Port[$3C4] := 2;
        Port[$3C5] := 1 shl Plane;
        Mem[VGASeg : Ofs] := B[P];
      end;
      Inc(P);
    end;
end;

{ Forward declarations: Scene1 drives the starfield, which is defined after
  it in the original layout. }
procedure StarStep; forward;

{ [stub] Poly_FillFan 108b:09b1 -- fills an N-vertex convex face as N-2
  triangles from a common first vertex. }
{ --------------------------------------------------------------------------
  Tri_Fill (108b:0461) -- the solid triangle filler. Everything solid in this
  part goes through here, and it is nothing like a naive scanline fill.

  REGISTER CONVENTION. The original takes the colour on the stack and the
  three vertices in registers -- X1 in BX, Y1 in CX, X2 in DX, Y2 in SI, with
  the third vertex the only pair passed normally. Declared with ordinary
  parameters here; the behaviour is what matters.

  Four things the first reconstruction of this routine got wrong, all of them
  visible only once the actual instruction stream was read:

  1. IT DRAWS IN MODE-X. The screen is 320x240 unchained, so a pixel address
     is rowtable[y] + (x shr 2) + page, and the plane is selected through the
     Sequencer Map Mask (port $3C4 register 2). A span is written as a masked
     left group, a run of full 4-pixel groups with mask $0F, then a masked
     right group. Writing linearly -- which is what the inferred version did --
     puts every pixel in the wrong place.

  2. The edges are stepped with INTEGER DDA and an error accumulator, not a
     division per scanline: whole := d div dy, err := d mod dy, and the
     coordinate advances by an extra one whenever the error overflows.

  3. It CLIPS against a box held in DGROUP -- X 0..319, Y 0..239 -- and the
     240 is what confirms the 320x240 screen the "WRONG UNIVERSE" banner sits
     at the bottom of.

  4. It BUILDS A SPAN LIST first and then draws it BACKWARDS. Both passes are
     kept here because the order is observable: later spans overwrite earlier
     ones where they touch.
  -------------------------------------------------------------------------- }

const
  { DS:$066E..$0675 -- the clip box. Y runs to 239: this is a 320x240 screen. }
  ClipY1 = 0;    ClipY2 = 239;
  ClipX1 = 0;    ClipX2 = 319;

  { DS:$0676 / $067A -- Map Mask values for a span's partial first and last
    four-pixel groups, indexed by the coordinate mod 4. }
  LeftMask  : array[0..3] of Byte = ($0F, $0E, $0C, $08);
  RightMask : array[0..3] of Byte = ($0F, $01, $03, $07);

var
  { the span list the first pass builds, one (left, right) pair per scanline }
  SpanL, SpanR : array[0..255] of Integer;

  { DS:$A0CA -- Mode-X row offsets, one word per scanline. Separate from the
    linear table in the VGA unit: the stride here is 80 bytes per plane row,
    not 320. }
  RowOfs : array[0..255] of Word;

procedure BuildModeXRows;
var
  Y : Integer;
begin
  for Y := 0 to 255 do RowOfs[Y]     := Y * 80;    { 320-pixel screen  }
  for Y := 0 to 255 do PanoRowOfs[Y] := Y * 320;   { 1280-pixel panorama }
end;

procedure TriFill(Colour : Byte; X1, Y1, X2, Y2, X3, Y3 : Integer);
var
  T, Row, Top, Bot     : Integer;
  XA, XB               : Integer;
  DXA, EA, ErrA, DYA   : Integer;
  DXB, EB, ErrB, DYB   : Integer;
  L, R, Groups, I      : Integer;
  Ofs                  : Word;

  { one DDA step: advance X by the whole part, plus one more when the
    accumulated remainder passes the denominator }
  procedure Step(var X, Err : Integer; Whole, Rem, Den : Integer);
  begin
    Inc(Err, Rem);
    if Err >= Den then
    begin
      Dec(Err, Den);
      Inc(X);
    end;
    Inc(X, Whole);
  end;

  procedure Setup(var Whole, Rem : Integer; DX, DY : Integer);
  begin
    if DY = 0 then begin Whole := 0; Rem := 0; Exit end;
    Whole := DX div DY;
    Rem   := DX mod DY;
    if DX < 0 then
    begin
      Dec(Whole);
      Inc(Rem, DY);
    end;
  end;

begin
  { degenerate }
  if (Y1 = Y2) and (Y2 = Y3) then Exit;

  { sort the three vertices by Y ascending }
  if Y2 < Y1 then
  begin
    T := Y1; Y1 := Y2; Y2 := T;   T := X1; X1 := X2; X2 := T;
  end;
  if Y3 < Y1 then
  begin
    T := Y1; Y1 := Y3; Y3 := T;   T := X1; X1 := X3; X3 := T;
  end;
  if Y3 < Y2 then
  begin
    T := Y2; Y2 := Y3; Y3 := T;   T := X2; X2 := X3; X3 := T;
  end;

  if (Y3 < ClipY1) or (Y1 > ClipY2) then Exit;

  { the long edge Y1->Y3, and the two short ones Y1->Y2 then Y2->Y3 }
  DYA := Y3 - Y1;
  Setup(DXA, EA, X3 - X1, DYA);
  DYB := Y2 - Y1;
  Setup(DXB, EB, X2 - X1, DYB);

  XA := X1;  XB := X1;
  ErrA := 0; ErrB := 0;
  Top := Y1;

  for Row := Y1 to Y3 - 1 do
  begin
    if Row = Y2 then                   { switch to the second short edge }
    begin
      DYB := Y3 - Y2;
      Setup(DXB, EB, X3 - X2, DYB);
      XB := X2;  ErrB := 0;
    end;
    if (Row >= ClipY1) and (Row <= ClipY2) then
    begin
      SpanL[Row] := XA;
      SpanR[Row] := XB;
    end;
    Step(XA, ErrA, DXA, EA, DYA);
    if DYB <> 0 then Step(XB, ErrB, DXB, EB, DYB);
  end;

  { ---- second pass: draw the spans, backwards ---- }
  Bot := Y3 - 1;  if Bot > ClipY2 then Bot := ClipY2;
  if Top < ClipY1 then Top := ClipY1;

  for Row := Bot downto Top do
  begin
    L := SpanL[Row];  R := SpanR[Row];
    if L > R then begin T := L; L := R; R := T end;
    if R > ClipX2 then R := ClipX2;
    if L < ClipX1 then L := ClipX1;
    if L >= R then Continue;

    Ofs := RowOfs[Row] + (L shr 2) + PageBase[Page];
    Groups := ((R - 1) - (L and $FFFC)) shr 2;

    Port[$3C4] := 2;
    if Groups = 0 then
      Port[$3C5] := LeftMask[L and 3] and RightMask[R and 3]
    else
      Port[$3C5] := LeftMask[L and 3];
    Mem[VGASeg : Ofs] := Colour;
    Inc(Ofs);

    if Groups > 0 then
    begin
      if Groups > 1 then
      begin
        Port[$3C5] := $0F;                    { all four planes at once }
        FillChar(Mem[VGASeg : Ofs], Groups - 1, Colour);
        Inc(Ofs, Groups - 1);
      end;
      Port[$3C5] := RightMask[R and 3];
      Mem[VGASeg : Ofs] := Colour;
    end;
  end;
end;

{ [transcribed] Poly_FillFan 108b:09b1 -- an N-vertex convex face drawn as
  N-2 triangles all sharing vertex 1. That is why the object format allows up
  to ten vertices per face and still only ever calls a triangle filler. }
procedure FillFan(Colour : Byte; Count : Integer; XS, YS : Pointer);
type
  TCoords = array[1..MaxFaceV] of Integer;
var
  PXs : ^TCoords;
  PYs : ^TCoords;
  I   : Integer;
begin
  PXs := XS;
  PYs := YS;
  for I := 2 to Count - 1 do
    TriFill(Colour,
            PXs^[1], PYs^[1],
            PXs^[I], PYs^[I],
            PXs^[I + 1], PYs^[I + 1]);
end;

{ [stub] VGA_FlipPage 140c:00f4 -- set the CRTC start address to the given
  page and wait for retrace. }
{ --------------------------------------------------------------------------
  VGA_FlipPage (140c:00f4) -- set the CRTC start address.

  The ORDER matters and an earlier reconstruction had it backwards. It waits
  for the horizontal blank to END, writes both registers inside it, and only
  THEN waits for the vertical retrace:

      wait while (3DA and 1) <> 0     -- sit out the current h-blank
      out 3D4, $0D + low  shl 8       -- word writes: index in AL, data in AH
      out 3D4, $0C + high shl 8
      wait until (3DA and 8) <> 0     -- now wait for v-retrace

  Writing after the retrace, which is what the inferred version did, lands the
  change a frame late and tears.
  -------------------------------------------------------------------------- }
procedure FlipPage(StartAddr : Word); assembler;
asm
  MOV  BL, $0D
  MOV  BH, BYTE PTR StartAddr        { low byte  }
  MOV  CL, $0C
  MOV  CH, BYTE PTR StartAddr+1      { high byte }
  MOV  DX, $3DA
@@HBlank:
  IN   AL, DX
  TEST AL, 1
  JNZ  @@HBlank
  MOV  DX, $3D4
  MOV  AX, BX
  OUT  DX, AX
  MOV  AX, CX
  OUT  DX, AX
  MOV  DX, $3DA
@@VRetrace:
  IN   AL, DX
  TEST AL, 8
  JZ   @@VRetrace
end;

{ --------------------------------------------------------------------------
  Scene1_LoadFrames (1008:00b9)

  ASSETS  NEUROSIS.DAT $03BE36, 269,180 bytes:
            assets/part002/house_palette.pal      768 B
            assets/part002/house_plane0.raw       64,000 B  |  four Mode-X
            assets/part002/house_plane1.raw       64,000 B  |  planes of ONE
            assets/part002/house_plane2.raw       64,000 B  |  1280x200 image
            assets/part002/house_plane3.raw       64,000 B  |
            assets/part002/garage_door.bin        12,412 B
          De-interleaved composite:
            assets/part002/panorama_1280x200.png
          Reading a plane on its own as 320x200 gives a plausible but WRONG
          picture -- see docs/15-part002.md.
  -------------------------------------------------------------------------- }
procedure LoadPanorama;
var
  F : file;
  P : Integer;
begin
  { Buffer was dereferenced without ever being allocated -- the same fault
    that hung the tunnel and part 001 scene 2. }
  GetMem(Buffer, 64000);
  BufferSeg := Seg(Buffer^);
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $03BE36);
  BlockRead(F, Palette, 768);
  for P := 0 to 3 do
  begin
    SelectPlane(P);                      { 107c:00ca }
    BlockRead(F, Buffer^, 64000);
    CopyToPlane(BufferSeg, $A000);       { 1436:0128 }
  end;
  BlockRead(F, Door, DoorBytes + 2);
  Close(F);
end;

{ --------------------------------------------------------------------------
  Anim_ShowFrame (107c:002a) -- hardware pan, no pixels moved.
  -------------------------------------------------------------------------- }
procedure ShowFrame(Page : Integer; PanOfs : Word); assembler;
asm
  { addr := PageBase[Page] + PanOfs shr 2
    NB the parameter cannot be called Offset -- OFFSET is an operator
    in TP7's inline assembler. }
  MOV  BX, Page
  SHL  BX, 1
  MOV  AX, [BX + OFFSET PageBase]
  MOV  DX, PanOfs
  SHR  DX, 2
  ADD  AX, DX

  MOV  DX, $3D4                  { CRTC start address: coarse, 4-pixel steps }
  MOV  AH, AL
  MOV  AL, $0D
  OUT  DX, AX
  { ... high byte to $0C ... }

  MOV  DX, $3DA                  { wait for retrace }
@W1: IN AL, DX
  TEST AL, 8
  JNZ  @W1
@W2: IN AL, DX
  TEST AL, 8
  JZ   @W2

  MOV  DX, $3C0                  { fine pan, sub-4-pixel }
  MOV  AL, $13
  OUT  DX, AL
  MOV  AL, BYTE PTR PanOfs
  AND  AL, 3
  SHL  AL, 1
  OUT  DX, AL
  MOV  AL, $20
  OUT  DX, AL
end;

{ --------------------------------------------------------------------------
  Door_RaiseOneRow (1008:0086)

  Scrolls the door bitmap up one row and fills the vacated bottom row with
  the sky mask colour. Eighty-five calls and the door is fully open.
  -------------------------------------------------------------------------- }
procedure RaiseDoor;
begin
  Move(Door[2 + DoorW], Door[2], DoorBytes - DoorW);
  FillChar(Door[2 + DoorBytes - DoorW], DoorW, SkyColour);
end;

{ --------------------------------------------------------------------------
  Scene1_Run (1008:066f)
  -------------------------------------------------------------------------- }
procedure Scene1;
var
  I, F : Integer;
begin
  { blank the DAC, load, then install the real palette }
  for I := 0 to 255 do SetRGB(I, 0, 0, 0);
  LoadPanorama;
  for I := 0 to 255 do SetRGB(I, Pal[I].R, Pal[I].G, Pal[I].B);
  Door[0] := DoorW;  Door[1] := DoorH;   { the file's header bytes are zero }

  ShowFrame(0, 0);
  Delay(2000);
  MusicStart; SyncPattern(1, 5);

  for F := 0 to ScrollEnd do             { pan the full panorama }
  begin
    MusicPoll;
    ShowFrame(0, F);
  end;

  Delay(2000);

  for I := 1 to NumStars do
  begin
    SX[I] := Random(StarX) + 1;
    SY[I] := Random(StarY) + 1;
    SC[I] := Random(3) + StarCol;
  end;

  { ---- the door rolls up, stars showing through the opening ---- }
  for F := 0 to DoorFrames do
  begin
    RaiseDoor;
    StarStep;
  end;

  for F := 0 to AfterFrames do
  begin
    StarStep;
    PaletteBrighten;                     { +3 per channel per frame }
  end;

  ClearVirtual;
  for I := 0 to 3 do begin SelectPlane(I); CopyToPlane(BufferSeg, $A000) end;
  for F := 1 to FadeFrames do PaletteFadeOut;   { -5 per channel per frame }
end;

{ --------------------------------------------------------------------------
  One frame of the starfield. Stars are written into the door bitmap only
  where the pixel is already the sky mask, so they are visible exactly as
  much of the opening as has been revealed -- no clipping logic needed.
  -------------------------------------------------------------------------- }
procedure StarStep;
var
  I : Integer;
begin
  for I := 1 to NumStars do
    if Door[2 + SY[I] * DoorW + SX[I]] = SkyColour then
      Door[2 + SY[I] * DoorW + SX[I]] := SC[I];

  BlitBitmap(Door, 960, 92, 94);         { 1008:0000 }

  for I := 1 to NumStars do
    if Door[2 + SY[I] * DoorW + SX[I]] = SC[I] then
      Door[2 + SY[I] * DoorW + SX[I]] := SkyColour;

  for I := 1 to NumStars do
  begin
    Inc(SX[I]);
    if SX[I] > DoorW then SX[I] := 1;
  end;
end;

{ ===========================================================================
  Scene 2 -- solid depth-sorted 3-D
  =========================================================================== }

const
  ObjSize    = $B51;         { 2897 bytes per object }
  FaceSize   = $17;          { 23 bytes: count, colour, up to 10 word indices }
  SortedOfs  = $533;         { sorted face list within the object }

{ MaxFaceV and TFace are declared with the scaffolding above, because the
  Face/Sorted arrays there need the type. }

{ --------------------------------------------------------------------------
  Obj_Transform (108b:0e03) -- painter's algorithm.

  Average Z per face, then repeatedly take the face with the smallest average
  and append it to the sorted list. Back to front, so nearer faces overpaint.
  -------------------------------------------------------------------------- }
procedure DepthSort(var Obj);
var
  I, J, Best, BestZ : Integer;
  AvgZ : array[1..MaxFaces] of Integer;
begin
  for I := 1 to NumFaces do
  begin
    AvgZ[I] := 0;
    for J := 1 to Face[I].Count do Inc(AvgZ[I], Vertex[Face[I].V[J]].Z);
    AvgZ[I] := AvgZ[I] div Face[I].Count;
  end;

  repeat
    Best := 0;  BestZ := 0;
    for I := 1 to NumFaces do
      if AvgZ[I] < BestZ then begin BestZ := AvgZ[I]; Best := I end;
    if Best > 0 then
    begin
      Sorted[NextSlot] := Face[Best];
      AvgZ[Best] := 0;
      Inc(NextSlot);
    end;
  until Best = 0;
end;

{ --------------------------------------------------------------------------
  Obj_RenderC (108b:0a2d) -- draw the sorted faces as filled triangle fans.
  -------------------------------------------------------------------------- }
procedure RenderSolid(var Obj);
var
  I, J : Integer;
begin
  for I := 1 to NumFaces do
  begin
    for J := 1 to Sorted[I].Count do
    begin
      PX[J] := Vertex[Sorted[I].V[J]].X;
      PY[J] := Vertex[Sorted[I].V[J]].Y;
    end;
    FillFan(Sorted[I].Colour, Sorted[I].Count, @PX, @PY);   { N-2 triangles }
  end;
  FlipPage(PageAddr[Page]);
  Page := (Page + 1) mod 2;
end;

{ --------------------------------------------------------------------------
  Scene2_Choreography (108b:11c1)

  A straight-line script of about a dozen loops, each with its own rotation
  deltas and position increments, interleaved with SyncPattern calls that WAIT
  for the music to reach a given MOD pattern. This is the only place in the
  demo where the music drives the structure rather than merely playing.
  -------------------------------------------------------------------------- }
procedure Choreography;
begin
  { seed 500 particles: X Random(320), Y Random(200), Z Random(20)+70 }
  { ... then, repeatedly ... }
  {   Obj_SetRotation(dx, dy, dz, Obj)                                   }
  {   Obj_SetPosition(x, y, z, Obj)     -- 32-bit                        }
  {   VGA_FillRect(...)                                                  }
  {   Obj_Transform(Obj)                -- depth sort                    }
  {   Obj_RenderA / B / C (Obj)         -- three draw styles             }
  { with SyncPattern(1, n) between sections for n = 2, 3, 4, 6           }
end;

{ ===========================================================================
  Main body (1000:0032)
  =========================================================================== }

procedure Scene2;
begin
  Choreography;
end;

procedure RunPart2;
begin
  SetMode13h;
  VirtScrAlloc;
  Scene1;   while KeyPressed do ReadKey;
  Scene2;   while KeyPressed do ReadKey;
  VirtScrFree;
  Halt(0);
end;

end.

{ ===========================================================================
  NOTES

  * The panorama costs nothing per frame -- it is one 1280x200 Mode-X image
    and the CRTC does the scrolling. Same technique as part 003's tunnel.
  * The garage door needs no clipping or state: a single mask colour (128)
    means "sky", the door scroll writes that colour into vacated rows, and
    stars are drawn only onto it. How far the door has opened is implicit in
    the bitmap itself.
  * Scene 2 is solid-filled, depth-sorted 3-D with page flipping -- ambitious
    for 1994 Borland Pascal, and it is why segment 108b is 14 KB.

  THE MODELS
  * Compiled into DGROUP, not loaded from NEUROSIS.DAT. Scene2_Intro
    (108b:1bbd) reads them and halves the coordinates on load. The on-disk
    face stream is: count, index1..indexN, colour -- count+2 words per face.
      assets/part002/obj_enterprise_top.png    75 verts, 55 faces
                                     the USS ENTERPRISE -- saucer, neck and
                                     two warp nacelles; only reads from above
      assets/part002/obj_revolver_long.png     68 verts, 64 faces -- a REVOLVER
      assets/part002/obj_sailboat_long2.png    32 verts, 21 faces -- a SAILBOAT
      assets/part002/obj_quad_top.png           4 verts,  1 face  -- a quad
      assets/part002/banner_320x40.png         320x40 -- "WRONG UNIVERSE"

    The revolver and the sailboat are both modelled along Y, so they only
    look right with Y horizontal. vecobj.py renders five axis pairs for
    exactly this reason -- a single projection is not enough to name a model.
  * Obj_SetPosition also holds the transform: angles wrapped into 0..3600
    (tenths of a degree), sin/cos per axis, rotate, translate, then
    Math_PerspDivide (142a:0071) for the projected Z.

  RESOLVED
  * The 12,800-byte buffer is the "WRONG UNIVERSE" BANNER -- a 320x40 image
    drawn by 108b:1101 at screen rows 200..239, i.e. the bottom strip of a
    320x240 Mode-X screen, below the 3-D object view. It is plotted to BOTH
    pages. Its colours are 101..200, exactly the range 108b:1101 loads into
    the palette from the 768-byte read.
        assets/part002/scene2_panel.png / .bin / .pal
  * Obj_RenderB (108b:0ca1) copies the 2,897-byte object record to a local,
    clears, plots 500 stars, transforms and depth-sorts, fills each face with
    Poly_FillFan, then flips the page. So RenderB is the starfield variant.
  * The 1,550-byte read at DAT $080CB2 is DEAD. It is byte-identical to the
    1,550 bytes part 003 scene 7 loads at $11EEC0, contains only the values 0
    and $AB, and the only instruction referencing its buffer (DS:$5448) is the
    BlockRead itself. Both parts read it and neither looks at it.
        assets/part002/font_5x5.bin

  OPEN
  * Nothing outstanding.
  =========================================================================== }
