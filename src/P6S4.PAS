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
  See docs/27-part6-notes.md for the reading.

  ADDRESS MAP
    (filename)    11bb:0000     Setup         11bb:0015
    FeedRow       11bb:0168     Render        11bb:025f
    Scene4        11bb:02c9

  DGROUP
    DS:$0C8A  the credits text, 113 lines on a 256-byte stride
    DS:$942c  the per-row margins, 180 bytes off the file
    DS:$94b8  the per-row 8.8 stretch, computed
    DS:$9648  the 64K text buffer     DS:$964c  the font, 23436 bytes
    DS:$9650  the line number         DS:$9652  the row within the line
    DS:$9654  the file
  =========================================================================== }

{$S-}   { 11bb:0015 opens ENTER $386,0 with no stack check. }
{$G+}   { 186 shifts with immediates }
{$N+}   { the stretch table is worked out on the x87 }

unit P6S4;

interface

procedure Scene4;

implementation

uses Crt, VGA;

const
  TopRow    = 20;                 { 11bb:00d5 starts the table at $14 }
  BotRow    = 180;                { 11bb:0129 counts to $B4 }
  Chars     = 12;                 { 11bb:0226 counts I to $0B, zero based }
  GlyphW    = 20;                 { 11bb:021d counts J to $14 }
  GlyphRows = 19;                 { 11bb:0233 wraps the row at $14 }
  Lines     = 113;                { 11bb:02fa stops at $72 }
  Pitch     = 21;                 { $15 -- the step between characters }
  BufSize   = $FFFF;              { 11bb:00b8 asks GetMem for exactly this }
  FontSize  = $5B8C;              { 23436 -- the same font part 004 scrolls }
  GlyphSt   = $17A;               { 378 bytes per glyph }
  MarginN   = $B4;                { 180 }
  DataOfs   = $0018B23F;          { 11bb:0039 pushes $0018 then $B23F }
  FeedAt    = $FA00;              { 64000 -- where a fed row lands }
  Backdrop  = $C8;                { 200 -- the colour of the two bars }

type
  TFont   = array[0..FontSize - 1] of Byte;
  TPal768 = array[0..767] of Byte;

{ THE ARRAY IS 99 AND THE LOOP COUNTS TO 113, and both are the original's.
  11bb:02fa stops at $72, so Lines really is 113; the table really is 99
  slots, because P6S1's Path pointer sits at DS:$737E and 99 slots of 256
  from $0D8A end at $708A -- 113 would run to $7F8A with Path inside it.
  Lines 100..113 therefore read PAST the array, into constants that are
  zeros, which is why they draw blank.

  A DEVIATION LIVES HERE. Those fourteen reads land on whatever follows the
  table, and what follows it in this build is not what follows it in the
  original. They are blank there and are not guaranteed blank here. }
{$I gen/P6TEXT.INC}   { const CreditText : array[1..99] of String[255] }

var
  Buf     : Pointer;              { DS:$9648 }
  Font    : ^TFont;               { DS:$964c }
  Line    : Integer;              { DS:$9650 }
  RowIn   : Integer;              { DS:$9652 }
  Margin  : array[TopRow..199] of Byte;      { DS:$942c }
  Stretch : array[TopRow..BotRow] of Integer;{ DS:$94b8 }
  F       : file;                 { DS:$9654 }

{ --------------------------------------------------------------------------
  11bb:0015 -- the assets and the stretch table.

  ASSETS  NEUROSIS.DAT $0018B23F:
            180 bytes     the per-row left margin
            23,436 bytes  the font -- 62 glyphs of 21 x 18, the same one
                          part 004's scroller uses
            768 bytes     the palette
  -------------------------------------------------------------------------- }
procedure Setup;
var
  Pal : TPal768;                  { [BP-$382] }
  I   : Integer;
begin
  Assign(F, 'neurosis.dat');                     { 11bb:0023 }
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Margin, MarginN);                 { 11bb:0054 }
  GetMem(Font, FontSize);                        { 11bb:005c }
  BlockRead(F, Font^, FontSize);                 { 11bb:007a }
  BlockRead(F, Pal, SizeOf(Pal));                { 11bb:0091 }
  SetPalette768(@Pal);                           { 11bb:009c }
  Close(F);                                      { 11bb:00a6 }
  SetRGB($1C, 0, 0, 0);                          { 11bb:00b3 }

  GetMem(Buf, BufSize);                          { 11bb:00ba }
  FillChar(Buf^, BufSize, 0);                    { 11bb:00d0 }

  { 11bb:00d5 -- 255 units of texture spread across the visible width of the
    row, in 8.8. CS:$000d is the single 255.0 and CS:$0011 the single 256.0. }
  for I := TopRow to BotRow do
    Stretch[I] := Round(255.0 / (320 - Margin[I] - Margin[I]) * 256.0);

  SetRGB(Backdrop, 5, 5, 5);                     { 11bb:0139 }
  FillRect(0, 0, 319, $13, Backdrop, VGASeg);    { 11bb:014c }
  FillRect(0, $B5, 319, 199, Backdrop, VGASeg);  { 11bb:0161 }
end;

{ --------------------------------------------------------------------------
  11bb:0168 -- feed one row of glyph pixels into the bottom of the buffer and
  scroll the whole thing up.

  Nothing is fed once the line number passes 99, and 11bb:017b skips the feed
  on the frame where the row counter IS 19 -- `JNZ` at 11bb:017b jumps INTO
  the feed, so eighteen rows out of nineteen are drawn and the nineteenth is
  the blank gap between lines. Reading that test the other way up feeds only
  row 19 of every glyph, and the scroller comes out as single lines instead of
  letters.
  -------------------------------------------------------------------------- }
procedure FeedRow(P : Pointer);
var I, J : Integer;
begin
  if (Line <= $63) and (RowIn <> GlyphRows) then  { 11bb:016c, 11bb:0176 }
    for I := 0 to Chars - 1 do
      for J := 1 to GlyphW do
        if Font^[Ord(CreditText[Line][I + 1]) * GlyphSt
                 + J * 18 + RowIn - 12115] <> 0 then
          Mem[Seg(P^) : FeedAt + I * Pitch + J] :=
            Font^[Ord(CreditText[Line][I + 1]) * GlyphSt
                  + J * 18 + RowIn - 12115];      { 11bb:021a }

  Inc(RowIn);                                     { 11bb:022f }
  if RowIn = $14 then                             { 11bb:0233 }
  begin
    RowIn := 1;
    Inc(Line);                                    { 11bb:0240 }
  end;

  { 11bb:0244 -- blank the first 256 bytes, then pull everything from $200
    down to $100. The buffer is 256 wide, so that is one row of scroll. }
  asm
    LES  DI, P             { 11bb:0244                                       }
    XOR  DI, DI            { 11bb:0247                                       }
    XOR  AX, AX            { 11bb:0249                                       }
    MOV  CX, 80h           { 11bb:024b  128 words = one 256-byte row         }
    REP  STOSW             { 11bb:024e                                       }
    MOV  CX, 7F74h         { 11bb:0250                                       }
  @@Shift:
    MOV  AX, ES:[DI+100h]  { 11bb:0253                                       }
    STOSW                  { 11bb:0258                                       }
    LOOP @@Shift           { 11bb:0259                                       }
  end;
end;

{ --------------------------------------------------------------------------
  11bb:025f -- draw the buffer, one screen row at a time, stretched.

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
  Row  : Integer;                 { [BP-2] }
  Step : Integer;                 { [BP-4] }
begin
  for Row := TopRow to BotRow do
  begin
    Step := Stretch[Row];                         { 11bb:0272 }
    asm
      PUSH DS                { 11bb:0279                                     }
      MOV  AX, 0A000h        { 11bb:027a                                     }
      MOV  ES, AX            { 11bb:027d                                     }
      MOV  BX, Row           { 11bb:027f                                     }
      ADD  BX, BX            { 11bb:0282                                     }
      MOV  DI, [BX + OFFSET YOfs]   { 11bb:0284  the binary has $96DA -- the }
                             {   VGA unit's row table, not an address to    }
                             {   copy across                                }
      MOV  SI, OFFSET Margin { 11bb:0288  the binary has $942C here...      }
      MOV  AX, SEG Margin    { 11bb:028b   ...and $164E here, both of them   }
      MOV  DS, AX            { 11bb:028e   absolute addresses in the ORIGINAL
                                           image. Copying the immediates over
                                           makes this read a random part of
                                           our data segment. }
      ADD  SI, Row           { 11bb:0290                                     }
      SUB  SI, 14h           { 11bb:0293  the table starts at row 20         }
      XOR  DX, DX            { 11bb:0296                                     }
      ADD  DL, [SI]          { 11bb:0298  DX := the margin                   }
      ADD  DI, DX            { 11bb:029a  indent the destination             }
      LDS  SI, P             { 11bb:029c  DS := the text buffer              }
      MOV  BX, Row           { 11bb:029f                                     }
      SHL  BX, 8             { 11bb:02a2  Row * 256 -- the buffer row        }
      MOV  CX, 140h          { 11bb:02a5                                     }
      SUB  CX, DX            { 11bb:02a8  320 less both margins              }
      SUB  CX, DX            { 11bb:02aa                                     }
      XOR  DX, DX            { 11bb:02ac  the 8.8 texture coordinate         }
      MOV  AX, Step          { 11bb:02ae                                     }
    @@Pixel:
      MOV  SI, DX            { 11bb:02b1                                     }
      SHR  SI, 8             { 11bb:02b3  its whole part                     }
      ADD  SI, BX            { 11bb:02b6                                     }
      MOVSB                  { 11bb:02b8                                     }
      ADD  DX, AX            { 11bb:02b9                                     }
      LOOP @@Pixel           { 11bb:02bb                                     }
      POP  DS                { 11bb:02bd                                     }
    end;
  end;
end;

{ 11bb:02c9 -- the scene. It ends on a key or when the 114th line comes up. }
procedure Scene4;
begin
  Setup;                                          { 11bb:02cc }
  Line  := 1;                                     { 11bb:02cf }
  RowIn := 1;                                     { 11bb:02d5 }
  repeat
    FeedRow(Buf);                                 { 11bb:02e3 }
    Render(Buf);                                  { 11bb:02ee }
  until KeyPressed or (Line = Lines + 1);         { 11bb:02f1, 11bb:02fa }
  FreeMem(Buf, BufSize);                          { 11bb:030b }
  FreeMem(Font, FontSize);                        { 11bb:031b }
end;

{ 11bb:0322 -- the unit's initialisation is empty. }
begin
end.
