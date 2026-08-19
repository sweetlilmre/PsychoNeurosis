{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 7
  Reconstructed from NEUROSIS_003_fpu.exe, segment 125e.

  The closing scene of the part, and the credits roll. It runs in two halves.

  FIRST, one at a time, each of the four members gets an introduction
  (Sprites_Prepare, once per portrait, three phases each):

    1. FLY-IN     the 56x56 portrait spins in from off-screen left while the
                  palette fades up from black over the same frames.
    2. ORBIT      181 frames of a full circle, radius 60, about (140, 100),
                  still spinning.
    3. TYPEWRITER ten lines of fifty characters, one character every 10 ms,
                  drawn with a 5x5 bitmap font -- name, codename, occupation
                  and tasks. Then a fade to black.

  THEN all four portraits together (Sprites_Run): random start angles, a fade
  up from black, and a 141-frame sweep down the screen with the four spread
  across it 70 pixels apart.

  Two things drive every frame:

    Trig[a]    = (Round(sin(a) * 64), Round(cos(a) * 64))
                 6-bit fixed point -- the rotation step for DrawRotated.
    Wobble[a]  = (Round(sin(a+225) * 39.6), Round(cos(a+225) * 39.6))
                 a +-40 pixel circular wobble added to every position, so
                 nothing ever travels in a straight line.

  Both are built once in Sprites_Load and never recomputed; the frame path
  has no floating point in it at all.

  ADDRESS MAP
    Demo_Scene7         125e:0958    Sprites_Load       125e:012e
    Sprites_Run         125e:077c    Sprites_Prepare    125e:0550
    Sprite_DrawRotated  125e:0388    Sprites_FadeStep   125e:047a
    Sprites_FadeOut     125e:0406    Sprites_DrawChar   125e:0000
    DegToRad (in Load)  125e:00d3    DegToRad (Prepare) 125e:0510
  =========================================================================== }

{$G+}   { 286 instructions: 125e:0390 is SHL AX,6 and 125e:03c8 is SHR DI,6.
          A shift by an immediate other than 1 is a 286 encoding, so the
          rotate-and-sample below will not assemble without this. }

unit Part3Sprites;

interface

procedure Scene7;

implementation

uses VGA, Crt;

{$I gen/P3CAPT.INC}      { const Captions : array[1..40] of String[50] }

const
  DataOfs    = $11EEC0;      { NEUROSIS.DAT -- 1,175,232 }

  { The 5x5 bitmap font. 1,550 bytes = 62 glyphs of 25, covering Ord 32..93,
    which is everything from space to ']' -- space through uppercase Z is all
    the captions ever use. Each byte is 0 or $AB; the typewriter tests it
    against zero and plots colour 50. }
  FontFirst  = 32;
  FontLast   = 93;
  FontCell   = 5;
  FontSize   = (FontLast - FontFirst + 1) * FontCell * FontCell;   { 1550 }

  SpriteW    = 56;
  SpriteH    = 56;
  SpriteSize = SpriteW * SpriteH;   { $C40 = 3136 }
  NumSprites = 4;

  FixedBits  = 6;            { positions are kept << 6 -- 125e:0390 }
  AngleWrap  = 360;          { $168 }
  SpinStep   = 5;            { degrees per frame }
  SwapAngle  = 180;          { $B4 -- above this the byte pair is written
                               the other way round; see DrawRotated }

  TrigScale  = 64.0;         { CS:$011C -- 6-bit fixed point }
  WobbleScale = 39.6;        { CS:$0120 -- the wobble amplitude, +-40 px }
  WobbleBias = 65535.0;      { CS:$012A -- see the note in Load }
  WobblePhase = 225;         { $E1 -- the wobble table is read 225 deg on }

  { Sprites_Prepare, phase 1 -- the fly-in }
  StartAngle = 350;          { $15E }
  FlyFrom    = -20;          { $FFEC }
  FlyTo      = 70;           { $46 }
  FlyY       = 160;          { $A0 -- fixed for the whole fly-in }

  { Sprites_Prepare, phase 2 -- the orbit }
  OrbitFrames = 180;         { $B4, so 181 frames of 2 degrees = one turn }
  OrbitRadius = 60.0;        { CS:$054C }
  OrbitCX    = 140;          { $8C }
  OrbitCY    = 100;          { $64 }

  { Sprites_Prepare, phase 3 -- the typewriter }
  CaptionRows = 10;
  CaptionCols = 50;          { $32 }
  CharGap    = 6;            { both the cell pitch and the pen advance }
  CharColour = 50;           { $32 -- 125e:0097 }
  PreDelay   = 1000;         { $3E8 }
  TypeDelay  = 10;           { $A per character }
  PostDelay  = 2000;         { $7D0 }

  { Sprites_Run -- the four together }
  FadeSteps  = 64;           { $40 }
  SweepFrom  = -20;          { $FFEC }
  SweepTo    = 120;          { $78 -- Y runs SweepFrom*2 .. SweepTo*2 }
  BaseX      = 50;           { $32 -- the leftmost portrait }
  HSpacing   = 70;           { $46 -- 125e:0838, 0885, 08d2 give 70/140/210 }

type
  TSprite = array[0..SpriteSize - 1] of Byte;
  TTrig   = record S, C : Integer end;

var
  { DS:$D28C -- four heap blocks of 3,136 bytes. GetMem normalises, so each
    pointer has offset 0, which is what lets DrawRotated throw the offset
    away and keep only the segment. }
  Sprite : array[1..NumSprites] of ^TSprite;

  { DS:$D29C, 360 x 4 bytes. sin at +0, cos at +2, both x 64. }
  Trig   : array[0..AngleWrap - 1] of TTrig;

  { DS:$D83C, 360 x 4 bytes, immediately after Trig. X at +0, Y at +2. }
  Wobble : array[0..AngleWrap - 1] of record X, Y : Integer end;

  { DS:$DDDE -- the 5x5 font, read straight off the DAT. The compiler folds
    the lower bounds into the base, which is why the binary addresses it as
    [DI + $DAB8] with DI = Ord(Ch)*25 + Row*5 + Col:
        $DDDE - (32*25 + 1*5 + 1) = $DAB8. }
  Font   : array[FontFirst..FontLast, 1..FontCell, 1..FontCell] of Byte;

  { DS:$DDDC -- one loop counter shared by Load, Run and Scene7. It really is
    a global in the original, not a local in each. }
  GI     : Integer;

  { DS:$E3EC -- the palette the scene fades UP to, read from the DAT. This is
    the scene's own buffer, not VGA.Palette: 125e:0347 (the BlockRead) and
    125e:04b1 (FadeStep's compare) are its only two references in the whole
    part. }
  TargetPal : array[0..255, 0..2] of Byte;

{ --------------------------------------------------------------------------
  Sprite_DrawRotated (125e:0388) -- HAND ASSEMBLER, transcribed verbatim.

  Draws one 56x56 sprite rotated about its top-left corner into the virtual
  screen. It is a plain rotate-and-sample: two fixed-point accumulators walk
  the source square, stepping by (SinA, CosA) along a row and (CosA, -SinA)
  down a column, so the rotation costs two adds per pixel and no multiplies
  at all. Coordinates are 6-bit fixed point, hence the SHL 6 on the way in
  and the SHR 6 on the way out.

  Three things are worth knowing before reading it:

  * TWO BYTES ARE WRITTEN PER SOURCE PIXEL. At 64/64 = 1.0 units per step a
    rotated sample grid leaves gaps, so each store is a WORD -- the sampled
    pixel and the one after it -- which smears the sprite one pixel wide and
    fills them. Above 180 degrees the pair is written in the other order
    (125e:03d6), because that is the side the gap falls on once the rotation
    has passed the half turn.

  * SI IS THE SOURCE INDEX AND IT MUST ADVANCE BY EXACTLY ONE PER PIXEL,
    whether the pixel is drawn or not. MOVSB/MOVSW advance it by one or two
    of their own accord, so the routine brackets the store with INC SI /
    DEC SI to land back on the right byte either way. That bookkeeping is the
    reason this cannot be written as Pascal without changing what it does.

  * THE DESTINATION IS ALWAYS VirtScrSeg, taken straight from DS:$E770. It is
    not a parameter.

  The address arithmetic at 125e:03c4 is
        DI := (FixX shr 6) + (FixY and $FFC0) * 5
  which is the same as (FixY shr 6) * 320 + (FixX shr 6), since masking off
  the low six bits and multiplying by five gives 64*5 = 320 per whole row.
  The multiply by five is done as x + x*4 with a shift, so there is no MUL.

  Clipping is one-sided: Y must be in 1..189 ($3F < FixY < $2F80) and X must
  be at least 1, but there is NO upper bound on X, so a sprite pushed far
  enough right wraps onto the following rows. The original has the same hole.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      FixX := X shl 6;
      FixY := Y shl 6;
      S    := 0;
      for Row := 1 to 56 do
      begin
        U := FixX;  V := FixY;
        for Col := 1 to 56 do
        begin
          if (V < $2F80) and (V > $3F) and (U > $3F) then
          begin
            D := (U shr 6) + (V and $FFC0) * 5;
            if Ang > 180 then
            begin
              Mem[VirtScrSeg : D + 1] := Src^[S];
              Mem[VirtScrSeg : D    ] := Src^[S + 1];
            end
            else
            begin
              Mem[VirtScrSeg : D    ] := Src^[S];
              Mem[VirtScrSeg : D + 1] := Src^[S + 1];
            end;
          end;
          Inc(U, SinA);  Inc(V, CosA);  Inc(S);
        end;
        Inc(FixX, CosA);  Dec(FixY, SinA);
      end;

  Where that Pascal is not the same thing:

  * Src^[S + 1] over-reads the heap block by one byte on the very last pixel.
    The original does too -- MOVSW at 125e:03e5 reads bytes 3135 and 3136 of
    a 3,136-byte block -- but Pascal with range checking on would trap it.
  * the two byte stores are one word store in the original, so the original
    is atomic across the pair and half the bus cycles.
  * S, U, V, D and the two loop counters live in SI, CX, AX, DI, BL and BH.
    There is no frame traffic in the inner loop whatsoever, and the whole
    thing is eleven instructions per pixel in the common case.
  -------------------------------------------------------------------------- }
{ @asm 003 125e:0388 }
procedure DrawRotated(Ang, SinA, CosA, X, Y : Integer; Src : Pointer);
  assembler;
var
  FixX, FixY : Integer;        { [BP-2] and [BP-4] }
asm
  PUSH DS                  { the source segment goes in DS, so save ours    }

  MOV  AX, X               { the left edge, in whole pixels                 }
  SHL  AX, 6               { -> 6-bit fixed point                           }
  MOV  FixX, AX            { [BP-2] := X shl 6, the row's starting U        }
  MOV  AX, Y               { the top edge                                   }
  SHL  AX, 6               { -> 6-bit fixed point                           }
  MOV  FixY, AX            { [BP-4] := Y shl 6, the row's starting V        }

  MOV  AX, [VirtScrSeg]    { DS:$E770 -- the virtual screen                 }
  MOV  ES, AX              { ES: is the destination for every store below   }
  LDS  SI, Src             { DS:SI := the sprite                            }
  XOR  SI, SI              { GetMem normalises, so the offset was 0 anyway; }
                           {   SI is now the source pixel index             }

  MOV  BH, 56              { BH counts output rows                          }

@@Row:                     { <- once per output row                         }
  MOV  CX, FixX            { CX := U, this row's fixed-point X              }
  MOV  AX, FixY            { AX := V, this row's fixed-point Y              }
  MOV  BL, 56              { BL counts output columns                       }

@@Col:                     { <- once per output pixel                       }
  INC  SI                  { assume the pixel is skipped: advance the index }
  CMP  AX, $2F80           { V >= 190.0 ?  (190 * 64)                       }
  JGE  @@Skip              {   below the screen -- drop it                  }
  CMP  AX, $3F             { V <= 0.98 ?                                    }
  JLE  @@Skip              {   above the screen -- drop it                  }
  CMP  CX, $3F             { U <= 0.98 ?                                    }
  JLE  @@Skip              {   off the left edge -- drop it                 }

  DEC  SI                  { drawing after all: back onto this pixel        }
  MOV  DX, AX              { DX := V                                        }
  MOV  DI, CX              { DI := U                                        }
  SHR  DI, 6               { DI := whole-pixel X                            }
  AND  DX, $FFC0           { DX := V with the fraction masked off           }
  ADD  DI, DX              { DI := X + V'                                   }
  SHL  DX, 2               { DX := V' * 4                                   }
  ADD  DI, DX              { DI := X + V' * 5  =  X + row * 320             }

  CMP  Ang, SwapAngle      { past the half turn?                            }
  JLE  @@Even              {   no -- the straight word store                }
  INC  DI                  {   yes: start one pixel to the right            }
  MOVSB                    { ES:[DI]   := Src[SI]   (the sampled pixel)     }
  SUB  DI, 2               { step back two -- SI advanced, DI must not      }
  MOVSB                    { ES:[DI-1] := Src[SI+1] (the filler, on the     }
                           {              left this time)                   }
  JMP  @@Next              { the pair is written -- rejoin                  }
@@Even:                    { <- at or below the half turn                   }
  MOVSW                    { ES:[DI] := Src[SI], ES:[DI+1] := Src[SI+1]     }
@@Next:                    { <- both stores rejoin here                     }
  DEC  SI                  { MOVSB/MOVSW left SI two on; net advance is one }

@@Skip:                    { <- clipped pixels join here, SI already on     }
  ADD  CX, SinA            { U += sin -- step along the output row          }
  ADD  AX, CosA            { V += cos                                       }
  DEC  BL                  { one column done                                }
  JNZ  @@Col               { round again until the row is finished          }

  MOV  DX, CosA            { the column direction's X component             }
  ADD  FixX, DX            { next row starts cos further along X            }
  MOV  DX, SinA            { and its Y component                            }
  SUB  FixY, DX            { and sin back up Y -- (cos, -sin) is the        }
                           {   column direction of the rotation matrix      }
  DEC  BH                  { one row done                                   }
  JNZ  @@Row               { round again until all 56 rows are done         }

  POP  DS                  { restore our data segment                       }
end;

{ --------------------------------------------------------------------------
  Sprites_DrawChar (125e:0000) -- compiled Pascal in the binary, so it is
  Pascal here.

  Draws a string with the 5x5 font at (X, Y), six pixels of pitch, in colour
  50. Note that the glyph's ROW index becomes the screen X and its COLUMN
  index becomes the screen Y -- the font is stored transposed, and the
  original plots it that way round (125e:0083 and 125e:008f).

  It takes a String even though every call site passes a single character;
  the compiler's Char-to-String helper at 1000:6fd7 does the conversion into
  a stack temporary, which is what the ENTER $10A is mostly reserving.
  -------------------------------------------------------------------------- }
procedure DrawChar(X, Y : Integer; S : String; Segment : Word);
var
  Advance, I, R, C : Integer;
begin
  Advance := 0;                           { [BP-$108] -- the pen position }
  for I := 1 to Length(S) do              { [BP-$102], limit at [BP-$10A] }
  begin
    for R := 1 to FontCell do             { [BP-$104] }
      for C := 1 to FontCell do           { [BP-$106] }
        if Font[Ord(S[I]), R, C] <> 0 then
          PutPixel(R + X + Advance, C + Y, CharColour, Segment);
    Inc(Advance, CharGap);                { 125e:00AF }
  end;
end;

{ --------------------------------------------------------------------------
  Sprites_FadeStep (125e:047a) -- one step of a 64-step fade IN.

  Waits for retrace, then for all 256 entries reads the current RGB back off
  the DAC and increments each channel that is still below its target. Called
  once a frame during the fly-in and 64 times before the closing sweep.
  -------------------------------------------------------------------------- }
procedure FadeStep;
var
  I       : Integer;
  R, G, B : Byte;
begin
  WaitRetrace;                                   { 125e:047e }
  for I := 0 to 255 do
  begin
    GetRGB(I, R, G, B);                          { 125e:04a0 }
    if R < TargetPal[I, 0] then Inc(R);          { 125e:04b1 -- unsigned }
    if G < TargetPal[I, 1] then Inc(G);
    if B < TargetPal[I, 2] then Inc(B);
    SetRGB(I, R, G, B);                          { 125e:04f4 }
  end;
end;

{ --------------------------------------------------------------------------
  Sprites_FadeOut (125e:0406) -- the fade to black after each caption block.

  Sixty-four passes over the whole DAC, each one decrementing every channel
  that has not reached zero yet. The retrace wait at 125e:040a is OUTSIDE
  both loops -- it happens once, not once per pass -- so this is not a
  timed fade; it runs as fast as the DAC will take it.
  -------------------------------------------------------------------------- }
procedure FadeOut;
var
  I, J    : Integer;
  R, G, B : Byte;
begin
  WaitRetrace;                                   { 125e:040a -- once only }
  for J := 1 to FadeSteps do
    for I := 0 to 255 do
    begin
      GetRGB(I, R, G, B);
      if R > 0 then Dec(R);                      { 125e:043b -- unsigned }
      if G > 0 then Dec(G);
      if B > 0 then Dec(B);
      SetRGB(I, R, G, B);
    end;
end;

{ --------------------------------------------------------------------------
  Sprites_Load (125e:012e)

  ASSETS  NEUROSIS.DAT $11EEC0, 14,862 bytes in six reads:
            assets/part003/font_5x5.bin          1,550 B, the 5x5 bitmap font
            assets/part003/sprite1.png / .bin    3,136 B = 56x56 portrait
            assets/part003/sprite2.png / .bin    3,136 B
            assets/part003/sprite3.png / .bin    3,136 B
            assets/part003/sprite4.png / .bin    3,136 B
            assets/part003/sprites_palette.pal     768 B
          The four 3,136-byte reads sit in a loop in the original; 3136 =
          56*56 is what fixes the sprite dimensions, and rendering them at
          that size shows the four Asphyxia members.
          See docs/13-part3-scene7-sprites.md.

  It then builds both lookup tables and blanks the DAC, so the scene starts
  from black no matter what the previous one left behind.

  THE 65535 BIAS. The wobble table is built as

      Round(sin(a) * 39.6 + 65535.0) mod 65535

  which looks pointless until you follow a negative value through it. For
  sin(a) = -1 that is Round(65495.4) = 65495; 65495 mod 65535 is still
  65495, and storing that LongInt into an Integer keeps the low word --
  $FFD7, which is -41. The bias and the modulo together are how the original
  gets a signed result out of Round without ever handing Round a negative:
  positive values come back unchanged, negative ones wrap round through the
  word. It is reproduced here as written; it needs range checking off, which
  is Borland's default.
  -------------------------------------------------------------------------- }
procedure Load;
var
  F   : file;                                    { DS:$E6EC }
  I   : Integer;                                 { [BP-$82] }
  Tmp : array[0..AngleWrap - 1] of               { [BP-$626] }
          record X, Y : Integer end;

  { 125e:00d3. The original declares this twice -- once nested in Load and
    once nested in Prepare (125e:0510) -- as two byte-identical copies. }
  function DegToRad(D : Real) : Real;
  begin
    DegToRad := D * Pi / 180.0;
  end;

begin
  Assign(F, 'neurosis.dat');                     { 125e:013c }
  Reset(F, 1);                                   { 125e:0148 }
  Seek(F, DataOfs);                              { 125e:0157 }
  BlockRead(F, Font, FontSize);                  { 125e:016d -> DS:$DDDE }

  { 125e:017a -- the rotation table, 6-bit fixed point }
  for I := 0 to AngleWrap - 1 do
  begin
    Trig[I].S := Round(Sin(DegToRad(I)) * TrigScale);
    Trig[I].C := Round(Cos(DegToRad(I)) * TrigScale);
  end;

  { 125e:01f0 -- the wobble, into a stack temporary first }
  for I := 0 to AngleWrap - 1 do
  begin
    Tmp[I].X := Round(Sin(DegToRad(I)) * WobbleScale + WobbleBias) mod 65535;
    Tmp[I].Y := Round(Cos(DegToRad(I)) * WobbleScale + WobbleBias) mod 65535;
  end;

  { 125e:0297 -- copied out 225 degrees along, so the wobble starts in the
    third quadrant rather than at zero }
  for I := 0 to AngleWrap - 1 do
  begin
    Wobble[I].X := Tmp[(I + WobblePhase) mod AngleWrap].X;
    Wobble[I].Y := Tmp[(I + WobblePhase) mod AngleWrap].Y;
  end;

  for I := 1 to NumSprites do                    { 125e:02ef }
    GetMem(Sprite[I], SpriteSize);

  for GI := 1 to NumSprites do                   { 125e:0319 -- the global }
    BlockRead(F, Sprite[GI]^, SpriteSize);

  BlockRead(F, TargetPal, 768);                  { 125e:0353 -> DS:$E3EC }

  for I := 0 to 255 do                           { 125e:0360 }
    SetRGB(I, 0, 0, 0);                          { start from black }

  Close(F);                                      { 125e:0381 }
end;

{ --------------------------------------------------------------------------
  Sprites_Prepare (125e:0550) -- one member's introduction, all three phases.

  Not the caption-only routine an earlier pass took it for. The caption is
  phase 3 of three; phases 1 and 2 are the portrait flying in and orbiting.

  The caption addressing at 125e:0741 is

      DS:$6BB8 + N * $A00 + Row * $100 + Col

  with N = 1..4 and Row = 1..10. That is a flat array of 256-byte String
  slots: $6BB8 + 11*$100 = $76B8 is member 1's first line, which is exactly
  where the strings were first found. In Pascal terms it is

      Captions[(N - 1) * 10 + Row][Col]

  and the two addresses agree exactly -- see gen/P3CAPT.INC.

  A keypress abandons the whole introduction at any point. It is never
  consumed, so Run's remaining Prepare calls fall straight through too and
  the scene ends.
  -------------------------------------------------------------------------- }
procedure Prepare(N : Integer);
var
  X, Y     : Integer;      { [BP-2], [BP-4] }
  Ang      : Integer;      { [BP-6] }
  T        : Integer;      { [BP-8]  -- the orbit frame counter }
  Row, Col : Integer;      { [BP-$A], [BP-$C] }

  { 125e:0510 -- the second of the two identical copies; see Load. }
  function DegToRad(D : Real) : Real;
  begin
    DegToRad := D * Pi / 180.0;
  end;

begin
  Y   := FlyY;                                   { 125e:0554 }
  Ang := StartAngle;                             { 125e:0559 }
  ClearScreen($A000, 0);                         { 125e:0563 }
  ClearScreen(VirtScrSeg, 0);                    { 125e:056e }

  { ---- phase 1: the fly-in, 125e:0573 ---- }
  for X := FlyFrom to FlyTo do
  begin
    if KeyPressed then Exit;                     { 125e:057d }
    if X > 0 then FadeStep;                      { 125e:0589 -- fade up
                                                   only once it is on screen }
    Ang := (Ang + SpinStep) mod AngleWrap;       { 125e:0592 }
    ClearScreen(VirtScrSeg, 0);
    DrawRotated(Ang, Trig[Ang].S, Trig[Ang].C,
                X * 2 + Wobble[Ang].X,
                Wobble[Ang].Y + Y,
                Sprite[N]);                      { 125e:05f0 }
    CopyScreen(VirtScrSeg, $A000);               { 125e:05fa }
  end;

  { ---- phase 2: the orbit, 125e:0608 ---- }
  for T := 0 to OrbitFrames do
  begin
    if KeyPressed then Exit;                     { 125e:0612 }
    Ang := (Ang + SpinStep) mod AngleWrap;       { 125e:061e }
    { 2 degrees a frame over 181 frames is one full turn, radius 60 }
    X := Round(Sin(DegToRad(T * 2)) * OrbitRadius) + OrbitCX;   { 125e:0655 }
    Y := Round(Cos(DegToRad(T * 2)) * OrbitRadius) + OrbitCY;   { 125e:0685 }
    ClearScreen(VirtScrSeg, 0);
    DrawRotated(Ang, Trig[Ang].S, Trig[Ang].C,
                Wobble[Ang].X + X,
                Wobble[Ang].Y + Y,
                Sprite[N]);                      { 125e:06da }
    CopyScreen(VirtScrSeg, $A000);               { 125e:06e4 }
  end;

  { ---- phase 3: the typewriter, 125e:06f3 ---- }
  Delay(PreDelay);                               { 125e:06f6 }
  for Row := 1 to CaptionRows do
    for Col := 1 to CaptionCols do
    begin
      if KeyPressed then Exit;                   { 125e:070f }
      DrawChar(Col * CharGap, Row * CharGap,
               Captions[(N - 1) * CaptionRows + Row][Col],
               $A000);                           { 125e:0757 -- straight to
                                                   the visible page }
      Delay(TypeDelay);                          { 125e:075c }
    end;
  Delay(PostDelay);                              { 125e:0770 }
  FadeOut;                                       { 125e:0775 }
end;

{ --------------------------------------------------------------------------
  Sprites_Run (125e:077c)

  The four introductions in turn, then all four portraits at once sweeping
  down the screen. The four DrawRotated calls are written out longhand in the
  original rather than looped -- 125e:0838, 0885 and 08d2 hold the literal
  70, 140 and 210 -- so they are longhand here too.

  X is fixed for the whole sweep and Y is what moves: Sweep runs -20..120 and
  the position is Sweep*2, so the group travels from Y = -40 to Y = 240,
  entering off the top and leaving off the bottom. DrawRotated clips to rows
  1..189, so most of each end of the run is off-screen.
  -------------------------------------------------------------------------- }
procedure Run;
var
  Angle : array[1..NumSprites] of Integer;   { [BP-$10] .. [BP-8] }
  X     : Integer;                           { [BP-4] }
  Sweep : Integer;                           { [BP-6] }
begin
  X := BaseX;                                    { 125e:0782 }
  { [BP-6] is also set to 100 here (125e:0787) and never read -- the sweep
    below overwrites it. }

  for GI := 1 to NumSprites do Prepare(GI);      { 125e:0797 }

  for GI := 1 to NumSprites do                   { 125e:07af }
    Angle[GI] := Random(AngleWrap);

  ClearScreen($A000, 0);                         { 125e:07cb }
  for GI := 1 to FadeSteps do FadeStep;          { 125e:07dc }

  for Sweep := SweepFrom to SweepTo do           { 125e:07ee }
  begin
    if KeyPressed then Exit;                     { 125e:07f8 }

    for GI := 1 to NumSprites do                 { 125e:0809 }
      Angle[GI] := (Angle[GI] + SpinStep) mod AngleWrap;

    ClearScreen(VirtScrSeg, 0);                  { 125e:0830 }

    DrawRotated(Angle[1], Trig[Angle[1]].S, Trig[Angle[1]].C,
                Wobble[Angle[1]].X + X,
                Sweep * 2 + Wobble[Angle[1]].Y,  Sprite[1]);
    DrawRotated(Angle[2], Trig[Angle[2]].S, Trig[Angle[2]].C,
                Wobble[Angle[2]].X + X + HSpacing,
                Sweep * 2 + Wobble[Angle[2]].Y,  Sprite[2]);
    DrawRotated(Angle[3], Trig[Angle[3]].S, Trig[Angle[3]].C,
                Wobble[Angle[3]].X + X + HSpacing * 2,
                Sweep * 2 + Wobble[Angle[3]].Y,  Sprite[3]);
    DrawRotated(Angle[4], Trig[Angle[4]].S, Trig[Angle[4]].C,
                Wobble[Angle[4]].X + X + HSpacing * 3,
                Sweep * 2 + Wobble[Angle[4]].Y,  Sprite[4]);

    CopyScreen(VirtScrSeg, $A000);               { 125e:0940 }
  end;
end;

{ --------------------------------------------------------------------------
  Demo_Scene7 (125e:0958)
  -------------------------------------------------------------------------- }
procedure Scene7;
begin
  Load;
  Run;
  for GI := 1 to NumSprites do                   { 125e:0967 }
    FreeMem(Sprite[GI], SpriteSize);             { 137b:029f, 3136 each }
end;

end.

{ ===========================================================================
  NOTES

  * The four faces ARE the four members. The captions are compiled into
    DGROUP as 256-byte String slots from DS:$76B8 -- ten 50-character lines
    per member, in portrait order (see gen/P3CAPT.INC):

        SUBJECT : PETER EDWARDS   CODENAME : EZE      THE WIERD ONE
        SUBJECT : GRANT SMITH     CODENAME : DENTHOR  THE TALL ONE
        SUBJECT : BRIAN BAILEY    CODENAME : GOTH     THE BITCHY ONE
        SUBJECT : PIETER BUYS     CODENAME : FUBAR    THE UNFORGIVEN ONE
                                                      (BECAUSE OF EXAMS...)

    Occupation is STUDENT for all four; tasks are CODE+MUSIC, CODE, CODE and
    ART respectively. This matches PSYCHO.NFO. Every character used falls in
    Ord 32..90, inside the font's 32..93.

  * THE 1,550-BYTE READ IS THE FONT, not padding. An earlier pass recorded it
    as dead because the same 1,550 bytes appear byte-identically in part 002
    (DAT $080CB2, loaded to DS:$5448) where nothing consumes them, and
    because the block holds only the values 0 and $AB. Both observations are
    true and neither settles it: 0/$AB is exactly what a one-bit 5x5 font
    looks like stored a byte per pixel, and here DrawChar reads it at
    [DI + $DAB8] with DI = Ord*25 + Row*5 + Col, which resolves to the same
    $DDDE the BlockRead writes. 1550 = 62 glyphs x 25. It is dead in part 002
    and live here.
        assets/part003/font_5x5.bin

  * Each portrait gets a RANDOM starting angle for the closing sweep, so the
    four are never in phase even though they all spin at the same rate.
    Random is never seeded, so the four angles are the same every run.

  * Nothing here sets a video mode. The scene inherits mode 13h and the
    virtual screen from the part's driver, and Load blanks the DAC so it
    always starts from black.

  * The introductions write the portrait to the virtual screen and blit, but
    the typewriter writes STRAIGHT to $A000 (125e:0754 pushes $A000). That is
    why the caption survives on screen without a blit behind it.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
