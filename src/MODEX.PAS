{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the shared Mode-X unit.

  MODE X: 320x200 in 256 colours with the four planes UNCHAINED, which is what
  makes hardware panning possible. Four routines -- set the mode, build a row
  offset table, select a plane, and move the visible window.

  The point of unchaining is that video memory stops being one linear run of
  bytes and becomes four interleaved planes, each addressed separately. That
  costs you a plane select before every write, and buys two things the demo
  needs: all 256K of VGA memory becomes reachable, so a canvas can be WIDER
  than the screen, and the CRTC can then be told to show a window into it. Pan
  by moving the window, not by redrawing.

  So the unit divides in two. SetModeX and SelectPlane are about the hardware
  arrangement; BuildRowTable and ShowFrame are about the canvas laid out inside
  it -- LogicalWidth is how wide that canvas is, in bytes per row.

  Parts differ in which routines they contain, because Turbo Pascal's smart
  linker drops what a part never calls: part 003 never pans, so it carries no
  ShowFrame.

  [re] ONE UNIT, LINKED BY THE PARTS THAT NEED IT. Segment 107c in part 002 and
  1192 in part 003, and as with VGA and DemoVT the two are the same source
  with Turbo Pascal's smart linker dropping whatever a part never calls:
      #  routine          002        003
      1  BuildRowTable    107c:0000  1192:0000
      2  ShowFrame        107c:002a  --
      3  SetModeX         107c:006d  1192:002a
      4  SelectPlane      107c:00ca  1192:0087
  Part 003 never pans, so ShowFrame is absent and everything after it moves
  up by exactly its length -- $6D - $2A = $43, and 1192's SelectPlane sits
  $43 below 107c's. SetModeX is 93 bytes in both and the two are byte for
  byte identical apart from the one address the last instruction reads
  LogicalWidth from.

  [re] THAT COMPARISON FOUND A BUG. VGA.PAS used to carry its own transcription of
  this routine as `SetMode`, read from part 003, and it was wrong in three
  places: it reloaded DX with an immediate twice where the original does
  DEC DX, and -- the one that matters -- it left out the REP STOSW that
  clears all 64K of video memory. The bytes at 1192:002a plainly contain it.
  Part 003 scene 3 was therefore starting in whatever the previous scene had
  left in VRAM. That transcription is gone; this is the routine.

  =========================================================================== }

{ 286 instructions are permitted; ShowFrame uses a two-bit shift. }
{$G+}   { [re] 286 instructions: 107c:0039 is SHR AX,2 in ShowFrame. }

unit ModeX;

interface

const
  { Rows in the offset table -- four times the 200 on screen, because the
    canvas may be taller than the display as well as wider. }
  RowCount = 800;                       { [re] $320 -- the table 107c:0000 fills }

const
  { HOW WIDE THE CANVAS IS, in bytes per plane per row, and it is deliberately
    writable. $50 is 80 bytes x 4 planes = 320 pixels, the same as the screen.
    A scene that wants to pan raises it and gets a canvas wider than the
    display: part 002 scene 1 sets $A0 for a 1280-pixel canvas, and part 003
    puts it back to $50.

    A TYPED CONSTANT, WHICH IS THE POINT -- in Turbo Pascal that means
    initialised AND writable, so the value is in the file image and the code can
    still store over it. `var` would give a writable variable with no initial
    value, which is a different thing entirely.

    Both BuildRowTable and SetModeX read it: one to compute row offsets, the
    other to program the CRTC. Change it and rebuild the table, or the two
    disagree about the layout.

    [re] DS:$0002 here, DS:$76B6 in part 003 -- the CRTC Offset value and the
    multiplier BuildRowTable uses. A TYPED constant, so the compiled-in $50 is
    in the file image and the code can still write over it: Demo_Scene1 stores
    $A0 (1008:0727) to make that scene's canvas 1280 wide, and part 003's
    InitScene writes $50 back.

    [re] Declared `var` it was in BSS and stored NOTHING, which left a two-byte hole
    between the morph unit's shape tables and the sprite unit's captions and
    put every variable behind it two bytes low. `var` against `const X : T = v`
    is not variable against constant -- it is uninitialised against
    initialised, and both are writable. }
  LogicalWidth : Byte = $50;

var
  { The byte offset of the start of each canvas row, so drawing a pixel costs
    a table lookup instead of a multiply. Built by BuildRowTable and stale the
    moment LogicalWidth changes.

    [re] DS:$4B08 -- RowOfs[I] = LogicalWidth * I * 2. }
  RowOfs : array[0..RowCount - 1] of Word;

{ Fill RowOfs from the current LogicalWidth. Call after changing it. }
procedure BuildRowTable;                       far;   { 107c:0000 }
{ Point the CRTC at a window into the canvas -- this is the pan. }
{ [re] @asm 002 107c:002a }
procedure ShowFrame(X, Row : Integer);         far;   { 107c:002a }
{ Put the VGA into unchained 256-colour mode and clear its memory. }
{ [re] @asm 002 107c:006d }
procedure SetModeX;                            far;   { 107c:006d }
{ Choose which of the four planes subsequent writes land in, 0..3. }
{ [re] @asm 002 107c:00ca }
procedure SelectPlane(P : Byte);               far;   { 107c:00ca }

implementation

{ --------------------------------------------------------------------------
  Fill in the row offset table: row I starts at LogicalWidth * I * 2 bytes.

      for I := 0 to 799 do
        RowOfs[I] := (LogicalWidth * I) shl 1

  THE ARITHMETIC IS SIXTEEN BIT AND IT WRAPS, past about row 204 at the default
  width. That is the original's behaviour and not a defect to be widened: no
  scene addresses a row that high, and the table's later entries are never
  read.
  -------------------------------------------------------------------------- }
procedure BuildRowTable;
var
  I : Integer;
begin
  for I := 0 to RowCount - 1 do
    RowOfs[I] := Word(LogicalWidth) * Word(I) shl 1;
end;

{ --------------------------------------------------------------------------
  107c:002a -- point the CRTC at (X, Row) and pan.

      BX := RowOfs[Row] + (X shr 2)
      CRTC $0C := hi(BX)                start address high
      CRTC $0D := lo(BX)                start address low
      wait for the START of vertical retrace
      ATC  $13 := (X and 3) * 2         horizontal pixel panning
      ATC      := $20                   re-enable the palette

  PARAMETER ORDER. RET 4, so two words: BP+8 and BP+6. BP+8 is the higher, so
  it is the FIRST declared -- and BP+8 is the one used as X (it is shifted
  right by two for the byte offset and masked with 3 for the pan). BP+6 is the
  row. Scene1_Run calls it as (I, 0) while I sweeps 0..960, which is the pan.

  Note the start address is written BEFORE the wait, not after. That is what
  the code does.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      B := RowOfs[Row] + Word(X) shr 2;
      PortW[$3D4] := (B and $FF00) or $0C;
      PortW[$3D4] := ((B and $00FF) shl 8) or $0D;
      while (Port[$3DA] and 8) <> 0 do ;
      while (Port[$3DA] and 8) =  0 do ;
      Port[$3C0] := $13;
      Port[$3C0] := (X and 3) shl 1;
      Port[$3C0] := $20;

  That Pascal would work, but it is not what is there: the original keeps the
  start address in BX across the whole routine and assembles each CRTC write
  as one word OUT with the index in AL and the value in AH, which Pascal can
  only reach by building the word arithmetically.
  -------------------------------------------------------------------------- }
procedure ShowFrame(X, Row : Integer); assembler;
asm
  MOV  BX, Row            { the row to start the display at                }
  SHL  BX, 1              { * 2, a word index into the row table           }
  MOV  BX, [BX + OFFSET RowOfs]  { BX := RowOfs[Row], the row's byte offset }
  MOV  AX, X              { the horizontal position, in pixels             }
  SHR  AX, 2              { div 4 -- Mode X stores every 4th pixel in a    }
                          {   plane, so four pixels share one byte offset  }
  ADD  BX, AX             { BX := the display start address                }
  MOV  AH, BH             { high byte of it                                }
  MOV  AL, $0C            { CRTC register $0C: start address high          }
  MOV  DX, $3D4           { CRTC address register                          }
  OUT  DX, AX             { index and value in one 16-bit OUT              }
  MOV  AH, BL             { low byte of the start address                  }
  MOV  AL, $0D            { CRTC register $0D: start address low           }
  OUT  DX, AX             { DX is still $3D4                               }
  MOV  DX, $3DA           { input status register 1                        }
@@InRetrace:            { <- spin while a retrace is already running    }
  IN   AL, DX             { read the status                                }
  AND  AL, 8              { bit 3 is vertical retrace                      }
  JNZ  @@InRetrace        { one is already running -- wait it out          }
@@WaitRetrace:          { <- then spin until the next one begins         }
  IN   AL, DX             { read again                                     }
  AND  AL, 8              { still bit 3                                    }
  JZ   @@WaitRetrace      { wait for the NEXT one to start                 }
  MOV  DX, $3C0           { attribute controller                           }
  MOV  AL, $13            { register $13: horizontal pixel panning         }
  OUT  DX, AL             { select it                                      }
  MOV  AX, X              { the horizontal position again                  }
  AND  AL, 3              { the remainder the SHR 2 above threw away       }
  SHL  AL, 1              { * 2 -- the panning register counts half-pixels }
  OUT  DX, AL             { pan by it, so the scroll is pixel-exact        }
  MOV  AL, $20            { bit 5 set: re-enable the palette. The ATC      }
  OUT  DX, AL             {   blanks the screen while it is being indexed  }
end;

{ --------------------------------------------------------------------------
  PUT THE VGA INTO UNCHAINED 256-COLOUR MODE, and give it a logical line
  possibly wider than the screen.

  Six register groups in order: start from BIOS mode 13h, turn off the three
  bits that chain the planes together, enable all four planes for writing,
  clear all 64K of video memory, switch the CRTC from doubleword to byte
  addressing, and finally program the Offset register from LogicalWidth. The
  clear is not optional -- without it a scene starts in whatever the previous
  one left behind.

  [re] 107c:006d -- unchained 256-colour mode with a wide logical line.
      INT $10, AX = $0013
      SEQ  $04 := (v and $F7) or $04      Chain-4 off, odd/even off
      GC   $05 := v and $EF               shift/odd-even off
      GC   $06 := v and $FD               chain odd/even off
      SEQ  $02 := $0F                     all four planes enabled
      clear $A000 for $8000 words         = 65,536 bytes
      CRTC $14 := v and $BF               dword mode off
      CRTC $17 := v or $40                byte mode on
      CRTC $13 := DS:$0002                the logical line width

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      asm mov ax,$13; int $10 end;          -- no Pascal equivalent at all
      Port[$3C4] := 4;  Port[$3C5] := (Port[$3C5] and $F7) or $04;
      Port[$3CE] := 5;  Port[$3CF] :=  Port[$3CF] and $EF;
      Port[$3CE] := 6;  Port[$3CF] :=  Port[$3CF] and $FD;
      PortW[$3C4] := $0F02;
      FillChar(Mem[$A000 : 0], 65536, 0);
      Port[$3D4] := $14; Port[$3D5] := Port[$3D5] and $BF;
      Port[$3D4] := $17; Port[$3D5] := Port[$3D5] or  $40;
      Port[$3D4] := $13; Port[$3D5] := LogicalWidth;

  The mode set itself cannot be written in Pascal without an asm block for the
  INT, and FillChar of 65,536 bytes is a LongInt count Turbo Pascal will not
  take -- it would have to be two calls.
  -------------------------------------------------------------------------- }
procedure SetModeX; assembler;
asm
  MOV  AX, $0013     { BIOS mode $13: 320x200, 256 colours, chained       }
  INT  $10           { set it -- everything below un-chains it            }

  MOV  DX, $03C4     { Sequencer address register                         }
  MOV  AL, $04       { register 4 -- Memory Mode                          }
  OUT  DX, AL        { select it                                          }
  INC  DX            { DX := $3C5, the Sequencer data register            }
  IN   AL, DX        { read what is there                                 }
  AND  AL, $F7       { clear bit 3: Chain-4 off -- this is the un-chaining }
  OR   AL, $04       { set bit 2: odd/even addressing off                 }
  OUT  DX, AL        { write it back                                      }

  MOV  DX, $03CE     { Graphics Controller address register               }
  MOV  AL, $05       { register 5 -- Mode                                 }
  OUT  DX, AL        { select it                                          }
  INC  DX            { DX := $3CF, the GC data register                   }
  IN   AL, DX        { read it                                            }
  AND  AL, $EF       { clear bit 4: host odd/even off                     }
  OUT  DX, AL        { write it back                                      }

  DEC  DX            { back to the GC address register                    }
  MOV  AL, $06       { register 6 -- Miscellaneous                        }
  OUT  DX, AL        { select it                                          }
  INC  DX            { DX := $3CF again                                   }
  IN   AL, DX        { read it                                            }
  AND  AL, $FD       { clear bit 1: chain odd/even off                    }
  OUT  DX, AL        { write it back                                      }

  MOV  DX, $03C4     { Sequencer address register                         }
  MOV  AX, $0F02     { register 2 (Map Mask) := $0F, all four planes      }
  OUT  DX, AX        { so the clear below reaches every plane at once     }

  MOV  AX, $A000     { video memory                                       }
  MOV  ES, AX        {                                                    }
  SUB  DI, DI        { start at offset 0                                  }
  MOV  AX, 0         { the fill value: black                              }
  MOV  CX, $8000     { $8000 words = 65,536 bytes = the whole 64K window, }
                     {   which with four planes enabled is 256K of VRAM   }
  CLD                { forwards                                           }
  REP  STOSW         { clear it -- mode 13h left a screen behind          }

  MOV  DX, $03D4     { CRTC address register                              }
  MOV  AL, $14       { register $14 -- Underline Location                 }
  OUT  DX, AL        { select it                                          }
  INC  DX            { DX := $3D5, the CRTC data register                 }
  IN   AL, DX        { read it                                            }
  AND  AL, $BF       { clear bit 6: doubleword addressing off             }
  OUT  DX, AL        { write it back                                      }

  DEC  DX            { back to the CRTC address register                  }
  MOV  AL, $17       { register $17 -- Mode Control                       }
  OUT  DX, AL        { select it                                          }
  INC  DX            { DX := $3D5                                         }
  IN   AL, DX        { read it                                            }
  OR   AL, $40       { set bit 6: byte addressing on. With $14 bit 6      }
  OUT  DX, AL        {   cleared, that is what makes the mode linear      }

  MOV  DX, $03D4     { CRTC address register                              }
  MOV  AL, $13       { register $13 -- Offset, the logical line width     }
  OUT  DX, AL        { select it                                          }
  INC  DX            { DX := $3D5                                         }
  MOV  AL, [LogicalWidth]  { $50 normally, more for a panning             }
                     {   scene: the visible 320 becomes a window on it    }
  OUT  DX, AL        { write it, and the mode is set                      }
end;

{ --------------------------------------------------------------------------
  107c:00ca -- Map Mask := 1 shl P, written as a single word OUT to $3C4.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      PortW[$3C4] := ((Word(1) shl (P and 3)) shl 8) or $02;

  Note the original does NOT mask P with 3 -- SHL AH,CL with CL above 7 just
  shifts the bit out and disables every plane. Nothing calls it that way.
  -------------------------------------------------------------------------- }
procedure SelectPlane(P : Byte); assembler;
asm
  MOV  AL, 2              { Sequencer register 2 -- Map Mask               }
  MOV  AH, 1              { one bit, for plane 0                           }
  MOV  CL, P              { the plane wanted                               }
  SHL  AH, CL             { move the bit to that plane's position          }
  MOV  DX, $3C4           { Sequencer address register                     }
  OUT  DX, AX             { index in AL, mask in AH, one 16-bit OUT        }
end;

{ 107c:00de -- the unit's initialisation calls BuildRowTable.

  DS:$0002 is initialised data, so it already holds $50 when the table is
  first built; a scene that wants a different width stores its own value and
  calls BuildRowTable again, which is what Demo_Scene1 does through SetModeX. }
{ THE UNIT INITIALISES ITSELF BY BUILDING THE ROW TABLE, and does nothing
  else. It does NOT set LogicalWidth, because it does not need to: a typed
  constant is already in the initialised data image before a single
  instruction runs. So the table is correct for the default width from the
  moment the unit loads, and a scene that changes the width calls
  BuildRowTable again itself.

  [re] It used to store $50 into
  LogicalWidth first, which is redundant -- LogicalWidth is a TYPED CONSTANT
  declared `: Byte = $50`, so the value is already in the initialised data image
  before a single instruction runs -- and the original does not do it. 107c:00e1
  is PUSH BP / MOV BP,SP / PUSH CS / CALL BuildRowTable / LEAVE / RETF and
  nothing else; ours had MOV BYTE PTR [$0002],$50 in the middle of it, five
  bytes re-storing a byte that was already correct.

  [re] IT WAS INVISIBLE TO THE COVERAGE WALK, which stops reading each segment when
  fewer than ANCHOR bytes remain and so never examines the last nine -- exactly
  where an initialisation section sits. Found by comparing the segment tails
  directly. }
begin
  BuildRowTable;
end.
