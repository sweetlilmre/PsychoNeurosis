{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.006 scene 3, segment 1118.

  A fire effect with a picture burning in front of it.

  An 80 x 100 grid is seeded along its bottom row with random 0 or 255, and
  every frame each cell becomes the average of its left, right, self and the
  cell BELOW, minus one, written one row UP. Each cell is drawn as a 4 x 2
  block, so the grid fills the 320-wide screen. A 29,120-byte picture is then
  overlaid transparently across the bottom 91 rows.

  Before any of that there is a long title sequence: a 30 x 7 bitmap slides in
  from the right in four stages of decreasing speed, three palette entries
  flicker at random the whole time, a fourth tracks the position, and a
  diagonal spark walks across the screen leaving a trail. It ends on a white
  flash and a fade to black.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/27-part6-notes.md for the reading. }

{$S-}   { opens ENTER $484,0 with no stack check. }
{$G+}   { 186: SHR AX,2 with an immediate, in the diffusion loop }
{$N+}   { the spark and the palette ramp go through the x87 }

unit P6FIRE;

{ NO VARIABLE ALIGNMENT. With it on, Turbo Pascal pads a variable up to an
  even address; this unit has a word at an odd one, so the padding must be off
  or everything after it moves. }
{$A-}
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

interface

procedure Scene3;

implementation

uses Crt, VGA;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

const
  GridW    = 80;                  { counts to $50 }
  GridH    = 100;                 { counts to $64 }
  Cells    = $1EA0;               { 98 rows of 80 }
  PicSize  = $71C0;               { 29120 -- the picture, 320 x 91 }
  PicAt    = $8700;               { 34560 -- row 108 }
  TitleW   = 30;                  { $1E -- the bitmap stride }
  TitleH   = 7;                   { counts to 7 }
  DataOfs  = DAT_P6_FIREPIC;   { where this scene's assets start }
  Frames   = $12C;                { 300 frames, then the scene ends }
  HoldTill = $64;                 { 100 -- when the scroll-out starts }

  { The three colours that flicker and the one that tracks. The binary pushes
    them as negative words -- SetRGB only looks at the low byte. }
  Flick1   = $E3;   Flick2 = $E4;   Flick3 = $E5;
  Track    = $E1;
  SparkCol = $FE;                 { pushes -2 }

type
  { 256 THREE-BYTE ELEMENTS, not 768 bytes, and the displacements say so.
    The original addresses the green and blue components as [BX+DI-$403]
    and [BX+DI-$402] -- the component offset FOLDED INTO THE DISPLACEMENT,
    which is a record field. A flat Pal[I*3+1] cannot produce that: Turbo
    Pascal emits INC AX for the +1 and leaves the displacement at -$404.
    It also builds the index straight into DI here, where the flat form
    computes in AX and then copies. Same 768 bytes either way. }
  TRGB   = record R, G, B : Byte end;
  TPal256 = array[0..255] of TRGB;

var
  { TWO-DIMENSIONAL AND ONE-BASED. The compiler folds both low bounds into the
    displacement, so a flat 0-based array produces the same instruction here --
    but it puts the array somewhere else, and the address is not free. }
  Grid   : array[1..GridH, 1..GridW] of Byte;   { 8,000 bytes }

  Pic    : Pointer;

  { THE TITLE BITMAP AND THE 210 BYTES READ OFF THE FILE ARE THE SAME THING --
    one 7 x 30 bitmap, read into and then drawn from. There is no second,
    unused buffer. }
  TitleB : array[1..TitleH, 1..TitleW] of Byte;

  SparkX : Real;
  SparkY : Real;


{ --------------------------------------------------------------------------
  the assets.

  ASSETS  NEUROSIS.DAT $001836AD:
            29,120 bytes  the picture, 320 x 91
            210 bytes     the title bitmap, 7 x 30
            768 bytes     palette A -- all 256 entries
            768 bytes     palette B -- only entries 238..255 are taken
            768 bytes     palette C -- only entries 225..237 are taken

  The three palettes are read into the SAME buffer in turn, so only the slice
  each pass loops over survives.
  -------------------------------------------------------------------------- }
procedure Setup;
{ THE DECLARATION ORDER IS THE REVERSE OF THE OBVIOUS ONE: the two counters
  come FIRST and the file record LAST. Locals are allocated first-declared
  nearest BP, so writing the big buffers first still compiles, still gives a
  legal frame, and puts every offset in the routine somewhere else.

  WHAT THOSE 256 BYTES ARE IS NOT DECIDABLE FROM THE BINARY, and saying so
  is the honest answer. Nothing reads the slot, so a 256-byte local here
  and a 1024-byte Pal read 768 bytes at a time produce THE SAME BYTES
  everywhere -- same frame, same base addresses, same `push $0300`. This
  form is chosen because it keeps SizeOf(Pal) equal to the 768 the original
  actually pushes, so no literal has to be written where a SizeOf belongs.
  If a later reading of the file layout settles it the other way, the
  measurement will not change. }
var
  I, J : Integer;
  Spare : String;                 { 256 bytes, NEVER READ }
  Pal : TPal256;
  F   : file;

  { the scene has its own copy of SetRGB rather than using the
    VGA unit's, and it is nested inside Setup: RET $0A pops eight bytes of
    parameter plus the two-byte static link.

    HAND ASSEMBLER, transcribed verbatim. Four Port[] writes are what this
    was, and they cannot produce these bytes: Turbo Pascal emits MOV DX,imm
    for every constant port index, so `Port[$3C9] := R` reloads DX each
    time and never emits INC DX. It also evaluates the VALUE before the
    port, giving MOV AL then MOV DX, where the original does DX then AL.
    Two tells, opposite ways round. 27 bytes against our 35.

    FOR REFERENCE ONLY, the equivalent Pascal -- not what the binary does:
      Port[$3C8] := Col;  Port[$3C9] := R;
      Port[$3C9] := G;    Port[$3C9] := B;
  }
  procedure SetDAC(Col, R, G, B : Byte);
  begin
    asm
      MOV  DX, $03C8    { the DAC write-index port                        }
      MOV  AL, Col      { first parameter, so highest offset  }
      OUT  DX, AL       { select the colour                               }
      INC  DX           { $03C9, the data port -- DX is kept live for all
                          three components, which is the whole saving     }
      MOV  AL, R
      OUT  DX, AL
      MOV  AL, G
      OUT  DX, AL
      MOV  AL, B
      OUT  DX, AL
    end;
  end;

begin
  GetMem(Pic, PicSize);
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Pic^, PicSize);
  BlockRead(F, TitleB, SizeOf(TitleB));          { the title }

  BlockRead(F, Pal, SizeOf(Pal));
  for I := 0 to $FF do
    SetDAC(I, Pal[I].R, Pal[I].G, Pal[I].B);
  BlockRead(F, Pal, SizeOf(Pal));
  for I := $EE to $FF do
    SetDAC(I, Pal[I].R, Pal[I].G, Pal[I].B);
  BlockRead(F, Pal, SizeOf(Pal));
  for I := $E1 to $ED do
    SetDAC(I, Pal[I].R, Pal[I].G, Pal[I].B);

  for I := 1 to GridH do
    for J := 1 to GridW do
      Grid[I, J] := 0;
  Close(F);
end;

{ --------------------------------------------------------------------------
  lay the picture over the bottom of the screen, colour 0
  transparent. HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 0 to 29119 do
        if Pic^[I] <> 0 then Mem[Segment : $8700 + I] := Pic^[I];

  The only reason it is assembler at all is the LODSB/STOSB pair and the LOOP.
  DI ADVANCES ON A TRANSPARENT PIXEL TOO -- the skip jumps to the increment,
  not past it. Reading that jump as landing one instruction later holds DI back
  on every zero byte and slides the picture apart. }
procedure Overlay(Segment : Word); assembler;
asm
  PUSH DS
  MOV  AX, Segment
  MOV  ES, AX
  LDS  SI, Pic
  MOV  DI, 8700h         { row 108                                }
  MOV  CX, 71C0h         { 29120 bytes                            }
@@Next:
  LODSB
  CMP  AL, 0
  JZ   @@Skip
  MOV  ES:[DI], AL
@@Skip:
  INC  DI                { on EVERY byte, stored or not           }
  LOOP @@Next
  POP  DS
end;

{ --------------------------------------------------------------------------
 -- the spark.

  Both are the same routine with a different velocity: erase the old position
  if it is still the spark's colour, step, and draw at the new one if what is
  there is black. The fast one moves half a pixel a frame on both axes; the
  slow one 0.1 across and 0.2 down.
  -------------------------------------------------------------------------- }
procedure SparkHalf;
begin
  { NO PARAMETERS AND NO LOCALS, and it rounds the two coordinates twice over
    -- once for the read and again for the write inside the same `if`. Caching
    them, or sharing one routine between the two speeds with the velocity as a
    parameter, is the obvious way to write this and is not what the binary
    does. }
  if GetPixel(Round(SparkX), Round(SparkY), VGASeg) = SparkCol then
    PutPixel(Round(SparkX), Round(SparkY), 0, VGASeg);
  SparkX := SparkX - 0.5;
  SparkY := SparkY + 0.5;
  if GetPixel(Round(SparkX), Round(SparkY), VGASeg) = 0 then
    PutPixel(Round(SparkX), Round(SparkY), SparkCol, VGASeg);
end;

procedure SparkSlow;
begin
  { NO PARAMETERS AND NO LOCALS, the same shape as SparkHalf above. }
  if GetPixel(Round(SparkX), Round(SparkY), VGASeg) = SparkCol then
    PutPixel(Round(SparkX), Round(SparkY), 0, VGASeg);
  SparkX := SparkX - 0.1;
  SparkY := SparkY + 0.2;
  if GetPixel(Round(SparkX), Round(SparkY), VGASeg) = 0 then
    PutPixel(Round(SparkX), Round(SparkY), SparkCol, VGASeg);
end;
{ --------------------------------------------------------------------------
  the title sequence.

  Four stages, all the same shape: slide the 30 x 7 bitmap in one pixel at a
  time, flicker three palette entries, and set a fourth from the position.
  What changes between them is the range, the delay, the divisor in the ramp,
  which channel flickers, and whether the spark runs.

    320 -> 190   red flicker,   ramp /20, Delay 10, no spark
    189 -> 170   red flicker,   ramp /20, Delay 10, fast spark
    169 -> 160   blue flicker,  ramp /40, Delay  5, slow spark
    159 -> -30   blue flicker,  ramp /40, no delay, slow spark

  Then the spark alone for 500 frames, a white flash, and a fade to black.
  -------------------------------------------------------------------------- }
procedure Title;
var
  X, I, J, V : Integer;

begin
  SparkX := 205.0;
  SparkY := 48.0;

  for X := $140 downto $BE do
  begin
    { INLINE, and it appears once per loop. }
    for I := 1 to TitleW do
      for J := 1 to TitleH do
        if (X + I < 320) and (X + I > 0) then
          PutPixel(X + I, J + $28, TitleB[J, I], VGASeg);
    SetRGB(Flick1, Random($40), 0, 0);
    SetRGB(Flick2, Random($40), 0, 0);
    SetRGB(Flick3, Random($40), 0, 0);
    { `mod`, NOT `div`, AND THE RUNTIME HELPER'S TAIL PROVES IT. Turbo Pascal
      uses ONE routine for both operators -- RTL $3633 in this part -- and it
      returns the QUOTIENT in DX:AX and the REMAINDER in CX:BX:

          mov  ecx, edx          ; ECX := the remainder
          shld edx, eax, 0x10    ; quotient  -> DX:AX
          shld ebx, ecx, 0x10    ; remainder -> CX:BX

 is MOV AX,CX / MOV DX,BX immediately after the call, so the
      original takes the REMAINDER. Ours went straight on with DX:AX and took
      the quotient. Two bytes at each of four sites, and which operator it is
      cannot be read from the call alone -- only from what happens to CX:BX
      afterwards.

      THE VALUE RANGE AGREES, which is the second reading. V is the red channel
      of SetRGB, valid 0..63. X runs $140 down to $BE, so Round(X / 20.0) is 16
      down to 10; `div 2` gives 8..5 and times $3C is 300..480, far outside the
      DAC and truncated to nonsense by the Byte parameter. `mod 2` gives 0 or 1,
      so V is 0 or 60 -- a clean two-step flicker on the tracker colour, which
      is what the surrounding SetRGB calls are doing. }
    V := (Round(X / 20.0) mod 2) * $3C;
    SetRGB(Track, V, 0, 0);
    Delay(10);
  end;

  for X := $BD downto $AA do
  begin
    { INLINE, and it appears once per loop. }
    for I := 1 to TitleW do
      for J := 1 to TitleH do
        if (X + I < 320) and (X + I > 0) then
          PutPixel(X + I, J + $28, TitleB[J, I], VGASeg);
    SetRGB(Flick1, Random($40), 0, 0);
    SetRGB(Flick2, Random($40), 0, 0);
    SetRGB(Flick3, Random($40), 0, 0);
    V := (Round(X / 20.0) mod 2) * $3C;
    SetRGB(Track, V, 0, 0);
    Delay(10);
    SparkHalf;
  end;

  for X := $A9 downto $A0 do
  begin
    { INLINE, and it appears once per loop. }
    for I := 1 to TitleW do
      for J := 1 to TitleH do
        if (X + I < 320) and (X + I > 0) then
          PutPixel(X + I, J + $28, TitleB[J, I], VGASeg);
    SetRGB(Flick1, 0, 0, Random($40));
    SetRGB(Flick2, 0, 0, Random($40));
    SetRGB(Flick3, 0, 0, Random($40));
    V := (Round(X / 40.0) mod 2) * $3C;
    SetRGB(Track, V, 0, 0);
    Delay(5);
    SparkSlow;
  end;

  for X := $9F downto -$1E do
  begin
    { INLINE, and it appears once per loop. }
    for I := 1 to TitleW do
      for J := 1 to TitleH do
        if (X + I < 320) and (X + I > 0) then
          PutPixel(X + I, J + $28, TitleB[J, I], VGASeg);
    SetRGB(Flick1, 0, 0, Random($40));
    SetRGB(Flick2, 0, 0, Random($40));
    SetRGB(Flick3, 0, 0, Random($40));
    V := (Round(X / 40.0) mod 2) * $3C;
    SetRGB(Track, V, 0, 0);
    SparkSlow;
  end;

  { BOTH TAIL LOOPS REUSE X, the slide counter, rather than I. The inner I and
    J belong to the bitmap blit and are not touched again once the slide is
    over; counting in I instead moves seventeen bytes across the two loops. }
  for X := 1 to $1F4 do
  begin
    SparkSlow;
    Delay(2);
  end;

  SetRGB(0, $3F, $3F, $3F);                      { white }
  Delay($64);
  for X := $3F downto 0 do
  begin
    SetRGB(0, X, X, X);
    Delay(2);
  end;
end;

{ --------------------------------------------------------------------------
  push the picture down the screen, black above it.
  HAND ASSEMBLER, verbatim.
  -------------------------------------------------------------------------- }
procedure ScrollOut(SrcSeg, DstSeg : Word; Down : Word); assembler;
asm
  PUSH DS
  MOV  AX, DstSeg
  MOV  ES, AX
  MOV  AX, SrcSeg
  MOV  DS, AX
  XOR  SI, SI
  XOR  DI, DI
  MOV  BX, Down
  XOR  AX, AX
  MOV  CX, BX
  REP  STOSB             { black down to the new top              }
  MOV  CX, 0FA00h       { 64000                                   }
  SUB  CX, BX
  REP  MOVSB             { and the picture below it               }
  POP  DS
end;

{ --------------------------------------------------------------------------
  the fire.

  The diffusion is HAND ASSEMBLER and the equivalent Pascal is below it. Note
  the average is taken over the cell itself, its two SIDE neighbours and the
  one BELOW -- and written one row ABOVE, which is what makes the flames climb.
  -------------------------------------------------------------------------- }
procedure Run(Segment : Word);
var
  { FOUR DECLARATIONS AND AN x87 TEMPORARY, in ten bytes. The last two bytes
    are the code generator's, not ours -- the compiler parks an FPU status word
    there -- so they cannot be declared and must not be. }
  I     : Integer;
  Tmp   : Integer;
  Unread : Byte;                  { assigned 0 and never read }
  Frame : Integer;
begin
  Frame  := 0;
  Unread := 0;
  Overlay(Segment);
  CopyScreen(Segment, VGASeg);
  Title;

  repeat
    { THE KEY TEST IS INSIDE THE LOOP. Outside it, the key is read once and the
      fire then runs its full 300 frames whatever the keyboard does; inside,
      every frame can end the scene. One byte of jump displacement separates
      the two, and it is the difference between a scene that can be skipped and
      one that cannot. }
    if KeyPressed then Exit;
    { reseed the bottom row. Random is the REAL one here, and the threshold
      is 0.4. }
    { TWO THINGS HERE ARE EASY TO GET WRONG, AND TOGETHER THEY DECIDE HOW HIGH
      THE FIRE CLIMBS.

      THE TEST IS `<`, NOT `>`, so the seed fires on the SMALLER 40% of the
      random values rather than the larger 60%.

      AND THE STORE IS UNCONDITIONAL -- only the VALUE is conditional. So the
      seed is STICKY: the bottom row is written all the way across on every
      frame, carrying the last drawn value into the columns the test skips,
      rather than leaving them at whatever the diffusion cooled them to. That
      is a much hotter bottom row, and a taller fire.

      Tmp is never initialised before the loop, so the first columns of the
      first frame carry whatever the frame held. That is the original's
      behaviour and it is transcribed, not corrected.

 writes [$92A9+I], and $740A + 98*80 + I - 1 is $92A9 + I,
      which is row 99. }
    for I := 1 to GridW do
    begin
      if Random < 0.4 then                       { JBE }
        Tmp := Random(2) * 255;
      Grid[99, I] := Tmp;                        { EVERY column }
    end;

    { ------------------------------------------------------------------
      EQUIVALENT PASCAL, for reference -- the assembler is what runs:

          for each of the 7840 cells from row 2 on:
            V := (Self + Left + Right + Below) div 4;
            if V <> 0 then Dec(V);
            the cell one row UP := V;
            draw V as a 4 x 2 block
      ------------------------------------------------------------------ }
    asm
      MOV  AX, Segment
      MOV  ES, AX
      XOR  DI, DI
      MOV  AX, OFFSET Grid   { assembles to $740A, element [1,1]   }
      MOV  SI, AX
      ADD  SI, 50h           { and on to row 2                    }
      MOV  DX, 0             { the column within the screen row   }
      MOV  BX, 1EA0h         { 7840 cells                         }
      XOR  AX, AX            { ONCE, outside the loop             }
    @@Cell:
      MOV  AL, [SI]          { the loop comes back HERE, so                }
                             {   AH is NOT cleared per cell. The four ADC    }
                             {   AH,0 below therefore carry across cells and }
                             {   SHR AX,2 shifts some of that back into AL.  }
                             {   Clearing AX inside the loop puts the fire   }
                             {   out.                                        }
      ADD  AL, [SI-1]        { the one to the left                }
      ADC  AH, 0
      ADD  AL, [SI+1]        { and to the right                   }
      ADC  AH, 0
      ADD  AL, [SI+50h]      { and the one BELOW                  }
      ADC  AH, 0
      SHR  AX, 2             { the average                        }
      JZ   @@Zero
      DEC  AX                { cool it by one                     }
    @@Zero:
      MOV  [SI-50h], AL      { written one row UP                 }
      CMP  DI, 0ED80h        { past row 190: stop drawing         }
      JNC  @@Next
      MOV  CX, 4
      REP  STOSB             { four across...                     }
      ADD  DI, 13Ch
      MOV  CX, 4
      REP  STOSB             { ...on two rows                   }
      SUB  DI, 140h
      ADD  DX, 4
      CMP  DX, 140h
      JNZ  @@Next
      ADD  DI, 140h          { end of the screen row: drop two    }
      XOR  DX, DX
    @@Next:
      INC  SI
      DEC  BX
      JNZ  @@Cell
    end;

    Overlay(Segment);
    Inc(Frame);
    if Frame < HoldTill then
      CopyScreen(Segment, VGASeg)
    else
      ScrollOut(Segment, VGASeg,
                (Frame - HoldTill) * 320);
  until Frame = Frames;
end;

{ the scene. }
procedure Scene3;
begin
  ClearScreen(VirtScrSeg, 0);
  ClearScreen(VGASeg, 0);
  Setup;
  Run(VirtScrSeg);
  FreeMem(Pic, PicSize);
  ClearScreen(VirtScrSeg, 0);
  ClearScreen(VGASeg, 0);
end;

{ the unit's initialisation is empty. }
begin
end.
