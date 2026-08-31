{ ==========================================================================
  P1STAR -- part 001 scene 4's starfield, segment 12b2.

  The uses clause of P1INTRO runs in REVERSE segment order, so this unit is
  named there between P1VECTOR and P1BALLS. }
unit P1STAR;
{$A-}   { NO VARIABLE ALIGNMENT, and it does nothing on its own -- see the note
          beside Star. It is one of three changes that only work together. }

{ 286 instructions are permitted -- the star record's stride needs a
  multiply the 8086 cannot do in one instruction. }
{$G+}

interface

uses VGA;

const
  StarCount  = 90;                          { $5A }

type
  { 9 bytes in the original. }
  TStar = record
    X, Y, DX, Spare : Integer;
    Colour          : Byte;
  end;

var
  { stride 9 -- AND IT LANDS THERE NOW. This unit used to carry a
    long note calling seven bytes an unreachable floor, on the reasoning that
    our TP7 pads a unit's data block to a word boundary where the original's
    did not, and that nothing in any source reaches a block's placement. Three
    hypotheses had been eliminated one at a time and the conclusion drawn from
    their failure. It was wrong, and all three failed for the same reason: each
    was tried ALONE.

    The block's start is still not reachable, but it does not have to be. What
    Star needs is an ODD address, and it takes three changes AT ONCE:

      P1BALLS's Tail3 becomes TWO bytes, so that unit's block ends at $9DD9 and
        ours pads the next block to the EVEN $9DDA rather than to $9DDC;
      this unit takes A-minus, so a word-sized type does not step past an odd
        offset;
      and Lead below takes the byte Tail3 gave up, at $9DDA.

    Star then begins at $9DDB. Tail3 as two bytes alone had measured 53 bytes to
    188; $A- alone had measured no change at all; a one-byte probe alone had
    moved Star TWO bytes instead of one. Three results that each read as a
    refutation, and all three were parts of the same answer. Part 001 went from
    nine differing bytes to one.

    WHAT TO TAKE FROM IT: a placement hypothesis cannot be tested one change at
    a time when the compiler rounds. Rounding hides a one-byte move and doubles
    it, so a single change either does nothing visible or overshoots, and both
    readings look like proof. The total has to be held constant across the
    experiment -- which is what moving Tail3's byte in here does. }
  Lead  : Byte;                                     { never read
                                                      -- the byte Tail3 gave up }
  Star  : array[1..StarCount] of TStar;

procedure StarInit(C0, Ca, Cb, Speed : Byte);
procedure StarStep;
procedure StarDraw(Segment : Word);

implementation

{ --------------------------------------------------------------------------
StarInit(C0, C1, C2, Speed)

  Demo_Scene4 pushes 8, 9, 10, 1 in that order, so the three colours are 8, 9
  and 10 and the base speed is 1. Ninety stars, each given a random position
  and one of three depth bands:

      band 0   colour C0   dx := Speed
      band 1   colour C1   dx := Speed * 2
      band 2   colour C2   dx := Speed * 3

  The earlier reconstruction never called this at all, so every star sat at
  (0,0) in colour 0 and the starfield was invisible.
  -------------------------------------------------------------------------- }
procedure StarInit(C0, Ca, Cb, Speed : Byte);
var
  I    : Byte;
  Band : Byte;
begin
  Randomize;
  for I := 1 to StarCount do
    with Star[I] do                     { IMUL DI,AX,9 + $9DD2 }
    begin
      X := Random(319);                 { PUSH $13F,  field +0 }
      Y := Random(199);                 { PUSH $C7,   field +2 }
      Band := Random(3);
      case Band of
        0 : begin Colour := C0;  DX := Speed;      Spare := 0 end;
        1 : begin Colour := Ca;  DX := Speed * 2;  Spare := 0 end;
        2 : begin Colour := Cb;  DX := Speed * 3;  Spare := 0 end;
      end;
    end;
end;

{ Advance one star: X := X + DX, wrapping at either edge of the screen. }
procedure StarStep; assembler;
asm
        MOV     BX, 0                   { a byte offset, not an   }
        MOV     CX, StarCount           { 00c3        index -- ninety stars  }
@@Star: MOV     DX, BX                  { 00c6  park it round the field work }
        MOV     DI, [BX + OFFSET Star]          { 00c8  X                    }
        ADD     DI, [BX + OFFSET Star + 4]      { 00cc  + DX                 }
        OR      DI, DI
        JGE     @@NotLeft
        ADD     DI, 319                 { 00d4  wrapped off the left edge   }
        JMP     @@Store
@@NotLeft:
        CMP     DI, 319
        JLE     @@Store
        SUB     DI, 319                 { 00e0  or off the right            }
@@Store:
        MOV     [BX + OFFSET Star], DI
        MOV     BX, DX
        ADD     BX, 9                   { 00ea  one record on               }
        DEC     CX
        JNE     @@Star
end;

{ --------------------------------------------------------------------------
StarDraw(Segment). HAND ASSEMBLER, verbatim.

  Every tell is present. There is no ENTER, only PUSH BP / MOV BP,SP, in a
  segment whose other Pascal routine opens ENTER 6 -- so this one was not
  compiled from Pascal. `MOV BX,0` is two bytes longer than the XOR the code
  generator emits for a zeroed register. The loop is `DEC CX / JNE` against a
  count loaded once with `MOV CX,$5A`, where a Pascal `for` would compare
  against a limit. And the write is a bare STOSB with ES:DI walked by hand.

  BX carries the byte offset into the star array and advances by 9 -- the
  record size -- so the three loads are one displacement apart from the array
  base rather than three subscript computations. DX holds BX across the row
  lookup, because BX is needed as the table index and there is no spare
  register.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 1 to StarCount do
        Mem[Segment : YOfs[Star[I].Y] + Star[I].X] := Star[I].Colour;

  Note the row TABLE, not a multiply: our previous transcription computed
  Y * ScrWidth, which is the same address by different code.
  -------------------------------------------------------------------------- }
{ `far` is not repeated here: an interface routine is far already, and TP7
  answers the duplicate directive with "BEGIN expected". }
procedure StarDraw(Segment : Word); assembler;
asm
  MOV  AX, Segment              { which screen -- $A000 or the virtual one   }
  MOV  ES, AX                   { ES:DI addresses the pixel                 }
  MOV  BX, 0                    { byte offset into Star; NOT xor, verbatim   }
  MOV  CX, StarCount            { $5A -- 90 stars, counted down             }
@Star:
  MOV  DX, BX                   { keep the offset; BX is about to be reused  }
  MOV  AL, [BX + OFFSET Star + 8]  { .Colour, offset 8 of the nine bytes     }
  MOV  DI, [BX + OFFSET Star]      { .X, offset 0                            }
  MOV  BX, [BX + OFFSET Star + 2]  { .Y, offset 2 -- BX now the row          }
  SHL  BX, 1                    { * 2, a word index into the row table       }
  ADD  DI, [BX + OFFSET YOfs]   { + the row's byte offset                   }
  STOSB                         { one byte, and DI advances (unused)         }
  MOV  BX, DX                   { the offset back                            }
  ADD  BX, 9                    { next star, one record on                   }
  DEC  CX
  JNE  @Star
end;


begin
end.
