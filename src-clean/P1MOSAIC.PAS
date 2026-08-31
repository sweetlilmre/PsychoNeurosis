{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 3, the mosaic pixelate

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit P1MOSAIC;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

{ 286 instructions are permitted. }
{$G+}
{ 80x87 code on: the loader builds its ramp in floating point. }
{$N+}

interface

procedure Scene3;

implementation

uses VGA, Crt, DemoVT;

{ Where each asset sits inside NEUROSIS.DAT. }
{$I gen/DATOFS.INC}


{ ===========================================================================
  Scene 3 -- mosaic pixelate
  =========================================================================== }

const
  MosaicLevels = 5;

{ --------------------------------------------------------------------------
  Mosaic_Run

  Progressive pixelate, in and out. For each level the block size doubles and
  the shift grows by 2, so `sum shr Shift` is exactly the block average and
  there is no division anywhere:

      4x4    16 px   shr 4
      8x8    64 px   shr 6
     16x16  256 px   shr 8
     32x32 1024 px   shr 10
     64x64 4096 px   shr 12

  ASSETS  NEUROSIS.DAT $02AEE0, 64,000 bytes:
            assets/part001/INTROSCR.PNG
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  THIS UNIT'S ONLY GLOBAL, and it was a local in Load. }
var
  F : file;




{ --------------------------------------------------------------------------
  Mosaic_Load

  This was missing, which is why the scene ran to completion and drew nothing:
  it was pixelating an empty screen through a black palette.

      Seek $02AEE0, read 64,000 bytes into the VIRTUAL screen
      for I := 1 to 255 do SetRGB(I, Round(I*K), Round(I*K), Round(I*K))

  All three channels take the SAME value, so it is a neutral GREY ramp, and the
  constant is chosen so that entry 255 lands on 63 -- the top of the DAC
  exactly. }
procedure Load;
var
  I : Integer;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DAT_P1_INTROSCR);               { was $02AEE0 }
  BlockRead(F, VirtScr^, 64000);
  Close(F);

  for I := 1 to 255 do
    SetRGB(I, Round(I * 0.247), Round(I * 0.247), Round(I * 0.247));
end;

procedure MosaicRun;
var
  { ENTER $18 IS TWENTY-FOUR BYTES AND EVERY ONE OF THEM IS NOW ACCOUNTED FOR,
    which took three separate readings of the same routine. }
  CntX, CntY        : Word;
  Dir               : Integer;
  CurSize           : Word;             { and it is the init loop's I }
  Level             : Integer;
  LevIdx            : Byte;
  ColsB             : Byte;
  CurShift          : Byte;             { and it is the init loop's Sh }
  Spare             : Byte;             { never read }
  Lev               : array[1..MosaicLevels] of record
                        Size, Shift : Byte;
                      end;
begin
  CurSize := 4;  CurShift := 4;
  for LevIdx := 1 to MosaicLevels do
  begin
    Lev[LevIdx].Size  := CurSize;
    Lev[LevIdx].Shift := CurShift;
    CurShift := CurShift + 2;
    CurSize  := CurSize shl 1;
  end;

  Dir   := -1;
  Level := MosaicLevels;
  ClearScreen($A000, 0);

  repeat
    if Level = 0 then
      CopyScreen(VirtScrSeg, $A000)     { level 0 = the unpixelated image }
    else
    begin
      CurSize  := Lev[Level].Size;
      CurShift := Lev[Level].Shift;

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

      asm
        PUSH ES
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
        MOV  LevIdx, AL        { block rows down -- LevIdx's slot, reused    }
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
        DEC  LevIdx
        JNZ  @@Row
        POP  DS
        POP  ES
      end;
    end;

    Delay(20);
    Level := Level + Dir;
    if Level = -1 then
    begin
      Dir := -Dir;                      { turn around at the coarsest level }
      Level := Level + Dir;
      Delay(5000);                      { hold on the clear image }
    end;
  until Level = MosaicLevels + 1;
end;


{ Demo_Scene3 -- clear both screens, load, run,
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

begin
end.
