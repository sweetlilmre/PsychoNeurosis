{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.007, segment 100f.

  The whole of part 007 is one thing: an Autodesk Animator FLI/FLC player,
  pointed at an animation embedded in NEUROSIS.DAT at $0019117F. There is no
  virtual screen and no VGA unit -- every chunk handler writes straight to
  $A000.

  Pacing is done properly, not with Delay: the unit reprograms PIT counter 0
  to a free-running 16-bit down-counter and reads it together with the BIOS
  tick at 0040:006C, giving a 1,193,182 Hz clock. Each frame stamps that clock
  and then spins until it has advanced by the FLC's own frame delay. The BIOS
  timer is put back to mode 3 when the animation ends.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/28-part7-notes.md for the reading.

  ADDRESS MAP
    FliCopy       100f:0000     FliSS2        100f:0019
    FliLC         100f:007b     FliColor256   100f:00de
    FliColor      100f:01dc     FliBrun       100f:0284
    ReadTimer     100f:02cf     Calibrate     100f:031d
    RestoreTimer  100f:03b4     WaitTicks     100f:03c9
    Play          100f:0453     UpCaseStr     100f:06f7
    AddFlic       100f:0771     PlayAll       100f:07d4
    Scene1        100f:084c     (unit init)   100f:088d

  DGROUP
    DS:$01fe  the measured timing overhead   DS:$0202  this frame's clock stamp
    DS:$0206  Names[1..100], 128 bytes each  (the compiler's base is $0186)
    DS:$3406  how many are registered        DS:$3408  which one to play
    DS:$340a  how many times                 DS:$340c  a flag, written once
    DS:$340d  SS2   DS:$3411  LC   DS:$3415  COPY   DS:$3419  BRUN
    DS:$341d  the file
  =========================================================================== }

{$S-}   { no stack checking -- 100f:0453 opens straight into ENTER $238,0 }
{$G+}   { ENTER/LEAVE, and SHR AX,2 in the COLOR256 handler }
{$N+}   { the non-FLC speed conversion is done on the x87 }
{$I-}   { THE ORIGINAL HAS NO I/O CHECKS. Not a convenience: 100f:054d seeks
          a file that was never opened (see Play), and only $I- makes that
          survivable. Turning checks back on stops the demo dead. }

unit P7S1;
{$A-}   { DATA ALIGNMENT OFF, and it only bites once the byte at [BP-$22D]
          exists. Play's Buf is at an ODD [BP-$231] in the original; under the
          $A+ default that byte is padded to a word and Buf lands at $232,
          while packing puts it exactly where the original has it.

          This directive was tried on this unit BEFORE the byte was declared,
          measured zero and was reverted -- correctly, on the evidence then.
          A refutation is only as good as what else was wrong at the time. }

interface

procedure Scene1;

implementation

{ EVERY ROUTINE IN THIS UNIT IS FAR, and the calls say so as clearly as the
  returns. 100f:084b is CB -- RETF at the end of PlayAll, which nothing outside
  this unit calls -- and 100f:0883 and 0887 are 0E E8, PUSH CS then a NEAR CALL,
  which is Turbo Pascal's four-byte far call to a routine in the SAME segment.
  With only Scene1 in the interface the other two compiled near: C3 for the
  return and a plain E8 for each call, one byte lighter at every site and at the
  wrong address for all of them. }
{$F+}

uses Crt;

const
  DataOfs  = $0019117F;         { 100f:04ac pushes $0019 then $117F }
  BufSize  = 65000;             { 100f:0478 pushes $FDE8            }
  MaxFlics = 100;               { 100f:07ad compares against $64    }
  MagicFLC = $AF12;             { 100f:04d3                         }
  PITHz    = $001234DE;         { 1,193,182 -- 100f:03d2/03d5       }

type
  { The 128-byte FLI/FLC header, exactly as it sits in the file. The player
    hands a pointer to this to every chunk handler as the FIRST parameter --
    only BRUN reads it, for the width and height. }
  TFlicHdr = record
    Size     : LongInt;                   {  0 }
    Magic    : Word;                      {  4 }
    Frames   : Word;                      {  6 }
    Width    : Word;                      {  8 }
    Height   : Word;                      { 10 }
    Depth    : Word;                      { 12 }
    Flags    : Word;                      { 14 }
    Speed    : LongInt;                   { 16 }
    Reserved : array[20..79] of Byte;
    OFrame1  : LongInt;                   { 80 }
    Rest     : array[84..127] of Byte;
  end;

  TFrameHdr = record
    Size   : LongInt;                     { 0 }
    Magic  : Word;                        { 4 }
    Chunks : Word;                        { 6 }
    Pad    : array[8..15] of Byte;
  end;

  { TWENTY-TWO BYTES, of which six are read. Play's own recorded offsets are
    what say so: Fr at [BP-$212] and Ch at [BP-$228], and locals go downward in
    declaration order, so Ch spans $228 to $213. Declared as six bytes it
    compiled to [BP-$218] and every reference in the routine was sixteen out.
    The pad is never touched, exactly as TFrameHdr's is not. }
  TChunkHdr = record
    Size : LongInt;                       { 0 }
    Kind : Word;                          { 4 }
    Pad  : array[6..21] of Byte;
  end;

  { THE SECOND PARAMETER IS AN UNTYPED VAR, not a Pointer. The original
    passes the buffer with LES/PUSH ES/PUSH DI -- six bytes -- where a
    Pointer value parameter compiles to two word pushes and eight. Four
    handler calls at eight bytes instead of six put every jump in the
    dispatch out by two and cost the whole 180-byte span. The asm bodies
    are unaffected: `LDS SI, Data` reads the same four bytes of frame. }
  TChunkProc = procedure(Hdr : Pointer; var Data);

var
  Names    : array[1..MaxFlics] of String[127];  { DS:$0206 }
  { THESE TWO COME FIRST, and their own recorded addresses say so: $01FE and
    $0202 are the LOWEST in this block, and Turbo Pascal allocates a unit's
    variables at increasing addresses in declaration order. Declared last they
    landed after the 128-byte file record instead. }
  Overhead : LongInt;                            { DS:$01fe }
  Stamp    : LongInt;                            { DS:$0202 }

  Count    : Integer;                            { DS:$3406 }
  PlayIdx  : Integer;                            { DS:$3408 }
  LoopCnt  : Integer;                            { DS:$340a }
  Spare    : Byte;                               { DS:$340c -- set once, never read }
  HSS2     : TChunkProc;                         { DS:$340d }
  HLC      : TChunkProc;                         { DS:$3411 }
  HCopy    : TChunkProc;                         { DS:$3415 }
  HBrun    : TChunkProc;                         { DS:$3419 }
  F        : file;                               { DS:$341d }

{ ==========================================================================
  100f:0000 -- FLI_COPY (chunk type 16). The chunk IS the frame.

  HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Move(Data^, Mem[$A000 : 0], 64000);

  -------------------------------------------------------------------------- }
{ @asm 007 100f:0000 FliCopy }
procedure FliCopy(Hdr : Pointer; var Data); far;
begin
  asm
    PUSH DS                { 100f:0003                                       }
    LDS  SI, Data          { 100f:0004  the decompressed chunk               }
    MOV  AX, 0A000h        { 100f:0007                                       }
    MOV  ES, AX            { 100f:000a                                       }
    MOV  DI, 0             { 100f:000c                                       }
    MOV  CX, 7D00h         { 100f:000f  32000 words = the whole 64000        }
    REP  MOVSW             { 100f:0012                                       }
    POP  DS                { 100f:0014                                       }
  end;
end;

{ ==========================================================================
  100f:0019 -- FLI_SS2 (chunk type 7), the word-aligned delta.

  HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Lines := NextWord;
      LineStart := 0;
      for L := Lines downto 1 do
      begin
        Op := NextWord;
        while Op and $C000 <> 0 do              -- a line skip
        begin
          DI := DI + (-Op) * 320;
          LineStart := DI;
          Op := NextWord;
        end;
        for P := Op downto 1 do
        begin
          DI := DI + NextByte;                 -- skip
          N := NextByte;                       -- signed
          if N and $80 <> 0 then
            FillWord(DI, -N, NextWord)         -- run
          else
            CopyWords(DI, N);                  -- literal
        end;
        DI := LineStart + 320;
      end;

  It cannot be written that way. The line counter and the packet counter both
  live in CX and are swapped in and out around every REP, DI is the working
  pointer throughout, and the skip test is a TEST on AH that the compiler has
  no way to express.
  -------------------------------------------------------------------------- }
{ @asm 007 100f:0019 FliSS2 }
procedure FliSS2(Hdr : Pointer; var Data); far;
begin
  asm
    PUSH DS                { 100f:001c                                       }
    LDS  SI, Data          { 100f:001d                                       }
    MOV  AX, 0A000h        { 100f:0020                                       }
    MOV  ES, AX            { 100f:0023                                       }
    MOV  DI, 0             { 100f:0025                                       }
    LODSW                  { 100f:0028  how many lines the chunk touches     }
    MOV  CX, AX            { 100f:0029                                       }
  @@Line:
    PUSH CX                { 100f:002b  <- 100f:0074 LOOPs back HERE, so the
                                          line counter is re-pushed each time }
    MOV  BX, DI            { 100f:002c  remember where this line started      }
  @@Op:
    LODSW                  { 100f:002e  <- 100f:006b comes back HERE          }
    TEST AH, 0C0h          { 100f:002f  top two bits set => a line skip       }
    JNZ  @@Skip            { 100f:0032  -> 100f:005b                          }
    MOV  CX, AX            { 100f:0034  otherwise AX is the packet count      }
  @@Packet:
    LODSB                  { 100f:0036  <- 100f:004d and 100f:0057 LOOP HERE  }
    XOR  AH, AH            { 100f:0037                                        }
    ADD  DI, AX            { 100f:0039  skip that many BYTES                  }
    LODSB                  { 100f:003b  the signed word count                 }
    TEST AL, 80h           { 100f:003c                                        }
    JZ   @@Literal         { 100f:003e  -> 100f:0051. POSITIVE is the literal
                                          copy here -- the opposite way round
                                          from BRUN below.                    }
    PUSH CX                { 100f:0040                                        }
    NOT  AL                { 100f:0041                                        }
    INC  AL                { 100f:0043  NEG AL, spelled out                   }
    XOR  AH, AH            { 100f:0045                                        }
    MOV  CX, AX            { 100f:0047                                        }
    LODSW                  { 100f:0049  the word to repeat                    }
    REP  STOSW             { 100f:004a                                        }
    POP  CX                { 100f:004c                                        }
    LOOP @@Packet          { 100f:004d                                        }
    JMP  @@EndLine         { 100f:004f  -> 100f:006d                          }
  @@Literal:
    PUSH CX                { 100f:0051                                        }
    MOV  CX, AX            { 100f:0052                                        }
    REP  MOVSW             { 100f:0054                                        }
    POP  CX                { 100f:0056                                        }
    LOOP @@Packet          { 100f:0057                                        }
    JMP  @@EndLine         { 100f:0059  -> 100f:006d                          }
  @@Skip:
    PUSH DX                { 100f:005b                                        }
    NOT  AX                { 100f:005c                                        }
    INC  AX                { 100f:005e  NEG AX -- the skip is negative        }
    MOV  BX, 140h          { 100f:005f                                        }
    MUL  BX                { 100f:0062  lines * 320                           }
    ADD  DX, AX            { 100f:0064  DEAD. DX is popped back on the very
                                        next instruction; the author left it
                                        in. Kept because it is what is there. }
    POP  DX                { 100f:0066                                        }
    ADD  DI, AX            { 100f:0067                                        }
    MOV  BX, DI            { 100f:0069  the skipped-to line is the new start   }
    JMP  @@Op              { 100f:006b  -> 100f:002e, NOT to @@Line: the line
                                        counter is not spent by a skip         }
  @@EndLine:
    POP  CX                { 100f:006d                                        }
    MOV  DI, BX            { 100f:006e                                        }
    ADD  DI, 140h          { 100f:0070                                        }
    LOOP @@Line            { 100f:0074  -> 100f:002b                          }
    POP  DS                { 100f:0076                                        }
  end;
end;

{ ==========================================================================
  100f:007b -- FLI_LC (chunk type 12), the byte-run delta.

  HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      DI := NextWord * 320;
      for L := NextWord downto 1 do
      begin
        Packets := NextByte;
        if Packets = 0 then
          Inc(LineStart, 320)
        else
        begin
          for P := Packets downto 1 do
          begin
            Inc(DI, NextByte);                 -- skip
            N := NextByte;
            if N and $80 <> 0 then
              FillByte(DI, -N, NextByte)
            else
              CopyBytes(DI, N);
          end;
          DI := LineStart + 320;
        end;
      end;

  Same reason as SS2: two counters sharing CX, and DX carrying the line start
  across the REPs.
  -------------------------------------------------------------------------- }
{ @asm 007 100f:007b FliLC }
procedure FliLC(Hdr : Pointer; var Data); far;
begin
  asm
    PUSH DS                { 100f:007e                                       }
    LDS  SI, Data          { 100f:007f                                       }
    MOV  AX, 0A000h        { 100f:0082                                       }
    MOV  ES, AX            { 100f:0085                                       }
    MOV  DI, 0             { 100f:0087                                       }
    LODSW                  { 100f:008a  the first line the chunk touches      }
    MOV  BX, 140h          { 100f:008b                                       }
    MUL  BX                { 100f:008e                                       }
    ADD  DI, AX            { 100f:0090                                       }
    MOV  DX, DI            { 100f:0092  DX holds the line start throughout    }
    LODSW                  { 100f:0094  how many lines                        }
    MOV  CX, AX            { 100f:0095                                       }
  @@Line:
    PUSH CX                { 100f:0097  <- 100f:00cc and 100f:00d7 LOOP HERE  }
    LODSB                  { 100f:0098  packets on this line                  }
    XOR  AH, AH            { 100f:0099                                       }
    MOV  CX, AX            { 100f:009b                                       }
    CMP  CX, 0             { 100f:009d                                       }
    JZ   @@Blank           { 100f:00a0  -> 100f:00d0                          }
  @@Packet:
    XOR  AH, AH            { 100f:00a2  <- 100f:00c1 LOOPs HERE               }
    LODSB                  { 100f:00a4                                       }
    ADD  DI, AX            { 100f:00a5  skip                                  }
    LODSB                  { 100f:00a7                                       }
    TEST AL, 80h           { 100f:00a8                                       }
    JNZ  @@Run             { 100f:00aa  -> 100f:00b6                          }
    PUSH CX                { 100f:00ac                                       }
    XOR  AH, AH            { 100f:00ad                                       }
    MOV  CX, AX            { 100f:00af                                       }
    REP  MOVSB             { 100f:00b1                                       }
    POP  CX                { 100f:00b3                                       }
    JMP  @@Next            { 100f:00b4  -> 100f:00c1                          }
  @@Run:
    PUSH CX                { 100f:00b6                                       }
    NEG  AL                { 100f:00b7                                       }
    XOR  AH, AH            { 100f:00b9                                       }
    MOV  CX, AX            { 100f:00bb                                       }
    LODSB                  { 100f:00bd  the byte to repeat                    }
    REP  STOSB             { 100f:00be                                       }
    POP  CX                { 100f:00c0                                       }
  @@Next:
    LOOP @@Packet          { 100f:00c1                                       }
    POP  CX                { 100f:00c3                                       }
    MOV  DI, DX            { 100f:00c4                                       }
    ADD  DI, 140h          { 100f:00c6                                       }
    MOV  DX, DI            { 100f:00ca                                       }
    LOOP @@Line            { 100f:00cc                                       }
    JMP  @@Done            { 100f:00ce  -> 100f:00d9                          }
  @@Blank:
    ADD  DI, 140h          { 100f:00d0  a line with no packets at all         }
    MOV  DX, DI            { 100f:00d4                                       }
    POP  CX                { 100f:00d6                                       }
    LOOP @@Line            { 100f:00d7                                       }
  @@Done:
    POP  DS                { 100f:00d9                                       }
  end;
end;

{ ==========================================================================
  100f:00de -- FLI_COLOR256 (chunk type 4).

  This one is compiled Pascal in the original, not hand assembler: ENTER
  $18,0 and every value in a [BP-n] slot. Only the BIOS call is inline.

  The chunk is a run of (skip, count, count*3 bytes) packets. The bytes are
  8-bit, the DAC takes 6, so each is shifted down two IN PLACE and the block
  is then handed to INT 10h AX=$1012 -- which is why the offset has to be
  wound back over the triples and then forward again.

  A count of zero means 256.
  -------------------------------------------------------------------------- }
procedure FliColor256(Hdr, Data : Pointer); far;
var
  Base    : Integer;                { [BP-$08]  the DAC register to start at }
  Start   : Word;                   { [BP-$02]                              }
  Cur     : Word;                   { [BP-$06]                              }
  Sg      : Word;                   { [BP-$04]                              }
  Packets : Integer;                { [BP-$0a] / [BP-$15]                   }
  I, J    : Integer;                { [BP-$0e] / [BP-$0c]                   }
  Skip    : Integer;                { [BP-$10]                              }
  Cnt     : Integer;                { [BP-$12]                              }
  Last    : Integer;                { [BP-$17]                              }
begin
  Base  := 0;                                     { 100f:00e2 }
  Sg    := Seg(Data^);                            { 100f:00ea }
  Cur   := Ofs(Data^);                            { 100f:00ef }
  Start := Cur;                                   { 100f:00f4 }
  Packets := MemW[Sg : Cur];                      { 100f:0102 }
  Inc(Cur, 2);                                    { 100f:0108 }

  for I := 1 to Packets do                        { 100f:0112 }
  begin
    Skip := Mem[Sg : Cur];  Inc(Cur);             { 100f:012d, 100f:0135 }
    Cnt  := Mem[Sg : Cur];  Inc(Cur);             { 100f:0140, 100f:0148 }
    if Cnt = 0 then Cnt := 256;                   { 100f:014b }
    Inc(Base, Skip);                              { 100f:0159 }

    Last := Cnt * 3 - 1;                          { 100f:015f }
    for J := 0 to Last do                         { 100f:0169 }
    begin
      Mem[Sg : Cur] := Mem[Sg : Cur] shr 2;       { 100f:0180, 100f:0192 }
      Inc(Cur);                                   { 100f:0195 }
    end;

    Dec(Cur, Cnt * 3);                            { 100f:01a9  back to the top }
    asm
      MOV  AH, 10h         { 100f:01ac                                       }
      MOV  AL, 12h         { 100f:01ae  set a block of DAC registers         }
      MOV  BX, Base        { 100f:01b0                                       }
      MOV  CX, Cnt         { 100f:01b3                                       }
      LES  DX, Data        { 100f:01b6                                       }
      ADD  DX, Cur         { 100f:01b9                                       }
      SUB  DX, Start       { 100f:01bc                                       }
      INT  10h             { 100f:01bf                                       }
    end;
    Inc(Cur, Cnt * 3);                            { 100f:01ca }
  end;
end;

{ ==========================================================================
  100f:01dc -- FLI_COLOR (chunk type 11).

  Byte for byte the same routine as COLOR256 with the shift loop taken out:
  an FLI COLOR chunk already holds 6-bit values, so there is nothing to
  scale and nothing to wind back over.
  -------------------------------------------------------------------------- }
procedure FliColor(Hdr, Data : Pointer); far;
var
  { DECLARATION ORDER IS THE OFFSETS, READ BACKWARDS. Turbo Pascal gives the
    first-declared local the address nearest BP, so the original's offsets fix
    the order exactly: -2, -4, -6, -8, -$a, -$c, -$e, -$10, -$12, -$14. That is
    TEN words and we declared eight, in an order that put Base at -2 where the
    binary has Start.

    THE TWO SPARES ARE MEASURED, NOT INVENTED. ENTER $16 is 22 bytes; the
    for-loop's limit temporary takes the last two at [BP-$15] -- 100f:020d
    copies Packets there and 100f:0213 compares against it, which is Turbo
    Pascal evaluating a for limit once into a hidden slot -- leaving exactly 20
    bytes for declared locals. Nine named ones account for 18, so two words are
    unaccounted for and their positions are pinned by the gaps at -$c and -$14.

    An earlier note here recorded Packets as "[BP-$0a] / [BP-$15]", one variable
    with two addresses. It is two objects: the value read from the buffer, and
    the loop's own copy of it. }
  Start   : Word;                   { [BP-$02] }
  Sg      : Word;                   { [BP-$04] }
  Cur     : Word;                   { [BP-$06] }
  Base    : Integer;                { [BP-$08] }
  Packets : Integer;                { [BP-$0a] }
  Spare1  : Integer;                { [BP-$0c], never touched }
  I       : Integer;                { [BP-$0e] }
  Skip    : Integer;                { [BP-$10] }
  Cnt     : Integer;                { [BP-$12] }
  Spare2  : Integer;                { [BP-$14], never touched }
begin
  Base  := 0;                                     { 100f:01e0 }
  Sg    := Seg(Data^);                            { 100f:01e8 }
  Cur   := Ofs(Data^);                            { 100f:01ed }
  Start := Cur;                                   { 100f:01f2 }
  Packets := MemW[Sg : Cur];                      { 100f:0200 }
  Inc(Cur, 2);                                    { 100f:0206 }

  for I := 1 to Packets do                        { 100f:0210 }
  begin
    Skip := Mem[Sg : Cur];  Inc(Cur);             { 100f:0228, 100f:0230 }
    Cnt  := Mem[Sg : Cur];  Inc(Cur);             { 100f:023b, 100f:0243 }
    if Cnt = 0 then Cnt := 256;                   { 100f:0246 }
    Inc(Base, Skip);                              { 100f:0254 }
    asm
      MOV  AH, 10h         { 100f:0257                                       }
      MOV  AL, 12h         { 100f:0259                                       }
      MOV  BX, Base        { 100f:025b                                       }
      MOV  CX, Cnt         { 100f:025e                                       }
      LES  DX, Data        { 100f:0261                                       }
      ADD  DX, Cur         { 100f:0264                                       }
      SUB  DX, Start       { 100f:0267                                       }
      INT  10h             { 100f:026a                                       }
    end;
    Inc(Cur, Cnt * 3);                            { 100f:0275 }
  end;
end;

{ ==========================================================================
  100f:0284 -- FLI_BRUN (chunk type 15), the whole-frame RLE.

  HAND ASSEMBLER, verbatim. This is the only handler that looks at the header
  -- it takes the width and height from it rather than assuming 320x200.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for Row := Height downto 1 do
      begin
        Left := Width;
        NextByte;                          -- the packet count, thrown away
        while Left > 0 do
        begin
          N := NextByte;
          if N and $80 <> 0 then            -- negative: literal
            begin Dec(Left, -N); CopyBytes(DI, -N) end
          else
            begin Dec(Left, N);  FillByte(DI, N, NextByte) end;
        end;
      end;

  It cannot be written that way: the row counter is in CX and gets XCHGed out
  for the duration of every REP, and the per-line packet count is read and
  discarded because the loop is driven by the width remaining instead.
  -------------------------------------------------------------------------- }
{ @asm 007 100f:0284 FliBrun }
procedure FliBrun(Hdr : Pointer; var Data); far;
begin
  asm
    PUSH DS                { 100f:0287                                       }
    LES  BX, Hdr           { 100f:0288  the FIRST parameter -- [BP+0Ah]      }
    MOV  CX, ES:[BX+0Ah]   { 100f:028b  Height                               }
    MOV  BX, ES:[BX+08h]   { 100f:028f  Width                                }
    MOV  AX, 0A000h        { 100f:0293                                       }
    MOV  ES, AX            { 100f:0296                                       }
    MOV  DI, 0             { 100f:0298                                       }
    LDS  SI, Data          { 100f:029b                                       }
  @@Line:
    MOV  DX, BX            { 100f:029e  bytes still owed on this line        }
    CMP  CX, 0             { 100f:02a0                                       }
    JBE  @@Done            { 100f:02a3  -> 100f:02ca                          }
    LODSB                  { 100f:02a5  the packet count -- READ AND DROPPED }
  @@Packet:
    CMP  DX, 0             { 100f:02a6  <- 100f:02ba and 100f:02c6 come HERE }
    JBE  @@EndLine         { 100f:02a9  -> 100f:02c8                          }
    LODSB                  { 100f:02ab                                       }
    TEST AL, 80h           { 100f:02ac                                       }
    JZ   @@Run             { 100f:02ae  -> 100f:02bc. NEGATIVE is the literal
                                          copy here -- the opposite way round
                                          from SS2 and LC above.             }
    NEG  AL                { 100f:02b0                                       }
    XOR  AH, AH            { 100f:02b2                                       }
    SUB  DX, AX            { 100f:02b4                                       }
    XCHG AX, CX            { 100f:02b6  park the row counter in AX           }
    REP  MOVSB             { 100f:02b7                                       }
    XCHG AX, CX            { 100f:02b9  and take it back                     }
    JMP  @@Packet          { 100f:02ba                                       }
  @@Run:
    XOR  AH, AH            { 100f:02bc                                       }
    SUB  DX, AX            { 100f:02be                                       }
    PUSH CX                { 100f:02c0                                       }
    XCHG AX, CX            { 100f:02c1                                       }
    LODSB                  { 100f:02c2  the byte to repeat                   }
    REP  STOSB             { 100f:02c3                                       }
    POP  CX                { 100f:02c5                                       }
    JMP  @@Packet          { 100f:02c6                                       }
  @@EndLine:
    LOOP @@Line            { 100f:02c8                                       }
  @@Done:
    POP  DS                { 100f:02ca                                       }
  end;
end;

{ ==========================================================================
  100f:02cf -- read the high-resolution clock.

  HAND ASSEMBLER, verbatim. There is no Pascal for this: it latches PIT
  counter 0, reads the PIC's interrupt request register, and reads the BIOS
  tick word, all with interrupts off and the PIC masked, then decides whether
  a tick has fired but not yet been serviced.

  The answer is a LongInt whose high word is the BIOS tick and whose low word
  is the PIT counter, i.e. 65536 units per tick and 1,193,182 units a second.
  -------------------------------------------------------------------------- }
function ReadTimer : LongInt; far;
{ FAR: 100f:031c is RETF, and its caller at 100f:03fd is PUSH CS / CALL near --
  the same-segment far call. Declared near, the caller emitted a bare CALL and
  the two differed by the pushed CS.

  NO LOCALS AT ALL, and that is what ENTER $04 means. Turbo Pascal allocates
  four bytes of frame for a LongInt function's RESULT, so a routine with one
  LongInt local would open ENTER $08 -- which is what this did, under three
  different spellings before the frame was read properly:

    two Words + `(LongInt(Hi) shl 16) or Lo`      ENTER $08
    two Words + a `LongInt absolute` alias        ENTER $08
    one LongInt local + `ReadTimer := T`          ENTER $08

  The referenced slots [BP-4] and [BP-2] ARE the result, not locals. The
  assembler writes both halves of it directly and the compiler's own epilogue
  loads them into DX:AX -- which is why 100f:0315 is MOV AX,[BP-4] /
  MOV DX,[BP-2] with no shift and no `or`. `@Result` is how BASM names it. }
begin
  asm
    CLI                    { 100f:02d3                                       }
    MOV  DX, 20h           { 100f:02d4  the PIC's command port               }
    MOV  AL, 0Ah           { 100f:02d7  OCW3: next read gives the IRR        }
    OUT  DX, AL            { 100f:02d9                                       }
    MOV  AL, 0             { 100f:02da  latch counter 0                      }
    OUT  43h, AL           { 100f:02dc                                       }
    IN   AL, DX            { 100f:02de  the IRR -- bit 0 is the timer        }
    MOV  DI, AX            { 100f:02df                                       }
    IN   AL, 40h           { 100f:02e1                                       }
    MOV  BL, AL            { 100f:02e3                                       }
    IN   AL, 40h           { 100f:02e5                                       }
    MOV  BH, AL            { 100f:02e7                                       }
    NOT  BX                { 100f:02e9  the counter runs DOWN; invert it     }
    IN   AL, 21h           { 100f:02eb  keep the interrupt mask              }
    MOV  SI, AX            { 100f:02ed                                       }
    MOV  AL, 0FFh          { 100f:02ef                                       }
    OUT  21h, AL           { 100f:02f1  mask everything while we read 0040:6C}
    MOV  AX, 40h           { 100f:02f3                                       }
    MOV  ES, AX            { 100f:02f6                                       }
    MOV  DX, ES:[6Ch]      { 100f:02f8  the BIOS tick, low word              }
    MOV  AX, SI            { 100f:02fd                                       }
    OUT  21h, AL           { 100f:02ff  put the mask back                    }
    STI                    { 100f:0301                                       }
    MOV  AX, DI            { 100f:0302                                       }
    TEST AL, 1             { 100f:0304  a timer interrupt pending...         }
    JZ   @@Store           { 100f:0306  -> 100f:030f                          }
    CMP  BX, 0FFh          { 100f:0308  ...and the counter has just wrapped  }
    JA   @@Store           { 100f:030c  -> 100f:030f                          }
    INC  DX                { 100f:030e  so 0040:6C is one behind. Fix it.    }
  @@Store:
    MOV  WORD PTR @Result, BX     { 100f:030f  the low half              }
    MOV  WORD PTR @Result+2, DX   { 100f:0312  and the high                 }
  end;
end;

{ ==========================================================================
  100f:031d -- put counter 0 into free-running mode and measure the overhead.

  The counter is set to mode 2, binary, with a reload of 0, which is 65536 --
  the same rate the BIOS uses, so 0040:006C keeps ticking at 18.2 Hz and
  ReadTimer's two halves stay in step.

  Then it times its own arithmetic a hundred times over and keeps the average.
  WaitTicks adds that back in, so the wait is measured from the same point in
  the calculation that the stamp was taken from.
  -------------------------------------------------------------------------- }
procedure Calibrate;
var
  I              : Integer;   { [BP-$2] }
  Acc            : LongInt;   { [BP-$6] }
  Junk           : LongInt;   { [BP-$A] }
  T0             : LongInt;   { [BP-$E] }
  T1             : LongInt;   { [BP-$12] }
  { FOUR BYTES DECLARED AND NEVER READ. ENTER $16 is 22 bytes and the routine
    references nine word slots from [BP-2] down to [BP-$12], which is 18 -- so
    four more are declared below T1 and nothing touches them. LongInt because
    every other local here is one; the type is a guess and the size is not. }
  Spare          : LongInt;   { [BP-$16] }
begin
  asm
    MOV  AL, 34h           { 100f:0321  counter 0, both bytes, mode 2, binary}
    OUT  43h, AL           { 100f:0323                                       }
    JMP  @@S1              { 100f:0325  an I/O settling delay -- JMP $+2     }
  @@S1:
    MOV  AL, 0             { 100f:0327                                       }
    OUT  40h, AL           { 100f:0329                                       }
    JMP  @@S2              { 100f:032b                                       }
  @@S2:
    MOV  AL, 0             { 100f:032d                                       }
    OUT  40h, AL           { 100f:032f  reload 0 => a full 65536             }
  end;

  Acc := 0;                                       { 100f:0331 }
  for I := 1 to 100 do                            { 100f:0339, 100f:0395 }
  begin
    T0   := ReadTimer;                            { 100f:0343 }
    Junk := T0 * 1000 div 1234;                   { 100f:0353, 100f:035d }
    T1   := ReadTimer;                            { 100f:036d }
    Inc(Acc, T1 - T0);                            { 100f:037d, 100f:038f }
  end;
  Overhead := Acc div 100;                        { 100f:03a1, 100f:03ab }
end;

{ 100f:03b4 -- counter 0 back to mode 3, reload 0: what the BIOS left it as.
  No @asm marker: the original opens PUSH BP / MOV BP,SP and Turbo Pascal
  gives a procedure with no parameters and no locals no frame at all, so the
  five instructions that matter start three bytes in and the walk cannot
  anchor on them. }
procedure RestoreTimer;
begin
  asm
    MOV  AL, 36h           { 100f:03b7                                       }
    OUT  43h, AL           { 100f:03b9                                       }
    JMP  @@S1              { 100f:03bb                                       }
  @@S1:
    MOV  AL, 0             { 100f:03bd                                       }
    OUT  40h, AL           { 100f:03bf                                       }
    JMP  @@S2              { 100f:03c1                                       }
  @@S2:
    MOV  AL, 0             { 100f:03c3                                       }
    OUT  40h, AL           { 100f:03c5                                       }
  end;
end;

{ --------------------------------------------------------------------------
  100f:03c9 -- spin until MS milliseconds have passed since the frame's stamp.

  The target is absolute, not relative: Stamp is taken once per frame in Play
  and this waits until the clock reaches Stamp + the delay. Decoding time is
  therefore free until it exceeds the frame delay, and the animation runs at
  its authored speed rather than at decode speed plus the delay.
  -------------------------------------------------------------------------- }
procedure WaitTicks(MS : Word); far;
{ FAR, and the parameter's offset says so: 100f:03cd reads MS from [BP+6], and
  a near routine's first parameter is at [BP+4] -- the extra two bytes are the
  pushed CS. 100f:040e confirms it with RETF 2. Declared near, every reference
  to MS in this routine was two bytes off. }
var
  Target : LongInt;                 { [BP-4] }
begin
  { ONE STATEMENT, not three. 100f:03e7 and 100f:03ef are ADD AX / ADC DX
    against Overhead and Stamp with the result still in the register pair, and
    the ONLY store is 100f:03f7's MOV [BP-4],AX / MOV [BP-2],DX. Written as an
    assignment plus two Inc's, each one stores Target and loads it again -- the
    same arithmetic and three times the traffic. }
  Target := LongInt(MS) * PITHz div 1000
            + Overhead + Stamp;                   { 100f:03cd .. 100f:03fa }
  { REPEAT, not WHILE. The original's test is at the BOTTOM with the
    conditional jumps going back and the fall-through leaving -- 100f:0404 is
    JG to the exit, 100f:0406 JL back, 100f:040b JB back, and then LEAVE. A
    `while c do ;` with an empty body compiles to test, jump-out, JMP back,
    which is one jump more. }
  repeat until ReadTimer >= Target;               { 100f:03fd .. 100f:040b }
end;

{ ==========================================================================
  100f:0453 -- open the animation and play it once through.

  The result is 0, 1 or 2; PlayAll below reads 1 as "stop everything" and 2 as
  "stop this one". Nothing in this build ever sets either -- the result slot is
  zeroed at 100f:0475 and never touched again -- so the animation always runs
  to its last frame.

  THE NAME PARAMETER IS NOT USED. 100f:0491 assigns the literal 'neurosis.dat'
  from CS:$0411 and seeks $0019117F. Whatever is in Names[] is copied onto the
  stack at 100f:045e and then ignored.
  -------------------------------------------------------------------------- }
function Play(Name : String) : Integer;
var
  { IN THE ORDER THE RECORDED OFFSETS GIVE -- first declared is nearest BP, so
    sorting them ascending recovers the original's var block. Five of these
    were in the wrong place, which put Ch at [BP-$218] where every comment
    below says [BP-$228]. }
  Stale  : file;                    { [BP-$182] -- never opened; see below }
  Hdr    : TFlicHdr;                { [BP-$202] }
  Fr     : TFrameHdr;               { [BP-$212] }
  Ch     : TChunkHdr;               { [BP-$228] }
  N      : Word;                    { [BP-$22A] }
  FrameNo: Word;                    { [BP-$22C] }
  { ONE BYTE AT [BP-$22D], AND NOTHING READS IT. The frame arithmetic requires
    it: FrameNo ends at BP-$22B and Buf spans BP-$231 to BP-$22E -- its offset
    word is the [BP-$231] the routine reads nine times and its segment word the
    [BP-$22F] it reads twice -- which leaves BP-$22D with nothing in it. A
    four-byte pointer cannot land on an ODD base by padding: $A+ aligns it to
    $230 and $A- packs it to $230. Only a byte-sized local in front of it puts
    Buf where the original has it. What that byte was for is not recoverable
    from this binary; that it is there is arithmetic. }
  Unread : Byte;                    { [BP-$22D] }
  Buf    : Pointer;                 { [BP-$231] }
  Speed  : Word;                    { [BP-$233] }
  Key    : Char;                    { [BP-$234] }
  Stop   : Boolean;                 { [BP-$235] -- cleared, never set }
  Chunks : Word;                    { [BP-$237] }
begin
  Stop := False;                                  { 100f:046e }
  Play := 0;                                      { 100f:0475 }

  GetMem(Buf, BufSize);                           { 100f:0478 }
  Calibrate;                                      { 100f:0489 }

  Assign(F, 'neurosis.dat');                      { 100f:0491 }
  Reset(F, 1);                                    { 100f:04a0 }
  Seek(F, DataOfs);                               { 100f:04ac }
  FrameNo := 1;                                   { 100f:04b6 }
  BlockRead(F, Hdr, SizeOf(Hdr));                 { 100f:04c7 }

  { 100f:04d3 -- an FLC states its delay in milliseconds outright. An FLI
    states it in 70ths of a second, and CS:$041e / CS:$0422 are the 70.0 and
    the 1000.0 that convert it. }
  if Hdr.Magic = MagicFLC then
    Speed := Word(Hdr.Speed)                      { 100f:04db }
  else
    Speed := Round(Hdr.Speed / 70.0 * 1000.0);    { 100f:04e6 }

  { 100f:04ff -- and it has to be exactly 320 x 200, because every handler
    above writes straight into mode 13h with a hard-coded 320 stride. }
  if (Hdr.Width <> 320) or (Hdr.Height <> 200) then
  begin
    asm
      MOV  AX, 3           { 100f:050f }
      INT  10h             { 100f:0512 }
    end;
    WriteLn;                                      { 100f:0519 }
    WriteLn('Error : Sorry, only 320x200 flics supported.');  { 100f:052a }
    WriteLn;                                      { 100f:0539 }
    Halt(0);                                      { 100f:0540 }
  end;

  { 100f:054d -- A BUG IN THE ORIGINAL, reproduced. This seeks to the FLC's
    own "offset of first frame" field, but it seeks `Stale`, a file record
    that was never assigned and never opened, instead of F. Under $I- the
    RTL just sets InOutRes and returns, so the seek quietly does nothing and
    the read carries straight on from the end of the 128-byte header -- which
    for this file is where frame 1 begins anyway, so it never showed. Turn
    I/O checking on and the demo dies here. }
  if Hdr.Magic = MagicFLC then
    Seek(Stale, Hdr.OFrame1);

  repeat
    Stamp := ReadTimer;                           { 100f:0561 }
    BlockRead(F, Fr, SizeOf(Fr));                 { 100f:057c }
    Chunks := Fr.Chunks;                          { 100f:0581 }

    for N := 1 to Chunks do                       { 100f:0589 }
    begin
      BlockRead(F, Ch, 6);                        { 100f:05b0 -- a literal 6,
                                                    not SizeOf: 100f:05aa
                                                    pushes 6 and the record
                                                    is twenty-two bytes }

      { 100f:05b5 -- a COPY chunk's stated size is two short of the truth in
        the files this player was written against. IN PLACE: 100f:05bc adds
        the two to [BP-$228], which is Ch.Size itself. A separate CSize local
        made the binary copy the field before touching it, and took four bytes
        of frame that moved every local behind it -- Ch is documented at
        [BP-$228] and was compiling to [BP-$218]. }
      if Ch.Kind = 16 then Inc(Ch.Size, 2);

      { 100f:05d9 -- INLINE, and no masking. The original subtracts six from
        the 32-bit size and pushes AX, so the truncation to a Word is the
        push itself. An `Amount` local and an `and $FFFF` produced four more
        instructions and a store, and took a slot the original does not have. }
      BlockRead(F, Buf^, Ch.Size - 6);            { 100f:05e4 }

      case Ch.Kind of                             { 100f:05e9 }
        18 : ;                                    { 100f:05ed  PSTAMP: skip  }
         { CALLED THROUGH THE VARIABLES, and measured: naming FliSS2, FliLC,
           FliCopy and FliBrun directly here costs 6 bytes. The original's
           100f:0662 does read as PUSH CS / CALL $de -- a direct same-segment
           far call -- but that is a DIFFERENT ARM of this case: the six-byte
           push sequence ahead of it occurs six times in this dispatch, so an
           exact eight-byte anchor lands on whichever one the aligner prefers.
           Exactness is not uniqueness. }
         7 : HSS2(@Hdr, Buf^);                     { 100f:0606 }
        12 : HLC(@Hdr, Buf^);                      { 100f:061d }
        16 : HCopy(@Hdr, Buf^);                    { 100f:0634 }
        15 : HBrun(@Hdr, Buf^);                    { 100f:064b }
         4 : FliColor256(@Hdr, Buf);              { 100f:0663 }
        11 : FliColor(@Hdr, Buf);                 { 100f:067a }
      else
        Halt(5);                                  { 100f:067f  unknown chunk }
      end;

      { 100f:0687 -- drain the keyboard. Nothing acts on what comes out:
        Key is written and never read, and Stop is never set. }
      if KeyPressed then
        while KeyPressed do Key := ReadKey;
    end;

    WaitTicks(Speed);                             { 100f:06b6 }
    Inc(FrameNo);                                 { 100f:06b9 }
  until (Hdr.Frames + 1 < FrameNo) or Stop;       { 100f:06c2, 100f:06c8 }

  RestoreTimer;                                   { 100f:06d3 }
  Close(F);                                       { 100f:06db }
  FreeMem(Buf, BufSize);                          { 100f:06eb }
end;

{ 100f:06f7 -- UpCase over a whole string. }
function UpCaseStr(S : String) : String; far;
{ FAR: 100f:0763 is RETF 4, and 100f:0712 reads the String parameter from
  [BP+6] where a near routine's first parameter is at [BP+4] -- the two extra
  bytes are the pushed CS. That is the third routine in this unit declared near
  that is far; ReadTimer and WaitTicks were the others. }
var
  { ONE local, not two, and the second slot the routine reads is the FOR
    LOOP's OWN TEMPORARY. ENTER $104 is 260: the String parameter's 256-byte
    copy at [BP-$100], I at [BP-$102], and two bytes at [BP-$104] that hold
    the limit. A probe settles which: `for I := 1 to L` over a local L costs a
    two-byte temporary ON TOP of L, so declaring both L and the loop gives 262.

    So the length is written into the loop, not into a variable -- 100f:0712
    stores it to [BP-$104] and 100f:071f and 100f:0749 compare against that
    same slot, which is the temporary and not a declared L. }
  I : Integer;                                    { [BP-$102] }
begin
  for I := 1 to Length(S) do                      { 100f:0712, limit temp }
    S[I] := UpCase(S[I]);                         { 100f:0738 }
  UpCaseStr := S;                                 { 100f:075d }
end;

{ --------------------------------------------------------------------------
  100f:0771 -- reset the playlist and put one entry on it.

  'lemend.flc' at CS:$0766 IS A DEAD STRING. Play ignores its parameter and
  opens neurosis.dat by name, so this only ever fills in a slot nothing reads.
  It is the author's own working filename, left in -- the same thing part 006
  does with its .cel names. The file is not shipped with the demo.
  -------------------------------------------------------------------------- }
procedure AddFlic;
var
  { ENTER $308 IS 776 BYTES AND IT DECOMPOSES EXACTLY. Only three slots are
    referenced -- [BP-$100], [BP-$107] and [BP-$307] -- and first-declared is
    nearest BP, so working down from S:

        [BP-$100]  S      256   the String below
        [BP-$107]  a SEVEN-byte slot, whose base is its length byte:
                          100f:07a8 is MOV BYTE PTR [BP-$107],1, which sets a
                          length of 1. Seven bytes is String[6].
        [BP-$207]  256   another String, never referenced
        [BP-$307]  256   Turbo Pascal's temporary for the UpCaseStr result --
                         100f:078b LEAs it before the call, so it is the
                         compiler's, not a declaration

    256 + 7 + 256 = 519 declared, plus the 256-byte result temporary, is 775,
    and ENTER rounds it to 776. Declared with S alone this frame came out $200.

    THE TWO NEW ONES ARE SIZED, NOT UNDERSTOOD. The seven-byte slot gets a
    length of 1 and nothing writes a character into it, and the 256-byte one is
    never touched at all. String[6] and String are what fit; what they were for
    is not readable from this routine. }
  S    : String;                    { [BP-$100] }
  Ext  : String[6];                 { [BP-$107] -- length set to 1, no data }
  Unused : String;                  { [BP-$207] -- never referenced }
begin
  Count   := 0;                                   { 100f:0777 }
  PlayIdx := 1;                                   { 100f:077a }
  Spare   := 0;                                   { 100f:0780 }
  LoopCnt := 1;                                   { 100f:0785 }

  S := UpCaseStr('lemend.flc');                   { 100f:078b .. 100f:07a3 }
  { 100f:07a8 -- MOV BYTE PTR [BP-$107],1, ONE store and nothing else. That is
    the length byte of Ext being set directly: `Ext := ' '` would store the
    length AND a character, which is two. So the source writes the length and
    leaves the content, which makes Ext a one-character string of whatever the
    frame held. It reads as an abandoned line rather than a deliberate one, and
    it is transcribed because the store is there. }
  Ext[0] := #1;                                   { 100f:07a8 }
  if Count < MaxFlics then Inc(Count);            { 100f:07ad }
  Names[Count] := S;                              { 100f:07b8 .. 100f:07cd }
end;

{ --------------------------------------------------------------------------
  100f:07d4 -- the playlist loop.

  Two nested loops that both fall out on the same three flags. Since Play
  always answers 0, Done and Abort stay false, Left goes 1 -> 0 on the first
  pass, and the whole thing runs the animation exactly once.
  -------------------------------------------------------------------------- }
procedure PlayAll;
var
  Abort          : Boolean;   { [BP-$1] }
  Outer          : Boolean;   { [BP-$2] }
  Done           : Boolean;   { [BP-$3] }
  Left           : Integer;   { [BP-$5] }
  Res            : Integer;   { [BP-$7] }
begin
  Outer := False;                                 { 100f:07d8 }
  repeat
    Left  := LoopCnt;                             { 100f:07dc }
    Abort := False;                               { 100f:07e2 }
    repeat
      Res := Play(Names[PlayIdx]);                { 100f:07f4 }
      if Res = 2 then Left := 0;                  { 100f:07fa }
      Done  := Res = 1;                           { 100f:0805 }
      Abort := Res = 2;                           { 100f:0811 }
      Dec(Left);                                  { 100f:081d }
    until Done or Abort or (Left = 0);            { 100f:0820 .. 100f:0830 }
  until Done or Outer or Abort or (Left = 0);     { 100f:0832 .. 100f:0848 }
end;

{ 100f:084c -- the scene: hook the four handlers up, register, play. }
procedure Scene1;
begin
  HSS2  := FliSS2;                                { 100f:084f }
  HLC   := FliLC;                                 { 100f:085c }
  HCopy := FliCopy;                               { 100f:0869 }
  HBrun := FliBrun;                               { 100f:0876 }
  AddFlic;                                        { 100f:0884 }
  PlayAll;                                        { 100f:0888 }
end;

{ 100f:088d -- the unit's initialisation is empty. }
begin
end.
