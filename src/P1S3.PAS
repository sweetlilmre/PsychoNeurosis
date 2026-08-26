{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 3, the mosaic pixelate

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit P1S3;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

{$G+}   { 286: Mosaic_Run 10e3:00bb opens ENTER $18. }
{$N+}   { Mosaic_Load's arithmetic is x87 -- 10e3:0075 FILD. }

interface

procedure Scene3;

implementation

uses VGA, Crt, DemoVT;

{ The block sampling is HAND ASSEMBLER in the original -- 10e3:0148..01cb,
  one inline BASM block bracketed by PUSH ES/PUSH DS .. POP DS/POP ES inside
  the otherwise compiled Mosaic_Run. The segments are loaded ONCE for the
  whole level -- ES := $A000, DS := VirtScrSeg -- and the pixel loops run
  register-only, five instructions per source pixel. An earlier version of
  this unit re-expressed it as Pascal Mem[] loops, which reload ES on every
  access; at 128,000 accesses per level that is why the scene CRAWLED next
  to the original (part of plan: pacing). It is back in verbatim below.

  The sum is read from the VIRTUAL screen and the average written straight
  to VIDEO, so the clean image is never modified and each level re-averages
  from it rather than compounding the previous one. The shift IS the block
  area, so there is no division: 4x4 shr 4 .. 64x64 shr 12. The accumulator
  is 16-bit AX, so the 64x64 level overflows on a bright image -- the
  original's behaviour, kept. }

{ ===========================================================================
  Scene 3 -- mosaic pixelate                      Demo_Scene3  10e3:0206
  =========================================================================== }

const
  MosaicLevels = 5;

{ --------------------------------------------------------------------------
  Mosaic_Run (10e3:00bb)

  Progressive pixelate, in and out. For each level the block size doubles and
  the shift grows by 2, so `sum shr Shift` is exactly the block average and
  there is no division anywhere:

      4x4    16 px   shr 4
      8x8    64 px   shr 6
     16x16  256 px   shr 8
     32x32 1024 px   shr 10
     64x64 4096 px   shr 12

  ASSETS  NEUROSIS.DAT $02AEE0, 64,000 bytes:
            assets/part001/intro_screen.png
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  THIS UNIT'S ONLY GLOBAL, and it was a local in Load.

  DS:$5A52 -- the file record. 10e3:0017 opens ENTER $02, two bytes, which is
  the counter alone and leaves no room for a 128-byte file record; and the
  addresses recorded across this part leave exactly 128 bytes unaccounted here.
  Sorted, they run $59D2 for scene 2's file record, 128 bytes on to $5A52, and
  then 128 MORE to $5AD2 where scene 4's begins. Nothing was declared in that
  second 128, this unit has no other unit-level data, and every other scene in
  the part keeps its file record as a global -- so it is this.
  -------------------------------------------------------------------------- }
var
  F : file;                             { DS:$5A52 }


{ LOAD IS DEFINED FIRST, BEFORE MosaicRun, AND THE STRING LITERAL IS THE PROOF.
  The original's segment OPENS with 0C 'neurosis.dat' at 10e3:0000 -- a code-
  segment string constant, which TP7 emits immediately ahead of the routine
  that references it -- and the first routine after it is ENTER $02 at
  10e3:0017, the two bytes of Load's frame. Defined after MosaicRun the literal
  landed at 10e3:014b instead, and 10e3:0020's MOV DI,offset carried that
  address rather than zero. The map at the top of this file already gave
  Load 0017 and Mosaic_Run 00bb; nothing had checked the order against it. }


{ --------------------------------------------------------------------------
  Mosaic_Load (10e3:0017)

  This was missing, which is why the scene ran to completion and drew nothing:
  it was pixelating an empty screen through a black palette.

      Seek $02AEE0, read 64,000 bytes into the VIRTUAL screen
      for I := 1 to 255 do SetRGB(I, Round(I*K), Round(I*K), Round(I*K))

  All three channels take the SAME value, so it is a neutral GREY ramp. K is
  the 80-bit constant at CS:$000D = 0.247, which puts I = 255 at 63 -- the top
  of the DAC exactly.
  -------------------------------------------------------------------------- }
procedure Load;
var
  { ENTER $02 at 10e3:0017 is TWO BYTES -- just the counter. The file record is
    a GLOBAL, declared with the unit's other data above, which is what every
    other scene in this part turned out to do as well. }
  I : Integer;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $02AEE0);
  { VirtScr^, NOT Mem[VirtScrSeg : 0]. 10e3:004a is LES DI,[mem] -- one
    instruction loading a stored far POINTER -- where the segment-plus-zero form
    reads only VGA's segment word and builds the pointer around it: MOV AX,[mem]
    / PUSH AX / XOR DI,DI / POP ES, three bytes more, and this unit's only
    remaining excess. The two address the same memory; only one of them is what
    the original wrote. }
  BlockRead(F, VirtScr^, 64000);
  Close(F);

  { RECOMPUTED THREE TIMES, once per channel, which is what the comment above
    already said and what the code did not do. 10e3:0075, 0088 and 009b each
    do FILD [BP-2] / FLD the constant at CS:$000D / FMULP / Round, and each
    result is pushed separately -- nine x87 sites where a single V costs three.
    Turbo Pascal does not common up the subexpression, so the source really
    does write it out. }
  for I := 1 to 255 do
    SetRGB(I, Round(I * 0.247), Round(I * 0.247), Round(I * 0.247));
end;

procedure MosaicRun;
var
  { ENTER $18 IS TWENTY-FOUR BYTES AND EVERY ONE OF THEM IS NOW ACCOUNTED FOR,
    which took three separate readings of the same routine.

    THE TWO TABLES ARE ONE ARRAY OF PAIRS. 10e3:00dd writes [BP+DI-$1A] and
    10e3:00ec writes [BP+DI-$19] with DI = Level * 2 in both -- ONE index, two
    consecutive bytes -- so it is an array of two-byte records and not two
    separate byte arrays, which would have separate bases and separate indices.

    I AND CurSize ARE THE SAME VARIABLE, at [BP-$8]. 10e3:00bf sets it to 4 and
    00f9 doubles it in the init loop; 10e3:013a loads it from the table in the
    main loop. So is Sh AND CurShift, at [BP-$D]: 00c4 sets it to 4 and 00ef
    adds two, and 0145 loads it from the table. Two variables, not four -- and
    that is where the six bytes went that made ours ENTER $1E.

    AND FOUR OF THEM ARE BYTES. The init loop's counter is a byte (10e3:00c8 is
    MOV BYTE PTR [BP-$B],1) and so are the shift and the two block counters; we
    had Integers. The `Inc(Sh, 2)` is also an ASSIGNMENT -- 00ef loads, widens,
    INCs twice and stores back, where Inc on a byte emits ADD [mem],2.

    Order, nearest BP first, and the arithmetic closes at 24:
        [BP-$2] CntX  [BP-$4] CntY  [BP-$6] Dir  [BP-$8] CurSize
        [BP-$A] Level [BP-$B] LevIdx [BP-$C] ColsB [BP-$D] CurShift
        [BP-$E] RowsB  [BP-$18] the five pairs }
  CntX, CntY        : Word;             { [BP-$2], [BP-$4] }
  Dir               : Integer;          { [BP-$6] }
  CurSize           : Word;             { [BP-$8], and it is the init loop's I }
  Level             : Integer;          { [BP-$A] }
  LevIdx            : Byte;             { [BP-$B] }
  ColsB             : Byte;             { [BP-$C] }
  CurShift          : Byte;             { [BP-$D], and it is the init loop's Sh }
  RowsB             : Byte;             { [BP-$E] }
  Lev               : array[1..MosaicLevels] of record
                        Size, Shift : Byte;
                      end;              { [BP-$18] }
begin
  CurSize := 4;  CurShift := 4;
  for LevIdx := 1 to MosaicLevels do
  begin
    Lev[LevIdx].Size  := CurSize;                { 10e3:00dd }
    Lev[LevIdx].Shift := CurShift;               { 10e3:00ec }
    CurShift := CurShift + 2;                    { 10e3:00ef }
    CurSize  := CurSize shl 1;                   { 10e3:00f9 }
  end;

  Dir   := -1;
  Level := MosaicLevels;
  ClearScreen($A000, 0);

  repeat
    if Level = 0 then
      CopyScreen(VirtScrSeg, $A000)     { level 0 = the unpixelated image }
    else
    begin
      CurSize  := Lev[Level].Size;      { 10e3:0130 }
      CurShift := Lev[Level].Shift;     { 10e3:013d }

      { EQUIVALENT PASCAL, for reference -- the assembler below is what
        runs. For each block: sum its pixels from the virtual screen,
        shift the sum down to the average, fill the same block on video.

            Ofs := 0;
            for Row := 1 to 200 div CurSize do
            begin
              for Col := 1 to 320 div CurSize do
              begin
                Sum := 0;  P := Ofs;
                for BY := 1 to CurSize do
                begin
                  for BX := 1 to CurSize do
                  begin
                    Inc(Sum, Mem[VirtScrSeg : P]);  Inc(P);
                  end;
                  Inc(P, ScrWidth - CurSize);
                end;
                Sum := Sum shr CurShift;  P := Ofs;
                for BY := 1 to CurSize do
                begin
                  for BX := 1 to CurSize do
                  begin
                    Mem[VGASeg : P] := Sum;  Inc(P);
                  end;
                  Inc(P, ScrWidth - CurSize);
                end;
                Inc(Ofs, CurSize);
              end;
              Inc(Ofs, (CurSize - 1) * ScrWidth);
            end;

        Where that Pascal is not the same thing: every Mem[] access reloads
        a segment register, where the assembler loads ES and DS once for
        the whole level and keeps the block walk entirely in registers --
        the difference between a crawl and the original's pace. }

      { @asm 001 10e3:0148 +132 MosaicBlocks }
      asm
        PUSH ES                { 10e3:0148                                  }
        PUSH DS                { DS is about to point at the virtual screen }
        MOV  AX, VGASeg        { $A000                                      }
        MOV  ES, AX            { ES := video, the destination               }
        MOV  AX, VirtScrSeg    { read while DS still points at DGROUP       }
        MOV  DS, AX            { DS := the clean image, the source          }
        XOR  DI, DI            { DI := this block's video offset            }
        XOR  SI, SI            { SI := this block's source offset           }
        MOV  CX, CurSize       { CX holds the block edge throughout         }
        MOV  AX, 200           { $C8                                        }
        DIV  CL                { AL := 200 div Size                         }
        MOV  RowsB, AL         { block rows down the screen                 }
      @@Row:
        MOV  AX, 320           { $140                                       }
        DIV  CL                { AL := 320 div Size -- redone every row     }
        MOV  ColsB, AL         { blocks across                              }
      @@Col:
        MOV  CntY, CX          { CntY counts the block's rows               }
        XOR  AX, AX            { AX := the sum -- 16-bit, overflows at 64x64}
        XOR  BX, BX            { BX walks the block, relative to SI/DI      }
      @@SumRow:
        MOV  CntX, CX          { CntX counts the row's pixels               }
        XOR  DX, DX            { DL carries one pixel, DH stays 0           }
      @@SumPix:
        MOV  DL, [BX + SI]     { read a source pixel                        }
        ADD  AX, DX            { sum it                                     }
        INC  BX
        DEC  CntX
        JNZ  @@SumPix          { across the block row                       }
        ADD  BX, 320           { down one screen row...                     }
        SUB  BX, CX            {   ...back to the block's left edge         }
        DEC  CntY
        JNZ  @@SumRow          { down the block                             }
        MOV  CL, CurShift      { the shift IS the block area                }
        SHR  AX, CL            { AL := the average                          }
        MOV  CX, CurSize       { CX was the shift for a moment -- restore   }
        MOV  CntY, CX
        XOR  BX, BX
      @@WrRow:
        MOV  CntX, CX
      @@WrPix:
        MOV  ES:[BX + DI], AL  { fill the block on video with the average   }
        INC  BX
        DEC  CntX
        JNZ  @@WrPix
        ADD  BX, 320
        SUB  BX, CX
        DEC  CntY
        JNZ  @@WrRow
        ADD  SI, CX            { next block along the row                   }
        MOV  DI, SI            { video tracks the source exactly            }
        DEC  ColsB
        JNZ  @@Col
        MOV  AX, 320           { skip the Size-1 screen rows the col walk   }
        MOV  BX, CX            {   already covered                          }
        DEC  BX
        MUL  BX                { AX := 320 * (Size - 1)                     }
        ADD  SI, AX
        MOV  DI, SI
        DEC  RowsB
        JNZ  @@Row
        POP  DS                { 10e3:01ca }
        POP  ES
      end;
    end;

    Delay(20);
    { ASSIGNMENTS, NOT Inc. 10e3:01ea is MOV AX,[Level] / ADD AX,[Dir] /
      MOV [Level],AX -- nine bytes through the accumulator -- where
      Inc(Level, Dir) emits ADD [Level],reg, which is shorter. Both steps of
      the level have the long form. }
    Level := Level + Dir;
    if Level = -1 then
    begin
      Dir := -Dir;                      { turn around at the coarsest level }
      Level := Level + Dir;             { 10e3:01ea }
      Delay(5000);                      { hold on the clear image }
    end;
  until Level = MosaicLevels + 1;
end;


{ [transcribed] Demo_Scene3 (10e3:0206) -- clear both screens, load, run,
  clear both again. }
procedure Scene3;
begin
  ClearScreen($A000, 0);
  ClearScreen(VirtScrSeg, 0);
  Load;
  MosaicRun;
  ClearScreen($A000, 0);
  ClearScreen(VirtScrSeg, 0);
end;

{ AN EMPTY INITIALISATION SECTION, AND THE ORIGINAL GIVES EVERY UNIT ONE. 10e3:023b
  is PUSH BP / MOV BP,SP / LEAVE / RETF -- five bytes, doing nothing -- and the
  main body opens with a chain of far calls that runs one per unit. The chain is
  twelve calls at 1000:0000..003b in the 1994 binary and was SEVEN in ours,
  because the five scene units ended `end.` with no `begin`, so TP7 emitted no
  section and the chain had nothing to call. Twenty-five bytes of stub and
  twenty-five of chain, and the body started twenty-five bytes early.

  Without the `begin` below this unit does not appear in that chain at all. }
begin
end.
