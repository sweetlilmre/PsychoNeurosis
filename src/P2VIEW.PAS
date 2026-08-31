{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the 320x400 unit.

  Segment 140c in NEUROSIS_002_fpu.exe, transcribed in full -- all seven
  routines and the unit initialisation, nothing inferred.

  This is the OTHER video unit in part 002, and it is nothing like ModeX.
  Scene 2 runs unchained 320 x 400 with two pages stacked in the same 64K:

      [re] page 0   offset $0000        DS:$A696
      page 1   offset $4B00        DS:$A698     ($4B00 = 19,200 = 80 * 240)
      current  DS:$A69A            what Plot and FillRect write through

  80 bytes per plane-row, four planes, so 320 pixels across; the CRTC table
  below turns off the 200-line double scan and stretches the vertical timing
  to 400 lines, which is what makes room for two 320x200 pages.
  =========================================================================== }

unit P2View;

(* 286 CODE ON, so every routine here closes with one LEAVE instead of two
   instructions.

   [re] Every routine in segment 140c ends `LEAVE / RETF` -- 140c:01de
   is C9 CB -- and LEAVE is a 286 instruction that Turbo Pascal emits only
   under the G-plus switch; the G-minus epilogue is POP BP / RETF.

   [re] prologue.py reads this segment as G-minus and it is NOT WRONG so much as
   BLIND here: it decides by counting ENTER against PUSH BP, and NO routine in
   this unit declares a local, so both switches emit PUSH BP / MOV BP,SP and
   there is no ENTER for either to produce. With no locals the entry tells you
   nothing and only the EXIT does. *)
{$G+}

interface

const
  PlaneWidth = 80;         { bytes per plane per row }
  Page0Base  = $0000;      { 140c:01cf }
  Page1Base  = $4B00;      { 140c:01d2 }
  CrtcCount  = 10;         { the table below has ten entries }

type
  TCrtcTable = array[0..CrtcCount - 1] of Word;

var
  { BSS, AND THE ORIGINAL'S OWN CODE SETTLES IT: eighty-four references. The
    original addresses these as $A696, $A698 and $A69A -- twenty-two, seven
    and fifty-five sites, every one of them in the scene-2 renderers and the
    unit's own SetMode400. Made typed constants they moved to $0CE6..$0CEB and
    all eighty-four went with them.

    An earlier note here argued the other way, from the data image: declaring
    them `var` left dgimage reading 3,392 bytes against the original's 3,408,
    with the first difference at $0CE6, and six bytes of typed constant closed
    the first of it. That reasoning was backwards. The image is a weaker
    witness than a reference count, and the sixteen bytes it was pointing at
    are a separate hole -- initialised data the original has ahead of
    PageIndex that we do not, and which has to be found rather than filled
    with the nearest variables to hand. }
  PageBase  : array[0..1] of Word;    { DS:$A696, $A698 }
  WritePage : Word;                   { DS:$A69A }

  { DS:$A69C, and it follows the three above: $A69A + 2. SetMode400 fills this
    then hands it to SetMode. }
  Crtc : TCrtcTable;

const
  { [re] DS:$0CE6..$0CEB -- SIX BYTES OF INITIALISED DATA NOTHING REFERENCES, and
    they are the whole of part 002's data-image shortfall. The original's image
    is 3,408 bytes; without these it is 3,398, which pads to 3,408 -- so this
    one declaration accounts for all sixteen bytes the file was short.

    [re] The values are 0, $4B00, 0 -- Page0Base, Page1Base and a zero, the same
    three words the BSS trio above holds at run time. A search of the whole
    part finds NO instruction addressing $0CE6, $0CE8 or $0CEA: the two
    apparent hits at 108b:13af and 14b1:0f48 are `E8 0C` inside near-CALL
    displacements, which is what sent an earlier reading here down the wrong
    path entirely. So this is a dead copy -- most likely how the author first
    wrote the page table before the working variables moved to `var` -- and
    what is measured is its SIZE, its POSITION ahead of PageIndex, and its
    three values. Its name here is ours; the original's is not recoverable
    from the binary, because nothing names it. }
  DeadPageTable : array[0..2] of Word = (Page0Base, Page1Base, 0);

  { DS:$0CEC -- which of the two pages is being drawn into. Initialised data;
    the compiled-in value is 1. The renderers toggle it after every flip. }
  { [re] WORD, not Integer. The page swap at the end of every renderer is
    `INC AX / XOR DX,DX / MOV CX,2 / DIV CX` at 108b:0c8e -- zero-extend
    and an UNSIGNED divide, which is what `mod` on a Word compiles to.
    Declared Integer it came out `CWD` and `IDIV`, and that was the only
    difference left in all three renderer tails. }
  PageIndex : Word = 1;

{ [re] @asm 002 140c:0045 }
procedure SetMode400;                                        far;   { 140c:009c }
{ [re] @asm 002 140c:00b1 }
procedure Plot(X, Y : Integer; Colour : Byte);               far;   { 140c:00b1 }
{ [re] @asm 002 140c:00f4 }
procedure FlipPage(StartAddr : Word);                        far;   { 140c:00f4 }
{ [re] @asm 002 140c:011e }
procedure FillRect(X1, Y1, X2, Y2 : Integer;
                   Page : Word; Colour : Byte);              far;   { 140c:011e }
procedure SetRGB(Col, R, G, B : Byte);                       far;   { 140c:01af }

{ [re] The two nibble masks the planar span writers need. Scene 2's triangle filler
  at 108b:0461 reads its own copies from DS:$0676 and DS:$067A, which hold the
  same four bytes each as this unit's tables at DS:$0CF0 and DS:$0CF4. }
function LeftMaskOf(X : Integer) : Byte;
function RightMaskOf(X : Integer) : Byte;

implementation

const
  { DS:$0CEE -- initialised data, and SetMode reads it FROM MEMORY at
    140c:0078 (`MOV CX, [$0CEE]`), so it has to be a typed constant. A plain
    const would fold into the instruction as an immediate. }
  CrtcWrites : Word = CrtcCount;

  { 140c:014a / 140c:0155 -- DS:$0CF0 and DS:$0CF4, initialised data. }
  LeftMask  : array[0..3] of Byte = ($0F, $0E, $0C, $08);
  RightMask : array[0..3] of Byte = ($0F, $01, $03, $07);

function LeftMaskOf(X : Integer) : Byte;
begin
  LeftMaskOf := LeftMask[X and 3];
end;

function RightMaskOf(X : Integer) : Byte;
begin
  RightMaskOf := RightMask[X and 3];
end;

{ --------------------------------------------------------------------------
  140c:0000 -- ten CRTC index/value pairs written out longhand, one MOV each.
  As index:value they are the standard 320x400 unchained set:

      $06 := $0D    vertical total
      $07 := $3E    overflow
      $09 := $41    maximum scan line -- bit 7 clear, so NO double scan
      $10 := $EA    vertical retrace start
      $11 := $AC    vertical retrace end
      $12 := $DF    vertical display end
      $14 := $00    underline location -- dword mode off
      $15 := $E7    start vertical blank
      $16 := $06    end vertical blank
      $17 := $E3    mode control -- byte mode
  -------------------------------------------------------------------------- }
procedure FillCrtcTable(var T : TCrtcTable);
begin
  T[0] := $0D06;  T[1] := $3E07;  T[2] := $4109;  T[3] := $EA10;
  T[4] := $AC11;  T[5] := $DF12;  T[6] := $0014;  T[7] := $E715;
  T[8] := $0616;  T[9] := $E317;
end;

{ --------------------------------------------------------------------------
  Put the VGA into unchained 256-colour mode.

  [re] 140c:0045

  [re] INT $10, AX = $0013
      SEQ  $04 := $06          chain-4 off and odd/even off in one write
      SEQ  $00 := $01          synchronous reset
      MISC ($3C2) := $E3       clocks and polarity for 400 lines
      SEQ  $00 := $03          end reset
      CRTC $11 := v and $7F    unprotect registers 0..7
      write the ten table words to $3D4    count from DS:$0CEE
      SEQ  $02 := $0F          all planes
      clear $A000, $8000 words = 64K

  Note it never puts the CRTC write protect back.

  IT IS ONE ASSEMBLER ROUTINE, not two round a Pascal loop -- the ten table
  words go out through LODSW / OUT / LOOP with DX still holding $3D4 from the
  write-protect unlock above it. An earlier transcription split it in three,
  which reloaded DX and used a counted Pascal loop.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      asm mov ax,$13; int $10 end;
      PortW[$3C4] := $0604;  PortW[$3C4] := $0100;
      Port[$3C2]  := $E3;
      PortW[$3C4] := $0300;
      Port[$3D4]  := $11;  Port[$3D5] := Port[$3D5] and $7F;
      for I := 0 to CrtcCount - 1 do PortW[$3D4] := T[I];
      PortW[$3C4] := $0F02;
      FillChar(Mem[$A000 : 0], 65536, 0);
  -------------------------------------------------------------------------- }
procedure SetMode(var T : TCrtcTable); assembler;
asm
  PUSH DS                 { DS points at the caller's table below           }
  PUSH SI                 { and SI/DI are Turbo Pascal's to keep            }
  PUSH DI                 {                                                 }
  MOV  AX, $0013          { BIOS mode $13 first -- everything below         }
  INT  $10                {   reprograms it into 320x400 unchained          }

  MOV  DX, $03C4          { Sequencer address register                      }
  MOV  AX, $0604          { register 4 (Memory Mode) := $06: Chain-4 off    }
  OUT  DX, AX             {   and odd/even off, in one write                }
  MOV  AX, $0100          { register 0 (Reset) := $01: synchronous reset    }
  OUT  DX, AX             {   -- the timing is about to change              }

  MOV  DX, $03C2          { Miscellaneous Output register                   }
  MOV  AL, $E3            { clock select and both sync polarities negative, }
  OUT  DX, AL             {   which is what asks the monitor for 400 lines  }

  MOV  DX, $03C4          { back to the Sequencer                           }
  MOV  AX, $0300          { register 0 := $03: end the reset                }
  OUT  DX, AX             {                                                 }

  MOV  DX, $03D4          { CRTC address register                           }
  MOV  AL, $11            { register $11 -- Vertical Retrace End            }
  OUT  DX, AL             { select it                                       }
  INC  DX                 { DX := $3D5, the CRTC data register              }
  IN   AL, DX             { read it                                         }
  AND  AL, $7F            { clear bit 7: unprotect registers 0..7, which    }
  OUT  DX, AL             {   the table below needs to write                }

  DEC  DX                 { back to $3D4, the address register              }
  CLD                     { forwards through the table                      }
  LDS  SI, T              { DS:SI := the caller's ten index/value words     }
  MOV  CX, [CrtcWrites]   { DS:$0CEE -- ten                                 }
@@Pair:                   { <- once per register                            }
  LODSW                   { AX := index in AL, value in AH                  }
  OUT  DX, AX             { one 16-bit OUT does both halves                 }
  LOOP @@Pair             { next pair                                       }

  MOV  DX, $03C4          { Sequencer address register                      }
  MOV  AX, $0F02          { register 2 (Map Mask) := $0F, all four planes   }
  OUT  DX, AX             { so the clear below reaches every plane          }

  MOV  AX, $A000          { video memory                                    }
  MOV  ES, AX             {                                                 }
  SUB  DI, DI             { from offset 0                                   }
  SUB  AX, AX             { the fill value: black                           }
  MOV  CX, $8000          { $8000 words = 64K, which with four planes       }
  REP  STOSW              {   enabled is the whole 256K                     }

  POP  DI                 { restore what Turbo Pascal expects to survive    }
  POP  SI                 {                                                 }
  POP  DS                 {                                                 }
end;

{ Fill the row table, then set the mode from it. }
procedure SetMode400;
begin
  FillCrtcTable(Crtc);
  SetMode(Crtc);
end;

{ --------------------------------------------------------------------------
  140c:00b1 -- Plot(X, Y, Colour)

      offset := Y * 80 + (X shr 2) + WritePage
      Map Mask := 1 shl (X and 3)
      $A000:[offset] := Colour

  The Y * 80 is done as (Y shl 4) + (Y shl 6). RETF 6, so X is at BP+$A (the
  first declared), Y at BP+8, Colour at BP+6.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      PortW[$3C4] := ((Word(1) shl (X and 3)) shl 8) or $02;
      Mem[$A000 : Word(Y) * PlaneWidth + (Word(X) shr 2) + WritePage] :=
        Colour;

  The only real difference is the multiply: Turbo Pascal emits a MUL for
  Y * 80, the original emits six shifts and an add. No bounds test either
  way -- an off-screen Y simply lands somewhere else in the 64K.
  -------------------------------------------------------------------------- }
procedure Plot(X, Y : Integer; Colour : Byte); assembler;
asm
  MOV  AX, Y              { the row                                         }
  MOV  BX, AX             { keep a copy to shift separately                 }
  SHL  BX, 1              { Y * 2                                           }
  SHL  BX, 1              { Y * 4                                           }
  SHL  BX, 1              { Y * 8                                           }
  SHL  BX, 1              { Y * 16                                          }
  MOV  AX, BX             { AX := Y * 16                                    }
  SHL  BX, 1              { Y * 32                                          }
  SHL  BX, 1              { Y * 64                                          }
  ADD  AX, BX             { AX := Y*16 + Y*64 = Y * 80, no MUL anywhere     }
  MOV  BX, X              { the column                                      }
  SHR  BX, 1              { X / 2                                           }
  SHR  BX, 1              { X / 4 -- four pixels share a byte offset        }
  ADD  BX, AX             { + the row offset                                }
  ADD  BX, [WritePage]    { + 0 or $4B00, whichever page is being drawn     }
  MOV  AX, $A000          { video memory                                    }
  MOV  ES, AX             { ES:BX now addresses the pixel                    }
  MOV  CL, BYTE PTR X     { the column again, low byte only                 }
  AND  CL, 3              { X mod 4 = which of the four planes              }
  MOV  AX, $0102          { Sequencer register 2, mask $01 for plane 0      }
  SHL  AH, CL             { move the bit to the right plane                 }
  MOV  DX, $3C4           { Sequencer address register                      }
  OUT  DX, AX             { enable just that plane                          }
  MOV  AL, Colour         { the pixel value                                 }
  MOV  ES:[BX], AL        { write it                                        }
end;

{ --------------------------------------------------------------------------
  140c:00f4 -- FlipPage(StartAddr)

      wait while ($3DA and 1) <> 0        out of horizontal retrace
      CRTC $0D := lo(StartAddr)
      CRTC $0C := hi(StartAddr)
      wait while ($3DA and 8)  = 0        into vertical retrace

  Low byte first, then high, and both BEFORE the vertical retrace wait -- the
  wait afterwards is what stops the caller running ahead, not what protects
  the write.

  Both OUTs are prepared BEFORE the wait, in BX and CX, so the two writes
  land back to back with nothing between them -- which is the point of doing
  it this way rather than computing each as it goes.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      while (Port[$3DA] and 1) <> 0 do ;
      PortW[$3D4] := (Lo(StartAddr) shl 8) or $0D;
      PortW[$3D4] := (Hi(StartAddr) shl 8) or $0C;
      while (Port[$3DA] and 8)  = 0 do ;
  -------------------------------------------------------------------------- }
procedure FlipPage(StartAddr : Word); assembler;
asm
  MOV  BL, $0D            { CRTC register $0D: start address LOW            }
  MOV  BH, BYTE PTR StartAddr      { its value -- the low byte              }
  MOV  CL, $0C            { CRTC register $0C: start address HIGH           }
  MOV  CH, BYTE PTR StartAddr+1    { its value -- the high byte             }
  MOV  DX, $03DA          { input status register 1                         }
@@InHorz:                 { <- do not start mid horizontal retrace          }
  IN   AL, DX             { read the status                                 }
  TEST AL, 1              { bit 0 is display-enable/horizontal blank        }
  JNZ  @@InHorz           { wait it out                                     }
  MOV  DX, $03D4          { CRTC address register                           }
  MOV  AX, BX             { the low-byte pair, index and value together     }
  OUT  DX, AX             { one 16-bit OUT                                  }
  MOV  AX, CX             { the high-byte pair                              }
  OUT  DX, AX             { and again, immediately after                    }
  MOV  DX, $03DA          { input status register 1 again                   }
@@WaitVert:               { <- now hold the caller until the frame ends     }
  IN   AL, DX             { read the status                                 }
  TEST AL, 8              { bit 3 is vertical retrace                       }
  JZ   @@WaitVert         { not there yet -- keep waiting                   }
end;

{ --------------------------------------------------------------------------
  140c:011e -- FillRect(X1, Y1, X2, Y2, Page, Colour)

  A planar rectangle fill. The left and right edge bytes are written with
  partial Map Masks out of the two tables above, and the span between them
  with mask $0F, so a whole four-pixel column goes down in one STOSB.

      DI := Y1 * 80 + (X1 shr 2) + Page
      BH := LeftMask[X1 and 3]
      BL := RightMask[X2 and 3]
      if X2 <= X1 then exit
      CX := ((X2 - 1) - (X1 and $FFFC)) shr 2         middle byte count
      if CX = 0 then BH := BH and BL                  one byte wide
      SI := Y2 - Y1 ; if SI <= 0 then exit
      per row: left byte, middle run at mask $0F, right byte, DI += 80 - CX - 1

  RETF $C, six words. Highest first: X1 at BP+$10, Y1 at BP+$E, X2 at BP+$C,
  Y2 at BP+$A, Page at BP+8, Colour at BP+6.

  [re] IT USES BP AS A SCRATCH REGISTER. At 140c:017d, once every parameter has
  been read out of the frame, BP is loaded with the per-row skip (80 - CX - 1)
  and stays there to the end. That is why the routine pushes BP at the top
  and pops it at the bottom, and why nothing below that point can refer to a
  parameter by name -- there is no frame left to reach it through. It is also
  the single clearest reason this cannot be Pascal.

  The middle run is written as REP STOSW plus an ADC/REP STOSB tail: CX is
  halved, the carry out of the shift is added back to itself to give 0 or 1,
  and that many odd bytes follow the words. Two instructions instead of a
  branch.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if X2 <= X1 then Exit;
      Rows := Y2 - Y1;  if Rows <= 0 then Exit;
      D   := Word(Y1) * PlaneWidth + (Word(X1) shr 2) + Page;
      LM  := LeftMask[X1 and 3];
      RM  := RightMask[X2 and 3];
      Mid := ((X2 - 1) - (X1 and $FFFC)) shr 2;
      if Mid = 0 then LM := LM and RM;
      for R := 1 to Rows do
      begin
        Port[$3C4] := 2;  Port[$3C5] := LM;
        Mem[$A000 : D] := Colour;
        if Mid > 0 then
        begin
          Port[$3C5] := $0F;
          for I := 1 to Mid - 1 do Mem[$A000 : D + I] := Colour;
          Port[$3C5] := RM;
          Mem[$A000 : D + Mid] := Colour;
        end;
        Inc(D, PlaneWidth);
      end;
  -------------------------------------------------------------------------- }
procedure FillRect(X1, Y1, X2, Y2 : Integer; Page : Word; Colour : Byte);
  assembler;
asm
  PUSH SI                 { Turbo Pascal expects SI, DI and BP back         }
  PUSH DI                 {                                                 }
  PUSH BP                 { and BP is about to become a scratch register    }
  CLD                     { forwards                                        }
  MOV  AX, $50            { 80 bytes per plane-row                          }
  MUL  Y1                 { AX := Y1 * 80 -- the one MUL in the routine     }
  MOV  DI, X1             { the left edge, in pixels                        }
  SHR  DI, 1              { / 2                                             }
  SHR  DI, 1              { / 4 -- four pixels to a byte offset             }
  ADD  DI, AX             { + the row offset                                }
  ADD  DI, Page           { + 0 or $4B00, whichever page                    }
  MOV  AX, $A000          { video memory                                    }
  MOV  ES, AX             { ES:DI addresses the first byte of the rectangle }
  MOV  DX, $3C4           { Sequencer address register                      }
  MOV  AL, 2              { register 2 -- Map Mask                          }
  OUT  DX, AL             { select it once; only the data port is touched   }
  INC  DX                 {   from here, so DX := $3C5 and stays there      }
  MOV  SI, X1             { the left edge again                             }
  AND  SI, 3              { which pixel within its byte                     }
  MOV  BH, [SI + OFFSET LeftMask]   { the partial mask for that byte        }
  MOV  SI, X2             { the right edge                                  }
  AND  SI, 3              { which pixel within its byte                     }
  MOV  BL, [SI + OFFSET RightMask]  { the partial mask for that byte        }
  MOV  CX, X2             { right edge                                      }
  MOV  SI, X1             { left edge                                       }
  CMP  CX, SI             { is the rectangle inside out?                    }
  JLE  @@Out              {   yes -- nothing to draw                        }
  DEC  CX                 { the last pixel column, not one past it          }
  AND  SI, $FFFC          { round the left edge down to its byte            }
  SUB  CX, SI             { how many pixels the run spans                   }
  SHR  CX, 1              { / 2                                             }
  SHR  CX, 1              { / 4 = how many WHOLE bytes lie between the ends }
  JNZ  @@HaveMid          { there is a middle -- the two masks stay apart   }
  AND  BH, BL             { one byte wide: combine both edge masks into it  }
@@HaveMid:                { <- the general case joins here                  }
  MOV  SI, Y2             { the bottom edge                                 }
  SUB  SI, Y1             { SI := how many rows                             }
  JLE  @@Out              { none -- nothing to draw                         }
  MOV  AH, Colour         { the fill value, parked in AH for the whole loop }
  MOV  BP, $50            { 80 bytes per row...                             }
  SUB  BP, CX             {   less the middle bytes...                      }
  DEC  BP                 {   less the left byte = the skip to the next row }
                          { FROM HERE ON BP IS NOT A FRAME POINTER.        }
@@Row:                    { <- once per row of the rectangle                }
  PUSH CX                 { the middle count is consumed below              }
  MOV  AL, BH             { the left edge's partial mask                    }
  OUT  DX, AL             { enable just those planes                        }
  MOV  AL, AH             { the colour                                      }
  STOSB                   { write the left byte; DI moves on                }
  DEC  CX                 { one byte of the span accounted for              }
  JS   @@NextRow          { it was negative -- the left byte was all of it  }
  JZ   @@RightOnly        { zero -- no middle, just the right byte          }
  MOV  AL, $0F            { all four planes                                 }
  OUT  DX, AL             { the middle is full-width                        }
  MOV  AL, AH             { the colour                                      }
  SHR  CX, 1              { bytes -> words, carry holds the odd one         }
  REP  STOSW              { fill the middle two bytes at a time             }
  ADC  CX, CX             { CX := 0 or 1, the odd byte the shift dropped    }
  REP  STOSB              { and write it, if there was one                  }
@@RightOnly:              { <- one-byte-middle case joins here              }
  MOV  AL, BL             { the right edge's partial mask                   }
  OUT  DX, AL             { enable just those planes                        }
  MOV  AL, AH             { the colour                                      }
  STOSB                   { write the right byte                            }
@@NextRow:                { <- the degenerate case joins here               }
  ADD  DI, BP             { skip to the same column on the next row         }
  POP  CX                 { the middle count back for the next pass         }
  DEC  SI                 { one row done                                    }
  JNZ  @@Row              { round again                                     }
@@Out:                    { <- both early exits land here                   }
  POP  BP                 { BP is a frame pointer again                     }
  POP  DI                 {                                                 }
  POP  SI                 {                                                 }
end;

{ --------------------------------------------------------------------------
  140c:01af -- THE SECOND COPY OF THE DAC POKE, and it really is a second one.

  Part 002 carries this alongside VGA.SetRGB: it sits at linear $0426F where
  VGA's is at $043A8, so they are two distinct routines in the image and not
  a segment-range artefact. The bodies are identical; the DECLARATIONS are
  what cannot be shared, which is the same reason SetPalette768 is exempt.

  This reconstruction used to keep only one of them and point every caller at
  VGA.SetRGB. That is a deviation with a price: P2SOLID calls this EIGHTEEN
  times, and a far call encodes its target's segment AND offset, so every one
  of those sites differed in four bytes -- a run the coverage walk cannot
  forgive. P2SOLID's `uses` lists P2View after VGA, so simply declaring it here
  points those eighteen calls at the right routine.
  -------------------------------------------------------------------------- }
{ EQUIVALENT PASCAL -- REFERENCE ONLY, and not what is compiled:

      procedure SetRGB(Col, R, G, B : Byte);
      begin
        Port[$3C8] := Col;
        Port[$3C9] := R;  Port[$3C9] := G;  Port[$3C9] := B;
      end;

  which is the same five port writes, but reloads $3C9 each time where the
  original keeps DX and INCs it once. }
{$I SETRGB.INC}



{ 140c:01ca -- the unit's initialisation. }
begin
  { [re] THREE STORES AND NOTHING ELSE. 140c:01ca is `XOR AX,AX / MOV [$A696],AX
    / MOV WORD PTR [$A698],$4B00 / MOV AX,[$A696] / MOV [$A69A],AX`. There is
    no PageIndex assignment: DS:$0CEC arrives carrying 1 as INITIALISED DATA,
    which is a typed constant, not a var written here. }
  PageBase[0] := Page0Base;
  PageBase[1] := Page1Base;
  WritePage   := PageBase[0];
end.
