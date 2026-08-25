{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.005 scene 2, segment 1096.

  A rotozoomer, and in front of it a scatter-and-reassemble: the rotozoomed
  frame is picked apart into up to 1,500 single pixels, each of which flies in
  from a random point on the screen and lands where it belongs, over 25 steps.
  That happens eight times, and only then does the rotozoomer start turning.

  THE ROTOZOOM ITSELF IS SIX INSTRUCTIONS OF ADDRESSING. The texture is 256
  wide, so the texture offset is just the two HIGH bytes of the two 8.8
  fixed-point coordinates stuck together -- MOV AH,DH / MOV AL,BH / MOV SI,AX.
  No shifts, no masks, no multiply.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/26-part5-notes.md for the reading.

  ADDRESS MAP
    RotozoomFrame   1096:0000     Demo_Scene2     1096:03d7
    Shatter         1096:0042     (unit init)     1096:06b8

  DGROUP
    DS:$63c8  a loop counter        DS:$63ca  another   DS:$63cc  another
    DS:$63ce  the 64K texture, a Pointer
    DS:$63d2  TabSin  : array[0..2000] of Integer
    DS:$7374  TabCos  : array[0..2000] of Integer
    DS:$8316  TabU    : array[0..2000] of Integer
    DS:$92b8  TabV    : array[0..2000] of Integer
    DS:$a25a  the 768-byte palette buffer
    DS:$a5da  Speed   DS:$a5dc  Index   DS:$a5e0  Key   DS:$a5e1  the file
  =========================================================================== }

{$S-}   { 1096:0042 opens ENTER $26,0 with no stack check, the same as scene 1
          and unlike this part's copy of FixMath. }

{$G+}   { 286, AND THE EVIDENCE WAS ALREADY IN THE LINE ABOVE. `ENTER` is a
          286 instruction and Turbo Pascal emits it only under $G+; without it
          a framed routine opens PUSH BP / MOV BP,SP / SUB SP,n. Both framed
          routines in this segment open ENTER -- $26,0 at 1096:0042 and $04,0
          at 1096:03d7 -- so the original was compiled $G+ and this unit was
          not. The switch had been added to eight other units on exactly this
          evidence and this one was missed, while its own comment quoted the
          instruction that proves it. }

unit P5S2;

{$N+}   { FIRST, SO NOBODY HAS TO REDISCOVER IT: THERE IS NOT ONE RAW 80x87
          OPCODE IN THE SHIPPED 1994 BINARY, AND THAT IS NOT AN ARGUMENT
          AGAINST $N+. Under $E+ every 80x87 instruction ships with its
          two-byte WAIT ESC prefix overwritten by a two-byte INT 34h..3Dh, so
          what is IN the file is traps. The author had no coprocessor and
          Turbo Pascal's emulator executed every one of them in 1994. Ours
          ships and runs them exactly the same way; $E+ was never touched.

          WHY $N+ IS HERE ANYWAY: THE ORIGINAL WAS COMPILED THAT WAY, and the
          traps are the proof rather than the objection. $N- emits no 80x87
          instructions at all, so it produces NO TRAPS EITHER -- floating
          point becomes far calls into the software six-byte-Real library and
          there is nothing for an emulator to emulate. A trap can only exist
          if an 80x87 instruction was emitted, so 12 traps in this loop mean
          $N+. It is a fidelity choice: it would still be the right switch if
          the rebuild ran no quicker, and it would still be right if the
          rebuild ran SLOWER.

          MEASURED, 24 Aug 2026, and this is the check that does not depend on
          anyone reading a trap correctly: building this unit $N- and walking
          every byte of part 005 against the 1994 file drops the alignment
          from 80.4% to 79.2%, 137 bytes FURTHER from the original. Had the
          original been $N-, that number would have moved the other way.

          THE MOTION TABLE, 1096:051a..0591 -- the loop body, entered by the
          JMP at 1096:0514. FILD the index, FDIV by a SINGLE 180.0 at CS:$03c9,
          FLD the ten-byte EXTENDED Pi at CS:$03cd, and the $N+ RTL's Sin
          (CS:$32ad), Cos (CS:$32b2) and Round on the stack top. It carries
          TWELVE traps; the fourteen an earlier note put "at 1096:051a" is the
          count for the whole of Demo_Scene2, 1096:03d7..06b7, and the number
          was right with the wrong extent attached to it.

          The counter at DS:$63ca runs 0 to 2000 inclusive -- 1096:050f seeds
          it, 1096:0592 tests against $7D0 -- so the loop turns 2001 times and
          makes 4,002 trig calls, two a turn. An earlier note said 3,424; that
          figure is not reproducible from this loop and has been dropped.

          Under the $N- default those same 4,002 calls go through the software
          six-byte-Real RTL instead. Two watched runs bracket the switch with
          nothing else in the unit moving between them: the pause was there on
          21 Aug 2026 and gone on 24 Aug. WHY it is gone is NOT MEASURED. It
          is certainly not that anything acquired a coprocessor -- neither
          build has one and both run the emulator over the same traps -- so
          any account of the speed is about two different pieces of SOFTWARE
          doing floating point, and nobody has timed them.

          $N SAYS WHICH CODE IS EMITTED. $E SAYS HOW IT SHIPS. Conflating them
          is a mistake this project has now made three times, the third time
          inside a corrected account of the first two. See
          docs/23-deviations.md, `NOT a deviation: the x87 emulator traps`. }

interface

procedure Scene2;

implementation

uses Crt, VGA;

const
  TabTop    = 2000;               { 1096:0592 counts to $7D0 }
  MaxDots   = 1500;               { 1096:00f9 compares against $5DC }
  DotSteps  = 25;                 { 1096:006f, the interpolation denominator }
  Passes    = 8;                  { 1096:038d }
  TexWide   = 256;                { the texture is 256 across -- see the blit }
  TexRows   = 200;                { 1096:04ee copies 200 rows out of the image }
  TexSize   = $FFFF;              { 1096:0485 asks GetMem for exactly this }
  RotoRows  = 195;                { 1096:0037 compares against $C3 }
  DataOfs   = $001549E5;          { 1096:03fb pushes $0015 then $49E5 }
  StartIdx  = $10E;               { 270 -- 1096:060f }
  Speed0    = $0A;                { 1096:0609 }
  EndIdx    = $7BC;               { 1980 -- 1096:068a }

type
  { Ten bytes, and the field offsets are read off 1096:010f onwards. The
    original indexes it one-based: DI is Count*10 and every field is reached
    at DI-10 through DI-1. }
  TDot = record
    Age  : Byte;                  { +0 -- also the interpolation step }
    Col  : Byte;                  { +1 }
    FromX, ToX : Integer;         { +2, +4 }
    FromY, ToY : Integer;         { +6, +8 }
  end;
  TDots   = array[1..MaxDots] of TDot;
  TTab    = array[0..TabTop] of Integer;
  TPal768 = array[0..767] of Byte;

var
  I1, I2, I3 : Integer;           { DS:$63c8, $63ca, $63cc }
  Texture    : Pointer;           { DS:$63ce }
  TabSin     : TTab;              { DS:$63d2 }
  TabCos     : TTab;              { DS:$7374 }
  TabU       : TTab;              { DS:$8316 }
  TabV       : TTab;              { DS:$92b8 }
  Pal        : TPal768;           { DS:$a25a }
  Speed      : Integer;           { DS:$a5da }
  Index      : Integer;           { DS:$a5dc }
  Key        : Char;              { DS:$a5e0 }
  F          : file;              { DS:$a5e1 }

{ --------------------------------------------------------------------------
  1096:0000 -- one rotozoomed frame. HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Ofs := 0;
      for Row := 0 to 194 do
      begin
        V := V0;  U := U0;
        for Col := 0 to 319 do
        begin
          V := V + dV;   U := U + dU;
          Mem[VirtScrSeg : Ofs] := Tex^[Hi(V) * 256 + Hi(U)];
          Inc(Ofs);
        end;
        V0 := V0 - dU;   U0 := U0 + dV;      -- the incremental rotation
      end;

  It cannot be written that way and be the same code. `Hi(V) * 256 + Hi(U)` is
  not a multiply in the original, it is MOV AH,DH / MOV AL,BH -- the two high
  bytes assembled into one register -- and the copy is a MOVSB with DS already
  pointing at the texture, so the texture is addressed with no arithmetic at
  all. V0 and U0 are updated IN THE CALLER'S FRAME, which Pascal would need
  var parameters for.
  -------------------------------------------------------------------------- }
{ @asm 005 1096:0000 +64 RotozoomFrame }
procedure RotozoomFrame(V0, U0, dV, dU : Integer; Tex : Pointer); assembler;
asm
  PUSH DS                { 1096:0003  DS is about to be the texture          }
  MOV  AX, VirtScrSeg    { 1096:0004                                         }
  MOV  ES, AX            { 1096:0007  ES:DI walks the whole screen once      }
  XOR  DI, DI            { 1096:0009    and is never reset per row           }
  XOR  CX, CX            { 1096:000b  CX counts rows                         }
  LDS  SI, Tex           { 1096:000d  only DS matters -- SI is overwritten   }
@Row:
  PUSH CX                { 1096:0010  CX is the pixel count below            }
  MOV  CX, 140h          { 1096:0011  320 across                             }
  MOV  DX, V0            { 1096:0014  DX is the texture ROW, 8.8 fixed       }
  MOV  BX, U0            { 1096:0017  BX is the texture COLUMN               }
@Pixel:
  ADD  DX, dV            { 1096:001a                                         }
  MOV  AH, DH            { 1096:001d  the row's whole part -> the high byte  }
  ADD  BX, dU            { 1096:001f                                         }
  MOV  AL, BH            { 1096:0022  the column's -> the low byte           }
  MOV  SI, AX            { 1096:0024  and that IS the texture offset         }
  MOVSB                  { 1096:0026  ES:[DI] <- DS:[SI], DI walks on        }
  LOOP @Pixel            { 1096:0027                                         }
  POP  CX                { 1096:0029                                         }
  MOV  AX, dU            { 1096:002a                                         }
  SUB  V0, AX            { 1096:002d  rotate the row start by one step...    }
  MOV  AX, dV            { 1096:0030                                         }
  ADD  U0, AX            { 1096:0033    ...perpendicular to itself           }
  INC  CX                { 1096:0036                                         }
  CMP  CX, 0C3h          { 1096:0037  195 rows, not 200                      }
  JNZ  @Row              { 1096:003b                                         }
  POP  DS                { 1096:003d                                         }
end;

{ --------------------------------------------------------------------------
  1096:0042 -- shatter the rotozoomed frame and put it back together, eight
  times over.

  Each pass draws one rotozoom frame into the virtual screen, walks it from
  the BOTTOM LEFT upwards collecting every non-black pixel as a dot with a
  random starting point, blanks the virtual screen, and then runs 25 steps of
  linear interpolation. Each step erases the previous position by copying
  whatever the (now blank) virtual screen has there, and draws the dot's own
  colour at the new one.

  It stops collecting at 1,500 dots, so on a busy frame only the bottom of the
  picture takes part.
  -------------------------------------------------------------------------- }
procedure Shatter;
var
  Work    : Pointer;              { [BP-$21] -- a second 64,000-byte screen }
  WorkSeg : Word;                 { [BP-$23] }
  Dots    : ^TDots;               { [BP-$0e] }
  Count   : Integer;              { [BP-2]  }
  X, Y    : Integer;              { [BP-4], [BP-6] }
  I       : Integer;              { [BP-8]  }
  Step    : Integer;              { [BP-$0a] }
  X0, X1  : Integer;              { [BP-$10], [BP-$12] }
  Y0, Y1  : Integer;              { [BP-$14], [BP-$16] }
  Col     : Byte;                 { [BP-$17] }
  Denom   : Integer;              { [BP-$19] }
  T       : Integer;              { [BP-$1b] }
  Pass    : Integer;              { [BP-$1d] }
  Limit   : Integer;              { [BP-$25] }
begin
  GetMem(Work, 64000);                           { 1096:0046 }
  WorkSeg := Seg(Work^);                         { 1096:0054 }
  GetMem(Dots, MaxDots * SizeOf(TDot));          { 1096:005c -- $3A98 = 15000 }

  Count := 0;                                    { 1096:006a }
  Denom := DotSteps;                             { 1096:006f }
  X := 0;                                        { 1096:0074 }
  Y := 199;                                      { 1096:0079 }
  ClearScreen(VirtScrSeg, 0);                    { 1096:007e }
  ClearScreen(WorkSeg, 0);                       { 1096:0089 }

  for Pass := 1 to Passes do
  begin
    Count := 0;                                  { 1096:009d }
    { 1096:00a2 -- one frame of the rotozoomer, at the index the scene left
      set. Nothing here advances it, so all eight passes shatter the SAME
      picture. }
    RotozoomFrame(TabV[Index + 1] + $59D8, TabU[Index + 1] + $4E20,
                  TabSin[Index + 1], TabCos[Index], Texture);

    { 1096:00e3 -- collect. The scan runs left to right along a row and then
      UPWARDS, starting at the bottom left.

      A BLACK PIXEL IS SKIPPED, NOT AN END. 1096:00f4 is JNZ to the recording
      code and 1096:00f6 is a JMP straight to the Inc(X) at 1096:0180, so the
      scan carries on regardless. Reading that as `while GetPixel <> 0` stops
      the whole thing dead on the first pixel, because RotozoomFrame only
      draws 195 rows and the scan starts on row 199, which is blank.

      X and Y are NOT reset per pass -- they are set once at 1096:0074 before
      the pass loop -- so a later pass carries on from where the last one ran
      out of dots. }
    while True do
    begin
      if GetPixel(X, Y, VirtScrSeg) <> 0 then    { 1096:00ed }
        if Count < MaxDots then                  { 1096:00f9 }
        begin
          Inc(Count);                            { 1096:0103 }
          Dots^[Count].Age   := 1;               { 1096:010f }
          Dots^[Count].Col   := GetPixel(X, Y, VirtScrSeg);   { 1096:012e }
          Dots^[Count].ToX   := X;               { 1096:013e }
          Dots^[Count].ToY   := Y;               { 1096:014e }
          Dots^[Count].FromX := Random(320);     { 1096:0165 }
          Dots^[Count].FromY := Random(200);     { 1096:017c }
        end;

      Inc(X);                                    { 1096:0180 }
      if (Count = MaxDots) or (X > 319) then     { 1096:0187, 1096:018e }
      begin
        if X > 319 then                          { 1096:0198 }
        begin
          X := 0;                                { 1096:019f }
          Dec(Y);                                { 1096:01a7 }
        end;
        if (Count = MaxDots) or (Y < 1) then Break;   { 1096:01ab, 01b2 }
      end;
    end;

    { 1096:01bb -- the work screen is still black, so this blanks the virtual
      screen. From here on the dots have a black background to erase to. }
    CopyScreen(WorkSeg, VirtScrSeg);

    for Step := 1 to DotSteps do
    begin
      { 1096:01d1 -- erase: put back whatever the background has at the
        position the dot occupied on the PREVIOUS step. }
      Limit := Count;
      for I := 1 to Limit do
      begin
        T  := Dots^[I].Age - 1;                  { 1096:01f9 }
        X1 := Dots^[I].ToX;                      { 1096:0206 }
        X0 := Dots^[I].FromX;                    { 1096:0216 }
        Y1 := Dots^[I].ToY;                      { 1096:0226 }
        Y0 := Dots^[I].FromY;                    { 1096:0236 }
        X0 := (X1 - X0) * T div Denom + X0;      { 1096:023d }
        Y0 := (Y1 - Y0) * T div Denom + Y0;      { 1096:0250 }
        Col := GetPixel(X0, Y0, VirtScrSeg);     { 1096:026d }
        Mem[WorkSeg : YOfs[Y0] + X0] := Col;     { 1096:0289 }
      end;

      { 1096:0297 -- draw: the dot's own colour at the NEW position, and only
        then is Age stepped. }
      Limit := Count;
      for I := 1 to Limit do
      begin
        T  := Dots^[I].Age;                      { 1096:02b9 -- no -1 here }
        X1 := Dots^[I].ToX;                      { 1096:02cb }
        X0 := Dots^[I].FromX;                    { 1096:02db }
        Y1 := Dots^[I].ToY;                      { 1096:02eb }
        Y0 := Dots^[I].FromY;                    { 1096:02fb }
        Dots^[I].Age := Dots^[I].Age + 1;        { 1096:031d }
        Col := Dots^[I].Col;                     { 1096:032a }
        X0 := (X1 - X0) * T div Denom + X0;      { 1096:0331 }
        Y0 := (Y1 - Y0) * T div Denom + Y0;      { 1096:0344 }
        Mem[WorkSeg : YOfs[Y0] + X0] := Col;     { 1096:036b }
      end;

      CopyScreen(WorkSeg, $A000);                { 1096:0379 }
    end;
  end;

  Delay($384);                                   { 1096:0396 -- 900 }
  FreeMem(Dots, MaxDots * SizeOf(TDot));         { 1096:03a7 }
  FreeMem(Work, 64000);                          { 1096:03b5 }
end;

{ --------------------------------------------------------------------------
  1096:03d7 -- the scene.

  ASSETS  NEUROSIS.DAT $001549E5:
            768 bytes    the palette
            64,000 bytes a 320 x 200 picture, of which a 256-wide window
                         starting four pixels in becomes the texture

  The two tables at 1096:051a are the whole of the motion. Every entry is
  Round(I * Sin(...)) rather than plain Sin -- the amplitude grows with the
  index -- so as the index runs from 270 to 1980 the rotozoom spirals outwards
  as well as turning.
  -------------------------------------------------------------------------- }
procedure Scene2;
{ NO LOCALS. Every counter in this routine is one of the unit's own globals --
  the palette loop runs on I1 at DS:$63C8, exactly as the two below it run on
  I2 and I3. It was the only loop here still using a local, and a local shifts
  the frame that the rest of the routine's references are measured against. }
begin
  Assign(F, 'neurosis.dat');                     { 1096:03e5 }
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Pal, SizeOf(Pal));                { 1096:0416 }
  for I1 := 0 to 255 do                          { 1096:041b -- DS:$63C8 }
    SetRGB(I1, Pal[I1 * 3], Pal[I1 * 3 + 1], Pal[I1 * 3 + 2]);
  BlockRead(F, VirtScr^, 64000);                 { 1096:0476 }
  Close(F);                                      { 1096:0480 }

  GetMem(Texture, TexSize);                      { 1096:0487 -- $FFFF }
  { 1096:049d -- FillChar with a count of ZERO. It does nothing at all, and it
    is transcribed because it is there; the intent was presumably 65536, which
    does not fit in the Word the count is. }
  FillChar(Texture^, 0, 0);

  { 1096:04a2 -- lift a 256-wide window out of the picture, four pixels in. }
  for I2 := 0 to 199 do
    for I3 := 0 to 255 do
      Mem[Seg(Texture^) : (I2 shl 8) + I3] :=
        Mem[VirtScrSeg : I2 * 320 + 4 + I3];

  { 1096:04f6 -- and blank the 56 rows past the bottom of it, so a texture
    coordinate that runs off the picture reads black rather than rubbish. }
  FillChar(Mem[Seg(Texture^) : TexRows * TexWide], $3800, 0);

  { 1096:051a -- the motion tables. The angle is in DEGREES: the divisor at
    CS:$03c9 is the single 180.0 and the multiplicand at CS:$03cd is the
    ten-byte extended Pi. }
  for I2 := 0 to TabTop do
  begin
    TabSin[I2] := Round(I2 * Sin((I2 + 270) / 180.0 * Pi));
    TabCos[I2] := Round(I2 * Cos((I2 + 270) / 180.0 * Pi));
  end;

  { 1096:059d -- and the two scaled, negated copies the frame routine uses. }
  for I2 := 0 to TabTop do
  begin
    TabU[I2] := -Round(TabSin[I2] * 100);        { 1096:05ae }
    TabV[I2] := -Round(TabCos[I2] * 160);        { 1096:05da }
  end;

  Speed := Speed0;                               { 1096:0609 }
  Index := StartIdx;                             { 1096:060f }
  Shatter;                                       { 1096:0615 }

  Key := #0;                                     { 1096:0618 }
  repeat
    Index := Index + Speed;                      { 1096:061d }
    { 1096:0627 -- note this differs from Shatter's call: the U term is taken
      at Index rather than Index+1, and the bias is $3E80 and not $4E20. }
    RotozoomFrame(TabV[Index + 1] + $59D8, TabU[Index] + $3E80,
                  TabSin[Index + 1], TabCos[Index], Texture);
    CopyScreen(VirtScrSeg, $A000);               { 1096:066d }
    if KeyPressed then Key := ReadKey;           { 1096:0672 }
  until (Key <> #0) or (Index >= EndIdx);        { 1096:0683, 1096:068a }

  ClearScreen($A000, 0);                         { 1096:0697 }
  ClearScreen(VirtScrSeg, 0);                    { 1096:06a2 }
  FreeMem(Texture, TexSize);                     { 1096:06b1 }
end;

{ 1096:06b8 -- the unit's initialisation is empty. }
begin
end.
