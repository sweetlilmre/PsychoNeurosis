{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.004, the VGA unit.

  Segment 11e3 in NEUROSIS_004.exe, transcribed in full -- all sixteen
  routines and the unit initialisation, nothing inferred.

  Part 004 has its OWN copy of the VGA unit and it is not the same build as
  any other part's. Against part 001's (segment 1491) and part 003's (12f8 and
  1192) it gains a pixel READ and a rectangle fill, loses everything Mode-X,
  and its palette fade steps the whole DAC down rather than toward a target:

      here (11e3)        001 (1491)     003 (12f8/1192)
      GetPixel           --             --
      FillRect           --             --
      SetRGBFrom         --             --
      GetRGBTo           --             --
      FadeStep           --             --
      --                 PaletteDim     --
      --                 --             SetMode, SelectPlane

  That is why this is a separate unit rather than another set of routines
  bolted onto VGA.PAS: the two disagree about what the unit contains.

  ADDRESS MAP
    VirtScrAlloc   11e3:0006     VirtScrFree    11e3:0033
    GetPixel       11e3:0048     FillRect       11e3:0063
    DrawLine       11e3:009c     SetRGB         11e3:01DB
    SetRGBFrom     11e3:01F6     GetRGBTo       11e3:0216
    SetPalette768  11e3:0230     GetPalette768  11e3:0248
    FadeStep       11e3:0260     PaletteFadeUp  11e3:02B9
    WaitRetrace    11e3:03D4     ClearScreen    11e3:03E2
    BuildRowTable  11e3:03F8     unit init      11e3:041D
  =========================================================================== }

{$G+}   { 286 instructions: REP OUTSB and REP INSB in the palette routines. }

unit P4VGA;

interface

const
  ScrWidth  = 320;
  ScrHeight = 200;
  VGASeg    = $A000;

type
  { The DAC in the order the hardware wants it: R, G, B per entry, 0..63. }
  TPalette = array[0..255, 0..2] of Byte;
  TRGB     = array[0..2] of Byte;

var
  { DS:$CF88 the pointer, DS:$CF8C its segment, DS:$CF8E the row table. }
  VirtScr    : Pointer;
  VirtScrSeg : Word;
  YOfs       : array[0..ScrHeight - 1] of Word;

procedure VirtScrAlloc;                                     far; { 11e3:0006 }
procedure VirtScrFree;                                      far; { 11e3:0033 }
function  GetPixel(X, Y : Integer; Segment : Word) : Byte;  far; { 11e3:0048 }
procedure FillRect(X1, Y1, X2, Y2 : Integer;
                   Colour : Byte; Segment : Word);          far; { 11e3:0063 }
procedure DrawLine(X1, Y1, X2, Y2 : Integer;
                   Colour : Byte; Segment : Word);          far; { 11e3:009c }
procedure SetRGB(Col, R, G, B : Byte);                      far; { 11e3:01DB }
procedure SetRGBFrom(Col : Byte; P : Pointer);              far; { 11e3:01F6 }
procedure GetRGBTo(Col : Byte; P : Pointer);                far; { 11e3:0216 }
procedure SetPalette768(P : Pointer);                       far; { 11e3:0230 }
procedure GetPalette768(P : Pointer);                       far; { 11e3:0248 }
procedure FadeStep;                                         far; { 11e3:0260 }
procedure PaletteFadeUp(P : Pointer; Pause : Word);         far; { 11e3:02B9 }
procedure WaitRetrace;                                      far; { 11e3:03D4 }
procedure ClearScreen(Segment : Word; Colour : Byte);       far; { 11e3:03E2 }
procedure BuildRowTable;                                         { 11e3:03F8 }

implementation

uses Crt;      { 11e3:0311 calls Crt's Delay }

{ --------------------------------------------------------------------------
  11e3:0006 and 11e3:0033 -- the 64,000-byte virtual screen.

  GetMem, keep the segment out separately because everything addresses the
  screen as a bare segment, then blank it. Compiled Pascal in the binary.
  -------------------------------------------------------------------------- }
procedure VirtScrAlloc;
begin
  GetMem(VirtScr, 64000);                { 11e3:000A }
  VirtScrSeg := Seg(VirtScr^);           { 11e3:001C -> DS:$CF8C }
  FillChar(VirtScr^, 64000, 0);          { 11e3:0027 }
end;

procedure VirtScrFree;
begin
  FreeMem(VirtScr, 64000);               { 11e3:0033 }
end;

{ --------------------------------------------------------------------------
  11e3:0048 -- read one pixel back. HAND ASSEMBLER, verbatim.

  The lemmings need this: a walker decides whether to climb, fall or turn by
  READING the terrain it is standing on, so the landscape is the collision
  map. No other part's VGA unit has it.

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
  MOV  DI, [BX + OFFSET YOfs]   { DI := YOfs[Y] = Y * 320 -- DS:$CF8E       }
  ADD  DI, X            { + the column                                      }
  MOV  AL, ES:[DI]      { read it -- AL is the function result              }
end;

{ --------------------------------------------------------------------------
  11e3:0063 -- filled rectangle. HAND ASSEMBLER, verbatim.

  RETF $C, so six words. Highest first: X1 at BP+$10, Y1 at BP+$E, X2 at
  BP+$C, Y2 at BP+$A, Colour at BP+8, Segment at BP+6. Both edges are
  INCLUSIVE -- the width is X2 - X1 + 1 and the height Y2 - Y1 + 1.

  The loop is tighter than it first looks: the jump at 11e3:0096 goes back to
  the REP STOSB itself, not to the top. AL keeps the colour and BX keeps the
  width for the whole call, so a row costs one REP plus four instructions and
  nothing is reloaded.

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
  11e3:009c -- Bresenham line. Compiled Pascal in the binary (ENTER 8), so it
  is Pascal here. Nothing in part 004 calls it; it is part of the unit.
  -------------------------------------------------------------------------- }
procedure DrawLine(X1, Y1, X2, Y2 : Integer; Colour : Byte; Segment : Word);
var
  DX_, DY, SX, SY, Err, E2 : Integer;
begin
  DX_ := Abs(X2 - X1);
  DY  := Abs(Y2 - Y1);
  if X1 < X2 then SX := 1 else SX := -1;
  if Y1 < Y2 then SY := 1 else SY := -1;
  Err := DX_ - DY;
  while True do
  begin
    Mem[Segment : YOfs[Y1] + X1] := Colour;
    if (X1 = X2) and (Y1 = Y2) then Break;
    E2 := Err * 2;
    if E2 > -DY then begin Dec(Err, DY); Inc(X1, SX) end;
    if E2 <  DX_ then begin Inc(Err, DX_); Inc(Y1, SY) end;
  end;
end;

{ --------------------------------------------------------------------------
  11e3:01DB -- write one DAC entry. HAND ASSEMBLER, verbatim.

  The colour index is the FIRST parameter, at BP+$C. Same routine as every
  other part's.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := Col;
      Port[$3C9] := R;  Port[$3C9] := G;  Port[$3C9] := B;
  -------------------------------------------------------------------------- }
procedure SetRGB(Col, R, G, B : Byte); assembler;
asm
  MOV  DX, $3C8         { the DAC WRITE index register                      }
  MOV  AL, Col          { which entry                                       }
  OUT  DX, AL           { select it                                         }
  INC  DX               { DX := $3C9, the DAC data register                 }
  MOV  AL, R            { red, 0..63                                        }
  OUT  DX, AL           { the DAC latches the entry after the third         }
  MOV  AL, G            { green                                             }
  OUT  DX, AL           {                                                   }
  MOV  AL, B            { blue                                              }
  OUT  DX, AL           {                                                   }
end;

{ --------------------------------------------------------------------------
  11e3:01F6 -- write one DAC entry from a three-byte record, rather than from
  three separate parameters. HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := Col;
      Port[$3C9] := TRGB(P^)[0];
      Port[$3C9] := TRGB(P^)[1];
      Port[$3C9] := TRGB(P^)[2];
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

{ --------------------------------------------------------------------------
  11e3:0216 -- read one DAC entry back into a three-byte record.
  HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C7] := Col;
      TRGB(P^)[0] := Port[$3C9];
      TRGB(P^)[1] := Port[$3C9];
      TRGB(P^)[2] := Port[$3C9];
  -------------------------------------------------------------------------- }
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
  11e3:0230 -- out $3C8 := 0 then REP OUTSB 768 bytes from P^.
  HAND ASSEMBLER, verbatim. Byte for byte P2VGA's 1436:0083 and VGA's
  1491:01C2 -- the same routine in a third unit.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := 0;
      for I := 0 to 767 do Port[$3C9] := TPal768(P^)[I];
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
  11e3:0248 -- out $3C7 := 0 then REP INSB 768 bytes into P^.
  HAND ASSEMBLER, verbatim.

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
  11e3:0260 -- one step of a fade to black. Compiled Pascal (ENTER $304).

  Reads the live DAC back, decrements every non-zero component by one, waits
  for retrace and writes it out again. LoadAssets calls it 64 times.

  THE ORIGINAL'S LOOP RUNS 768 DOWN TO 3 IN THREES, touching [i], [i-1] and
  [i-2] each pass. That means index 768 -- one PAST the buffer -- is
  decremented, and index 0 never is. See docs/23-deviations.md: the loop here
  is written over 1..767, which is exactly the components that reach the DAC,
  so the result is identical and nothing lands on Turbo Pascal's frame.
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
  11e3:02B9 -- fade UP from black to P^. Compiled Pascal (ENTER $602: two
  768-byte buffers and two counters).

  Byte for byte part 001's 1491:0215. Copies the target into a local, blanks
  a second one, and walks every component of the second up toward the first
  by one a step, showing it after each. 64 steps with Delay(Pause) between.

  Because it steps by one and stops on a match, dark colours arrive early and
  bright ones keep climbing -- which is what gives the fade its shape rather
  than a flat ramp.
  -------------------------------------------------------------------------- }
procedure PaletteFadeUp(P : Pointer; Pause : Word);
var
  Target : TPalette;                       { [BP-$302] }
  Cur    : TPalette;                       { [BP-$602] }
  Step   : Byte;
  I      : Byte;
begin
  Move(P^, Target, SizeOf(Target));        { 11e3:02BD }
  FillChar(Cur, SizeOf(Cur), 0);           { 11e3:02D6 -- start from black }
  for Step := 0 to $3F do
  begin
    for I := 0 to 255 do
    begin
      if Cur[I, 0] < Target[I, 0] then Inc(Cur[I, 0]);
      if Cur[I, 1] < Target[I, 1] then Inc(Cur[I, 1]);
      if Cur[I, 2] < Target[I, 2] then Inc(Cur[I, 2]);
    end;
    WaitRetrace;                           { 11e3:0300 }
    SetPalette768(@Cur);                   { 11e3:0306 }
    Delay(Pause);                          { 11e3:0311 }
  end;
end;

{ --------------------------------------------------------------------------
  11e3:03D4 -- wait out any retrace in progress, then wait for the next one
  to start. HAND ASSEMBLER, verbatim: no stack frame at all.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      while (Port[$3DA] and 8) <> 0 do ;
      while (Port[$3DA] and 8)  = 0 do ;
  -------------------------------------------------------------------------- }
procedure WaitRetrace; assembler;
asm
  MOV  DX, $3DA         { input status register 1                           }
@@InRetrace:            { <- spin while a retrace is already running        }
  IN   AL, DX           { read the status                                   }
  TEST AL, 8            { bit 3 is vertical retrace                         }
  JNZ  @@InRetrace      { one is running -- wait it out                     }
@@WaitStart:            { <- then spin until the next one begins            }
  IN   AL, DX           { read again                                        }
  TEST AL, 8            { still bit 3                                       }
  JZ   @@WaitStart      { not yet -- keep waiting                           }
end;

{ --------------------------------------------------------------------------
  11e3:03E2 -- fill 64,000 bytes with a colour. HAND ASSEMBLER, verbatim.
  STOSW, so the byte is doubled into AX first. No CLD: it relies on the
  direction flag already being clear, which Turbo Pascal guarantees.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      FillChar(Mem[Segment : 0], 64000, Colour);
  -------------------------------------------------------------------------- }
procedure ClearScreen(Segment : Word; Colour : Byte); assembler;
asm
  MOV  CX, $7D00        { 32,000 words = 64,000 bytes = 320 x 200           }
  MOV  ES, Segment      { ES: is what gets filled                           }
  XOR  DI, DI           { from offset 0                                     }
  MOV  AL, Colour       { the fill byte                                     }
  MOV  AH, AL           { doubled into AX, so one STOSW does two pixels     }
  REP  STOSW            { the fill, one instruction                         }
end;

{ --------------------------------------------------------------------------
  11e3:03F8 -- YOfs[I] := I * 320, for I = 0..199. Compiled Pascal.
  -------------------------------------------------------------------------- }
procedure BuildRowTable;
var
  I : Integer;
begin
  for I := 0 to ScrHeight - 1 do
    YOfs[I] := I * ScrWidth;
end;

{ 11e3:041D -- the unit's initialisation calls BuildRowTable and nothing else. }
begin
  BuildRowTable;
end.
