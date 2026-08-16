{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the music unit.

  Segment 13f9 in NEUROSIS_002_fpu.exe, transcribed in full -- all ten
  routines, nothing inferred.

  This is not a player. It is the client side of a resident tracker, found
  through the multiplex interrupt:

      INT $2F with AX = $5654, BX = $5472, CX = $6163      'VT' 'Tr' 'ac'
      resident if AX = 0, BX = $3F17, CX = $1343

  The far pointer at ES:[DI-4] is the TSR's data block; the routine entry
  point lives at block+$121 and its segment at block+$123. Everything else is
  reached by poking fields of that block:

      block + [$0CDC]   the song position, a LongInt
      block + [$0CDE]   a three-byte sync slot: a flag then two values
      block + [$0CE4]   the volume, one byte

  Every entry point checks DS:$0CD4 (the block's segment) for zero first and
  does nothing if the tracker is not resident, so all of this is harmless
  without it. The offsets at $0CDC/$0CDE/$0CE4 are initialised data, read from
  DGROUP.
  =========================================================================== }

{$G+}   { 286 instructions: the dispatch calls at 13f9:0047, 0055 and 0063
          are PUSH imm8. The original targets 386 and above. }

unit P2VT;

interface

procedure MusicDetect;                    far;   { 13f9:0000 }
procedure MusicPoll;                      far;   { 13f9:0040  function 2 }
procedure MusicStart;                     far;   { 13f9:004e  function 0 }
procedure MusicStop;                      far;   { 13f9:005c  function 1 }
function  MusicPos : LongInt;             far;   { 13f9:006a }
procedure MusicCue;                       far;   { 13f9:0085 }
procedure SyncPattern(A, B : Byte);       far;   { 13f9:00ca }
procedure SetVolume(V : Byte);            far;   { 13f9:00f2 }
function  GetVolume : Byte;               far;   { 13f9:010e }

type
  { A far pointer with the two halves named, so the assembler below can test
    the segment on its own the way the original does at 13f9:0045. The
    segment half is Sgmt, not Seg: SEG is an operator in TP7's inline
    assembler, so `Block.Seg` inside an asm block is a syntax error. }
  TFarPtr = record Ofs, Sgmt : Word end;

var
  { DS:$0CD2/$0CD4 the block, DS:$0CD6/$0CD8 the entry point. Zero when the
    tracker is not resident, which is what every routine below tests. }
  Block : TFarPtr;
  Entry : TFarPtr;

implementation

{ --------------------------------------------------------------------------
  EVERY ROUTINE IN THIS UNIT IS HAND ASSEMBLER IN THE BINARY, and is
  transcribed verbatim here. None of them has a stack frame worth the name,
  they address the tracker's block through ES:SI, and MusicPos and GetVolume
  return their results in registers. An earlier pass had all nine as Pascal.

  The three field offsets below are INITIALISED DATA in the original, not
  immediates: 13f9:0079 is `ADD SI, [$0CDC]`, a memory read. They are typed
  constants here for that reason -- a plain const would fold into the
  instruction and the transcription would no longer match.
  -------------------------------------------------------------------------- }

const
  CuePosition = $19;      { 13f9:00af -- MusicCue polls until the position
                            reaches 25, then zeroes it }

const
  { ($0CE0 = $0204 and $0CE2 = $0205 hold the second and third sync bytes as
    separate constants; the code reaches them with INC SI instead, so they are
    not needed here.) }
  PosField  : Word = $0125;      { DS:$0CDC -- the song position, a LongInt }
  SyncField : Word = $0203;      { DS:$0CDE -- flag, then two values }
  VolField  : Word = $0206;      { DS:$0CE4 -- the volume byte }

var
  { DS:$A694 -- MusicCue's comparand. A global, not a local: the routine has
    no frame to put one in. }
  CueTarget : Word;

{ --------------------------------------------------------------------------
  13f9:0000 -- probe for the resident tracker and cache its block and entry.

  The handshake is INT $2F with a three-register magic number; the tracker
  answers by clearing AX and returning two more magic numbers, and leaves a
  far pointer to its data block at ES:[DI-4]. The routine entry point lives
  at block+$121 and its segment at block+$123.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      R.AX := $5654; R.BX := $5472; R.CX := $6163; R.ES := 0; R.DI := 0;
      Intr($2F, R);
      if (R.AX = 0) and (R.BX = $3F17) and (R.CX = $1343) then
      begin
        Block := TFarPtr(Ptr(R.ES, R.DI - 4)^);
        Entry.Ofs := MemW[Block.Sgmt : Block.Ofs + $121];
        Entry.Sgmt := MemW[Block.Sgmt : Block.Ofs + $123];
      end;

  That Pascal needs a Registers record and an Intr call the original does not
  make -- it issues the INT inline with the values already in the registers.
  -------------------------------------------------------------------------- }
procedure MusicDetect; assembler;
asm
  MOV  AX, $5654          { 'VT' -- the first third of the magic number    }
  MOV  BX, $5472          { 'Tr'                                           }
  MOV  CX, $6163          { 'ac' -- together, "VTrac"                      }
  XOR  DI, DI             { ES:DI := 0:0, where the answer comes back      }
  MOV  ES, DI             {                                                }
  INT  $2F                { the DOS multiplex interrupt                    }
  AND  AX, AX             { a resident tracker clears AX                   }
  JNZ  @@None             { it did not -- nothing is installed             }
  CMP  BX, $3F17          { second half of the answer                      }
  JNZ  @@None             { wrong: not our tracker                         }
  CMP  CX, $1343          { third half                                     }
  JNZ  @@None             { wrong                                          }
  LES  DI, ES:[DI-4]      { ES:DI := the far pointer left below the handler }
  MOV  Block.Ofs, DI      { -> DS:$0CD2                                    }
  MOV  Block.Sgmt, ES     { -> DS:$0CD4, and this is the "is it there" flag }
  MOV  AX, ES:[DI+$121]   { the tracker's entry point, offset              }
  MOV  Entry.Ofs, AX      { -> DS:$0CD6                                    }
  MOV  AX, ES:[DI+$123]   { and its segment                                }
  MOV  Entry.Sgmt, AX     { -> DS:$0CD8                                    }
@@None:                { <- every failed test lands here and returns        }
end;

{ --------------------------------------------------------------------------
  13f9:0040, 13f9:004e and 13f9:005c -- the three dispatch calls.

  Each is four instructions: bail out if the tracker is not there, push a
  function number, and call the tracker's entry point far and indirect. There
  is no stack fixup afterwards, so the tracker cleans up its own argument.

  THIS SETTLES THE DISAGREEMENT with part 001's DemoVT, which names function
  0 "MusicPoll" and declares FuncStop = 3. The binary is unambiguous here:
  13f9:0040 pushes 2, 13f9:004e pushes 0, 13f9:005c pushes 1. Poll is 2,
  start is 0, stop is 1.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt <> 0 then TTrackerProc(Entry)(Func);

  which is close, but Pascal cannot express "test one variable and call
  through another" without naming a procedural type and assigning to it.
  -------------------------------------------------------------------------- }
procedure MusicPoll; assembler;      { function 2 }
asm
  CMP  Block.Sgmt, 0      { is the tracker resident?                       }
  JZ   @@Out              { no -- do nothing at all                        }
  PUSH 2                  { function 2: poll                               }
  CALL DWORD PTR Entry    { far indirect through DS:$0CD6; it pops the arg }
@@Out:                  { <- the not-resident case returns from here    }
end;

procedure MusicStart; assembler;     { function 0 }
asm
  CMP  Block.Sgmt, 0      { resident?                                      }
  JZ   @@Out              { no                                             }
  PUSH 0                  { function 0: start                              }
  CALL DWORD PTR Entry    { far indirect through DS:$0CD6                  }
@@Out:                  { <- the not-resident case returns from here    }
end;

procedure MusicStop; assembler;      { function 1 }
asm
  CMP  Block.Sgmt, 0      { resident?                                      }
  JZ   @@Out              { no                                             }
  PUSH 1                  { function 1: stop                               }
  CALL DWORD PTR Entry    { far indirect through DS:$0CD6                  }
@@Out:                  { <- the not-resident case returns from here    }
end;

{ --------------------------------------------------------------------------
  13f9:006a -- read the song position, a LongInt at block + PosField.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt = 0 then MusicPos := 0
      else MusicPos := MemL[Block.Sgmt : Block.Ofs + PosField];

  The result is built directly in DX:AX, which is where Turbo Pascal wants a
  LongInt function result anyway -- so the two really are the same here.
  -------------------------------------------------------------------------- }
function MusicPos : LongInt; assembler;
asm
  XOR  AX, AX             { the not-resident answer: 0, low word           }
  XOR  DX, DX             { and high word                                  }
  CMP  Block.Sgmt, 0      { resident?                                      }
  JZ   @@Out              { no -- return the zero already in DX:AX         }
  LES  SI, Block          { ES:SI := the tracker's data block              }
  ADD  SI, [PosField]     { + the position field's offset within it        }
  MOV  AX, ES:[SI]        { low word of the LongInt                        }
  MOV  DX, ES:[SI+2]      { high word                                      }
@@Out:                     { <- DX:AX is the function result                }
end;

{ --------------------------------------------------------------------------
  13f9:0085 -- cue the module to a known place.

      zero the position
      repeat  MusicPoll  until  MusicPos - $19 = CueTarget
      zero the position again

  So it spins the tracker forward until it reports position 25, then resets
  the counter -- which is how the scene's timing gets pinned to the music.

  Two oddities, both reproduced: the MusicPos at 13f9:008c has its result
  thrown away, and the loop compares only the LOW word of the position
  against DS:$A694, which was set to zero just above and never changes.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt = 0 then Exit;
      MusicPos;                                    -- result discarded
      MemL[Block.Sgmt : Block.Ofs + PosField] := 0;
      CueTarget := 0;
      repeat MusicPoll until Word(MusicPos) - CuePosition = CueTarget;
      MemL[Block.Sgmt : Block.Ofs + PosField] := 0;
  -------------------------------------------------------------------------- }
procedure MusicCue; assembler;
asm
  CMP  Block.Sgmt, 0      { resident?                                      }
  JZ   @@Out              { no -- nothing to cue                           }
  CALL MusicPos           { 13f9:008c -- called, answer thrown away        }
  XOR  AX, AX             { zero, to clear the position with               }
  LES  SI, Block          { ES:SI := the data block                        }
  ADD  SI, [PosField]     { + the position field                           }
  MOV  ES:[SI], AX        { clear the low word                             }
  MOV  ES:[SI+2], AX      { and the high word                              }
  MOV  [CueTarget], AX    { DS:$A694 := 0, the value we spin toward        }
@@Spin:                 { <- poll until the tracker reaches position 25  }
  CALL MusicPoll          { let the tracker advance one step               }
  CALL MusicPos           { where is it now? -- DX:AX                      }
  SUB  AX, CuePosition    { $19 -- low word only, the original ignores DX  }
  CMP  AX, [CueTarget]    { reached position 25 yet?                       }
  JNZ  @@Spin             { no -- poll again                               }
  XOR  AX, AX             { yes: reset the counter to zero                 }
  LES  SI, Block          { ES:SI := the data block again                  }
  ADD  SI, [PosField]     { + the position field                           }
  MOV  ES:[SI], AX        { clear the low word                             }
  MOV  ES:[SI+2], AX      { and the high word                              }
@@Out:                  { <- the not-resident case returns from here    }
end;

{ --------------------------------------------------------------------------
  13f9:00ca -- write the three-byte sync slot at block + SyncField:

      [0] := 1          the "there is a request" flag
      [1] := A          BP+8, the FIRST declared parameter
      [2] := B          BP+6

  Scene1_Run calls it as (5, 1).

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt = 0 then Exit;
      Mem[Block.Sgmt : Block.Ofs + SyncField]     := 1;
      Mem[Block.Sgmt : Block.Ofs + SyncField + 1] := A;
      Mem[Block.Sgmt : Block.Ofs + SyncField + 2] := B;
  -------------------------------------------------------------------------- }
procedure SyncPattern(A, B : Byte); assembler;
asm
  CMP  Block.Sgmt, 0      { resident?                                      }
  JZ   @@Out              { no                                             }
  LES  SI, Block          { ES:SI := the data block                        }
  ADD  SI, [SyncField]    { + the sync slot's offset                       }
  MOV  BYTE PTR ES:[SI], 1 { flag it: there is a request waiting            }
  MOV  AH, A              { the first parameter                            }
  INC  SI                 { step to the second byte of the slot            }
  MOV  ES:[SI], AH        { store it                                       }
  MOV  AL, B              { the second parameter                           }
  INC  SI                 { step to the third byte                         }
  MOV  ES:[SI], AL        { store it                                       }
@@Out:                  { <- the not-resident case returns from here    }
end;

{ --------------------------------------------------------------------------
  13f9:00f2 and 13f9:010e -- the volume byte at block + VolField.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt <> 0 then
        Mem[Block.Sgmt : Block.Ofs + VolField] := V;

      if Block.Sgmt = 0 then GetVolume := 0
      else GetVolume := Mem[Block.Sgmt : Block.Ofs + VolField];
  -------------------------------------------------------------------------- }
procedure SetVolume(V : Byte); assembler;
asm
  CMP  Block.Sgmt, 0      { resident?                                      }
  JZ   @@Out              { no                                             }
  LES  SI, Block          { ES:SI := the data block                        }
  ADD  SI, [VolField]     { + the volume field's offset                    }
  MOV  AL, V              { the new volume                                 }
  MOV  ES:[SI], AL        { store it                                       }
@@Out:                  { <- the not-resident case returns from here    }
end;

function GetVolume : Byte; assembler;
asm
  XOR  AL, AL             { the not-resident answer: 0                     }
  CMP  Block.Sgmt, 0      { resident?                                      }
  JZ   @@Out              { no -- return the zero already in AL            }
  LES  SI, Block          { ES:SI := the data block                        }
  ADD  SI, [VolField]     { + the volume field                             }
  MOV  AL, ES:[SI]        { read it                                        }
@@Out:                     { <- AL is the function result                   }
end;

{ 13f9:0123 -- the unit's initialisation body is empty. }
begin
end.
