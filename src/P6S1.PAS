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

  ADDRESS MAP
    (filename)    1095:0000     BuildPath     1095:01a0
    Setup         1095:000d     DrawFrame     1095:0578
    Sign          1095:0114     LoadGlyph     1095:0614
    Whoosh        1095:067d     Scene1        1095:07d4

  DGROUP
    DS:$737e  the path table, 16 x 200 words   -- GetMem 6400
    DS:$7382  the dot table,  16 x 200 bytes   -- GetMem 3200
    DS:$7386  the font, 59 glyphs of 16 x 16   -- GetMem 15104
    DS:$738a  the file
  =========================================================================== }

{$S-}   { 1095:000d opens ENTER $386,0 with no stack check. }
{$N+}   { six-byte Reals through the x87, which is what the binary uses }

unit P6S1;

{$G+}   { 286: Whoosh_Run 100f:0590 opens ENTER $50a; every framed routine
          in the segment does. }

interface

procedure Scene1;

implementation

uses Crt, VGA;

const
  Lanes    = 16;                  { 1095:05b0 counts to $10 }
  LaneLen  = 200;                 { 1095:073a compares BX against $C9 }
  PathSize = Lanes * LaneLen * 2; { 6400 -- 1095:0048 }
  DotSize  = Lanes * LaneLen;     { 3200 -- 1095:0057 }
  FontSize = $3B00;               { 15104 -- 1095:0086, 59 glyphs of 256 }
  FirstCh  = 32;                  { the fold at 1095:0649 is -(32*256 + 17) }
  DataOfs  = $001743E5;           { 1095:0031 pushes $0017 then $43E5 }

  { 1095:018e, 1095:0192 and 1095:0196, read out of the code segment. }
  Two      = 2.0;
  One      = 1.0;
  Decay    = 0.005;
  Thresh0  = 1.3;                 { 1095:01b8 builds it as 81 66 66 66 66 26 }

type
  TPath = array[1..Lanes, 1..LaneLen] of Word;
  TDots = array[0..DotSize - 1] of Byte;
  TFont = array[0..FontSize - 1] of Byte;
  TPal768 = array[0..767] of Byte;

var
  Path : ^TPath;                  { DS:$737e }
  Dots : ^TDots;                  { DS:$7382 }
  Font : ^TFont;                  { DS:$7386 }
  F    : file;                    { DS:$738a }

{ --------------------------------------------------------------------------
  1095:0114 -- the sign of a Real, as three separate tests rather than an
  if/else chain. That is how the original is written and it is why the routine
  loads and compares the same value three times.
  -------------------------------------------------------------------------- }
function Sign(X : Real) : Integer;
var R : Integer;
begin
  if X > 0.0 then R :=  1;        { 1095:0136 }
  if X < 0.0 then R := -1;        { 1095:015b }
  if X = 0.0 then R :=  0;        { 1095:0180 }
  Sign := R;
end;

{ --------------------------------------------------------------------------
  1095:01a0 -- walk a line from (X, Y) to (X2, Y2) and record the screen
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
  Dx, Dy       : Real;            { [BP-6], [BP-$0c] }
  Err          : Real;            { [BP-$12] }
  StepDX,StepDY: Real;            { [BP-$18], [BP-$1e] -- the diagonal step }
  SideDX,SideDY: Real;            { [BP-$24], [BP-$2a] -- the straight step }
  Major, Minor : Real;            { [BP-$30], [BP-$36] }
  I            : Integer;         { [BP-$38] }
  Points       : Integer;         { [BP-$3a] }
  Accum        : Real;            { [BP-$40] }
  Thresh       : Real;            { [BP-$46] }
  Limit        : Integer;         { [BP-$48] }
begin
  Points := 0;                                   { 1095:01a4 }
  Accum  := 0.0;                                 { 1095:01a9 }
  Thresh := Thresh0;                             { 1095:01b8 }

  Dx := X2 - X;                                  { 1095:01c7 }
  Dy := Y2 - Y;                                  { 1095:01dc }

  StepDX := Sign(Dx);                            { 1095:01fa }
  StepDY := Sign(Dy);                            { 1095:0215 }
  SideDX := Sign(Dx);                            { 1095:0230 }
  SideDY := 0.0;                                 { 1095:0242 }
  Major  := Abs(Dx);                             { 1095:0260 }
  Minor  := Abs(Dy);                             { 1095:027f }

  { 1095:02ac -- if the line is steeper than it is wide, swap which axis is
    the major one and make the straight step vertical instead. }
  if Abs(Dy) >= Abs(Dx) then
  begin
    SideDX := 0.0;                               { 1095:02ba }
    SideDY := Sign(Dy);                          { 1095:02d2 }
    Major  := Abs(Dy);                           { 1095:02f5 }
    Minor  := Abs(Dx);                           { 1095:0314 }
  end;

  Err   := Int(Major / Two);                     { 1095:0331 }
  Limit := Round(Major);                         { 1095:0357 }

  for I := 0 to Limit do
  begin
    Accum := Accum + Thresh;                     { 1095:038e }
    if Accum > One then                          { 1095:03ad }
    begin
      Inc(Points);                               { 1095:03c1 }
      if Points > LaneLen then Exit;             { 1095:03c4 }
      Path^[Lane, Points] := 0;                  { 1095:03e4 }
      { 1095:03e9 -- note the window: X in 1..319 and Y in 17..199. }
      if (X > 0) and (Y > 16) and (Y < 200) and (X < 320) then
        Path^[Lane, Points] := Y * 320 + X;      { 1095:0421 }
      Accum  := 0.0;                             { 1095:0426 }
      Thresh := Thresh - Decay;                  { 1095:044a }
    end;

    Err := Err + Minor;                          { 1095:0477 }
    if Major > Err then                          { 1095:04a4 }
    begin
      X := X + Round(SideDX);                    { 1095:0533 }
      Y := Y + Round(SideDY);                    { 1095:0555 }
    end
    else
    begin
      Err := Err - Major;                        { 1095:04cf }
      X := X + Round(StepDX);                    { 1095:04ed }
      Y := Y + Round(StepDY);                    { 1095:050f }
    end;
  end;
end;

{ --------------------------------------------------------------------------
  1095:0614 -- unpack one glyph into the dot table.

  The font is 16 x 16 bytes per character from space onwards. It is written
  into the dot table TRANSPOSED AND MIRRORED -- lane (16 - Row), position
  (16 - Col) -- so each lane ends up holding one row of the letter, which is
  what makes the letter arrive a row at a time.

  Row starts at TWO, not one, so the top row of every glyph is dropped.
  -------------------------------------------------------------------------- }
procedure LoadGlyph(Ch : Byte);
var Row, Col : Integer;
begin
  for Row := 2 to 16 do                          { 1095:0618 }
    for Col := 1 to 16 do                        { 1095:0622 }
      Dots^[(16 - Row) * LaneLen + (16 - Col)] :=
        Font^[(Ch - FirstCh) * 256 + (Row - 1) * 16 + (Col - 1)];
end;

{ --------------------------------------------------------------------------
  1095:067d -- stream one string in.

  The plotting loop is HAND ASSEMBLER and the equivalent Pascal is below it.
  SI is a single running index from 1 to 3200 that walks the path table and
  the dot table TOGETHER -- it is not reset per lane, and the lane loop only
  exists to do the shift at the end of each 200.
  -------------------------------------------------------------------------- }
procedure Whoosh(S : String);
var
  PathSeg, PathOfs : Word;        { [BP-$10a], [BP-$10c] }
  DotSeg,  DotOfs  : Word;        { [BP-$10e], [BP-$110] }
  Len              : Integer;     { [BP-$112] }
  CharIdx          : Integer;     { [BP-$106] }
  Pass             : Integer;     { [BP-$108] }
  Lane             : Integer;     { [BP-$102] }
  Idx              : Word;        { SI in the original }
begin
  PathSeg := Seg(Path^);   PathOfs := Ofs(Path^);    { 1095:0698 }
  DotSeg  := Seg(Dots^);   DotOfs  := Ofs(Dots^);    { 1095:06ac }
  Len     := Length(S);                              { 1095:06c0 }

  for CharIdx := 1 to Len do
  begin
    LoadGlyph(Ord(S[CharIdx]));                  { 1095:06e9 }
    for Pass := 1 to Lanes do
    begin
      Idx := 0;                                { 1095:06f8 }
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
          MOV  SI, Idx           { SI is a REGISTER in the original and is   }
          PUSH DS                { 1095:0706  DS is about to be two tables   }
          MOV  AX, 0A000h        { 1095:0707                                 }
          MOV  ES, AX            { 1095:070a  ES is the screen               }
          MOV  BX, 1             { 1095:070c  200 dots per lane              }
        @@Dot:
          MOV  AX, PathSeg       { 1095:070f  <- THE LOOP COMES BACK HERE.   }
          MOV  DS, AX            { 1095:0713   1095:073e jumps to $070F, not
                                               to the INC below, because the
                                               body may have left DS pointing
                                               at the DOT table. Re-entering
                                               one instruction later reads the
                                               next path entry out of the dot
                                               table, and the dots then fly
                                               off in a straight line. }
          INC  SI                { 1095:0715  the running index              }
          SHL  SI, 1             { 1095:0716    as a WORD index...           }
          ADD  SI, PathOfs       { 1095:0718                                 }
          MOV  DI, [SI]          { 1095:071c  the screen offset, or 0        }
          SUB  SI, PathOfs       { 1095:071e    ...and back to an index      }
          SHR  SI, 1             { 1095:0722                                 }
          CMP  DI, 0             { 1095:0724                                 }
          JZ   @@Skip            { 1095:0727  0 means nothing here           }
          MOV  AX, DotSeg        { 1095:0729                                 }
          MOV  DS, AX            { 1095:072d                                 }
          ADD  SI, DotOfs        { 1095:072f                                 }
          MOVSB                  { 1095:0733  ES:[DI] <- the dot             }
          DEC  SI                { 1095:0734  MOVSB moved SI: put it back    }
          SUB  SI, DotOfs        { 1095:0735                                 }
        @@Skip:
          INC  BX                { 1095:0739                                 }
          CMP  BX, 0C9h          { 1095:073a  201                            }
          JNZ  @@Dot             { 1095:073e                                 }
          POP  DS                { 1095:0740                                 }
          MOV  Idx, SI           {   carried across the Move below           }
        end;

        { 1095:0741 -- shift this lane one place along, which is what makes
          the dots travel. 164 of the 200 bytes move; the tail does not. }
        Move(Dots^[(Lane - 1) * LaneLen],
             Dots^[(Lane - 1) * LaneLen + 1], $A4);

        { AND THE INDEX IS WHATEVER MOVE LEAVES IN SI. The original keeps its
          running index in SI across this call and never reloads it, so what
          the next lane starts from is Move's own side effect. Source is one
          BELOW destination here, so Turbo Pascal's Move takes its backward
          path -- SI := Source + Count, decremented Count times -- and comes
          out at Source - 1. Written down explicitly because a register cannot
          be relied on to survive a Pascal call in the reconstruction, and
          because it is the reason lane L+1 walks lane L's stretch of the
          tables rather than its own. }
        Idx := Ofs(Dots^) + (Lane - 1) * LaneLen - 1;
      end;
    end;
  end;
end;

{ --------------------------------------------------------------------------
  1095:000d -- the assets.

  ASSETS  NEUROSIS.DAT $001743E5:
            15,104 bytes  the font, 59 glyphs of 16 x 16, from space onwards
            768 bytes     the palette
  -------------------------------------------------------------------------- }
procedure Setup;
var
  Pal   : TPal768;                { [BP-$386] }
  Dummy : LongInt;                { [BP-$86] }
  I     : Integer;
begin
  Assign(F, 'neurosis.dat');                     { 1095:001b }
  Reset(F, 1);
  Seek(F, DataOfs);
  { 1095:003b and 1095:00d8 -- both results go into a local that nothing ever
    reads. Dead in the original; kept because it is there. }
  Dummy := MemAvail;

  GetMem(Path, PathSize);                        { 1095:004b }
  GetMem(Dots, DotSize);                         { 1095:005a }
  FillChar(Path^, PathSize, 0);                  { 1095:0071 }
  FillChar(Dots^, DotSize, 0);                   { 1095:0081 }
  GetMem(Font, FontSize);                        { 1095:0089 }

  BlockRead(F, Font^, FontSize);                 { 1095:00a7 }
  BlockRead(F, Pal, SizeOf(Pal));                { 1095:00be }
  Close(F);                                      { 1095:00c8 }
  SetPalette768(@Pal);                           { 1095:00d3 }

  Dummy := MemAvail;                             { 1095:00d8 }
  for I := 0 to $3F do                           { 1095:00ed }
    SetRGB(I + 100, I, 0, 0);
end;

{ --------------------------------------------------------------------------
  1095:0578 -- the sixteen paths, and two fans of lines behind them.
  -------------------------------------------------------------------------- }
procedure DrawFrame;
var I : Integer;
begin
  for I := 1 to Lanes do                         { 1095:057c }
    BuildPath(320 - I * 2, 0, 0, 199 - I * 6, I);

  for I := 1 to $3F do                           { 1095:05b6 }
    DrawLine($120 - I, 0, 0, $67 - I, I + $63, VGASeg);
  for I := 1 to $3F do                           { 1095:05e7 }
    DrawLine(I, $C7, $13F, I, I + $63, VGASeg);
end;

{ 1095:07d4 -- the scene. }
procedure Scene1;
begin
  Setup;                                         { 1095:07d7 }
  DrawFrame;                                     { 1095:07da }
  Whoosh('ISNT''T THIS GREAT?     ');             { 1095:07e2 }
  Whoosh('THIS WHOOSHTEXT HAS 4000 DOTS!!!            ');   { 1095:07ea }
  ClearScreen(VGASeg, 0);                        { 1095:07f2 }
  FreeMem(Path, PathSize);                       { 1095:0802 }
  FreeMem(Font, FontSize);                       { 1095:0812 }
  FreeMem(Dots, DotSize);                        { 1095:0822 }
end;

{ 1095:0829 -- the unit's initialisation is empty. }
begin
end.
