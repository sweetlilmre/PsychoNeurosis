{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the VGA unit.

  This is segment 1436 in NEUROSIS_002_fpu.exe, transcribed in full -- every
  routine in the segment, in address order, nothing inferred. Part 002 has its
  own copy of this unit and it is NOT the same as part 001's VGA.PAS: the
  staging buffer is a single global here, the palette helpers take pointers,
  and the row table is 320-stride rather than the Mode-X one in P2ModeX.
  =========================================================================== }

{$G+}   { 286 instructions: REP OUTSB and REP INSB in the two palette
          routines. The original targets 386 and above. }

unit P2VGA;

interface

const
  ScrWidth  = 320;
  ScrHeight = 200;
  VGASeg    = $A000;

var
  { DS:$A6B0 pointer, DS:$A6B4 its segment, DS:$A6B6 the row table. }
  Buffer    : Pointer;
  BufferSeg : Word;
  YOfs      : array[0..ScrHeight - 1] of Word;

procedure VirtScrAlloc;                              far;   { 1436:0006 }
procedure VirtScrFree;                               far;   { 1436:0033 }
procedure SetRGB(Col, R, G, B : Byte);               far;   { 1436:0048 }
procedure GetRGB(Col : Byte; var R, G, B : Byte);    far;   { 1436:0063 }
procedure SetPalette(P : Pointer);                   far;   { 1436:0083 }
procedure GetPalette(P : Pointer);                   far;   { 1436:009b }
procedure PaletteDim(P : Pointer);                   far;   { 1436:00b3 }
procedure PaletteFade(Pause : Word);                 far;   { 1436:00d6 }
procedure WaitRetrace;                               far;   { 1436:011a }
procedure CopyToPlane(SrcSeg, DestSeg : Word);       far;   { 1436:0128 }
procedure ClearSeg(Segment : Word; Colour : Byte);   far;   { 1436:0144 }
procedure BuildYOfs;                                        { 1436:015a }

implementation

uses Crt;      { 1436:010a calls Crt's Delay }

type
  TPalBuf = array[0..767] of Byte;

{ 1436:0006 -- GetMem(Buffer, 64000), copy the segment out to BufferSeg, then
  FillChar the whole thing with 0. }
procedure VirtScrAlloc;
begin
  GetMem(Buffer, 64000);
  BufferSeg := Seg(Buffer^);
  FillChar(Buffer^, 64000, 0);
end;

{ 1436:0033 -- FreeMem(Buffer, 64000). }
procedure VirtScrFree;
begin
  FreeMem(Buffer, 64000);
end;

{ --------------------------------------------------------------------------
  THE NEXT EIGHT ROUTINES ARE HAND ASSEMBLER IN THE BINARY. An earlier pass
  had the first five as Pascal; the audit put them back. The tells are the
  same throughout: DX is loaded once and walked with INC/ADD rather than
  reloaded per port, the bulk work goes through the string instructions, and
  none of them reserves a local.
  -------------------------------------------------------------------------- }

{ --------------------------------------------------------------------------
  1436:0048 -- out $3C8 := Col, then $3C9 := R, G, B.
  RET 8, so four word slots: Col at BP+$C (the FIRST declared), R at BP+$A,
  G at BP+8, B at BP+6.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := Col;
      Port[$3C9] := R;
      Port[$3C9] := G;
      Port[$3C9] := B;

  which compiles to four separate loads of DX; the original loads it once and
  steps it with a single INC.
  -------------------------------------------------------------------------- }
procedure SetRGB(Col, R, G, B : Byte); assembler;
asm
  MOV  DX, $3C8           { the DAC WRITE index register                   }
  MOV  AL, Col            { which entry                                    }
  OUT  DX, AL             { select it                                      }
  INC  DX                 { DX := $3C9, the DAC data register              }
  MOV  AL, R              { red, 0..63                                     }
  OUT  DX, AL             { the DAC takes the three in order and latches   }
  MOV  AL, G              { green                                          }
  OUT  DX, AL             {   the entry after the third                    }
  MOV  AL, B              { blue                                           }
  OUT  DX, AL             {                                                }
end;

{ --------------------------------------------------------------------------
  1436:0063 -- out $3C7 := Col, then three reads of $3C9 stored through the
  three var parameters. RET $E: Col at BP+$12, @R at BP+$E, @G at BP+$A,
  @B at BP+6.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C7] := Col;
      R := Port[$3C9];
      G := Port[$3C9];
      B := Port[$3C9];

  The original stores each byte with LES DI / STOSB rather than through the
  pointer, so the three var parameters are walked in declaration order and
  never held in a register together.
  -------------------------------------------------------------------------- }
procedure GetRGB(Col : Byte; var R, G, B : Byte); assembler;
asm
  MOV  DX, $3C7           { the DAC READ index register -- $3C7, not $3C8  }
  MOV  AL, Col            { which entry                                    }
  OUT  DX, AL             { select it                                      }
  ADD  DX, 2              { DX := $3C9, the DAC data register              }
  IN   AL, DX             { red                                            }
  LES  DI, R              { ES:DI := @R                                    }
  STOSB                   { store it                                       }
  IN   AL, DX             { green                                          }
  LES  DI, G              { ES:DI := @G                                    }
  STOSB                   { store it                                       }
  IN   AL, DX             { blue                                           }
  LES  DI, B              { ES:DI := @B                                    }
  STOSB                   { store it                                       }
end;

{ --------------------------------------------------------------------------
  1436:0083 -- out $3C8 := 0 then REP OUTSB 768 bytes from P^.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := 0;
      for I := 0 to 767 do Port[$3C9] := TPalBuf(P^)[I];

  REP OUTSB is one instruction for the whole 768; the Pascal loop is several
  per byte and shows as a visible step on a fade.
  -------------------------------------------------------------------------- }
procedure SetPalette(P : Pointer); assembler;
asm
  PUSH DS                 { DS is about to point at the caller's buffer    }
  LDS  SI, P              { DS:SI := the 768-byte palette                  }
  MOV  DX, $3C8           { the DAC WRITE index register                   }
  MOV  AL, 0              { start at colour 0                              }
  OUT  DX, AL             { select it -- the DAC auto-increments from here }
  INC  DX                 { DX := $3C9, the DAC data register              }
  MOV  CX, $300           { 768 bytes = 256 entries of R, G, B             }
  REP  OUTSB              { write them all out from DS:SI                  }
  POP  DS                 { restore our data segment                       }
end;

{ --------------------------------------------------------------------------
  1436:009b -- out $3C7 := 0 then REP INSB 768 bytes into P^.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C7] := 0;
      for I := 0 to 767 do TPalBuf(P^)[I] := Port[$3C9];
  -------------------------------------------------------------------------- }
procedure GetPalette(P : Pointer); assembler;
asm
  LES  DI, P              { ES:DI := where the palette is to go            }
  MOV  DX, $3C7           { the DAC READ index register                    }
  MOV  AL, 0              { start at colour 0                              }
  OUT  DX, AL             { select it                                      }
  ADD  DX, 2              { DX := $3C9, the DAC data register              }
  MOV  CX, $300           { 768 bytes                                      }
  REP  INSB               { read them all in to ES:DI                      }
end;

{ --------------------------------------------------------------------------
  1436:00b3 -- walk 768 bytes; every NON-ZERO one is decremented in place and
  written back, zeroes are stepped over (the JZ at 1436:00c3 skips the STOSB
  and just bumps DI). One step of a fade held in a palette buffer.

  It reads and writes the SAME buffer through two segment registers -- LES DI
  and LDS SI are both loaded from the one parameter -- so SI runs one byte
  ahead of DI and each decrement lands back where it came from.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 0 to 767 do
        if TPalBuf(P^)[I] <> 0 then Dec(TPalBuf(P^)[I]);
  -------------------------------------------------------------------------- }
procedure PaletteDim(P : Pointer); assembler;
asm
  PUSH DS                 { DS becomes the buffer's segment below          }
  LES  DI, P              { ES:DI := the buffer, for writing               }
  LDS  SI, P              { DS:SI := the same buffer, for reading          }
  MOV  CX, $300           { 768 bytes                                      }
@@Next:                   { <- once per component                          }
  LODSB                   { AL := this component; SI moves on              }
  OR   AL, AL             { already black?                                 }
  JZ   @@Skip             {   yes -- leave it alone                        }
  DEC  AL                 { one step darker                                }
  STOSB                   { write it back; DI moves on                     }
  DEC  CX                 { one byte done                                  }
  JNZ  @@Next             { round again                                    }
  JMP  @@Out              { finished                                       }
@@Skip:                   { <- the zero case: no store, so bump DI by hand }
  INC  DI                 { keep DI level with SI                          }
  DEC  CX                 { one byte done                                  }
  JNZ  @@Next             { round again                                    }
@@Out:                    { <- both exits                                  }
  POP  DS                 { restore our data segment                       }
end;

{ 1436:00d6 -- read the live palette into a 768-byte local, then 64 passes of
  WaitRetrace / PaletteDim / SetPalette / Delay(Pause). The counter runs 0..$3F
  at 1436:010f. }
procedure PaletteFade(Pause : Word);
var
  Buf  : TPalBuf;
  Step : Byte;
begin
  GetPalette(@Buf);
  Step := 0;
  repeat
    WaitRetrace;
    PaletteDim(@Buf);
    SetPalette(@Buf);
    Delay(Pause);
    Inc(Step);
  until Step = $3F;
end;

{ --------------------------------------------------------------------------
  1436:011a -- wait out any retrace in progress, then wait for the next one to
  start. No stack frame at all: the routine is four instructions and two
  loops.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      while (Port[$3DA] and 8) <> 0 do ;
      while (Port[$3DA] and 8) =  0 do ;

  Both halves matter. Waiting only for the second edge would return
  immediately if a retrace happened to be running already, and the caller
  would then draw into the visible part of the frame.
  -------------------------------------------------------------------------- }
procedure WaitRetrace; assembler;
asm
  MOV  DX, $03DA          { input status register 1                        }
@@InRetrace:              { <- spin while a retrace is already running     }
  IN   AL, DX             { read the status                                }
  TEST AL, 8              { bit 3 is vertical retrace                      }
  JNZ  @@InRetrace        { one is running -- wait it out                  }
@@WaitStart:              { <- then spin until the next one begins         }
  IN   AL, DX             { read again                                     }
  TEST AL, 8              { still bit 3                                    }
  JZ   @@WaitStart        { not yet -- keep waiting                        }
end;

{ --------------------------------------------------------------------------
  1436:0128 -- REP MOVSW of $7D00 words = 64,000 bytes, SI = DI = 0.
  DS comes from BP+8 and ES from BP+6, so the FIRST declared parameter is the
  SOURCE and the second the destination.

  There is no CLD. The original relies on the direction flag already being
  clear, which Turbo Pascal guarantees; an earlier transcription added one,
  which is harmless but is not what is there.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Move(Mem[SrcSeg : 0], Mem[DestSeg : 0], 64000);

  and that really is equivalent -- Move is itself a REP MOVSW. It is written
  out because the original is, and because Move would push six words for a
  call the original does not make.
  -------------------------------------------------------------------------- }
procedure CopyToPlane(SrcSeg, DestSeg : Word); assembler;
asm
  PUSH DS                 { DS becomes the source segment below            }
  MOV  AX, DestSeg        { the second declared parameter                  }
  MOV  ES, AX             { ES: is the destination                         }
  MOV  AX, SrcSeg         { the first                                      }
  MOV  DS, AX             { DS: is the source                              }
  XOR  SI, SI             { both start at offset 0 -- these are whole      }
  XOR  DI, DI             {   64,000-byte screens, not sub-rectangles      }
  MOV  CX, $7D00          { 32,000 words = 64,000 bytes = 320x200          }
  REP  MOVSW              { the blit, one instruction                      }
  POP  DS                 { restore our data segment                       }
end;

{ --------------------------------------------------------------------------
  1436:0144 -- REP STOSW of $7D00 words with the colour doubled into AX.
  ES comes from BP+8 and the colour from BP+6, so the segment is declared
  first. No CLD here either, for the same reason as above.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      FillChar(Mem[Segment : 0], 64000, Colour);
  -------------------------------------------------------------------------- }
procedure ClearSeg(Segment : Word; Colour : Byte); assembler;
asm
  MOV  CX, $7D00          { 32,000 words = 64,000 bytes                    }
  MOV  ES, Segment        { ES: is what gets filled                        }
  XOR  DI, DI             { from offset 0                                  }
  MOV  AL, Colour         { the fill byte                                  }
  MOV  AH, AL             { doubled into AX, so one STOSW does two pixels  }
  REP  STOSW              { the fill, one instruction                      }
end;

{ 1436:015a -- YOfs[I] := I * $140, for I = 0..$C7. Note this is the LINEAR
  320-byte stride, not the Mode-X one; P2ModeX keeps its own table. }
procedure BuildYOfs;
var
  Y : Integer;
begin
  for Y := 0 to ScrHeight - 1 do
    YOfs[Y] := Y * ScrWidth;
end;

{ 1436:017f -- the unit's initialisation calls BuildYOfs and nothing else. }
begin
  BuildYOfs;
end.
