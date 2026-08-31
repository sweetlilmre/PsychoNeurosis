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
  See docs/26-part5-notes.md for the reading. }

{$S-}   { opens ENTER $26,0 with no stack check, the same as scene 1
          and unlike this part's copy of FixMath. }

{ 286 instructions are permitted -- `ENTER`, which the routine below opens
  with, is one of them. }
{$G+}

unit P5ROTO;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

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
          rebuild ran SLOWER. }

{ DATA ALIGNMENT OFF. With it on, Turbo Pascal pads a variable up to an even
  address, so a one-byte variable followed by a record moves everything after
  it. This unit has exactly that pair, and the original does not pad. }
{$A-}

interface

procedure Scene2;

implementation

uses Crt, VGA;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

const
  TabTop    = 2000;               { counts to $7D0 }
  MaxDots   = 1500;               { compares against $5DC }
  DotSteps  = 25;                 { the interpolation denominator }
  Passes    = 8;
  TexWide   = 256;                { the texture is 256 across -- see the blit }
  TexRows   = 200;                { copies 200 rows out of the image }
  TexSize   = $FFFF;              { asks GetMem for exactly this }
  RotoRows  = 195;                { compares against $C3 }
  DataOfs   = DAT_P5_P5PAL;   { where this scene's assets start }
  StartIdx  = $10E;               { 270, the angle the spiral starts at }
  Speed0    = $0A;
  EndIdx    = $7BC;

type
  { Ten bytes, and the array of these is ONE-based. }
  TDot = record
    Age  : Byte;                  { +0 -- also the interpolation step }
    Col  : Byte;                  { +1 }
    FromX, ToX : Integer;         { +2, +4 }
    FromY, ToY : Integer;         { +6, +8 }
  end;
  TDots   = array[1..MaxDots] of TDot;
  TTab    = array[0..TabTop] of Integer;
  { TWO-DIMENSIONAL, entry by channel, and the upload loop is what says so.
 builds C*3 in DI and then reads the three channels as
    [DI-$5DA6], [DI-$5DA5] and [DI-$5DA4] -- three consecutive displacements
    off ONE index. A flat array[0..767] subscripted Pal[C*3+1] adds the 1 at
    run time and builds the index in AX instead. Same 768 bytes. Part 004's
    scene palette turned out to be the same shape for the same reason. }
  TPal768 = array[0..255, 0..2] of Byte;

var
  I1, I2, I3 : Integer;
  Texture    : Pointer;
  TabSin     : TTab;
  TabCos     : TTab;
  TabU       : TTab;
  TabV       : TTab;
  Pal        : TPal768;
  { 128 BYTES, WHICH IS A FILE RECORD, and it was 98 for as long as
    it was compensating for someone else's error. The span from Pal's end at
    $A55A to Speed at $A5DA is 128 bytes and always was; 98 was what balanced
    scene 3 while scene 1's own dead block was thirty-two bytes too big and this
    whole unit sat thirty-two bytes high. With scene 1 corrected the gap can be
    read straight off the two addresses, and it reads 128.

    THE SIZE IS NOW A DECLARATION RATHER THAN A NUMBER THAT BALANCES, and 128
    is the size of an untyped `file`. That is the seventh place in this target
    where a file record is declared and never opened, so it is very likely what
    this is; the TYPE is still not measurable, because nothing references it,
    and a byte array is what can be claimed. }
  Spare      : array[1..128] of Byte;
  Speed      : Integer;
  Index      : Integer;
  { TWO MORE BYTES NOTHING REFERENCES, and they can be read straight off two
    measured addresses now that the block starts in the right place: Index is a
    word at $A5DC and Key is a byte at $A5E0, so $A5DE and $A5DF are declared
    and untouched. Before the layout was corrected this pair was invisible --
    the whole unit was thirty-two bytes high and every gap in it was being read
    against the wrong baseline. }
  Spare2     : Integer;           { never read }
  Key        : Char;
  F          : file;

{ --------------------------------------------------------------------------
  one rotozoomed frame. HAND ASSEMBLER, verbatim.

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
procedure RotozoomFrame(V0, U0, dV, dU : Integer; Tex : Pointer); assembler;
asm
  PUSH DS                { DS is about to be the texture          }
  MOV  AX, VirtScrSeg
  MOV  ES, AX            { ES:DI walks the whole screen once      }
  XOR  DI, DI            { and is never reset per row           }
  XOR  CX, CX            { CX counts rows                         }
  LDS  SI, Tex           { only DS matters -- SI is overwritten   }
@Row:
  PUSH CX                { CX is the pixel count below            }
  MOV  CX, 140h          { 320 across                             }
  MOV  DX, V0            { DX is the texture ROW, 8.8 fixed       }
  MOV  BX, U0            { BX is the texture COLUMN               }
@Pixel:
  ADD  DX, dV
  MOV  AH, DH            { the row's whole part -> the high byte  }
  ADD  BX, dU
  MOV  AL, BH            { the column's -> the low byte           }
  MOV  SI, AX            { and that IS the texture offset         }
  MOVSB                  { ES:[DI] <- DS:[SI], DI walks on        }
  LOOP @Pixel
  POP  CX
  MOV  AX, dU
  SUB  V0, AX            { rotate the row start by one step...    }
  MOV  AX, dV
  ADD  U0, AX            { ...perpendicular to itself           }
  INC  CX
  CMP  CX, 0C3h          { 195 rows, not 200                      }
  JNZ  @Row
  POP  DS
end;

{ --------------------------------------------------------------------------
  shatter the rotozoomed frame and put it back together, eight
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
  Count          : Integer;
  X              : Integer;
  Y              : Integer;
  I              : Integer;
  Step           : Integer;
  Dots           : ^TDots;
  X0             : Integer;
  X1             : Integer;
  Y0             : Integer;
  Y1             : Integer;
  Col            : Byte;
  Denom          : Integer;
  T              : Integer;
  Pass           : Integer;
  Work           : Pointer;
  WorkSeg        : Word;
  { THERE IS NO `Limit` VARIABLE, deliberately. A `for` loop costs two bytes
    of frame for its limit whatever the limit is, so lifting the bound into a
    variable of its own pays for the variable AND the temporary. }
begin
  GetMem(Work, 64000);
  WorkSeg := Seg(Work^);
  GetMem(Dots, MaxDots * SizeOf(TDot));          { $3A98 = 15000 }

  Count := 0;
  Denom := DotSteps;
  X := 0;
  Y := 199;
  ClearScreen(VirtScrSeg, 0);
  ClearScreen(WorkSeg, 0);

  for Pass := 1 to Passes do
  begin
    Count := 0;
    { one frame of the rotozoomer, at the index the scene left
      set. Nothing here advances it, so all eight passes shatter the SAME
      picture. }
    RotozoomFrame(TabV[Index + 1] + $59D8, TabU[Index + 1] + $4E20,
                  TabSin[Index + 1], TabCos[Index], Texture);

    { collect. The scan runs left to right along a row and then
      UPWARDS, starting at the bottom left.

      A BLACK PIXEL IS SKIPPED, NOT AN END -- the scan carries on regardless.
      Reading it as `while GetPixel <> 0` stops the whole thing dead on the
      first pixel, because only 195 rows are drawn and the scan starts on row
      199, which is blank.

      X and Y are NOT reset per pass. They are set once, before the pass loop,
      so a later pass carries on from where the last one ran out of dots. }
    { A `repeat` NESTED INSIDE THE `while`, and the two back-jumps say so.
 are both JMP $E3 -- two separate jumps to the same
      address -- which is what an inner `repeat` sitting at the top of an outer
      loop's body produces. And the inner `until`'s two tests JUMP FORWARD out
      of the loop when they succeed (JE $198, JG $198) and fall through to the
      back-jump when they do not; a single `if ... then Break` inside one loop
      inverts that, tests JLE and jumps BACK, which is a byte shorter per site
      and is what ours emitted.

      AND THE OUTER LOOP IS A `repeat` TOO, not a `while True` with a `Break`.
      A `Break` emits its exit jump before the back-jump; a `repeat` emits the
      exits first and falls through to the back-jump, and the two nested
      `until`s land on the same address. }
    repeat
     repeat
      if GetPixel(X, Y, VirtScrSeg) <> 0 then
        if Count < MaxDots then
        begin
          Inc(Count);
          Dots^[Count].Age   := 1;
          Dots^[Count].Col   := GetPixel(X, Y, VirtScrSeg);
          Dots^[Count].ToX   := X;
          Dots^[Count].ToY   := Y;
          Dots^[Count].FromX := Random(320);
          Dots^[Count].FromY := Random(200);
        end;

      { ASSIGNMENTS, NOT `Inc` AND `Dec` -- written out through the
        accumulator, where `Inc` increments in place. Six bytes between them
        across the pair, and everything after out of step. See the wiki's
        `Inc is not an assignment`. }
      X := X + 1;
     until (Count = MaxDots) or (X > 319);
      if X > 319 then
      begin
        X := 0;
        Y := Y - 1;
      end;
    until (Count = MaxDots) or (Y < 1);

    { the work screen is still black, so this blanks the virtual
      screen. From here on the dots have a black background to erase to. }
    CopyScreen(WorkSeg, VirtScrSeg);

    for Step := 1 to DotSteps do
    begin
      { erase: put back whatever the background has at the
        position the dot occupied on the PREVIOUS step. }
      for I := 1 to Count do
      begin
        T  := Dots^[I].Age - 1;
        X1 := Dots^[I].ToX;
        X0 := Dots^[I].FromX;
        Y1 := Dots^[I].ToY;
        Y0 := Dots^[I].FromY;
      { ----------------------------------------------------------------------
        THE INTERPOLATION AND THE PIXEL WRITE ARE HAND ASSEMBLER, and no
        spelling of the Pascal reproduces them -- eight were tried across three
        compiler versions.

        and the two LongInt casts call the runtime instead. NOT ONE of the
        twenty-four builds emits the original's

            CWD / IMUL <T> / IDIV <Denom>

        which is the wiki's `instruction-the-compiler-never-emits` exactly: a
        construct no spelling reaches is not a spelling problem.

        AND OURS WAS WRONG, not merely different. MUL leaves the product in
        DX:AX and the CWD that follows overwrites DX with the sign of AX, so the
        product's top half is thrown away before IDIV ever sees it. Any dot
        whose (X1 - X0) * T exceeds 16 bits interpolated from a truncated
        dividend. The original's CWD is dead -- IMUL overwrites DX immediately --
        and it is transcribed because it is what ships.

        THE PIXEL WRITE IS THE SAME STORY IN THE OTHER DIRECTION. `YOfs[Y0]
        + X0` mixes a Word array with a signed Integer, which promotes the
        whole expression to 32 bits -- where the original computes the offset
        in sixteen throughout. }
      asm
              MOV     AX, X1
              SUB     AX, X0
              CWD                             { IMUL rewrites DX }
              IMUL    T                       { 0244  SIGNED, and 32-bit wide  }
              IDIV    Denom
              ADD     AX, X0
              MOV     X0, AX
              MOV     AX, Y1
              SUB     AX, Y0
              CWD
              IMUL    T
              IDIV    Denom
              ADD     AX, Y0
              MOV     Y0, AX
      end;
        Col := GetPixel(X0, Y0, VirtScrSeg);
      asm
              MOV     AX, WorkSeg
              MOV     ES, AX
              MOV     BX, Y0
              ADD     BX, BX                  { 027d  a word index -- ADD      }
              MOV     DI, [BX + OFFSET YOfs]  { 027f  DI := Y0 * 320           }
              ADD     DI, X0                  { 0283    + X0, SIXTEEN bits     }
              MOV     AL, Col
              MOV     ES:[DI], AL
      end;
      end;

      { draw: the dot's own colour at the NEW position, and only
        then is Age stepped. }
      for I := 1 to Count do
      begin
        T  := Dots^[I].Age;                      { no -1 here }
        X1 := Dots^[I].ToX;
        X0 := Dots^[I].FromX;
        Y1 := Dots^[I].ToY;
        Y0 := Dots^[I].FromY;
        Dots^[I].Age := Dots^[I].Age + 1;
        Col := Dots^[I].Col;
      { the same two shapes as the erase loop above, and here they are one
        contiguous block with no call between them. }
      asm
              MOV     AX, X1
              SUB     AX, X0
              CWD
              IMUL    T
              IDIV    Denom
              ADD     AX, X0
              MOV     X0, AX
              MOV     AX, Y1
              SUB     AX, Y0
              CWD
              IMUL    T
              IDIV    Denom
              ADD     AX, Y0
              MOV     Y0, AX
              MOV     AX, WorkSeg
              MOV     ES, AX
              MOV     BX, Y0
              ADD     BX, BX
              MOV     DI, [BX + OFFSET YOfs]
              ADD     DI, X0
              MOV     AL, Col
              MOV     ES:[DI], AL
      end;
      end;

      CopyScreen(WorkSeg, $A000);
    end;
  end;

  Delay($384);                                   { 900 }
  FreeMem(Dots, MaxDots * SizeOf(TDot));
  FreeMem(Work, 64000);
end;

{ --------------------------------------------------------------------------
  the scene.

  ASSETS  NEUROSIS.DAT $001549E5:
            768 bytes    the palette
            64,000 bytes a 320 x 200 picture, of which a 256-wide window
                         starting four pixels in becomes the texture

  The two tables below are the whole of the motion. Every entry is
  Round(I * Sin(...)) rather than plain Sin -- the amplitude grows with the
  index -- so as the index runs from 270 to 1980 the rotozoom spirals outwards
  as well as turning.
  -------------------------------------------------------------------------- }
procedure Scene2;
{ NO LOCALS. Every counter in this routine is one of the unit's own globals,
  including the palette loop's -- a local here would give the routine a frame,
  and every reference below it is measured against that. }
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  BlockRead(F, Pal, SizeOf(Pal));
  for I1 := 0 to 255 do
    SetRGB(I1, Pal[I1, 0], Pal[I1, 1], Pal[I1, 2]);
  BlockRead(F, VirtScr^, 64000);
  Close(F);

  GetMem(Texture, TexSize);                      { $FFFF }
  { FillChar with a count of ZERO. It does nothing at all, and it
    is transcribed because it is there; the intent was presumably 65536, which
    does not fit in the Word the count is. }
  FillChar(Texture^, 0, 0);

  { lift a 256-wide window out of the picture, four pixels in. }
  for I2 := 0 to 199 do
    for I3 := 0 to 255 do
      Mem[Seg(Texture^) : (I2 shl 8) + I3] :=
        Mem[VirtScrSeg : I2 * 320 + 4 + I3];

  { and blank the 56 rows past the bottom of it, so a texture
    coordinate that runs off the picture reads black rather than rubbish. }
  { A `Ptr` CALL, NOT A `Mem` SUBSCRIPT, and the difference is the ORDER the
    two arguments are evaluated in: `Mem[S : O]` takes the segment first, a
    two-argument `Ptr` takes the offset first because a call's arguments go
    right to left. Same address, different code. }
  FillChar(Ptr(Seg(Texture^), TexRows * TexWide)^, $3800, 0);

  { The motion tables. THE ANGLE IS IN DEGREES -- hence the division by 180
    and the multiplication by Pi below, which is where the conversion lives. }
  for I2 := 0 to TabTop do
  begin
    TabSin[I2] := Round(I2 * Sin((I2 + 270) / 180.0 * Pi));
    TabCos[I2] := Round(I2 * Cos((I2 + 270) / 180.0 * Pi));
  end;

  { and the two scaled, negated copies the frame routine uses. }
  for I2 := 0 to TabTop do
  begin
    TabU[I2] := -Round(TabSin[I2] * 100);
    TabV[I2] := -Round(TabCos[I2] * 160);
  end;

  Speed := Speed0;
  Index := StartIdx;
  Shatter;

  Key := #0;
  repeat
    Index := Index + Speed;
    { note this differs from Shatter's call: the U term is taken
      at Index rather than Index+1, and the bias is $3E80 and not $4E20. }
    RotozoomFrame(TabV[Index + 1] + $59D8, TabU[Index] + $3E80,
                  TabSin[Index + 1], TabCos[Index], Texture);
    CopyScreen(VirtScrSeg, $A000);
    if KeyPressed then Key := ReadKey;
  until (Key <> #0) or (Index >= EndIdx);

  ClearScreen($A000, 0);
  ClearScreen(VirtScrSeg, 0);
  FreeMem(Texture, TexSize);
end;

{ the unit's initialisation is empty. }
begin
end.
