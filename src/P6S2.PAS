{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.006 scene 2, segment 100f.

  A grid of 25 x 25 animated tiles, laid out on a rotating rectangular mesh
  and scrolled up the screen. Every tile plays the same 72-frame animation,
  but which of two colour maps it uses comes out of a cell grid, and where it
  lands comes out of a table of 72 pre-rotated positions.

  ALL THE MOTION IS PRECOMPUTED. `BuildTables` turns 72 angles into 72 x 26 x
  16 pairs of screen coordinates before anything is drawn, so the frame loop
  itself has no arithmetic in it beyond a table index.

  THE TWO .CEL FILENAMES ARE DEAD. `LoadCel` takes a name -- 'p5.cel' and
  'p8.cel' -- copies it into a local, and never looks at it again: the 256
  bytes come from the NEUROSIS.DAT handle the caller already has open. The
  strings are still in the code segment at 100f:00fc and 100f:0103.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/27-part6-notes.md for the reading.

  ADDRESS MAP
    Blit          100f:0000     LoadCels      100f:010a
    LoadCel       100f:00ac     Rad           100f:0133
    BuildTables   100f:0173     Setup         100f:03f8
    Run           100f:0590     Scene2        100f:07d5

  DGROUP
    DS:$0002/$0004  the horizontal clip bounds   -- initialised data
    DS:$0006/$0008  the vertical clip bounds
    DS:$70ee  the cell grid, 170 x 16      -- GetMem 2720
    DS:$70f2  Cels : array[1..2] of 256 bytes, two colour maps
    DS:$72f2  the Y table, 72 x 26 x 16 words   -- GetMem 59904
    DS:$72f6  the X table, likewise            -- GetMem 59904
    DS:$72fa  the animation, 72 frames of 25 x 25 -- GetMem 45000
    DS:$72fe  the file
    DS:$96d8  VirtScrSeg      DS:$96da  the row table
  =========================================================================== }

{$S-}   { 100f:0173 opens ENTER $946,0 with no stack check. }
{$G+}   { 186: the shifts take immediates }
{$N+}   { six-byte Reals through the x87 }

unit P6S2;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

interface

procedure Scene2;

implementation

uses Crt, VGA;

const
  Angles   = 72;                  { 100f:01c1 counts to $47 }
  GridRows = 26;                  { 100f:03e4 compares against $1A }
  GridCols = 16;                  { 100f:03db compares against $10 }
  TileSide = 25;                  { 100f:069f and 100f:06a5 count to $19 }
  TilePix  = TileSide * TileSide; { 625 }
  TileRec  = TilePix + 2;         { 627 -- two bytes of width/height first }
  CellRows = 170;                 { 100f:0472 counts to $AA }
  AnimSize = Angles * TilePix;    { 45000 -- 100f:0429 }
  TabSize  = Angles * GridRows * GridCols * 2;   { 59904 -- 100f:040b }
  CellSize = CellRows * GridCols; { 2720 -- 100f:03fc }
  DataOfs  = $001781E5;           { 100f:07f8 pushes $0017 then $81E5 }
  Fix      = 8192.0;              { CS:$016f -- the tables are 16.13 }
  Bias     = $2000;               { and biased by 8192 so they stay positive }

const
  { DS:$0002..$0008, INITIALISED DATA read straight out of the image: a five
    pixel border all round. Blit reads all four directly, which is why they
    are typed constants -- a plain const would fold into the instruction.

    THESE ARE NOT ADDRESSES TO COPY. The binary says MOV AX,[6]; writing that
    literally reads offset 6 of OUR data segment, which is not the clip bound
    and is what turned the screen to rubbish. Same for the row table at
    $96DA, which is the VGA unit's YOfs. }
  ClipLeft   : Integer = 5;       { DS:$0002 }
  ClipRight  : Integer = 315;     { DS:$0004 }
  ClipTop    : Integer = 5;       { DS:$0006 }
  ClipBottom : Integer = 195;     { DS:$0008 }

{ ALL TWENTY-SIX BANDS. P6SHAPE.INC held the same table read from the same
  DS:$000A with a shorter length -- sixteen bands, 2,048 bytes -- and its own
  generator no longer exists. Bands 17..26 are never drawn, exactly as part
  003's unused shape slots are never drawn, and leaving them out moved every
  typed constant declared after them: CellShape ended at $080A where the
  original's ends at $0D0A, and CreditText sits at $0D8A. }
{$I gen/P6CELL.INC}    { const CellShape : array[1..26,1..16,1..8] of Byte }

type
  TCells  = array[1..CellRows, 1..GridCols] of Byte;
  TCel    = array[0..255] of Byte;
  TCoord  = array[0..Angles - 1, 1..GridRows, 1..GridCols] of Integer;
  TAnim   = array[0..Angles - 1, 0..TilePix - 1] of Byte;
  TTile   = record W, H : Byte; Pix : array[0..TilePix - 1] of Byte end;
  TPal768 = array[0..767] of Byte;
  TPoint  = record X, Y : Integer end;

var
  Cells : ^TCells;                { DS:$70ee }
  Cels  : array[1..2] of TCel;    { DS:$70f2 }
  YTab  : ^TCoord;                { DS:$72f2 }
  XTab  : ^TCoord;                { DS:$72f6 }
  Anim  : ^TAnim;                 { DS:$72fa }
  F     : file;                   { DS:$72fe }

{ --------------------------------------------------------------------------
  100f:0000 -- the clipped transparent sprite blit. HAND ASSEMBLER, verbatim,
  and SHARED SOURCE: the routine is src/asm/BLITCLIP.INC, because part 001
  scene 4 compiles the same text at 1107:0199. The marker names the routine,
  which is how it stays byte-checked with its header inside the include.
  -------------------------------------------------------------------------- }
{ @asm 006 100f:0000 +170 Blit }
{$I BLITCLIP.INC}

{ --------------------------------------------------------------------------
  100f:00ac -- read one 256-byte colour map.

  `Name` IS NEVER USED. The routine copies it into a 256-byte local and then
  reads from the file the caller already opened. Transcribed because it is
  what the binary does; the two names it is called with are in the code
  segment and are the only trace of whatever the .cel files once were.
  -------------------------------------------------------------------------- }
procedure LoadCel(Name : String; Slot : Integer);
var Buf : TCel;                   { [BP-$200] }
begin
  BlockRead(F, Buf, SizeOf(Buf));               { 100f:00d9 }
  Cels[Slot] := Buf;                            { 100f:00f3 }
end;

{ 100f:010a -- the two of them, in this order. }
procedure LoadCels;
begin
  LoadCel('p5.cel', 2);                          { 100f:0115 }
  LoadCel('p8.cel', 1);                          { 100f:0120 }
end;

{ 100f:0133 -- degrees to radians. CS:$0125 is the ten-byte Pi and CS:$012f
  the single 180.0. }
function Rad(D : Real) : Real;
begin
  Rad := D * Pi / 180.0;
end;

{ --------------------------------------------------------------------------
  100f:0173 -- every position the grid will ever be drawn at.

  The grid is 28 x 16 points on a 15-pixel pitch, centred by subtracting 14
  and 8. For each of 72 angles five degrees apart it is rotated and the
  results stored as plain screen coordinates -- 72 x 26 x 16 of them, twice.
  The sine and cosine are held as 16.13 fixed point biased by 8192, so the
  rotate is an integer multiply and a shift.

  Note the grid is built 1..28 but only 1..26 of it is ever rotated or drawn.
  -------------------------------------------------------------------------- }
procedure BuildTables;
var
  A, I, J : Integer;
  SinT    : array[0..Angles - 1] of LongInt;    { [BP-$126] }
  CosT    : array[0..Angles - 1] of LongInt;    { [BP-$246] }
  G       : array[1..28, 1..GridCols] of TPoint;{ [BP-$98a] }
begin
  for A := 0 to Angles - 1 do                    { 100f:0177 }
    CosT[A] := Round(Cos(Rad(A * 5)) * Fix) + Bias;
  for A := 0 to Angles - 1 do                    { 100f:01c7 }
    SinT[A] := Round(Sin(Rad(A * 5)) * Fix) + Bias;

  for I := 1 to 28 do                            { 100f:0217 }
    for J := 1 to GridCols do
    begin
      G[I, J].X := (I - 14) * 15;                { 100f:0244 }
      G[I, J].Y := (J - 8) * 15;                 { 100f:0261 }
    end;

  for A := 0 to Angles - 1 do                    { 100f:0271 }
    for I := 1 to GridRows do
      for J := 1 to GridCols do
      begin
        { 100f:02c9 pushes the X*Sin term and 100f:0307 SUBTRACTS it from the
          Y*Cos term -- that way round. Getting it backwards mirrors the mesh
          about the wrong axis. }
        YTab^[A, I, J] :=                        { 100f:0331 }
          (G[I, J].Y * (CosT[A] - Bias)) div Bias -
          (G[I, J].X * (SinT[A] - Bias)) div Bias + 100;
        XTab^[A, I, J] :=                        { 100f:03d7 }
          (G[I, J].Y * (SinT[A] - Bias)) div Bias +
          (G[I, J].X * (CosT[A] - Bias)) div Bias + 160;
      end;
end;

{ --------------------------------------------------------------------------
  100f:03f8 -- the assets.

  ASSETS  NEUROSIS.DAT $001781E5:
            256 bytes    colour map 2 ("p5.cel")
            256 bytes    colour map 1 ("p8.cel")
            768 bytes    the palette
            45,000 bytes 72 frames of a 25 x 25 animation
  -------------------------------------------------------------------------- }
procedure Setup;
var
  Pal  : TPal768;                 { [BP-$386] }
  A, I, J : Integer;
begin
  GetMem(Cells, CellSize);                       { 100f:03ff }
  GetMem(YTab, TabSize);                         { 100f:040e }
  GetMem(XTab, TabSize);                         { 100f:041d }
  GetMem(Anim, AnimSize);                        { 100f:042c }
  LoadCels;                                      { 100f:0438 }

  { 100f:043b -- every cell starts as map 2. }
  for I := 1 to CellRows do
    for J := 1 to GridCols do
      Cells^[I, J] := 2;

  { 100f:047a -- and rows 39..166 are overwritten from the compiled-in
    16 x 16 x 8 table at DS:$000A, transposed. Where it is zero the cell keeps
    its 2. The table is initialised data and is in gen/P6SHAPE.INC; an earlier
    pass reached it with `absolute $164E:$000A`, which is the ORIGINAL's data
    segment and reads rubbish in our build. }
  for A := 1 to GridCols do
    for I := 1 to GridCols do
      for J := 1 to 8 do
        if CellShape[A, I, J] <> 0 then
          Cells^[A * 8 + J + 30, I] := CellShape[A, I, J];

  BlockRead(F, Pal, SizeOf(Pal));                { 100f:0524 }
  for I := 0 to 255 do                           { 100f:0529 }
    SetRGB(I, Pal[I * 3], Pal[I * 3 + 1], Pal[I * 3 + 2]);

  BuildTables;                                   { 100f:0574 }
  BlockRead(F, Anim^, AnimSize);                 { 100f:0589 }
end;

{ --------------------------------------------------------------------------
  100f:0590 -- the frame loop.

  Two 25 x 25 tiles are rebuilt every frame: the animation frame supplies an
  index per pixel and the cell's colour map turns it into a colour, with 0
  left transparent. Then the visible band of the cell grid is walked and every
  non-zero cell blits its tile at the precomputed position.

  The band scrolls up two rows a frame. Past row 145 the screen is cleared
  instead of blitted, and at 146 the scene ends -- so the last few frames run
  black on purpose.
  -------------------------------------------------------------------------- }
procedure Run;
var
  I              : Integer;   { [BP-$2] }
  J              : Integer;   { [BP-$4] }
  Pix            : Word;   { [BP-$11] }
  Src            : Word;   { [BP-$13] }
  Dst            : Word;   { [BP-$15] }
  Tile           : array[1..2] of TTile;   { [BP-$4FB] }
  AnimSeg        : Word;   { [BP-$4FD] }
  DGroup         : Word;   { [BP-$4FF] }
  CelsOfs        : Word;   { [BP-$501] }
  TileSeg        : Word;   { [BP-$503] }
  TileOfs        : Word;   { [BP-$505] }
  ScrollY        : Integer;   { [BP-$507] }
  Frame          : Integer;   { [BP-$509] }
begin
  for I := 1 to 2 do
  begin
    Tile[I].W := TileSide;                       { 100f:05a3 }
    Tile[I].H := TileSide;                       { 100f:05ad }
  end;
  ScrollY := 1;                                  { 100f:05b8 }
  Frame   := 0;                                  { 100f:05be }

  AnimSeg := Seg(Anim^);                         { 100f:05c9 }
  DGroup  := DSeg;                               { 100f:05d3 }
  CelsOfs := Ofs(Cels);                          { 100f:05d9 }
  TileSeg := SSeg;                               { 100f:05e0 }
  TileOfs := Ofs(Tile);                          { 100f:05e6 }

  repeat
    ClearScreen(VirtScrSeg, 0);                  { 100f:05f4 }
    FillChar(Tile[1].Pix, TilePix, 0);           { 100f:0604 }
    FillChar(Tile[2].Pix, TilePix, 0);           { 100f:0614 }

    for I := 1 to 2 do
    begin
      { ------------------------------------------------------------------
        EQUIVALENT PASCAL, for reference -- the assembler is what runs:

            for K := 1 to 625 do
            begin
              B := Anim^[Frame, K];
              if B <> 0 then Tile[I].Pix[K] := Cels[I][B];
            end;

        It cannot be written that way: DS is swung between the animation and
        DGROUP once per pixel, SI is the running index into both, and BOTH
        loop counters live in registers -- BX across and DX down. An earlier
        pass used DX for the frame base as well as the counter, which is why
        the screen came out as rubbish.
        ------------------------------------------------------------------ }
      { 100f:064f -- the two bases, worked out the way the original does it:
        by repeated addition rather than a multiply. }
      asm
        PUSH DS                { 100f:0623                                   }
        MOV  CX, TileSeg       { 100f:0624                                   }
        MOV  ES, CX            { 100f:0628  ES:DI is the tile being built    }
        XOR  DI, DI            { 100f:062a                                   }
        MOV  CX, I             { 100f:062c                                   }
        DEC  CX                { 100f:062f                                   }
        JZ   @@AtTile          { 100f:0630                                   }
      @@TileStep:
        ADD  DI, 273h          { 100f:0632  627 bytes per tile record        }
        DEC  CX                { 100f:0636                                   }
        JNZ  @@TileStep        { 100f:0637                                   }
      @@AtTile:
        ADD  DI, 2             { 100f:0639  past the width/height bytes      }
        ADD  DI, TileOfs       { 100f:063c                                   }

        XOR  SI, SI            { 100f:0640                                   }
        MOV  CX, I             { 100f:0642                                   }
        DEC  CX                { 100f:0645                                   }
        JZ   @@AtCel           { 100f:0646                                   }
      @@CelStep:
        ADD  SI, 100h          { 100f:0648  256 bytes per colour map         }
        DEC  CX                { 100f:064c                                   }
        JNZ  @@CelStep         { 100f:064d                                   }
      @@AtCel:
        MOV  Src, SI           { 100f:064f                                   }
        MOV  SI, CelsOfs       { 100f:0652                                   }
        ADD  Src, SI           { 100f:0656  -> Cels[I]                       }

        XOR  SI, SI            { 100f:0659                                   }
        MOV  CX, Frame         { 100f:065b                                   }
        CMP  CX, 0             { 100f:065f                                   }
        JZ   @@AtFrame         { 100f:0662                                   }
      @@FrameStep:
        ADD  SI, 271h          { 100f:0664  625 bytes per animation frame    }
        DEC  CX                { 100f:0668                                   }
        JNZ  @@FrameStep       { 100f:0669                                   }
      @@AtFrame:
        MOV  Dst, SI           { 100f:066b  -> this frame                    }

        XOR  SI, SI            { 100f:066e  the running pixel index          }
        XOR  DX, DX            { 100f:0670  DX counts the 25 DOWN            }
      @@Outer:
        XOR  BX, BX            { 100f:0672  BX counts the 25 ACROSS          }
      @@Inner:
        MOV  DS, AnimSeg       { 100f:0674                                   }
        INC  SI                { 100f:0678                                   }
        PUSH SI                { 100f:0679                                   }
        MOV  AX, SI            { 100f:067a                                   }
        MOV  Pix, AX           { 100f:067c                                   }
        ADD  SI, Dst           { 100f:067f  + the frame's base               }
        XOR  AX, AX            { 100f:0682                                   }
        MOV  AL, [SI]          { 100f:0684  the animation byte               }
        CMP  AL, 0             { 100f:0686                                   }
        JZ   @@Next            { 100f:0688  0 stays transparent              }
        MOV  DS, DGroup        { 100f:068a                                   }
        XOR  SI, SI            { 100f:068e                                   }
        ADD  SI, AX            { 100f:0690                                   }
        ADD  SI, Src           { 100f:0692  -> Cels[I][B]                    }
        MOV  AL, [SI]          { 100f:0695                                   }
        PUSH DI                { 100f:0697                                   }
        ADD  DI, Pix           { 100f:0698                                   }
        STOSB                  { 100f:069b                                   }
        POP  DI                { 100f:069c                                   }
      @@Next:
        POP  SI                { 100f:069d                                   }
        INC  BX                { 100f:069e                                   }
        CMP  BX, 19h           { 100f:069f                                   }
        JNZ  @@Inner           { 100f:06a2                                   }
        INC  DX                { 100f:06a4                                   }
        CMP  DX, 19h           { 100f:06a5                                   }
        JNZ  @@Outer           { 100f:06a8                                   }
        POP  DS                { 100f:06aa                                   }
      end;
    end;

    { 100f:06b4 -- the visible band of the cell grid. }
    for I := 1 to GridRows do
      for J := 1 to 14 do
        if Cells^[I + ScrollY, J + 1] <> 0 then
          Blit(@Tile[Cells^[I + ScrollY, J + 1]],
               XTab^[Frame, I, J], YTab^[Frame, I, J], VirtScrSeg);

    if ScrollY < CellRows then                   { 100f:076e }
      ScrollY := ScrollY + 2;                    { 100f:0776 }
    if ScrollY < $91 then                        { 100f:0780 }
      CopyScreen(VirtScrSeg, VGASeg)             { 100f:078f }
    else
      ClearScreen(VGASeg, 0);                    { 100f:079b }

    Frame := (Frame + 1) mod Angles;             { 100f:07a0 }
  until KeyPressed or (ScrollY >= $92);          { 100f:07b0, 100f:07bb }
end;

{ 100f:07d5 -- the scene. }
procedure Scene2;
begin
  Assign(F, 'neurosis.dat');                     { 100f:07e2 }
  Reset(F, 1);
  Seek(F, DataOfs);
  Setup;                                         { 100f:0802 }
  Run;                                           { 100f:0805 }
  Close(F);                                      { 100f:080d }
  FreeMem(Cells, CellSize);                      { 100f:081d }
  FreeMem(YTab, TabSize);                        { 100f:082d }
  FreeMem(XTab, TabSize);                        { 100f:083d }
  FreeMem(Anim, AnimSize);                       { 100f:084d }
end;

{ 100f:0854 -- the unit's initialisation is empty. }
begin
end.
