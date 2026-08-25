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
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

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
  { TWO-DIMENSIONAL AND 1-BASED, which is what makes the subscripts fold.
    1095:0741 is `IMUL AX,[Lane],$C8` then `ADD DI,$FF38` -- the -200 is in
    the ADDRESS, and that is what a bare subscript on a 1-based array gives.
    Flat and 0-based, `Dots^[(Lane - 1) * LaneLen]` makes the compiler work
    the -1 out at run time instead. Same 3,200 bytes either way. }
  TDots = array[1..Lanes, 1..LaneLen] of Byte;
  { THREE-DIMENSIONAL, AND THE FOLD IS THE PROOF -- the same reading as TDots
    above, one dimension deeper. 1095:0649 reaches a glyph byte as
    ES:[DI-$2011] with DI built from Ch shifted left 8, Row shifted left 4 and
    Col added, and $2011 is 8,209 = 32*256 + 1*16 + 1: the three low bounds,
    folded into the displacement. A flat array indexed
    Font^[(Ch - FirstCh) * 256 + (Row - 1) * 16 + (Col - 1)] makes the compiler
    subtract all three at RUN TIME instead. Same 15,104 bytes.

    59 glyphs from space, which is what FontSize divided by 256 gives, and the
    upper bound follows from it rather than being chosen. }
  TFont = array[FirstCh..FirstCh + FontSize div 256 - 1,
                1..16, 1..16] of Byte;
  { Entry by channel, for the same reason -- see P6S2 and part 004. }
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
{ NO LOCAL. The frame is ENTER $04 -- two bytes for the function result and
  two for the FPU status word the comparisons spill -- so there is no room
  for a variable, and assigning the function name directly is what fits.
  A local R plus `Sign := R` came out at $06. }
function Sign(X : Real) : Integer;
begin
  if X > 0.0 then Sign :=  1;     { 1095:0136 }
  if X < 0.0 then Sign := -1;     { 1095:015b }
  if X = 0.0 then Sign :=  0;     { 1095:0180 }
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
    the major one and make the straight step vertical instead.

    THE TEST READS THE STORED VARIABLES, not Abs(Dy) >= Abs(Dx). The original
    pushes Major then Minor and skips the block on JB, so the source names
    Major on the left; recomputing the two Abs calls emitted two extra x87
    sites, which is exactly what fpusites.py counted. }
  if Major <= Minor then
  begin
    SideDX := 0.0;                               { 1095:02ba }
    SideDY := Sign(Dy);                          { 1095:02d2 }
    Major  := Abs(Dy);                           { 1095:02f5 }
    Minor  := Abs(Dx);                           { 1095:0314 }
  end;

  Err   := Int(Major / Two);                     { 1095:0331 }

  { 1095:0357 -- THE BOUND IS AN EXPRESSION, NOT A DECLARED LOCAL. The frame
    is ENTER $4a and the declarations above reach $46; a Limit variable plus
    the compiler's own bound temporary came to $4c. Round(Major) in the
    bound gives the temporary and nothing else. }
  for I := 0 to Round(Major) do
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
      Dots^[17 - Row, 17 - Col] := Font^[Ch, Row, Col];   { 1095:0649 }
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
  Lane           : Integer;   { [BP-$102] }
  { TWO BYTES AT [BP-$104] THAT NOTHING READS. Whoosh's frame references are
    $100 (the String parameter's 256-byte local copy), $102, $106, $108, $10A,
    $10C, $10E, $110 and $112 -- there is no $104. Lane is an Integer, so it
    ends at BP-$101 and CharIdx should follow at $104, not $106. Without this
    every local from CharIdx down was two bytes out. }
  Unread         : Integer;   { [BP-$104], never referenced }
  CharIdx        : Integer;   { [BP-$106] }
  Pass           : Integer;   { [BP-$108] }
  PathSeg        : Word;   { [BP-$10A] }
  PathOfs        : Word;   { [BP-$10C] }
  DotSeg         : Word;   { [BP-$10E] }
  DotOfs         : Word;   { [BP-$110] }
  { Len WAS DECLARED HERE and [BP-$112] is the FOR LOOP's OWN TEMPORARY, not a
    variable. 1095:06c6 stores the length there and 1095:06cd compares against
    the same slot -- store-then-compare is what a `for` does with its limit.
    A `for` costs two bytes of frame whatever the limit is, measured in
    probe/TWOBYTE.PAS, so declaring Len as well paid twice and made this frame
    $114 against the original's $112. }
  { AND NOTHING BELOW $112. The running index is SI and it is ONLY ever SI:
    1095:06F8 is `XOR SI,SI` where a declared variable would be a store to the
    frame, and the register is then carried across the `Move` at 1095:0768 --
    across a far call into the runtime -- without being spilled. Declaring it
    and moving it in and out of the asm block cost two bytes of frame and four
    instructions a pass. It is set below in an asm block of its own for that
    reason. }
begin
  PathSeg := Seg(Path^);   PathOfs := Ofs(Path^);    { 1095:0698 }
  DotSeg  := Seg(Dots^);   DotOfs  := Ofs(Dots^);    { 1095:06ac }


  for CharIdx := 1 to Length(S) do                   { 1095:06c0 }
  begin
    LoadGlyph(Ord(S[CharIdx]));                  { 1095:06e9 }
    for Pass := 1 to Lanes do
    begin
      asm XOR SI, SI end;                      { 1095:06f8 -- Idx := 0 }
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
        end;                     { SI is LEFT LIVE across the Move below     }

        { 1095:0741 -- shift this lane one place along, which is what makes
          the dots travel. 164 of the 200 bytes move; the tail does not. }
        { NEITHER FORM IS RIGHT YET, and both measure the same. `(Lane - 1) *
          LaneLen` makes the compiler compute Lane-1 with a DEC; writing it as
          `Lane * LaneLen - LaneLen` replaces the DEC with a SUB and gains
          nothing. The original has neither: 1095:0741 is `IMUL AX,[Lane],$C8`
          followed by `ADD DI,$FF38`, so the -200 is folded into the ADDRESS.
          That fold is what a BARE subscript on a 1-based two-dimensional array
          gives -- Dots as array[1..Lanes, 1..LaneLen] indexed [Lane, 1] -- and
          changing it means reshaping the two other places that index Dots
          linearly. Left as it was until that is done in one piece. }
        Move(Dots^[Lane, 1], Dots^[Lane, 2], $A4);

        { AND THE INDEX IS WHATEVER MOVE LEAVES IN SI. The original keeps its
          running index in SI across this call and never reloads it, so what
          the next lane starts from is Move's own side effect. Source is one
          BELOW destination here, so Turbo Pascal's Move takes its backward
          path -- SI := Source + Count, decremented Count times -- and comes
          out at Source - 1. It is the reason lane L+1 walks lane L's stretch
          of the tables rather than its own.

          IT USED TO BE WRITTEN DOWN, as `Idx := Ofs(Dots^[Lane, 1]) - 1`, on
          the grounds that a register cannot be relied on to survive a Pascal
          call. The original relies on exactly that and the statement was the
          deviation: 1095:0741 to 1095:0768 sets the Move up in AX, DI and ES
          and never touches SI, so the register arrives at the next pass
          holding what Move left in it -- which is the value that statement
          computed. Removing it costs two bytes of frame and the reload. }
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
  { IN THE ORDER THE FRAME GIVES, and it closes to the byte: 128 + 2 + 4 + 768
    is 902, which is the ENTER $386 this routine opens with. Declared the other
    way round -- Pal first -- it put the palette nearest BP and everything else
    behind it, and the routine's frame references are 128 bytes of an unread
    local away from the original's.

    THE 128 BYTES NEAREST BP ARE NEVER REFERENCED. Every frame reference in
    1095:000d..1095:01a0 is to [BP-$82], [BP-$84], [BP-$86] or [BP-$386] --
    nothing touches [BP-$80] upward. A file record is exactly 128 bytes and
    this routine does open a file, but it opens the UNIT's F at DS:$738A, which
    1095:00c3 pushes by address. So the original very likely had a local file
    record here once and kept the declaration after moving to the global. That
    it is 128 bytes and unread is measured; what it was for is not. }
  Unread : file;                  { [BP-$80]..[BP-1], never referenced }
  I      : Integer;               { [BP-$82] }
  Dummy  : LongInt;               { [BP-$86] }
  Pal    : TPal768;               { [BP-$386] }
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
var
  I      : Integer;               { [BP-$02], 18 references }
  Unread : Integer;               { [BP-$04], never touched -- 1095:0578 opens
                                    ENTER $04 and [BP-$02] is the only slot the
                                    routine names, so the second word is either
                                    a declaration nothing reads or a temporary
                                    the compiler did not need. Declaring it is
                                    what closes the frame either way. }
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
