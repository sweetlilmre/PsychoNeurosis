{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 1, the logo and bouncing sprites

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit P1S1;

interface

procedure Scene1;

implementation

uses VGA, Crt, DemoVT;

const
  NumBouncers = 10;
  BounceW     = 40;        { 1012:0311 blits 40 rows of 40 bytes }
  BounceH     = 40;

type
  TSaveBank = array[1..NumBouncers, 0..BounceH * BounceW - 1] of Byte;
  TCell     = array[0..BounceH * BounceW - 1] of Byte;
  TLensTab  = array[0..BounceH * BounceW - 1] of Word;

var
  { The saved background under each bouncer. There is NO sprite bitmap: the
    bouncers are lenses over whatever they are sitting on. }
  Under   : ^TSaveBank;
  { DS:$4FD6 -- the single working cell the lens gathers into. }
  Cell    : TCell;
  { DS:$4304 -- the gather table, built once by BuildLens. }
  LensTab : TLensTab;

{ [transcribed] Scene 1 loads a 768-byte palette then a 320x200 screen
  straight into the virtual screen -- NEUROSIS.DAT $000000, 64,768 bytes. }
procedure LoadLogo;
var
  F : file;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, 0);
  BlockRead(F, Palette, SizeOf(Palette));
  SetPalette;
  BlockRead(F, Mem[VirtScrSeg : 0], 64000);
  Close(F);
end;

{ --------------------------------------------------------------------------
  The ten bouncing sprites -- Bounce_Run 1012:03e3, with the blit at
  1012:0311 and the matching save at 1012:02bc.

  Transcribed. An earlier reconstruction had the right IDEA -- save the
  background, draw, restore in reverse -- but the wrong numbers:

  * the sprites are 40 x 40, not 20 x 20;
  * they are drawn CENTRED, at (X - 20, Y - 20);
  * the blit is opaque (REP MOVSB), with no transparency test;
  * save and restore are the SAME routine, just with source and destination
    swapped -- restoring is a blit out of the saved-background buffer.

  The save slots are 1,641 bytes apart ($669) at DS:$FC81 + N * $669, which is
  more than the 1,600 a 40 x 40 block needs; the slack is not used.

  Erasing in REVERSE order is what makes overlapping sprites restore
  correctly, and is only necessary because of the save/restore scheme.

  HAND ASSEMBLER, verbatim. Instruction for instruction it is SaveUnder with
  LDS/LES swapped and DI walking the screen instead of SI -- see the notes
  there for the shift-based row offset.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      P := Src;
      for Row := 0 to 39 do
      begin
        Move(P^, Mem[Segment : (Y - 20 + Row) * 320 + X - 20], 40);
        Inc(LongInt(P), 40);
      end;
  -------------------------------------------------------------------------- }
procedure BlitSprite(X, Y : Integer; Src : Pointer; Segment : Word); assembler;
asm
  PUSH DS                 { DS becomes the source buffer's segment below    }
  LDS  SI, Src            { DS:SI := the 40 x 40 block to draw              }
  MOV  AX, X              { the sprite's centre X                           }
  MOV  BX, Y              {   and Y                                         }
  MOV  CX, $14            { 20 -- half of 40                                }
  SUB  AX, CX             { AX := the LEFT edge                             }
  SUB  BX, CX             { BX := the TOP edge                              }
  MOV  CX, Segment        { the screen to write to                          }
  MOV  ES, CX             { ES := it                                        }
  MOV  CX, AX             { park the left edge                              }
  MOV  AX, BX             { AX := the top row                               }
  MOV  BH, BL             { BX := row * 256                                 }
  XOR  BL, BL             {                                                 }
  SHL  AX, 1              { row * 2                                         }
  SHL  AX, 1              { row * 4                                         }
  SHL  AX, 1              { row * 8                                         }
  SHL  AX, 1              { row * 16                                        }
  SHL  AX, 1              { row * 32                                        }
  SHL  AX, 1              { row * 64                                        }
  ADD  BX, AX             { row * 320                                       }
  MOV  AX, CX             { the left edge back                              }
  ADD  AX, BX             { + the row offset                                }
  MOV  DI, AX             { ES:DI := the first screen byte to write         }
  MOV  DL, $28            { 40 rows to go                                   }
  XOR  CH, CH             {                                                 }
  MOV  CL, DL             { CX := 40, the bytes per row                     }
  CLD                     { forwards                                        }
  MOV  AX, CX             { keep the row length -- REP destroys CX          }
@@Row:                    { <- once per row of the block                    }
  MOV  BX, DI             { keep the row's start -- REP moves DI on         }
  MOV  CX, AX             { CX := 40 again                                  }
  REP  MOVSB              { draw the row                                    }
  MOV  DI, BX             { back to where the row started                   }
  DEC  DL                 { one row done                                    }
  JZ   @@Out              { all forty drawn                                 }
  ADD  DI, $140           { 320 -- down one screen row                      }
  JMP  @@Row              { round again                                     }
@@Out:                  { <- all forty rows done                          }
  POP  DS                 { restore our data segment                        }
end;

{ --------------------------------------------------------------------------
  1012:02bc -- SaveUnder(X, Y, Dest, Segment). HAND ASSEMBLER, verbatim.

  Copies the 40 x 40 block centred on (X, Y) out of Segment into Dest. The
  matching write is 1012:0311 below; the two are the same routine with the
  source and destination swapped.

  The screen offset is built with shifts, not a multiply: BX takes the row
  shifted up a byte (row * 256) and AX the row shifted left six (row * 64),
  and the two are added to give row * 320.

  RET $A: X at BP+$C, Y at BP+$A, Dest at BP+6, Segment at BP+4.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      P := Dest;
      for Row := 0 to 39 do
      begin
        Move(Mem[Segment : (Y - 20 + Row) * 320 + X - 20], P^, 40);
        Inc(LongInt(P), 40);
      end;
  -------------------------------------------------------------------------- }
procedure SaveUnder(X, Y : Integer; Dest : Pointer; Segment : Word); assembler;
asm
  PUSH DS                 { DS becomes the screen's segment below           }
  LES  DI, Dest           { ES:DI := the save buffer                        }
  MOV  AX, X              { the sprite's centre X                           }
  MOV  BX, Y              {   and Y                                         }
  MOV  CX, $14            { 20 -- half of 40                                }
  SUB  AX, CX             { AX := the LEFT edge                             }
  SUB  BX, CX             { BX := the TOP edge -- the sprite is centred     }
  MOV  CX, Segment        { the screen to read from                         }
  MOV  DS, CX             { DS := it                                        }
  MOV  CX, AX             { park the left edge                              }
  MOV  AX, BX             { AX := the top row                               }
  MOV  BH, BL             { BX := row * 256, by moving the byte up          }
  XOR  BL, BL             {                                                 }
  SHL  AX, 1              { row * 2                                         }
  SHL  AX, 1              { row * 4                                         }
  SHL  AX, 1              { row * 8                                         }
  SHL  AX, 1              { row * 16                                        }
  SHL  AX, 1              { row * 32                                        }
  SHL  AX, 1              { row * 64                                        }
  ADD  BX, AX             { row*256 + row*64 = row * 320, and no MUL        }
  MOV  AX, CX             { the left edge back                              }
  ADD  AX, BX             { + the row offset                                }
  MOV  SI, AX             { DS:SI := the first screen byte to copy          }
  MOV  DL, $28            { 40 rows to go                                   }
  XOR  CH, CH             {                                                 }
  MOV  CL, DL             { CX := 40, the bytes per row                     }
  CLD                     { forwards                                        }
  MOV  AX, CX             { keep the row length -- REP destroys CX          }
@@Row:                    { <- once per row of the block                    }
  MOV  BX, SI             { and keep the row's start -- REP moves SI on     }
  MOV  CX, AX             { CX := 40 again                                  }
  REP  MOVSB              { copy the row into the buffer                    }
  MOV  SI, BX             { back to where the row started                   }
  DEC  DL                 { one row done                                    }
  JZ   @@Out              { all forty copied                                }
  ADD  SI, $140           { 320 -- down one screen row                      }
  JMP  @@Row              { round again                                     }
@@Out:                  { <- all forty rows done                          }
  POP  DS                 { restore our data segment                        }
end;

{ --------------------------------------------------------------------------
  1012:0004 -- build the lens table.

  The bouncing objects are NOT sprites. Nothing in this scene loads any sprite
  data: Logo_Load reads a 768-byte palette and one 320x200 screen and stops.
  Each bouncer is a MAGNIFYING LENS over whatever it is sitting on.

  The table has one word per pixel of the 40 x 40 block, and EVERY pixel gets
  an entry -- that is the part an earlier reconstruction got wrong, which is
  why it drew a solid square with a lens inside it.

      X*X + Y*Y >  300   IDENTITY. The gather reads the pixel back from its
                         own position, the blit writes it straight back, and
                         the corner is invisible. There is no transparency
                         test anywhere: the blit is a flat REP MOVSB.

      X*X + Y*Y <= 300   the lens proper. Read off the x87 at 1012:0116:

                             Scale := R / (R + Sqrt(R*R - (X*X + Y*Y - 400)) + K)
                             SX    := Round(Scale * X)
                             SY    := Round(Scale * Y)

                         with R = 40 (the word at DS:$0002) and K = 1.0 (the
                         single at CS:$0000), so

                             Scale = 40 / (41 + Sqrt(2000 - (X*X + Y*Y)))

                         which runs from about 0.467 at the centre to 0.486 at
                         the rim -- a roughly even 2x magnification with a
                         slight barrel to it.

  The original walks X and Y from 0 up and writes all four quadrants each
  iteration; the formula is symmetric, so walking the full range once is the
  same thing and reads better.
  -------------------------------------------------------------------------- }
const
  LensR   = 40;        { DS:$0002 }
  LensK   = 1.0;       { CS:$0000 }
  LensCut = 300;       { the disc: X*X + Y*Y <= 300 }
  LensOfs = 400;       { the 20*20 term inside the square root }

procedure BuildLens;
var
  X, Y, D2, SX, SY : Integer;
  Scale            : Real;
begin
  for Y := -20 to 19 do
    for X := -20 to 19 do
    begin
      D2 := X * X + Y * Y;
      if D2 > LensCut then
      begin
        { outside the disc -- map the pixel to itself, so the blit is a no-op }
        SX := X;
        SY := Y;
      end
      else
      begin
        Scale := LensR / (LensR + Sqrt(LensR * LensR - (D2 - LensOfs)) + LensK);
        SX := Round(Scale * X);
        SY := Round(Scale * Y);
      end;
      LensTab[(Y + 20) * BounceW + (X + 20)] := (SY + 20) * BounceW + (SX + 20);
    end;
end;

{ [transcribed] 1012:0366 -- gather the working cell for bouncer N out of the
  background saved under it, through the lens table. 1,600 bytes, walked
  backwards. }
procedure BuildCell(N : Integer);
var
  I : Integer;
begin
  for I := BounceH * BounceW - 1 downto 0 do
    Cell[I] := Under^[N, LensTab[I]];
end;

{ Draw order per frame, from Bounce_Run: save the background, build the lens
  cell from it, blit it. Erasing is the same blit with the saved background as
  the source -- which is why the erase pass runs in REVERSE order. }
procedure DrawSprite(N, X, Y : Integer);
begin
  SaveUnder(X, Y, @Under^[N], VirtScrSeg);
  BuildCell(N);
  BlitSprite(X, Y, @Cell, VirtScrSeg);
end;

procedure EraseSprite(N, X, Y : Integer);
begin
  BlitSprite(X, Y, @Under^[N], VirtScrSeg);
end;

{ ===========================================================================
  Scene 1 -- logo and bouncing sprites            Demo_Scene1  1012:0678
  =========================================================================== }

const
  BounceMinX  = 21;   BounceMaxX = 299;
  BounceMinY  = 21;   BounceMaxY = 179;
  BounceFrames = 300;      { $12C -- 1012:05b1, the scene's whole lifetime }
  ScrollFrom   = 140;      { $8C  -- 1012:05a7, after which it slides out }
  ScrollStep   = 2;        { pixels per frame }

var
  BX, BY, BDX, BDY : array[1..NumBouncers] of Integer;

{ --------------------------------------------------------------------------
  1012:03bd -- ScrollLeft

  Slides the whole virtual screen two pixels to the left, one row at a time:

      DS = ES = VirtScrSeg ; DI = 0 ; SI = 2
      200 times:  REP MOVSW with CX = $9F      318 bytes = 159 words
                  SI += 2 ; DI += 2            318 + 2 = one 320-byte row

  The last two bytes of every row are deliberately NOT copied, so they hold
  whatever was there before -- and Demo_Scene1 drew two black vertical lines
  down x = 318 and x = 319 before the loop started. That black column is what
  feeds in from the right as the picture leaves.

  160 scrolling frames at 2 pixels is 320 -- exactly one screen, so the scene
  ends the instant the last of the logo clears the left edge. Leaving this out
  is why the scene simply sat there and bounced forever.

  HAND ASSEMBLER, verbatim. There is no CLD: it relies on the direction flag
  already being clear, which Turbo Pascal guarantees.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      D := 0;
      for Row := 0 to 199 do
      begin
        Move(Mem[VirtScrSeg : D + 2], Mem[VirtScrSeg : D], 318);
        Inc(D, 320);
      end;
  -------------------------------------------------------------------------- }
procedure ScrollLeft; assembler;
asm
  PUSH DS                 { DS becomes the virtual screen below             }
  MOV  ES, [VirtScrSeg]   { source and destination are the same screen      }
  MOV  DS, [VirtScrSeg]   {                                                 }
  MOV  DI, 0              { write from column 0                             }
  MOV  SI, 2              { read from column 2 -- two pixels along          }
  MOV  BX, $C8            { 200 rows                                        }
@@Row:                    { <- once per screen row                          }
  MOV  CX, $9F            { 159 words = 318 bytes, NOT the whole 320        }
  REP  MOVSW              { slide the row two pixels left                   }
  ADD  SI, 2              { the two bytes the copy did not touch: skip them }
  ADD  DI, 2              {   so both pointers land on the next row         }
  DEC  BX                 { one row done                                    }
  JNZ  @@Row              { round again                                     }
  POP  DS                 { restore our data segment                        }
end;

{ --------------------------------------------------------------------------
  Demo_Scene1 (1012:0678)

  ASSETS  NEUROSIS.DAT $000000, 64,768 bytes:
            assets/part001/logo_palette.pal    768 B
            assets/part001/asphyxia_logo.png   64,000 B -- the chrome/green
                                               ASPHYXIA logo with reflection
          See docs/14-part001-intro.md.
  -------------------------------------------------------------------------- }
procedure Scene1;
var
  F     : file;
  I     : Integer;
  Frame : Integer;
begin
  GetMem(Under, SizeOf(TSaveBank));
  BuildLens;
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  LoadLogo;                             { palette + 320x200 screen }
  Close(F);

  { Two black vertical lines down the right edge -- the artwork evidently
    has rubbish in its last two columns. }
  DrawLine(319, 199, 319, 0, 0, VirtScrSeg);
  DrawLine(318, 199, 318, 0, 0, VirtScrSeg);
  CopyScreen(VirtScrSeg, $A000);

  for I := 1 to NumBouncers do
  begin
    BDX[I] := Random(3) + 2;
    BDY[I] := Random(3) + 2;
    BX[I]  := Random(250) + 30;
    BY[I]  := Random(150) + 30;
  end;

  { 1012:0442 -- a counted loop, not an open one. }
  Frame := 1;
  repeat
    for I := 1 to NumBouncers do DrawSprite(I, BX[I], BY[I]);
    CopyScreen(VirtScrSeg, $A000);
    { erase in REVERSE order so overlapping sprites restore correctly }
    for I := NumBouncers downto 1 do EraseSprite(I, BX[I], BY[I]);

    for I := 1 to NumBouncers do
    begin
      Inc(BX[I], BDX[I]);
      Inc(BY[I], BDY[I]);
      { four separate tests in the original, 1012:0518..1012:058b -- X and Y
        are checked against their own low and high bounds independently }
      if BX[I] < BounceMinX then BDX[I] := -BDX[I];
      if BX[I] > BounceMaxX then BDX[I] := -BDX[I];
      if BY[I] < BounceMinY then BDY[I] := -BDY[I];
      if BY[I] > BounceMaxY then BDY[I] := -BDY[I];
    end;

    if KeyPressed then                  { 1012:0597 }
    begin
      ReadKey;
      Exit;
    end;

    if Frame > ScrollFrom then ScrollLeft;    { 1012:05a7 }
    Inc(Frame);
  until Frame > BounceFrames;                 { 1012:05b1 }
end;

end.
