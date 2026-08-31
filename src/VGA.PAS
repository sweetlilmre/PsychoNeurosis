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

  [re] ONE UNIT, SEVEN EXECUTABLES. Every part links this same source and Turbo
  Pascal's SMART LINKER drops whatever that part never calls, which is why
  the segment is a different size and the addresses are different in each --
  and why an earlier pass mistook the subsets for four separate units.

  [re] The proof is the ORDER. Routines come out in source order with the unused
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

  The Mode-X routines are NOT here. They are in MODEX.PAS, which is the unit
  to read for unchained mode, plane selection and panning.

  [re] Anchors: SetMode13h is six bytes at offset 0 of the unit in all seven.
  Part 001 has DrawLine at 1491:0048 and part 004 at 11e3:009c purely because
  004 also links GetPixel and FillRect ahead of it. Part 003 gets PutPixel at
  12f8:0048 for the same reason in reverse.

  [re] So there is no "part 004 FillRect" distinct from anything here -- FillRect
  is in this unit, and parts 004 and 006 are simply the only two that call
  it. Their copies are byte-identical.

  [re] The Mode-X routines that used to be in this file have moved to MODEX.PAS,
  where they belong -- segment 1192 in part 003, 107c in part 002.

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

  [re] How we can tell: VGA_WaitRetrace has no procedure prologue whatsoever, the
  blit and clear are REP MOVSW / REP STOSW with CX preloaded, and PutPixel
  indexes a precomputed row table and falls straight into STOSB. Borland
  Pascal 7 does not generate any of that shape -- it would emit ENTER/LEAVE,
  BP-relative locals and a multiply for the row offset.

  [re] All of them end in RETF n, i.e. far procedures using the Pascal calling
  convention with callee stack cleanup -- so they are `procedure ...; far;
  assembler;` in the original source.

  [re] ADDRESS MAP
    PutPixel        12f8:0048      SetRGB          12f8:0064
    GetRGB          12f8:007f      WaitRetrace     12f8:009f
    CopyScreen      12f8:00ad      ClearScreen     12f8:00c9
    SetMode         1192:002a      SelectPlane     1192:0087

  =========================================================================== }

{ ===========================================================================
  [re] A NOTE ON PARAMETER ORDER -- read this before changing any signature here.

  [re] Borland Pascal pushes parameters LEFT TO RIGHT, and the stack grows DOWN.
  So inside the callee the FIRST (leftmost) parameter is at the HIGHEST [BP+n]
  offset, and the last is at the lowest:
      procedure P(A, B, C);   near   ->   [BP+8]=A  [BP+6]=B  [BP+4]=C

  [re] Ghidra's decompiler prints arguments in ASCENDING [BP+n] order, which is the
  REVERSE of the declaration. Taking that listing as the signature is how the
  whole of this unit ended up backwards on the first pass -- the behaviour was
  right, because the call sites were reversed to match, but the signatures did
  not correspond to the binary at all.

  [re] The orders below are read off the disassembly and are the originals.
  =========================================================================== }

{ 286 instructions are permitted -- the palette routines use REP OUTSB and
  REP INSB, which move all 768 DAC bytes in one instruction each. }
{$G+}   { [re] 286 instructions: REP OUTSB and REP INSB in the palette routines.
          The original targets 386 and above. }

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
  { [re] THE ORDER OF THESE THREE IS MEASURED, and YOfs came FIRST here, which put
    every one of them 400 bytes out. Part 001 has VirtScr at DS:$AB54,
    VirtScrSeg at DS:$AB58 and YOfs at DS:$AB5A -- 1107:0583 pushes [$AB58] as
    the screen segment and 12b2:010f indexes [$AB5A] after SHL BX,1, so the
    pointer and its segment precede the table. }

  { The virtual screen every part draws into before blitting to $A000.
    64,000 bytes on the heap; VirtScrSeg is its segment, and because GetMem
    returns a normalised pointer the offset is always 0 -- which is why every
    part addresses it as a bare segment. }
  VirtScr    : Pointer;                 { [re] part 001: DS:$AB54 }
  VirtScrSeg : Word;                    { [re] part 001: DS:$AB58 }
  { Row offset lookup: YOfs[y] is y * 320, the byte offset of row y. PutPixel
    indexes this rather than multiplying, which is why it needs no MUL -- the
    saving is per pixel, so it is the whole reason the table exists.

    [re] DS:$AB5A in part 001. }
  YOfs       : array[0..ScrHeight - 1] of Word;


  { THERE IS NO SHARED PALETTE BUFFER IN THIS UNIT, deliberately. Every palette
    routine below takes a POINTER to the caller's own 768 bytes, so a scene owns
    its palette and two scenes cannot tread on each other.

    [re] Palette WAS DECLARED HERE and the original's VGA has no such global. Every
    palette routine in segment 1491 takes a POINTER: 1491:01c6 and 1491:01f6
    load it off [BP+6]. The only thing that used it was part 001 scene 1's
    loader, whose original reads into an SS-relative local at [BP-$400], and
    part 001 scene 2 has its own unit-level buffer at DS:$56D2. Part 003's
    sprite scene had already recorded the same about itself. }

procedure SetMode13h;
procedure SetTextMode;
{ BuildRowTable IS NOT IN THE INTERFACE. It fills YOfs and the unit calls it
  from its own initialisation, so it is done before any caller could need it.
  Nothing outside reaches it -- and note that MODEX has a BuildRowTable of its
  own for the Mode-X row table, which is a different table for a different
  layout. Two routines, same name, different units.

  [re] and part 007 says so in one byte.
  Its segment 100b is the whole of this unit smart-linked down to four items,
  and 100b:0030 is C3 -- a NEAR return. Turbo Pascal compiles every interface
  routine FAR, so a near return means the routine is implementation-only; and
  100b:0034 is E8 D5 FF, a NEAR call to it from the initialisation section,
  which is the same fact from the caller's side. Nothing outside this unit calls
  it: ModeX declares its own BuildRowTable and that is the one part 002 scene 1
  reaches. Declared here it returned FAR and cost a byte at both ends. }
procedure VirtScrAlloc;
procedure VirtScrFree;
procedure ClearVirtual;
procedure DrawLine(X1, Y1, X2, Y2 : Integer; Colour : Byte; Segment : Word);

{ The palette machinery. These are part 001's copy of the unit (segment 1491)
  and are NOT in part 003's (12f8/1192), which is what this file was first
  transcribed from -- so they were missing altogether until part 001 scene 2
  turned out to have no fade at either end. }
{ [re] @asm 004 11e3:0230 }
procedure SetPalette768(P : Pointer);                far;   { 1491:01C2 }
{ [re] @asm 004 11e3:0248 }
procedure GetPalette768(P : Pointer);                far;   { 1491:01DA }
{ [re] @asm 001 1491:0202 }
procedure PaletteDim(P : Pointer);                   far;   { 1491:01F2 }
procedure PaletteFadeUp(P : Pointer; Pause : Word);  far;   { 1491:0215 }
procedure PaletteFadeOut(Pause : Word);              far;   { 1491:0330 }

{ [re] @asm 003 12f8:0048 }
procedure PutPixel(X, Y : Word; Colour : Byte; Segment : Word); far;
{ [re] @asm 004 11e3:0048 }
function  GetPixel(X, Y : Integer; Segment : Word) : Byte;      far;
{ [re] @asm 004 11e3:0063 }
procedure FillRect(X1, Y1, X2, Y2 : Integer;
                   Colour : Byte; Segment : Word);              far;
{ [re] @asm 004 11e3:01db }
procedure SetRGB(Col, R, G, B : Byte); far;
{ [re] @asm 003 12f8:007f }
procedure GetRGB(Col : Byte; var R, G, B : Byte); far;
{ [re] @asm 004 11e3:01f6 }
procedure SetRGBFrom(Col : Byte; P : Pointer);    far;
{ [re] @asm 004 11e3:0216 }
procedure GetRGBTo(Col : Byte; P : Pointer);      far;
procedure FadeStep;                               far;
{ [re] @asm 003 12f8:009f }
procedure WaitRetrace; far;
{ [re] @asm 003 12f8:00ad }
procedure CopyScreen(SrcSeg, DestSeg : Word); far;
{ [re] @asm 003 12f8:00c9 }
procedure ClearScreen(Segment : Word; Colour : Byte); far;

implementation

uses Crt;   { Delay, in the palette fades }

{ [re] ROUTINE ORDER IS THE ORIGINAL'S. Turbo Pascal emits a unit's code in
  implementation order, so the order here IS the segment layout, and a
  far call from another unit encodes the callee's OFFSET. Part 002's VGA
  segment runs SetMode13h at 1436:0000, VirtScrAlloc at 1436:0006 and
  VirtScrFree at 1436:0033 before anything else; these three sat after
  CopyScreen here, which put CopyScreen at offset $9c against the
  original's $128 and made every far call to it differ in four bytes --
  a run the coverage walk's rule cannot forgive. }
{ EQUIVALENT PASCAL -- REFERENCE ONLY, and not what is compiled:

      procedure SetMode13h;
      begin
        asm MOV AX, $0013; INT $10 end;
      end;

  which is the same two instructions with a stack frame around them. The
  original has no frame, so the procedure is `assembler`.

  [re] NO @asm MARKER HERE, deliberately. A marker is a claim that the bytes can
  be compared, and this routine is stripped from every harness we build --
  nothing in the reconstruction references it, so routines.py reported it
  NOT FOUND in any built image. That the ORIGINAL's part 002 does carry it at
  1436:0000 means something there calls it and nothing here does. }
procedure SetMode13h; assembler;
asm
  { [re] SIX BYTES: 1436:0000 is `MOV AX,$13 / INT $10 / RETF` and nothing else.
    BuildRowTable was called from here and does not belong -- the row table
    is built by the unit's INITIALIZATION, which is what 1436:017f is:
    seventeen bytes of `PUSH BP / MOV BP,SP / CALL $015A / LEAVE / RETF`,
    emitted last as a unit's initialization always is. There is no frame
    either -- six bytes leaves no room for one -- so this is `assembler`. }
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
  { [re] TWENTY-ONE BYTES at 1436:0033, and all of them are the FreeMem: push the
    far pointer, push 64000, call, leave, return. There is no nil guard and
    nothing is cleared afterwards. }
  FreeMem(VirtScr, 64000);
end;

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
  MOV  DI, [BX + OFFSET YOfs]   { DI := YOfs[Y], the row's byte offset      }
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
  12f8:0064 -- write one DAC entry. Index to $3C8, then R,G,B to $3C9.
  -------------------------------------------------------------------------- }
{ [re] AND IT SITS HERE, BEFORE SetRGB, because the original's segment says so:
  11ee:00b8 is this routine and 11ee:01f7 is SetRGB, and part 004's copy has
  the same order at 11e3:009c and 11e3:01db. Declared last in the unit, as it
  was, every VGA routine after FillRect sits at the wrong offset and every far
  call to one of them from another unit differs. The order of a unit's
  implementations is a measurement, not a matter of taste. }
{ --------------------------------------------------------------------------
  DrawLine -- a Bresenham line, and only the parts that actually draw one link
  it. That is why no two copies of this unit are the same size.

  [re] Part 001's copy of this unit is LARGER than part
  003's precisely because it carries this routine (1491:0048); parts that
  never draw a line do not link it.

  Argument order is the original's: segment, colour, then the two endpoints
  as (Y, X) pairs rather than (X, Y).
  -------------------------------------------------------------------------- }
procedure DrawLine(X1, Y1, X2, Y2 : Integer; Colour : Byte; Segment : Word);
  assembler;
var
  { Four words. THE FIRST TWO ARE REUSED for a second purpose partway through
    -- see the note above the asm block, which is the only place that says so.

    [re] Declared in this order so they land at [BP-2], [BP-4],
    [BP-6] and [BP-8], which is where 11ee:00b8 puts them. }
  DXAbs, DYAbs : Integer;         { |dx| and |dy|, then flags }
  Inc1, Inc2   : Integer;         { the two error increments  }
asm
    MOV  AX, Segment       { 11ee:00bc                                       }
    MOV  ES, AX            { 11ee:00bf  loaded ONCE, and never reloaded       }
    MOV  BX, Y1            { 11ee:00c1                                       }
    ADD  BX, BX            { 11ee:00c4  a Word index into the row table       }
    MOV  DI, WORD PTR YOfs[BX]      { 11ee:00c6  Y1 * 320                              }
    ADD  DI, X1            { 11ee:00ca  the first pixel's offset              }

    MOV  AX, X1            { 11ee:00cd                                       }
    SUB  AX, X2            {                                                  }
    JG   @@DXOK            { 11ee:00d3  <= 0, so negate -- Abs, and negating  }
    NEG  AX                { 11ee:00d5    zero is harmless, which is why the  }
@@DXOK:                    {              test is JG and not JGE             }
    MOV  DXAbs, AX         { 11ee:00d7                                       }
    MOV  AX, Y1            { 11ee:00da                                       }
    SUB  AX, Y2            {                                                  }
    JG   @@DYOK            { 11ee:00e0                                       }
    NEG  AX                { 11ee:00e2                                       }
@@DYOK:
    MOV  DYAbs, AX         { 11ee:00e4                                       }
    CMP  AX, DXAbs         { 11ee:00e7  which axis is the major one?          }
    JLE  @@Shallow         { 11ee:00ea  |dy| <= |dx|: step along X            }
    JMP  @@Steep           { 11ee:00ec                                       }

{ ---- shallow: X is the major axis, one step per column ---- }
@@Shallow:
    MOV  CX, DXAbs         { 11ee:00ef  the loop count                        }
    SHL  AX, 1             { 11ee:00f2  AX is still |dy|                      }
    MOV  Inc1, AX          { 11ee:00f4  2 * |dy|                              }
    SUB  AX, DXAbs         { 11ee:00f7                                       }
    MOV  BX, AX            { 11ee:00fa  BX is the error term, in a register   }
    MOV  AX, DYAbs         { 11ee:00fc                                       }
    SUB  AX, DXAbs         { 11ee:00ff                                       }
    SHL  AX, 1             { 11ee:0102                                       }
    MOV  Inc2, AX          { 11ee:0104  2 * (|dy| - |dx|)                     }

    MOV  DXAbs, 0          { 11ee:0107  REUSED: 0 means X counts down         }
    MOV  AX, X1            { 11ee:010c                                       }
    SUB  AX, X2            {                                                  }
    JG   @@SXSet           { 11ee:0112                                       }
    MOV  DXAbs, 1          { 11ee:0114    X1 <= X2, so X counts up            }
@@SXSet:
    MOV  DYAbs, 0          { 11ee:0119  REUSED the same way for Y             }
    MOV  AX, Y1            { 11ee:011e                                       }
    SUB  AX, Y2            {                                                  }
    JG   @@SYSet           { 11ee:0124                                       }
    MOV  DYAbs, 1          { 11ee:0126                                       }
@@SYSet:
    MOV  AL, Colour        { 11ee:012b  AL holds the colour for both loops    }
    MOV  ES:[DI], AL       { 11ee:012e  the first pixel                       }
    CMP  CX, 0             { 11ee:0131                                       }
    JZ   @@SDone           { 11ee:0134  a zero-length line is one pixel, and
                             the target is the JMP below, NOT @@Out: the
                             original's is `JE $016E`, two bytes, where a jump
                             all the way to the routine's end needs the long
                             form and three more. Those three bytes put every
                             VGA routine after this one at the wrong offset. }

@@SLoop:
    CMP  DXAbs, 0          { 11ee:0136                                       }
    JZ   @@SLeft           { 11ee:013a                                       }
    INC  DI                { 11ee:013c                                       }
    JNC  @@SErr            { 11ee:013d  the carry fix-up below is vestigial:  }
    INC  DX                { 11ee:013f    DX is never initialised and never   }
    JMP  @@SErr            { 11ee:0140    reaches ES                         }
@@SLeft:
    DEC  DI                { 11ee:0142                                       }
    JNC  @@SErr            { 11ee:0143                                       }
    DEC  DX                { 11ee:0145                                       }
@@SErr:
    CMP  BX, 0             { 11ee:0146                                       }
    JGE  @@SStep           { 11ee:0149                                       }
    ADD  BX, Inc1          { 11ee:014b  no minor-axis step this time          }
    JMP  @@SPlot           { 11ee:014e                                       }
@@SStep:
    ADD  BX, Inc2          { 11ee:0150                                       }
    CMP  DYAbs, 0          { 11ee:0153                                       }
    JZ   @@SUp             { 11ee:0157                                       }
    ADD  DI, 320           { 11ee:0159                                       }
    JNC  @@SPlot           { 11ee:015d                                       }
    INC  DX                { 11ee:015f                                       }
    JMP  @@SPlot           { 11ee:0160                                       }
@@SUp:
    SUB  DI, 320           { 11ee:0162                                       }
    JNC  @@SPlot           { 11ee:0166                                       }
    DEC  DX                { 11ee:0168                                       }
@@SPlot:
    MOV  ES:[DI], AL       { 11ee:0169                                       }
    LOOP @@SLoop           { 11ee:016c                                       }
@@SDone:
    JMP  @@Out             { 11ee:016e                                       }

{ ---- steep: Y is the major axis, one step per row. The mirror of the above,
       with the two axes exchanged everywhere. ---- }
@@Steep:
    MOV  CX, DYAbs         { 11ee:0171                                       }
    MOV  AX, DXAbs         { 11ee:0174                                       }
    SHL  AX, 1             { 11ee:0177                                       }
    MOV  Inc1, AX          { 11ee:0179  2 * |dx|                              }
    SUB  AX, DYAbs         { 11ee:017c                                       }
    MOV  BX, AX            { 11ee:017f                                       }
    MOV  AX, DXAbs         { 11ee:0181                                       }
    SUB  AX, DYAbs         { 11ee:0184                                       }
    SHL  AX, 1             { 11ee:0187                                       }
    MOV  Inc2, AX          { 11ee:0189                                       }

    MOV  DXAbs, 0          { 11ee:018c                                       }
    MOV  AX, X1            { 11ee:0191                                       }
    SUB  AX, X2            {                                                  }
    JG   @@TXSet           { 11ee:0197                                       }
    MOV  DXAbs, 1          { 11ee:0199                                       }
@@TXSet:
    MOV  DYAbs, 0          { 11ee:019e                                       }
    MOV  AX, Y1            { 11ee:01a3                                       }
    SUB  AX, Y2            {                                                  }
    JG   @@TYSet           { 11ee:01a9                                       }
    MOV  DYAbs, 1          { 11ee:01ab                                       }
@@TYSet:
    MOV  AL, Colour        { 11ee:01b0                                       }
    MOV  ES:[DI], AL       { 11ee:01b3                                       }
    CMP  CX, 0             { 11ee:01b6                                       }
    JZ   @@Out             { 11ee:01b9                                       }

@@TLoop:
    CMP  DYAbs, 0          { 11ee:01bb                                       }
    JZ   @@TUp             { 11ee:01bf                                       }
    ADD  DI, 320           { 11ee:01c1                                       }
    JNC  @@TErr            { 11ee:01c5                                       }
    INC  DX                { 11ee:01c7                                       }
    JMP  @@TErr            { 11ee:01c8                                       }
@@TUp:
    SUB  DI, 320           { 11ee:01ca                                       }
    JNC  @@TErr            { 11ee:01ce                                       }
    DEC  DX                { 11ee:01d0                                       }
@@TErr:
    CMP  BX, 0             { 11ee:01d1                                       }
    JGE  @@TStep           { 11ee:01d4                                       }
    ADD  BX, Inc1          { 11ee:01d6                                       }
    JMP  @@TPlot           { 11ee:01d9                                       }
@@TStep:
    ADD  BX, Inc2          { 11ee:01db                                       }
    CMP  DXAbs, 0          { 11ee:01de                                       }
    JZ   @@TLeft           { 11ee:01e2                                       }
    INC  DI                { 11ee:01e4                                       }
    JNC  @@TPlot           { 11ee:01e5                                       }
    INC  DX                { 11ee:01e7                                       }
    JMP  @@TPlot           { 11ee:01e8                                       }
@@TLeft:
    DEC  DI                { 11ee:01ea                                       }
    JNC  @@TPlot           { 11ee:01eb                                       }
    DEC  DX                { 11ee:01ed                                       }
@@TPlot:
    MOV  ES:[DI], AL       { 11ee:01ee                                       }
    LOOP @@TLoop           { 11ee:01f1                                       }
@@Out:
end;

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
{$I SETRGB.INC}

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
  Set all 256 DAC entries from a caller's 768-byte buffer: select colour 0,
  then REP OUTSB the lot. The DAC auto-increments, so one instruction writes
  every entry.

  [re] 1491:01C2 -- out $3C8 := 0 then REP OUTSB 768 bytes from P^.
  1436:0083 in part 002, 11e3:0230 in part 004 -- the same bytes.

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
  ONE STEP OF A FADE, applied to a palette buffer in place: walk all 768 bytes
  and decrement every non-zero one, stepping over the zeroes. Call it
  repeatedly and the palette walks down to black; a component that has reached
  zero stays there, so the fade ends of its own accord.

  [re] 1491:01F2 -- walk 768 bytes; every NON-ZERO one is decremented in place and
  written back, zeroes are stepped over (the JZ at 1491:0202 skips the STOSB
  and just bumps DI).

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

{ [re] AND IT SITS BETWEEN FadeStep AND WaitRetrace, which part 004's copy fixes
  exactly: 11e3:0260 is FadeStep, 02b9 this routine, 03d4 WaitRetrace's
  fourteen bytes and 03e2 ClearScreen -- 02b9 to 03d4 is $11B, which is this
  routine's length. Declared near the end of the unit instead, ClearScreen came
  out 283 bytes early in parts 001 and 004 and every far call to it differed.
  Part 001's copy agrees from the other side: PaletteDim at 1491:01F2 is 35
  bytes and this routine follows at 0215. }

{ --------------------------------------------------------------------------
  11e3:0260 -- one step of a fade to black, on the LIVE DAC. Compiled Pascal.
  Only part 004 links it.

  Not the same routine as PaletteDim above: that one dims a buffer the caller
  owns, this one reads the hardware back, dims it and writes it out. Both are
  in the unit; each part keeps whichever it calls.

  [re] THE LOOP IS HAND-WRITTEN ASSEMBLER, and reading the frame is what showed it.
  The routine opens ENTER $304 for a 768-byte buffer, and the four bytes below
  BP are not two scalars but one far POINTER: 11e3:0264 is `P := @Buf`, stored
  as LEA AX / MOV DX,SS / MOV [BP-4],AX / MOV [BP-2],DX. The loop then does
  LES DI,P once and walks ES:[BX+DI] with BX counting DOWN from 768, three
  components unrolled per pass and no frame slot for an index at all -- which
  is why there is none in the frame. A Pascal `for` loop cannot produce that
  shape, and the method's rule is that hand assembler is transcribed rather
  than re-expressed, so it is transcribed below.

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
  P   : Pointer;                  { [BP-$004], and it is only ever read by the
                                    asm block below -- the buffer's address is
                                    taken once instead of per component }
  Buf : array[0..767] of Byte;    { [BP-$304] }
begin
  P := @Buf;                               { 11e3:0264 }
  GetPalette768(@Buf);                     { 11e3:0270 }
  asm
        LES     DI, P           { 11e3:027A  ES:DI is the buffer, once        }
        MOV     BX, 300h        { 11e3:027D  768 -- ONE PAST the last byte    }
    @@Three:
        MOV     AL, ES:[BX+DI]  { 11e3:0280  the first of three components    }
        OR      AL, AL          { 11e3:0283                                   }
        JE      @@Second        { 11e3:0285  already black: leave it alone    }
        DEC     AL              { 11e3:0287  one step darker                  }
        MOV     ES:[BX+DI], AL  { 11e3:0289                                   }
    @@Second:
        DEC     BX              { 11e3:028C                                   }
        MOV     AL, ES:[BX+DI]  { 11e3:028D  the second                       }
        OR      AL, AL          { 11e3:0290                                   }
        JE      @@First         { 11e3:0292                                   }
        DEC     AL              { 11e3:0294                                   }
        MOV     ES:[BX+DI], AL  { 11e3:0296                                   }
    @@First:
        DEC     BX              { 11e3:0299                                   }
        MOV     AL, ES:[BX+DI]  { 11e3:029A  and the third                    }
        OR      AL, AL          { 11e3:029D                                   }
        JE      @@Next          { 11e3:029F                                   }
        DEC     AL              { 11e3:02A1                                   }
        MOV     ES:[BX+DI], AL  { 11e3:02A3                                   }
    @@Next:
        DEC     BX              { 11e3:02A6  the third decrement IS the test  }
        JNE     @@Three         { 11e3:02A7  BX reached 0: index 0 is skipped }
  end;
  WaitRetrace;                             { 11e3:02A9 }
  SetPalette768(@Buf);                     { 11e3:02AD }
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
  { Two whole palettes on the stack -- where the fade is going, and where it is
    now -- plus the two counters. Step is the OUTER loop: it walks the fade from
    dark to the target, and I walks the 768 bytes within each step.

    [re] THE TWO BYTES BELOW THE BUFFERS ARE I THEN Step, and 11e3's copy says which
    is which: the OUTER loop counts in [BP-$602] -- 02E2 stores zero and 02E7
    jumps to its increment -- so Step is the further of the two from BP and
    therefore the SECOND declared. }
  Target : TPalette;
  Cur    : TPalette;
  I      : Byte;
  Step   : Byte;
begin
  { A STRUCTURED ASSIGNMENT RATHER THAN Move, and it must stay one: Turbo
    Pascal copies a whole record inline, where a Move call would be a call.
    Same effect, different code.

    [re] 11e3:02BD copies the palette INLINE -- MOV BX,SS /
    MOV ES,BX / MOV BX,DS / CLD / LEA DI / LDS SI,[BP+8] / MOV CX,$300 /
    REP MOVSB / MOV DS,BX, nineteen bytes -- where a Move call is twenty-one.
    Those two bytes are why ClearScreen came out two bytes early in parts 001
    and 004 after the ordering was fixed. }
  { THE COPY IS HAND ASSEMBLER, and three Pascal forms were tried before that
    was the answer: `Move(P^, Target, SizeOf(Target))`, `Target := TPalette(P^)`
    and `Target := PPalette(P)^` all compile to the runtime helper, and so does
    a `var` parameter. Turbo Pascal uses the helper for a 768-byte structured
    assignment whatever the source looks like, so the inline REP MOVSB at
    11e3:02BD cannot come from Pascal at all. Transcribed verbatim, it is two
    bytes shorter than the call -- which is exactly what ClearScreen's offset
    was out by in parts 001 and 004. }
  asm
    MOV  BX, SS            { 11e3:02BD  the destination is on the stack       }
    MOV  ES, BX            { 11e3:02BF                                        }
    MOV  BX, DS            { 11e3:02C1  save DGROUP -- LDS is about to take it }
    CLD                    { 11e3:02C3  upwards                               }
    LEA  DI, Target        { 11e3:02C4                                        }
    LDS  SI, P             { 11e3:02C8  the caller's palette, a far pointer    }
    MOV  CX, $300          { 11e3:02CB  768 bytes                             }
    REP  MOVSB             { 11e3:02CE                                        }
    MOV  DS, BX            { 11e3:02D0  DGROUP back                           }
  end;
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

{ [re] ORDER: this sits between PaletteDim and WaitRetrace because that is
  where 1436:00d6 puts it -- PaletteDim ends at $00D6, this runs to
  $011A and WaitRetrace's fourteen bytes follow, with CopyScreen at
  $0128. Declared near the end of the unit instead, CopyScreen landed
  at $00E4 and every far call to it from another segment differed in
  four bytes.

  prologue.py reports ONE routine of 82 bytes at $00D6 and there are
  two: WaitRetrace has no standard prologue, so the scan cannot see it
  and folds it into its neighbour. The `call $011A` inside the reported
  extent is what gives it away -- a routine does not call into its own
  middle. }
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
  12f8:0033 -- back to 80-column colour text.

  [re] SIX BYTES AND NO FRAME, and it comes BEFORE BuildRowTable. Part 007's
  segment 100b is this unit reduced by the smart linker to SetMode13h,
  SetTextMode, BuildRowTable and the initialisation, in that order and in 64
  bytes: 100b:0006 is B8 03 00 / CD 10 / CB and nothing else. Written as a
  Pascal procedure wrapping an asm block it gained a frame -- PUSH BP /
  MOV BP,SP ... LEAVE -- and four bytes with it, and being declared after
  BuildRowTable it also shipped after it, which put both routines at the
  other's address.

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

{ 100b:000c -- the row table, and it is NEAR: see the note in the interface. }
procedure BuildRowTable;
var
  Y : Integer;
begin
  for Y := 0 to ScrHeight - 1 do
    YOfs[Y] := Y * ScrWidth;
end;

{ [re] The unit's own 64,000-byte staging screen: GetMem, keep the segment out
  separately because everything addresses it as a bare segment, then BLANK it.
  The FillChar is in the binary -- 11e3:0027 in part 004, 1436:0027 in part
  002 -- and was missing from this transcription until the units were
  consolidated. }
procedure ClearVirtual;
begin
  ClearScreen(VirtScrSeg, 0);
end;

{ Palette transfer. Port $3C8 selects the entry for writing ($3C7 for
  reading), then $3C9 takes R, G, B in turn and auto-increments, so the whole
  table moves in one burst. }
{ [re] The no-argument forms are a convenience over the global Palette; the
  original has only the pointer-taking 1491:01C2 and 1491:01DA. The
  WaitRetrace here is OURS -- 1491:01C2 does not wait, because the callers
  that care (both fades below) wait for themselves. }
{ SetPalette and GetPalette took no arguments and wrapped the 768 versions
  around the unit's own Palette global. Both are gone with it: there is nothing
  for them to wrap, and the only caller now passes its own buffer. }


{ --------------------------------------------------------------------------
  1491:0330 -- PaletteFadeOut(Pause). Compiled Pascal (ENTER $302).

  Reads the live DAC back, then 64 rounds of show-then-darken with
  Delay(Pause) between them. Note the order: it SHOWS the buffer and then
  dims it, so the first frame is the palette exactly as it was and the last
  is 63 steps down -- not quite black if anything started above 63, which
  nothing does.

  [re] Called once in the whole demo, from Demo_Scene2 at 1082:05BB with Pause=10.
  -------------------------------------------------------------------------- }

begin
  { 1436:017f -- the unit's initialization, and it does ONE thing. }
  BuildRowTable;
end.

{ ===========================================================================
  NOTE ON THE ROW TABLE

  [re] PutPixel reads YOfs from DS:$E772 for the mode 13h path (y*320). Scene 1
  builds a *different* table for its Mode-X screen -- 800 entries of y*160 at
  DS:$9F1E-ish -- because the logical line there is 160 bytes per plane, not
  320. The two coexist; do not conflate them.
  =========================================================================== }

