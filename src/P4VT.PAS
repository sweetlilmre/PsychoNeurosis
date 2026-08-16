{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.004, the music unit.

  Segment 11d9 in NEUROSIS_004.exe, transcribed in full -- all six routines,
  nothing inferred. Every one of them is hand assembler.

  This is the client side of JCAB's resident DemoVT / VTracker, the same one
  P2VT and DemoVT talk to. Part 004 links a REDUCED build of it: only detect,
  start, stop and the two volume accessors. Poll, position, cue and the
  pattern sync are all absent, and because they are absent the surviving
  routines SHIFT UP the segment:

      part 001 / 002 / 003        part 004
      0000  detect                0000  detect
      0040  poll     (function 2) 0040  start    (function 0)
      004E  start    (function 0) 004E  stop     (function 1)
      005C  stop     (function 1) 005C  SetVolume
      ...                         0078  GetVolume

  So the addresses do NOT line up with the other parts and reading across
  from them would get start and stop wrong. The FUNCTION NUMBERS still agree:
  11d9:0047 pushes 0 for start and 11d9:0055 pushes 1 for stop, which is what
  P2VT established.

  The control block and its fields are the same as everywhere: a far pointer
  at DS:$010E/$0110, the tracker's entry point at DS:$0112/$0114, and the
  volume byte at block + [DS:$0120].
  =========================================================================== }

{$G+}   { 286 instructions: the dispatch calls at 11d9:0047 and 0055 are
          PUSH imm8. }

unit P4VT;

interface

procedure MusicDetect;                    far;   { 11d9:0000 }
procedure MusicStart;                     far;   { 11d9:0040  function 0 }
procedure MusicStop;                      far;   { 11d9:004E  function 1 }
procedure SetVolume(V : Byte);            far;   { 11d9:005C }
function  GetVolume : Byte;               far;   { 11d9:0078 }

type
  { The segment half is Sgmt, not Seg: SEG is an operator in TP7's inline
    assembler, so `Block.Seg` inside an asm block is a syntax error. }
  TFarPtr = record Ofs, Sgmt : Word end;

var
  { DS:$010E/$0110 the control block, DS:$0112/$0114 the entry point. }
  Block : TFarPtr;
  Entry : TFarPtr;

implementation

const
  { DS:$0120 -- initialised data, and SetVolume reads it FROM MEMORY at
    11d9:006A (`ADD SI, [$0120]`), so it has to be a typed constant. A plain
    const would fold into the instruction as an immediate. }
  VolField : Word = $0206;

{ --------------------------------------------------------------------------
  11d9:0000 -- probe for the resident tracker and cache its block and entry.
  Byte for byte P2VT's 13f9:0000.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      R.AX := $5654; R.BX := $5472; R.CX := $6163; R.ES := 0; R.DI := 0;
      Intr($2F, R);
      if (R.AX = 0) and (R.BX = $3F17) and (R.CX = $1343) then
      begin
        Block := TFarPtr(Ptr(R.ES, R.DI - 4)^);
        Entry.Ofs  := MemW[Block.Sgmt : Block.Ofs + $121];
        Entry.Sgmt := MemW[Block.Sgmt : Block.Ofs + $123];
      end;

  That Pascal needs a Registers record and an Intr call the original does not
  make -- it issues the INT inline with the values already in the registers.
  -------------------------------------------------------------------------- }
procedure MusicDetect; assembler;
asm
  MOV  AX, $5654        { 'VT' -- the first third of the magic number       }
  MOV  BX, $5472        { 'Tr'                                              }
  MOV  CX, $6163        { 'ac' -- together, "VTrac"                         }
  XOR  DI, DI           { ES:DI := 0:0, where the answer comes back         }
  MOV  ES, DI           {                                                   }
  INT  $2F              { the DOS multiplex interrupt                       }
  AND  AX, AX           { a resident tracker clears AX                      }
  JNZ  @@None           {   it did not -- nothing is installed              }
  CMP  BX, $3F17        { second half of the answer                         }
  JNZ  @@None           {   wrong: not our tracker                          }
  CMP  CX, $1343        { third half                                        }
  JNZ  @@None           {   wrong                                           }
  LES  DI, ES:[DI-4]    { ES:DI := the far pointer below the handler        }
  MOV  Block.Ofs, DI    { -> DS:$010E                                       }
  MOV  Block.Sgmt, ES   { -> DS:$0110, and this is the "is it there" flag   }
  MOV  AX, ES:[DI+$121] { the tracker's entry point, offset                 }
  MOV  Entry.Ofs, AX    { -> DS:$0112                                       }
  MOV  AX, ES:[DI+$123] { and its segment                                   }
  MOV  Entry.Sgmt, AX   { -> DS:$0114                                       }
@@None:                 { <- every failed test lands here and returns       }
end;

{ --------------------------------------------------------------------------
  11d9:0040 and 11d9:004E -- the two dispatch calls part 004 keeps.

  Four instructions each: bail out if the tracker is not there, push a
  function number, call its entry point far and indirect. No stack fixup
  afterwards, so the tracker cleans up its own argument.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt <> 0 then TTrackerProc(Entry)(Func);

  which Pascal cannot express without naming a procedural type and assigning
  to it -- the test is on one variable and the call through another.
  -------------------------------------------------------------------------- }
procedure MusicStart; assembler;     { function 0 }
asm
  CMP  Block.Sgmt, 0    { is the tracker resident?                          }
  JZ   @@Out            { no -- do nothing at all                           }
  PUSH 0                { function 0: start                                 }
  CALL DWORD PTR Entry  { far indirect through DS:$0112; it pops the arg    }
@@Out:                  { <- the not-resident case returns from here        }
end;

procedure MusicStop; assembler;      { function 1 }
asm
  CMP  Block.Sgmt, 0    { resident?                                         }
  JZ   @@Out            { no                                                }
  PUSH 1                { function 1: stop                                  }
  CALL DWORD PTR Entry  { far indirect through DS:$0112                     }
@@Out:                  { <- the not-resident case returns from here        }
end;

{ --------------------------------------------------------------------------
  11d9:005C and 11d9:0078 -- the volume byte at block + VolField.

  Demo_Main reads it before the scene and puts it back afterwards, so the
  part leaves the tracker's volume exactly as it found it.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt <> 0 then
        Mem[Block.Sgmt : Block.Ofs + VolField] := V;

      if Block.Sgmt = 0 then GetVolume := 0
      else GetVolume := Mem[Block.Sgmt : Block.Ofs + VolField];
  -------------------------------------------------------------------------- }
procedure SetVolume(V : Byte); assembler;
asm
  CMP  Block.Sgmt, 0    { resident?                                         }
  JZ   @@Out            { no                                                }
  LES  SI, Block        { ES:SI := the tracker's control block              }
  ADD  SI, [VolField]   { + the volume field's offset within it             }
  MOV  AL, V            { the new volume                                    }
  MOV  ES:[SI], AL      { store it                                          }
@@Out:                  { <- the not-resident case returns from here        }
end;

function GetVolume : Byte; assembler;
asm
  XOR  AL, AL           { the not-resident answer: 0                        }
  CMP  Block.Sgmt, 0    { resident?                                         }
  JZ   @@Out            { no -- return the zero already in AL               }
  LES  SI, Block        { ES:SI := the control block                        }
  ADD  SI, [VolField]   { + the volume field                                }
  MOV  AL, ES:[SI]      { read it                                           }
@@Out:                  { <- AL is the function result                      }
end;

{ 11d9:008D -- the unit's initialisation body is empty. }
begin
end.
