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

uses VGA, ModeX, Crt;

const
  NumPoints  = 765;        { $2FD -- points actually DRAWN per shape }
  ShapeSlots = 800;        { and the slot is bigger than that: the six
                             shape blocks are contiguous and 4,800 bytes
                             apart, $0636 + 4 * 4800 = $5136 = ShapeCube }
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
  TShape = array[1..ShapeSlots, 1..3] of Integer;

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

  { [inferred] The shape currently being drawn. The original addresses shapes
    by their DGROUP offset (CurShape, MorphFrom, MorphTo are Words holding
    $0636, $5136, $63F6) and walks them with pointer arithmetic; a working
    copy is the readable equivalent. }
{$I gen/P3SHAPE.INC}     { const ShapeSphere, ShapeCube, ShapeGrid : TShape }

var
  { The rotation's sines and cosines. COSINE FIRST IN EACH PAIR: the recorded
    addresses are SinX $BE92 / CosX $BE90 and SinY $BE96 / CosY $BE94, so the
    cosine is the lower of the two and the declarations were the wrong way
    round. Z is the other way about, and that is not a slip -- $BE98 is SinZ
    and $BE9A is CosZ. }
  CosX, SinX          : Integer;   { DS:$BE90, $BE92 }
  CosY, SinY          : Integer;   { DS:$BE94, $BE96 }
  SinZ, CosZ          : Integer;   { DS:$BE98, $BE9A }

  AngX, AngY, AngZ    : Integer;   { DS:$BE9C, $BE9E, $BEA0 }
  StepX, StepY, StepZ : Integer;   { DS:$BEA2, $BEA4, $BEA6 }

  { SIX BYTES OF SCRATCH, and the name they used to carry was wrong. The
    original uses $BEA8 and $BEAA as DX SPILLS -- 1139:0111 and 015b are
    `MOV [$BEA8],DX`, 1139:0132 and 017c read it back, and 00c7/00e8 do the
    same with $BEAA -- so they are working storage for a routine between
    SetAngles and DrawShape, not the shape offsets this once called them.
    $BEAC is never referenced at all.

    They are still declared, because the original really has six bytes here and
    removing them moves every variable above. What they are FOR is now read
    correctly; what the routine that spills into them is doing is not yet. }
  { AND TWO OF THE THREE ARE TransformPoint's T2 AND T1. 1139:00c5 stores DX to
    $BEAA and 1139:010f to $BEA8 -- the two scratch words the routine keeps its
    shifted high halves in -- and this unit was declaring them TWICE: three
    unreferenced Scratch words here at the right addresses, and a separate
    `var T1, T2` block further down whose own comment already said
    "DS:$BEAA and DS:$BEA8". Declared after Count they landed at $BEC6 and
    $BEC8, and every reference from $C506 up carried the four bytes -- which is
    the +4 dsmap has been reporting across fifty-three sites in this part.

    T2 first, because declaration order runs upward and 1139:010f is the store
    to the lower address. $BEAC really is never referenced. }
  T2, T1    : Integer;                   { DS:$BEA8, $BEAA }
  Scratch3  : Word;                      { DS:$BEAC, never referenced }

  { [transcribed] The projection centre. Morph_InitScene zeroes both before the
    first shape and they stay put for this scene. }
  XCentre, YCentre    : Integer;   { DS:$BEAE, $BEB0 }

  { PLAIN VARS, not typed constants, and their own addresses prove it: the
    original has these three above the end of its initialised data at $9F20,
    so they cannot be stored, and it writes all three as immediates inside
    Morph_InitScene. Declared as typed constants they went into the
    initialised region instead -- six bytes in the wrong half of DGROUP. }
  ProjScale           : Integer;   { DS:$BEB2 -- 1139:0328 sets it to 256 }
  ViewDist            : Integer;   { DS:$BEB4 -- 1139:032e sets it to 2500 }
  MorphSteps          : Integer;   { DS:$BEB6 -- 1139:0316 sets it to 45 }

  MorphStep           : Integer;   { DS:$BEB8 }
  CurShape            : Word;      { DS:$BEBA -- shape being drawn }
  MorphFrom, MorphTo  : Word;      { DS:$BEBC, $BEBE }
  PageOfs             : Word;      { DS:$BEC0 -- 0 or 80 }
  Frames              : Integer;   { DS:$BEC2 }
  Count               : Word;      { DS:$BEC4 -- the point counter }

{ BindShapes IS GONE. It filled three Words with Ofs() of the shape tables and
  the original has no such routine -- the addresses it was reading are DX spills
  (see the var block), and the original's own Scene3 gets the offsets as OFFSET
  inside an asm block, which is both the right immediate and the reference that
  keeps the tables in DGROUP. Removing the call took 32 bytes out and left the
  initialised image identical. }

{ --------------------------------------------------------------------------
  1139:034d -- GetPalette768(var P)

  Hand assembler. The whole DAC comes back in a single REP INSB rather than a
  counted loop, which is why there is no loop here to transcribe.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C7] := 0;
      for I := 0 to 767 do B[I] := Port[$3C9];
  -------------------------------------------------------------------------- }
{ @asm 003 1139:0000 ? }
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

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      AngX := Wrap(AngX + StepX);       -- Wrap: +360 if < 0, -360 if > 360
      AngY := Wrap(AngY + StepY);
      AngZ := Wrap(AngZ + StepZ);
      SetAngles(AngX, AngY, AngZ);
  -------------------------------------------------------------------------- }
{ @asm 003 1139:0035 }
procedure StepAngles; assembler;
asm
  MOV  BX, [AngX]                { BX := the X angle                        }
  ADD  BX, [StepX]               { advance it by this scene's step          }
  CMP  BX, 0                     { did it go negative?                      }
  JGE  @@XNotNeg                 {   no                                     }
  ADD  BX, 360                   {   yes: wrap up one turn                  }
@@XNotNeg:                       { <- the not-negative case joins here      }
  CMP  BX, 360                   { did it pass a full turn?                 }
  JLE  @@XDone                   {   no                                     }
  SUB  BX, 360                   {   yes: wrap down one turn                }
@@XDone:                         { <- both cases join here                  }
  MOV  [AngX], BX                { store back, and leave it in BX           }

  MOV  CX, [AngY]                { the Y angle, kept in CX                  }
  ADD  CX, [StepY]               { advance it -- DS:$BEA4                   }
  CMP  CX, 0                     { negative?                                }
  JGE  @@YNotNeg                 {   no                                     }
  ADD  CX, 360                   {   yes: wrap up one turn                  }
@@YNotNeg:                       { <- joins here                            }
  CMP  CX, 360                   { past a full turn?                        }
  JLE  @@YDone                   {   no                                     }
  SUB  CX, 360                   {   yes: wrap down one turn                }
@@YDone:                         { <- joins here                            }
  MOV  [AngY], CX                { store back -- DS:$BE9E -- and keep in CX }

  MOV  DX, [AngZ]                { the Z angle, kept in DX                  }
  ADD  DX, [StepZ]               { advance it -- DS:$BEA6                   }
  CMP  DX, 0                     { negative?                                }
  JGE  @@ZNotNeg                 {   no                                     }
  ADD  DX, 360                   {   yes: wrap up one turn                  }
@@ZNotNeg:                       { <- joins here                            }
  CMP  DX, 360                   { past a full turn?                        }
  JLE  @@ZDone                   {   no                                     }
  SUB  DX, 360                   {   yes: wrap down one turn                }
@@ZDone:                         { <- joins here                            }
  MOV  [AngZ], DX                { store back -- DS:$BEA0 -- and keep in DX }

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

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      T := (Z * SinX + Y * CosX) sar 14;      -- about the first axis
      U := (Z * CosX - Y * SinX) sar 14;
      V := (X * CosY - U * SinY) sar 14;      -- second
      U := (U * CosY + X * SinY) sar 14;
      X := (V * CosZ + T * SinZ) sar 14;      -- third
      Y := (T * CosZ - V * SinZ) sar 14;
      D := ViewDist - U;
      if D >= 0 then
      begin
        SX := (X - XCentre) * ProjScale div D + 160;
        SY := (Y - YCentre) * ProjScale div D + 200;
      end
      else begin SX := -1; SY := -1 end;

  It cannot actually be written that way and still work: the inputs arrive in
  registers and the results leave in them, and Turbo Pascal has no `sar` --
  its `shr` on a LongInt is a LOGICAL shift, where SHL/RCL keeping DX is an
  arithmetic one.
  -------------------------------------------------------------------------- }
{ @asm 003 1139:0096 ? }
procedure TransformPoint; assembler;
var
  LX, LY, LZ : Integer;            { [BP-2], [BP-4], [BP-6] -- and THAT IS
                                     ALL: the original's frame is ENTER 6,
                                     three words. T1 and T2 are not locals,
                                     they are the DGROUP globals below --
                                     1139:00b8 is MOV [BEAA],DX, a memory
                                     store, not MOV [BP-8],DX. }
asm
  MOV  LX, BX                      { the caller left X in BX                 }
  MOV  LY, CX                      { Y in CX                                 }
  MOV  LZ, DX                      { Z in DX -- all three now in the frame   }

  { ---- first axis: rotate Y and Z about X ---- }
  MOV  CX, [CosX]                  { CX := cos(AngX), 16.14  -- DS:$BE90     }
  MOV  BX, [SinX]                  { BX := sin(AngX)         -- DS:$BE92     }
  MOV  AX, LY                      { AX := Y                                 }
  IMUL CX                          { DX:AX := Y * cos, 32 bits signed        }
  MOV  SI, AX                      { stash the low half                      }
  MOV  DI, DX                      { and the high half                       }
  MOV  AX, LZ                      { AX := Z                                 }
  IMUL BX                          { DX:AX := Z * sin                        }
  ADD  AX, SI                      { add the stashed product back in,        }
  ADC  DX, DI                      {   full 32 bits: Y*cos + Z*sin           }
  SHL  AX, 1                       { shift the 32-bit value left one bit...  }
  RCL  DX, 1                       {   ...carrying into the high word        }
  SHL  AX, 1                       { and again, so the product is now x4     }
  RCL  DX, 1                       {                                         }
  MOV  T1, DX                      { keeping DX alone is >>16 on the x4      }
                                   {   value, i.e. an ARITHMETIC >>14        }
  MOV  AX, LY                      { AX := Y again                           }
  IMUL BX                          { DX:AX := Y * sin                        }
  MOV  SI, AX                      { stash it                                }
  MOV  DI, DX                      {                                         }
  MOV  AX, LZ                      { AX := Z                                 }
  IMUL CX                          { DX:AX := Z * cos                        }
  SUB  AX, SI                      { subtract the stashed product,           }
  SBB  DX, DI                      {   32 bits: Z*cos - Y*sin                }
  SHL  AX, 1                       { x4 again...                             }
  RCL  DX, 1                       {                                         }
  SHL  AX, 1                       {                                         }
  RCL  DX, 1                       {                                         }
  MOV  LZ, DX                      { Z := (Z*cos - Y*sin) >> 14              }
  MOV  DX, T1                      { fetch the first result back             }
  MOV  LY, DX                      { Y := (Y*cos + Z*sin) >> 14              }

  { ---- second axis: rotate Z and X about Y ---- }
  MOV  CX, [CosY]                  { CX := cos(AngY)         -- DS:$BE94     }
  MOV  BX, [SinY]                  { BX := sin(AngY)         -- DS:$BE96     }
  MOV  AX, LZ                      { AX := the Z from the first rotation     }
  IMUL BX                          { DX:AX := Z * sin                        }
  MOV  SI, AX                      { stash it                                }
  MOV  DI, DX                      {                                         }
  MOV  AX, LX                      { AX := X                                 }
  IMUL CX                          { DX:AX := X * cos                        }
  SUB  AX, SI                      { X*cos - Z*sin,                          }
  SBB  DX, DI                      {   32 bits                               }
  SHL  AX, 1                       { x4...                                   }
  RCL  DX, 1                       {                                         }
  SHL  AX, 1                       {                                         }
  RCL  DX, 1                       {                                         }
  MOV  T2, DX                      { ...and keep the high word: >>14         }
  MOV  AX, LX                      { AX := X again                           }
  IMUL BX                          { DX:AX := X * sin                        }
  MOV  SI, AX                      { stash it                                }
  MOV  DI, DX                      {                                         }
  MOV  AX, LZ                      { AX := Z                                 }
  IMUL CX                          { DX:AX := Z * cos                        }
  ADD  AX, SI                      { Z*cos + X*sin,                          }
  ADC  DX, DI                      {   32 bits                               }
  SHL  AX, 1                       { x4...                                   }
  RCL  DX, 1                       {                                         }
  SHL  AX, 1                       {                                         }
  RCL  DX, 1                       {                                         }
  MOV  LZ, DX                      { Z := (Z*cos + X*sin) >> 14              }
  MOV  DX, T2                      { fetch the first result back             }
  MOV  LX, DX                      { X := (X*cos - Z*sin) >> 14              }

  { ---- third axis: rotate X and Y about Z ---- }
  MOV  CX, [CosZ]                  { CX := cos(AngZ)         -- DS:$BE98     }
  MOV  BX, [SinZ]                  { BX := sin(AngZ)         -- DS:$BE9A     }
  MOV  AX, LY                      { AX := Y                                 }
  IMUL BX                          { DX:AX := Y * sin                        }
  MOV  SI, AX                      { stash it                                }
  MOV  DI, DX                      {                                         }
  MOV  AX, LX                      { AX := X                                 }
  IMUL CX                          { DX:AX := X * cos                        }
  ADD  AX, SI                      { X*cos + Y*sin,                          }
  ADC  DX, DI                      {   32 bits                               }
  SHL  AX, 1                       { x4...                                   }
  RCL  DX, 1                       {                                         }
  SHL  AX, 1                       {                                         }
  RCL  DX, 1                       {                                         }
  MOV  T2, DX                      { ...high word only: >>14                 }
  MOV  AX, LX                      { AX := X again                           }
  IMUL BX                          { DX:AX := X * sin                        }
  MOV  SI, AX                      { stash it                                }
  MOV  DI, DX                      {                                         }
  MOV  AX, LY                      { AX := Y                                 }
  IMUL CX                          { DX:AX := Y * cos                        }
  SUB  AX, SI                      { Y*cos - X*sin,                          }
  SBB  DX, DI                      {   32 bits                               }
  SHL  AX, 1                       { x4...                                   }
  RCL  DX, 1                       {                                         }
  SHL  AX, 1                       {                                         }
  RCL  DX, 1                       {                                         }
  MOV  LY, DX                      { Y := (Y*cos - X*sin) >> 14              }
  MOV  DX, T2                      { fetch the first result back             }
  MOV  LX, DX                      { X := (X*cos + Y*sin) >> 14              }

  { ---- perspective: the one real divide in the whole frame path ---- }
  MOV  BX, [ViewDist]              { BX := 2500              -- DS:$BEB4     }
  SUB  BX, LZ                      { BX := the point's distance from the eye }
  CMP  BX, 0                       { has it gone behind us?                  }
  JL   @@Behind                    {   yes -- there is no projection for it  }
  MOV  CX, [ProjScale]             { CX := 256               -- DS:$BEB2     }
  MOV  AX, LX                      { AX := the rotated X                     }
  SUB  AX, [XCentre]               { measure it from the object's own centre }
  IMUL CX                          { DX:AX := that * 256, 32 bits            }
  IDIV BX                          { AX := divided by the distance -- signed }
  ADD  AX, 160                     { $A0 -- half of the 320-pixel page       }
  MOV  DI, AX                      { DI := screen X, for PlotPixel           }
  MOV  AX, LY                      { AX := the rotated Y                     }
  SUB  AX, [YCentre]               { from the object's centre                }
  IMUL CX                          { DX:AX := that * 256                     }
  IDIV BX                          { AX := divided by the same distance      }
  ADD  AX, 200                     { $C8 -- half of the 400-line page        }
  MOV  BX, AX                      { BX := screen Y, for PlotPixel           }
  JMP  @@Done                      { skip the off-screen case                }
@@Behind:                          { <- the point is behind the viewer       }
  MOV  DI, -1                      { an X PlotPixel's bounds test rejects    }
  MOV  BX, -1                      { and a Y likewise                        }
@@Done:                            { <- both cases leave DI and BX set       }
end;

{ --------------------------------------------------------------------------
  1139:01bb -- PlotPixel.  X in DI, Y in BX.  Clips to 0..319 by 0..399,
  looks the row up, selects the plane from X and 3, and stores colour $0E.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if (X >= 0) and (X <= 319) and (Y >= 0) and (Y <= 399) then
      begin
        PortW[$3C4] := (($01 shl (X and 3)) shl 8) or 2;
        Mem[$A000 : (X shr 2) + RowOfs[Y] + PageOfs] := $0E;
      end;
  -------------------------------------------------------------------------- }
{ @asm 003 1139:01bb }
procedure PlotPixel; assembler;
asm
  CMP  DI, 0            { X off the left?                                    }
  JL   @@Out            {   drop the point                                   }
  CMP  DI, 319          { X off the right? ($13F)                            }
  JG   @@Out            {   drop it                                          }
  CMP  BX, 0            { Y above the page?                                  }
  JL   @@Out            {   drop it                                          }
  CMP  BX, 399          { Y below it? ($18F -- 400 lines, not 200)           }
  JG   @@Out            {   drop it                                          }
  SHL  BX, 1            { BX := Y * 2, a word index into the row table       }
  MOV  BX, [BX + OFFSET RowOfs]   { BX := RowOfs[Y] -- DS:$BEC6, Y*160       }
  MOV  CX, DI           { keep a copy of X: the plane number comes from it   }
  SHR  DI, 2            { X div 4 -- Mode X puts every 4th pixel in a plane, }
                        {   so the byte offset within the row is X shr 2     }
  ADD  DI, BX           { + the row's own offset                             }
  ADD  DI, [PageOfs]    { + 0 or 80, whichever page is being drawn           }
  AND  CX, 3            { CL := X mod 4 = which of the four planes           }
  MOV  AH, 1            { one bit...                                         }
  SHL  AH, CL           {   ...shifted to that plane's position in the mask  }
  MOV  DX, $3C4         { Sequencer address register                         }
  MOV  AL, 2            { register 2 -- Map Mask                             }
  OUT  DX, AX           { index in AL, value in AH, one 16-bit OUT           }
  MOV  AX, $A000        { video memory                                       }
  MOV  ES, AX           { ES:DI now addresses the pixel                      }
  MOV  AL, DotColour    { $0E -- yellow                                      }
  STOSB                 { write it; only the enabled plane takes it          }
@@Out:                  { <- every clipped case lands here and returns       }
end;

{ --------------------------------------------------------------------------
  1139:02a2 -- ClearPage.  Blanks the half of each row belonging to the back
  page. Hand assembler: a REP STOSW per row with a fixed skip between them.

  Note it runs 399 rows, not 400 -- the last row of the page is never
  cleared. That is the original's count and is kept.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      P := PageOfs;
      PortW[$3C4] := $0F02;
      for Y := 1 to 399 do
      begin
        for I := 1 to 40 do  MemW[$A000 : P] := 0, then Inc(P, 2);
        Inc(P, 80);
      end;
  -------------------------------------------------------------------------- }
{ @asm 003 1139:01f9 }
procedure DrawShape; assembler;
asm
  MOV  SI, [CurShape]              { DS:$BEBA -- the shape's DGROUP offset   }
  MOV  WORD PTR [Count], 765       { $2FD points -- DS:$BEC4                 }
@@Point:                           { <- once per point                       }
  PUSH SI                          { TransformPoint clobbers SI, so save it  }
  MOV  BX, [SI]                    { BX := X, the first word of the record   }
  MOV  CX, [SI+2]                  { CX := Y                                 }
  MOV  DX, [SI+4]                  { DX := Z -- the register convention      }
  CALL TransformPoint              { rotate and project: out in DI and BX    }
  CALL PlotPixel                   { plot it straight from those registers   }
  POP  SI                          { get the record pointer back             }
  ADD  SI, 6                       { three signed words per point            }
  DEC  WORD PTR [Count]            { one point done                          }
  JNZ  @@Point                     { round again until all 765 are drawn     }
end;

{ --------------------------------------------------------------------------
  1139:021d -- DrawMorph.

      if MorphStep > MorphSteps then CurShape := MorphTo ; DrawShape
      else  blend 765 points and Inc(MorphStep)

  Each component is `AX := B-A ; CWD ; IMUL MorphStep ; IDIV MorphSteps ;
  ADD AX,A` -- a 32-bit intermediate between the multiply and the divide.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      if MorphStep > MorphSteps then
      begin
        CurShape := MorphTo;  DrawShape;  Exit;
      end;
      A := Ptr(DSeg, MorphFrom);  B := Ptr(DSeg, MorphTo);
      for I := 1 to 765 do
        PlotPixel(TransformPoint(
          A^[I,k] + LongInt(B^[I,k] - A^[I,k]) * MorphStep div MorphSteps
          for k = 1, 2, 3));
      Inc(MorphStep);
  -------------------------------------------------------------------------- }
{ @asm 003 1139:021d ? }
procedure DrawMorph; assembler;
asm
  MOV  BX, [MorphStep]             { DS:$BEB8 -- how far through the blend   }
  CMP  BX, [MorphSteps]            { DS:$BEB6 -- 45 steps in all             }
  JLE  @@Blend                     { still blending: go and interpolate      }
  MOV  BX, [MorphTo]               { finished: the destination shape wins    }
  MOV  [CurShape], BX              { -> DS:$BEBA                             }
  CALL DrawShape                   { and draw it straight, no blending       }
  JMP  @@Done                      { nothing else to do this frame           }

@@Blend:                           { <- the interpolating case               }
  MOV  WORD PTR [Count], 765       { $2FD points -- DS:$BEC4                 }
  MOV  SI, [MorphFrom]             { DS:$BEBC -- the shape being left        }
  MOV  DI, [MorphTo]               { DS:$BEBE -- the shape being approached  }
@@Point:                           { <- once per point                       }
  PUSH DI                          { both walkers are clobbered by the calls }
  PUSH SI                          {   below, so save them                   }

  MOV  AX, [DI]                    { AX := the destination X                 }
  SUB  AX, [SI]                    { AX := destination - source, the span    }
  CWD                              { sign-extend it into DX:AX               }
  IMUL WORD PTR [MorphStep]        { DX:AX := span * step, 32 bits wide      }
  IDIV WORD PTR [MorphSteps]       { AX := that / 45 -- the fraction covered }
  ADD  AX, [SI]                    { AX := source + it = the blended X       }
  MOV  BX, AX                      { BX is where TransformPoint wants X      }
  ADD  SI, 2                       { step both walkers on to Y               }
  ADD  DI, 2                       {                                         }

  MOV  AX, [DI]                    { AX := the destination Y                 }
  SUB  AX, [SI]                    { the span                                }
  CWD                              { sign-extend                             }
  IMUL WORD PTR [MorphStep]        { * step                                  }
  IDIV WORD PTR [MorphSteps]       { / 45                                    }
  ADD  AX, [SI]                    { + source = the blended Y                }
  MOV  CX, AX                      { CX is where TransformPoint wants Y      }
  ADD  SI, 2                       { step both walkers on to Z               }
  ADD  DI, 2                       {                                         }

  MOV  AX, [DI]                    { AX := the destination Z                 }
  SUB  AX, [SI]                    { the span                                }
  CWD                              { sign-extend                             }
  IMUL WORD PTR [MorphStep]        { * step                                  }
  IDIV WORD PTR [MorphSteps]       { / 45                                    }
  ADD  AX, [SI]                    { + source = the blended Z                }
  MOV  DX, AX                      { DX is where TransformPoint wants Z      }
  { A THIRD ADVANCE, AND IT IS DEAD. 1139:0283 is ADD SI,2 / ADD DI,2
    immediately before the two calls, and the POP SI / POP DI after them puts
    both walkers back regardless -- so stepping them here changes nothing. It is
    what the original does: three identical blocks, each ending with the
    register store and the step, rather than two steps and a bare store. }
  ADD  SI, 2                       { 1139:0283                               }
  ADD  DI, 2                       { 1139:0286                               }

  CALL TransformPoint              { rotate and project: out in DI and BX    }
  CALL PlotPixel                   { plot it straight from those registers   }

  POP  SI                          { the walkers back, still on this point's }
  POP  DI                          {   first word                            }
  ADD  DI, 6                       { three signed words per point            }
  ADD  SI, 6                       {                                         }
  DEC  WORD PTR [Count]            { one point done                          }
  JNZ  @@Point                     { round again until all 765 are drawn     }

  INC  WORD PTR [MorphStep]        { one step further along the blend        }
@@Done:                            { <- both cases return from here          }
end;

{ --------------------------------------------------------------------------
  Morph_FadeStep (1139:0365)
  Read the whole DAC back, decrement every non-zero component by one, wait
  for retrace and write it out again -- a one-step fade toward black, called
  once per frame during the closing segment.
  -------------------------------------------------------------------------- }

{ @asm 003 1139:02a2 }
procedure ClearPage; assembler;
asm
  MOV  DI, [PageOfs]    { DI := 0 or 80 -- which half of the row to clear    }
  MOV  AX, $A000        { video memory                                       }
  MOV  ES, AX           { ES := video; the pages live in VRAM, not the heap  }
  MOV  DX, $3C4         { Sequencer address register                         }
  MOV  AX, $0F02        { register 2 (Map Mask) := $0F, all four planes      }
  OUT  DX, AX           { so one STOSW clears four pixels per plane at once  }
  XOR  AX, AX           { the fill value: black                              }
  MOV  DX, 399          { $18F rows -- one short of the page, see above      }
@@Row:                  { <- once per row                                    }
  MOV  CX, 40           { $28 words = 80 bytes = 320 pixels of this page     }
  REP  STOSW            { blank the row; DI advances 80                      }
  ADD  DI, 80           { $50: step over the OTHER page's half of the row    }
  DEC  DX               { one row done                                       }
  JNZ  @@Row            { round again until all 399 are clear                }
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

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3D4] := $0C;  Port[$3D5] := Hi(PageOfs);
      Port[$3D4] := $0D;  Port[$3D5] := Lo(PageOfs);
      PageOfs := 80 - PageOfs;
  -------------------------------------------------------------------------- }
{ @asm 003 1139:02c3 }
procedure FlipPage; assembler;
asm
  MOV  BX, [PageOfs]    { BX := the offset of the page just drawn            }
  MOV  AH, BH           { high byte of the start address                     }
  MOV  AL, $0C          { CRTC register $0C: start address HIGH              }
  MOV  DX, $3D4         { CRTC address register                              }
  OUT  DX, AX           { write index and value in one 16-bit OUT            }
  MOV  AH, BL           { low byte of the start address                      }
  MOV  AL, $0D          { CRTC register $0D: start address LOW               }
  MOV  DX, $3D4         { CRTC address register again                        }
  OUT  DX, AX           { and the second half of the start address           }
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
  Morph_CheckKey (1139:02e0) -- ASSEMBLER, AND IT RETURNS IN DX.

  The scene tests for a key through its own routine and not through Crt's
  KeyPressed directly: 1139:040a is a NEAR call and CALLF never appears in the
  eight loops. So there is a routine of this unit's own in between.

  TWO THINGS ABOUT IT ARE NOT PASCAL, and both were visible for weeks.

  IT HAS NO STACK FRAME. 1139:02e0 is the far call itself -- no PUSH BP, no
  MOV BP,SP, and a bare RET at 02f1 with no LEAVE. A compiled procedure gets
  the frame whether or not it has locals; only `assembler` omits it.

  AND IT ANSWERS IN DX. Turbo Pascal returns a Boolean in AL, a word in AX, a
  LongInt or a pointer in DX:AX -- and nothing at all in DX alone. The
  MOV DX,0 / MOV DX,1 pair here, and the OR DX,DX that Scene3 tests it with,
  appear EXACTLY ONCE in the whole demo: this routine and its callers. Every
  part carries the runtime's own AL form of the same shape, which is what made
  the DX form look like a decoding mistake rather than a finding.

  So it is the author's own calling convention, and the callers are asm because
  nothing else can read it. That is why this and Scene3 had to change together:
  making this `assembler` on its own leaves the callers testing AL, and the
  measurement gets WORSE rather than better.

  The declared result type stays Boolean because that is what the routine
  MEANS; nothing reads AL, so nothing depends on Turbo Pascal's idea of where
  the answer goes.
  -------------------------------------------------------------------------- }
function CheckKey : Boolean; assembler;
asm
        CALL    KeyPressed              { 1139:02e0 -- far, into Crt          }
        OR      AL,AL                   { 02e5 -- Crt's answer IS in AL       }
        JNE     @@Yes                   { 02e7                                }
        MOV     DX,0                    { 02e9                                }
        JMP     @@Out                   { 02ec                                }
@@Yes:  MOV     DX,1                    { 02ee                                }
@@Out:                                  { 02f1 is the RET Turbo Pascal adds   }
end;

{ --------------------------------------------------------------------------
  1139:01f9 -- DrawShape.  Reads CurShape, walks 765 points six bytes at a
  time and hands each to TransformPoint in BX, CX, DX, whose results go
  straight on to PlotPixel in DI and BX. Assembler in the original; the
  register hand-off between the three is the whole reason.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      S := Ptr(DSeg, CurShape);
      for I := 1 to 765 do
        PlotPixel(TransformPoint(S^[I,1], S^[I,2], S^[I,3]));
  -------------------------------------------------------------------------- }
{ @asm 003 1139:02f2 }
procedure Set400Lines; assembler;
asm
  MOV  DX, $3D4     { $3D4 is the CRTC index register                        }
  MOV  AL, 9        { register 9 -- Maximum Scan Line                        }
  OUT  DX, AL       { select it                                              }
  INC  DX           { DX := $3D5, the CRTC data register                     }
  IN   AL, DX       { read what is in register 9 now                         }
  AND  AL, $E0      { keep bits 5-7, clear the repeat count in bits 0-4      }
  OUT  DX, AL       { write it back -- no double scan, so 400 lines          }
end;

{ --------------------------------------------------------------------------
  1139:0000 -- SetAngles.  AngX in BX, AngY in CX, AngZ in DX.

  Hand assembler, reached by a plain CALL from StepAngles with the angles
  already in registers. One table serves both functions: cos(a) is sin(a+90),
  so the cosine lookup is the same table 90 entries -- 180 bytes -- further
  along. That is why the original quotes two base addresses, $02A8 and $035C,
  for one table. No trig call anywhere in the frame path.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      SinX := SinTab[AngX];  CosX := SinTab[AngX + 90];
      SinY := SinTab[AngY];  CosY := SinTab[AngY + 90];
      SinZ := SinTab[AngZ];  CosZ := SinTab[AngZ + 90];
  -------------------------------------------------------------------------- }
{ HAND ASSEMBLER, and the frame is what proves it. 1139:0334 is a bare `C3`:
  no LEAVE, no POP BP, and therefore no prologue either. Turbo Pascal emits a
  frame for EVERY Pascal procedure whatever its contents -- measured in
  probe/ZEROSTOR.PAS, where a procedure with no parameters and no locals still
  gets one, near or far, under $G- (`55 89E5 ... 5D`) and under $G+
  (`... C9`). An `assembler` procedure with neither is the only shape that has
  none.

  IT ALSO EXPLAINS THE ZERO STORES. 1139:0310, 031c and 0322 write zero as
  `MOV WORD PTR [x],0`, six bytes, where Pascal writes `XOR AX,AX / MOV [x],AX`,
  five. The probe eliminated every source-level explanation for that -- the
  compiler version, Word against Integer, a named `= 0` constant, interleaving
  with non-zero stores, the LongInt high-word case, and an array element or
  record field as the target. Hand-written asm needs none of them: the author
  wrote the store and BASM assembled it.

  AND IT DOES NOT CALL BindShapes. The original's first instruction is the
  LogicalWidth store; there is no call ahead of it, and there is no BindShapes
  in this unit any more either.

  FOR REFERENCE ONLY, the equivalent Pascal -- not what the binary does:
    LogicalWidth := 80;  SetModeX;  Set400Lines;  ModeX.BuildRowTable;
    MorphStep := 0;  MorphSteps := 45;  XCentre := 0;  YCentre := 0;
    ProjScale := 256;  ViewDist := 2500; }
procedure InitScene; assembler;
asm
  MOV  LogicalWidth, 80          { 1139:02fe  640 logical pixels per row }
  CALL SetModeX                  { 1139:0303  1192:002a, mode 13h -> Mode-X }
  CALL Set400Lines               { 1139:0308  near, and now 320x400 }
  CALL ModeX.BuildRowTable       { 1139:030b  1192:0000, NOT VGA's }
  MOV  WORD PTR MorphStep,  0    { 1139:0310 }
  MOV  WORD PTR MorphSteps, 45   { 1139:0316 }
  MOV  WORD PTR XCentre,    0    { 1139:031c }
  MOV  WORD PTR YCentre,    0    { 1139:0322 }
  MOV  WORD PTR ProjScale,  256  { 1139:0328 }
  MOV  WORD PTR ViewDist,   2500 { 1139:032e }
end;

{ --------------------------------------------------------------------------
  Demo_Scene3 (1139:03b4)

  Eight scripted segments of 45 frames (63 for the last). Odd segments hold a
  shape, even segments morph to the next one. The closing segment also fades.
  -------------------------------------------------------------------------- }
{ AND IT IS DECLARED AFTER Scene3, at 1139:0670, which is why only a forward
  declaration can go here. Placing the body before Scene3 puts Scene3 at the
  wrong offset and every one of its eight blocks with it -- 476 bytes, the
  largest single span in this target, and all of it downstream of one
  declaration's position. }
{ --------------------------------------------------------------------------
  Demo_Scene3 (1139:03b4) -- HAND ASSEMBLER, and the whole procedure is.

  THREE MEASUREMENTS SAY SO, and two of them had been made and disbelieved.

  1. NO PROLOGUE AND NO EPILOGUE. 1139:03b4 goes straight into a CALL and the
     routine ends at 0583 with a bare RETF. A compiled Turbo Pascal procedure
     opens PUSH BP / MOV BP,SP and closes LEAVE / RETF even with no locals at
     all -- probe/DECLOOP.PAS has seven such procedures and every one of them
     carries the frame. Only `assembler` omits it.

  2. DEC FOLLOWED STRAIGHT BY JNE. 1139:0414 is DEC WORD PTR [Frames] / JNE,
     six bytes. Turbo Pascal re-reads the variable: DEC, then CMP ...,0, then
     JNE -- five bytes more, at each of eight loops. probe/DECLOOP.PAS tries
     seven spellings of "count down and stop at zero" -- Dec then `until = 0`,
     with a call in the body, `until <= 0`, an assignment instead of Dec, Word,
     Byte, and a while -- across Turbo Pascal 7, 6.0 and 6.1. EVERY ONE emits
     the CMP. There is no such peephole in any dialect.

  3. OR DX,DX. Turbo Pascal returns a Boolean in AL, a word in AX, a LongInt or
     a pointer in DX:AX, and NOTHING in DX alone. The DX form appears exactly
     once in the whole demo -- here -- while every part carries the runtime's AL
     form. CheckKey below is an assembler function returning DX by the author's
     own convention, and only asm can test it.

  AND THE JUMPS OUT PROVE IT TWICE OVER, which is the detail that settles any
  doubt about extent. Eight loops test the key and leave the scene; the first
  five write JE over a JMP and the last three write a plain JNE. A compiler is
  consistent. A PERSON writes `JNE @@Done` every time, and inverts it only where
  the assembler complains that the target is out of a short branch's reach --
  which is exactly the first five, whose exits are $1A3 down to $109 bytes away,
  and exactly not the last three, at $6D, $43 and $06. The inconsistency is the
  signature.

  So it is transcribed verbatim below, per the standing rule for this target.
  THE EQUIVALENT PASCAL, which is what was here before and is behaviourally the
  same thing:

      InitScene;  PageOfs := PageOfsB;
      CurShape := ShapeSphere; MorphFrom := ShapeSphere; MorphTo := ShapeCube;
      StepX := SpinX; StepY := SpinY; StepZ := SpinZ;
      AngX := 0; AngY := 0; AngZ := 0;
      Frames := SegFrames;
      repeat ClearPage; DrawShape; FlipPage; WaitRetrace; StepAngles;
             if CheckKey then Exit; Dec(Frames) until Frames = 0;

  and seven more of those, alternating DrawShape and DrawMorph, with MorphFrom
  and MorphTo walking sphere -> cube -> grid -> cube -> sphere and the last one
  fading the palette out as it morphs.

  A key abandons the WHOLE scene rather than one segment of it -- every test
  jumps to the procedure's own RETF.
  -------------------------------------------------------------------------- }

{ @asm 003 1139:0335 }
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


  { RowOfs is the Mode-X unit's own table (1192:0000 fills it), not this
    scene's -- see MODEX.PAS. It is imported, not declared here. }

{ CheckKey IS DEFINED HERE, BETWEEN FlipPage AND Set400Lines, AND NOT AT THE
  END OF THE FILE. Definition order is segment order and the map at the top of
  this file gives the original's: ModeX_FlipPage 1139:02c3, Morph_CheckKey
  02e0, VGA_Set400Lines 02f2. Defined last, behind a `forward`, its eighteen
  bytes sat past Scene3 instead and every routine from Set400Lines on came out
  eighteen bytes early -- Demo_Scene3 at 03a2 against the original's 03b4.

  NOTHING IN THIS UNIT'S OWN MEASUREMENTS COULD SEE THAT. The segment is the
  right size either way, the coverage walk locates each routine by content and
  scored them all aligned, and the initialised data image is identical. What
  found it was the PROGRAM segment: 1000:0082 is LCALL 1139:03b4, so the main
  body names Scene3's offset exactly, and ours said 03a2. A part's program
  segment is a list of every unit's entry-point offsets, and comparing it byte
  for byte is the only instrument here that reads them. }

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

{ --------------------------------------------------------------------------
  VGA_Set400Lines (1139:02f2)

  CRTC register 9 is Maximum Scan Line. Its low five bits say how many times
  each character row is repeated; mode 13h leaves them at 1, which is what
  double-scans 200 lines into 400. Clearing them turns the double scan off,
  so the 320x200 Mode-X screen becomes 320x400 with no other change.

  The top three bits of register 9 are not ours to touch -- bit 7 is the
  200-line double word mode flag and bits 5-6 are the start row of the text
  cursor -- so the write is read-modify-write with AND $E0, not a plain MOV.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3D4] := 9;
      Port[$3D5] := Port[$3D5] and $E0;

  That Pascal is genuinely equivalent here. It is written in assembler
  because the original is, not because Pascal could not express it.
  -------------------------------------------------------------------------- }
{ @asm 003 1139:034d }
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

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Port[$3C8] := 0;
      for I := 0 to 767 do Port[$3C9] := B[I];
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  Morph_FadeStep (1139:0365)
  Read the whole DAC back, decrement every non-zero component by one, wait
  for retrace and write it out again -- a one-step fade toward black, called
  once per frame during the closing segment.
  -------------------------------------------------------------------------- }
procedure FadeStep;
var
  Pal : array[0..767] of Byte;
begin
  GetPalette768(Pal);                  { 1139:036f }

  (* The loop below, as Pascal:

         for I := 767 downto 0 do
           if Pal[I] <> 0 then Dec(Pal[I]);

     which is the same result and NOT the same code. Written that way the
     compiler gives I a stack slot and the routine opens ENTER $302; the
     original opens ENTER $300, exactly the buffer, so the index never reaches
     memory. Three unrolled steps, DI decremented between each, and the loop
     leaving on the sign flag are all hand assembler, and 555 bytes of the
     coverage walk said so before the frame did. *)
  asm
    MOV  DI, $02FF               { the LAST byte of the buffer -- see below     }
@Next:                           { <- three bytes a pass, one DAC triple        }
    MOV  AL, BYTE PTR Pal[DI]             { [BP+DI-$300]: this component                 }
    OR   AL, AL                  { already zero?                                }
    JZ   @Skip1                  {   yes: leave it, the fade SATURATES          }
    DEC  AL                      { one step darker                              }
    MOV  BYTE PTR Pal[DI], AL             { and back into the buffer                     }
@Skip1:
    DEC  DI                      { the next component down                      }
    MOV  AL, BYTE PTR Pal[DI]             { unrolled rather than looped -- the original  }
    OR   AL, AL                  {   has three copies of this block between one }
    JZ   @Skip2                  {   MOV DI and one JNS                         }
    DEC  AL
    MOV  BYTE PTR Pal[DI], AL
@Skip2:
    DEC  DI
    MOV  AL, BYTE PTR Pal[DI]
    OR   AL, AL
    JZ   @Skip3
    DEC  AL
    MOV  BYTE PTR Pal[DI], AL
@Skip3:
    DEC  DI                      { past this triple                             }
    JNS  @Next                   { DI went negative: every byte has been done   }
  end;

  { THE ONE DELIBERATE DIFFERENCE is the constant above: the original loads
    $0300, not $02FF. That is 768 -- one PAST the last byte of a 0..767 buffer
    -- so its first pass writes [BP+0], the saved BP, and its last two writes
    land below the frame. It survives because LEAVE reads BP before popping and
    the caller keeps nothing there. Reproducing it literally hung the scene
    when it was tried, and it would corrupt OUR frame, which is not the same
    frame. $02FF covers 767..0 in the same 256 passes and stays inside the
    buffer; it costs two bytes of the immediate and nothing else. }

  WaitRetrace;                         { 1139:03a4 }
  SetPalette768(Pal);                  { 1139:03af }
end;

{ --------------------------------------------------------------------------
  Morph_InitScene (1139:02fe)
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  Demo_Scene3 (1139:03b4) -- HAND ASSEMBLER, and the whole procedure is.

  THREE MEASUREMENTS SAY SO, and two of them had been made and disbelieved.

  1. NO PROLOGUE AND NO EPILOGUE. 1139:03b4 goes straight into a CALL and the
     routine ends at 0583 with a bare RETF. A compiled Turbo Pascal procedure
     opens PUSH BP / MOV BP,SP and closes LEAVE / RETF even with no locals at
     all -- probe/DECLOOP.PAS has seven such procedures and every one of them
     carries the frame. Only `assembler` omits it.

  2. DEC FOLLOWED STRAIGHT BY JNE. 1139:0414 is DEC WORD PTR [Frames] / JNE,
     six bytes. Turbo Pascal re-reads the variable: DEC, then CMP ...,0, then
     JNE -- five bytes more, at each of eight loops. probe/DECLOOP.PAS tries
     seven spellings of "count down and stop at zero" -- Dec then `until = 0`,
     with a call in the body, `until <= 0`, an assignment instead of Dec, Word,
     Byte, and a while -- across Turbo Pascal 7, 6.0 and 6.1. EVERY ONE emits
     the CMP. There is no such peephole in any dialect.

  3. OR DX,DX. Turbo Pascal returns a Boolean in AL, a word in AX, a LongInt or
     a pointer in DX:AX, and NOTHING in DX alone. The DX form appears exactly
     once in the whole demo -- here -- while every part carries the runtime's AL
     form. CheckKey below is an assembler function returning DX by the author's
     own convention, and only asm can test it.

  AND THE JUMPS OUT PROVE IT TWICE OVER, which is the detail that settles any
  doubt about extent. Eight loops test the key and leave the scene; the first
  five write JE over a JMP and the last three write a plain JNE. A compiler is
  consistent. A PERSON writes `JNE @@Done` every time, and inverts it only where
  the assembler complains that the target is out of a short branch's reach --
  which is exactly the first five, whose exits are $1A3 down to $109 bytes away,
  and exactly not the last three, at $6D, $43 and $06. The inconsistency is the
  signature.

  So it is transcribed verbatim below, per the standing rule for this target.
  THE EQUIVALENT PASCAL, which is what was here before and is behaviourally the
  same thing:

      InitScene;  PageOfs := PageOfsB;
      CurShape := ShapeSphere; MorphFrom := ShapeSphere; MorphTo := ShapeCube;
      StepX := SpinX; StepY := SpinY; StepZ := SpinZ;
      AngX := 0; AngY := 0; AngZ := 0;
      Frames := SegFrames;
      repeat ClearPage; DrawShape; FlipPage; WaitRetrace; StepAngles;
             if CheckKey then Exit; Dec(Frames) until Frames = 0;

  and seven more of those, alternating DrawShape and DrawMorph, with MorphFrom
  and MorphTo walking sphere -> cube -> grid -> cube -> sphere and the last one
  fading the palette out as it morphs.

  A key abandons the WHOLE scene rather than one segment of it -- every test
  jumps to the procedure's own RETF.
  -------------------------------------------------------------------------- }
procedure Scene3; assembler;
asm
        CALL    InitScene               { 1139:03b4                          }
        MOV     WORD PTR PageOfs, PageOfsB      { 03b7 -- draw to page B     }

        { The shape addresses are OFFSET and not literals, and that does two
          jobs: it emits the same immediate the original has AND it REFERENCES
          the table, which is what keeps 8,738 bytes of shape data from being
          smart-linked out of DGROUP. A literal number references nothing. }
        MOV     WORD PTR CurShape,  OFFSET ShapeSphere  { 03bd  $0636 }
        MOV     WORD PTR MorphFrom, OFFSET ShapeSphere  { 03c3  $0636 }
        MOV     WORD PTR MorphTo,   OFFSET ShapeCube    { 03c9  $5136 }

        MOV     WORD PTR StepX, SpinX   { 03cf -- three degrees a frame, and  }
        MOV     WORD PTR StepY, SpinY   { 03d5    on all three axes at once   }
        MOV     WORD PTR StepZ, SpinZ   { 03db                                }
        MOV     WORD PTR AngX, 0        { 03e1                                }
        MOV     WORD PTR AngY, 0        { 03e7                                }
        MOV     WORD PTR AngZ, 0        { 03ed                                }

        { ---- 1: the sphere, spinning ---- }
        MOV     WORD PTR Frames, SegFrames      { 03f3                        }
@@L1:   CALL    ClearPage               { 03f9                                }
        CALL    DrawShape               { 03fc                                }
        CALL    FlipPage                { 03ff                                }
        CALL    WaitRetrace             { 0402 -- far, it is the VGA unit's   }
        CALL    StepAngles              { 0407                                }
        CALL    CheckKey                { 040a                                }
        OR      DX,DX                   { 040d -- DX, not AL. See above.      }
        JE      @@K1                    { 040f                                }
        JMP     @@Done                  { 0411 -- $16F away, past a short JNE }
@@K1:   DEC     WORD PTR Frames         { 0414                                }
        JNE     @@L1                    { 0418 -- on the DEC's own flags      }

        { ---- 2: morph sphere -> cube ---- }
        MOV     WORD PTR MorphFrom, OFFSET ShapeSphere  { 041a                }
        MOV     WORD PTR MorphTo,   OFFSET ShapeCube    { 0420                }
        MOV     WORD PTR MorphStep, 0   { 0426 -- the IMMEDIATE form, six     }
        MOV     WORD PTR Frames, SegFrames      { 042c    bytes; Pascal emits }
@@L2:   CALL    ClearPage               { 0432    XOR AX,AX / MOV, which is   }
        CALL    DrawMorph               { 0435    five                        }
        CALL    FlipPage                { 0438                                }
        CALL    WaitRetrace             { 043b                                }
        CALL    StepAngles              { 0440                                }
        CALL    CheckKey                { 0443                                }
        OR      DX,DX                   { 0446                                }
        JE      @@K2                    { 0448                                }
        JMP     @@Done                  { 044a                                }
@@K2:   DEC     WORD PTR Frames         { 044d                                }
        JNE     @@L2                    { 0451                                }

        { ---- 3: the cube, spinning. CurShape := MorphTo rather than the
          constant -- 0453 reads MorphTo back out of memory. ---- }
        MOV     AX, WORD PTR MorphTo    { 0453                                }
        MOV     WORD PTR CurShape, AX   { 0456                                }
        MOV     WORD PTR Frames, SegFrames      { 0459                        }
@@L3:   CALL    ClearPage               { 045f                                }
        CALL    DrawShape               { 0462                                }
        CALL    FlipPage                { 0465                                }
        CALL    WaitRetrace             { 0468                                }
        CALL    StepAngles              { 046d                                }
        CALL    CheckKey                { 0470                                }
        OR      DX,DX                   { 0473                                }
        JE      @@K3                    { 0475                                }
        JMP     @@Done                  { 0477                                }
@@K3:   DEC     WORD PTR Frames         { 047a                                }
        JNE     @@L3                    { 047e                                }

        { ---- 4: morph cube -> grid ---- }
        MOV     WORD PTR MorphFrom, OFFSET ShapeCube    { 0480  $5136 }
        MOV     WORD PTR MorphTo,   OFFSET ShapeGrid    { 0486  $63F6 }
        MOV     WORD PTR MorphStep, 0   { 048c                                }
        MOV     WORD PTR Frames, SegFrames      { 0492                        }
@@L4:   CALL    ClearPage               { 0498                                }
        CALL    DrawMorph               { 049b                                }
        CALL    FlipPage                { 049e                                }
        CALL    WaitRetrace             { 04a1                                }
        CALL    StepAngles              { 04a6                                }
        CALL    CheckKey                { 04a9                                }
        OR      DX,DX                   { 04ac                                }
        JE      @@K4                    { 04ae                                }
        JMP     @@Done                  { 04b0                                }
@@K4:   DEC     WORD PTR Frames         { 04b3                                }
        JNE     @@L4                    { 04b7                                }

        { ---- 5: the grid, spinning ---- }
        MOV     AX, WORD PTR MorphTo    { 04b9                                }
        MOV     WORD PTR CurShape, AX   { 04bc                                }
        MOV     WORD PTR Frames, SegFrames      { 04bf                        }
@@L5:   CALL    ClearPage               { 04c5                                }
        CALL    DrawShape               { 04c8                                }
        CALL    FlipPage                { 04cb                                }
        CALL    WaitRetrace             { 04ce                                }
        CALL    StepAngles              { 04d3                                }
        CALL    CheckKey                { 04d6                                }
        OR      DX,DX                   { 04d9                                }
        JE      @@K5                    { 04db                                }
        JMP     @@Done                  { 04dd -- the LAST that needs this    }
@@K5:   DEC     WORD PTR Frames         { 04e0                                }
        JNE     @@L5                    { 04e4                                }

        { ---- 6: morph grid -> cube. From here the exit is within a short
          branch's reach, and the original stops inverting the test. ---- }
        MOV     WORD PTR MorphFrom, OFFSET ShapeGrid    { 04e6 }
        MOV     WORD PTR MorphTo,   OFFSET ShapeCube    { 04ec }
        MOV     WORD PTR MorphStep, 0   { 04f2                                }
        MOV     WORD PTR Frames, SegFrames      { 04f8                        }
@@L6:   CALL    ClearPage               { 04fe                                }
        CALL    DrawMorph               { 0501                                }
        CALL    FlipPage                { 0504                                }
        CALL    WaitRetrace             { 0507                                }
        CALL    StepAngles              { 050c                                }
        CALL    CheckKey                { 050f                                }
        OR      DX,DX                   { 0512                                }
        JNE     @@Done                  { 0514 -- $6D, so a plain JNE         }
        DEC     WORD PTR Frames         { 0516                                }
        JNE     @@L6                    { 051a                                }

        { ---- 7: the cube again ---- }
        MOV     AX, WORD PTR MorphTo    { 051c                                }
        MOV     WORD PTR CurShape, AX   { 051f                                }
        MOV     WORD PTR Frames, SegFrames      { 0522                        }
@@L7:   CALL    ClearPage               { 0528                                }
        CALL    DrawShape               { 052b                                }
        CALL    FlipPage                { 052e                                }
        CALL    WaitRetrace             { 0531                                }
        CALL    StepAngles              { 0536                                }
        CALL    CheckKey                { 0539                                }
        OR      DX,DX                   { 053c                                }
        JNE     @@Done                  { 053e -- $43                         }
        DEC     WORD PTR Frames         { 0540                                }
        JNE     @@L7                    { 0544                                }

        { ---- 8: morph cube -> sphere while the palette fades out. Sixty-three
          frames rather than forty-five, which is the fade's length. ---- }
        MOV     WORD PTR MorphFrom, OFFSET ShapeCube    { 0546 }
        MOV     WORD PTR MorphTo,   OFFSET ShapeSphere  { 054c  $0636 }
        MOV     WORD PTR MorphStep, 0   { 0552                                }
        MOV     WORD PTR Frames, LastFrames     { 0558  $3F = 63             }
        { DI AND SI ARE SAVED ACROSS FadeStep AND NOWHERE ELSE. 055e is
          PUSH DI / PUSH SI and 0563 is POP SI / POP DI -- the caller's own
          save, which a compiled call never needs because a Turbo Pascal
          callee must preserve both. So FadeStep does not, and it is the one
          call in this loop written by hand at the other end too. Transcribed
          as it stands; the pair costs four bytes and changes nothing that can
          be observed. }
@@L8:   PUSH    DI                      { 055e                                }
        PUSH    SI                      { 055f                                }
        CALL    FadeStep                { 0560                                }
        POP     SI                      { 0563                                }
        POP     DI                      { 0564                                }
        CALL    ClearPage               { 0565                                }
        CALL    DrawMorph               { 0568                                }
        CALL    FlipPage                { 056b                                }
        CALL    WaitRetrace             { 056e                                }
        CALL    StepAngles              { 0573                                }
        CALL    CheckKey                { 0576                                }
        OR      DX,DX                   { 0579                                }
        JNE     @@Done                  { 057b -- $06                         }
        DEC     WORD PTR Frames         { 057d                                }
        JNE     @@L8                    { 0581                                }
@@Done:                                 { 0583 is the RETF Turbo Pascal adds  }
end;


{ The original gives every unit an EMPTY initialisation section, and the
  main body's opening far calls are the chain that runs them -- eleven of
  them in this part, one per unit, ending at 1000:0041 where the real body
  starts. Each stub is five bytes, PUSH BP / MOV BP,SP / LEAVE / RETF, and
  it sits at the END of the unit's own segment. Without a `begin` here
  Turbo Pascal emits neither the stub nor the chain entry. }

begin
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
