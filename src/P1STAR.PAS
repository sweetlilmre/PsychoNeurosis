{ ==========================================================================
  P1STAR -- part 001 scene 4's starfield, segment 12b2.

  These three routines were transcribed into P1S4 and measured wrong there for
  as long as they stayed: 1107:09a7 is a FAR call to 12b2:0000, and a routine
  in the calling unit cannot be reached by one. The far call is the whole
  evidence -- within a single segment Turbo Pascal emits PUSH CS plus a near
  CALL, four bytes, and never a 9A. So the original had a unit here, between
  P1S4 (1107) and P1S5 (12c5), holding nothing but the starfield.

  The uses clause of P1INTRO runs in REVERSE segment order, so this unit is
  named there between P1S5 and P1S4.

  `Star` comes with them. It sits at DS:$9DDB in the original, immediately
  after P1S4's data, which is what a unit linked directly after P1S4
  contributes -- so the address is evidence for this split rather than a cost
  of it.
  ========================================================================== }
unit P1STAR;

{$G+}   { 286 instructions, and this unit needs it: 12b2:0017 is IMUL DI,AX,9,
          which TP7 emits only under $G+. Without it the whole address
          computation comes out as a shift-and-add and 12b2:0017..0043 reads as
          a 44-byte difference -- which is what a new unit gets for not
          carrying the switch every other part-001 unit already had. }

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
  { DS:$9DDB, stride 9 }
  { OUR STAR ARRAY LANDS ONE BYTE HIGH AND THAT IS THIS UNIT'S WHOLE DIFFERENCE
    -- SEVEN BYTES, EVERY ONE A DISPLACEMENT. 12b2:001a is ADD DI,$9DD2 in the
    original and $9DD3 in ours, and the three folded bases go with it:
    [BX-$6225] against [BX-$6224] and so on. The address is forced from below:
    P1S4's Blob is 145 records of 51 bytes from DS:$80F5, ending at $9DD7, and
    its Tail3 fills $9DD8..$9DDA, so Star belongs at the ODD $9DDB. Ours pads
    to $9DDC.

    TWO HYPOTHESES ELIMINATED BY MEASUREMENT, so they need not be tried again:
      $A- on THIS unit -- no effect at all, byte for byte. So TP7's $A does
        not control where a unit's data block starts; P1S4 already carries $A-minus
        and it does not help either.
      Tail3 as TWO bytes instead of three, on the theory that our compiler's
        boundary pad supplies the third -- measurably WORSE, 53 differing bytes
        across part 001 to 188. Tail3 is three.
    A THIRD MEASUREMENT PINS IT DOWN, and it makes this a floor rather than an
    open question. Declaring a one-byte Probe immediately before Star moved Star
    from $9DDC to $9DDE -- a jump of TWO, not one. So the Probe took $9DDC and
    Star was then word-aligned past the odd $9DDD, which means our P1Star data
    BLOCK begins at $9DDC and Star's own alignment is a separate, currently
    harmless effect. The byte is the BLOCK's placement: P1S4's data ends at
    $9DDA, the next free byte is the odd $9DDB, and our TP7 pads the following
    unit's block to a word while the original's did not.

    Nothing in either unit's source reaches that. $A- controls variable
    alignment -- it demonstrably works, since adding it to P1S1 is what put F at
    the odd $563F -- and it does not move a block. Moving P1Star in the uses
    clause would move the block, but the clause is also the code segment order,
    which is exact.

    SO THESE SEVEN BYTES ARE A FLOOR: one pad byte, its six folded consequences,
    and three hypotheses eliminated by measurement rather than by argument. The
    next thing that could move it is the .TPU's own data-segment alignment
    record, which is not source-controllable, or a different patch level of
    TP 7.00. }
  Star  : array[1..StarCount] of TStar;             { DS:$9DDB }

procedure StarInit(C0, Ca, Cb, Speed : Byte);
procedure StarStep;
procedure StarDraw(Segment : Word);

implementation

{ --------------------------------------------------------------------------
  12b2:0000 -- StarInit(C0, C1, C2, Speed)

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
  { ENTER 6, AND IT IS TWO BYTES PLUS A `with`. 12b2:0009 sets [BP-1] to 1 and
    12b2:000f INCs it, so the counter is a Byte; 12b2:004a stores Random(3)'s
    result into [BP-2] and 12b2:004d reads it straight back for the case, which
    is a second Byte and not a compiler temporary -- a temporary is not read
    through memory when the value is already in AL; and 12b2:0020 puts DI and
    ES into [BP-6], which is the four bytes a `with` gets for the record's
    address. 1 + 1 + 4 = 6.

    IT IS A `with` AND NOT A POINTER, and the two bytes at 12b2:001e are what
    separate them: PUSH DS / POP ES puts the segment in ES before the pair is
    stored, which is what `with` over a DGROUP record does. Assigning
    @Star[I] to a declared pointer moves DS through AX instead, and leaves no
    room for the case's byte. }
  I    : Byte;                          { [BP-1] }
  Band : Byte;                          { [BP-2] }
begin
  Randomize;                            { 12b2:0004 }
  for I := 1 to StarCount do
    with Star[I] do                     { 12b2:0017, IMUL DI,AX,9 + $9DD2 }
    begin
      X := Random(319);                 { 12b2:0026, PUSH $13F,  field +0 }
      Y := Random(199);                 { 12b2:0034, PUSH $C7,   field +2 }
      { AND Spare := 0 IS INSIDE EACH BRANCH, not before the case. 12b2:0067,
        008a and their third are three separate XOR AX,AX / MOV ES:[DI+6],AX,
        one per arm; hoisting it above the case emits it once. }
      Band := Random(3);                { 12b2:0043 }
      case Band of
        0 : begin Colour := C0;  DX := Speed;      Spare := 0 end;
        1 : begin Colour := Ca;  DX := Speed * 2;  Spare := 0 end;
        2 : begin Colour := Cb;  DX := Speed * 3;  Spare := 0 end;
      end;
    end;
end;

{ [transcribed] 12b2:00c0 -- StarStep. X := X + DX, wrapping on 0 and 319. }
{ HAND ASSEMBLER, TRANSCRIBED VERBATIM. 12b2:00c0 has no prologue at all -- it
  goes straight into MOV BX,0 and ends with a bare RETF -- so no frame and no
  locals; the star count lives in CX and DEC CX / JNE closes the loop; and BX
  walks the array by NINE, the record's size, rather than being multiplied up
  from an index. None of the three is something the code generator produces.

  DX PARKS THE ROW POINTER. BX is copied to DX at the top of each iteration and
  restored from it at the bottom before the ADD BX,9 -- because the two field
  reads and the store all use BX as the index and the wrap arithmetic is done in
  DI. Nothing needs it, and it is what the original does.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 1 to StarCount do
      begin
        X := Star[I].X + Star[I].DX;
        if X < 0 then Inc(X, 319) else if X > 319 then Dec(X, 319);
        Star[I].X := X;
      end;
  -------------------------------------------------------------------------- }
{ @asm 001 12b2:00c0 +0 StarStep }
procedure StarStep; assembler;
asm
        MOV     BX, 0                   { 12b2:00c0  a byte offset, not an   }
        MOV     CX, StarCount           { 00c3        index -- ninety stars  }
@@Star: MOV     DX, BX                  { 00c6  park it round the field work }
        MOV     DI, [BX + OFFSET Star]          { 00c8  X                    }
        ADD     DI, [BX + OFFSET Star + 4]      { 00cc  + DX                 }
        OR      DI, DI                  { 00d0                              }
        JGE     @@NotLeft               { 00d2                              }
        ADD     DI, 319                 { 00d4  wrapped off the left edge   }
        JMP     @@Store                 { 00d8                              }
@@NotLeft:
        CMP     DI, 319                 { 00da                              }
        JLE     @@Store                 { 00de                              }
        SUB     DI, 319                 { 00e0  or off the right            }
@@Store:
        MOV     [BX + OFFSET Star], DI  { 00e4                              }
        MOV     BX, DX                  { 00e8                              }
        ADD     BX, 9                   { 00ea  one record on               }
        DEC     CX                      { 00ed                              }
        JNE     @@Star                  { 00ee                              }
end;

{ --------------------------------------------------------------------------
  12b2:00f1 -- StarDraw(Segment). HAND ASSEMBLER, verbatim.

  Every tell is present. There is no ENTER, only PUSH BP / MOV BP,SP, in a
  segment whose other Pascal routine opens ENTER 6 -- so this one was not
  compiled from Pascal. `MOV BX,0` is two bytes longer than the XOR the code
  generator emits for a zeroed register. The loop is `DEC CX / JNE` against a
  count loaded once with `MOV CX,$5A`, where a Pascal `for` would compare
  against a limit. And the write is a bare STOSB with ES:DI walked by hand.

  It is FAR: 12b2:011d is RETF 2, one Word of parameter.

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
  ADD  DI, [BX + OFFSET YOfs]   { + YOfs[Y] = Y * 320 -- DS:$AB5A           }
  STOSB                         { one byte, and DI advances (unused)         }
  MOV  BX, DX                   { the offset back                            }
  ADD  BX, 9                    { next star, one record on                   }
  DEC  CX                       { 12b2:0119                                  }
  JNE  @Star                    { 12b2:011a                                  }
end;


{ AN EMPTY INITIALISATION SECTION, AND THE ORIGINAL HAS ONE. 12b2:0120 is
  PUSH BP / MOV BP,SP / LEAVE -- a routine with a frame and no body, which is
  what Turbo Pascal emits for `begin end.` at the foot of a unit. A bare `end.`
  emits nothing there at all. }
begin
end.
