{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.006 scene 1, segment 1095.

  The "whooshtext". Two lines of text are turned into a cloud of dots that
  stream in along sixteen curved paths and settle into the letters.

  HOW IT WORKS. Sixteen paths are walked ONCE, up front, by a Bresenham line
  in six-byte Reals, and the screen offset of each step is recorded -- but not
  every step. A running total is advanced by a threshold that starts at 1.3
  and DROPS BY 0.005 each time a point is recorded, so the recorded points
  start close together and spread further and further apart. That is the whole
  acceleration of the whoosh, and it is why the paths are built with floating
  point when everything else in the demo is integers.

  A glyph is 16 x 16 and is unpacked into a 3200-byte table as sixteen
  200-byte lanes, one per glyph row, transposed and mirrored. The renderer
  then walks all 3200 path/dot pairs, plots wherever the path entry is not
  zero, and shifts each lane along by one -- so each row of the letter is a
  stream of dots travelling down its own path.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/27-part6-notes.md for the reading.

  DGROUP
 the path table, 16 x 200 words   -- GetMem 6400
 the dot table,  16 x 200 bytes   -- GetMem 3200
 the font, 59 glyphs of 16 x 16   -- GetMem 15104
 the file
  =========================================================================== }

{$S-}   { opens ENTER $386,0 with no stack check. }
{$N+}   { six-byte Reals through the x87, which is what the binary uses }

unit P6WHOOSH;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

{ 286 instructions are permitted -- `ENTER`, which every framed routine here
  opens with, is one of them. }
{$G+}

interface

procedure Scene1;

implementation

uses Crt, VGA;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

const
  Lanes    = 16;                  { counts to $10 }
  LaneLen  = 200;                 { compares BX against $C9 }
  PathSize = Lanes * LaneLen * 2;
  DotSize  = Lanes * LaneLen;
  FontSize = $3B00;               { 15104 -- 59 glyphs of 256 }
  FirstCh  = 32;                  { the font starts at space }
  DataOfs  = DAT_P6_WHOOSHFN;   { where this scene's assets start }

  { read out of the code segment. }
  Two      = 2.0;
  One      = 1.0;
  Decay    = 0.005;
  Thresh0  = 1.3;                 { builds it as 81 66 66 66 66 26 }

type
  TPath = array[1..Lanes, 1..LaneLen] of Word;
  { TWO-DIMENSIONAL AND 1-BASED, which is what makes the subscripts fold.
 is `IMUL AX,[Lane],$C8` then `ADD DI,$FF38` -- the -200 is in
    the ADDRESS, and that is what a bare subscript on a 1-based array gives.
    Flat and 0-based, `Dots^[(Lane - 1) * LaneLen]` makes the compiler work
    the -1 out at run time instead. Same 3,200 bytes either way. }
  TDots = array[1..Lanes, 1..LaneLen] of Byte;
  { THREE-DIMENSIONAL, the same shape as TDots above and one dimension deeper.
    All three low bounds fold into the displacement, so a lookup costs no
    arithmetic; a flat array makes the compiler subtract all three at run time.
    Same 15,104 bytes either way.

    59 glyphs from space, which is what FontSize divided by 256 gives, and the
    upper bound follows from it rather than being chosen. }
  TFont = array[FirstCh..FirstCh + FontSize div 256 - 1,
                1..16, 1..16] of Byte;
  { Entry by channel, for the same reason -- see P6TILES and part 004. }
  TPal768 = array[0..767] of Byte;

var
  Path : ^TPath;
  Dots : ^TDots;
  Font : ^TFont;
  F    : file;

{ --------------------------------------------------------------------------
  the sign of a Real, as three separate tests rather than an
  if/else chain. That is how the original is written and it is why the routine
  loads and compares the same value three times.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  the assets.

  ASSETS  NEUROSIS.DAT $001743E5:
            15,104 bytes  the font, 59 glyphs of 16 x 16, from space onwards
            768 bytes     the palette
  -------------------------------------------------------------------------- }
procedure Setup;
var
  { IN THE ORDER THE FRAME GIVES, and it closes to the byte: 128 + 2 + 4 + 768
    is 902, which is the ENTER $386 this routine opens with. Declared the other
    way round -- Pal first -- it put the palette nearest BP and everything else
    behind it, and the routine's frame references are 128 bytes of an unread
    local away from the original's.

    THE 128 BYTES NEAREST BP ARE NEVER REFERENCED, and they still have to be
    declared -- everything below them depends on their being there. They are
    the size of a file record, and this routine does open a file, but it opens
    the UNIT's rather than a local one. What they were for is not known; that
    they are 128 bytes and unread is. }
  Unread : file;                  { never referenced }
  I      : Integer;
  Dummy  : LongInt;
  Pal    : TPal768;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  { -- both results go into a local that nothing ever
    reads. Dead in the original; kept because it is there. }
  Dummy := MemAvail;

  GetMem(Path, PathSize);
  GetMem(Dots, DotSize);
  FillChar(Path^, PathSize, 0);
  FillChar(Dots^, DotSize, 0);
  GetMem(Font, FontSize);

  BlockRead(F, Font^, FontSize);
  BlockRead(F, Pal, SizeOf(Pal));
  Close(F);
  SetPalette768(@Pal);

  Dummy := MemAvail;
  for I := 0 to $3F do
    SetRGB(I + 100, I, 0, 0);
end;

{ NO LOCAL. The frame is ENTER $04 -- two bytes for the function result and
  two for the FPU status word the comparisons spill -- so there is no room
  for a variable, and assigning the function name directly is what fits.
  A local R plus `Sign := R` came out at $06. }
function Sign(X : Real) : Integer;
begin
  if X > 0.0 then Sign :=  1;
  if X < 0.0 then Sign := -1;
  if X = 0.0 then Sign :=  0;
end;

{ --------------------------------------------------------------------------
  walk a line from (X, Y) to (X2, Y2) and record the screen
  offsets of the points that survive the thinning into lane `Lane`.

  Ordinary Bresenham, except:

  - it is done in six-byte Reals, including Int(Major / 2) for the initial
    error;
  - a point is only RECORDED when a running total exceeds 1.0, and the amount
    added each step starts at 1.3 and loses 0.005 every time a point is
    recorded, so the spacing widens as the path runs;
  - the recorded slot is zeroed FIRST and only overwritten if the point is
    inside the window, so 0 doubles as "nothing here";
  - it gives up at 200 recorded points, and the window it clips to is not the
    screen: Y must be above 16, not above 0.
  -------------------------------------------------------------------------- }
procedure BuildPath(X, Y, X2, Y2, Lane : Integer);
var
  Dx, Dy       : Real;
  Err          : Real;
  StepDX,StepDY: Real;            { the diagonal step }
  SideDX,SideDY: Real;            { the straight step }
  Major, Minor : Real;
  I            : Integer;
  Points       : Integer;
  Accum        : Real;
  Thresh       : Real;
begin
  Points := 0;
  Accum  := 0.0;
  Thresh := Thresh0;

  Dx := X2 - X;
  Dy := Y2 - Y;

  StepDX := Sign(Dx);
  StepDY := Sign(Dy);
  SideDX := Sign(Dx);
  SideDY := 0.0;
  Major  := Abs(Dx);
  Minor  := Abs(Dy);

  { if the line is steeper than it is wide, swap which axis is
    the major one and make the straight step vertical instead.

    THE TEST READS THE STORED VARIABLES, not `Abs(Dy) >= Abs(Dx)`. Recomputing
    the two Abs calls costs two extra floating-point sites, and Major is named
    on the left. }
  if Major <= Minor then
  begin
    SideDX := 0.0;
    SideDY := Sign(Dy);
    Major  := Abs(Dy);
    Minor  := Abs(Dx);
  end;

  Err   := Int(Major / Two);

  { THE BOUND IS AN EXPRESSION, NOT A DECLARED LOCAL. The frame
    is ENTER $4a and the declarations above reach $46; a Limit variable plus
    the compiler's own bound temporary came to $4c. Round(Major) in the
    bound gives the temporary and nothing else. }
  for I := 0 to Round(Major) do
  begin
    Accum := Accum + Thresh;
    if Accum > One then
    begin
      Inc(Points);
      if Points > LaneLen then Exit;
      Path^[Lane, Points] := 0;
      { note the window: X in 1..319 and Y in 17..199. }
      if (X > 0) and (Y > 16) and (Y < 200) and (X < 320) then
        Path^[Lane, Points] := Y * 320 + X;
      Accum  := 0.0;
      Thresh := Thresh - Decay;
    end;

    Err := Err + Minor;
    { BOTH HALVES OF THIS TEST ARE MEASURED, and getting either wrong moved
      115 bytes without changing one instruction -- the same two blocks in the
      other order, each addressing the slots the other had.

      ERR IS ON THE LEFT. Turbo Pascal loads left to right and the operand
      loaded SECOND ends up on top of the floating-point stack, so the flags
      are read against the one named second.

      AND THE TEST IS `>=`, WITH THE SUBTRACT ARM FIRST -- the arm that falls
      through is the one the source names first. Written as `if Err < Major`
      with the arms swapped, every instruction is still the right length and
      only the branch condition differs. }
    if Err >= Major then
    begin
      Err := Err - Major;
      X := X + Round(StepDX);
      Y := Y + Round(StepDY);
    end
    else
    begin
      X := X + Round(SideDX);
      Y := Y + Round(SideDY);
    end;
  end;
end;

{ --------------------------------------------------------------------------
  the sixteen paths, and two fans of lines behind them.
  -------------------------------------------------------------------------- }
procedure DrawFrame;
var
  I      : Integer;               { 18 references }
  Unread : Integer;               { never touched -- either a declaration
                                    nothing reads or a temporary the compiler
                                    did not need. Declaring it closes the frame
                                    either way. }
begin
  for I := 1 to Lanes do
    BuildPath(320 - I * 2, 0, 0, 199 - I * 6, I);

  for I := 1 to $3F do
    DrawLine($120 - I, 0, 0, $67 - I, I + $63, VGASeg);
  for I := 1 to $3F do
    DrawLine(I, $C7, $13F, I, I + $63, VGASeg);
end;

{ the scene. }

{ --------------------------------------------------------------------------
  unpack one glyph into the dot table.

  The font is 16 x 16 bytes per character from space onwards. It is written
  into the dot table TRANSPOSED AND MIRRORED -- lane (16 - Row), position
  (16 - Col) -- so each lane ends up holding one row of the letter, which is
  what makes the letter arrive a row at a time.

  Row starts at TWO, not one, so the top row of every glyph is dropped.
  -------------------------------------------------------------------------- }
procedure LoadGlyph(Ch : Byte);
var Row, Col : Integer;
begin
  for Row := 2 to 16 do
    for Col := 1 to 16 do
      Dots^[17 - Row, 17 - Col] := Font^[Ch, Row, Col];
end;

{ --------------------------------------------------------------------------
  stream one string in.

  The plotting loop is HAND ASSEMBLER and the equivalent Pascal is below it.
  SI is a single running index from 1 to 3200 that walks the path table and
  the dot table TOGETHER -- it is not reset per lane, and the lane loop only
  exists to do the shift at the end of each 200.
  -------------------------------------------------------------------------- }
procedure Whoosh(S : String);
var
  Lane           : Integer;
  { TWO BYTES THAT NOTHING READS, and they must be declared: without them
    every local below is two bytes out. }
  Unread         : Integer;   { never referenced }
  CharIdx        : Integer;
  Pass           : Integer;
  PathSeg        : Word;
  PathOfs        : Word;
  DotSeg         : Word;
  DotOfs         : Word;
  { THERE IS NO `Len` VARIABLE. The slot at the bottom of the frame is the
    `for` loop's own temporary: a `for` costs two bytes for its limit whatever
    the limit is, so lifting the length into a variable pays for it twice. }
  { AND NOTHING BELOW IT. The running index lives in SI and ONLY in SI --
    carried across a far call into the runtime without being spilled -- which
    is why it is set in an asm block of its own below rather than declared.
    Declaring it costs two bytes of frame and four instructions a pass. }
begin
  PathSeg := Seg(Path^);   PathOfs := Ofs(Path^);
  DotSeg  := Seg(Dots^);   DotOfs  := Ofs(Dots^);


  for CharIdx := 1 to Length(S) do
  begin
    LoadGlyph(Ord(S[CharIdx]));
    for Pass := 1 to Lanes do
    begin
      asm XOR SI, SI end;                      { Idx := 0 }
      for Lane := 1 to Lanes do
      begin
        { --------------------------------------------------------------
          EQUIVALENT PASCAL, for reference -- the assembler is what runs:

              for K := 1 to 200 do
              begin
                Inc(SI);
                if Path^[1, SI] <> 0 then
                  Mem[$A000 : Path^[1, SI]] := Dots^[SI];
              end;

          It cannot be written that way: DS is repointed at the path table,
          then at the dot table, then back, once per dot, and SI is used as
          the index into both AND as the source offset for the MOVSB.
          -------------------------------------------------------------- }
        asm
          PUSH DS                { DS is about to be two tables   }
          MOV  AX, 0A000h
          MOV  ES, AX            { ES is the screen               }
          MOV  BX, 1             { 200 dots per lane              }
        @@Dot:
          MOV  AX, PathSeg       { <- THE LOOP COMES BACK HERE.   }
          MOV  DS, AX            { jumps to $070F, not
                                               to the INC below, because the
                                               body may have left DS pointing
                                               at the DOT table. Re-entering
                                               one instruction later reads the
                                               next path entry out of the dot
                                               table, and the dots then fly
                                               off in a straight line. }
          INC  SI                { the running index              }
          SHL  SI, 1             { as a WORD index...           }
          ADD  SI, PathOfs
          MOV  DI, [SI]          { the screen offset, or 0        }
          SUB  SI, PathOfs       { ...and back to an index      }
          SHR  SI, 1
          CMP  DI, 0
          JZ   @@Skip            { 0 means nothing here           }
          MOV  AX, DotSeg
          MOV  DS, AX
          ADD  SI, DotOfs
          MOVSB                  { ES:[DI] <- the dot             }
          DEC  SI                { MOVSB moved SI: put it back    }
          SUB  SI, DotOfs
        @@Skip:
          INC  BX
          CMP  BX, 0C9h          { 201                            }
          JNZ  @@Dot
          POP  DS
        end;                     { SI is LEFT LIVE across the Move below     }

        { shift this lane one place along, which is what makes
          the dots travel. 164 of the 200 bytes move; the tail does not. }
        Move(Dots^[Lane, 1], Dots^[Lane, 2], $A4);

        { AND THE INDEX IS WHATEVER MOVE LEAVES IN SI. The original keeps its
          running index in SI across this call and never reloads it, so what
          the next lane starts from is Move's own side effect. Source is one
          BELOW destination here, so Turbo Pascal's Move takes its backward
          path -- SI := Source + Count, decremented Count times -- and comes
          out at Source - 1. It is the reason lane L+1 walks lane L's stretch
          of the tables rather than its own. }
      end;
    end;
  end;
end;

{ the scene. }
procedure Scene1;
begin
  Setup;
  DrawFrame;
  Whoosh('ISNT''T THIS GREAT?     ');
  Whoosh('THIS WHOOSHTEXT HAS 4000 DOTS!!!            ');
  ClearScreen(VGASeg, 0);
  FreeMem(Path, PathSize);
  FreeMem(Font, FontSize);
  FreeMem(Dots, DotSize);
end;

{ the unit's initialisation is empty. }

begin
end.
