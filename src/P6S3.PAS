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
  See docs/27-part6-notes.md for the reading.

  ADDRESS MAP
    SetRGBLocal   1118:0000     SparkHalf     1118:020a
    (filename)    1118:001b     SparkSlow     1118:034b
    Setup         1118:0028     Title         1118:0486
    Overlay       1118:01e3     ScrollOut     1118:08a2
    Run           1118:08d3     Scene3        1118:09df

  DGROUP
    DS:$73b9  the fire grid, 100 x 80          DS:$92a9  its bottom row
    DS:$932f  the title bitmap, 30 x 7         DS:$934a  the picture, 29120
    DS:$934e  210 bytes read off the file      DS:$9420  the spark's X, a Real
    DS:$9426  the spark's Y, a Real
  =========================================================================== }

{$S-}   { 1118:0028 opens ENTER $484,0 with no stack check. }
{$G+}   { 186: SHR AX,2 with an immediate, in the diffusion loop }
{$N+}   { the spark and the palette ramp go through the x87 }

unit P6S3;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

interface

procedure Scene3;

implementation

uses Crt, VGA;

const
  GridW    = 80;                  { 1118:01ca counts to $50 }
  GridH    = 100;                 { 1118:01d0 counts to $64 }
  Cells    = $1EA0;               { 7840 -- 1118:0954, 98 rows of 80 }
  PicSize  = $71C0;               { 29120 -- 1118:002c }
  PicAt    = $8700;               { 34560 -- row 108 }
  TitleW   = 30;                  { $1E -- the bitmap stride }
  TitleH   = 7;                   { 1118:0505 counts to 7 }
  DataOfs  = $001836AD;           { 1118:005e pushes $0018 then $36AD }
  Frames   = $12C;                { 300 -- 1118:09d1 }
  HoldTill = $64;                 { 100 -- when the scroll-out starts }

  { The three colours that flicker and the one that tracks. The binary pushes
    them as negative words -- SetRGB only looks at the low byte. }
  Flick1   = $E3;   Flick2 = $E4;   Flick3 = $E5;
  Track    = $E1;
  SparkCol = $FE;                 { 1118:0472 pushes -2 }

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
  { DS:$740A, and TWO-DIMENSIONAL. 1118:01c5 writes [$73B9 + I*80 + J], and a
    1-based array[1..100, 1..80] indexed Grid[I, J] emits exactly that: the
    compiler folds the low bounds, so the displacement is base - 81 and the
    base is $73B9 + 81 = $740A.

    Declared FLAT and 0-based the displacement matches just as well -- both
    forms produce the same instruction -- but they put the array in different
    places, and $73B9 is not available: P6S1's file record occupies $738A to
    $7409. $740A is the first free byte after it, and the chain closes from
    there: $740A + 8,000 is $934A, which is Pic; Pic and TitleB together run to
    $9420, which is SparkX. An earlier pass rejected the 2-D form on the
    strength of the flat index at 1118:0938, which simply needed rewriting. }
  Grid   : array[1..GridH, 1..GridW] of Byte;   { DS:$740A, 8,000 bytes }

  Pic    : Pointer;               { DS:$934a }

  { DS:$934e. The title bitmap and the 210 bytes read off the file are THE
    SAME THING. 1118:04f8 reads it as [$932f + B*30 + A], and $932f + 31 is
    exactly $934e -- so the read lands on element [1,1] of a 7 x 30 bitmap,
    and 7*30 is exactly the 210 bytes read. An earlier pass declared a
    separate `TitleB` at $932f and called this one "read, never used". }
  TitleB : array[1..TitleH, 1..TitleW] of Byte;

  SparkX : Real;                  { DS:$9420 }
  SparkY : Real;                  { DS:$9426 }


{ --------------------------------------------------------------------------
  1118:0028 -- the assets.

  ASSETS  NEUROSIS.DAT $001836AD:
            29,120 bytes  the picture, 320 x 91
            210 bytes     read into DS:$934e and never looked at again
            768 bytes     palette A -- all 256 entries
            768 bytes     palette B -- only entries 238..255 are taken
            768 bytes     palette C -- only entries 225..237 are taken

  The three palettes are read into the SAME buffer in turn, so only the slice
  each pass loops over survives.
  -------------------------------------------------------------------------- }
procedure Setup;
{ THE DECLARATION ORDER IS THE MEASUREMENT and it is the reverse of the
  obvious one. Locals are allocated FIRST-DECLARED NEAREST BP, and the
  original's slots are [BP-$02], [BP-$04], [BP-$404] and [BP-$484], so the
  two counters come first and the file record LAST. Declared the other way
  round the frame is still legal, still compiles, and puts every offset in
  the routine somewhere else.

  AND THE FRAME IS $484 -- 1156 bytes -- where 2 + 2 + 768 + 128 reaches
  only $384. The missing 256 sit between J and Pal: Pal's base is [BP-$404]
  and 768 bytes below [BP-$04] would put it at [BP-$304].

  WHAT THOSE 256 BYTES ARE IS NOT DECIDABLE FROM THE BINARY, and saying so
  is the honest answer. Nothing reads the slot, so a 256-byte local here
  and a 1024-byte Pal read 768 bytes at a time produce THE SAME BYTES
  everywhere -- same frame, same base addresses, same `push $0300`. This
  form is chosen because it keeps SizeOf(Pal) equal to the 768 the original
  actually pushes, so no literal has to be written where a SizeOf belongs.
  If a later reading of the file layout settles it the other way, the
  measurement will not change. }
var
  I, J : Integer;                 { [BP-$02], [BP-$04] }
  Spare : String;                 { [BP-$104] -- 256 bytes, NEVER READ }
  Pal : TPal256;                  { [BP-$404] }
  F   : file;                     { [BP-$484] }

  { 1118:0000 -- the scene has its own copy of SetRGB rather than using the
    VGA unit's, and it is nested inside Setup: RET $0A pops eight bytes of
    parameter plus the two-byte static link.

    HAND ASSEMBLER, transcribed verbatim. Four Port[] writes are what this
    was, and they cannot produce these bytes: Turbo Pascal emits MOV DX,imm
    for every constant port index, so `Port[$3C9] := R` reloads DX each
    time and never emits INC DX. It also evaluates the VALUE before the
    port, giving MOV AL then MOV DX, where the original does DX then AL.
    Two tells, opposite ways round. 27 bytes against our 35.

    handasm.py says `no evidence` here, which is the honest answer for a
    27-byte routine and not a refutation -- its signals need volume.

    FOR REFERENCE ONLY, the equivalent Pascal -- not what the binary does:
      Port[$3C8] := Col;  Port[$3C9] := R;
      Port[$3C9] := G;    Port[$3C9] := B;
  }
  procedure SetDAC(Col, R, G, B : Byte);
  begin
    asm
      MOV  DX, $03C8    { the DAC write-index port                        }
      MOV  AL, Col      { [BP+$0C] -- first parameter, so highest offset  }
      OUT  DX, AL       { select the colour                               }
      INC  DX           { $03C9, the data port -- DX is kept live for all
                          three components, which is the whole saving     }
      MOV  AL, R        { [BP+$0A]                                        }
      OUT  DX, AL
      MOV  AL, G        { [BP+$08]                                        }
      OUT  DX, AL
      MOV  AL, B        { [BP+$06]                                        }
      OUT  DX, AL
    end;
  end;

begin
  GetMem(Pic, PicSize);                          { 1118:002f }
  Assign(F, 'neurosis.dat');                     { 1118:0046 }
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Pic^, PicSize);                   { 1118:007b }
  BlockRead(F, TitleB, SizeOf(TitleB));          { 1118:0092 -- the title }

  BlockRead(F, Pal, SizeOf(Pal));                { 1118:00aa }
  for I := 0 to $FF do                           { 1118:00af }
    SetDAC(I, Pal[I].R, Pal[I].G, Pal[I].B);
  BlockRead(F, Pal, SizeOf(Pal));                { 1118:0105 }
  for I := $EE to $FF do                         { 1118:010a }
    SetDAC(I, Pal[I].R, Pal[I].G, Pal[I].B);
  BlockRead(F, Pal, SizeOf(Pal));                { 1118:0160 }
  for I := $E1 to $ED do                         { 1118:0165 }
    SetDAC(I, Pal[I].R, Pal[I].G, Pal[I].B);

  for I := 1 to GridH do                         { 1118:01a8 }
    for J := 1 to GridW do
      Grid[I, J] := 0;
  Close(F);                                      { 1118:01dc }
end;

{ --------------------------------------------------------------------------
  1118:01e3 -- lay the picture over the bottom of the screen, colour 0
  transparent. HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 0 to 29119 do
        if Pic^[I] <> 0 then Mem[Segment : $8700 + I] := Pic^[I];

  The only reason it is assembler at all is the LODSB/STOSB pair and the LOOP.
  1118:01f9 jumps to 1118:01FE, which is the INC DI -- so DI advances on a
  transparent pixel too. An earlier pass read that jump as landing one
  instruction later, which held DI back on every zero byte and slid the
  picture apart.
  -------------------------------------------------------------------------- }
{ @asm 006 1118:01e3 +33 Overlay }
procedure Overlay(Segment : Word); assembler;
asm
  PUSH DS                { 1118:01e6                                         }
  MOV  AX, Segment       { 1118:01e7                                         }
  MOV  ES, AX            { 1118:01ea                                         }
  LDS  SI, Pic           { 1118:01ec                                         }
  MOV  DI, 8700h         { 1118:01f0  row 108                                }
  MOV  CX, 71C0h         { 1118:01f3  29120 bytes                            }
@@Next:
  LODSB                  { 1118:01f6                                         }
  CMP  AL, 0             { 1118:01f7                                         }
  JZ   @@Skip            { 1118:01f9                                         }
  MOV  ES:[DI], AL       { 1118:01fb                                         }
@@Skip:
  INC  DI                { 1118:01fe  on EVERY byte, stored or not           }
  LOOP @@Next            { 1118:01ff                                         }
  POP  DS                { 1118:0201                                         }
end;

{ --------------------------------------------------------------------------
  1118:020a and 1118:034b -- the spark.

  Both are the same routine with a different velocity: erase the old position
  if it is still the spark's colour, step, and draw at the new one if what is
  there is black. The fast one moves half a pixel a frame on both axes; the
  slow one 0.1 across and 0.2 down.
  -------------------------------------------------------------------------- }
procedure SparkHalf;
begin
  { NO PARAMETERS AND NO LOCALS. 1118:020a takes nothing and rounds SparkX
    and SparkY twice over -- once for the GetPixel and again for the PutPixel
    inside the same `if`. Caching them in two Integers, and sharing one routine
    between the two speeds with the velocity as a parameter, is the obvious way
    to write this and is not what the binary does. }
  if GetPixel(Round(SparkX), Round(SparkY), VGASeg) = SparkCol then
    PutPixel(Round(SparkX), Round(SparkY), 0, VGASeg);
  SparkX := SparkX - 0.5;
  SparkY := SparkY + 0.5;
  if GetPixel(Round(SparkX), Round(SparkY), VGASeg) = 0 then
    PutPixel(Round(SparkX), Round(SparkY), SparkCol, VGASeg);
end;

procedure SparkSlow;
begin
  { NO PARAMETERS AND NO LOCALS. 1118:034b takes nothing and rounds SparkX
    and SparkY twice over -- once for the GetPixel and again for the PutPixel
    inside the same `if`. Caching them in two Integers, and sharing one routine
    between the two speeds with the velocity as a parameter, is the obvious way
    to write this and is not what the binary does. }
  if GetPixel(Round(SparkX), Round(SparkY), VGASeg) = SparkCol then
    PutPixel(Round(SparkX), Round(SparkY), 0, VGASeg);
  SparkX := SparkX - 0.1;
  SparkY := SparkY + 0.2;
  if GetPixel(Round(SparkX), Round(SparkY), VGASeg) = 0 then
    PutPixel(Round(SparkX), Round(SparkY), SparkCol, VGASeg);
end;
{ --------------------------------------------------------------------------
  1118:0486 -- the title sequence.

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
  SparkX := 205.0;                               { 1118:048a }
  SparkY := 48.0;                                { 1118:049c }

  for X := $140 downto $BE do                    { 1118:04ae }
  begin
    { 1118:04bf -- INLINE, and it appears once per loop. I and J are the
      original's own [BP-4] and [BP-6]. }
    for I := 1 to TitleW do
      for J := 1 to TitleH do
        if (X + I < 320) and (X + I > 0) then
          PutPixel(X + I, J + $28, TitleB[J, I], VGASeg);
    SetRGB(Flick1, Random($40), 0, 0);           { 1118:051f }
    SetRGB(Flick2, Random($40), 0, 0);           { 1118:0532 }
    SetRGB(Flick3, Random($40), 0, 0);           { 1118:0545 }
    { `mod`, NOT `div`, AND THE RUNTIME HELPER'S TAIL PROVES IT. Turbo Pascal
      uses ONE routine for both operators -- RTL $3633 in this part -- and it
      returns the QUOTIENT in DX:AX and the REMAINDER in CX:BX:

          mov  ecx, edx          ; ECX := the remainder
          shld edx, eax, 0x10    ; quotient  -> DX:AX
          shld ebx, ecx, 0x10    ; remainder -> CX:BX

      1118:0563 is MOV AX,CX / MOV DX,BX immediately after the call, so the
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
    V := (Round(X / 20.0) mod 2) * $3C;          { 1118:054b }
    SetRGB(Track, V, 0, 0);                      { 1118:057e }
    Delay(10);                                   { 1118:0585 }
  end;

  for X := $BD downto $AA do                     { 1118:0594 }
  begin
    { 1118:04bf -- INLINE, and it appears once per loop. I and J are the
      original's own [BP-4] and [BP-6]. }
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
    SparkHalf;                         { 1118:0670 }
  end;

  for X := $A9 downto $A0 do                     { 1118:067d }
  begin
    { 1118:04bf -- INLINE, and it appears once per loop. I and J are the
      original's own [BP-4] and [BP-6]. }
    for I := 1 to TitleW do
      for J := 1 to TitleH do
        if (X + I < 320) and (X + I > 0) then
          PutPixel(X + I, J + $28, TitleB[J, I], VGASeg);
    SetRGB(Flick1, 0, 0, Random($40));           { 1118:06ee }
    SetRGB(Flick2, 0, 0, Random($40));
    SetRGB(Flick3, 0, 0, Random($40));
    V := (Round(X / 40.0) mod 2) * $3C;          { 1118:071a }
    SetRGB(Track, V, 0, 0);
    Delay(5);                                    { 1118:0754 }
    SparkSlow;                         { 1118:0759 }
  end;

  for X := $9F downto -$1E do                    { 1118:0766 }
  begin
    { 1118:04bf -- INLINE, and it appears once per loop. I and J are the
      original's own [BP-4] and [BP-6]. }
    for I := 1 to TitleW do
      for J := 1 to TitleH do
        if (X + I < 320) and (X + I > 0) then
          PutPixel(X + I, J + $28, TitleB[J, I], VGASeg);
    SetRGB(Flick1, 0, 0, Random($40));
    SetRGB(Flick2, 0, 0, Random($40));
    SetRGB(Flick3, 0, 0, Random($40));
    V := (Round(X / 40.0) mod 2) * $3C;
    SetRGB(Track, V, 0, 0);
    SparkSlow;                         { 1118:083b }
  end;

  for I := 1 to $1F4 do                          { 1118:0847 }
  begin
    SparkSlow;                         { 1118:0851 }
    Delay(2);                                    { 1118:0856 }
  end;

  SetRGB(0, $3F, $3F, $3F);                      { 1118:086a -- white }
  Delay($64);                                    { 1118:0871 }
  for I := $3F downto 0 do                       { 1118:0876 }
  begin
    SetRGB(0, I, I, I);                          { 1118:088e }
    Delay(2);                                    { 1118:0895 }
  end;
end;

{ --------------------------------------------------------------------------
  1118:08a2 -- push the picture down the screen, black above it.
  HAND ASSEMBLER, verbatim.
  -------------------------------------------------------------------------- }
{ @asm 006 1118:08a2 +37 ScrollOut }
procedure ScrollOut(SrcSeg, DstSeg : Word; Down : Word); assembler;
asm
  PUSH DS                { 1118:08a5                                         }
  MOV  AX, DstSeg        { 1118:08a6                                         }
  MOV  ES, AX            { 1118:08a9                                         }
  MOV  AX, SrcSeg        { 1118:08ab                                         }
  MOV  DS, AX            { 1118:08ae                                         }
  XOR  SI, SI            { 1118:08b0                                         }
  XOR  DI, DI            { 1118:08b2                                         }
  MOV  BX, Down          { 1118:08b4                                         }
  XOR  AX, AX            { 1118:08b7                                         }
  MOV  CX, BX            { 1118:08b9                                         }
  REP  STOSB             { 1118:08bb  black down to the new top              }
  MOV  CX, 0FA00h       { 1118:08bd  64000                                   }
  SUB  CX, BX            { 1118:08c0                                         }
  REP  MOVSB             { 1118:08c2  and the picture below it               }
  POP  DS                { 1118:08c4                                         }
end;

{ --------------------------------------------------------------------------
  1118:08d3 -- the fire.

  The diffusion is HAND ASSEMBLER and the equivalent Pascal is below it. Note
  the average is taken over the cell itself, its two SIDE neighbours and the
  one BELOW -- and written one row ABOVE, which is what makes the flames climb.
  -------------------------------------------------------------------------- }
procedure Run(Segment : Word);
var
  { FOUR DECLARATIONS AND AN x87 TEMPORARY, in ten bytes. 1118:08d3 touches
    [BP-$02] four times, [BP-$04] twice, [BP-$05] once, [BP-$07] five times and
    [BP-$08] once -- and the last of those is `MOV AH,[BP-$08] / SAHF` at
    1118:091E, which is the high half of an FPU status word the compiler stored
    at [BP-$09]. So the declarations run $02, $04, $05, $07 and the two bytes
    below them are the code generator's.

    [BP-$05] is written once, with a zero, at 1118:08DC and never read again --
    so the source assigns it and the value goes nowhere. Frame is initialised
    first and it second, which is the order below. }
  I     : Integer;                { [BP-$02] }
  Tmp   : Integer;                { [BP-$04] }
  Unread : Byte;                  { [BP-$05], assigned 0 and never read }
  Frame : Integer;                { [BP-$07] }
begin
  Frame  := 0;
  Unread := 0;                                   { 1118:08DC }
  Overlay(Segment);                              { 1118:08e3 }
  CopyScreen(Segment, VGASeg);                   { 1118:08ec }
  Title;                                         { 1118:08f1 }
  if KeyPressed then Exit;                       { 1118:08f4 }

  repeat
    { 1118:0907 -- reseed the bottom row. Random is the REAL one here, and
      the threshold is the extended 0.4 at CS:$08c9. }
    { TWO DEFECTS HERE AND TOGETHER THEY ARE WHY THE FIRE DID NOT CLIMB AS
      HIGH as the original's -- reported from a watched run beside ORIG6 on
      25 Aug 2026, and found from the bytes afterwards.

      THE TEST IS `<`, NOT `>`. The original emits JBE at 1118:0922 where
      ours emitted JAE over the same FCOMPP, so the branch senses are
      opposite.

      AND THE STORE IS UNCONDITIONAL. 1118:0932 is the jump's OWN TARGET,
      and it reads the value back out of [BP-$04] and writes it to
      Grid[99,I] on EVERY column -- only the VALUE is conditional. So the
      seed is STICKY: the bottom row is written all the way across every
      frame, carrying the last drawn value into the columns the test skips,
      instead of leaving 60% of them at whatever the diffusion cooled them
      to. That is a much hotter bottom row, and a taller fire.

      Tmp is [BP-$04] and was already declared for this and unused. It is
      never initialised before the loop, so the first columns of the first
      frame carry whatever the frame held -- that is the original's
      behaviour and it is transcribed, not corrected.

      1118:0938 writes [$92A9+I], and $740A + 98*80 + I - 1 is $92A9 + I,
      which is row 99. }
    for I := 1 to GridW do
    begin
      if Random < 0.4 then                       { 1118:0922, JBE }
        Tmp := Random(2) * 255;                  { 1118:0926 -> [BP-$04] }
      Grid[99, I] := Tmp;                        { 1118:0932, EVERY column }
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
      MOV  AX, Segment       { 1118:0942                                     }
      MOV  ES, AX            { 1118:0945                                     }
      XOR  DI, DI            { 1118:0947                                     }
      MOV  AX, OFFSET Grid   { 1118:0949  the binary has $740A, which is    }
      ADD  AX, 51h           {   Grid + 81 -- element [1,1]                  }
      MOV  SI, AX            { 1118:094c                                     }
      ADD  SI, 50h           { 1118:094e  and on to row 2                    }
      MOV  DX, 0             { 1118:0951  the column within the screen row   }
      MOV  BX, 1EA0h         { 1118:0954  7840 cells                         }
      XOR  AX, AX            { 1118:0957  ONCE, outside the loop             }
    @@Cell:
      MOV  AL, [SI]          { 1118:0959  <- 1118:099f comes back HERE, so   }
                             {   AH is NOT cleared per cell. The four ADC    }
                             {   AH,0 below therefore carry across cells and }
                             {   SHR AX,2 shifts some of that back into AL.  }
                             {   Clearing AX inside the loop puts the fire   }
                             {   out.                                        }
      ADD  AL, [SI-1]        { 1118:095b  the one to the left                }
      ADC  AH, 0             { 1118:095e                                     }
      ADD  AL, [SI+1]        { 1118:0961  and to the right                   }
      ADC  AH, 0             { 1118:0964                                     }
      ADD  AL, [SI+50h]      { 1118:0967  and the one BELOW                  }
      ADC  AH, 0             { 1118:096a                                     }
      SHR  AX, 2             { 1118:096d  the average                        }
      JZ   @@Zero            { 1118:0970                                     }
      DEC  AX                { 1118:0972  cool it by one                     }
    @@Zero:
      MOV  [SI-50h], AL      { 1118:0973  written one row UP                 }
      CMP  DI, 0ED80h        { 1118:0976  past row 190: stop drawing         }
      JNC  @@Next            { 1118:097a                                     }
      MOV  CX, 4             { 1118:097c                                     }
      REP  STOSB             { 1118:097f  four across...                     }
      ADD  DI, 13Ch          { 1118:0981                                     }
      MOV  CX, 4             { 1118:0985                                     }
      REP  STOSB             { 1118:0988    ...on two rows                   }
      SUB  DI, 140h          { 1118:098a                                     }
      ADD  DX, 4             { 1118:098e                                     }
      CMP  DX, 140h          { 1118:0991                                     }
      JNZ  @@Next            { 1118:0995                                     }
      ADD  DI, 140h          { 1118:0997  end of the screen row: drop two    }
      XOR  DX, DX            { 1118:099b                                     }
    @@Next:
      INC  SI                { 1118:099d                                     }
      DEC  BX                { 1118:099e                                     }
      JNZ  @@Cell            { 1118:099f                                     }
    end;

    Overlay(Segment);                            { 1118:09a4 }
    Inc(Frame);                                  { 1118:09a7 }
    if Frame < HoldTill then                     { 1118:09aa }
      CopyScreen(Segment, VGASeg)                { 1118:09b6 }
    else
      ScrollOut(Segment, VGASeg,                 { 1118:09ce }
                (Frame - HoldTill) * 320);
  until Frame = Frames;                          { 1118:09d1 }
end;

{ 1118:09df -- the scene. }
procedure Scene3;
begin
  ClearScreen(VirtScrSeg, 0);                    { 1118:09e8 }
  ClearScreen(VGASeg, 0);                        { 1118:09f2 }
  Setup;                                         { 1118:09f7 }
  Run(VirtScrSeg);                               { 1118:09fe }
  FreeMem(Pic, PicSize);                         { 1118:0a0c }
  ClearScreen(VirtScrSeg, 0);                    { 1118:0a17 }
  ClearScreen(VGASeg, 0);                        { 1118:0a21 }
end;

{ 1118:0a28 -- the unit's initialisation is empty. }
begin
end.
