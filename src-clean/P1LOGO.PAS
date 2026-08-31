{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 1, the logo and bouncing sprites

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit P1LOGO;
{$A-}   { BYTE ALIGNMENT, AND THE ORIGINAL'S OWN ADDRESSES PROVE IT. Under sits
          at the ODD $02EA and F at the ODD $563F -- 1,641-byte Cell ends at
          $563E and the original puts F straight after it with no gap. Word
          alignment, which is TP7's default, pads before both: ours had F at
          $5642 against $563F, and the padding accumulated down the block.
          $A is a whole-file switch in TP7, so it goes here at the head. }
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

{$G+}   { 286: every framed routine in 1012 opens ENTER, e.g. Bounce_Run
          the bouncer loop's frame. }
{ 80x87 code on: the lens table is built in floating point. }
{$N+}

interface

procedure Scene1;

implementation

uses VGA, Crt, DemoVT;

const
  NumBouncers = 10;
  BounceW     = 40;        { blits 40 rows of 40 bytes }
  BounceH     = 40;

const
  LensK   = 1.0;       { the lens's strength                              }
  LensCut = 300;       { the disc: a pixel is inside if X*X + Y*Y <= 300 }
  LensOfs = 400;       { the 20*20 term inside the square root }
  LensArc = 20;        { the lens's radius in pixels, one quadrant       }

const
  LensR : Word = 40;      { read, never folded; see above }

type
  TSaveBank = array[1..NumBouncers, 0..BounceW * (BounceH + 1)] of Byte;
  { 1641 BYTES, the same as a bank row and the same as the lens table, for the
    same reason: LensTab[I] subscripts both. And it tiles -- Cell at $4FD6 plus
    1641 is $563F, which is where the file record is. }
  TCell     = array[0..BounceW * (BounceH + 1)] of Byte;
  TLensTab  = array[0..BounceW * (BounceH + 1)] of Word;

var
  { The saved background under each bouncer. There is NO sprite bitmap: the
    bouncers are lenses over whatever they are sitting on. }
  { INLINE IN DGROUP, not on the heap. This was `^TSaveBank` with
    a GetMem, which is four bytes where the original has 16,410, and it is most
    of why every absolute data displacement in this part was wrong: the MZ
    header asks the loader for 16,704 bytes more uninitialised space than our
    build did. }
  {    DELETING Spare0 PUT ALL FIVE PUSHED ADDRESSES ON THE ORIGINAL'S: $4304,
    $4FD6 and $563F against $4306, $4FD8 and $5642 before it, and dsmap went from
    106 sites at +2 to 219 at +0 across $0000..$ACFC. P1BALLS's byte-level
    difference fell from 119 to 15 with no code change anywhere. }
  Under   : TSaveBank;                  { 16,410 bytes; folds to $02EA }
  { the gather table, built once by BuildLens. AND IT COMES SECOND,
    which the four addresses already in these comments tile out exactly:
    Under at $02EA plus 16,410 is $4304, plus LensTab's 3,282 is $4FD6, plus
    Cell's 1,641 is $563F, which is F. Declared Cell-F-LensTab instead, the
    block ran 129 bytes long and dsmap reported one bounded +4864 run over
    $433B..$56C0 with zero either side -- a misplaced block, not a shift. }
  LensTab : TLensTab;                   { 3,282 bytes }
  { the single working cell the lens gathers into. }
  Cell    : TCell;                      { 1,641 bytes }
  F       : file;

{ [transcribed] Scene 1 loads a 768-byte palette then a 320x200 screen
  straight into the virtual screen -- NEUROSIS.DAT $000000, 64,768 bytes. }
{ --------------------------------------------------------------------------
build the lens table.

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

      X*X + Y*Y <= 300   the lens proper:

                             Scale := R / (R + Sqrt(R*R - (X*X + Y*Y - 400)) + K)
                             SX    := Round(Scale * X)
                             SY    := Round(Scale * Y)

                         with R = 40 and K = 1.0, so

                             Scale = 40 / (41 + Sqrt(2000 - (X*X + Y*Y)))

                         which runs from about 0.467 at the centre to 0.486 at
                         the rim -- a roughly even 2x magnification with a
                         slight barrel to it.

  THE ORIGINAL WALKS ONE QUADRANT AND MIRRORS IT. X and Y each run 0 to 20 --
  twenty-one values, not twenty -- and every iteration writes FOUR entries,
  one per sign pairing, with SX and SY carrying the same signs as X and Y:

      Lens[( Y+20)*40 + ( X+20)] := ( SY+20)*40 + ( SX+20)
      Lens[(-Y+20)*40 + (-X+20)] := (-SY+20)*40 + (-SX+20)
      Lens[(-Y+20)*40 + ( X+20)] := (-SY+20)*40 + ( SX+20)
      Lens[( Y+20)*40 + (-X+20)] := ( SY+20)*40 + (-SX+20)

  A previous reconstruction walked -20..19 once instead, on the argument that
  the formula is symmetric so one full pass is the same thing. For the 1600
  cells the blit reads it IS the same thing -- but it is not the same code,
  and it is not the same table: 0..20 mirrored reaches index 1640, which is
  why the table is 1641 words and why the loop bound above is 20 and not 19.
  It is also four times less square root: 441 evaluations instead of 1600. }

procedure BuildLens;
var
  SX, SY, Y, X : Integer;
  S, Scale     : Real;
begin
  FillChar(LensTab, SizeOf(LensTab), 0);   { 3282 bytes }
  for Y := 0 to LensArc do
    for X := 0 to LensArc do
    begin
      if X * X + Y * Y > LensCut then
      begin
        LensTab[( X + 20) + ( Y + 20) * BounceW] := ( X + 20) + ( Y + 20) * BounceW;
        LensTab[(-X + 20) + (-Y + 20) * BounceW] := (-X + 20) + (-Y + 20) * BounceW;
        LensTab[( X + 20) + (-Y + 20) * BounceW] := ( X + 20) + (-Y + 20) * BounceW;
        LensTab[(-X + 20) + ( Y + 20) * BounceW] := (-X + 20) + ( Y + 20) * BounceW;
      end
      else
      begin
        S     := Sqrt(LensR * LensR - (X * X + Y * Y - LensOfs)) + LensK;
        Scale := LensR / (S + LensR);
        SX    := Round(Scale * X);
        SY    := Round(Scale * Y);
        LensTab[( X + 20) + ( Y + 20) * BounceW] := ( SX + 20) + ( SY + 20) * BounceW;
        LensTab[(-X + 20) + (-Y + 20) * BounceW] := (-SX + 20) + (-SY + 20) * BounceW;
        LensTab[( X + 20) + (-Y + 20) * BounceW] := ( SX + 20) + (-SY + 20) * BounceW;
        LensTab[(-X + 20) + ( Y + 20) * BounceW] := (-SX + 20) + ( SY + 20) * BounceW;
      end;
    end;
end;

{ --------------------------------------------------------------------------
gather the working cell through the lens table. HAND ASSEMBLER.

  THE ADDRESSES ALSO TILE, and that is what identifies the frame's four slots:

 IMUL DI,N,$669 then LEA AX,[DI-$37F]  =  Ofs(Under[N])
               $669 is 1641, a saved cell; N * 1641 - 895 is a ONE-based
               array whose element 1 sits at $2EA, which is Under
 $4FD6  =  Ofs(Cell)
 $4304  =  Ofs(LensTab), and $4304 - $2EA is 16,410,
               which is ten rows of 1641 -- so Under has ten of them
 a Byte, zeroed at the top of every iteration

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 1599 downto 0 do
        Cell[I] := Under[N, LensTab[I]];
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
  XOR  BL, BL
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
  XOR  CH, CH
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
  The ten bouncing sprites -- Bounce_Run, with a paired blit and save so each
  sprite restores the background it covered.

  Transcribed. An earlier reconstruction had the right IDEA -- save the
  background, draw, restore in reverse -- but the wrong numbers:

  * the sprites are 40 x 40, not 20 x 20;
  * they are drawn CENTRED, at (X - 20, Y - 20);
  * the blit is opaque (REP MOVSB), with no transparency test;
  * save and restore are the SAME routine, just with source and destination
    swapped -- restoring is a blit out of the saved-background buffer.

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
  XOR  BL, BL
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
  XOR  CH, CH
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
build the lens table.

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

      X*X + Y*Y <= 300   the lens proper:

                             Scale := R / (R + Sqrt(R*R - (X*X + Y*Y - 400)) + K)
                             SX    := Round(Scale * X)
                             SY    := Round(Scale * Y)

                         with R = 40 and K = 1.0, so

                             Scale = 40 / (41 + Sqrt(2000 - (X*X + Y*Y)))

                         which runs from about 0.467 at the centre to 0.486 at
                         the rim -- a roughly even 2x magnification with a
                         slight barrel to it.

  THE ORIGINAL WALKS ONE QUADRANT AND MIRRORS IT. X and Y each run 0 to 20 --
  twenty-one values, not twenty -- and every iteration writes FOUR entries,
  one per sign pairing, with SX and SY carrying the same signs as X and Y:

      Lens[( Y+20)*40 + ( X+20)] := ( SY+20)*40 + ( SX+20)
      Lens[(-Y+20)*40 + (-X+20)] := (-SY+20)*40 + (-SX+20)
      Lens[(-Y+20)*40 + ( X+20)] := (-SY+20)*40 + ( SX+20)
      Lens[( Y+20)*40 + (-X+20)] := ( SY+20)*40 + (-SX+20)

  A previous reconstruction walked -20..19 once instead, on the argument that
  the formula is symmetric so one full pass is the same thing. For the 1600
  cells the blit reads it IS the same thing -- but it is not the same code,
  and it is not the same table: 0..20 mirrored reaches index 1640, which is
  why the table is 1641 words and why the loop bound above is 20 and not 19.
  It is also four times less square root: 441 evaluations instead of 1600. }

procedure BuildCell(N : Integer); assembler;
var
  CellOfs : Word;
  SrcBase : Word;
  LensOfs : Word;
  Bias    : Byte;
  Spare   : Byte;                       { never read }
asm
        IMUL    DI, N, 1641                 { N * $669           }
        { SYMBOLIC, AND THE LITERAL -895 WAS A REAL BUG. The original's
          instruction is LEA AX,[DI-$37F], and -895 is 1641 - 746 where 746 is
          where ITS Under sits. Transcribing the CONSTANT rather than its
          MEANING made this routine read from $02EA while our Under is at
          $02E8 -- two bytes into every saved row -- so every lens gathered
          its pixels two columns off and the bouncing sprites came out
          visibly wrong on a watched run while all four instruments passed.
          A hardcoded address in an asm block is only correct by coincidence;
          write what the number MEANS and it survives the next reorder. }
        LEA     AX, [DI + OFFSET Under - 1641]   { 036f  = Ofs(Under[N])     }
        MOV     SrcBase, AX
        MOV     CX, 1600                { 0376  40 x 40                     }
        DEC     CX                      { 0379    counted from 1599 down    }
        MOV     WORD PTR CellOfs, OFFSET Cell     { 037a  $4FD6             }
        MOV     WORD PTR LensOfs, OFFSET LensTab  { 037f  $4304             }
@@Pixel:
        MOV     BYTE PTR Bias, 0        { 0384  <- once per pixel           }
        MOV     BX, CX
        SHL     BX, 1                   { 038a  a word index                }
        ADD     BX, LensOfs
        MOV     AX, [BX]                { 038f  AX := LensTab[I]            }
        CMP     AX, CX                  { 0391  DEAD: sets the bias to zero }
        JE      @@Same                  { 0393    when it is already zero   }
        MOV     BYTE PTR Bias, 0
@@Same: CMP     AX, 1640                { 0399  DEAD: adds zero to it       }
        JNE     @@Gather
        ADD     BYTE PTR Bias, 0
@@Gather:
        MOV     BX, SrcBase
        ADD     BX, AX                  { 03a5  + the lens offset           }
        MOV     AL, [BX]                { 03a7  the saved pixel             }
        MOV     BX, CX
        ADD     BX, CellOfs
        ADD     AL, Bias                { 03ae  and the bias is always 0    }
        MOV     [BX], AL
        DEC     CX
        CMP     CX, -1
        JG      @@Pixel
end;

{ Draw order per frame, from Bounce_Run: save the background, build the lens
  cell from it, blit it. Erasing is the same blit with the saved background as
  the source -- which is why the erase pass runs in REVERSE order. }

{ ===========================================================================
  Scene 1 -- logo and bouncing sprites
  =========================================================================== }

const
  BounceMinX  = 21;   BounceMaxX = 299;
  BounceMinY  = 21;   BounceMaxY = 179;
  BounceFrames = 300;      { the scene's whole lifetime, in frames       }
  ScrollFrom   = 140;      { after this frame the logo slides out        }
  ScrollStep   = 2;        { pixels per frame }

{ --------------------------------------------------------------------------
ScrollLeft

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
  MOV  DS, [VirtScrSeg]
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
  Demo_Scene1

  ASSETS  NEUROSIS.DAT $000000, 64,768 bytes:
            assets/part001/LOGOPAL.PAL    768 B
            assets/part001/ASPHLOGO.PNG   64,000 B -- the chrome/green
                                               ASPHYXIA logo with reflection
          See docs/14-part001-intro.md.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  Bounce_Run.

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
  {    A FOURTH ATTEMPT AT CONVERTING IT CLOSED THIS SPAN AND COST 47 BYTES, and
    the reason is now located rather than guessed. With the loop using a local,
    the unit-level Frame is referenced by nothing, Turbo Pascal smart-links it
    away, and this unit's data block loses two bytes: the original's absolute
    references run $56C0, $56C2 ... $56D0 and ours came out $56BE, $56C2 ...
    $56CC, two low throughout.

    BOTH THINGS ARE TRUE AT ONCE. The counter is a local AND two bytes of this
    unit's data need a home something references. Every previous attempt chose
    between them.

    AND THE TWO BYTES ARE NOT A VARIABLE IN THE ORIGINAL. $56C0's only two
    references are from segment 1082, so it is P1TITLE's; nothing anywhere reads
    $56BF. F sits at $563F and is 128 bytes, ending at $56BE, so $56BF is odd
    and word alignment pads it to $56C0 -- one byte of padding, not a variable.

    MEASURED AGAIN ON 27 Aug 2026, AND THE SIGN IN THE PARAGRAPH ABOVE IS THE
    OTHER WAY ROUND NOW. Five sites in this unit push a data address as
    MOV DI,imm / PUSH DS / PUSH DI, so the three big ones can be read straight
    out of both images:

        LensTab   original $4304   ours $4306    +2
        Cell      original $4FD6   ours $4FD8    +2
        F         original $563F   ours $5642    +3

    So ours is two bytes HIGH from LensTab onwards -- not two low -- and gains a
    THIRD byte between Cell and F. Cell is 1,641 bytes: the original runs
    $4FD6..$563E and puts F at the odd $563F with no padding, while ours runs
    $4FD8..$5640 and puts F at $5642, so ours pads and the original does not.
    dsmap agrees on the first part, reporting a clean boundary -- shift +0 below
    $56C0 and +2 across $56C4..$ACFC, 106 sites.

    THAT IS TWO DEFECTS, NOT ONE, and the earlier reading of "two low" was taken
    from a build that has since changed underneath it. Two bytes too many before
    LensTab, and one byte of padding before F that the original does not have.
    Frame is 2 bytes and cannot account for 3. Whatever it is standing in for,
    the arithmetic no longer works, so re-derive rather than trusting the
    paragraph above -- and note that the chain quoted further up this file
    ("Under at $02EA plus 16,410 is $4304") adds a FOLD base to a size, which
    tiles self-consistently and is not a layout. Read the five pushed addresses;
    they are the only unambiguous numbers here.

    Carried by p1s1-hardcoded-lens-base, whose own note says the hardcoded lens
    displacement will emit the original's -895 by itself once these bytes are
    found. Converting the loop to a local before that will always cost the same
    47. }
  BDX    : array[1..NumBouncers] of Integer;   { base one per bouncer }
  BDY    : array[1..NumBouncers] of Integer;   { base one per bouncer }
  BX     : array[1..NumBouncers] of Integer;   { base one per bouncer }
  BY     : array[1..NumBouncers] of Integer;   { base one per bouncer }
  I      : Integer;
  Frame  : Integer;                            { the `for` variable }
begin
  for I := 1 to NumBouncers do
  begin
    BDX[I] := Random(3) + 2;
    BDY[I] := Random(3) + 2;
    BX[I]  := Random(250) + 30;
    BY[I]  := Random(150) + 30;
  end;

  BuildLens;

  for Frame := 1 to BounceFrames do
  begin
    for I := 1 to NumBouncers do
    begin
      SaveUnder(BX[I], BY[I], @Under[I], VirtScrSeg);
      BuildCell(I);
      BlitSprite(BX[I], BY[I], @Cell, VirtScrSeg);
    end;
    CopyScreen(VirtScrSeg, $A000);
    { erase in REVERSE order so overlapping sprites restore correctly }
    for I := NumBouncers downto 1 do
      BlitSprite(BX[I], BY[I], @Under[I], VirtScrSeg);

    for I := 1 to NumBouncers do
    begin
      BX[I] := BX[I] + BDX[I];
      BY[I] := BY[I] + BDY[I];
      if BX[I] < BounceMinX then BDX[I] := -BDX[I];
      if BX[I] > BounceMaxX then BDX[I] := -BDX[I];
      if BY[I] < BounceMinY then BDY[I] := -BDY[I];
      if BY[I] > BounceMaxY then BDY[I] := -BDY[I];
    end;

    if KeyPressed then
    begin
      ReadKey;
      Exit;
    end;

    if Frame > ScrollFrom then ScrollLeft;
  end;
end;

procedure LoadLogo(Name : String; Dest : Pointer);
var
  Pal    : array[0..767] of Byte;
  I      : Integer;
  Unread : file;                        { never opened }
begin
  BlockRead(F, Pal, SizeOf(Pal));
  BlockRead(F, VirtScr^, 64000);
  for I := 0 to 255 do
    SetRGB(I, Pal[I * 3], Pal[I * 3 + 1], Pal[I * 3 + 2]);
end;

{ --------------------------------------------------------------------------
  SaveUnder(X, Y, Dest, Segment). HAND ASSEMBLER, verbatim.

  Copies the 40 x 40 block centred on (X, Y) out of Segment into Dest.

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
{ --------------------------------------------------------------------------
  The scene: load, draw the frame, then hand over to BounceRun.
  -------------------------------------------------------------------------- }
procedure Scene1;

begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  LoadLogo('asphyxia.cel', VirtScr);
  Close(F);

  { Two black vertical lines down the right edge -- the artwork evidently
    has rubbish in its last two columns. }
  DrawLine(319, 0, 319, 199, 0, VirtScrSeg);
  DrawLine(318, 0, 318, 199, 0, VirtScrSeg);

  CopyScreen(VirtScrSeg, $A000);
  BounceRun;
end;

begin
end.
