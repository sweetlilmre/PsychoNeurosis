(* ===========================================================================
  SETPAL.INC -- the 768-byte DAC palette write, HAND ASSEMBLER, verbatim.

  ONE TEXT, INCLUDED BY EVERY UNIT THAT NEEDS IT, the same way BLITCLIP.INC is.
  Four units compile these nine instructions into their own code segment -- the
  shared VGA unit in parts 001, 002 and 004, plus part 001 scene 4's own copy in
  P1BALLS.PAS -- and every copy is identical, because they are all this file.

  THE HEADER IS PART OF THE SHARED TEXT, and it can be because near and far
  are decided by the SURROUNDING unit, not by this line: in VGA.PAS the
  interface declaration makes it far, in P1BALLS.PAS it is an
  implementation-only routine and near, and the same text compiles correctly in
  both. That is the whole reason this file can exist.

  P3MORPH's copy is NOT included from here. Its parameter is an untyped `var P`
  rather than a `P : Pointer`, so its header is genuinely a different line --
  the body is identical, which is exactly the case an include cannot express.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := 0;
      for I := 0 to 767 do Port[$3C9] := TPal768(P^)[I];

  REP OUTSB is one instruction for the whole 768; the Pascal loop is several
  per byte and shows as a visible step on a fade. It does NOT wait for
  retrace -- the callers that care do that themselves.
  =========================================================================== *)
procedure SetPalette768(P : Pointer); assembler;
asm
  PUSH DS               { DS is about to point at the caller's buffer        }
  LDS  SI, P            { DS:SI := the 768-byte palette                     }
  MOV  DX, $3C8         { the DAC WRITE index register                       }
  MOV  AL, 0            { start at colour 0                                  }
  OUT  DX, AL           { select it -- the DAC auto-increments from here     }
  INC  DX               { DX := $3C9, the DAC data register                  }
  MOV  CX, $300         { 768 bytes = 256 entries of R, G, B                 }
  REP  OUTSB            { write them all out from DS:SI                      }
  POP  DS               { restore our data segment                           }
end;
