(* ===========================================================================
  SETRGB.INC -- write one DAC entry, HAND ASSEMBLER, verbatim.

  ONE TEXT, INCLUDED BY EVERY UNIT THAT NEEDS IT, the same way BLITCLIP.INC is.
  Part 002 compiles these ten instructions TWICE, in two different units:

      part 002  140c:01af  P2VIEW.PAS   linear $0426f
      part 002  12f8:0000  VGA.PAS      linear $043a8
      part 003  12f8:0048  VGA.PAS
      part 004  11e3:0048  VGA.PAS

  The duplication in part 002 is not an accident to be tidied away. P2SOLID
  calls the P2VIEW copy EIGHTEEN times and a far call encodes its target's
  segment AND offset, so pointing those callers at VGA.SetRGB instead differs
  in four bytes at every one of the eighteen sites. P2SOLID's `uses` lists
  P2View after VGA, which is what aims them here.

  THE HEADER IS PART OF THE SHARED TEXT. Both units declare it far in their
  interface, and in any case near and far are decided by the surrounding unit
  rather than by this line -- see SETPAL768.INC's note.

  THE PARAMETER ORDER IS LOAD-BEARING and cost a whole bug. Declared as
  (B, G, R, Col) the body still worked, but the call sites disagreed with each
  other, and part 003's `for I := 0 to 255 do SetRGB(I,0,0,0)` then set colour
  ZERO's blue 256 times instead of blanking the palette. That was the blue
  screen.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := Col;
      Port[$3C9] := R;  Port[$3C9] := G;  Port[$3C9] := B;

  which compiles to four separate loads of DX; the original loads it once and
  steps it with a single INC.
  =========================================================================== *)
procedure SetRGB(Col, R, G, B : Byte); assembler;
asm
  MOV  DX, $3C8         { the DAC WRITE index register                       }
  MOV  AL, Col          { which entry                                        }
  OUT  DX, AL           { select it                                          }
  INC  DX               { DX := $3C9, the DAC data register                  }
  MOV  AL, R            { red, 0..63                                         }
  OUT  DX, AL           { the DAC takes the three in order and latches       }
  MOV  AL, G            { green                                              }
  OUT  DX, AL           {   the entry after the third                        }
  MOV  AL, B            { blue                                               }
  OUT  DX, AL
end;
