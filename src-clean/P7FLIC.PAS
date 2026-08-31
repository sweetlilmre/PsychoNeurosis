{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.007, segment 100f.

  The whole of part 007 is one thing: an Autodesk Animator FLI/FLC player,
  pointed at an animation embedded in NEUROSIS.DAT at $0019117F. There is no
  virtual screen and no VGA unit -- every chunk handler writes straight to
  $A000.

  Pacing is done properly, not with Delay: the unit reprograms PIT counter 0
  to a free-running 16-bit down-counter and reads it together with the BIOS
  tick in the BIOS data area, giving a 1,193,182 Hz clock. Each frame stamps that clock
  and then spins until it has advanced by the FLC's own frame delay. The BIOS
  timer is put back to mode 3 when the animation ends.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/28-part7-notes.md for the reading. }

{ no stack checking: with it on, every procedure opens with a call to the
  runtime's overflow check, which changes the first instruction of each. }
{$S-}
{$G+}   { ENTER/LEAVE, and SHR AX,2 in the COLOR256 handler }
{$N+}   { the non-FLC speed conversion is done on the x87 }
{ I/O CHECKING OFF, and it must stay off: with it on Turbo Pascal puts a
  five-byte call to the runtime's check after every file operation. }
{$I-}

unit P7FLIC;
{ DATA ALIGNMENT OFF. With it on, Turbo Pascal pads a variable up to an even
  address -- which matters here because one routine's frame has a single byte
  in it, and padding that byte moves everything below. }
{$A-}

interface

procedure Scene1;

implementation

(* EVERY ROUTINE IN THIS UNIT IS FAR, which is what the {$F+} below is for. A
  near routine returns and is called one byte more cheaply, so getting this
  wrong shifts every address in the unit -- including the routines nothing
  outside it ever calls. *)
{$F+}

uses Crt;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

const
  DataOfs  = DAT_P7_LEMEND;   { where this part's animations start }
  BufSize  = 65000;             { pushes $FDE8            }
  MaxFlics = 100;               { compares against $64    }
  MagicFLC = $AF12;
  PITHz    = $001234DE;         { 1,193,182 -- the PIT's input clock }

type
  { The 128-byte FLI/FLC header, exactly as it sits in the file. The player
    hands a pointer to this to every chunk handler as the FIRST parameter --
    only BRUN reads it, for the width and height. }
  TFlicHdr = record
    Size     : LongInt;                   {  0 }
    Magic    : Word;                      {  4 }
    Frames   : Word;                      {  6 }
    Width    : Word;                      {  8 }
    Height   : Word;
    Depth    : Word;
    Flags    : Word;
    Speed    : LongInt;
    { The unread middle, spelled out with the FLC spec's own field names.
      Nothing here is witnessed by the binary -- the player reads none of it --
      but the offsets are the spec's and the total is the same 60 bytes. }
    Reserved1 : Word;
    Created   : LongInt;
    Creator   : LongInt;
    Updated   : LongInt;
    Updater   : LongInt;
    AspectDx  : Word;
    AspectDy  : Word;
    Reserved2 : array[42..79] of Byte;
    OFrame1   : LongInt;
    OFrame2   : LongInt;
    Reserved3 : array[88..127] of Byte;
  end;

  TFrameHdr = record
    Size   : LongInt;                     { 0 }
    Magic  : Word;                        { 4 }
    Chunks : Word;                        { 6 }
    Reserved : array[8..15] of Byte;      { the spec's name for these 8 bytes }
  end;

  { TWENTY-TWO BYTES, OF WHICH SIX ARE READ. A FLIC chunk header ends at byte
    six, so the sixteen after it have no name in the format -- they are the
    1994 declaration's own padding, and they must be declared: without them
    every reference in the routine that holds this is sixteen bytes out. }
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
  { THESE TWO COME FIRST, and their own recorded addresses say so: $01FE and
    $0202 are the LOWEST in this block, and Turbo Pascal allocates a unit's
    variables at increasing addresses in declaration order. Declared AFTER
    Names -- which is where they were, whatever this note said -- they landed
    at $33FE and $3402, the whole 12,800 bytes of the name table further on,
    and every reference to either went with them. }
  Overhead : LongInt;
  Stamp    : LongInt;
  Names    : array[1..MaxFlics] of String[127];

  Count    : Integer;
  PlayIdx  : Integer;
  LoopCnt  : Integer;
  Spare    : Byte;                               { set once, never read }
  HSS2     : TChunkProc;
  HLC      : TChunkProc;
  HCopy    : TChunkProc;
  HBrun    : TChunkProc;
  F        : file;

{ ==========================================================================
  FLI_COPY (chunk type 16). The chunk IS the frame.

  HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Move(Data^, Mem[$A000 : 0], 64000);

  -------------------------------------------------------------------------- }
procedure FliCopy(Hdr : Pointer; var Data); far;
begin
  asm
    PUSH DS
    LDS  SI, Data          { the decompressed chunk               }
    MOV  AX, 0A000h
    MOV  ES, AX
    MOV  DI, 0
    MOV  CX, 7D00h         { 32000 words = the whole 64000        }
    REP  MOVSW
    POP  DS
  end;
end;

{ ==========================================================================
  FLI_SS2 (chunk type 7), the word-aligned delta.

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
procedure FliSS2(Hdr : Pointer; var Data); far;
begin
  asm
    PUSH DS
    LDS  SI, Data
    MOV  AX, 0A000h
    MOV  ES, AX
    MOV  DI, 0
    LODSW                  { how many lines the chunk touches     }
    MOV  CX, AX
  @@Line:
    PUSH CX                { the loop comes back HERE, so the line counter
                                          is re-pushed each time             }
    MOV  BX, DI            { remember where this line started      }
  @@Op:
    LODSW                  { the packet loop comes back HERE               }
    TEST AH, 0C0h          { top two bits set => a line skip       }
    JNZ  @@Skip
    MOV  CX, AX            { otherwise AX is the packet count      }
  @@Packet:
    LODSB                  { both inner loops come back HERE               }
    XOR  AH, AH
    ADD  DI, AX            { skip that many BYTES                  }
    LODSB                  { the signed word count                 }
    TEST AL, 80h
    JZ   @@Literal         { POSITIVE is the literal
                                          copy here -- the opposite way round
                                          from BRUN below.                    }
    PUSH CX
    NOT  AL
    INC  AL                { NEG AL, spelled out                   }
    XOR  AH, AH
    MOV  CX, AX
    LODSW                  { the word to repeat                    }
    REP  STOSW
    POP  CX
    LOOP @@Packet
    JMP  @@EndLine
  @@Literal:
    PUSH CX
    MOV  CX, AX
    REP  MOVSW
    POP  CX
    LOOP @@Packet
    JMP  @@EndLine
  @@Skip:
    PUSH DX
    NOT  AX
    INC  AX                { NEG AX -- the skip is negative        }
    MOV  BX, 140h
    MUL  BX                { lines * 320                           }
    ADD  DX, AX            { DEAD. DX is popped back on the very
                                        next instruction; the author left it
                                        in. Kept because it is what is there. }
    POP  DX
    ADD  DI, AX
    MOV  BX, DI            { the skipped-to line is the new start   }
    JMP  @@Op              { NOT to @@Line: the line
                                        counter is not spent by a skip         }
  @@EndLine:
    POP  CX
    MOV  DI, BX
    ADD  DI, 140h
    LOOP @@Line
    POP  DS
  end;
end;

{ ==========================================================================
  FLI_LC (chunk type 12), the byte-run delta.

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
procedure FliLC(Hdr : Pointer; var Data); far;
begin
  asm
    PUSH DS
    LDS  SI, Data
    MOV  AX, 0A000h
    MOV  ES, AX
    MOV  DI, 0
    LODSW                  { the first line the chunk touches      }
    MOV  BX, 140h
    MUL  BX
    ADD  DI, AX
    MOV  DX, DI            { DX holds the line start throughout    }
    LODSW                  { how many lines                        }
    MOV  CX, AX
  @@Line:
    PUSH CX                { both loops come back HERE                     }
    LODSB                  { packets on this line                  }
    XOR  AH, AH
    MOV  CX, AX
    CMP  CX, 0
    JZ   @@Blank
  @@Packet:
    XOR  AH, AH            { the packet loop comes back HERE               }
    LODSB
    ADD  DI, AX            { skip                                  }
    LODSB
    TEST AL, 80h
    JNZ  @@Run
    PUSH CX
    XOR  AH, AH
    MOV  CX, AX
    REP  MOVSB
    POP  CX
    JMP  @@Next
  @@Run:
    PUSH CX
    NEG  AL
    XOR  AH, AH
    MOV  CX, AX
    LODSB                  { the byte to repeat                    }
    REP  STOSB
    POP  CX
  @@Next:
    LOOP @@Packet
    POP  CX
    MOV  DI, DX
    ADD  DI, 140h
    MOV  DX, DI
    LOOP @@Line
    JMP  @@Done
  @@Blank:
    ADD  DI, 140h          { a line with no packets at all         }
    MOV  DX, DI
    POP  CX
    LOOP @@Line
  @@Done:
    POP  DS
  end;
end;

{ ==========================================================================
  FLI_COLOR256 (chunk type 4).

  This one is compiled Pascal in the original, not hand assembler -- every
  value lives in a frame slot. Only the BIOS call is inline.

  The chunk is a run of (skip, count, count*3 bytes) packets. The bytes are
  8-bit, the DAC takes 6, so each is shifted down two IN PLACE and the block
  is then handed to INT 10h AX=$1012 -- which is why the offset has to be
  wound back over the triples and then forward again.

  A count of zero means 256.
  -------------------------------------------------------------------------- }
{ `var Data`, NOT `Data : Pointer` -- as every other chunk handler in this
  unit takes it, and as TChunkProc declares it. An untyped var parameter hands
  the routine an address it can split once; a `Pointer` variable has to be
  reloaded for each half. }
procedure FliColor256(Hdr : Pointer; var Data); far;
var
  { DECLARED IN SLOT ORDER, WHICH IS NOT THE ORDER THEY READ IN. Locals go
    down from BP as they are declared, so the first named is the one nearest
    BP -- and that is not the one the code touches first. }
  Start   : Word;
  Sg      : Word;
  Cur     : Word;
  Base    : Integer;                { the DAC register to start at }
  Packets : Integer;
  { J FIRST, for the same reason as the block above -- declaration order is
    slot order. }
  J, I    : Integer;
  Skip    : Integer;
  Cnt     : Integer;
  { ONE DECLARED BYTE, AND THE COMPILER'S OWN TEMPORARIES ARE WHAT FIND IT.
    The first temporary sits at an ODD offset, which cannot happen unless an
    odd number of bytes was declared above it -- so there is a byte here, and
    with it the frame closes two bytes wider. }
  Spare   : Byte;                   { never read }
  { NO `Last` VARIABLE. The loop below takes its bound as an expression, and a
    `for` makes ONE hidden temporary for that whatever it is -- so naming the
    expression pays for the variable AND the temporary, and copies between
    them. }
begin
  Base  := 0;
  Sg    := Seg(Data);
  Cur   := Ofs(Data);
  Start := Cur;
  Packets := MemW[Sg : Cur];
  Inc(Cur, 2);

  for I := 1 to Packets do
  begin
    Skip := Mem[Sg : Cur];  Inc(Cur);
    Cnt  := Mem[Sg : Cur];  Inc(Cur);
    if Cnt = 0 then Cnt := 256;
    Inc(Base, Skip);

    for J := 0 to Cnt * 3 - 1 do
    begin
      Mem[Sg : Cur] := Mem[Sg : Cur] shr 2;
      Inc(Cur);
    end;

    Dec(Cur, Cnt * 3);                            { back to the top }
    asm
      MOV  AH, 10h
      MOV  AL, 12h         { set a block of DAC registers         }
      MOV  BX, Base
      MOV  CX, Cnt
      LES  DX, Data
      ADD  DX, Cur
      SUB  DX, Start
      INT  10h
    end;
    Inc(Cur, Cnt * 3);
  end;
end;

{ ==========================================================================
  FLI_COLOR (chunk type 11).

  Byte for byte the same routine as COLOR256 with the shift loop taken out:
  an FLI COLOR chunk already holds 6-bit values, so there is nothing to
  scale and nothing to wind back over.
  -------------------------------------------------------------------------- }
{ `var Data`, NOT `Data : Pointer` -- as every other chunk handler in this
  unit takes it, and as TChunkProc declares it. An untyped var parameter hands
  the routine an address it can split once; a `Pointer` variable has to be
  reloaded for each half. }
procedure FliColor(Hdr : Pointer; var Data); far;
var
  { DECLARATION ORDER IS THE OFFSETS, READ BACKWARDS. Turbo Pascal gives the
    first-declared local the address nearest BP, so the original's offsets fix
    the order exactly: -2, -4, -6, -8, -$a, -$c, -$e, -$10, -$12, -$14. That is
    TEN words and we declared eight, in an order that put Base at -2 where the
    binary has Start. }
  Start   : Word;
  Sg      : Word;
  Cur     : Word;
  Base    : Integer;
  Packets : Integer;
  Spare1  : Integer;                { never touched }
  I       : Integer;
  Skip    : Integer;
  Cnt     : Integer;
  { A BYTE, NOT A WORD, and the compiler's own loop temporary is what measures
    it: the temporary sits at an ODD offset, which cannot happen unless an odd
    number of bytes was declared above it. }
  Spare2  : Byte;                   { never touched }
begin
  Base  := 0;
  { FOUR BYTES HERE ARE NOT REACHABLE FROM PASCAL. Turbo Pascal does not keep
    a loaded pointer across statements, so taking a segment and an offset off
    one pointer costs two far loads in Pascal and one in assembler. Six
    spellings were driven through three compiler versions and every one emits
    the second load.

    That points at hand assembler, and the routing supports it: a compiler
    holding the offset in DI has no reason to move it through AX before
    storing, and the original does that for BOTH halves, symmetrically. }
  Sg    := Seg(Data);
  Cur   := Ofs(Data);
  Start := Cur;
  Packets := MemW[Sg : Cur];
  Inc(Cur, 2);

  for I := 1 to Packets do
  begin
    Skip := Mem[Sg : Cur];  Inc(Cur);
    Cnt  := Mem[Sg : Cur];  Inc(Cur);
    if Cnt = 0 then Cnt := 256;
    Inc(Base, Skip);
    asm
      MOV  AH, 10h
      MOV  AL, 12h
      MOV  BX, Base
      MOV  CX, Cnt
      LES  DX, Data
      ADD  DX, Cur
      SUB  DX, Start
      INT  10h
    end;
    Inc(Cur, Cnt * 3);
  end;
end;

{ ==========================================================================
  FLI_BRUN (chunk type 15), the whole-frame RLE.

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
procedure FliBrun(Hdr : Pointer; var Data); far;
begin
  asm
    PUSH DS
    LES  BX, Hdr           { the FIRST parameter                            }
    MOV  CX, ES:[BX+0Ah]   { Height                               }
    MOV  BX, ES:[BX+08h]   { Width                                }
    MOV  AX, 0A000h
    MOV  ES, AX
    MOV  DI, 0
    LDS  SI, Data
  @@Line:
    MOV  DX, BX            { bytes still owed on this line        }
    CMP  CX, 0
    JBE  @@Done
    LODSB                  { the packet count -- READ AND DROPPED }
  @@Packet:
    CMP  DX, 0             { both loops come back HERE                      }
    JBE  @@EndLine
    LODSB
    TEST AL, 80h
    JZ   @@Run             { NEGATIVE is the literal
                                          copy here -- the opposite way round
                                          from SS2 and LC above.             }
    NEG  AL
    XOR  AH, AH
    SUB  DX, AX
    XCHG AX, CX            { park the row counter in AX           }
    REP  MOVSB
    XCHG AX, CX            { and take it back                     }
    JMP  @@Packet
  @@Run:
    XOR  AH, AH
    SUB  DX, AX
    PUSH CX
    XCHG AX, CX
    LODSB                  { the byte to repeat                   }
    REP  STOSB
    POP  CX
    JMP  @@Packet
  @@EndLine:
    LOOP @@Line
  @@Done:
    POP  DS
  end;
end;

{ ==========================================================================
  read the high-resolution clock.

  HAND ASSEMBLER, verbatim. There is no Pascal for this: it latches PIT
  counter 0, reads the PIC's interrupt request register, and reads the BIOS
  tick word, all with interrupts off and the PIC masked, then decides whether
  a tick has fired but not yet been serviced.

  The answer is a LongInt whose high word is the BIOS tick and whose low word
  is the PIT counter, i.e. 65536 units per tick and 1,193,182 units a second.
  -------------------------------------------------------------------------- }
function ReadTimer : LongInt; far;
{ FAR, like everything else in this unit. Declared near, the caller emits a
  bare CALL instead of PUSH CS / CALL, and the two differ by the pushed CS.

  NO LOCALS AT ALL, and that is what ENTER $04 means. Turbo Pascal allocates
  four bytes of frame for a LongInt function's RESULT, so a routine with one
  LongInt local would open ENTER $08 -- which is what this did, under three
  different spellings before the frame was read properly:

    two Words + `(LongInt(Hi) shl 16) or Lo`      ENTER $08
    two Words + a `LongInt absolute` alias        ENTER $08
    one LongInt local + `ReadTimer := T`          ENTER $08

  The two slots the routine writes ARE the function result, not locals: BASM
  names it `@Result`, the assembler writes both halves directly, and the
  compiler's own epilogue loads them into the register pair. }
begin
  asm
    CLI
    MOV  DX, 20h           { the PIC's command port               }
    MOV  AL, 0Ah           { OCW3: next read gives the IRR        }
    OUT  DX, AL
    MOV  AL, 0             { latch counter 0                      }
    OUT  43h, AL
    IN   AL, DX            { the IRR -- bit 0 is the timer        }
    MOV  DI, AX
    IN   AL, 40h
    MOV  BL, AL
    IN   AL, 40h
    MOV  BH, AL
    NOT  BX                { the counter runs DOWN; invert it     }
    IN   AL, 21h           { keep the interrupt mask              }
    MOV  SI, AX
    MOV  AL, 0FFh
    OUT  21h, AL           { mask everything while we read 0040:6C}
    MOV  AX, 40h
    MOV  ES, AX
    MOV  DX, ES:[6Ch]      { the BIOS tick, low word              }
    MOV  AX, SI
    OUT  21h, AL           { put the mask back                    }
    STI
    MOV  AX, DI
    TEST AL, 1             { a timer interrupt pending...         }
    JZ   @@Store
    CMP  BX, 0FFh          { ...and the counter has just wrapped  }
    JA   @@Store
    INC  DX                { so 0040:6C is one behind. Fix it.    }
  @@Store:
    MOV  WORD PTR @Result, BX     { the low half              }
    MOV  WORD PTR @Result+2, DX   { and the high                 }
  end;
end;

{ ==========================================================================
  put counter 0 into free-running mode and measure the overhead.

  The counter is set to mode 2, binary, with a reload of 0, which is 65536 --
  the same rate the BIOS uses, so the BIOS tick keeps running at 18.2 Hz and
  ReadTimer's two halves stay in step.

  Then it times its own arithmetic a hundred times over and keeps the average.
  WaitTicks adds that back in, so the wait is measured from the same point in
  the calculation that the stamp was taken from.
  -------------------------------------------------------------------------- }
procedure Calibrate;
var
  I              : Integer;
  Acc            : LongInt;
  Junk           : LongInt;
  T0             : LongInt;
  T1             : LongInt;
  { A NAMED INTERMEDIATE, NOT SPARE SPACE. The difference T1 - T0 is stored
    here and read straight back before being added to Acc -- so the statement
    below goes THROUGH this variable rather than adding directly, and it is a
    LongInt. }
  Delta          : LongInt;
begin
  asm
    MOV  AL, 34h           { counter 0, both bytes, mode 2, binary}
    OUT  43h, AL
    JMP  @@S1              { an I/O settling delay -- JMP $+2     }
  @@S1:
    MOV  AL, 0
    OUT  40h, AL
    JMP  @@S2
  @@S2:
    MOV  AL, 0
    OUT  40h, AL           { reload 0 => a full 65536             }
  end;

  Acc := 0;
  for I := 1 to 100 do
  begin
    T0   := ReadTimer;
    Junk := T0 * 1000 div 1234;
    T1   := ReadTimer;
    { THROUGH Delta, NOT DIRECTLY -- `Inc(Acc, T1 - T0)` skips the store and
      the reload, and cannot match. }
    Delta := T1 - T0;
    Inc(Acc, Delta);
  end;
  Overhead := Acc div 100;
end;

{ counter 0 back to mode 3, reload 0: what the BIOS left it as.
  No @asm marker: the original opens PUSH BP / MOV BP,SP and Turbo Pascal
  gives a procedure with no parameters and no locals no frame at all, so the
  five instructions that matter start three bytes in and the walk cannot
  anchor on them. }
procedure RestoreTimer;
begin
  asm
    MOV  AL, 36h
    OUT  43h, AL
    JMP  @@S1
  @@S1:
    MOV  AL, 0
    OUT  40h, AL
    JMP  @@S2
  @@S2:
    MOV  AL, 0
    OUT  40h, AL
  end;
end;

{ --------------------------------------------------------------------------
  spin until MS milliseconds have passed since the frame's stamp.

  The target is absolute, not relative: Stamp is taken once per frame in Play
  and this waits until the clock reaches Stamp + the delay. Decoding time is
  therefore free until it exceeds the frame delay, and the animation runs at
  its authored speed rather than at decode speed plus the delay.
  -------------------------------------------------------------------------- }
procedure WaitTicks(MS : Word); far;
{ FAR, like everything else in this unit -- and here it shows in the
  PARAMETER: a far routine's first parameter sits two bytes further up, because
  of the pushed CS. Declared near, every reference to it is two bytes off. }
var
  Target : LongInt;
begin
  { ONE STATEMENT, NOT THREE. The whole sum is computed in registers and
    stored once; written as an assignment plus two `Inc`s, each step stores the
    target and loads it again -- the same arithmetic, three times the traffic. }
  Target := LongInt(MS) * PITHz div 1000
            + Overhead + Stamp;
  { REPEAT, NOT WHILE. A `repeat` puts the test at the bottom, with the
    conditional jumps going back and the fall-through leaving; a `while` with
    an empty body needs one jump more. }
  repeat until ReadTimer >= Target;
end;

{ ==========================================================================
  open the animation and play it once through.

  The result is 0, 1 or 2; PlayAll below reads 1 as "stop everything" and 2 as
  "stop this one". NOTHING EVER SETS EITHER -- the result is zeroed on entry
  and never touched again -- so the animation always runs to its last frame.

  THE NAME PARAMETER IS NOT USED. The routine assigns the literal
  'neurosis.dat' and seeks into it; whatever is in Names[] is copied onto the
  stack and then ignored. }
function Play(Name : String) : Integer;
var
  { DECLARATION ORDER IS FRAME ORDER, and this block is in the original's --
    first declared is nearest BP, so moving any of these moves every one below
    it. }
  Stale  : file;                    { never opened; see below }
  Hdr    : TFlicHdr;
  Fr     : TFrameHdr;
  Ch     : TChunkHdr;
  N      : Word;
  FrameNo: Word;
  { ONE BYTE THAT NOTHING READS, AND IT HAS TO BE HERE. The pointer below it
    sits on an ODD base, which no amount of padding can produce -- alignment on
    or off puts a four-byte pointer on an even one. Only a byte-sized local in
    front of it explains the address. What the byte was for is not recoverable;
    that it is there is arithmetic. }
  Unread : Byte;
  Buf    : Pointer;
  Speed  : Word;
  Key    : Char;
  Stop   : Boolean;                 { cleared, never set }
  { THERE IS NO `Chunks` VARIABLE -- the loop's bound goes straight into the
    temporary a `for` makes anyway. Declaring it as well pays for both and
    copies between them. Second site in this unit; the wiki's
    loop-limit-is-a-temporary covers the class. }
begin
  Stop := False;
  Play := 0;

  GetMem(Buf, BufSize);
  Calibrate;

  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  FrameNo := 1;
  BlockRead(F, Hdr, SizeOf(Hdr));

  { an FLC states its delay in milliseconds outright; an FLI states it in
    70ths of a second, and the constants below convert it. }
  if Hdr.Magic = MagicFLC then
    Speed := Word(Hdr.Speed)
  else
    { TRUNC, NOT ROUND, and it shows: one frame delay in a hundred lands a
      millisecond short of what rounding would give. }
    Speed := Trunc(Hdr.Speed / 70.0 * 1000.0);

  { and it has to be exactly 320 x 200, because every handler
    above writes straight into mode 13h with a hard-coded 320 stride. }
  if (Hdr.Width <> 320) or (Hdr.Height <> 200) then
  begin
    asm
      MOV  AX, 3
      INT  10h
    end;
    WriteLn;
    WriteLn('Error : Sorry, only 320x200 flics supported.');
    WriteLn;
    Halt(0);
  end;

  { A BUG IN THE ORIGINAL, reproduced. This seeks to the FLC's
    own "offset of first frame" field, but it seeks `Stale`, a file record
    that was never assigned and never opened, instead of F. Under $I- the
    RTL just sets InOutRes and returns, so the seek quietly does nothing and
    the read carries straight on from the end of the 128-byte header -- which
    for this file is where frame 1 begins anyway, so it never showed. Turn
    I/O checking on and the demo dies here. }
  if Hdr.Magic = MagicFLC then
    Seek(Stale, Hdr.OFrame1);

  repeat
    Stamp := ReadTimer;
    BlockRead(F, Fr, SizeOf(Fr));
    for N := 1 to Fr.Chunks do
    begin
      BlockRead(F, Ch, 6);                        { a literal 6, not SizeOf --
                                                    the record is twenty-two
                                                    bytes and only six are
                                                    read }

      { a COPY chunk's stated size is two short of the truth in the files this
        player was written against, and the correction is made IN PLACE, to the
        field itself. A separate local for it makes the binary copy the field
        before touching it, and costs four bytes of frame that move every local
        behind it. }
      if Ch.Kind = 16 then Inc(Ch.Size, 2);

      { INLINE, and no masking. The original subtracts six from
        the 32-bit size and pushes AX, so the truncation to a Word is the
        push itself. An `Amount` local and an `and $FFFF` produced four more
        instructions and a store, and took a slot the original does not have. }
      BlockRead(F, Buf^, Ch.Size - 6);

      case Ch.Kind of
        18 : ;                                    { PSTAMP: skip  }
         { CALLED THROUGH THE VARIABLES, and measured: naming FliSS2, FliLC,
           FliCopy and FliBrun directly here costs 6 bytes. The original's
 does read as PUSH CS / CALL $de -- a direct same-segment
           far call -- but that is a DIFFERENT ARM of this case: the six-byte
           push sequence ahead of it occurs six times in this dispatch, so an
           exact eight-byte anchor lands on whichever one the aligner prefers.
           Exactness is not uniqueness. }
         7 : HSS2(@Hdr, Buf^);
        12 : HLC(@Hdr, Buf^);
        16 : HCopy(@Hdr, Buf^);
        15 : HBrun(@Hdr, Buf^);
        { `Buf^`, like the four arms above it. Both forms reach the same bytes,
          because Buf points at the heap block -- the difference is whether the
          pointer is READ or its own address is taken. Two bytes at each of two
          sites. }
         4 : FliColor256(@Hdr, Buf^);
        11 : FliColor(@Hdr, Buf^);
      else
        Halt(5);                                  { unknown chunk }
      end;

      { drain the keyboard. Nothing acts on what comes out:
        Key is written and never read, and Stop is never set. }
      if KeyPressed then
        while KeyPressed do Key := ReadKey;
    end;

    WaitTicks(Speed);
    Inc(FrameNo);
  until (Hdr.Frames + 1 < FrameNo) or Stop;

  RestoreTimer;
  Close(F);
  FreeMem(Buf, BufSize);
end;

{ UpCase over a whole string. }
function UpCaseStr(S : String) : String; far;
{ FAR, like everything else in this unit, and the parameter's position shows
  it: a far routine's first parameter sits two bytes further up because of the
  pushed CS. }
var
  { ONE LOCAL, NOT TWO -- the second slot the routine reads is the `for`
    loop's own temporary. `for I := 1 to L` over a local L costs a two-byte
    temporary ON TOP of L, so declaring the length as well makes the frame two
    bytes wider. }
  I : Integer;
begin
  for I := 1 to Length(S) do                      { limit temp }
    S[I] := UpCase(S[I]);
  UpCaseStr := S;
end;

{ --------------------------------------------------------------------------
  reset the playlist and put one entry on it.

  'lemend.flc' IS A DEAD STRING. Play ignores its parameter and opens
  neurosis.dat by name, so this only ever fills in a slot nothing reads. It is
  the author's own working filename, left in -- the same thing part 006 does
  with its .cel names. The file is not shipped with the demo.
  -------------------------------------------------------------------------- }
procedure AddFlic;
var
  { 776 BYTES, AND IT DECOMPOSES EXACTLY. First declared is nearest BP, so the
    order below is what places each one.

    256 + 7 + 256 = 519 declared, plus the 256-byte result temporary, is 775,
    and ENTER rounds it to 776. Declared with S alone this frame came out $200.

    THE TWO NEW ONES ARE SIZED, NOT UNDERSTOOD. The seven-byte slot gets a
    length of 1 and nothing writes a character into it, and the 256-byte one is
    never touched at all. String[6] and String are what fit; what they were for
    is not readable from this routine. }
  S    : String;
  Ext  : String[6];                 { length set to 1, no data }
  Unused : String;                  { never referenced }
begin
  Count   := 0;
  PlayIdx := 1;
  Spare   := 0;
  LoopCnt := 1;

  S := UpCaseStr('lemend.flc');
  { THE LENGTH BYTE IS SET AND THE CONTENT IS NOT. `Ext := ' '` would store
    both, which is two stores; the original does one. So Ext becomes a
    one-character string of whatever the frame held. It reads as an abandoned
    line rather than a deliberate one, and it is transcribed because the store
    is there. }
  Ext[0] := #1;
  if Count < MaxFlics then Inc(Count);
  Names[Count] := S;
end;

{ --------------------------------------------------------------------------
  the playlist loop.

  Two nested loops that both fall out on the same three flags. Since Play
  always answers 0, Done and Abort stay false, Left goes 1 -> 0 on the first
  pass, and the whole thing runs the animation exactly once.
  -------------------------------------------------------------------------- }
procedure PlayAll;
var
  Abort          : Boolean;
  Outer          : Boolean;
  Done           : Boolean;
  Left           : Integer;
  Res            : Integer;
begin
  Outer := False;
  repeat
    Left  := LoopCnt;
    Abort := False;
    repeat
      Res := Play(Names[PlayIdx]);
      if Res = 2 then Left := 0;
      Done  := Res = 1;
      Abort := Res = 2;
      Dec(Left);
    until Done or Abort or (Left = 0);
  until Done or Outer or Abort or (Left = 0);
end;

{ the scene: hook the four handlers up, register, play. }
procedure Scene1;
begin
  HSS2  := FliSS2;
  HLC   := FliLC;
  HCopy := FliCopy;
  HBrun := FliBrun;
  AddFlic;
  PlayAll;
end;

{ the unit's initialisation is empty. }
begin
end.
