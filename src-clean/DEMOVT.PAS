{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the DemoVT interface unit.

  NEUROSIS.008 is JCAB's DemoVT / VTracker MOD player, a third-party TSR that
  is LZEXE-packed and out of scope for this reconstruction. This unit is NOT
  that player -- it is the thin client side that every effect part links
  against to talk to it.

  ONE UNIT, LINKED BY EVERY PART, and no two parts keep the same routines:
  Turbo Pascal's smart linker drops whatever a part never calls, so part 004
  carries five of the ten and part 001 carries a function nothing else uses.
  **The function NUMBERS are the stable thing here, not the addresses** -- they
  are what the player's dispatcher reads, and they agree in every part.

  FUNCTION 3 IS ONLY PART 001'S, and it is called once at startup -- after
  detection, before the music is started.

  WHAT IT DOES IS A RESYNC: it asks the player where the hardware has actually
  reached in the output buffer, rounds down to a multiple of four, stores that
  as the play position, and zeroes the counters measured from the previous
  anchor. It re-anchors "now" and stops nothing -- which fits a call made
  before playback, to zero the clock that later position reads are measured
  against.

  **That description does not come from the shipped documentation, which does
  not list the function numbers at all. It comes from reading the player's own
  side in the sibling DemoVT reconstruction, so it inherits that tree's
  confidence rather than the author's.** The name stays MusicFunc3, because the
  number is what the binary encodes and a descriptive name would assert more
  than is known.

  All ten routines are hand assembler in the binary and are verbatim here.

  HOW IT WORKS -- AND THIS IS A PUBLISHED INTERFACE, so the following is the
  author of the player's own account of it, from the shipped DEMOVT.DOC under
  "Software interface". It is not inference.

    Detection is an INT 2Fh handshake with an ASCII signature. The doc names
    the constants: MagicAX 'VT', MagicBX 'Tr', MagicCX 'ac' -- together
    "VTrac(ker)" -- plus MagicXorBX 'ke' and MagicXorCX 'r '.

        AX := $5654   BX := $5472   CX := $6163   ES:DI := 0:0
        INT $2F
        present if AX = 0, BX = MagicBX xor MagicXorBX, CX = MagicCX xor
        MagicXorCX

    **The two reply values are not arbitrary**: $5472 xor $6B65 is $3F17 and
    $6163 xor $7220 is $1343, which is why those two immediates appear below
    with no explanation of where they came from. The player answers by XORing
    the challenge with the rest of its own name.

    THE DL FLAG IS THE DOCUMENTED RESULT: the doc's sequence clears DL, tests
    all three halves, and does INC DL on success, so "DL contains 1 if the
    DemoVT is in fact installed, or 0 if it is not". MusicDetect follows that
    sequence to the letter -- which is why it sets a register that nothing in
    this unit ever reads.

    On success ES:DI points at a Pascal-format version string and ES:[DI-4] is
    a far pointer to the player's control block. The doc lays that block out,
    and the offsets this unit uses fall straight out of it:

        Semaphores      256 bytes    at   $000
        ChansTrig        32 bytes    at   $100
        NumChannels       1 byte     at   $120
        CtrlEntryPoint    4 bytes    at   $121   <- the dispatch routine
        TickCounter       4 bytes    at   $125   incremented at 50Hz
        RegEntryPoint     4 bytes    at   $129

    So CB+$121 and CB+$123 are the two halves of CtrlEntryPoint, and the
    player's own name for the field is the one to use. Commands are a far call
    through it with a function number pushed; state like the volume is a byte
    written DIRECTLY into a control-block field.

    Every entry point tests the control-block segment first and does nothing if
    the player is absent, which is why the demo runs silently rather than
    crashing when it is not loaded.

  =========================================================================== }

{ 286 instructions are permitted -- the dispatch calls push their function
  number as an 8-bit immediate. }
{$G+}

unit DemoVT;

interface

procedure MusicDetect;                    far;
procedure MusicPoll;                      far;   { function 2 }
procedure MusicStart;                     far;   { function 0 }
procedure MusicStop;                      far;   { function 1 }
procedure MusicFunc3;                     far;   { function 3 }
function  MusicPos : LongInt;             far;
procedure MusicCue;                       far;
procedure SyncPattern(A, B : Byte);       far;   { part 002 only }
procedure SetVolume(V : Byte);            far;
function  GetVolume : Byte;               far;

type
  { A far pointer with its two halves named separately, because the code tests
    the SEGMENT on its own -- a zero segment is how "the player is not there"
    is represented, and testing it is the guard at the top of every routine.

    The segment field is Sgmt and not Seg on purpose: SEG is an operator in
    Turbo Pascal's inline assembler, so `Block.Seg` inside an asm block is a
    syntax error rather than a field reference. }
  TFarPtr = record Ofs, Sgmt : Word end;

const
  { WHERE THE PLAYER IS, cached by MusicDetect and read by everything else.
    Block points at the control block the handshake returned; Entry is a copy
    of its CtrlEntryPoint field, so a command is one indirect far call rather
    than two memory reads.

    BOTH ARE ZERO UNTIL DETECTION SUCCEEDS, and Block.Sgmt staying zero is what
    every routine below tests before doing anything. That single test is why
    the demo runs silently instead of crashing when the player is not loaded.

    Typed constants rather than variables, which in Turbo Pascal means
    initialised AND assignable -- so the zeroes are in the file image and
    MusicDetect can still store over them. }
  Block : TFarPtr = (Ofs : 0; Sgmt : 0);
  Entry : TFarPtr = (Ofs : 0; Sgmt : 0);

implementation

const
  CuePosition = $19;      { MusicCue polls until the position
                            reaches 25, then zeroes it }

const
  { OFFSETS INTO THE PLAYER'S CONTROL BLOCK. Each names a field the demo reads
    or writes directly rather than through a dispatch call -- the song position,
    the sync flag, the volume byte. The player's documented layout is in the
    unit header.

    They are typed constants, so the code READS them from memory rather than
    folding them into an instruction. That is how the original does it, and it
    would matter to anyone patching the values at runtime. }
  { THREE OF THE FIVE BELOW ARE NEVER READ -- Unread, SyncValue1 and
    SyncValue2. They are here because the original's data image carries them,
    and a declared typed constant is allocated whether anything references it
    or not. Removing them would move every field after this unit's data. }
  Unread    : Word = 0;          { in part 004 }
  PosField  : Word = $0125;      { the song position, a LongInt }
  SyncField : Word = $0203;      { the sync FLAG }
  SyncValue1 : Word = $0204;
  SyncValue2 : Word = $0205;
  VolField  : Word = $0206;      { the volume byte }

var
  { MusicCue's comparand. A unit-level variable rather than a local because
    the routine is hand assembler with no stack frame to put one in. }
  CueTarget : Word;

{ --------------------------------------------------------------------------
probe for the resident player and cache its block and entry.

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

  THE DL FLAG IS THE PUBLISHED INTERFACE'S OWN RESULT, not a curiosity. The
  shipped DEMOVT.DOC gives a calling sequence that clears DL, tests all three
  halves of the reply and does INC DL on success, so that "DL will contain a 1
  if the DemoVT is in fact installed". This routine follows that sequence to
  the letter.

  So it sets a register nothing in this unit reads -- every path falls into the
  same RETF, and a Pascal Boolean would come back in AL anyway. Reading it as a
  mistake is the wrong conclusion: the author implemented the documented
  handshake exactly as documented, and that is also why the two reply values
  appear below as bare immediates rather than as an XOR of the player's name. }
procedure MusicDetect; assembler;
asm
  MOV  AX, $5654          { 'VT' -- the first third of the magic number     }
  MOV  BX, $5472          { 'Tr'                                            }
  MOV  CX, $6163          { 'ac' -- together, "VTrac"                       }
  XOR  DI, DI             { ES:DI := 0:0, where the answer comes back       }
  MOV  ES, DI
  INT  $2F                { the DOS multiplex interrupt                     }
  XOR  DL, DL             { DL := 0, the documented "not installed" answer  }
  AND  AX, AX             { a resident player clears AX                     }
  JNZ  @@None             {   it did not -- nothing is installed            }
  CMP  BX, $3F17          { second half of the answer                       }
  JNZ  @@None             {   wrong: not our player                         }
  CMP  CX, $1343          { third half                                      }
  JNZ  @@None             {   wrong                                         }
  INC  DL                 { DL := 1 -- installed, per the doc's sequence     }
  LES  DI, ES:[DI-4]      { ES:DI := the far pointer below the handler      }
  MOV  Block.Ofs, DI      { cache the control block                         }
  MOV  Block.Sgmt, ES     { and its segment -- the "is it there" flag       }
  MOV  AX, ES:[DI+$121]   { CtrlEntryPoint, offset half                     }
  MOV  Entry.Ofs, AX      {   cached for the dispatch calls                 }
  MOV  AX, ES:[DI+$123]   { CtrlEntryPoint, segment half                    }
  MOV  Entry.Sgmt, AX
@@None:                   { <- every failed test lands here and returns     }
end;

{ --------------------------------------------------------------------------
 004e, 005c and 006a -- the four dispatch calls.

  Each is four instructions: bail out if the player is not there, push a
  function number, and call its entry point far and indirect. There is no
  stack fixup afterwards, so the player cleans up its own argument.

  Function 3 is part 001's alone -- see the note in the header.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt <> 0 then TPlayerProc(Entry)(Func);

  which is close, but Pascal cannot express "test one variable and call
  through another" without naming a procedural type and assigning to it.
  -------------------------------------------------------------------------- }
procedure MusicPoll; assembler;      { function 2 }
asm
  CMP  Block.Sgmt, 0      { is the player resident?                         }
  JZ   @@Out              { no -- do nothing at all                         }
  PUSH 2                  { function 2: poll                                }
  CALL DWORD PTR Entry    { far indirect; the player pops the arg  }
@@Out:                    { <- the not-resident case returns from here      }
end;

procedure MusicStart; assembler;     { function 0 }
asm
  CMP  Block.Sgmt, 0      { resident?                                       }
  JZ   @@Out              { no                                              }
  PUSH 0                  { function 0: start                               }
  CALL DWORD PTR Entry    { far indirect through Entry                   }
@@Out:                    { <- the not-resident case returns from here      }
end;

procedure MusicStop; assembler;      { function 1 }
asm
  CMP  Block.Sgmt, 0      { resident?                                       }
  JZ   @@Out              { no                                              }
  PUSH 1                  { function 1: stop                                }
  CALL DWORD PTR Entry    { far indirect through Entry                   }
@@Out:                    { <- the not-resident case returns from here      }
end;

procedure MusicFunc3; assembler;     { function 3 -- part 001 only }
asm
  CMP  Block.Sgmt, 0      { resident?                                       }
  JZ   @@Out              { no                                              }
  PUSH 3                  { function 3 -- resync the play position          }
  CALL DWORD PTR Entry    { far indirect through Entry                   }
@@Out:                    { <- the not-resident case returns from here      }
end;

{ --------------------------------------------------------------------------
read the song position, a LongInt at block + PosField.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt = 0 then MusicPos := 0
      else MusicPos := MemL[Block.Sgmt : Block.Ofs + PosField];

  The result is built directly in DX:AX, which is where Turbo Pascal wants a
  LongInt function result anyway -- so the two really are the same here.
  -------------------------------------------------------------------------- }
function MusicPos : LongInt; assembler;
asm
  XOR  AX, AX             { the not-resident answer: 0, low word            }
  XOR  DX, DX             {   and high word                                 }
  CMP  Block.Sgmt, 0      { resident?                                       }
  JZ   @@Out              { no -- return the zero already in DX:AX          }
  LES  SI, Block          { ES:SI := the player's control block             }
  ADD  SI, [PosField]     { + the position field's offset within it         }
  MOV  AX, ES:[SI]        { low word of the LongInt                         }
  MOV  DX, ES:[SI+2]      { high word                                       }
@@Out:                    { <- DX:AX is the function result                 }
end;

{ --------------------------------------------------------------------------
cue the module to a known place.

      zero the position
      repeat  MusicPoll  until  MusicPos - $19 = CueTarget
      zero the position again

  So it spins the player forward until it reports position 25, then resets
  the counter -- which is how a scene's timing gets pinned to the music.

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
  CMP  Block.Sgmt, 0      { resident?                                       }
  JZ   @@Out              { no -- nothing to cue                            }
  CALL MusicPos           { called, answer thrown away         }
  XOR  AX, AX             { zero, to clear the position with                }
  LES  SI, Block          { ES:SI := the control block                      }
  ADD  SI, [PosField]     { + the position field                            }
  MOV  ES:[SI], AX        { clear the low word                              }
  MOV  ES:[SI+2], AX      { and the high word                               }
  MOV  [CueTarget], AX    { := 0, the value we spin toward         }
@@Spin:                   { <- poll until the player reaches position 25    }
  CALL MusicPoll          { let it advance one step                         }
  CALL MusicPos           { where is it now? -- DX:AX                       }
  SUB  AX, CuePosition    { $19 -- low word only, the original ignores DX   }
  CMP  AX, [CueTarget]    { reached position 25 yet?                        }
  JNZ  @@Spin             { no -- poll again                                }
  XOR  AX, AX             { yes: reset the counter to zero                  }
  LES  SI, Block          { ES:SI := the control block again                }
  ADD  SI, [PosField]     { + the position field                            }
  MOV  ES:[SI], AX        { clear the low word                              }
  MOV  ES:[SI+2], AX      { and the high word                               }
@@Out:                    { <- the not-resident case returns from here      }
end;

{ --------------------------------------------------------------------------
write the three-byte sync slot at block + SyncField:

      [0] := 1          the "there is a request" flag
      [1] := A          BP+8, the FIRST declared parameter
      [2] := B          BP+6

  This is what pins a scene's choreography to the module: the player picks
  the request up on its next tick and jumps the song to that pattern and row.
  Part 002's scene 1 calls it as (5, 1); nothing in part 001 or 003 does.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt = 0 then Exit;
      Mem[Block.Sgmt : Block.Ofs + SyncField]     := 1;
      Mem[Block.Sgmt : Block.Ofs + SyncField + 1] := A;
      Mem[Block.Sgmt : Block.Ofs + SyncField + 2] := B;
  -------------------------------------------------------------------------- }
procedure SyncPattern(A, B : Byte); assembler;
asm
  CMP  Block.Sgmt, 0      { resident?                                       }
  JZ   @@Out              { no                                              }
  LES  SI, Block          { ES:SI := the control block                      }
  ADD  SI, [SyncField]    { + the sync slot's offset                        }
  MOV  BYTE PTR ES:[SI], 1  { flag it: there is a request waiting           }
  MOV  AH, A              { the first parameter                             }
  INC  SI                 { step to the second byte of the slot             }
  MOV  ES:[SI], AH        { store it                                        }
  MOV  AL, B              { the second parameter                            }
  INC  SI                 { step to the third byte                          }
  MOV  ES:[SI], AL        { store it                                        }
@@Out:                    { <- the not-resident case returns from here      }
end;

{ --------------------------------------------------------------------------
 -- the volume byte at block + VolField.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if Block.Sgmt <> 0 then
        Mem[Block.Sgmt : Block.Ofs + VolField] := V;

      if Block.Sgmt = 0 then GetVolume := 0
      else GetVolume := Mem[Block.Sgmt : Block.Ofs + VolField];
  -------------------------------------------------------------------------- }
procedure SetVolume(V : Byte); assembler;
asm
  CMP  Block.Sgmt, 0      { resident?                                       }
  JZ   @@Out              { no                                              }
  LES  SI, Block          { ES:SI := the control block                      }
  ADD  SI, [VolField]     { + the volume field's offset                     }
  MOV  AL, V              { the new volume                                  }
  MOV  ES:[SI], AL        { store it                                        }
@@Out:                    { <- the not-resident case returns from here      }
end;

function GetVolume : Byte; assembler;
asm
  XOR  AL, AL             { the not-resident answer: 0                      }
  CMP  Block.Sgmt, 0      { resident?                                       }
  JZ   @@Out              { no -- return the zero already in AL             }
  LES  SI, Block          { ES:SI := the control block                      }
  ADD  SI, [VolField]     { + the volume field                              }
  MOV  AL, ES:[SI]        { read it                                         }
@@Out:                    { <- AL is the function result                    }
end;

{ The unit's initialisation body is empty. }
begin
end.
