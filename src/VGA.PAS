{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the shared VGA unit.

  ONE UNIT, SEVEN EXECUTABLES. Every part links this same source and Turbo
  Pascal's SMART LINKER drops whatever that part never calls, which is why
  the segment is a different size and the addresses are different in each --
  and why an earlier pass mistook the subsets for four separate units.

  The proof is the ORDER. Routines come out in source order with the unused
  ones simply missing, so the survivors' offsets stay monotonic in every
  part. Reading across the seven binaries recovers the whole unit:

    #   routine          001   002   003   004   005   006   007
    1   SetMode13h        y     y     y     y     y     y     y
    2   VirtScrAlloc      y     y     y     y     y     y     .
    3   VirtScrFree       y     y     y     y     y     y     .
    4   PutPixel          .     .     y     .     y     y     .
    5   GetPixel          .     .     .     y     y     y     .
    6   FillRect          .     .     .     y     .     y     .
    7   DrawLine          y     .     .     y     .     y     .
    8   SetRGB            y     y     y     y     y     y     .
    9   GetRGB            y     y     y     .     .     .     .
    10  SetRGBFrom        .     .     .     y     .     .     .
    11  GetRGBTo          .     .     .     y     .     .     .
    12  SetPalette768     y     y     .     y     y     y     .
    13  GetPalette768     y     y     .     y     .     .     .
    14  PaletteDim        y     y     .     .     y     .     .
    15  FadeStep          .     .     .     y     .     .     .
    16  PaletteFadeUp     .     .     .     y     .     .     .
    17  PaletteFadeOut    y     y     .     .     .     .     .
    18  WaitRetrace       y     y     y     y     .     .     .
    19  CopyScreen        y     y     y     .     y     y     .
    20  ClearScreen       y     y     y     y     y     y     .
    21  BuildRowTable     y     y     y     y     y     y     .

  Anchors: SetMode13h is six bytes at offset 0 of the unit in all seven.
  Part 001 has DrawLine at 1491:0048 and part 004 at 11e3:009c purely because
  004 also links GetPixel and FillRect ahead of it. Part 003 gets PutPixel at
  12f8:0048 for the same reason in reverse.

  So there is no "part 004 FillRect" distinct from anything here -- FillRect
  is in this unit, and parts 004 and 006 are simply the only two that call
  it. Their copies are byte-identical.

  SetMode and SelectPlane below are NOT part of this unit. They belong to the
  Mode-X unit, which is segment 1192 in part 003 and 107c in part 002; the
  same order argument holds there too. They are left here for now because
  part 003's scenes reach them through this unit's name.

  THIS UNIT IS HAND-WRITTEN ASSEMBLER, not compiled Pascal, and is written
  back as `assembler` procedures so the original instruction sequences are
  preserved rather than paraphrased.

  How we can tell: VGA_WaitRetrace has no procedure prologue whatsoever, the
  blit and clear are REP MOVSW / REP STOSW with CX preloaded, and PutPixel
  indexes a precomputed row table and falls straight into STOSB. Borland
  Pascal 7 does not generate any of that shape -- it would emit ENTER/LEAVE,
  BP-relative locals and a multiply for the row offset.

  All of them end in RETF n, i.e. far procedures using the Pascal calling
  convention with callee stack cleanup -- so they are `procedure ...; far;
  assembler;` in the original source.

  ADDRESS MAP
    PutPixel        12f8:0048      SetRGB          12f8:0064
    GetRGB          12f8:007f      WaitRetrace     12f8:009f
    CopyScreen      12f8:00ad      ClearScreen     12f8:00c9
    SetMode         1192:002a      SelectPlane     1192:0087
  =========================================================================== }

{ ===========================================================================
  A NOTE ON PARAMETER ORDER -- read this before changing any signature here.

  Borland Pascal pushes parameters LEFT TO RIGHT, and the stack grows DOWN.
  So inside the callee the FIRST (leftmost) parameter is at the HIGHEST [BP+n]
  offset, and the last is at the lowest:

      procedure P(A, B, C);   near   ->   [BP+8]=A  [BP+6]=B  [BP+4]=C

  Ghidra's decompiler prints arguments in ASCENDING [BP+n] order, which is the
  REVERSE of the declaration. Taking that listing as the signature is how the
  whole of this unit ended up backwards on the first pass -- the behaviour was
  right, because the call sites were reversed to match, but the signatures did
  not correspond to the binary at all.

  The orders below are read off the disassembly and are the originals.
  =========================================================================== }

{$G+}   { 286 instructions: REP OUTSB and REP INSB in the palette routines.
          The original targets 386 and above. }

unit VGA;

interface

const
  ScrWidth  = 320;
  ScrHeight = 200;
  VGASeg    = $A000;

const
  { DS:$76B6 -- the Mode-X plane stride: 80 bytes per row = 320 pixels.
    SetMode writes it straight to CRTC register $13 (Offset), and
    BuildRowTable doubles it, giving a 640-pixel LOGICAL width so the visible
    320 is a window that can be panned. It sits in the executable's
    initialised data, so it was a typed constant -- which in Borland Pascal is
    writable, and that is what lets a scene change the stride at run time. }
  LogicalWidth : Byte = 80;

var
  { Row offset lookup, DS:$E772 -- YOfs[y] = y * 320. PutPixel indexes this
    rather than multiplying, which is why it needs no MUL. }
  YOfs : array[0..ScrHeight - 1] of Word;

type
  { The DAC in the order the hardware wants it: R, G, B per entry, 0..63. }
  TPalette = array[0..255, 0..2] of Byte;

var
  { The virtual screen every part draws into before blitting to $A000.
    64,000 bytes on the heap; VirtScrSeg is its segment, and because GetMem
    returns a normalised pointer the offset is always 0 -- which is why every
    part addresses it as a bare segment. }
  VirtScr    : Pointer;
  VirtScrSeg : Word;
  Palette    : TPalette;

procedure SetMode13h;
procedure SetTextMode;
procedure BuildRowTable;
procedure VirtScrAlloc;
procedure VirtScrFree;
procedure ClearVirtual;
procedure FlushKeys;
procedure SetPalette;
procedure GetPalette;
procedure DrawLine(X1, Y1, X2, Y2 : Integer; Colour : Byte; Segment : Word);

{ The palette machinery. These are part 001's copy of the unit (segment 1491)
  and are NOT in part 003's (12f8/1192), which is what this file was first
  transcribed from -- so they were missing altogether until part 001 scene 2
  turned out to have no fade at either end. }
procedure SetPalette768(P : Pointer);                far;   { 1491:01C2 }
procedure GetPalette768(P : Pointer);                far;   { 1491:01DA }
procedure PaletteDim(P : Pointer);                   far;   { 1491:01F2 }
procedure PaletteFadeUp(P : Pointer; Pause : Word);  far;   { 1491:0215 }
procedure PaletteFadeOut(Pause : Word);              far;   { 1491:0330 }

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
procedure SetMode; far;
procedure SelectPlane(Plane : Byte); far;

implementation

uses Crt;   { FlushKeys needs KeyPressed/ReadKey }

{ --------------------------------------------------------------------------
  12f8:0048 -- plot one pixel via the row table.

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
  MOV  DI, [BX + OFFSET YOfs]   { DI := YOfs[Y] = Y * 320 -- DS:$E772       }
  ADD  DI, X            { + the column                                      }
  MOV  AL, Colour       { the pixel value                                   }
  STOSB                 { write it                                          }
end;

{ --------------------------------------------------------------------------
  11e3:0048 -- read one pixel back. HAND ASSEMBLER, verbatim.

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
  11e3:0063 -- filled rectangle. HAND ASSEMBLER, verbatim.
  Linked only by parts 004 and 006, where the two copies are byte-identical.

  RETF $C, so six words. Highest first: X1 at BP+$10, Y1 at BP+$E, X2 at
  BP+$C, Y2 at BP+$A, Colour at BP+8, Segment at BP+6. Both edges are
  INCLUSIVE -- the width is X2 - X1 + 1 and the height Y2 - Y1 + 1.

  The loop is tighter than it looks: the jump at 11e3:0096 goes back to the
  REP STOSB itself, not to the top. AL keeps the colour and BX the width for
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
  12f8:0064 -- write one DAC entry. Index to $3C8, then R,G,B to $3C9.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  12f8:0064 -- one DAC entry.

  ARGUMENT ORDER MATTERS and the reconstruction had it backwards. The original
  pushes the COLOUR INDEX FIRST:

      [BP+$C] -> $3C8   index      (first pushed)
      [BP+$A] -> $3C9   R
      [BP+$8] -> $3C9   G
      [BP+$6] -> $3C9   B          (last pushed)

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
procedure SetRGB(Col, R, G, B : Byte); assembler;
asm
  MOV  DX, $3C8         { the DAC WRITE index register                      }
  MOV  AL, Col          { which entry                                       }
  OUT  DX, AL           { select it                                         }
  INC  DX               { DX := $3C9, the DAC data register                 }
  MOV  AL, R            { red, 0..63                                        }
  OUT  DX, AL           { the DAC takes the three in order and latches      }
  MOV  AL, G            { green                                             }
  OUT  DX, AL           {   the entry after the third                       }
  MOV  AL, B            { blue                                              }
  OUT  DX, AL           {                                                   }
end;

{ --------------------------------------------------------------------------
  12f8:007f -- read one DAC entry back. Index to $3C7, three reads from $3C9.
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
  11e3:01F6 and 11e3:0216 -- the same two DAC accessors, but reading and
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
  OUT  DX, AL           {                                                   }
  MOV  AL, ES:[DI+1]    { green                                             }
  OUT  DX, AL           {                                                   }
  MOV  AL, ES:[DI+2]    { blue                                              }
  OUT  DX, AL           {                                                   }
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
  STOSB                 {                                                   }
  IN   AL, DX           { blue                                              }
  STOSB                 {                                                   }
end;

{ --------------------------------------------------------------------------
  1491:01C2 -- out $3C8 := 0 then REP OUTSB 768 bytes from P^.

  1436:0083 in part 002, 11e3:0230 in part 004 -- the same bytes. Note it
  does NOT wait for retrace; the
  callers that care do that themselves, which is why both fades below have an
  explicit WaitRetrace in the loop.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := 0;
      for I := 0 to 767 do Port[$3C9] := TPal768(P^)[I];

  REP OUTSB is one instruction for the whole 768; the Pascal loop is several
  per byte and shows as a visible step on a fade.
  -------------------------------------------------------------------------- }
procedure SetPalette768(P : Pointer); assembler;
asm
  PUSH DS               { DS is about to point at the caller's buffer       }
  LDS  SI, P            { DS:SI := the 768-byte palette                     }
  MOV  DX, $3C8         { the DAC WRITE index register                      }
  MOV  AL, 0            { start at colour 0                                 }
  OUT  DX, AL           { select it -- the DAC auto-increments from here    }
  INC  DX               { DX := $3C9, the DAC data register                 }
  MOV  CX, $300         { 768 bytes = 256 entries of R, G, B                }
  REP  OUTSB            { write them all out from DS:SI                     }
  POP  DS               { restore our data segment                          }
end;

{ --------------------------------------------------------------------------
  1491:01DA -- out $3C7 := 0 then REP INSB 768 bytes into P^.

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
  1491:01F2 -- walk 768 bytes; every NON-ZERO one is decremented in place and
  written back, zeroes are stepped over (the JZ at 1491:0202 skips the STOSB
  and just bumps DI). One step of a fade held in a palette buffer.

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
  11e3:0260 -- one step of a fade to black, on the LIVE DAC. Compiled Pascal.
  Only part 004 links it.

  Not the same routine as PaletteDim above: that one dims a buffer the caller
  owns, this one reads the hardware back, dims it and writes it out. Both are
  in the unit; each part keeps whichever it calls.

  THE ORIGINAL'S LOOP RUNS 768 DOWN TO 3 IN THREES, touching [i], [i-1] and
  [i-2] each pass -- so index 768, one PAST the buffer, is decremented and
  index 0 never is. The loop here is written over 1..767, which is exactly
  the components that reach the DAC, so the result is identical and nothing
  lands on Turbo Pascal's frame. See docs/23-deviations.md.
  -------------------------------------------------------------------------- }
procedure FadeStep;
var
  Buf : array[0..767] of Byte;
  I   : Integer;
begin
  GetPalette768(@Buf);                     { 11e3:0264 }
  for I := 767 downto 1 do                 { 11e3:0271 -- see the note above }
    if Buf[I] <> 0 then Dec(Buf[I]);
  WaitRetrace;                             { 11e3:02A6 }
  SetPalette768(@Buf);                     { 11e3:02AC }
end;

{ --------------------------------------------------------------------------
  12f8:009f -- wait for the start of vertical retrace.

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
  12f8:00ad -- 64000-byte screen copy (32000 words).

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
  12f8:00c9 -- fill 64000 bytes with a colour (STOSW, so the byte is doubled).

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

{ --------------------------------------------------------------------------
  1192:002a -- mode 13h, then unchain to Mode-X at 640 logical width.

  Note what is NOT here: part 002's equivalent (107c:006d) clears all 64K
  after enabling the four planes. This one enables them and moves straight on,
  so the mode-13h screen underneath survives into Mode X.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      asm mov ax,$13; int $10 end;          -- no Pascal equivalent at all
      Port[$3C4] := 4;  Port[$3C5] := (Port[$3C5] and $F7) or $04;
      Port[$3CE] := 5;  Port[$3CF] :=  Port[$3CF] and $EF;
      Port[$3CE] := 6;  Port[$3CF] :=  Port[$3CF] and $FD;
      PortW[$3C4] := $0F02;
      Port[$3D4] := $14; Port[$3D5] := Port[$3D5] and $BF;
      Port[$3D4] := $17; Port[$3D5] := Port[$3D5] or  $40;
      Port[$3D4] := $13; Port[$3D5] := LogicalWidth;

  The mode set itself cannot be written in Pascal without an asm block for
  the INT.
  -------------------------------------------------------------------------- }
procedure SetMode; assembler;
asm
  MOV  AX, $0013        { BIOS mode $13: 320x200, 256 colours, chained      }
  INT  $10              { set it -- everything below un-chains it           }

  MOV  DX, $3C4         { Sequencer address register                        }
  MOV  AL, 4            { register 4 -- Memory Mode                         }
  OUT  DX, AL           { select it                                         }
  INC  DX               { DX := $3C5, the Sequencer data register           }
  IN   AL, DX           { read what is there                                }
  AND  AL, $F7          { clear bit 3: Chain-4 off -- this is the un-chain  }
  OR   AL, 4            { set bit 2: odd/even addressing off                }
  OUT  DX, AL           { write it back                                     }

  MOV  DX, $3CE         { Graphics Controller address register              }
  MOV  AL, 5            { register 5 -- Mode                                }
  OUT  DX, AL           { select it                                         }
  INC  DX               { DX := $3CF, the GC data register                  }
  IN   AL, DX           { read it                                           }
  AND  AL, $EF          { clear bit 4: host odd/even off                    }
  OUT  DX, AL           { write it back                                     }

  MOV  DX, $3CE         { GC address register again -- reloaded, not DEC'd  }
  MOV  AL, 6            { register 6 -- Miscellaneous                       }
  OUT  DX, AL           { select it                                         }
  INC  DX               { DX := $3CF                                        }
  IN   AL, DX           { read it                                           }
  AND  AL, $FD          { clear bit 1: chain odd/even off                   }
  OUT  DX, AL           { write it back                                     }

  MOV  DX, $3C4         { Sequencer address register                        }
  MOV  AX, $0F02        { register 2 (Map Mask) := $0F, all four planes     }
  OUT  DX, AX           { so every plane is writable from here on           }

  MOV  DX, $3D4         { CRTC address register                             }
  MOV  AL, $14          { register $14 -- Underline Location                }
  OUT  DX, AL           { select it                                         }
  INC  DX               { DX := $3D5, the CRTC data register                }
  IN   AL, DX           { read it                                           }
  AND  AL, $BF          { clear bit 6: doubleword addressing off            }
  OUT  DX, AL           { write it back                                     }

  MOV  DX, $3D4         { CRTC address register                             }
  MOV  AL, $17          { register $17 -- Mode Control                      }
  OUT  DX, AL           { select it                                         }
  INC  DX               { DX := $3D5                                        }
  IN   AL, DX           { read it                                           }
  OR   AL, $40          { set bit 6: byte addressing on. With $14 bit 6     }
  OUT  DX, AL           {   cleared, that is what makes the mode linear     }

  MOV  DX, $3D4         { CRTC address register                             }
  MOV  AL, $13          { register $13 -- Offset, the logical line width    }
  OUT  DX, AL           { select it                                         }
  INC  DX               { DX := $3D5                                        }
  MOV  AL, [LogicalWidth]   { DS:$76B6 -- 80, so 640 logical pixels: the    }
                        {   visible 320 is a window that can be panned      }
  OUT  DX, AL           { write it, and the mode is set                     }
end;

{ --------------------------------------------------------------------------
  1192:0087 -- Mode-X plane select (Sequencer register 2, Map Mask).

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      PortW[$3C4] := ((Word(1) shl Plane) shl 8) or $02;

  Note there is no mask with 3: a Plane above 7 just shifts the bit out and
  disables every plane. Nothing calls it that way.
  -------------------------------------------------------------------------- }
procedure SelectPlane(Plane : Byte); assembler;
asm
  MOV  CL, Plane        { the plane wanted                                  }
  MOV  AH, 1            { one bit, for plane 0                              }
  SHL  AH, CL           { moved to that plane's position                    }
  MOV  AL, 2            { Sequencer register 2 -- Map Mask                  }
  MOV  DX, $3C4         { Sequencer address register                        }
  OUT  DX, AX           { index in AL, mask in AH, one 16-bit OUT           }
end;

{ ===========================================================================
  Shared screen management.

  These are the helpers every effect part assumes exist. Unlike the assembler
  routines above they are NOT transcribed instruction by instruction -- BP7
  inlines or duplicates most of them per part, so there is no single original
  to transcribe. They are written as ordinary Pascal doing the same job.
  =========================================================================== }

procedure BuildRowTable;
var
  Y : Integer;
begin
  for Y := 0 to ScrHeight - 1 do
    YOfs[Y] := Y * ScrWidth;
end;

{ 12f8:0000 -- mode 13h and nothing else, then the row table. The asm block
  is two instructions because a BIOS call has no Pascal equivalent; Intr()
  would push a Registers record the original does not have. }
procedure SetMode13h;
begin
  asm
    MOV  AX, $0013      { BIOS function 0, mode $13: 320x200, 256 colours   }
    INT  $10            { the video BIOS                                    }
  end;
  BuildRowTable;
end;

{ 12f8:0033 -- back to 80-column colour text. Same note as above. }
procedure SetTextMode;
begin
  asm
    MOV  AX, $0003      { BIOS function 0, mode 3: 80x25 colour text        }
    INT  $10            { the video BIOS                                    }
  end;
end;

procedure VirtScrAlloc;
begin
  GetMem(VirtScr, 64000);
  VirtScrSeg := Seg(VirtScr^);
end;

procedure VirtScrFree;
begin
  if VirtScr <> nil then
  begin
    FreeMem(VirtScr, 64000);
    VirtScr := nil;
    VirtScrSeg := 0;
  end;
end;

procedure ClearVirtual;
begin
  ClearScreen(VirtScrSeg, 0);
end;

procedure FlushKeys;
var
  C : Char;
begin
  while KeyPressed do C := ReadKey;
end;

{ Palette transfer. Port $3C8 selects the entry for writing ($3C7 for
  reading), then $3C9 takes R, G, B in turn and auto-increments, so the whole
  table moves in one burst. }
{ The no-argument forms are a convenience over the global Palette; the
  original has only the pointer-taking 1491:01C2 and 1491:01DA. The
  WaitRetrace here is OURS -- 1491:01C2 does not wait, because the callers
  that care (both fades below) wait for themselves. }
procedure SetPalette;
begin
  WaitRetrace;
  SetPalette768(@Palette);
end;

procedure GetPalette;
begin
  GetPalette768(@Palette);
end;

{ --------------------------------------------------------------------------
  1491:0215 -- PaletteFadeUp(P, Pause). Compiled Pascal in the binary
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
  Target : TPalette;              { [BP-$302] }
  Cur    : TPalette;              { [BP-$602] }
  Step   : Byte;                  { [BP-$604] }
  I      : Byte;                  { [BP-$603] }
begin
  Move(P^, Target, SizeOf(Target));          { 1491:0219 }
  FillChar(Cur, SizeOf(Cur), 0);              { 1491:0232 -- start from black }
  for Step := 0 to $3F do
  begin
    for I := 0 to 255 do
    begin
      if Cur[I, 0] < Target[I, 0] then Inc(Cur[I, 0]);
      if Cur[I, 1] < Target[I, 1] then Inc(Cur[I, 1]);
      if Cur[I, 2] < Target[I, 2] then Inc(Cur[I, 2]);
    end;
    WaitRetrace;                              { 1491:0300 }
    SetPalette768(@Cur);                      { 1491:0306 }
    Delay(Pause);                             { 1491:0311 }
  end;
end;

{ --------------------------------------------------------------------------
  1491:0330 -- PaletteFadeOut(Pause). Compiled Pascal (ENTER $302).

  Reads the live DAC back, then 64 rounds of show-then-darken with
  Delay(Pause) between them. Note the order: it SHOWS the buffer and then
  dims it, so the first frame is the palette exactly as it was and the last
  is 63 steps down -- not quite black if anything started above 63, which
  nothing does.

  Called once in the whole demo, from Demo_Scene2 at 1082:05BB with Pause=10.
  -------------------------------------------------------------------------- }
procedure PaletteFadeOut(Pause : Word);
var
  Buf  : TPalette;                { [BP-$302] }
  Step : Byte;                    { [BP-$303] }
begin
  GetPalette768(@Buf);                        { 1491:033B }
  for Step := 0 to $3F do
  begin
    WaitRetrace;                              { 1491:034A }
    SetPalette768(@Buf);                      { 1491:0354 }
    PaletteDim(@Buf);                         { 1491:035E }
    Delay(Pause);                             { 1491:0364 }
  end;
end;

{ --------------------------------------------------------------------------
  DrawLine -- Bresenham. Part 001's copy of this unit is LARGER than part
  003's precisely because it carries this routine (1491:0048); parts that
  never draw a line do not link it.

  Argument order is the original's: segment, colour, then the two endpoints
  as (Y, X) pairs rather than (X, Y).
  -------------------------------------------------------------------------- }
procedure DrawLine(X1, Y1, X2, Y2 : Integer; Colour : Byte; Segment : Word);
var
  DX, DY, SX, SY, Err, E2 : Integer;
begin
  DX := Abs(X2 - X1);
  DY := Abs(Y2 - Y1);
  if X1 < X2 then SX := 1 else SX := -1;
  if Y1 < Y2 then SY := 1 else SY := -1;
  Err := DX - DY;
  while True do
  begin
    if (X1 >= 0) and (X1 < ScrWidth) and (Y1 >= 0) and (Y1 < ScrHeight) then
      PutPixel(X1, Y1, Colour, Segment);
    if (X1 = X2) and (Y1 = Y2) then Exit;
    E2 := Err * 2;
    if E2 > -DY then
    begin
      Dec(Err, DY);
      Inc(X1, SX);
    end;
    if E2 < DX then
    begin
      Inc(Err, DX);
      Inc(Y1, SY);
    end;
  end;
end;

begin
  VirtScr    := nil;
  VirtScrSeg := 0;
end.

{ ===========================================================================
  NOTE ON THE ROW TABLE

  PutPixel reads YOfs from DS:$E772 for the mode 13h path (y*320). Scene 1
  builds a *different* table for its Mode-X screen -- 800 entries of y*160 at
  DS:$9F1E-ish -- because the logical line there is 160 bytes per plane, not
  320. The two coexist; do not conflate them.
  =========================================================================== }
