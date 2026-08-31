{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 2, "ASPHYXIA PRESENTS"

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit P1TITLE;

{$I-}   { NO I/O CHECK, and this unit had no I directive at all so it took the
          command line's $I+ default -- four five-byte near calls to the
          runtime's check routine that the original does not have. Part 004's
          Lemmings unit and part 006's P6CREDIT were missed the same way; a unit
          with no I directive at all is worth suspecting on sight. }

{ 286 instructions are permitted. }
{$G+}

{ 80x87 code on: the reveal's timing is computed in floating point. }
{$N+}

interface

procedure Scene2;

implementation

uses VGA, Crt, DemoVT;

{ Where each asset sits inside NEUROSIS.DAT. }
{$I gen/DATOFS.INC}

const
  { both pass 10 -- the delay between fade frames. }
  FadePause   = 10;
  CometFrames = 10;
  CometW      = 65;
  CometH      = 48;
  CometSize   = CometW * CometH;   { the stride in the loaded buffer }
  RevealOfs   = 294;               { $126, and 01da adds a row to it }
  FontBias    = 8209;              { = 32*256 + 17, see DrawChar }

const
  ClipX1 : Integer = 0;
  ClipX2 : Integer = 319;
  ClipY1 : Integer = 0;
  ClipY2 : Integer = 199;

type
  TWorkBuf   = array[1..200, 1..26] of Byte;
  { ONE-BASED AND TWO-DIMENSIONAL, and the fold at the blit call says so.
 is IMUL AX,AX,$C30 -- the frame number times 3,120 -- and then
 is ADD DI,$F3D0, which as a signed word is MINUS 3,120: one
    element's worth, folded into the address, which is what a 1-based array of
    3,120-byte frames gives. A flat array indexed (Frame - 1) * CometSize makes
    the compiler subtract the one at RUN TIME instead. Same 31,200 bytes. }
  TCometFrame = array[0..CometSize - 1] of Byte;
  TCometBank = array[1..CometFrames] of TCometFrame;
  TFontBuf   = array[#32..#90, 1..16, 1..16] of Byte;

var
  { THE ORDER BELOW IS THE ADDRESSES', and it was not before -- WorkBuf came
    first here and belongs fifth. IT IS RIGHT NOW, MEASURED: every absolute
    displacement into this block is identical in both images, with identical
    reference counts -- $56C0 three times, $56C4 twice, $56C8 once, $56CA four
    times, $56CE five times. dsmap reports six sites here at +10, +4 and -14,
    and those are MIS-PAIRINGS, not defects: it anchors on the bytes before a
    reference and this block has several that look alike, which is why it also
    reports 87 sites skipped as ambiguous. Read the displacements directly
    before believing a shift row in a block this dense.

    Sorted, this unit's block TILES with no gap:

        $56C0  CometBank      4
        $56C4  Backdrop       4
        $56C8  BackdropSeg    2
        $56CA  FontBuf        4
        $56CE  WorkBuf        4
        $56D2  Pal          768
        $59D2  F            128   -> $5A52

    All four pointers are HEAP blocks in the original -- Title_Load GetMem's
    5,200, 64,000, 31,200 and 15,104 bytes in that order -- so only their four
    bytes each live here. }
  CometBank   : ^TCometBank;    { 10 frames of 65 x 48 }
  Backdrop    : Pointer;        { the 111,072-byte title image        }
  BackdropSeg : Word;
  FontBuf     : ^TFontBuf;      { 59 glyphs of 16 x 16 }
  WorkBuf     : ^TWorkBuf;
  { THIS SCENE'S OWN PALETTE BUFFER, and it was missing entirely.
 is MOV DI,$56D2 / PUSH $300 / BlockRead, so the 768 bytes are
    read into a unit-level buffer here and not into VGA's global. Part 003's
    sprite scene already records the same thing about itself. }
  Pal         : array[0..767] of Byte;
  F           : file;

{ --------------------------------------------------------------------------
  Title_Load

  This was missing entirely, which is why the scene hung: WorkBuf was nil and
  BlurBuffer WRITES through it -- 3,900 bytes straight over the interrupt
  vector table at 0000:xxxx.

  NEUROSIS.DAT $00FD00, 111,072 bytes in four reads:

      768     palette
      31,200  the comet, 10 frames of 65 x 48 (10 * 3120)
      64,000  the backdrop screen
      15,104  the font, 59 glyphs of 16 x 16 (59 * 256)

  Between the screen read and the font read it blanks all 256 DAC entries,
  shows the screen, FADES UP to the palette it just loaded, and only then
  lays a RED ramp over entries 1..121 (R := I div 2) and shows it again. }
procedure Load;
var
  I      : Integer;
  Spare1 : String;                      { 256, never read }
  Spare2 : String[127];                 { 128, never read }
begin
  GetMem(WorkBuf,   SizeOf(TWorkBuf));
  GetMem(Backdrop,  64000);
  BackdropSeg := Seg(Backdrop^);
  GetMem(CometBank, SizeOf(TCometBank));

  BlockRead(F, Pal, 768);
  BlockRead(F, CometBank^, SizeOf(TCometBank));
  ClearScreen($A000, 0);
  BlockRead(F, VirtScr^, 64000);

  { Blank, show, then fade UP to the palette just loaded. Only after that
    does the red ramp go over entries 1..121.

    An earlier version blanked the DAC and set nothing but the ramp, which
    left colours 122..255 BLACK. Most of the backdrop is in that range, so the
    scene ran correctly and displayed nothing. }
  for I := 0 to 255 do SetRGB(I, 0, 0, 0);
  CopyScreen(VirtScrSeg, $A000);
  PaletteFadeUp(@Pal, FadePause);
  for I := 1 to 121 do SetRGB(I, I div 2, 0, 0);  { the red ramp }
  CopyScreen(VirtScrSeg, $A000);
  CopyScreen(VirtScrSeg, BackdropSeg);            { keep a clean copy }

  GetMem(FontBuf, SizeOf(TFontBuf));              { late }
  BlockRead(F, FontBuf^, SizeOf(TFontBuf));
end;

{ Redraw the characters revealed so far.

  A 150-row by 26-column masked blit out of the working buffer.
  The mask is a THRESHOLD, not a key: source bytes of 20 or less are skipped,
  so the anti-aliased edges of the glyphs drop out and only the solid core is
  copied. }
procedure BlitClipped(Src : Pointer; X, Y : Integer; Segment : Word); assembler;
var
  SkipL : Integer;
  SkipR : Integer;
  Spare : Integer;                { never touched }
asm
        PUSH    DS
        MOV     AX, Segment
        MOV     ES, AX                  { 0130  ES:DI is the screen          }
        LDS     SI, Src                 { 0132  DS:SI is the sprite...       }
        XOR     DH, DH
        MOV     DL, CometH              { 0137  DX := 48 rows                }
        XOR     CH, CH
        MOV     CL, CometW              { 013b  CX := 65 columns             }
        POP     DS                      { 013d  ...but DGROUP again for now, }
        MOV     WORD PTR SkipL, 0       { 013e    because the clip bounds    }
        MOV     WORD PTR SkipR, 0       { 0143    are read out of it         }
        MOV     BX, Y
        MOV     AX, ClipY1
        SUB     AX, BX
        JLE     @@NoTop
        CMP     AX, DX
        JGE     @@Done                  { 0154  wholly above the window      }
        SUB     DX, AX
        ADD     BX, AX
        MOV     DI, DX                  { 015a  park the row count round MUL }
        MUL     CX                      { 015c  clipped rows x 65            }
        MOV     DX, DI
        ADD     SI, AX
@@NoTop:
        MOV     AX, ClipY2
        SUB     AX, BX
        JLE     @@Done                  { 0167  wholly below it              }
        CMP     AX, DX
        JGE     @@NoBot
        INC     AX
        MOV     DX, AX
@@NoBot:
        ADD     BX, BX
        MOV     DI, [BX + OFFSET YOfs]  { 0172  DI := Y * 320                }
        MOV     BX, X
        ADD     DI, BX
        MOV     AX, ClipX1
        SUB     AX, BX
        JLE     @@NoLeft
        CMP     AX, CX
        JGE     @@Done                  { 0184  wholly left of the window    }
        MOV     WORD PTR SkipL, AX      { 0186  skip this many per row       }
        ADD     DI, AX
        SUB     CX, AX
@@NoLeft:
        MOV     AX, ClipX2
        SUB     AX, BX
        JLE     @@Done                  { 0192  wholly right of it           }
        CMP     AX, CX
        JGE     @@NoRight
        SUB     CX, AX
        MOV     WORD PTR SkipR, CX
        MOV     CX, AX
@@NoRight:
        MOV     BX, CX                  { 019f  BX := the drawn width        }
        { DS IS RELOADED THE LONG WAY ROUND. LDS overwrites SI, and the SI it
          overwrites is the clipped start the code has just spent forty
          instructions computing -- so SI is pushed, the LDS is done for its DS
          alone, and SI is popped straight back. Four bytes and it is what the
          original does. }
        PUSH    DS
        PUSH    SI
        LDS     SI, Src                 { 01a3  for DS only                  }
        POP     SI
        CLD
@@Row:  ADD     SI, SkipL               { 01a8  <- once per row              }
@@Pixel:
        LODSB
        OR      AL, AL
        JE      @@Clear
        STOSB
        DEC     CL
        JNE     @@Pixel
        JMP     @@NextRow
@@Clear:
        INC     DI
        DEC     CL
        JNE     @@Pixel
@@NextRow:
        ADD     SI, SkipR
        MOV     CX, BX                  { 01bf  the width back for next row  }
        ADD     DI, 320
        SUB     DI, BX
        DEC     DL
        JNE     @@Row
        POP     DS
@@Done:                                 { 01cc is the LEAVE / RET $A         }
end;

{ --------------------------------------------------------------------------
  Title_ShowWord

  Called twice -- once with 'ASPHYXIA' (1082:$055E) and once with
  'PRESENTS' (1082:$0567). A counter runs from 80 down to -18 while a comet
  sprite flies across; as it passes, characters are revealed one at a time.
  When the counter reaches -18 a 100-frame outro plays.

  ASSETS, out of NEUROSIS.DAT:
            assets/part001/INTROPAL.PAL    768 B
            assets/part001/COMET0.PNG .. COMET9.PNG
                                      10 frames of 65x48 -- a flaming comet
            assets/part001/INTROBAK.PNG   64,000 B
            assets/part001/00FD00D.BIN        15,104 B = a 59-character
                                      16x16 font (59 x 256), drawn two
                                      rows at a time by DrawChar
          A 5,200-byte working buffer is allocated separately.
  -------------------------------------------------------------------------- }

procedure DrawRevealed; assembler;
asm
        PUSH    ES
        PUSH    DS
        MOV     AX, [VirtScrSeg]
        MOV     ES, AX                  { 01d5  ES:DI is the virtual screen   }
        MOV     DI, RevealOfs           { 01d7  $266                         }
        ADD     DI, 320                 { 01da  one row down to start         }
        LDS     SI, WorkBuf             { 01de  DS:SI is the working buffer   }
        MOV     BX, 150                 { 01e2  rows                         }
@@Row:  MOV     CX, 26                  { 01e5  columns, reloaded per row     }
@@Pixel:
        MOV     AL, [SI]
        CMP     AL, 20                  { 01ea  THE MASK IS A THRESHOLD       }
        JLE     @@Skip                  { 01ec    and not a colour key        }
        MOV     ES:[DI], AL
@@Skip: INC     DI                      { 01f1  BOTH advance either way, so   }
        INC     SI                      { 01f2    the skip is a hole and not  }
        DEC     CX                      { 01f3    a shift                     }
        JNE     @@Pixel
        ADD     DI, 292                 { 01f6  $124 -- and DI is already 26  }
        DEC     BX                      { 01fa    further on, so the stride   }
        JNE     @@Row                   { 01fb    is 318 and the block LEANS  }
        POP     DS
        POP     ES
end;
{ Draw the character currently animating. Phase is
  Trunc(Phase) from ShowWord: one of 1, 3, 5, 7, 9, 11, 13, 15. }
{ --------------------------------------------------------------------------
  Draw one character into the work buffer.

  It does TWO font rows per call, Phase and Phase + 1, which is what makes the
  glyph unroll two scanlines at a time as Phase steps 1, 3, 5 .. 15.

  The font is 16 x 16: 256 bytes per glyph, 16 per row -- which is where the
  15,104-byte read comes from (59 * 256). The work buffer is 26 bytes per row,
  the same 26 that DrawRevealed blits and BlurBuffer smears.

      if Font[Ord(Ch)*256 + Phase*16 + C - 8209] <> 0 then
        Work[((Index-1)*17 + Phase + 1) * 26 + C + 5 - 27] := 121

  The -8209 is not decoration: the font holds 59 glyphs, so a raw Ord('A')*256
  would run 1,500 bytes off the end of the 15,104-byte buffer. 8209 = 32*256
  + 17, i.e. the table starts at space and each glyph is 17 bytes short of a
  full 256 -- which is what brings 'A'..'Z' back inside it.

  Every lit pixel is written as colour $79 = 121; there is no shading here,
  the gradient comes from BlurBuffer afterwards.
  -------------------------------------------------------------------------- }
procedure DrawChar(Ch : Char; Phase, Index : Integer);
var
  C : Integer;                     { the whole frame }
begin
  for C := 1 to 16 do
    if FontBuf^[Ch, Phase, C] <> 0 then
      WorkBuf^[(Index - 1) * 17 + Phase + 1, C + 5] := 121;
  for C := 1 to 16 do
    if FontBuf^[Ch, Phase + 1, C] <> 0 then
      WorkBuf^[(Index - 1) * 17 + Phase + 2, C + 5] := 121;
end;

{ --------------------------------------------------------------------------
  NOT an outro. It is a BLUR.

  3,900 iterations of a diagonal four-neighbour average over the working
  buffer:

      P[0] := (P[-27] + P[-25] + P[+25] + P[+27]) shr 2

  With a row width of 26 those offsets are the four DIAGONAL neighbours, and
  3,900 is exactly 26 x 150 -- the same buffer DrawRevealed reads. Running it
  100 times is what dissolves the finished word into a smear rather than
  cutting away from it.

  The earlier name and body were guesses from the call site alone.
  -------------------------------------------------------------------------- }
procedure BlurBuffer; assembler;
asm
        LES     DI, WorkBuf             { ES:DI := the buffer                 }
        ADD     DI, 27                  { 02be  the first byte with four      }
                                        {         diagonal neighbours         }
        MOV     CX, 3900                { 02c1  26 x 150, the whole band      }
                                        {         loop, so BX is a widened BL }
@@Pixel:
        XOR     AX, AX
        XOR     BX, BX                  { 02c6  BH stays zero for the whole   }
        MOV     BL, ES:[DI-27]          { 02c8  up and left                   }
        MOV     AX, BX
        MOV     BL, ES:[DI-25]          { 02ce  up and right                  }
        ADD     AX, BX
        MOV     BL, ES:[DI+25]          { 02d4  down and left                 }
        ADD     AX, BX
        MOV     BL, ES:[DI+27]          { 02da  down and right                }
        ADD     AX, BX
        SHR     AX, 2                   { 02e0  the average of the four       }
        STOSB                           { 02e3  and DI steps on by itself     }
        LOOP    @@Pixel
end;

{ ===========================================================================
  Scene 2 -- "ASPHYXIA PRESENTS"
  =========================================================================== }


{ --------------------------------------------------------------------------
  Sprite_BlitClipped -- the comet. HAND ASSEMBLER, verbatim.

  A 65 x 48 transparent blit clipped against four bounds in DGROUP:

  The clip is done by adjusting the START POINTER and the row and column COUNTS
  before the copy, never per pixel: a top clip advances the source by
  (rows * 65) with a MUL, a left clip advances the destination and shortens the
  row, and both leftovers are added back between rows. Zero bytes are skipped.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Rows := CometH;  Cols := CometW;  SkipL := 0;  SkipR := 0;
      if ClipY1 - Y > 0 then
      begin
        if ClipY1 - Y >= Rows then Exit;
        Dec(Rows, ClipY1 - Y);  Inc(P, (ClipY1 - Y) * CometW);  Y := ClipY1;
      end;
      if ClipY2 - Y <= 0 then Exit;
      if ClipY2 - Y < Rows then Rows := ClipY2 - Y + 1;
      D := YOfs[Y] + X;
      if ClipX1 - X > 0 then
      begin
        if ClipX1 - X >= Cols then Exit;
        SkipL := ClipX1 - X;  Inc(D, SkipL);  Dec(Cols, SkipL);
      end;
      if ClipX2 - X <= 0 then Exit;
      if ClipX2 - X < Cols then
      begin
        SkipR := Cols - (ClipX2 - X);  Cols := ClipX2 - X;
      end;
      for Row := 1 to Rows do
      begin
        Inc(P, SkipL);
        for Col := 1 to Cols do
        begin
          if P^ <> 0 then Mem[Segment : D] := P^;
          Inc(P);  Inc(D);
        end;
        Inc(P, SkipR);  Inc(D, 320 - Cols);
      end;
  -------------------------------------------------------------------------- }

{ --------------------------------------------------------------------------
  Title_ShowWord

  Called twice -- once with 'ASPHYXIA' (1082:$055E) and once with
  'PRESENTS' (1082:$0567). A counter runs from 80 down to -18 while a comet
  sprite flies across; as it passes, characters are revealed one at a time.
  When the counter reaches -18 a 100-frame outro plays.

  ASSETS, out of NEUROSIS.DAT:
            assets/part001/INTROPAL.PAL    768 B
            assets/part001/COMET0.PNG .. COMET9.PNG
                                      10 frames of 65x48 -- a flaming comet
            assets/part001/INTROBAK.PNG   64,000 B
            assets/part001/00FD00D.BIN        15,104 B = a 59-character
                                      16x16 font (59 x 256), drawn two
                                      rows at a time by DrawChar
          A 5,200-byte working buffer is allocated separately.
  -------------------------------------------------------------------------- }
procedure ShowWord(S : String);
var
  Count                  : Integer;
  CometPos, Frame, Phase : Real;
  CharIdx                : Integer;
begin
  CometPos := -48.0;
  Frame   :=   1.0;
  CharIdx :=  -1;
  Phase   :=   1.0;

  { FillChar(WorkBuf, 5200, 0). ShowWord clears the work buffer
    on EVERY call, which is what stops the first word's blurred remains (and,
    on the first call, raw heap garbage) showing through. DrawRevealed stores
    any byte above 20, so without this there is a permanent stripe. }
  FillChar(WorkBuf^, SizeOf(TWorkBuf), 0);

  for Count := 80 downto -18 do
  begin
    CopyScreen(BackdropSeg, VirtScrSeg);
    DrawRevealed;                    { the characters so far }

    BlitClipped(@CometBank^[Round(Frame)],
                Count * 4, Round(CometPos), VirtScrSeg);

    { Only the character currently animating is drawn here; Trunc(Phase) is
      its animation step, one of 1, 3, 5, 7, 9, 11, 13, 15. }
    if (CharIdx > 0) and (CharIdx < Length(S) + 1) then
      DrawChar(S[CharIdx], Round(Phase), CharIdx);

    Phase := Phase + 2.0;
    if Phase > 15.0 then
    begin
      Phase := 1.0;
      CharIdx := CharIdx + 1;          { eight frames per character }
    end;

    CopyScreen(VirtScrSeg, $A000);

    Frame := Frame + 0.3;            { ~31 frames for the 10-frame cycle }
    if Frame > 10.0 then Frame := 1.0;

    CometPos := CometPos + 2.0;

    if KeyPressed then Exit;
  end;

  { --------------------------------------------------------------------
    The outro -- 100 frames, and it REDRAWS every one:

        CopyScreen(Backdrop -> Virt)
        DrawRevealed                    (* the work buffer as it stands *)
        BlurBuffer                      (* one pass *)
        CopyScreen(Virt -> $A000)

    That is the fade. BlurBuffer alone changes nothing on screen; it is the
    re-blit each frame that makes the smear visible, and because DrawRevealed
    only stores bytes above 20, the letters stop being drawn at all once the
    blur has pulled them under that threshold. Running the 100 passes without
    redrawing -- which is what an earlier version did -- leaves the finished
    word sitting there and then cuts away.
    -------------------------------------------------------------------- }
  for Count := 1 to 100 do
  begin
    CopyScreen(BackdropSeg, VirtScrSeg);
    DrawRevealed;
    BlurBuffer;
    CopyScreen(VirtScrSeg, $A000);
  end;
end;



procedure Scene2;

begin
  { Opened HERE, before Load, which is where the original has it. }
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DAT_P1_INTROPAL);               { was $00FD00 }
  Load;                                   { a near call to offset 0 }
  Close(F);                               { AFTER Load returns }
  ShowWord('ASPHYXIA');
  ShowWord('PRESENTS');
  PaletteFadeOut(FadePause);
  { THE FOUR FreeMems ARE INLINE, and the segment's arithmetic leaves nowhere
    else for them. 1082 runs Load 0000, BlitClipped 0128, DrawRevealed 01d0,
    DrawChar 0200, BlurBuffer 02ba, ShowWord 02fd, Scene2 056f and the
    initialisation 0602 -- contiguous, with no gap for an Unload routine. And
 is CB, a FAR return, which is Scene2's own epilogue; ours emitted
    C3 because a near local Unload ended there instead. }
  FreeMem(CometBank, SizeOf(TCometBank));  { $79E0 = 31,200 }
  FreeMem(Backdrop,  64000);               { $FA00 }
  FreeMem(FontBuf,   SizeOf(TFontBuf));    { $3B00 = 15,104 }
  FreeMem(WorkBuf,   SizeOf(TWorkBuf));
end;

begin
end.
