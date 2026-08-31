{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the shared VGA unit.

  THE SCREEN, THE PALETTE AND THE DRAWING PRIMITIVES every part is built on:
  set the video mode, allocate a virtual screen, plot and read pixels, draw a
  line, fill a rectangle, blit and clear, and eleven ways to move the palette
  about. Twenty-one routines, all of them hand-written assembler.

  ONE UNIT, SEVEN EXECUTABLES. Every part links this same source and Turbo
  Pascal's smart linker drops whatever that part never calls -- so no two parts
  contain the same subset, and none contains all twenty-one. Part 007 links
  almost none of it.

  The Mode-X routines are NOT here. They are in MODEX.PAS, which is the unit
  to read for unchained mode, plane selection and panning.

  EVERY ROUTINE HERE IS HAND-WRITTEN ASSEMBLER, and that is why they read as
  `assembler` procedures rather than Pascal. It is not stylistic: a blit is
  REP MOVSW with CX preloaded, PutPixel indexes a precomputed row table and
  falls straight into STOSB, and WaitRetrace has no frame at all. Turbo Pascal
  would emit ENTER/LEAVE, BP-relative locals and a multiply for the row
  offset -- which on a per-pixel path is the difference between an effect
  running and not.

  So each body is documented per instruction, with equivalent Pascal above it
  where the shape is not obvious. The Pascal is there to be READ, never to be
  swapped in.

  =========================================================================== }

{ =========================================================================== }

{ 286 instructions are permitted -- the palette routines use REP OUTSB and
  REP INSB, which move all 768 DAC bytes in one instruction each. }
{$G+}

unit VGA;

interface

const
  ScrWidth  = 320;
  ScrHeight = 200;
  VGASeg    = $A000;


type
  { The DAC in the order the hardware wants it: R, G, B per entry, 0..63. }
  TPalette = array[0..255, 0..2] of Byte;
  PPalette = ^TPalette;

var

  { The virtual screen every part draws into before blitting to $A000.
    64,000 bytes on the heap; VirtScrSeg is its segment, and because GetMem
    returns a normalised pointer the offset is always 0 -- which is why every
    part addresses it as a bare segment. }
  VirtScr    : Pointer;
  VirtScrSeg : Word;
  { Row offset lookup: YOfs[y] is y * 320, the byte offset of row y. PutPixel
    indexes this rather than multiplying, which is why it needs no MUL -- the
    saving is per pixel, so it is the whole reason the table exists. }
  YOfs       : array[0..ScrHeight - 1] of Word;


  { THERE IS NO SHARED PALETTE BUFFER IN THIS UNIT, deliberately. Every palette
    routine below takes a POINTER to the caller's own 768 bytes, so a scene owns
    its palette and two scenes cannot tread on each other. }

procedure SetMode13h;
procedure SetTextMode;
{ BuildRowTable IS NOT IN THE INTERFACE. It fills YOfs and the unit calls it
  from its own initialisation, so it is done before any caller could need it.
  Nothing outside reaches it -- and note that MODEX has a BuildRowTable of its
  own for the Mode-X row table, which is a different table for a different
  layout. Two routines, same name, different units. }
procedure VirtScrAlloc;
procedure VirtScrFree;
procedure ClearVirtual;
procedure DrawLine(X1, Y1, X2, Y2 : Integer; Colour : Byte; Segment : Word);

{ The palette machinery. These are part 001's copy of the unit (segment 1491)
  and are NOT in part 003's (12f8/1192), which is what this file was first
  transcribed from -- so they were missing altogether until part 001 scene 2
  turned out to have no fade at either end. }
procedure SetPalette768(P : Pointer);                far;
procedure GetPalette768(P : Pointer);                far;
procedure PaletteDim(P : Pointer);                   far;
procedure PaletteFadeUp(P : Pointer; Pause : Word);  far;
procedure PaletteFadeOut(Pause : Word);              far;

procedure PutPixel(X, Y : Word; Colour : Byte; Segment : Word); far;
function  GetPixel(X, Y : Integer; Segment : Word) : Byte;      far;
procedure FillRect(X1, Y1, X2, Y2 : Integer;
                   Colour : Byte; Segment : Word);              far;
procedure SetRGB(Col, R, G, B : Byte); far;
procedure GetRGB(Col : Byte; var R, G, B : Byte); far;
procedure SetRGBFrom(Col : Byte; P : Pointer);    far;
procedure GetRGBTo(Col : Byte; P : Pointer);      far;
procedure FadeStep;                               far;
procedure WaitRetrace; far;
procedure CopyScreen(SrcSeg, DestSeg : Word); far;
procedure ClearScreen(Segment : Word; Colour : Byte); far;

implementation

uses Crt;   { Delay, in the palette fades }

{ EQUIVALENT PASCAL -- REFERENCE ONLY, and not what is compiled:

      procedure SetMode13h;
      begin
        asm MOV AX, $0013; INT $10 end;
      end;

  which is the same two instructions with a stack frame around them. The
  original has no frame, so the procedure is `assembler`. }
procedure SetMode13h; assembler;
asm
  MOV  AX, $0013        { BIOS function 0, mode $13: 320x200, 256 colours   }
  INT  $10              { the video BIOS                                    }
end;

procedure VirtScrAlloc;
begin
  GetMem(VirtScr, 64000);
  VirtScrSeg := Seg(VirtScr^);
  FillChar(VirtScr^, 64000, 0);
end;

procedure VirtScrFree;
begin
  FreeMem(VirtScr, 64000);
end;

{ --------------------------------------------------------------------------
plot one pixel via the row table.

  There is no multiply and no bounds test. Y indexes the precomputed row
  table, X is added straight on, and an out-of-range Y simply reads past the
  table and lands somewhere else in the segment.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Mem[Segment : YOfs[Y] + X] := Colour;
  -------------------------------------------------------------------------- }
procedure PutPixel(X, Y : Word; Colour : Byte; Segment : Word); assembler;
asm
  MOV  AX, Segment      { which screen -- $A000 or the virtual one          }
  MOV  ES, AX           { ES:DI addresses the pixel                         }
  MOV  BX, Y            { the row                                           }
  SHL  BX, 1            { * 2, a word index into the row table              }
  MOV  DI, [BX + OFFSET YOfs]   { DI := YOfs[Y], the row's byte offset      }
  ADD  DI, X            { + the column                                      }
  MOV  AL, Colour       { the pixel value                                   }
  STOSB                 { write it                                          }
end;

{ --------------------------------------------------------------------------
read one pixel back. HAND ASSEMBLER, verbatim.

  Only parts 004, 005 and 006 link this; the rest never call it and the
  smart linker drops it. Part 004 is where it earns its keep: the lemmings
  read the hillside as their collision map.

  There is no bounds test, and Y indexes the row table straight, so an
  off-screen Y reads past the table and returns whatever is there.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      GetPixel := Mem[Segment : YOfs[Y] + X];
  -------------------------------------------------------------------------- }
function GetPixel(X, Y : Integer; Segment : Word) : Byte; assembler;
asm
  MOV  AX, Segment      { which screen to read                              }
  MOV  ES, AX           { ES:DI addresses the pixel                         }
  MOV  BX, Y            { the row                                           }
  SHL  BX, 1            { * 2, a word index into the row table              }
  MOV  DI, [BX + OFFSET YOfs]   { DI := YOfs[Y] = Y * 320                   }
  ADD  DI, X            { + the column                                      }
  MOV  AL, ES:[DI]      { read it -- AL is the function result              }
end;

{ --------------------------------------------------------------------------
filled rectangle. HAND ASSEMBLER, verbatim.
  Linked only by parts 004 and 006, where the two copies are byte-identical.

  RETF $C, so six words. Highest first: X1 at BP+$10, Y1 at BP+$E, X2 at
  BP+$C, Y2 at BP+$A, Colour at BP+8, Segment at BP+6. Both edges are
  INCLUSIVE -- the width is X2 - X1 + 1 and the height Y2 - Y1 + 1.

  The loop is tighter than it looks: the backward jump goes to the REP STOSB
  itself, not to the top of the loop. AL keeps the colour and BX the width for
  the whole call, so a row costs one REP plus four instructions.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      D := YOfs[Y1] + X1;
      for Row := 1 to Y2 - Y1 + 1 do
      begin
        FillChar(Mem[Segment : D], X2 - X1 + 1, Colour);
        Inc(D, 320);
      end;
  -------------------------------------------------------------------------- }
procedure FillRect(X1, Y1, X2, Y2 : Integer;
                   Colour : Byte; Segment : Word); assembler;
asm
  MOV  AX, Segment      { which screen                                      }
  MOV  ES, AX           { ES:DI is the destination throughout               }
  MOV  AX, X1           { the left edge                                     }
  MOV  CX, X2           { the right edge                                    }
  MOV  DX, Y2           { the bottom edge                                   }
  MOV  BX, Y1           { the top edge                                      }
  SHL  BX, 1            { * 2, a word index into the row table              }
  MOV  DI, [BX + OFFSET YOfs]   { DI := YOfs[Y1]                            }
  ADD  DI, AX           { + X1 -- the first byte of the rectangle           }
  SUB  CX, AX           { X2 - X1                                           }
  INC  CX               { CX := the width, both edges inclusive             }
  SUB  DX, Y1           { Y2 - Y1                                           }
  INC  DX               { DX := the height, likewise                        }
  MOV  BX, CX           { keep the width -- REP destroys CX                 }
  MOV  AL, Colour       { the fill byte, kept in AL for the whole call      }
@@Row:                  { <- once per row; the loop starts HERE, at the REP }
  REP  STOSB            { fill this row; DI advances by the width           }
  MOV  CX, BX           { the width back for the next pass                  }
  ADD  DI, $140         { 320 -- down one screen row...                     }
  SUB  DI, BX           {   ...less what the fill already advanced          }
  DEC  DX               { one row done                                      }
  JNZ  @@Row            { round again                                       }
end;

{ --------------------------------------------------------------------------
write one DAC entry. Index to $3C8, then R,G,B to $3C9.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  DrawLine -- a Bresenham line, and only the parts that actually draw one link
  it. That is why no two copies of this unit are the same size.

  Argument order is the original's: segment, colour, then the two endpoints
  as (Y, X) pairs rather than (X, Y).
  -------------------------------------------------------------------------- }
procedure DrawLine(X1, Y1, X2, Y2 : Integer; Colour : Byte; Segment : Word);
  assembler;
var
  { Four words. THE FIRST TWO ARE REUSED for a second purpose partway through
    -- see the note above the asm block, which is the only place that says so. }
  DXAbs, DYAbs : Integer;         { |dx| and |dy|, then flags }
  Inc1, Inc2   : Integer;         { the two error increments  }
asm
    MOV  AX, Segment
    MOV  ES, AX            { loaded ONCE, and never reloaded       }
    MOV  BX, Y1
    ADD  BX, BX            { a Word index into the row table       }
    MOV  DI, WORD PTR YOfs[BX]      { Y1 * 320                              }
    ADD  DI, X1            { the first pixel's offset              }

    MOV  AX, X1
    SUB  AX, X2
    JG   @@DXOK            { <= 0, so negate -- Abs, and negating  }
    NEG  AX                { zero is harmless, which is why the  }
@@DXOK:                    {              test is JG and not JGE             }
    MOV  DXAbs, AX
    MOV  AX, Y1
    SUB  AX, Y2
    JG   @@DYOK
    NEG  AX
@@DYOK:
    MOV  DYAbs, AX
    CMP  AX, DXAbs         { which axis is the major one?          }
    JLE  @@Shallow         { |dy| <= |dx|: step along X            }
    JMP  @@Steep

{ ---- shallow: X is the major axis, one step per column ---- }
@@Shallow:
    MOV  CX, DXAbs         { the loop count                        }
    SHL  AX, 1             { AX is still |dy|                      }
    MOV  Inc1, AX          { 2 * |dy|                              }
    SUB  AX, DXAbs
    MOV  BX, AX            { BX is the error term, in a register   }
    MOV  AX, DYAbs
    SUB  AX, DXAbs
    SHL  AX, 1
    MOV  Inc2, AX          { 2 * (|dy| - |dx|)                     }

    MOV  DXAbs, 0          { REUSED: 0 means X counts down         }
    MOV  AX, X1
    SUB  AX, X2
    JG   @@SXSet
    MOV  DXAbs, 1          { X1 <= X2, so X counts up            }
@@SXSet:
    MOV  DYAbs, 0          { REUSED the same way for Y             }
    MOV  AX, Y1
    SUB  AX, Y2
    JG   @@SYSet
    MOV  DYAbs, 1
@@SYSet:
    MOV  AL, Colour        { AL holds the colour for both loops    }
    MOV  ES:[DI], AL       { the first pixel                       }
    CMP  CX, 0
    JZ   @@SDone           { a zero-length line is one pixel, and
                             the target is the JMP below, NOT @@Out: the
                             original's is `JE $016E`, two bytes, where a jump
                             all the way to the routine's end needs the long
                             form and three more. Those three bytes put every
                             VGA routine after this one at the wrong offset. }

@@SLoop:
    CMP  DXAbs, 0
    JZ   @@SLeft
    INC  DI
    JNC  @@SErr            { the carry fix-up below is vestigial:  }
    INC  DX                { DX is never initialised and never   }
    JMP  @@SErr            { reaches ES                         }
@@SLeft:
    DEC  DI
    JNC  @@SErr
    DEC  DX
@@SErr:
    CMP  BX, 0
    JGE  @@SStep
    ADD  BX, Inc1          { no minor-axis step this time          }
    JMP  @@SPlot
@@SStep:
    ADD  BX, Inc2
    CMP  DYAbs, 0
    JZ   @@SUp
    ADD  DI, 320
    JNC  @@SPlot
    INC  DX
    JMP  @@SPlot
@@SUp:
    SUB  DI, 320
    JNC  @@SPlot
    DEC  DX
@@SPlot:
    MOV  ES:[DI], AL
    LOOP @@SLoop
@@SDone:
    JMP  @@Out

{ ---- steep: Y is the major axis, one step per row. The mirror of the above,
       with the two axes exchanged everywhere. ---- }
@@Steep:
    MOV  CX, DYAbs
    MOV  AX, DXAbs
    SHL  AX, 1
    MOV  Inc1, AX          { 2 * |dx|                              }
    SUB  AX, DYAbs
    MOV  BX, AX
    MOV  AX, DXAbs
    SUB  AX, DYAbs
    SHL  AX, 1
    MOV  Inc2, AX

    MOV  DXAbs, 0
    MOV  AX, X1
    SUB  AX, X2
    JG   @@TXSet
    MOV  DXAbs, 1
@@TXSet:
    MOV  DYAbs, 0
    MOV  AX, Y1
    SUB  AX, Y2
    JG   @@TYSet
    MOV  DYAbs, 1
@@TYSet:
    MOV  AL, Colour
    MOV  ES:[DI], AL
    CMP  CX, 0
    JZ   @@Out

@@TLoop:
    CMP  DYAbs, 0
    JZ   @@TUp
    ADD  DI, 320
    JNC  @@TErr
    INC  DX
    JMP  @@TErr
@@TUp:
    SUB  DI, 320
    JNC  @@TErr
    DEC  DX
@@TErr:
    CMP  BX, 0
    JGE  @@TStep
    ADD  BX, Inc1
    JMP  @@TPlot
@@TStep:
    ADD  BX, Inc2
    CMP  DXAbs, 0
    JZ   @@TLeft
    INC  DI
    JNC  @@TPlot
    INC  DX
    JMP  @@TPlot
@@TLeft:
    DEC  DI
    JNC  @@TPlot
    DEC  DX
@@TPlot:
    MOV  ES:[DI], AL
    LOOP @@TLoop
@@Out:
end;

{ --------------------------------------------------------------------------
one DAC entry.

  ARGUMENT ORDER MATTERS and the reconstruction had it backwards. The original
  pushes the COLOUR INDEX FIRST:

 -> $3C8   index      (first pushed)
 -> $3C9   R
 -> $3C9   G
 -> $3C9   B          (last pushed)

  Declared as (B, G, R, Col) the body still worked, but call sites disagreed
  with each other -- and the tunnel's `for I := 0 to 255 do SetRGB(I,0,0,0)`
  set colour ZERO's blue 256 times instead of blanking the palette. That is
  the blue screen.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := Col;
      Port[$3C9] := R;
      Port[$3C9] := G;
      Port[$3C9] := B;

  which compiles to four separate loads of DX; the original loads it once and
  steps it with a single INC.
  -------------------------------------------------------------------------- }
{$I SETRGB.INC}

{ --------------------------------------------------------------------------
read one DAC entry back. Index to $3C7, three reads from $3C9.
  Results go straight to the var parameters with LES/STOSB.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C7] := Col;
      R := Port[$3C9];
      G := Port[$3C9];
      B := Port[$3C9];
  -------------------------------------------------------------------------- }
procedure GetRGB(Col : Byte; var R, G, B : Byte); assembler;
asm
  MOV  DX, $3C7         { the DAC READ index register -- $3C7, not $3C8     }
  MOV  AL, Col          { which entry                                       }
  OUT  DX, AL           { select it                                         }
  ADD  DX, 2            { DX := $3C9, the DAC data register                 }
  IN   AL, DX           { red                                               }
  LES  DI, R            { ES:DI := @R                                       }
  STOSB                 { store it                                          }
  IN   AL, DX           { green                                             }
  LES  DI, G            { ES:DI := @G                                       }
  STOSB                 { store it                                          }
  IN   AL, DX           { blue                                              }
  LES  DI, B            { ES:DI := @B                                       }
  STOSB                 { store it                                          }
end;

{ --------------------------------------------------------------------------
 -- the same two DAC accessors, but reading and
  writing a THREE-BYTE RECORD rather than three separate parameters. Only
  part 004 links them; its explosion walks a local RGB triple up toward the
  scene palette and these are what it uses.
  HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := Col;
      Port[$3C9] := TRGB(P^)[0];
      Port[$3C9] := TRGB(P^)[1];
      Port[$3C9] := TRGB(P^)[2];

      Port[$3C7] := Col;
      TRGB(P^)[0] := Port[$3C9];  ... and so on
  -------------------------------------------------------------------------- }
procedure SetRGBFrom(Col : Byte; P : Pointer); assembler;
asm
  LES  DI, P            { ES:DI := the three bytes                          }
  MOV  DX, $3C8         { the DAC WRITE index register                      }
  MOV  AL, Col          { which entry                                       }
  OUT  DX, AL           { select it                                         }
  INC  DX               { DX := $3C9, the DAC data register                 }
  MOV  AL, ES:[DI]      { red                                               }
  OUT  DX, AL
  MOV  AL, ES:[DI+1]    { green                                             }
  OUT  DX, AL
  MOV  AL, ES:[DI+2]    { blue                                              }
  OUT  DX, AL
end;

procedure GetRGBTo(Col : Byte; P : Pointer); assembler;
asm
  LES  DI, P            { ES:DI := where the three bytes go                 }
  MOV  DX, $3C7         { the DAC READ index register -- $3C7, not $3C8     }
  MOV  AL, Col          { which entry                                       }
  OUT  DX, AL           { select it                                         }
  ADD  DX, 2            { DX := $3C9, the DAC data register                 }
  IN   AL, DX           { red                                               }
  STOSB                 { store it; DI moves on                             }
  IN   AL, DX           { green                                             }
  STOSB
  IN   AL, DX           { blue                                              }
  STOSB
end;

{ --------------------------------------------------------------------------
  Set all 256 DAC entries from a caller's 768-byte buffer: select colour 0,
  then REP OUTSB the lot. The DAC auto-increments, so one instruction writes
  every entry.

  It does NOT wait for retrace; the
  callers that care do that themselves, which is why both fades below have an
  explicit WaitRetrace in the loop.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := 0;
      for I := 0 to 767 do Port[$3C9] := TPal768(P^)[I];

  REP OUTSB is one instruction for the whole 768; the Pascal loop is several
  per byte and shows as a visible step on a fade.
  -------------------------------------------------------------------------- }
{$I SETPAL.INC}

{ --------------------------------------------------------------------------
out $3C7 := 0 then REP INSB 768 bytes into P^.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C7] := 0;
      for I := 0 to 767 do TPal768(P^)[I] := Port[$3C9];
  -------------------------------------------------------------------------- }
procedure GetPalette768(P : Pointer); assembler;
asm
  LES  DI, P            { ES:DI := where the palette is to go               }
  MOV  DX, $3C7         { the DAC READ index register                       }
  MOV  AL, 0            { start at colour 0                                 }
  OUT  DX, AL           { select it                                         }
  ADD  DX, 2            { DX := $3C9, the DAC data register                 }
  MOV  CX, $300         { 768 bytes                                         }
  REP  INSB             { read them all in to ES:DI                         }
end;

{ --------------------------------------------------------------------------
  ONE STEP OF A FADE, applied to a palette buffer in place: walk all 768 bytes
  and decrement every non-zero one, stepping over the zeroes. Call it
  repeatedly and the palette walks down to black; a component that has reached
  zero stays there, so the fade ends of its own accord.

  It reads and writes the SAME buffer through two segment registers -- LES DI
  and LDS SI are both loaded from the one parameter -- so SI runs one byte
  ahead of DI and each decrement lands back where it came from.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 0 to 767 do
        if TPal768(P^)[I] <> 0 then Dec(TPal768(P^)[I]);
  -------------------------------------------------------------------------- }
procedure PaletteDim(P : Pointer); assembler;
asm
  PUSH DS               { DS becomes the buffer's segment below             }
  LES  DI, P            { ES:DI := the buffer, for writing                  }
  LDS  SI, P            { DS:SI := the same buffer, for reading             }
  MOV  CX, $300         { 768 bytes                                         }
@@Next:                 { <- once per component                             }
  LODSB                 { AL := this component; SI moves on                 }
  OR   AL, AL           { already black?                                    }
  JZ   @@Skip           {   yes -- leave it alone                           }
  DEC  AL               { one step darker                                   }
  STOSB                 { write it back; DI moves on                        }
  DEC  CX               { one byte done                                     }
  JNZ  @@Next           { round again                                       }
  JMP  @@Out            { finished                                          }
@@Skip:                 { <- the zero case: no store, so bump DI by hand    }
  INC  DI               { keep DI level with SI                             }
  DEC  CX               { one byte done                                     }
  JNZ  @@Next           { round again                                       }
@@Out:                  { <- both exits                                     }
  POP  DS               { restore our data segment                          }
end;


{ --------------------------------------------------------------------------
one step of a fade to black, on the LIVE DAC. Compiled Pascal.
  Only part 004 links it.

  Not the same routine as PaletteDim above: that one dims a buffer the caller
  owns, this one reads the hardware back, dims it and writes it out. Both are
  in the unit; each part keeps whichever it calls.

  BX STARTS AT 768, one PAST the last byte of a 0..767 buffer, and the loop
  ends when BX reaches 0 -- so index 768 IS decremented, on Turbo Pascal's own
  frame, and index 0 never is. That is the original's behaviour and it is now
  reproduced rather than corrected; the deviation that used to be recorded here
  no longer exists. The four bytes above the buffer are the pointer itself, so
  what index 768 lands on is the low byte of P.
  -------------------------------------------------------------------------- }
procedure FadeStep;
{ EQUIVALENT PASCAL for the asm block -- reference only, not what is compiled:

      for I := 768 downto 1 do
        if Buf[I] <> 0 then Dec(Buf[I]);

  which reads the same and does not run the same: it needs a frame slot for I
  and it reloads the buffer's address every pass. }
var
  P   : Pointer;                  { and it is only ever read by the
                                    asm block below -- the buffer's address is
                                    taken once instead of per component }
  Buf : array[0..767] of Byte;
begin
  P := @Buf;
  GetPalette768(@Buf);
  asm
        LES     DI, P           { ES:DI is the buffer, once        }
        MOV     BX, 300h        { 768 -- ONE PAST the last byte    }
    @@Three:
        MOV     AL, ES:[BX+DI]  { the first of three components    }
        OR      AL, AL
        JE      @@Second        { already black: leave it alone    }
        DEC     AL              { one step darker                  }
        MOV     ES:[BX+DI], AL
    @@Second:
        DEC     BX
        MOV     AL, ES:[BX+DI]  { the second                       }
        OR      AL, AL
        JE      @@First
        DEC     AL
        MOV     ES:[BX+DI], AL
    @@First:
        DEC     BX
        MOV     AL, ES:[BX+DI]  { and the third                    }
        OR      AL, AL
        JE      @@Next
        DEC     AL
        MOV     ES:[BX+DI], AL
    @@Next:
        DEC     BX              { the third decrement IS the test  }
        JNE     @@Three         { BX reached 0: index 0 is skipped }
  end;
  WaitRetrace;
  SetPalette768(@Buf);
end;

{ --------------------------------------------------------------------------
PaletteFadeUp(P, Pause). Compiled Pascal in the binary
  (ENTER $602: two 768-byte buffers and two counters).

  Copies the target palette into a local, blanks a second one, and then walks
  every component of the second UP toward the first by one a step, showing it
  after each. 64 steps with Delay(Pause) between them.

  Because it steps by one and stops when it matches, a component that starts
  at 63 takes all 64 steps and one at 10 arrives after 10 -- so dark colours
  land early and the bright ones keep climbing. That is what gives the fade
  its shape rather than a flat linear ramp.
  -------------------------------------------------------------------------- }
procedure PaletteFadeUp(P : Pointer; Pause : Word);
var
  { Two whole palettes on the stack -- where the fade is going, and where it is
    now -- plus the two counters. Step is the OUTER loop: it walks the fade from
    dark to the target, and I walks the 768 bytes within each step. }
  Target : TPalette;
  Cur    : TPalette;
  I      : Byte;
  Step   : Byte;
begin
  { A STRUCTURED ASSIGNMENT RATHER THAN Move, and it must stay one: Turbo
    Pascal copies a whole record inline, where a Move call would be a call.
    Same effect, different code. }
  { THE COPY IS HAND ASSEMBLER, and three Pascal forms were tried before that
    was the answer: `Move(P^, Target, SizeOf(Target))`, `Target := TPalette(P^)`
    and `Target := PPalette(P)^` all compile to the runtime helper, and so does
    a `var` parameter. Turbo Pascal uses the helper for a 768-byte structured
    assignment whatever the source looks like, so the inline REP MOVSB at
 cannot come from Pascal at all. Transcribed verbatim, it is two
    bytes shorter than the call -- which is exactly what ClearScreen's offset
    was out by in parts 001 and 004. }
  asm
    MOV  BX, SS            { the destination is on the stack       }
    MOV  ES, BX
    MOV  BX, DS            { save DGROUP -- LDS is about to take it }
    CLD                    { upwards                               }
    LEA  DI, Target
    LDS  SI, P             { the caller's palette, a far pointer    }
    MOV  CX, $300          { 768 bytes                             }
    REP  MOVSB
    MOV  DS, BX            { DGROUP back                           }
  end;
  FillChar(Cur, SizeOf(Cur), 0);              { start from black }
  for Step := 0 to $3F do
  begin
    for I := 0 to 255 do
    begin
      if Cur[I, 0] < Target[I, 0] then Inc(Cur[I, 0]);
      if Cur[I, 1] < Target[I, 1] then Inc(Cur[I, 1]);
      if Cur[I, 2] < Target[I, 2] then Inc(Cur[I, 2]);
    end;
    WaitRetrace;
    SetPalette768(@Cur);
    Delay(Pause);
  end;
end;

procedure PaletteFadeOut(Pause : Word);
var
  Buf  : TPalette;
  Step : Byte;
begin
  GetPalette768(@Buf);
  for Step := 0 to $3F do
  begin
    WaitRetrace;
    SetPalette768(@Buf);
    PaletteDim(@Buf);
    Delay(Pause);
  end;
end;

{ --------------------------------------------------------------------------
wait for the start of vertical retrace.

  No prologue and no epilogue beyond RETF: this one is unmistakably hand
  assembler. It waits for retrace to END first, then for it to BEGIN, so the
  caller always gets a full frame of blanking rather than joining one late.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      while (Port[$3DA] and 8) <> 0 do ;
      while (Port[$3DA] and 8)  = 0 do ;
  -------------------------------------------------------------------------- }
procedure WaitRetrace; assembler;
asm
  MOV  DX, $3DA         { input status register 1                           }
@WaitEnd:               { <- spin while a retrace is already running        }
  IN   AL, DX           { read the status                                   }
  TEST AL, 8            { bit 3 is vertical retrace                         }
  JNZ  @WaitEnd         { one is running -- wait it out                     }
@WaitStart:             { <- then spin until the next one begins            }
  IN   AL, DX           { read again                                        }
  TEST AL, 8            { still bit 3                                       }
  JZ   @WaitStart       { not yet -- keep waiting                           }
end;

{ --------------------------------------------------------------------------
64000-byte screen copy (32000 words).

  Used two different ways: as a mode 13h page flip (virtual screen -> $A000),
  and in Scene 1 to push one 64000-byte Mode-X plane into video memory with
  the Map Mask already set.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Move(Mem[SrcSeg : 0], Mem[DestSeg : 0], 64000);

  and that really is equivalent -- Move is itself a REP MOVSW. It is written
  out because the original writes it out, with no call.
  -------------------------------------------------------------------------- }
procedure CopyScreen(SrcSeg, DestSeg : Word); assembler;
asm
  PUSH DS               { DS becomes the source segment below               }
  MOV  AX, DestSeg      { the second declared parameter                     }
  MOV  ES, AX           { ES: is the destination                            }
  MOV  AX, SrcSeg       { the first                                         }
  MOV  DS, AX           { DS: is the source                                 }
  XOR  SI, SI           { both start at offset 0 -- these are whole         }
  XOR  DI, DI           {   64,000-byte screens, not sub-rectangles         }
  MOV  CX, 32000        { words, so 64,000 bytes = 320 x 200                }
  REP  MOVSW            { the blit, one instruction                         }
  POP  DS               { restore our data segment                          }
end;

{ --------------------------------------------------------------------------
fill 64000 bytes with a colour (STOSW, so the byte is doubled).

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      FillChar(Mem[Segment : 0], 64000, Colour);
  -------------------------------------------------------------------------- }
procedure ClearScreen(Segment : Word; Colour : Byte); assembler;
asm
  MOV  CX, 32000        { words, so 64,000 bytes                            }
  MOV  ES, Segment      { ES: is what gets filled                           }
  XOR  DI, DI           { from offset 0                                     }
  MOV  AL, Colour       { the fill byte                                     }
  MOV  AH, AL           { doubled into AX, so one STOSW does two pixels     }
  REP  STOSW            { the fill, one instruction                         }
end;

{ SetMode, SelectPlane and LogicalWidth used to be here. They are not part of
  this unit -- they belong to the Mode-X unit (segment 1192 in part 003, 107c
  in part 002), which is src/MODEX.PAS. The SetMode transcription that lived
  here was also missing the 64K video-memory clear; see that file. }


{ ===========================================================================
  Shared screen management.

  These are the helpers every effect part assumes exist. Unlike the assembler
  routines above they are NOT transcribed instruction by instruction -- BP7
  inlines or duplicates most of them per part, so there is no single original
  to transcribe. They are written as ordinary Pascal doing the same job.
  =========================================================================== }

{ --------------------------------------------------------------------------
back to 80-column colour text.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      (none). Setting a video mode is a BIOS call, and Turbo Pascal has no way
      to make one without an asm block or an Intr(), which would push a
      Registers record the original does not have.
  -------------------------------------------------------------------------- }
procedure SetTextMode; assembler;
asm
  MOV  AX, $0003        { BIOS function 0, mode 3: 80x25 colour text        }
  INT  $10              { the video BIOS                                   }
end;

{ the row table, and it is NEAR: see the note in the interface. }
procedure BuildRowTable;
var
  Y : Integer;
begin
  for Y := 0 to ScrHeight - 1 do
    YOfs[Y] := Y * ScrWidth;
end;

procedure ClearVirtual;
begin
  ClearScreen(VirtScrSeg, 0);
end;

{ Palette transfer. Port $3C8 selects the entry for writing ($3C7 for
  reading), then $3C9 takes R, G, B in turn and auto-increments, so the whole
  table moves in one burst. }
{ SetPalette and GetPalette took no arguments and wrapped the 768 versions
  around the unit's own Palette global. Both are gone with it: there is nothing
  for them to wrap, and the only caller now passes its own buffer. }


{ --------------------------------------------------------------------------
PaletteFadeOut(Pause). Compiled Pascal (ENTER $302).

  Reads the live DAC back, then 64 rounds of show-then-darken with
  Delay(Pause) between them. Note the order: it SHOWS the buffer and then
  dims it, so the first frame is the palette exactly as it was and the last
  is 63 steps down -- not quite black if anything started above 63, which
  nothing does. }

begin
  { the unit's initialization, and it does ONE thing. }
  BuildRowTable;
end.

{ ===========================================================================
  NOTE ON THE ROW TABLE }

