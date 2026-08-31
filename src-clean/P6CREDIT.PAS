{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.006 scene 4, segment 11bb.

  The credits, as a vertical scroller seen in perspective. A 256-wide, 256-tall
  buffer holds the text; one row of glyph pixels is fed into the bottom of it
  per frame and the whole 64K is shifted up. Screen rows 20..180 then each take
  one row of that buffer and STRETCH it horizontally by a per-row amount, so
  the text narrows towards the middle of the screen and flares out at the top
  and bottom.

  The stretch factors are worked out once: for each row, 255/(320 - 2*margin)
  in 8.8 fixed point, where the margins are 180 bytes read off NEUROSIS.DAT.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/27-part6-notes.md for the reading. }

{$S-}   { opens ENTER $386,0 with no stack check. }
{$G+}   { 186 shifts with immediates }
{$N+}   { the stretch table is worked out on the x87 }
{ I/O CHECKING OFF, and it must stay off: with it on Turbo Pascal puts a
  five-byte call to the runtime's check after every file operation, and this
  unit never tests IOResult. }
{$I-}

unit P6CREDIT;

interface

procedure Scene4;

implementation

uses Crt, VGA;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

const
  TopRow    = 20;                 { starts the table at $14 }
  BotRow    = 180;                { counts to $B4 }
  Chars     = 12;                 { counts I to $0B, zero based }
  GlyphW    = 20;                 { counts J to $14 }
  GlyphRows = 19;                 { wraps the row at $14 }
  Lines     = 113;                { stops at $72 }
  Pitch     = 21;                 { $15 -- the step between characters }
  BufSize   = $FFFF;              { asks GetMem for exactly this }
  FontSize  = $5B8C;              { 23436 -- the same font part 004 scrolls }
  GlyphSt   = $17A;               { 378 bytes per glyph }
  FirstChar  = 32;                { the font starts at space -- see TFont }
  GlyphCount = 62;                { 23,436 / 378 }
  { THE ARRAY'S DIMENSIONS ARE NOT THE LOOP BOUNDS. The glyph is 21 columns of
    18, and the loops below walk 20 and 19 -- one past each -- so with range
    checking off they read into the next glyph's first bytes. Declaring the
    array from the loop bounds instead changes the strides, and every glyph
    lookup then lands two bytes further on per character. }
  GlyphCols  = 21;                { the array's second dimension, 378 / 18 }
  GlyphHigh  = 18;                { the array's third }
  MarginN   = $B4;                { 180 }
  DataOfs   = DAT_P6_MARGIN;   { where this scene's assets start }
  FeedAt    = $FA00;              { 64000 -- where a fed row lands }
  Backdrop  = $C8;                { 200 -- the colour of the two bars }

type
  { THREE DIMENSIONS, and the addressing proves both the shape and the bounds.
 is LES DI,[Font] followed by THREE separate adds -- ADD DI,AX,
    ADD DI,DX, ADD DI,CX -- which is what a three-subscript reference emits;
    summing the terms into AX first and adding once, as a one-dimensional
    subscript does, is what ours did. }
  TFont   = array[FirstChar..FirstChar + GlyphCount - 1,
                  1..GlyphCols, 1..GlyphHigh] of Byte;
  TPal768 = array[0..767] of Byte;

{ THE ARRAY IS 99 AND THE LOOP COUNTS TO 113, and both are the original's.
  Lines 100..113 read PAST the array, into constants that happen to be zeros,
  which is why they draw blank. Widening the array to 113 would overlap the
  next unit's data.

  A DEVIATION LIVES HERE. Those fourteen reads land on whatever follows the
  table, and what follows it in this build is not what follows it in the
  original. They are blank there and are not guaranteed blank here. }
{$I gen/P6TEXT.INC}   { const CreditText : array[1..99] of String[255] }

var
  Margin  : array[TopRow..199] of Byte;
  { RUNS TO 199, NOT TO BotRow -- 180 entries, indices 20..199. Declaring it
    to BotRow gives 161 and leaves the next variable 38 bytes early, which was
    the whole of this part's data shortfall. }
  Stretch : array[TopRow..199] of Integer;   { folded base $94B8 }
  Buf     : Pointer;
  Font    : ^TFont;
  Line    : Integer;
  RowIn   : Integer;
  F       : file;

{ --------------------------------------------------------------------------
  the assets and the stretch table.

  ASSETS  NEUROSIS.DAT $0018B23F:
            180 bytes     the per-row left margin
            23,436 bytes  the font -- 62 glyphs of 21 x 18, the same one
                          part 004's scroller uses
            768 bytes     the palette
  -------------------------------------------------------------------------- }
procedure Setup;
var
  { 902 BYTES OF FRAME, AND THE PALETTE'S POSITION PLACES EVERYTHING ELSE.
    First declared is nearest BP, so the order is: a 128-byte file record and
    one Integer, neither referenced, then the 768-byte palette, then four more
    bytes. 128 + 2 + 768 + 4 = 902. Moving any of them moves the palette, and
    every reference to it with it.

    THE FOUR BELOW Pal ARE THE COMPILER'S, not a declaration. Declared as a
    LongInt the frame came out $38A -- four too many -- so 898 bytes of
    declarations plus a four-byte temporary is what makes 902. That is the same
    trap as part 007's function result: a slot the routine uses is not
    necessarily a slot it declares.

    P6TILES's Setup has the identical shape -- an unreferenced file record nearest
    BP ahead of its palette -- and so does P6WHOOSH's Load. Three routines in this
    part declare a file they never open. }
  Unread : file;                  { never referenced }
  I      : Integer;
  Pal    : TPal768;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Margin, MarginN);
  GetMem(Font, FontSize);
  BlockRead(F, Font^, FontSize);
  BlockRead(F, Pal, SizeOf(Pal));
  SetPalette768(@Pal);
  Close(F);
  SetRGB($1C, 0, 0, 0);

  GetMem(Buf, BufSize);
  FillChar(Buf^, BufSize, 0);

  { 255 units of texture spread across the visible width of the row, in 8.8. }
  for I := TopRow to BotRow do
    Stretch[I] := Round(255.0 / (320 - Margin[I] - Margin[I]) * 256.0);

  SetRGB(Backdrop, 5, 5, 5);
  FillRect(0, 0, 319, $13, Backdrop, VGASeg);
  FillRect(0, $B5, 319, 199, Backdrop, VGASeg);
end;

{ --------------------------------------------------------------------------
  feed one row of glyph pixels into the bottom of the buffer and
  scroll the whole thing up.

  Nothing is fed once the line number passes 99, and the feed is SKIPPED on the
  frame where the row counter is 19 -- so eighteen rows out of nineteen carry a
  glyph and the nineteenth is the blank gap between lines. Reading that test the
  other way up feeds only row 19 of every glyph, and the scroller comes out as
  single lines instead of letters. }
procedure FeedRow(P : Pointer);
var I, J : Integer;
begin
  if (Line <= $63) and (RowIn <> GlyphRows) then
    for I := 0 to Chars - 1 do
      for J := 1 to GlyphW do
        if Font^[Ord(CreditText[Line][I + 1]), J, RowIn] <> 0 then
          { THE GLOBAL HERE, NOT THE PARAMETER -- and the two hold the same
            value, because the caller passes Buf. The original simply names it
            directly at this one site and through the parameter at the other. }
          Mem[Seg(Buf^) : FeedAt + I * Pitch + J] :=
            Font^[Ord(CreditText[Line][I + 1]), J, RowIn];

  Inc(RowIn);
  if RowIn = $14 then
  begin
    RowIn := 1;
    Inc(Line);
  end;

  { blank the first 256 bytes, then pull everything from $200
    down to $100. The buffer is 256 wide, so that is one row of scroll. }
  asm
    LES  DI, P
    XOR  DI, DI
    XOR  AX, AX
    MOV  CX, 80h           { 128 words = one 256-byte row         }
    REP  STOSW
    MOV  CX, 7F74h
  @@Shift:
    MOV  AX, ES:[DI+100h]
    STOSW
    LOOP @@Shift
  end;
end;

{ --------------------------------------------------------------------------
  draw the buffer, one screen row at a time, stretched.

  HAND ASSEMBLER, verbatim. The equivalent Pascal is

      for Row := 20 to 180 do
      begin
        M := Margin[Row];
        U := 0;
        for K := 1 to 320 - 2*M do
        begin
          Mem[$A000 : RowOfs[Row] + M + K - 1] :=
            Mem[Seg(P^) : Row * 256 + Hi(U)];
          Inc(U, Stretch[Row]);
        end;
      end;

  and it cannot be written that way: the source segment is loaded from an
  IMMEDIATE ($164E, the data segment) to read the margin, then swapped for the
  buffer, and the texture coordinate lives in DX with the whole part taken by
  SHR SI,8 straight into the index.
  -------------------------------------------------------------------------- }
procedure Render(P : Pointer);
var
  Row  : Integer;
  Step : Integer;
begin
  for Row := TopRow to BotRow do
  begin
    Step := Stretch[Row];
    asm
      PUSH DS
      MOV  AX, 0A000h
      MOV  ES, AX
      MOV  BX, Row
      ADD  BX, BX
      MOV  DI, [BX + OFFSET YOfs]   { the binary has $96DA -- the }
                             {   VGA unit's row table, not an address to    }
                             {   copy across                                }
      MOV  SI, OFFSET Margin { the binary has $942C here...      }
      MOV  AX, SEG Margin    { ...and $164E here, both of them   }
      MOV  DS, AX            { absolute addresses in the ORIGINAL
                                           image. Copying the immediates over
                                           makes this read a random part of
                                           our data segment. }
      ADD  SI, Row
      SUB  SI, 14h           { the table starts at row 20         }
      XOR  DX, DX
      ADD  DL, [SI]          { DX := the margin                   }
      ADD  DI, DX            { indent the destination             }
      LDS  SI, P             { DS := the text buffer              }
      MOV  BX, Row
      SHL  BX, 8             { Row * 256 -- the buffer row        }
      MOV  CX, 140h
      SUB  CX, DX            { 320 less both margins              }
      SUB  CX, DX
      XOR  DX, DX            { the 8.8 texture coordinate         }
      MOV  AX, Step
    @@Pixel:
      MOV  SI, DX
      SHR  SI, 8             { its whole part                     }
      ADD  SI, BX
      MOVSB
      ADD  DX, AX
      LOOP @@Pixel
      POP  DS
    end;
  end;
end;

{ the scene. It ends on a key or when the 114th line comes up. }
procedure Scene4;
begin
  Setup;
  Line  := 1;
  RowIn := 1;
  repeat
    FeedRow(Buf);
    Render(Buf);
  until KeyPressed or (Line = Lines + 1);
  FreeMem(Buf, BufSize);
  FreeMem(Font, FontSize);
end;

{ the unit's initialisation is empty. }
begin
end.
