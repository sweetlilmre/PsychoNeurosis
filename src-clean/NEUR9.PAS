{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.009, the end screen.

  Read from bin/NEUROSIS.009; the chart is docs/30-byebye.md. The debug
  info appended to the original names the source (NEUR9.PAS, saved
  4 Feb 1994), every variable, and -- through the line table -- the exact
  shape of the code: main is 98 bytes, and its core is the inline asm
  block below, one instruction per source line as the original had it.

  The sign-off screen is an 80x25 text page with attributes, compiled in
  as a typed constant (src/gen/P9IMG.INC, tools/emit_byebye.py). The asm
  scrolls it up into view from the bottom: each pass copies the image's
  last (25-Row+1) rows to the TOP of text video memory, so the picture
  rises one row every Delay(100). Row 25 copies nothing and Row 0 never
  runs, so the image's own first row is never drawn -- the original does
  the same.

  Directives are measured, not style (docs/30-byebye.md, "Build flags"):
  $G+ because the author's PUSHA and PUSH imm are 286 encodings, and
  $S+ because main calls __StackCheck at 1069:02CD -- the original was
  built with stack checking ON, unlike the demo parts, and dosbuild's
  /$S- must be overridden here in-source for the bytes to match.

  DGROUP (10C3)
 ImageData             DS:$0FF0  P
 Flag (declared in the original, never referenced -- kept)
  =========================================================================== }

{$G+,S+}
program NEUR9;

uses
  Crt;

const
  ImageData_Width  = 80;
  ImageData_Depth  = 25;
  ImageData_Length = 4000;

{$I gen/P9IMG.INC}

var
  P    : Pointer;
  Flag : Byte;

begin
  ClrScr;
  P := @ImageData;

  { Equivalent Pascal, reference only -- the assembler below is the
    original's, transcribed verbatim (1000:0025..0050):

      for Row := 25 downto 1 do
      begin
        Move(Pointer(LongInt(P) + Row * 160)^,
             Ptr(SegB800, 0)^, (2000 - Row * 80) * 2);
        Delay(100);
      end;

    It could not be written that way exactly: the copy must be a word
    copy into B800 for the snowless CRTs the era cared about, and the
    PUSHA/POPA bracket exists because Delay is being called from inside
    an asm block with every register live. }
  asm
    PUSH DS                  { DS is about to be retargeted at the image  }

    MOV  BX, 25              { Row := 25, counting down                   }
  @Row:
    LDS  SI, P               { DS:SI := start of ImageData                }

    MOV  AX, 160             { one text row is 80 chars * 2 bytes         }
    MUL  BX                  { AX := Row * 160                            }
    ADD  SI, AX              { SI := image start + Row rows               }

    MOV  CX, 2000            { the whole screen, in words                 }
    SHR  AX, 1               { AX := Row * 80, the skipped rows in words  }
    SUB  CX, AX              { CX := words actually copied this pass      }

    MOV  AX, 0B800h          { text video memory                          }
    MOV  ES, AX
    XOR  DI, DI              { always to the TOP of the screen            }

    REP  MOVSW               { image tail -> screen top                   }

    PUSHA                    { Delay clobbers; everything here is live    }
    PUSH 100                 { a tenth of a second per row                }
    CALL Delay
    POPA

    DEC  BX                  { next row up                                }
    JNZ  @Row

    POP  DS                  { our DGROUP back                            }
  end;

  GotoXY(1, 23);             { park the DOS prompt below the artwork }
end.
