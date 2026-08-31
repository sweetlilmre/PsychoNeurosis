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
  strings are still in the code segment, so they are still passed.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/27-part6-notes.md for the reading. }

{$S-}   { opens ENTER $946,0 with no stack check. }
{$G+}   { 186: the shifts take immediates }
{$N+}   { six-byte Reals through the x87 }

unit P6TILES;

{ NO VARIABLE ALIGNMENT. With it on, Turbo Pascal pads a variable up to an
  even address, which would move everything declared after the odd one. }
{$A-}
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

interface

procedure Scene2;

implementation

uses Crt, VGA;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

const
  Angles   = 72;                  { counts to $47 }
  GridRows = 26;                  { compares against $1A }
  GridCols = 16;                  { compares against $10 }
  TileSide = 25;                  { count to $19 }
  TilePix  = TileSide * TileSide; { 625 }
  TileRec  = TilePix + 2;         { 627 -- two bytes of width/height first }
  CellRows = 170;                 { counts to $AA }
  AnimSize = Angles * TilePix;    { 45000 }
  TabSize  = Angles * GridRows * GridCols * 2;   { 59904 }
  CellSize = CellRows * GridCols;
  DataOfs  = DAT_P6_CMAP2;   { where this scene's assets start }
  Fix      = 8192.0;              { the tables are 16.13 }
  Bias     = $2000;               { and biased by 8192 so they stay positive }

const
  { THE CLIP BOX: a five-pixel border all round. These are TYPED constants,
    not plain ones -- a plain const folds into the instruction that uses it,
    where the blit below reads all four from memory.

    THESE ARE NOT ADDRESSES TO COPY. The binary says MOV AX,[6]; writing that
    literally reads offset 6 of OUR data segment, which is not the clip bound
    and is what turned the screen to rubbish. Same for the row table at
    $96DA, which is the VGA unit's YOfs. }
  ClipLeft   : Integer = 5;
  ClipRight  : Integer = 315;
  ClipTop    : Integer = 5;
  ClipBottom : Integer = 195;

{ ALL TWENTY-SIX BANDS. P6SHAPE.INC held the same table read from the same
 with a shorter length -- sixteen bands, 2,048 bytes -- and its own
  generator no longer exists. Bands 17..26 are never drawn, exactly as part
  003's unused shape slots are never drawn, and leaving them out moved every
  typed constant declared after them: CellShape ended at $080A where the
  original's ends at $0D0A, and CreditText sits at $0D8A.

  THE 128-BYTE GAP AFTER THIS TABLE IS NOT A 27TH BAND, and it is not an unread
  constant either. Both were tested. A 27th band overshoots: it moves every
  variable in the part from four bytes LOW to 124 HIGH, so the real deficit is
  four bytes. And declaring 128 unreferenced bytes as a constant of their own
  changes the load image by exactly nothing, because **Turbo Pascal smart-links
  away a typed constant no code mentions.** }
{$I gen/P6CELL.INC}    { const CellShape : array[1..27,1..16,1..8] of Byte }

type
  TCells  = array[1..CellRows, 1..GridCols] of Byte;
  TCel    = array[0..255] of Byte;
  TCoord  = array[0..Angles - 1, 1..GridRows, 1..GridCols] of Integer;
  TAnim   = array[0..Angles - 1, 0..TilePix - 1] of Byte;
  TTile   = record W, H : Byte; Pix : array[0..TilePix - 1] of Byte end;
  { TWO-DIMENSIONAL, entry by channel, so the channel is a constant subscript
    the compiler folds rather than an addition at run time. Part 004's scene
    palette and part 005's are the same shape, which makes three. Same 768
    bytes either way. }
  TPal768 = array[0..255, 0..2] of Byte;
  TPoint  = record X, Y : Integer end;

var
  Cells : ^TCells;
  Cels  : array[1..2] of TCel;
  YTab  : ^TCoord;
  XTab  : ^TCoord;
  Anim  : ^TAnim;
  F     : file;

{ --------------------------------------------------------------------------
  the clipped transparent sprite blit. HAND ASSEMBLER, verbatim,
  and SHARED SOURCE: the routine is src/asm/BLITCLIP.INC, because part 001
  scene 4 compiles the same text. The marker names the routine, which is how it
  stays byte-checked with its header inside the include.
  -------------------------------------------------------------------------- }
{$I BLITCLIP.INC}

{ --------------------------------------------------------------------------
  read one 256-byte colour map.

  `Name` IS NEVER USED. The routine copies it into a 256-byte local and then
  reads from the file the caller already opened. Transcribed because it is
  what the binary does; the two names it is called with are in the code
  segment and are the only trace of whatever the .cel files once were.
  -------------------------------------------------------------------------- }
{ the two of them, in this order. }
procedure LoadCels;

  { NESTED INSIDE LoadCels, not a routine of its own. A nested procedure is
    called with a STATIC LINK pushed after its arguments, which takes the first
    frame slot and moves both parameters up two bytes -- so making it top-level
    changes every reference in it.

    Declared at unit level it was RET 6 and the parameters were two bytes low. }
  procedure LoadCel(Name : String; Slot : Integer);
  var
    { 514 bytes: the String parameter's own 256-byte copy, Buf's 256, and two
      bytes below them that nothing reads. }
    Buf    : TCel;
    Unread : Integer;             { never referenced }
  begin
    BlockRead(F, Buf, SizeOf(Buf));
    Cels[Slot] := Buf;
  end;

begin
  LoadCel('p5.cel', 2);
  LoadCel('p8.cel', 1);
end;

{ degrees to radians. }
function Rad(D : Real) : Real;
begin
  Rad := D * Pi / 180.0;
end;

{ --------------------------------------------------------------------------
  every position the grid will ever be drawn at.

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
  SinT    : array[0..Angles - 1] of LongInt;
  CosT    : array[0..Angles - 1] of LongInt;
  G       : array[1..28, 1..GridCols] of TPoint;
begin
  for A := 0 to Angles - 1 do
    CosT[A] := Round(Cos(Rad(A * 5)) * Fix) + Bias;
  for A := 0 to Angles - 1 do
    SinT[A] := Round(Sin(Rad(A * 5)) * Fix) + Bias;

  for I := 1 to 28 do
    for J := 1 to GridCols do
    begin
      G[I, J].X := (I - 14) * 15;
      G[I, J].Y := (J - 8) * 15;
    end;

  for A := 0 to Angles - 1 do
    for I := 1 to GridRows do
      for J := 1 to GridCols do
      begin
        { The X*Sin term is SUBTRACTED FROM the Y*Cos term, that way round.
          Getting it backwards mirrors the mesh about the wrong axis. }
        { THE TRIG TERM IS WRITTEN FIRST AND THE GRID LOOKUP SECOND, and the
          order is not free: Turbo Pascal evaluates the RIGHT operand first and
          parks it, so which term is named second decides which is emitted
          first. Multiplication is commutative, so this is spelling rather than
          arithmetic -- but it is two bytes at each of eight sites. }
        YTab^[A, I, J] :=
          ((CosT[A] - Bias) * G[I, J].Y) div Bias -
          ((SinT[A] - Bias) * G[I, J].X) div Bias + 100;
        { AND THE COSINE TERM IS WRITTEN FIRST HERE, the other way round from
          YTab above -- same rule, opposite spelling. Ten bytes across five
          operand pairs. }
        XTab^[A, I, J] :=
          ((CosT[A] - Bias) * G[I, J].X) div Bias +
          ((SinT[A] - Bias) * G[I, J].Y) div Bias + 160;
      end;
end;

{ --------------------------------------------------------------------------
  the assets.

  ASSETS  NEUROSIS.DAT $001781E5:
            256 bytes    colour map 2 ("p5.cel")
            256 bytes    colour map 1 ("p8.cel")
            768 bytes    the palette
            45,000 bytes 72 frames of a 25 x 25 animation
  -------------------------------------------------------------------------- }
procedure Setup;
var
  { 902 BYTES, OF WHICH THE 128 NEAREST BP ARE NEVER READ. It is a file record
    the routine declares and does not open -- the same shape part 005's and
    part 006's other scenes have -- and it must come FIRST, because first
    declared is nearest BP and everything below it depends on that.

    A file record is what fits, and P6WHOOSH's Load has the same thing in the same
    position, also unreferenced. }
  Unread  : file;                 { never referenced }
  { I, THEN J, THEN A. Declaration order fixes which counter gets which slot,
    and A and J the other way round costs two bytes of displacement on every
    reference in the three-deep shape loop below. }
  I, J, A : Integer;
  Pal     : TPal768;
begin
  GetMem(Cells, CellSize);
  GetMem(YTab, TabSize);
  GetMem(XTab, TabSize);
  GetMem(Anim, AnimSize);
  LoadCels;

  { every cell starts as map 2. }
  for I := 1 to CellRows do
    for J := 1 to GridCols do
      Cells^[I, J] := 2;

  { rows 39..166 are overwritten from the compiled-in 16 x 16 x 8 table,
    transposed. Where it is zero the cell keeps its 2. The table is initialised
    data and lives in gen/P6SHAPE.INC. }
  for A := 1 to GridCols do
    for I := 1 to GridCols do
      for J := 1 to 8 do
        if CellShape[A, I, J] <> 0 then
          { THE ORDER IS NOT COSMETIC, AND IT IS THIS WAY ROUND -- the sum
            reads `(J + 30) + A * 8`, with the parentheses. Turbo Pascal
            evaluates the right operand first and parks it, so the parked term
            is the one written second. Dropping the parentheses is worse again:
            `A * 8 + J + 30` parses left to right, every right operand is
            simple, and the whole sum stays in one register. }
          Cells^[(J + 30) + A * 8, I] := CellShape[A, I, J];

  BlockRead(F, Pal, SizeOf(Pal));
  for I := 0 to 255 do
    SetRGB(I, Pal[I, 0], Pal[I, 1], Pal[I, 2]);

  BuildTables;
  BlockRead(F, Anim^, AnimSize);
end;

{ --------------------------------------------------------------------------
  the frame loop.

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
  I              : Integer;
  J              : Integer;
  { ELEVEN BYTES BETWEEN J AND Pix, and they have to be declared. Pix sitting
    at an ODD offset is the tell: a word does not land there unless an odd
    number of bytes was declared before it. }
  Unread         : array[1..11] of Byte;   { never read -- eleven, which the
                                             note above works out. Ten of them
                                             moves everything below by a byte. }
  Pix            : Word;
  Src            : Word;
  Dst            : Word;
  Tile           : array[1..2] of TTile;
  AnimSeg        : Word;
  DGroup         : Word;
  CelsOfs        : Word;
  TileSeg        : Word;
  TileOfs        : Word;
  ScrollY        : Integer;
  Frame          : Integer;
begin
  for I := 1 to 2 do
  begin
    Tile[I].W := TileSide;
    Tile[I].H := TileSide;
  end;
  ScrollY := 1;
  Frame   := 0;
  { CRT'S DirectVideo, TURNED OFF. Crt writes screen memory directly when this
    is true and goes through the slow path when it is false; the scene wants
    the slow path.

    Turning it off matters in mode 13h: a Write that goes straight to text
    memory lands in the middle of the graphics screen. }
  DirectVideo := False;

  AnimSeg := Seg(Anim^);
  DGroup  := DSeg;
  CelsOfs := Ofs(Cels);
  TileSeg := SSeg;
  TileOfs := Ofs(Tile);

  repeat
    ClearScreen(VirtScrSeg, 0);
    FillChar(Tile[1].Pix, TilePix, 0);
    FillChar(Tile[2].Pix, TilePix, 0);

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
      { the two bases, worked out the way the original does it:
        by repeated addition rather than a multiply. }
      asm
        PUSH DS
        MOV  CX, TileSeg
        MOV  ES, CX            { ES:DI is the tile being built    }
        XOR  DI, DI
        MOV  CX, I
        DEC  CX
        JZ   @@AtTile
      @@TileStep:
        ADD  DI, 273h          { 627 bytes per tile record        }
        DEC  CX
        JNZ  @@TileStep
      @@AtTile:
        ADD  DI, 2             { past the width/height bytes      }
        ADD  DI, TileOfs

        XOR  SI, SI
        MOV  CX, I
        DEC  CX
        JZ   @@AtCel
      @@CelStep:
        ADD  SI, 100h          { 256 bytes per colour map         }
        DEC  CX
        JNZ  @@CelStep
      @@AtCel:
        MOV  Src, SI
        MOV  SI, CelsOfs
        ADD  Src, SI           { -> Cels[I]                       }

        XOR  SI, SI
        MOV  CX, Frame
        CMP  CX, 0
        JZ   @@AtFrame
      @@FrameStep:
        ADD  SI, 271h          { 625 bytes per animation frame    }
        DEC  CX
        JNZ  @@FrameStep
      @@AtFrame:
        MOV  Dst, SI           { -> this frame                    }

        XOR  SI, SI            { the running pixel index          }
        XOR  DX, DX            { DX counts the 25 DOWN            }
      @@Outer:
        XOR  BX, BX            { BX counts the 25 ACROSS          }
      @@Inner:
        MOV  DS, AnimSeg
        INC  SI
        PUSH SI
        MOV  AX, SI
        MOV  Pix, AX
        ADD  SI, Dst           { + the frame's base               }
        XOR  AX, AX
        MOV  AL, [SI]          { the animation byte               }
        CMP  AL, 0
        JZ   @@Next            { 0 stays transparent              }
        MOV  DS, DGroup
        XOR  SI, SI
        ADD  SI, AX
        ADD  SI, Src           { -> Cels[I][B]                    }
        MOV  AL, [SI]
        PUSH DI
        ADD  DI, Pix
        STOSB
        POP  DI
      @@Next:
        POP  SI
        INC  BX
        CMP  BX, 19h
        JNZ  @@Inner
        INC  DX
        CMP  DX, 19h
        JNZ  @@Outer
        POP  DS
      end;
    end;

    { the visible band of the cell grid. }
    for I := 1 to GridRows do
      for J := 1 to 14 do
        if Cells^[I + ScrollY, J + 1] <> 0 then
          Blit(@Tile[Cells^[I + ScrollY, J + 1]],
               XTab^[Frame, I, J], YTab^[Frame, I, J], VirtScrSeg);

    if ScrollY < CellRows then
      ScrollY := ScrollY + 2;
    if ScrollY < $91 then
      CopyScreen(VirtScrSeg, VGASeg)
    else
      ClearScreen(VGASeg, 0);

    Frame := (Frame + 1) mod Angles;
  { THIS IS AN `Exit`, NOT AN `or` IN THE `until`. TP7's `or` is short-circuit,
    so `until A or B` tests A and jumps straight out on true -- one branch.
    `if A then Exit` has to jump over the Exit's own jump, which is two. The
    original has two, and no spelling of the `or` produces the longer form.

    IT IS AN Exit, AND THE ARGUMENT THAT SAID OTHERWISE WAS THE WRONG TEST.
    That argument ran: both jumps land on 07c6, whereas in P1TITLE's ShowWord the
    two went to different places, so convergence proves this is a plain
    `until A or B`. Convergence proves nothing here. This `until` is the LAST
    statement of the routine, so `Exit` and falling out of the loop have the
    SAME destination by construction -- the leave/ret at 07c6 -- and both
    readings predict exactly what was measured. ShowWord's divergence was
    positive evidence FOR an Exit; convergence is not evidence against one.

    WHAT DOES DISTINGUISH THEM IS THE SHAPE, and it always did. TP7's `or` is
    short-circuit by default, so `until A or B` tests A and jumps STRAIGHT out
    on true -- one JNE. `if A then Exit` has to jump over the Exit's own JMP,
    which is JZ +2 / JMP, four bytes. The original has four bytes. Three
    earlier attempts looked for a spelling of the `or` that produced the longer
    form; there is none, because the longer form is not an `or`. }
    if KeyPressed then Exit;
  until ScrollY >= $92;
end;

{ the scene. }
procedure Scene2;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  Setup;
  Run;
  Close(F);
  FreeMem(Cells, CellSize);
  FreeMem(YTab, TabSize);
  FreeMem(XTab, TabSize);
  FreeMem(Anim, AnimSize);
end;

{ the unit's initialisation is empty. }
begin
end.
