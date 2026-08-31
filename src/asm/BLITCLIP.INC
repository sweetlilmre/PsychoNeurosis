(* ===========================================================================
  BLITCLIP.INC -- the clipped transparent sprite blit, HAND ASSEMBLER, verbatim.

  ONE TEXT, INCLUDED BY EVERY UNIT THAT NEEDS IT. Two units compile this same
  blitter into their own code segment: P1BALLS for part 001 scene 4's grid of
  144 balls, and P6TILES for part 006's tumbling cell grid.

  IT WAS NEVER A SHARED UNIT, and that is worth knowing because it looks like
  one. In part 001 the blitter sits in the middle of the scene 4 unit's own
  code rather than at the head of a segment of its own -- so it was shared
  source TEXT compiled into each unit separately, which is what an include
  does and what this file is.

  [re] The demo compiles this same blitter into more than one part, each part
  getting its own copy in its own segment:
      part 001  1107:0199  P1BALLS.PAS   scene 4's grid of 144 balls
      part 006  100f:0000  P6TILES.PAS   the tumbling cell grid
  Byte for byte and instruction for instruction between the two -- part 001's
  addresses are part 006's plus $199. In part 001 it sits BETWEEN Banner_Load
  ($0025) and DrawBlobs ($0245), inside the scene 4 unit's own code rather
  than at the head of a segment of its own, so the original was not a shared
  UNIT: it was shared source text compiled into each unit separately, which is
  what an include does and what this file is.

  A shared unit would also be wrong on the bytes: one copy in one segment
  turns the other callers' near calls into far ones.

  THE INCLUDE CARRIES THE WHOLE PROCEDURE, header and all, because Turbo Pascal
  refuses an include INSIDE an asm block -- "Error 118: Include files are not
  allowed here". At declaration level it is fine, so the file starts at the
  procedure header and the including unit writes one line.

  [re] Each including unit writes the marker, because the address is the part's,
  and names the routine in the marker so asmverify still byte-checks it:
      { @asm 001 1107:0199 +170 Blit }
      {$I BLITCLIP.INC}

  WHAT THE INCLUDING UNIT MUST PROVIDE:

    * {$G+}, for the ENTER the frame needs.
    * VGA's YOfs row table in scope.
    * the four clip bounds as TYPED constants, so they are read out of DGROUP
      the way the binary reads them rather than folded into an instruction:
      ClipTop, ClipBottom, ClipLeft, ClipRight : Integer. The VALUES are the
      part's own -- 0/199/0/319 in part 001, 5/195/5/315 in part 006 -- and so
      is the order they are declared in, which follows each binary's DGROUP.

  THE OFFSETS IN THE COMMENTS ARE RELATIVE TO THE ROUTINE'S OWN START, because
  the two parts sit at different addresses. +$00 is the ENTER the compiler
  emits, so the first instruction here is +$04; add the base from the table.

  WHAT IT DOES. The sprite carries its own size in its first two bytes and
  colour 0 is transparent. Clipping moves the pointers rather than testing
  each pixel: the top rows go in one MUL, the left and right margins become
  two per-row skips held in the frame, and anything wholly outside leaves
  through the same exit.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      W := S^.W;  H := S^.H;
      clip H and the source start against the top edge,
      clip H against the bottom edge,
      clip W and record SkipLeft/SkipRight against the two side edges;
      for each remaining row, for each remaining column, copy the byte unless
      it is zero, then step DI on by 320 - W.

  It cannot be written that way: the row table is indexed straight off BX, the
  transparent case bumps DI rather than branching around a store, and the clip
  bounds are four DGROUP words the routine reads directly.
  =========================================================================== *)
procedure Blit(S : Pointer; X, Y : Integer; Segment : Word); assembler;
var
  SkipLeft, SkipRight : Integer;  { [BP-2], [BP-4] }
  Spare               : Integer;  { [BP-6] -- ENTER $0006 reserves a third
                                    word that the routine never touches }
asm
  PUSH DS                { +$04                                              }
  MOV  AX, Segment       { +$05                                              }
  MOV  ES, AX            { +$08  ES:DI is the destination                    }
  LDS  SI, S             { +$0a  DS:SI is the sprite                         }
  XOR  DH, DH            { +$0d                                              }
  MOV  DL, [SI+1]        { +$0f  DL := the height                            }
  XOR  CH, CH            { +$12                                              }
  MOV  CL, [SI]          { +$14  CL := the width                             }
  POP  DS                { +$16  DGROUP again, for the clip bounds           }
  MOV  SkipLeft, 0       { +$17                                              }
  MOV  SkipRight, 0      { +$1c                                              }
  MOV  BX, Y             { +$21                                              }
  MOV  AX, ClipTop       { +$24  the top edge                                }
  SUB  AX, BX            { +$27  how far above it we start                   }
  JLE  @@TopOK           { +$29                                              }
  CMP  AX, DX            { +$2b                                              }
  JGE  @@Out             { +$2d  the whole sprite is above the window        }
  SUB  DX, AX            { +$2f  drop that many rows                         }
  ADD  BX, AX            { +$31                                              }
  MOV  DI, DX            { +$33  MUL clobbers DX, so park the height         }
  MUL  CX                { +$35  rows-skipped * width                        }
  MOV  DX, DI            { +$37                                              }
  ADD  SI, AX            { +$39  and step the source past them               }
@@TopOK:
  MOV  AX, ClipBottom    { +$3b  the bottom edge                             }
  SUB  AX, BX            { +$3e                                              }
  JLE  @@Out             { +$40                                              }
  CMP  AX, DX            { +$42                                              }
  JGE  @@RowsOK          { +$44                                              }
  INC  AX                { +$46                                              }
  MOV  DX, AX            { +$47  clip the height                             }
@@RowsOK:
  ADD  BX, BX            { +$49                                              }
  MOV  DI, [BX + OFFSET YOfs]  { +$4b  the VGA unit's row table, a fixed      }
                         {   DGROUP offset in each binary                    }
  MOV  BX, X             { +$4f                                              }
  ADD  DI, BX            { +$52                                              }
  MOV  AX, ClipLeft      { +$54  the left edge                               }
  SUB  AX, BX            { +$57                                              }
  JLE  @@LeftOK          { +$59                                              }
  CMP  AX, CX            { +$5b                                              }
  JGE  @@Out             { +$5d  wholly off the left                         }
  MOV  SkipLeft, AX      { +$5f  skip this many bytes of each row            }
  ADD  DI, AX            { +$62                                              }
  SUB  CX, AX            { +$64                                              }
@@LeftOK:
  MOV  AX, ClipRight     { +$66  the right edge                              }
  SUB  AX, BX            { +$69                                              }
  JLE  @@Out             { +$6b                                              }
  CMP  AX, CX            { +$6d                                              }
  JGE  @@WidthOK         { +$6f                                              }
  SUB  CX, AX            { +$71                                              }
  MOV  SkipRight, CX     { +$73                                              }
  MOV  CX, AX            { +$76                                              }
@@WidthOK:
  MOV  BX, CX            { +$78  BX keeps the clipped width                  }
  PUSH DS                { +$7a                                              }
  PUSH SI                { +$7b                                              }
  LDS  SI, S             { +$7c  DS := the sprite's segment...               }
  POP  SI                { +$7f    ...but keep the stepped SI                }
  ADD  SI, 2             { +$80  past the width/height bytes                 }
  CLD                    { +$83                                              }
@@Row:
  ADD  SI, SkipLeft      { +$84                                              }
@@Pixel:
  LODSB                  { +$87                                              }
  OR   AL, AL            { +$88                                              }
  JZ   @@Clear           { +$8a  colour 0 is transparent                     }
  STOSB                  { +$8c                                              }
  DEC  CL                { +$8d                                              }
  JNZ  @@Pixel           { +$8f                                              }
  JMP  @@EndRow          { +$91                                              }
@@Clear:
  INC  DI                { +$93  step over it instead of storing             }
  DEC  CL                { +$94                                              }
  JNZ  @@Pixel           { +$96                                              }
@@EndRow:
  ADD  SI, SkipRight     { +$98                                              }
  MOV  CX, BX            { +$9b                                              }
  ADD  DI, 140h          { +$9d  next screen row...                          }
  SUB  DI, BX            { +$a1    ...less what we just wrote                }
  DEC  DL                { +$a3                                              }
  JNZ  @@Row             { +$a5                                              }
  POP  DS                { +$a7                                              }
@@Out:
end;
