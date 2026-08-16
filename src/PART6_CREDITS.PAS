{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.006, the credits
  Reconstructed from NEUROSIS_006_fpu.exe.

  Four scenes: a line wipe, the "whooshtext", a fire effect, and the greetings
  scroller.

  ADDRESS MAP
    Demo_Scene1  1095:07d4    Scene1_LineWipe   1095:0578
    Demo_Scene2  100f:07d5    Whoosh_Run        100f:0590
    Demo_Scene3  1118:09df    Fire_Run          1118:08d3
    Demo_Scene4  11bb:02c9    Credits_Step      11bb:0168
  =========================================================================== }

unit Part6Credits;

interface

procedure RunPart6;

implementation

uses VGA, Crt, DemoVT;

{$I gen/P6TEXT.INC}      { const Credits : array[1..99] of String[12] }
{$I gen/P6CELL.INC}      { const WhooshBoard : array[1..26, 1..16, 1..8] of Byte }

{ ===========================================================================
  Scene 1 -- line wipe
  =========================================================================== }

{ ===========================================================================
  RECONSTRUCTION SCAFFOLDING -- see the note in PART1_INTRO.PAS.
    [transcribed] read out of the binary   [inferred] implied by call sites
    [stub] signature only
  =========================================================================== }

type
  { [transcribed] a working cell: a 2-byte (25, 25) header then 625 pixels,
    627 bytes = $273 in all. }
  TCell = record
    W, H : Byte;
    Pix  : array[1..625] of Byte;
  end;

  { [transcribed] 72 angles x 26 rows x 16 columns of Integer = $EA00. }
  TPathTab = array[0..71, 1..26, 1..16] of Integer;
  TBoard   = array[1..170, 1..16] of Byte;
  TCells   = array[0..44999] of Byte;
  TBuf64   = array[0..64999] of Byte;
  PBuf64   = ^TBuf64;

const
  FireW = 80;             { $50 }
  FireH = 98;             { 7840 / 80 }

var
  PathX, PathY : ^TPathTab;
  Board        : ^TBoard;
  Cells        : ^TCells;
  Work         : array[1..2] of TCell;
  ColourMap    : array[1..2, 0..255] of Byte;
  F            : file;

  { scene 4 (the scroller). The font is 18 x 21 per glyph -- $17A = 378 bytes
    -- and there are 59 glyphs, so it fits DGROUP at 22,302 bytes. }
  Line         : Integer;
  GlyphRow     : Integer;

  { The fire buffer. Indices run one row either side of the 80x98 body,
    because the averaging reads P[I + FireW] and writes P[I - FireW]. }
  P        : array[-FireW .. FireW * FireH + FireW] of Byte;
  Bottom   : array[1..FireW] of Byte;   { the re-randomised bottom row }
  ScaleOfs : Word;                      { Scale4x's destination cursor }
  Backdrop : Pointer;                   { DS:$934A -- 320 x 91 at row 108 }
  Font         : array[0..58, 0..20, 1..18] of Byte;

{ [inferred] Which of the 59 glyphs a character maps to. 59 glyphs starting at
  space covers ' ' through 'Z' in ASCII order, which fits both the character
  set the credits actually use and the 15,104-byte (59 x 256) font in part 001.
  Not verified against the font image, so treat the mapping as provisional. }
function Glyph(C : Char) : Byte;
begin
  if (C >= ' ') and (C <= 'Z') then
    Glyph := Ord(C) - Ord(' ')
  else
    Glyph := 0;
end;

{ [transcribed] 100f:00ac -- reads a 256-byte colour map into DS:$6FF2 + N*$100.
  Called with 2 then 1, so cell 2 (background) is loaded first. }
procedure LoadColourMap(N : Integer);
begin
  BlockRead(F, ColourMap[N], 256);
end;

{ [transcribed] 100f:0000 -- blit one working cell.

  Transparent (zero bytes skipped) AND CLIPPED, which the inferred version was
  not. Width and height come from the source's own first two bytes, and the
  routine clips against bounds held at DS:$0006 / DS:$0008, adjusting the
  SOURCE pointer by (rows skipped * width) before the copy rather than testing
  per pixel. The row table is at DS:$96DA.

  The clipping is what lets the board spin past the screen edges without the
  cells wrapping. }
procedure DrawCell(var C : TCell; X, Y : Integer);
var
  Row, Col : Integer;
  V        : Byte;
begin
  for Row := 0 to C.H - 1 do
    for Col := 0 to C.W - 1 do
    begin
      V := C.Pix[Row * C.W + Col + 1];
      if (V <> 0) and (X + Col >= 0) and (X + Col < 320)
         and (Y + Row >= 0) and (Y + Row < 200) then
        Mem[VirtScrSeg : (Y + Row) * 320 + X + Col] := V;
    end;
end;

{ [transcribed] FUN_1118_01e3 -- scene 3's backdrop.

  NOT a screen clear, which is what an earlier reconstruction assumed. It is a
  TRANSPARENT blit of 29,120 bytes -- 91 rows of 320 -- from a heap buffer
  (DS:$934A) to screen offset $8700, which is row 108. Zero bytes are skipped,
  so the fire shows through the gaps.

  It runs twice per frame: once before the fire is stepped and once after. }
procedure DrawBackdrop(Segment : Word);
var
  I : Integer;
  B : ^TBuf64;
begin
  B := Backdrop;
  for I := 0 to 29119 do
    if B^[I] <> 0 then
      Mem[Segment : $8700 + I] := B^[I];
end;

{ [transcribed] the bottom row is re-randomised every frame with -Random(2),
  i.e. 0 or 255 as a Byte -- which is what keeps the flame flickering. }
procedure SeedFire;
var
  I : Integer;
begin
  for I := 1 to FireW do
    Bottom[I] := Byte(-Random(2));
end;

{ [transcribed] the 4x scale-up out of the 80x98 buffer: four bytes written
  per source byte, twice per row, which fills 320x200 from 80x50 of source.
  The destination cursor is carried in ScaleOfs rather than passed. }
procedure Scale4x(V : Byte);
begin
  FillChar(Mem[VirtScrSeg : ScaleOfs], 4, V);
  FillChar(Mem[VirtScrSeg : ScaleOfs + ScrWidth], 4, V);
  Inc(ScaleOfs, 4);
end;

{ [transcribed] FUN_1118_08a2 -- copy with a vertical offset.

  The direction is the opposite of what an earlier reconstruction had, and of
  what docs/18 claimed. It BLANKS the first ScrollOfs bytes and then copies
  the source in behind them:

      fill  dest[0 .. ScrollOfs-1] with 0
      move  src[0 .. 63999-ScrollOfs] -> dest[ScrollOfs ..]

  So the image is pushed DOWN and a black band grows from the TOP. The fire
  sinks off the bottom of the screen rather than lifting off it. }
procedure CopyScreenScrolled(SrcSeg, DestSeg : Word; ScrollOfs : Integer);
begin
  if ScrollOfs >= 64000 then Exit;
  FillChar(Mem[DestSeg : 0], ScrollOfs, 0);
  Move(Mem[SrcSeg : 0], Mem[DestSeg : ScrollOfs], 64000 - ScrollOfs);
end;

procedure LineWipe;
var
  I : Integer;
begin
  for I := 1 to 16 do                      { fan from the bottom-left }
    DrawLine(0, 199 - I * 6, 320 - I * 2, 0, I, $A000);
  for I := 1 to 63 do                      { converge }
    DrawLine(0, 103 - I, 288 - I, 0, 99 + I, $A000);
  for I := 1 to 63 do                      { diverge }
    DrawLine(319, I, I, 199, 99 + I, $A000);
end;

{ ===========================================================================
  Scene 2 -- the whooshtext
  =========================================================================== }

const
  CellW      = 25;        { each board cell is a 25x25 animated sprite }
  CellH      = 25;
  CellBytes  = 627;       { $273 -- 625 pixels plus a 2-byte (25,25) header }
  CellFrames = 72;        { $48 animation frames, 45,000 bytes on disk }
  BoardRows  = 170;       { $AA -- the scrolling axis }
  BoardCols  = 16;        { $10 }
  TextRows   = 26;        { $1A visible rows }
  TextCols   = 14;        { $0E visible columns }
  PathFrames = 72;        { $48 rotation steps -- 5 degrees each, 360 total }
  AngleStep  = 5;
  CellPitch  = 15;        { grid spacing, in screen units, before rotation }
  CentreX    = 160;
  CentreY    = 100;

{ --------------------------------------------------------------------------
  Whoosh_BuildPaths (100f:0173)

  The two 60,000-byte tables are NOT shipped in the data -- they are GENERATED
  here from sin/cos. (An earlier note in this file claimed otherwise; it was
  wrong.) $EA00 = 59,904 bytes each = 72 angles x 26 rows x 16 cols x 2 bytes.

  Step 1  build 72-entry cos and sin tables at 5 degrees per step.
  Step 2  lay out a 28 x 16 grid of points centred on the middle cell:
              Px := (Row - 14) * 15
              Py := (Col -  8) * 15
  Step 3  for every angle, rotate every grid point about the origin and store
          the screen position:
              PathX[A, Row, Col] := Px*Cos + Py*Sin + 160
              PathY[A, Row, Col] := Py*Cos - Px*Sin + 100

  Note which axis is which: the BOARD ROW drives screen X and the BOARD COLUMN
  drives screen Y. The board is drawn transposed, which is why the letters are
  stored lying on their side in WhooshBoard (see gen/P6CELL.INC).
  -------------------------------------------------------------------------- }
procedure BuildPaths;
var
  Angle, Row, Col : Integer;
  Px, Py          : Integer;
  Cos, Sin        : array[0..PathFrames - 1] of Real;
begin
  for Angle := 0 to PathFrames - 1 do
  begin
    Cos[Angle] := System.Cos(Angle * AngleStep * Pi / 180);
    Sin[Angle] := System.Sin(Angle * AngleStep * Pi / 180);
  end;

  for Angle := 0 to PathFrames - 1 do
    for Row := 1 to TextRows do
      for Col := 1 to BoardCols do
      begin
        Px := (Row - 14) * CellPitch;
        Py := (Col -  8) * CellPitch;
        PathX^[Angle, Row, Col] := Round(Px * Cos[Angle] + Py * Sin[Angle]) + CentreX;
        PathY^[Angle, Row, Col] := Round(Py * Cos[Angle] - Px * Sin[Angle]) + CentreY;
      end;
end;

{ --------------------------------------------------------------------------
  Whoosh_Load (100f:03f8)

  ASSETS  NEUROSIS.DAT $1781E5, 46,280 bytes:
            assets/part006/whoosh_cell2.pal    256 B colour map for cell type 2
            assets/part006/whoosh_cell1.pal    256 B colour map for cell type 1
            assets/part006/palette.pal         768 B VGA palette
            assets/part006/whoosh_cells.bin 45,000 B = 72 frames of a 25x25
                                            cell sprite (72 * 625)

  So the 45,000-byte block is the CELL ANIMATION, not a path table. The same
  25x25 animation is drawn for every lit cell on the board; the two 256-byte
  tables recolour it, giving the letters one palette and the background dots
  another.

  The board itself is a 170 x 16 byte array, pre-filled with 2 (background),
  then rows 39..166 are overlaid from WhooshBoard -- 16 letter bands of 8 rows
  each spelling "ASPHYXIA RULZ". See gen/P6CELL.INC.
  -------------------------------------------------------------------------- }
procedure WhooshLoad;
var
  Band, Col, Row : Integer;
begin
  GetMem(Board, BoardRows * BoardCols);          { $AA0  }
  GetMem(PathY, PathFrames * TextRows * BoardCols * 2);   { $EA00 }
  GetMem(PathX, PathFrames * TextRows * BoardCols * 2);   { $EA00 }
  GetMem(Cells, CellFrames * CellW * CellH);     { 45,000 }

  LoadColourMap(2);                              { -> DS:$71F2 }
  LoadColourMap(1);                              { -> DS:$70F2 }

  for Row := 1 to BoardRows do
    for Col := 1 to BoardCols do
      Board^[Row, Col] := 2;                     { background dots everywhere }

  for Band := 1 to 16 do
    for Col := 1 to BoardCols do
      for Row := 1 to 8 do
        if WhooshBoard[Band, Col, Row] <> 0 then
          Board^[30 + Band * 8 + Row, Col] := WhooshBoard[Band, Col, Row];

  BlockRead(F, Palette, 768);
  SetPalette;
  BuildPaths;
  BlockRead(F, Cells^, 45000);
end;

{ --------------------------------------------------------------------------
  Whoosh_Run (100f:0590)

  The demo announces this one itself:
    "ISNT'T THIS GREAT?     ,THIS WHOOSHTEXT HAS 4000 DOTS!!!"

  Two working cells are rasterised each frame -- the current animation frame
  recoloured through each of the two colour maps -- and then every lit board
  cell in the visible window is blitted at its precomputed rotated position.
  -------------------------------------------------------------------------- }
procedure WhooshRun;
var
  Row, Col, Frame, Scroll, Cell : Integer;
begin
  Scroll := 1;
  Frame  := 0;
  repeat
    ClearVirtual;

    { rasterise the two 25x25 working cells from this frame of the animation }
    for Cell := 1 to 2 do
    begin
      Work[Cell].W := CellW;  Work[Cell].H := CellH;
      for Row := 1 to CellW * CellH do
        if Cells^[Frame * CellW * CellH + Row] <> 0 then
          Work[Cell].Pix[Row] := ColourMap[Cell, Cells^[Frame * CellW * CellH + Row]];
    end;

    for Row := 1 to TextRows do
      for Col := 1 to TextCols do
        if Board^[Row + Scroll, Col] <> 0 then
          DrawCell(Work[Board^[Row + Scroll, Col]],
                   PathX^[Frame, Row, Col],
                   PathY^[Frame, Row, Col]);

    if Scroll < 170 then Inc(Scroll, 2);
    if Scroll < 145 then
      CopyScreen(VirtScrSeg, $A000)        { still copying }
    else
      ClearScreen(VirtScrSeg, 0);          { switches to clearing near the end }

    Frame := (Frame + 1) mod PathFrames;
  until KeyPressed or (Scroll >= 146);
end;

{ ===========================================================================
  Scene 3 -- fire
  =========================================================================== }

{ FireW/FireH and the fire buffers are declared with the scaffolding above,
  because SeedFire and Scale4x need them. }

{ --------------------------------------------------------------------------
  Fire_Run (1118:08d3)

  The classic flame algorithm, and cheap: average four neighbours, decay by
  one, and write the result ONE ROW UP. Heat therefore rises by construction.

      A := (P[-1] + P[0] + P[1] + P[FireW]) shr 2;
      if A <> 0 then Dec(A);
      P[-FireW] := A;

  The bottom row is re-randomised every frame (-Random(2)), and the 80x98
  buffer is scaled 4x on the way to the screen -- four bytes written per source
  byte, twice per row, giving 320x200.

  After frame 100 the output scrolls upward as well, which lifts the fire off
  the bottom of the screen.
  -------------------------------------------------------------------------- }
procedure FireRun(Segment : Word);
var
  I, Frame : Integer;
  A : Byte;
begin
  DrawBackdrop(Segment);
  CopyScreen(Segment, $A000);
  SeedFire;
  Frame := 0;
  repeat
    if KeyPressed then Exit;

    for I := 1 to FireW do                 { new random bottom row }
      Bottom[I] := -Random(2);

    for I := 1 to FireW * FireH do
    begin
      A := (P[I - 1] + P[I] + P[I + 1] + P[I + FireW]) shr 2;
      if A <> 0 then Dec(A);
      P[I - FireW] := A;
      Scale4x(A);                          { 4 bytes, twice per row }
    end;

    DrawBackdrop(Segment);
    Inc(Frame);
    if Frame < 100 then
      CopyScreen(Segment, $A000)
    else
      CopyScreenScrolled(Segment, $A000, (Frame - 99) * 320);
  until Frame = 300;
end;

{ ===========================================================================
  Scene 4 -- the greetings scroller
  =========================================================================== }

const
  FontW     = 18;         { $12 bytes per glyph row }
  FontH     = 21;         { 378 / 18 }
  FontBytes = 378;        { $17A per character }
  LineBytes = 256;        { $100 -- one text line }
  VisRows   = 12;
  VisCols   = 20;         { $14 }
  LastLine  = 114;        { $72 }

{ --------------------------------------------------------------------------
  Credits_Step (11bb:0168)

  A vertical scroller in a 64K buffer 256 bytes wide: each frame draws one
  more glyph row and then scrolls the whole buffer up by 256 bytes (one row).

  The text is compiled into the executable as 12-character lines at 256-byte
  spacing:

    MY WORK IN / THIS DEMO IS / DEDICATED TO / $ADELE$ / MY LADYMOTH / - EZE
    GREETS FROM / EZE / GO TO :- / SPLIT / NEMESIS / CAZ / SCHMUCK / ...
  -------------------------------------------------------------------------- }
procedure CreditsStep(ScrollBuf : PBuf64);
var
  Row, Col : Integer;
begin
  if (Line < 100) and (GlyphRow <> 19) then
    for Row := 0 to 11 do
      for Col := 1 to VisCols do
        { Credits is the real thing -- 99 lines lifted out of DGROUP,
          gen/P6TEXT.INC }
        if Font[Glyph(Credits[Line][Row + 1]), GlyphRow, Col] <> 0 then
          ScrollBuf^[Row * 21 + Col] :=
            Font[Glyph(Credits[Line][Row + 1]), GlyphRow, Col];

  Inc(GlyphRow);
  if GlyphRow = 20 then
  begin
    GlyphRow := 1;
    Inc(Line);
  end;

  FillChar(ScrollBuf^[0], LineBytes, 0);   { blank the new top row }
  Move(ScrollBuf^[LineBytes], ScrollBuf^[0], 65256);  { scroll up one row }
end;

{ --------------------------------------------------------------------------
  Scene wrappers.
  -------------------------------------------------------------------------- }
procedure Scene1;
begin
  LineWipe;
end;

procedure Scene2;
begin
  WhooshLoad;
  WhooshRun;
end;

procedure Scene3;
begin
  FireRun(VirtScrSeg);
end;

procedure Scene4;
var
  Buf : PBuf64;
begin
  GetMem(Buf, 65000);
  CreditsStep(Buf);
  FreeMem(Buf, 65000);
end;

{ step the module volume down to zero, as every other part does }
procedure MusicFadeOut;
begin
  while GetVolume > 0 do
  begin
    SetVolume(GetVolume - 1);
    Delay(10);
  end;
  MusicStop;
end;

procedure RunPart6;
begin
  SetMode13h; VirtScrAlloc; MusicDetect;
  Scene1;  FlushKeys;                      { line wipe }
  Scene2;  FlushKeys;                      { whooshtext }
  Scene3;  FlushKeys;                      { fire }
  Scene4;  FlushKeys;                      { credits scroller }
  MusicFadeOut;
  VirtScrFree;
  Halt(0);
end;

end.

{ ===========================================================================
  LAYOUT
  * Whoosh_Load allocates a 2,720-byte character map (16 columns x 170 rows),
    fills it with the background value 2, then expands a 16x16 grid of 8-row
    glyphs into it.
  * The path tables index as [frame][row][col] with strides $340 / $20 / 2 --
    72 frames x 26 rows x 16 columns x 2 bytes = 59,904 of the 60,000.

  RESOLVED
  * The 45,000-byte disk block is NOT the source of the path tables. It is 72
    frames of a 25x25 cell sprite (72 * 625 = 45,000). The path tables are
    generated by Whoosh_BuildPaths (100f:0173) from sin/cos.
  * The two 256-byte reads are per-cell-type colour maps, moved to DS:$70F2
    and DS:$71F2 by 100f:00ac.
  * The whoosh text is "ASPHYXIA RULZ", compiled into DGROUP at DS:$000A as
    16 bands of 8x16 letter cells stored on their side. Bands 17..26 spell
    "0,000 DOTS" and are never loaded -- dead data.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
