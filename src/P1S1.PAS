{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 1, the logo and bouncing sprites

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit P1S1;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

{$G+}   { 286: every framed routine in 1012 opens ENTER, e.g. Bounce_Run
          1012:03e3 ENTER $54. }
{$N+}   { the unit init's arithmetic is x87 -- 1012:0142 FILD. }

interface

procedure Scene1;

implementation

uses VGA, Crt, DemoVT;

const
  NumBouncers = 10;
  BounceW     = 40;        { 1012:0311 blits 40 rows of 40 bytes }
  BounceH     = 40;

type
  { THE ROW IS 1641 BYTES, NOT 1600, and it is the same index range as the
    lens table -- which is the point: LensTab[I] is used as a subscript into a
    bouncer's saved cell, so the two must have the same bound. BuildCell
    settles the size: 1012:036a is IMUL DI,[BP+4],$669 -- 1641 -- and
    1012:036f LEA AX,[DI-$37F] takes 895 off it, which is the base minus one
    row folded into the displacement, giving a base of $02EA.

    And it TILES: $02EA plus ten rows of 1641 is $4304, which is exactly where
    LensTab begins. }
  TSaveBank = array[1..NumBouncers, 0..BounceW * (BounceH + 1)] of Byte;
  { 1641 BYTES, the same as a bank row and the same as the lens table, for the
    same reason: LensTab[I] subscripts both. And it tiles -- Cell at $4FD6 plus
    1641 is $563F, which is where the file record is. }
  TCell     = array[0..BounceW * (BounceH + 1)] of Byte;
  { 1641 words, not 1600, and the extra 41 are not slack -- BuildLens walks a
    QUADRANT and mirrors, so it also writes row 20 and column 20, whose index
    is (20+20)*40 + (20+20) = 1640. Two measurements agree: the unit init at
    1012:0008 clears 3282 bytes (`PUSH $0CD2` at 1012:000d), and in the
    original DS:$4FD6 - DS:$4304 = $0CD2 = 1641 words exactly, so Cell begins
    where this table ends. }
  TLensTab  = array[0..BounceW * (BounceH + 1)] of Word;

var
  { The saved background under each bouncer. There is NO sprite bitmap: the
    bouncers are lenses over whatever they are sitting on. }
  { DS:$02EA -- INLINE IN DGROUP, not on the heap. This was `^TSaveBank` with
    a GetMem, which is four bytes where the original has 16,410, and it is most
    of why every absolute data displacement in this part was wrong: the MZ
    header asks the loader for 16,704 bytes more uninitialised space than our
    build did.

    BuildCell is the proof. 1012:03a2 is MOV BX,[BP-4] / ADD BX,AX / MOV AL,[BX]
    -- a DS-relative byte read at an offset computed from the bouncer number.
    A heap block cannot be reached that way; it would need the pointer loaded
    into a segment register first. }
  Under   : TSaveBank;                  { DS:$02EA, 16,410 bytes }
  { DS:$4FD6 -- the single working cell the lens gathers into. }
  Cell    : TCell;
  { DS:$563F -- THE FILE RECORD IS A GLOBAL. 1012:05d8 pushes DS:$563F to
    BlockRead and 1012:067b pushes the same address to Assign, in a DIFFERENT
    routine -- so the file is opened by one routine and read by another, the
    same split part 001 scene 2 turned out to have. }
  F       : file;                       { DS:$563F }
  { DS:$4304 -- the gather table, built once by BuildLens. }
  LensTab : TLensTab;

{ [transcribed] Scene 1 loads a 768-byte palette then a 320x200 screen
  straight into the virtual screen -- NEUROSIS.DAT $000000, 64,768 bytes. }
procedure LoadLogo;
var
  { THE PALETTE IS A LOCAL, and it was VGA's global. 1012:05dd is
    LEA DI,[BP-$400] / PUSH SS / PUSH DI / PUSH $300 / BlockRead -- an
    SS-relative buffer, so 768 bytes of frame and not a unit variable anywhere.

    That matters beyond this routine: VGA's `Palette` existed ONLY for this
    call, and the original's VGA has no such global -- every palette routine in
    segment 1491 takes a pointer parameter (1491:01c6 and 1491:01f6 are both
    LDS SI / LES DI off [BP+6]). Removing it took 768 bytes out of that unit's
    DGROUP, which is what a data-reference map had been reporting as a +768
    step between $AB58 and $ACEB. }
  Pal : array[0..767] of Byte;          { [BP-$400] }
begin
  Seek(F, 0);
  BlockRead(F, Pal, SizeOf(Pal));       { 1012:05ea }
  SetPalette768(@Pal);
  BlockRead(F, Mem[VirtScrSeg : 0], 64000);   { 1012:0601 }
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
{ @asm 001 1012:02bc }
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
{ @asm 001 1012:0311 }
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

  THE ORIGINAL WALKS ONE QUADRANT AND MIRRORS IT. X and Y each run 0 to 20 --
  twenty-one values, not twenty -- and every iteration writes FOUR entries,
  one per sign pairing, with SX and SY carrying the same signs as X and Y:

      Lens[( Y+20)*40 + ( X+20)] := ( SY+20)*40 + ( SX+20)   1012:01d8
      Lens[(-Y+20)*40 + (-X+20)] := (-SY+20)*40 + (-SX+20)   1012:0208
      Lens[(-Y+20)*40 + ( X+20)] := (-SY+20)*40 + ( SX+20)   1012:0240
      Lens[( Y+20)*40 + (-X+20)] := ( SY+20)*40 + (-SX+20)   1012:0274

  A previous reconstruction walked -20..19 once instead, on the argument that
  the formula is symmetric so one full pass is the same thing. For the 1600
  cells the blit reads it IS the same thing -- but it is not the same code,
  and it is not the same table: 0..20 mirrored reaches index 1640, which is
  why the table is 1641 words and why the loop bound above is 20 and not 19.
  It is also four times less square root: 441 evaluations instead of 1600.

  Two Real locals, not one. The frame is ENTER $1C (1012:0004) = 28 bytes:
  four Integers, two six-byte Reals, and two LongInt temporaries the compiler
  needs to reach `fild dword`. S is at [BP-$0E] and Scale at [BP-$14], and S
  is read exactly once, which is what says it is a variable and not a temp.

  LensR IS READ FROM MEMORY, so it cannot be an untyped constant here.
  1012:012e is `MOV AX,[$0002]` / `MUL WORD PTR [$0002]` -- had 40 been an
  untyped constant the compiler would have folded it to `MOV AX,1600`. The
  word at DS:$0002 in the shipped binary is initialised data and reads 40.
  Our own DGROUP puts this typed constant at a different offset; the shape
  matches, the address does not, and that is the whole of the difference.
  -------------------------------------------------------------------------- }
const
  LensK   = 1.0;       { CS:$0000, added as a single: 1012:014b FADD CS:[0] }
  LensCut = 300;       { the disc: X*X + Y*Y <= 300 -- 1012:003b CMP AX,$12C }
  LensOfs = 400;       { the 20*20 term inside the square root }
  LensArc = 20;        { one quadrant: 1012:02a8 CMP WORD PTR [BP-8],$14 }

const
  { WORD, not Integer, and the frame size is what proves it. 1012:0135 widens
    the product with `XOR DX,DX` -- unsigned -- and 1012:015e widens the bare
    LensR the same way into a LongInt temporary before `FILD DWORD`. An
    Integer would go to the x87 through `FILD WORD` with no temporary at all,
    and the frame would be ENTER $18 rather than the ENTER $1C at 1012:0004. }
  LensR : Word = 40;      { DS:$0002 -- read, never folded; see above }

procedure BuildLens;
var
  SX, SY, Y, X : Integer;
  S, Scale     : Real;
begin
  FillChar(LensTab, SizeOf(LensTab), 0);   { 1012:0008, 3282 bytes }
  for Y := 0 to LensArc do
    for X := 0 to LensArc do
    begin
      if X * X + Y * Y > LensCut then
      begin
        { OUTSIDE THE DISC -- the pixel maps to itself, and the original does
          not route that through SX and SY. 1012:0043 reads [BP-6] and [BP-8]
          straight into the index arithmetic, so the identity case carries its
          own four stores rather than falling into a shared tail. }
        LensTab[( Y + 20) * BounceW + ( X + 20)] := ( Y + 20) * BounceW + ( X + 20);
        LensTab[(-Y + 20) * BounceW + (-X + 20)] := (-Y + 20) * BounceW + (-X + 20);
        LensTab[(-Y + 20) * BounceW + ( X + 20)] := (-Y + 20) * BounceW + ( X + 20);
        LensTab[( Y + 20) * BounceW + (-X + 20)] := ( Y + 20) * BounceW + (-X + 20);
      end
      else
      begin
        { the sum is RECOMPUTED here, not held: the frame has room for four
          Integers and there are four, so the original has no D2 variable.
          1012:0116 repeats the two MULs the test at 1012:002b already did. }
        S     := Sqrt(LensR * LensR - (X * X + Y * Y - LensOfs)) + LensK;
        Scale := LensR / (LensR + S);
        SX    := Round(Scale * X);
        SY    := Round(Scale * Y);
        LensTab[( Y + 20) * BounceW + ( X + 20)] := ( SY + 20) * BounceW + ( SX + 20);
        LensTab[(-Y + 20) * BounceW + (-X + 20)] := (-SY + 20) * BounceW + (-SX + 20);
        LensTab[(-Y + 20) * BounceW + ( X + 20)] := (-SY + 20) * BounceW + ( SX + 20);
        LensTab[( Y + 20) * BounceW + (-X + 20)] := ( SY + 20) * BounceW + (-SX + 20);
      end;
    end;
end;

{ [transcribed] 1012:0366 -- gather the working cell for bouncer N out of the
  background saved under it, through the lens table. 1,600 bytes, walked
  backwards. }
procedure BuildCell(N : Integer);
var
  { ENTER 8 is eight bytes and the referenced slots are [BP-2], [BP-4], [BP-6]
    and [BP-7]. The odd one names the split: three Integers first, then two
    Bytes, of which [BP-8] is never read. 6 + 1 + 1 = 8.

    OUR BODY ONLY USES THE FIRST of them, where the original reads all four --
    so this routine still has a body defect and the declarations are only the
    frame half of it. They are transcribed because the frame is a prerequisite:
    while the ENTER operand is wrong the routine cannot align at all, and its
    four prologue bytes differ before any statement is reached. }
  I       : Integer;                    { [BP-2] }
  Spare1  : Integer;                    { [BP-4], read by the original }
  Spare2  : Integer;                    { [BP-6], read by the original }
  Spare3  : Byte;                       { [BP-7], read by the original }
  Spare4  : Byte;                       { [BP-8], never read }
begin
  for I := BounceH * BounceW - 1 downto 0 do
    Cell[I] := Under[N, LensTab[I]];
end;

{ Draw order per frame, from Bounce_Run: save the background, build the lens
  cell from it, blit it. Erasing is the same blit with the saved background as
  the source -- which is why the erase pass runs in REVERSE order. }
procedure DrawSprite(N, X, Y : Integer);
begin
  SaveUnder(X, Y, @Under[N], VirtScrSeg);
  BuildCell(N);
  BlitSprite(X, Y, @Cell, VirtScrSeg);
end;

procedure EraseSprite(N, X, Y : Integer);
begin
  BlitSprite(X, Y, @Under[N], VirtScrSeg);
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
  { A GLOBAL, because Bounce_Run's frame has no room for it: ENTER $54 is
    exactly the counter and the four arrays. }
  Frame : Integer;

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
{ @asm 001 1012:03bd }
{ NOT `assembler`. The original opens PUSH BP / MOV BP,SP and closes LEAVE,
  a stack frame it neither needs nor uses -- which is what a plain Pascal
  procedure whose body happens to be one asm block compiles to. Declared
  `assembler`, Turbo Pascal drops the frame for a routine with no parameters
  and no locals, and the transcription then differs from the binary at both
  ends while being identical in between. }
procedure ScrollLeft;
begin
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
end;

{ --------------------------------------------------------------------------
  Demo_Scene1 (1012:0678)

  ASSETS  NEUROSIS.DAT $000000, 64,768 bytes:
            assets/part001/logo_palette.pal    768 B
            assets/part001/asphyxia_logo.png   64,000 B -- the chrome/green
                                               ASPHYXIA logo with reflection
          See docs/14-part001-intro.md.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  1012:03e3 -- Bounce_Run.

  ITS FRAME IS ENTER $54 AND THAT IS THE WHOLE DECLARATION LIST: 2 + 4 * 20 is
  82, and 84 with the two bytes of padding. So the file record and the frame
  counter that used to share this routine cannot be here -- the file work
  belongs to Scene1 below, and Frame is a unit-level var.

  The offsets give the order, first declared nearest BP. Which array is which
  came from the BOUNDS TESTS rather than any name: the one checked against 299
  is X and the one checked against 179 is Y.
  -------------------------------------------------------------------------- }
procedure BounceRun;
var
  { THE COUNTER IS LAST, not first: 1012:03e7 writes 1 to [BP-$52], and the
    arrays are addressed [BP+DI-$16], -$2A, -$3E and -$52, which are their
    bases less the two bytes the compiler folds out of a 1-based subscript.
    So BDX sits nearest BP and I sits at the bottom.

    Which array is which came from the BOUNDS TESTS rather than any name: the
    one checked against 299 is X and the one against 179 is Y.

    Four arrays and the counter sum to 82; the routine opens ENTER $54, which
    is 84, so two more bytes sit below I and nothing reads them. }
  BDX    : array[1..NumBouncers] of Integer;   { base [BP-$14] }
  BDY    : array[1..NumBouncers] of Integer;   { base [BP-$28] }
  BX     : array[1..NumBouncers] of Integer;   { base [BP-$3C] }
  BY     : array[1..NumBouncers] of Integer;   { base [BP-$50] }
  I      : Integer;                            { [BP-$52] }
  Unread : Integer;                            { [BP-$54] }
begin
  for I := 1 to NumBouncers do
  begin
    BDX[I] := Random(3) + 2;
    BDY[I] := Random(3) + 2;
    BX[I]  := Random(250) + 30;
    BY[I]  := Random(150) + 30;
  end;

  CopyScreen(VirtScrSeg, $A000);

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

{ --------------------------------------------------------------------------
  The scene: load, draw the frame, then hand over to BounceRun.
  -------------------------------------------------------------------------- }
procedure Scene1;
var
  F : file;
begin
  BuildLens;
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  LoadLogo;                             { palette + 320x200 screen }
  Close(F);

  { Two black vertical lines down the right edge -- the artwork evidently
    has rubbish in its last two columns. }
  DrawLine(319, 199, 319, 0, 0, VirtScrSeg);
  DrawLine(318, 199, 318, 0, 0, VirtScrSeg);

  BounceRun;
end;

end.
