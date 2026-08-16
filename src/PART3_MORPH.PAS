{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 3
  Reconstructed from NEUROSIS_003_fpu.exe, segment 1139.

  A rotating 3-D point object that morphs between shapes, drawn in 320x400
  Mode-X with hardware page flipping, and faded to black at the end.

  Everything here is fixed-point integer -- 16.14 sin/cos from a lookup table
  and a 32-bit divide for the perspective. No floating point at all.

  THE SHAPE DATA IS NOT IN NEUROSIS.DAT. It is compiled into the executable as
  typed constants in DGROUP, which is why Scene 3 never appears in the DAT
  access map. Layout:

    DS:$02A8   sine table, 450 entries of 16.14 fixed point
               (cos is the same table read 90 entries in -- hence the $035C
                base, exactly 180 bytes = 90 words later)
    DS:$0636   shape data, slots of 4800 bytes (800 points x 6), of which the
               first 765 points of a slot are drawn

  Shapes used, identified by rendering the raw vertex data:

    slot 0  $0636   SPHERE     X,Y,Z all -800..800   (meridians + parallels)
    slot 4  $5136   CUBE       X,Y,Z all -400..400
    slot 5  $63F6   FLAT GRID  X,Z -1000..1000, Y -400..400

  So the scene runs sphere -> cube -> plane -> cube -> sphere. The clean
  symmetric ranges also confirm the 6-byte record is three signed words in
  X, Y, Z order.

  ADDRESS MAP
    Demo_Scene3       1139:03b4    Morph_InitScene       1139:02fe
    Morph_SetAngles   1139:0000    Morph_StepAngles      1139:0035
    Morph_TransformPoint 1139:0096 ModeX_PlotPixel       1139:01bb
    Morph_DrawShape   1139:01f9    Morph_DrawMorph       1139:021d
    ModeX_ClearPage   1139:02a2    ModeX_FlipPage        1139:02c3
    VGA_Set400Lines   1139:02f2    Morph_FadeStep        1139:0365
    VGA_SetPalette768 1139:0335    VGA_GetPalette768     1139:034d
  =========================================================================== }

{$G+}   { 286 instructions: 1139:01d9 is SHR DI,2, and a shift by an
          immediate other than 1 is a 286 encoding. The original
          targeted 286+, so enabling this is faithful, not a shortcut. }

unit Part3Morph;

interface

procedure Scene3;

implementation

uses VGA, Crt;

const
  NumPoints  = 765;        { $2FD -- points actually drawn per shape }
  SlotSize   = 4800;       { 800 points x 6 bytes -- spacing between shapes }
  ShapeBase  = $0636;
  Shape0     = $0636;
  Shape4     = $5136;      { ShapeBase + 4*SlotSize }
  Shape5     = $63F6;      { ShapeBase + 5*SlotSize }

  SinTable   = $02A8;      { 450 entries, 16.14 fixed point }
  CosTable   = $035C;      { = SinTable + 90 entries }
  FixedBits  = 14;         { products are shifted right by 14 }
  { The scaling has to be a DIVIDE, not `shr FixedBits`.

    The original does `IMUL` then `SHL AX,1 / RCL DX,1` twice and keeps DX --
    the top word of the product times four, which is an ARITHMETIC shift right
    by 14 and preserves the sign. Turbo Pascal's `shr` on a LongInt is a
    LOGICAL shift, so any point whose intermediate went negative came out as a
    huge positive, landed far off screen and was dropped by PlotPixel's bounds
    test. What survived was the handful of points that stayed non-negative
    throughout -- a small block of dots near the centre instead of a rotating
    solid.

    `div` truncates toward zero where an arithmetic shift floors, so the two
    differ by one unit on negative values -- well under a pixel after the
    perspective divide. The original really does shift; there is simply no
    signed shift operator in Turbo Pascal to write it with. }
  FixedOne   = 16384;      { 1 shl FixedBits }
  ScreenCentreX = 160;     { $A0 -- 1139:019c }
  ScreenCentreY = 200;     { $C8 -- 1139:01ac, half of 400 rows }

  PageWidth  = 320;        { visible page }
  PageHeight = 400;        { double-scan disabled -- see VGA_Set400Lines }
  RowBytes   = 160;        { per plane; two 320-wide pages side by side }
  PageOfsA   = 0;
  PageOfsB   = 80;         { second page starts 80 bytes into each row }

{ These four live in DGROUP, not in the code -- the scene assigns them in
  Morph_InitScene -- so they are TYPED constants, which Borland Pascal puts in
  initialised data and allows you to write to. }
const
  MorphSteps : Integer = 45;     { DS:$BEB6 }
  ViewDist   : Integer = 2500;   { DS:$BEB4 }
  ProjScale  : Integer = 256;    { DS:$BEB2 }

const

  AngleWrap  = 360;        { $168 }
  SpinX      = 3;          { degrees per frame, all three axes }
  SpinY      = 3;
  SpinZ      = 3;

  SegFrames  = 45;         { $2D -- frames per scripted segment }
  LastFrames = 63;         { $3F -- the closing fade segment }


  DotColour  = $0E;        { yellow }

type
  { 765 points of (X, Y, Z). Declared two-dimensional because that is what
    the data is; Morph_DrawMorph walks it with pointer arithmetic (six
    bytes per point) and does not care either way. }
  TShape = array[1..NumPoints, 1..3] of Integer;

{ Both of these are TYPED CONSTANTS living in the executable's initialised
  data, not tables built at run time -- a plain `var` would land in BSS and
  would not appear in the file image at all.

  Verified: SinTab[i] = round(sin(i degrees) * 16384) to within 1, and
  SinTab[90 + a] = round(cos(a) * 16384) exactly, which is what lets one
  table serve both functions. }
{$I gen/P3SINE.INC}      { const SinTab : array[0..449] of Integer = (...) }

{ ===========================================================================
  RECONSTRUCTION SCAFFOLDING -- see the note in PART1_INTRO.PAS.
  =========================================================================== }

var
  { [transcribed] The projection centre, DS:$BEB0-ish. Morph_InitScene zeroes
    both before the first shape and they stay put for this scene. }
  XCentre, YCentre : Integer;

  { [inferred] The shape currently being drawn. The original addresses shapes
    by their DGROUP offset (CurShape, MorphFrom, MorphTo are Words holding
    $0636, $5136, $63F6) and walks them with pointer arithmetic; a working
    copy is the readable equivalent. }
{$I gen/P3SHAPE.INC}     { const ShapeSphere, ShapeCube, ShapeGrid : TShape }

{ --------------------------------------------------------------------------
  SHAPE ADDRESSING

  The original identifies a shape by its DGROUP offset -- $0636, $5136,
  $63F6 -- and DrawShape/DrawMorph walk it with SI six bytes at a time.
  Typed constants live in DGROUP here too, so Ofs() gives exactly the same
  kind of value and the assembler below stays literal. The three compiled-in
  offsets cannot be reused verbatim because the compiler decides where it
  puts these arrays, but nothing else about the addressing changes.
  -------------------------------------------------------------------------- }
var
  OfsSphere, OfsCube, OfsGrid : Word;

procedure BindShapes;
begin
  OfsSphere := Ofs(ShapeSphere);      { $0636 in the original }
  OfsCube   := Ofs(ShapeCube);        { $5136 }
  OfsGrid   := Ofs(ShapeGrid);        { $63F6 }
end;

{ --------------------------------------------------------------------------
  1139:034d -- GetPalette768(var P)

  Hand assembler. The whole DAC comes back in a single REP INSB rather than a
  counted loop, which is why there is no loop here to transcribe.
  -------------------------------------------------------------------------- }
procedure GetPalette768(var P); assembler;
asm
  LES  DI, P            { ES:DI := the caller's 768-byte buffer, from [BP+4] }
  MOV  DX, $3C7         { $3C7 is the DAC READ index register                }
  MOV  AL, 0            { start at colour 0                                  }
  OUT  DX, AL           { select it; the DAC now auto-increments             }
  ADD  DX, 2            { DX := $3C9, the DAC data register                  }
  MOV  CX, $300         { 768 bytes: 256 colours x 3 components              }
  REP  INSB             { read them all straight into ES:DI                  }
end;

{ --------------------------------------------------------------------------
  1139:0335 -- SetPalette768(var P)

  The write side, likewise a single REP OUTSB. Note there is NO retrace wait
  in the original -- the Pascal version used to add one, which is a change in
  behaviour, not a tidy-up.
  -------------------------------------------------------------------------- }
procedure SetPalette768(var P); assembler;
asm
  PUSH DS               { OUTSB sources from DS:SI, so DS must be restored   }
  LDS  SI, P            { DS:SI := the caller's 768-byte buffer, from [BP+4] }
  MOV  DX, $3C8         { $3C8 is the DAC WRITE index register               }
  MOV  AL, 0            { start at colour 0                                  }
  OUT  DX, AL           { select it                                          }
  INC  DX               { DX := $3C9, the DAC data register                  }
  MOV  CX, $300         { 768 bytes                                          }
  REP  OUTSB            { write them all out from DS:SI                      }
  POP  DS               { restore the data segment                           }
end;


var
  AngX, AngY, AngZ    : Integer;   { DS:$BE9C, $BE9E, $BEA0 }
  StepX, StepY, StepZ : Integer;   { DS:$BEA2, $BEA4, $BEA6 }
  SinX, CosX          : Integer;   { DS:$BE92, $BE90 }
  SinY, CosY          : Integer;   { DS:$BE96, $BE94 }
  SinZ, CosZ          : Integer;   { DS:$BE98, $BE9A }
  CurShape            : Word;      { DS:$BEBA -- shape being drawn }
  MorphFrom, MorphTo  : Word;      { DS:$BEBC, $BEBE }
  MorphStep           : Integer;   { DS:$BEB8 }
  PageOfs             : Word;      { DS:$BEC0 -- 0 or 80 }
  Count               : Word;      { DS:$BEC4 -- the point counter }
  Frames              : Integer;   { DS:$BEC2 }
  { DS:$BEC6 -- EIGHT HUNDRED entries, not PageHeight. 1192:0000 fills
    0..$31F regardless of how many rows the mode actually shows. }
  RowOfs              : array[0..799] of Word;

{ --------------------------------------------------------------------------
  VGA_Set400Lines (1139:02f2)
  CRTC register 9, low five bits cleared: maximum scan line = 0, i.e. no
  double scanning. That turns the 320x200 Mode-X screen into 320x400.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  1192:0000 -- the Mode-X row table

      for I := 0 to $31F do
        RowOfs[I] := (LogicalWidth * I) shl 1

  LogicalWidth is the byte at DS:$76B6, which InitScene sets to 80, so the
  stride is 160 bytes per row -- one plane of a 640-pixel logical line.

  THIS IS NOT VGA.BuildRowTable. That one fills VGA's own YOfs with y * 320
  for the 200 rows of mode 13h, and it is what InitScene used to call: the
  table below stayed all zeros, every dot landed on row 0, and the scene drew
  nothing. The two tables coexist and must not be conflated -- the note at the
  bottom of VGA.PAS says exactly that.

  The code lives in segment 1192 with the rest of the VGA unit, but the table
  it fills is at DS:$BEC6, in this scene's own data, which is why it is here.
  -------------------------------------------------------------------------- }
procedure BuildModeXRows;
var
  I : Integer;
begin
  for I := 0 to 799 do
    RowOfs[I] := Word(LogicalWidth) * Word(I) shl 1;
end;

procedure Set400Lines; assembler;
asm
  MOV  DX, $3D4
  MOV  AL, 9
  OUT  DX, AL
  INC  DX
  IN   AL, DX
  AND  AL, $E0
  OUT  DX, AL
end;

{ --------------------------------------------------------------------------
  1139:0000 -- SetAngles.  AngX in BX, AngY in CX, AngZ in DX.

  Hand assembler, reached by a plain CALL from StepAngles with the angles
  already in registers. One table serves both functions: cos(a) is sin(a+90),
  so the cosine lookup is the same table 90 entries -- 180 bytes -- further
  along. That is why the original quotes two base addresses, $02A8 and $035C,
  for one table. No trig call anywhere in the frame path.
  -------------------------------------------------------------------------- }
procedure SetAngles; assembler;
asm
  ADD  BX, BX                          { BX := AngX * 2, a word index        }
  MOV  AX, [BX + OFFSET SinTab]        { AX := sin(AngX)          tbl $02A8  }
  MOV  [SinX], AX                      { -> DS:$BE92                         }
  MOV  AX, [BX + OFFSET SinTab + 180]  { +90 entries = cos(AngX)  tbl $035C  }
  MOV  [CosX], AX                      { -> DS:$BE90                         }

  MOV  BX, CX                          { the Y angle arrived in CX           }
  ADD  BX, BX                          { BX := AngY * 2                      }
  MOV  AX, [BX + OFFSET SinTab]        { AX := sin(AngY)                     }
  MOV  [SinY], AX                      { -> DS:$BE96                         }
  MOV  AX, [BX + OFFSET SinTab + 180]  { AX := cos(AngY)                     }
  MOV  [CosY], AX                      { -> DS:$BE94                         }

  MOV  BX, DX                          { the Z angle arrived in DX           }
  ADD  BX, BX                          { BX := AngZ * 2                      }
  MOV  AX, [BX + OFFSET SinTab]        { AX := sin(AngZ)                     }
  MOV  [SinZ], AX                      { -> DS:$BE9A                         }
  MOV  AX, [BX + OFFSET SinTab + 180]  { AX := cos(AngZ)                     }
  MOV  [CosZ], AX                      { -> DS:$BE98                         }
end;

{ --------------------------------------------------------------------------
  1139:0035 -- StepAngles.  Advance each axis, wrap into 0..360, then hand
  all three to SetAngles in BX, CX and DX.

  The wrap is two compares rather than a modulo. That is exact only because
  the step is small: three degrees a frame cannot overshoot by a whole turn.
  -------------------------------------------------------------------------- }
procedure StepAngles; assembler;
asm
  MOV  BX, [AngX]                { BX := the X angle                        }
  ADD  BX, [StepX]               { advance it by this scene's step          }
  CMP  BX, 0                     { did it go negative?                      }
  JGE  @@XNotNeg                 {   no                                     }
  ADD  BX, 360                   {   yes: wrap up one turn                  }
@@XNotNeg:
  CMP  BX, 360                   { did it pass a full turn?                 }
  JLE  @@XDone                   {   no                                     }
  SUB  BX, 360                   {   yes: wrap down one turn                }
@@XDone:
  MOV  [AngX], BX                { store back, and leave it in BX           }

  MOV  CX, [AngY]                { the Y angle, kept in CX                  }
  ADD  CX, [StepY]
  CMP  CX, 0
  JGE  @@YNotNeg
  ADD  CX, 360
@@YNotNeg:
  CMP  CX, 360
  JLE  @@YDone
  SUB  CX, 360
@@YDone:
  MOV  [AngY], CX

  MOV  DX, [AngZ]                { the Z angle, kept in DX                  }
  ADD  DX, [StepZ]
  CMP  DX, 0
  JGE  @@ZNotNeg
  ADD  DX, 360
@@ZNotNeg:
  CMP  DX, 360
  JLE  @@ZDone
  SUB  DX, 360
@@ZDone:
  MOV  [AngZ], DX

  CALL SetAngles                 { BX, CX, DX now hold the three angles     }
end;

{ --------------------------------------------------------------------------
  Morph_TransformPoint (1139:0096)

  Three successive 2-D rotations in 16.14 fixed point, then a perspective
  divide. Each product is a 32-bit multiply shifted right by 14.

  Registers on entry: BX = X, CX = Y, DX = Z (read straight from the 6-byte
  record). On exit DI = screen X, BX = screen Y, for ModeX_PlotPixel.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  The rotation's fixed-point scaling, as the original writes it.

  After each IMUL the 32-bit product sits in DX:AX, and 1139:00bd does

      SHL AX,1 / RCL DX,1        twice, then keeps DX

  -- the top word of the product times four, i.e. an arithmetic shift right by
  14. No divide. Turbo Pascal has no signed shift operator, but DX is just the
  high half of the shifted product, so casting the LongInt over a two-Integer
  record gets at it exactly, sign and all, with two shifts and no arithmetic:

      -16384 -> shl 2 = $FFFF0000 -> Hi = $FFFF = -1        ( -1.0 )
   16384000 -> shl 2 = $03E80000 -> Hi = $03E8 =  1000      ( 1000.0 )

  An earlier version of this used `div 16384`, which is numerically close but
  is not what the code does and rounds the other way on negatives.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  1139:0096 -- TransformPoint.  X in BX, Y in CX, Z in DX; SX out in DI,
  SY out in BX.  Hand assembler in the original and kept as such: it is
  reached by CALL with the registers already loaded, which is not a calling
  convention Turbo Pascal can express, and its fixed-point scaling is the
  SHL AX,1 / RCL DX,1 pair keeping DX -- an arithmetic shift right by 14
  with no divide anywhere.
  -------------------------------------------------------------------------- }
procedure TransformPoint; assembler;
var
  LX, LY, LZ, T1, T2 : Integer;    { [BP-2..-6], plus [$BEAA] and [$BEA8] }
asm
  MOV  LX, BX
  MOV  LY, CX
  MOV  LZ, DX

  MOV  CX, [CosX]                  { about the first axis }
  MOV  BX, [SinX]
  MOV  AX, LY
  IMUL CX
  MOV  SI, AX
  MOV  DI, DX
  MOV  AX, LZ
  IMUL BX
  ADD  AX, SI
  ADC  DX, DI
  SHL  AX, 1
  RCL  DX, 1
  SHL  AX, 1
  RCL  DX, 1
  MOV  T1, DX
  MOV  AX, LY
  IMUL BX
  MOV  SI, AX
  MOV  DI, DX
  MOV  AX, LZ
  IMUL CX
  SUB  AX, SI
  SBB  DX, DI
  SHL  AX, 1
  RCL  DX, 1
  SHL  AX, 1
  RCL  DX, 1
  MOV  LZ, DX
  MOV  DX, T1
  MOV  LY, DX

  MOV  CX, [CosY]                  { second axis }
  MOV  BX, [SinY]
  MOV  AX, LZ
  IMUL BX
  MOV  SI, AX
  MOV  DI, DX
  MOV  AX, LX
  IMUL CX
  SUB  AX, SI
  SBB  DX, DI
  SHL  AX, 1
  RCL  DX, 1
  SHL  AX, 1
  RCL  DX, 1
  MOV  T2, DX
  MOV  AX, LX
  IMUL BX
  MOV  SI, AX
  MOV  DI, DX
  MOV  AX, LZ
  IMUL CX
  ADD  AX, SI
  ADC  DX, DI
  SHL  AX, 1
  RCL  DX, 1
  SHL  AX, 1
  RCL  DX, 1
  MOV  LZ, DX
  MOV  DX, T2
  MOV  LX, DX

  MOV  CX, [CosZ]                  { third axis }
  MOV  BX, [SinZ]
  MOV  AX, LY
  IMUL BX
  MOV  SI, AX
  MOV  DI, DX
  MOV  AX, LX
  IMUL CX
  ADD  AX, SI
  ADC  DX, DI
  SHL  AX, 1
  RCL  DX, 1
  SHL  AX, 1
  RCL  DX, 1
  MOV  T2, DX
  MOV  AX, LX
  IMUL BX
  MOV  SI, AX
  MOV  DI, DX
  MOV  AX, LY
  IMUL CX
  SUB  AX, SI
  SBB  DX, DI
  SHL  AX, 1
  RCL  DX, 1
  SHL  AX, 1
  RCL  DX, 1
  MOV  LY, DX
  MOV  DX, T2
  MOV  LX, DX

  MOV  BX, [ViewDist]              { perspective -- the one real IDIV }
  SUB  BX, LZ
  CMP  BX, 0
  JL   @@Behind
  MOV  CX, [ProjScale]
  MOV  AX, LX
  SUB  AX, [XCentre]
  IMUL CX
  IDIV BX
  ADD  AX, 160                     { $A0 }
  MOV  DI, AX
  MOV  AX, LY
  SUB  AX, [YCentre]
  IMUL CX
  IDIV BX
  ADD  AX, 200                     { $C8 }
  MOV  BX, AX
  JMP  @@Done
@@Behind:
  MOV  DI, -1
  MOV  BX, -1
@@Done:
end;

{ --------------------------------------------------------------------------
  1139:01bb -- PlotPixel.  X in DI, Y in BX.  Clips to 0..319 by 0..399,
  looks the row up, selects the plane from X and 3, and stores colour $0E.
  -------------------------------------------------------------------------- }
procedure PlotPixel; assembler;
asm
  CMP  DI, 0
  JL   @@Out
  CMP  DI, 319
  JG   @@Out
  CMP  BX, 0
  JL   @@Out
  CMP  BX, 399
  JG   @@Out
  SHL  BX, 1
  MOV  BX, [BX + OFFSET RowOfs]
  MOV  CX, DI
  SHR  DI, 2
  ADD  DI, BX
  ADD  DI, [PageOfs]
  AND  CX, 3
  MOV  AH, 1
  SHL  AH, CL
  MOV  DX, $3C4
  MOV  AL, 2
  OUT  DX, AX
  MOV  AX, $A000
  MOV  ES, AX
  MOV  AL, DotColour
  STOSB
@@Out:
end;

{ --------------------------------------------------------------------------
  1139:02a2 -- ClearPage.  Blanks the half of each row belonging to the back
  page. Hand assembler: a REP STOSW per row with a fixed skip between them.

  Note it runs 399 rows, not 400 -- the last row of the page is never
  cleared. That is the original's count and is kept.
  -------------------------------------------------------------------------- }
procedure ClearPage; assembler;
asm
  MOV  DI, [PageOfs]    { DI := 0 or 80 -- which half of the row to clear    }
  MOV  AX, $A000
  MOV  ES, AX           { ES := video; the pages live in VRAM, not the heap  }
  MOV  DX, $3C4         { Sequencer address register                         }
  MOV  AX, $0F02        { register 2 (Map Mask) := $0F, all four planes      }
  OUT  DX, AX           { so one STOSW clears four pixels per plane at once  }
  XOR  AX, AX           { the fill value: black                              }
  MOV  DX, 399          { $18F rows                                          }
@@Row:
  MOV  CX, 40           { $28 words = 80 bytes = 320 pixels of this page     }
  REP  STOSW            { blank the row; DI advances 80                      }
  ADD  DI, 80           { $50: step over the OTHER page's half of the row    }
  DEC  DX               { one row done                                       }
  JNZ  @@Row
end;

{ --------------------------------------------------------------------------
  ModeX_FlipPage (1139:02c3)
  Show the page we just drew, then make the other one current.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  1139:02c3 -- FlipPage.  Points the CRTC at the page just drawn, then swaps
  PageOfs so the next frame draws into the other one.

  The two pages are the left and right halves of a 640-pixel logical line, so
  "flipping" is just moving the display start 80 bytes along the row.
  -------------------------------------------------------------------------- }
procedure FlipPage; assembler;
asm
  MOV  BX, [PageOfs]    { BX := the offset of the page just drawn            }
  MOV  AH, BH           { high byte of the start address                     }
  MOV  AL, $0C          { CRTC register $0C: start address HIGH              }
  MOV  DX, $3D4
  OUT  DX, AX           { write index and value in one 16-bit OUT            }
  MOV  AH, BL           { low byte of the start address                      }
  MOV  AL, $0D          { CRTC register $0D: start address LOW               }
  MOV  DX, $3D4
  OUT  DX, AX
  MOV  AX, 80           { $50 -- the other page                              }
  SUB  AX, BX           { 80 - PageOfs toggles between 0 and 80              }
  MOV  [PageOfs], AX    { next frame draws into whichever was just shown     }
end;

{ --------------------------------------------------------------------------
  Morph_DrawShape (1139:01f9) -- draw one shape straight.

  ASSETS  The shapes are compiled into the EXE, not in NEUROSIS.DAT.
          Extracted from DGROUP to:
            assets/part003/shape_sphere.bin / .png    DS:$0636
            assets/part003/shape_cube.bin   / .png    DS:$5136
            assets/part003/shape_grid.bin   / .png    DS:$63F6
          765 points x 6 bytes, three signed words (X, Y, Z).
          The .png files are previews rendered with the constants below.
          See docs/08-part3-scene3-morph.md.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  1139:01f9 -- DrawShape.  Reads CurShape, walks 765 points six bytes at a
  time and hands each to TransformPoint in BX, CX, DX, whose results go
  straight on to PlotPixel in DI and BX. Assembler in the original; the
  register hand-off between the three is the whole reason.
  -------------------------------------------------------------------------- }
procedure DrawShape; assembler;
asm
  MOV  SI, [CurShape]
  MOV  WORD PTR [Count], 765       { $2FD }
@@Point:
  PUSH SI
  MOV  BX, [SI]
  MOV  CX, [SI+2]
  MOV  DX, [SI+4]
  CALL TransformPoint
  CALL PlotPixel
  POP  SI
  ADD  SI, 6
  DEC  WORD PTR [Count]
  JNZ  @@Point
end;

{ --------------------------------------------------------------------------
  1139:021d -- DrawMorph.

      if MorphStep > MorphSteps then CurShape := MorphTo ; DrawShape
      else  blend 765 points and Inc(MorphStep)

  Each component is `AX := B-A ; CWD ; IMUL MorphStep ; IDIV MorphSteps ;
  ADD AX,A` -- a 32-bit intermediate between the multiply and the divide.
  -------------------------------------------------------------------------- }
procedure DrawMorph; assembler;
asm
  MOV  BX, [MorphStep]
  CMP  BX, [MorphSteps]
  JLE  @@Blend
  MOV  BX, [MorphTo]
  MOV  [CurShape], BX
  CALL DrawShape
  JMP  @@Done

@@Blend:
  MOV  WORD PTR [Count], 765
  MOV  SI, [MorphFrom]
  MOV  DI, [MorphTo]
@@Point:
  PUSH DI
  PUSH SI

  MOV  AX, [DI]
  SUB  AX, [SI]
  CWD
  IMUL WORD PTR [MorphStep]
  IDIV WORD PTR [MorphSteps]
  ADD  AX, [SI]
  MOV  BX, AX
  ADD  SI, 2
  ADD  DI, 2

  MOV  AX, [DI]
  SUB  AX, [SI]
  CWD
  IMUL WORD PTR [MorphStep]
  IDIV WORD PTR [MorphSteps]
  ADD  AX, [SI]
  MOV  CX, AX
  ADD  SI, 2
  ADD  DI, 2

  MOV  AX, [DI]
  SUB  AX, [SI]
  CWD
  IMUL WORD PTR [MorphStep]
  IDIV WORD PTR [MorphSteps]
  ADD  AX, [SI]
  MOV  DX, AX

  CALL TransformPoint
  CALL PlotPixel

  POP  SI
  POP  DI
  ADD  DI, 6
  ADD  SI, 6
  DEC  WORD PTR [Count]
  JNZ  @@Point

  INC  WORD PTR [MorphStep]
@@Done:
end;

{ --------------------------------------------------------------------------
  Morph_FadeStep (1139:0365)
  Read the whole DAC back, decrement every non-zero component by one, wait
  for retrace and write it out again -- a one-step fade toward black, called
  once per frame during the closing segment.
  -------------------------------------------------------------------------- }
procedure FadeStep;
var
  Pal : array[0..767] of Byte;
  I   : Integer;
begin
  GetPalette768(Pal);
  I := $300;
  repeat
    if Pal[I]     <> 0 then Dec(Pal[I]);
    if Pal[I - 1] <> 0 then Dec(Pal[I - 1]);
    if Pal[I - 2] <> 0 then Dec(Pal[I - 2]);
    Dec(I, 3);
  until I < 0;
  WaitRetrace;
  SetPalette768(Pal);
end;

{ --------------------------------------------------------------------------
  Morph_InitScene (1139:02fe)
  -------------------------------------------------------------------------- }
procedure InitScene;
begin
  LogicalWidth := 80;          { DS:$76B6 -- 640 logical pixels per row }
  SetMode;                     { mode 13h -> Mode-X }
  Set400Lines;                 { and now 320x400 }
  BuildModeXRows;              { 1192:0000 -- NOT VGA's BuildRowTable }
  MorphStep := 0;
  MorphSteps := 45;
  XCentre := 0;  YCentre := 0;
  ProjScale := 256;
  ViewDist  := 2500;
end;

{ --------------------------------------------------------------------------
  Demo_Scene3 (1139:03b4)

  Eight scripted segments of 45 frames (63 for the last). Odd segments hold a
  shape, even segments morph to the next one. The closing segment also fades.
  -------------------------------------------------------------------------- }
procedure Scene3;

  { one frame of the common loop; returns True if a key was pressed }
  function Frame(Morphing : Boolean) : Boolean;
  begin
    ClearPage;
    if Morphing then DrawMorph else DrawShape;
    FlipPage;
    WaitRetrace;
    StepAngles;
    Frame := KeyPressed;
  end;

  procedure Hold(N : Integer);
  begin
    Frames := N;
    repeat
      if Frame(False) then Exit;
      Dec(Frames);
    until Frames = 0;
  end;

  procedure MorphTo_(FromShape, ToShape : Word; N : Integer);
  begin
    MorphFrom := FromShape;
    MorphTo   := ToShape;
    MorphStep := 0;
    Frames    := N;
    repeat
      if Frame(True) then Exit;
      Dec(Frames);
    until Frames = 0;
    CurShape := MorphTo;
  end;

begin
  BindShapes;
  InitScene;
  PageOfs := PageOfsB;
  CurShape  := OfsSphere;
  MorphFrom := OfsSphere;
  MorphTo   := OfsCube;
  StepX := SpinX;  StepY := SpinY;  StepZ := SpinZ;
  AngX  := 0;      AngY  := 0;      AngZ  := 0;

  Hold(SegFrames);                          { 1: shape 0 }
  MorphTo_(OfsSphere, OfsCube, SegFrames);      { 2: 0 -> 4  }
  Hold(SegFrames);                          { 3: shape 4 }
  MorphTo_(OfsCube, OfsGrid, SegFrames);      { 4: 4 -> 5  }
  Hold(SegFrames);                          { 5: shape 5 }
  MorphTo_(OfsGrid, OfsCube, SegFrames);      { 6: 5 -> 4  }
  Hold(SegFrames);                          { 7: shape 4 }

  { 8: morph back to shape 0 while fading the palette out }
  MorphFrom := OfsCube;
  MorphTo   := OfsSphere;
  MorphStep := 0;
  Frames    := LastFrames;
  repeat
    FadeStep;
    if Frame(True) then Exit;
    Dec(Frames);
  until Frames = 0;
end;

end.

{ ===========================================================================
  HAND-WRITTEN ASSEMBLER IN THIS SCENE

  * VGA_SetPalette768 (1139:0335) -- LDS SI / MOV CX,$300 / REP OUTSB. The
    whole DAC written with one string instruction; unmistakably asm.
  * VGA_GetPalette768 (1139:034d) -- the matching read.
  * VGA_Set400Lines (1139:02f2) -- bare CRTC read-modify-write.
  * Morph_TransformPoint (1139:0096) takes its arguments in BX/CX/DX and
    leaves results in DI/BX for the plotter, which is not a Pascal calling
    convention -- this is an asm routine, and the Pascal above is a
    behavioural description of it rather than a literal translation.
  * ModeX_PlotPixel (1139:01bb) likewise consumes DI/BX directly.

  RESOLVED VALUES
    view distance 2500 ($BEB4)   projection scale 256 ($BEB2)
    spin 3 deg/frame on all three axes    segment 45 frames, closing 63
    morph length 45 steps        dot colour $0E     angle wrap 360

  VERIFIED BY RENDERING
  * Extracting the vertex data straight from DGROUP and projecting it with
    the constants above produces a recognisable dotted sphere (slot 0), cube
    (slot 4) and flat grid (slot 5) -- see work/assets/003_shape*.png. That
    independently confirms the record layout, the shape base addresses, the
    slot spacing, the view distance and the projection scale.

  RESOLVED
  * 1192:0000 is VGA_BuildRowTable, part of the VGA unit rather than this
    scene: RowOfs[i] := 160 * i for i = 0..799, at DS:$BEC6. The multiplier is
    the byte at DS:$76B6 (= 80, the Mode-X plane stride for 320 pixels) shifted
    left once. A 160-byte row stride is 640 pixels in Mode-X, and 400 such rows
    are exactly 64,000 bytes -- one full plane. See docs/05-vga-unit.md.
  * Shape slots 1, 2 and 3 exist in DGROUP but are unused by this scene. The
    three that ARE used (Sphere, Cube, Grid) are emitted in gen/P3SHAPE.INC.

  * Morph_DrawMorph is now transcribed rather than described. The blend is
    integer linear interpolation, P := A + (B - A) * Step div Steps, done with
    IMUL/IDIV through a 32-bit intermediate -- no floating point anywhere in
    the morph. Coordinates reach Morph_TransformPoint in BX, CX and DX, so it
    is a register-convention call in the original. DrawMorph is Pascal here.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
