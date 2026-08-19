{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.005 scene 1, segment 100e.

  A 32 x 32 grid of points is projected and drawn as 1,922 filled triangles.
  The height of each point comes from a 1,024-byte greyscale map read off
  NEUROSIS.DAT and THRESHOLDED -- and it is the threshold that is animated, so
  the landscape grows out of a flat plane and sinks back into it. Three maps
  are read in turn and each is morphed up and down.

  Read from the binary instruction by instruction; nothing here is inferred.
  See docs/26-part5-notes.md for the reading.

  ADDRESS MAP
    FillTriangle    100e:0000     Project         100e:05d3
    BuildRowTable   100e:04e6     Morph           100e:06ae
    BuildGrid       100e:050b     BuildRamp       100e:073c
    HeightFromMap   100e:056d     FadeUpDot       100e:076c
    DrawMesh        100e:062a     Scene1          100e:07a4

  DGROUP
    DS:$0002  the triangle list, 1922 x 3 words   -- initialised data
    DS:$2d0e  the clip window: 0, 199, 0, 319     -- initialised data
    DS:$2d7e  the height map, 1024 bytes
    DS:$317e  the grid, 1024 x (X, Y, Z) as words
    DS:$497e  the projected vertices, 1024 x (SX, SY : Word; Col : Byte)
    DS:$5d7e  the file variable
    DS:$5dfe  a row table, 200 words -- scene 1 keeps its own
    DS:$5fde  the edge buffer FillTriangle fills top-down and reads bottom-up
  =========================================================================== }

{$G+}   { 186: FillTriangle's scan converters are bracketed by PUSHA/POPA in
          DrawMesh, and the shifts take immediates. }
{$S-}   { STACK CHECKING OFF, and part 005 does NOT settle this in one answer:
          FixMath's copy in this part (segment 124a) opens
          MOV AX,4 / CALLF 12d9:0530 / SUB SP,4, so THAT unit was built with
          it on -- but segment 100e opens ENTER $1A,0 with no check at all. So
          the setting is per unit, and this one is off. With it on Turbo
          Pascal emits PUSH BP / MOV BP,SP / MOV AX,n / CALLF and never ENTER,
          which pushes every routine here seven bytes out of step. }

unit P5S1;

interface

procedure Scene1;

implementation

uses Crt, VGA;

const
  GridSide  = 32;                  { the grid is 32 x 32 }
  GridVerts = GridSide * GridSide; { 1024 -- 100e:0564 counts to $3FF }
  NumTris   = 1922;                { 100e:063e loads $782 }
  Spacing   = 20;                  { 100e:0526, IMUL AX,AX,$14 }
  RestZ     = 300;                 { 100e:055e, the flat plane }
  BaseZ     = 250;                 { 100e:05c2, what a thresholded point sits at }

  DataOfs   = $00153DE5;           { 100e:07c7 pushes $0015 then $3DE5 }
  MapSize   = $400;                { 1024 bytes per height map }

type
  TPoint3  = record X, Y, Z : Integer end;
  TProj    = record SX, SY : Integer; Col : Byte end;   { 5 bytes }
  TTri     = array[1..3] of Word;

{$I gen/P5MESH.INC}   { const MeshTris : array[1..NumTris] of TTri }

var
  { DS:$317e and DS:$497e }
  Grid   : array[0..GridVerts - 1] of TPoint3;
  Proj   : array[0..GridVerts - 1] of TProj;
  { DS:$2d7e }
  HeightMap : array[0..MapSize - 1] of Byte;
  { DS:$5dfe -- scene 1's own row table, not the VGA unit's }
  RowOfs : array[0..199] of Word;
  { DS:$5fde -- two words per scanline, written going down and read going up }
  EdgeBuf : array[0..799] of Word;
  F      : file;

const
  { DS:$2d0e..$2d14 -- INITIALISED DATA, read straight out of the image:
    00 00  C7 00  00 00  3F 01. The full 320 x 200 screen. FillTriangle reads
    all four, so they are typed constants rather than plain consts: a plain
    const would fold into the instruction and stop matching. }
  ClipTop    : Integer = 0;        { DS:$2d0e }
  ClipBottom : Integer = 199;      { DS:$2d10 }
  ClipLeft   : Integer = 0;        { DS:$2d12 }
  ClipRight  : Integer = 319;      { DS:$2d14 }

{ --------------------------------------------------------------------------
  100e:0000 -- the filled-triangle scan converter. HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      sort the three vertices so Y1 <= Y2 <= Y3
      reject anything with no area, or wholly above or below the clip window
      for each edge, Bresenham: Step := Dx div Dy, Err := Dx mod Dy, both
        floored towards minus infinity rather than towards zero
      walk both active edges down the triangle, pushing the two X values of
        every scanline into EdgeBuf
      then walk EdgeBuf BACK UP, clipping each pair to ClipLeft..ClipRight and
        filling the span with REP STOSW

  It cannot be written that way and still be the same code. The routine has
  FOUR scan converters -- flat-top, flat-bottom, and the two general cases
  told apart by the sign of the cross product -- which differ only in which
  edge feeds DI and which feeds SI. Turbo Pascal would emit one parameterised
  loop; the original unrolled it, and the unrolling is the routine.

  THE FLOORED DIVIDE. Turbo Pascal's div truncates towards zero. Every one of
  the six divisions here is followed by

      CMP CX, 0        the numerator
      JGE +5
      DEC AX           quotient
      ADD DX, BX       remainder += divisor

  which converts it to a floor. Without that the error term goes negative and
  the edge walks the wrong way.
  -------------------------------------------------------------------------- }
{ @asm 005 100e:0000 +1254 FillTriangle }
procedure FillTriangle(X1, Y1, X2, Y2, X3, Y3 : Integer;
                       Colour : Byte; Segment : Word); assembler;
var
  { ENTER $1A -- thirteen words, and the ORDER IS LOAD-BEARING: the original
    reads them at [BP-2] through [BP-$1A] in exactly this sequence. }
  Dx12, Dx13, Dx23    : Integer;   { [BP-2]  [BP-4]  [BP-6]  }
  Dy12, Dy13, Dy23    : Integer;   { [BP-8]  [BP-A]  [BP-C]  }
  Err12, Err13, Err23 : Integer;   { [BP-E]  [BP-10] [BP-12] }
  Stp12, Stp13, Stp23 : Integer;   { [BP-14] [BP-16] [BP-18] }
  RightX              : Integer;   { [BP-1A] }
asm
  PUSH ES                    { 100e:0004                                     }
  PUSH DI                    { 100e:0005                                     }
  MOV  AX, X1                { 100e:0006  AX,BX = vertex 1                   }
  MOV  BX, Y1                { 100e:0009                                     }
  MOV  CX, X2                { 100e:000c  CX,DX = vertex 2                   }
  MOV  DX, Y2                { 100e:000f    vertex 3 stays in the frame      }
  CMP  AX, CX                { 100e:0012  all three X equal?                 }
  JNZ  @Sort                 { 100e:0014                                     }
  CMP  CX, X3                { 100e:0016                                     }
  JNZ  @Sort                 { 100e:0019                                     }
  JMP  @Done                 { 100e:001b  a vertical line has no area        }

{ ---- sort the three vertices by Y ---- }
@Sort:
  CMP  BX, DX                { 100e:001e                                     }
  JG   @Swap1                { 100e:0020                                     }
  JMP  @Sorted2              { 100e:0022                                     }
@Swap1:
  XCHG AX, CX                { 100e:0024  vertex 1 <-> vertex 2              }
  XCHG BX, DX                { 100e:0025                                     }
@Sorted2:
  CMP  DX, Y3                { 100e:0027                                     }
  JG   @Swap2                { 100e:002a                                     }
  JMP  @Sorted3              { 100e:002c                                     }
@Swap2:
  XCHG X3, CX                { 100e:002e  vertex 2 <-> vertex 3, in the frame}
  XCHG Y3, DX                { 100e:0031                                     }
  CMP  BX, DX                { 100e:0034  which may have unsorted 1 and 2    }
  JG   @Swap3                { 100e:0036                                     }
  JMP  @Sorted3              { 100e:0038                                     }
@Swap3:
  XCHG AX, CX                { 100e:003a                                     }
  XCHG BX, DX                { 100e:003b                                     }
@Sorted3:
  CMP  BX, DX                { 100e:003d  Y1 = Y2 -- a flat top?             }
  JZ   @FlatTopTest          { 100e:003f                                     }
  JMP  @Test23               { 100e:0041                                     }

@FlatTopTest:
  CMP  DX, Y3                { 100e:0043  and Y2 = Y3 as well?               }
  JNZ  @FlatTopOrder         { 100e:0046                                     }
  JMP  @Done                 { 100e:0048  all three on one row: no area      }
@FlatTopOrder:
  CMP  AX, CX                { 100e:004b  the flat edge must run left->right }
  JG   @FlatTopSwap          { 100e:004d                                     }
  JGE  @DoneJmp              { 100e:004f  equal: no area                     }
  JMP  @FlatTop              { 100e:0051                                     }
@DoneJmp:
  JMP  @Done                 { 100e:0054                                     }
@FlatTopSwap:
  XCHG AX, CX                { 100e:0057                                     }
  JMP  @FlatTop              { 100e:0058                                     }

@Test23:
  CMP  DX, Y3                { 100e:005b  Y2 = Y3 -- a flat bottom?          }
  JZ   @FlatBotOrder         { 100e:005e                                     }
  JMP  @General              { 100e:0060                                     }
@FlatBotOrder:
  CMP  CX, X3                { 100e:0062                                     }
  JG   @FlatBotSwap          { 100e:0065                                     }
  JGE  @DoneJmp2             { 100e:0067  wrong: JGE means equal -- no area  }
  JMP  @FlatBot              { 100e:0069                                     }
@DoneJmp2:
  JMP  @Done                 { 100e:006c                                     }
@FlatBotSwap:
  XCHG X3, CX                { 100e:006f                                     }
  JMP  @FlatBot              { 100e:0072                                     }

{ ======== the general case: three distinct Y values ======== }
@General:
  MOV  X1, AX                { 100e:0075  put the sorted vertices back       }
  MOV  Y1, BX                { 100e:0078                                     }
  MOV  X2, CX                { 100e:007b                                     }
  MOV  Y2, DX                { 100e:007e                                     }
  MOV  DI, Y3                { 100e:0081                                     }
  CMP  DI, ClipTop           { 100e:0084  the whole triangle above the top?  }
  JGE  @GenB                 { 100e:0088                                     }
  JMP  @Done                 { 100e:008a                                     }
@GenB:
  MOV  DI, Y1                { 100e:008d                                     }
  CMP  DI, ClipBottom        { 100e:0090  ...or below the bottom?            }
  JLE  @GenEdges             { 100e:0094                                     }
  JMP  @Done                 { 100e:0096                                     }

@GenEdges:
  MOV  BX, DX                { 100e:0099  edge 1->2                          }
  SUB  BX, Y1                { 100e:009b                                     }
  MOV  Dy12, BX              { 100e:009e                                     }
  MOV  AX, X2                { 100e:00a1                                     }
  SUB  AX, X1                { 100e:00a4                                     }
  MOV  Dx12, AX              { 100e:00a7                                     }
  MOV  CX, AX                { 100e:00aa  keep the numerator's sign          }
  CWD                        { 100e:00ac                                     }
  IDIV BX                    { 100e:00ad                                     }
  CMP  CX, 0                 { 100e:00af                                     }
  JGE  @Keep12               { 100e:00b2                                     }
  DEC  AX                    { 100e:00b4  floor, not truncate                }
  ADD  DX, BX                { 100e:00b5    and keep the remainder positive  }
@Keep12:
  MOV  Stp12, AX             { 100e:00b7                                     }
  MOV  Err12, DX             { 100e:00ba                                     }

  MOV  BX, Y3                { 100e:00bd  edge 1->3, the long one            }
  SUB  BX, Y1                { 100e:00c0                                     }
  MOV  Dy13, BX              { 100e:00c3                                     }
  MOV  AX, X3                { 100e:00c6                                     }
  SUB  AX, X1                { 100e:00c9                                     }
  MOV  Dx13, AX              { 100e:00cc                                     }
  MOV  CX, AX                { 100e:00cf                                     }
  CWD                        { 100e:00d1                                     }
  IDIV BX                    { 100e:00d2                                     }
  CMP  CX, 0                 { 100e:00d4                                     }
  JGE  @Keep13               { 100e:00d7                                     }
  DEC  AX                    { 100e:00d9                                     }
  ADD  DX, BX                { 100e:00da                                     }
@Keep13:
  MOV  Stp13, AX             { 100e:00dc                                     }
  MOV  Err13, DX             { 100e:00df                                     }

  MOV  BX, Y3                { 100e:00e2  edge 2->3                          }
  SUB  BX, Y2                { 100e:00e5                                     }
  JLE  @Cross                { 100e:00e8  none of it: skip, it is unused     }
  MOV  Dy23, BX              { 100e:00ea                                     }
  MOV  AX, X3                { 100e:00ed                                     }
  SUB  AX, X2                { 100e:00f0                                     }
  MOV  Dx23, AX              { 100e:00f3                                     }
  MOV  CX, AX                { 100e:00f6                                     }
  CWD                        { 100e:00f8                                     }
  IDIV BX                    { 100e:00f9                                     }
  CMP  CX, 0                 { 100e:00fb                                     }
  JGE  @Keep23               { 100e:00fe                                     }
  DEC  AX                    { 100e:0100                                     }
  ADD  DX, BX                { 100e:0101                                     }
@Keep23:
  MOV  Stp23, AX             { 100e:0103                                     }
  MOV  Err23, DX             { 100e:0106                                     }

{ Which side is the middle vertex on? Dx12*Dy13 against Dx13*Dy12 -- the
  cross product, as two 32-bit products compared high word first. }
@Cross:
  MOV  AX, Dx12              { 100e:0109                                     }
  IMUL Dy13                  { 100e:010c  DX:AX := Dx12 * Dy13               }
  MOV  BX, AX                { 100e:010f                                     }
  MOV  CX, DX                { 100e:0111                                     }
  MOV  AX, Dx13              { 100e:0113                                     }
  IMUL Dy12                  { 100e:0116  DX:AX := Dx13 * Dy12               }
  CMP  CX, DX                { 100e:0119                                     }
  JG   @Left                 { 100e:011b                                     }
  JGE  @CrossLow             { 100e:011d  high words equal: compare low      }
  JMP  @Right                { 100e:011f                                     }
@CrossLow:
  CMP  BX, AX                { 100e:0122                                     }
  JA   @Left                 { 100e:0124  unsigned: the low halves           }
  JNC  @CrossZero            { 100e:0126                                     }
  JMP  @Right                { 100e:0128                                     }
@CrossZero:
  JMP  @Done                 { 100e:012b  collinear: no area                 }

{ ---- general case A: DI walks 1->3, SI walks 1->2 then 2->3 ---- }
@Left:
  MOV  AX, 0                 { 100e:012e  the two error accumulators         }
  MOV  BX, 0                 { 100e:0131                                     }
  MOV  CX, Y1                { 100e:0134  CX is the scanline                 }
  MOV  DI, X1                { 100e:0137                                     }
  MOV  SI, DI                { 100e:013a  both edges start at vertex 1       }
  XOR  DX, DX                { 100e:013c  DX indexes EdgeBuf                 }
  CMP  CX, ClipTop           { 100e:013e                                     }
  JGE  @LeftTop              { 100e:0142                                     }
  MOV  DX, ClipTop           { 100e:0144                                     }
  MOV  Y1, DX                { 100e:0148                                     }
  MOV  DX, Y1                { 100e:014b                                     }
  CMP  DX, Y3                { 100e:014e                                     }
  JNZ  @LeftReset            { 100e:0151                                     }
  JMP  @Done                 { 100e:0153                                     }
@LeftReset:
  XOR  DX, DX                { 100e:0156                                     }
@LeftTop:
  CMP  CX, ClipTop           { 100e:0158  above the window: step, do not     }
  JL   @LeftStep1            { 100e:015c    record                           }
  MOV  ES, BX                { 100e:015e  BX is in use, so ES is the spare   }
  MOV  BX, DX                { 100e:0160                                     }
  MOV  [BX + OFFSET EdgeBuf], DI       { 100e:0162                                     }
  MOV  BX, ES                { 100e:0166                                     }
  ADD  DX, 2                 { 100e:0168                                     }
  MOV  ES, BX                { 100e:016b                                     }
  MOV  BX, DX                { 100e:016d                                     }
  MOV  [BX + OFFSET EdgeBuf], SI       { 100e:016f                                     }
  MOV  BX, ES                { 100e:0173                                     }
  ADD  DX, 2                 { 100e:0175                                     }
@LeftStep1:
  ADD  AX, Err13             { 100e:0178                                     }
  JLE  @LeftNoCarry1         { 100e:017b                                     }
  SUB  AX, Dy13              { 100e:017d                                     }
  INC  DI                    { 100e:0180                                     }
@LeftNoCarry1:
  ADD  DI, Stp13             { 100e:0181  the step happens either way        }
  ADD  BX, Err12             { 100e:0184                                     }
  JLE  @LeftNoCarry2         { 100e:0187                                     }
  SUB  BX, Dy12              { 100e:0189                                     }
  INC  SI                    { 100e:018c                                     }
@LeftNoCarry2:
  ADD  SI, Stp12             { 100e:018d                                     }
  INC  CX                    { 100e:0190                                     }
  CMP  CX, ClipBottom        { 100e:0191                                     }
  JL   @LeftMid              { 100e:0195                                     }
  MOV  Y3, CX                { 100e:0197  ran off the bottom: stop here      }
  JMP  @Span                 { 100e:019a                                     }
@LeftMid:
  CMP  CX, Y2                { 100e:019d  still in the upper half?           }
  JL   @LeftTop              { 100e:01a0                                     }

@LeftLower:
  CMP  CX, ClipTop           { 100e:01a2                                     }
  JL   @LeftStep2            { 100e:01a6                                     }
  MOV  ES, BX                { 100e:01a8                                     }
  MOV  BX, DX                { 100e:01aa                                     }
  MOV  [BX + OFFSET EdgeBuf], DI       { 100e:01ac                                     }
  MOV  BX, ES                { 100e:01b0                                     }
  ADD  DX, 2                 { 100e:01b2                                     }
  MOV  ES, BX                { 100e:01b5                                     }
  MOV  BX, DX                { 100e:01b7                                     }
  MOV  [BX + OFFSET EdgeBuf], SI       { 100e:01b9                                     }
  MOV  BX, ES                { 100e:01bd                                     }
  ADD  DX, 2                 { 100e:01bf                                     }
@LeftStep2:
  ADD  AX, Err13             { 100e:01c2  DI is still on the long edge       }
  JLE  @LeftNoCarry3         { 100e:01c5                                     }
  SUB  AX, Dy13              { 100e:01c7                                     }
  INC  DI                    { 100e:01ca                                     }
@LeftNoCarry3:
  ADD  DI, Stp13             { 100e:01cb                                     }
  ADD  BX, Err23             { 100e:01ce  SI has moved on to edge 2->3       }
  JLE  @LeftNoCarry4         { 100e:01d1                                     }
  SUB  BX, Dy23              { 100e:01d3                                     }
  INC  SI                    { 100e:01d6                                     }
@LeftNoCarry4:
  ADD  SI, Stp23             { 100e:01d7                                     }
  INC  CX                    { 100e:01da                                     }
  CMP  CX, ClipBottom        { 100e:01db                                     }
  JL   @LeftEnd              { 100e:01df                                     }
  MOV  Y3, CX                { 100e:01e1                                     }
@LeftEnd:
  CMP  CX, Y3                { 100e:01e4                                     }
  JL   @LeftLower            { 100e:01e7                                     }
  JMP  @Span                 { 100e:01e9                                     }

{ ---- general case B: DI walks 1->2 then 2->3, SI walks 1->3 ---- }
@Right:
  MOV  AX, 0                 { 100e:01ec                                     }
  MOV  BX, 0                 { 100e:01ef                                     }
  MOV  CX, Y1                { 100e:01f2                                     }
  MOV  DI, X1                { 100e:01f5                                     }
  MOV  SI, X1                { 100e:01f8                                     }
  XOR  DX, DX                { 100e:01fb                                     }
  CMP  CX, ClipTop           { 100e:01fd                                     }
  JGE  @RightTop             { 100e:0201                                     }
  MOV  DX, ClipTop           { 100e:0203                                     }
  MOV  Y1, DX                { 100e:0207                                     }
  MOV  DX, Y1                { 100e:020a                                     }
  CMP  DX, Y3                { 100e:020d                                     }
  JNZ  @RightReset           { 100e:0210                                     }
  JMP  @Done                 { 100e:0212                                     }
@RightReset:
  XOR  DX, DX                { 100e:0215                                     }
@RightTop:
  CMP  CX, ClipTop           { 100e:0217                                     }
  JL   @RightStep1           { 100e:021b                                     }
  MOV  ES, BX                { 100e:021d                                     }
  MOV  BX, DX                { 100e:021f                                     }
  MOV  [BX + OFFSET EdgeBuf], DI       { 100e:0221                                     }
  MOV  BX, ES                { 100e:0225                                     }
  ADD  DX, 2                 { 100e:0227                                     }
  MOV  ES, BX                { 100e:022a                                     }
  MOV  BX, DX                { 100e:022c                                     }
  MOV  [BX + OFFSET EdgeBuf], SI       { 100e:022e                                     }
  MOV  BX, ES                { 100e:0232                                     }
  ADD  DX, 2                 { 100e:0234                                     }
@RightStep1:
  ADD  AX, Err12             { 100e:0237  DI is on the short edge here       }
  JLE  @RightNoCarry1        { 100e:023a                                     }
  SUB  AX, Dy12              { 100e:023c                                     }
  INC  DI                    { 100e:023f                                     }
@RightNoCarry1:
  ADD  DI, Stp12             { 100e:0240                                     }
  ADD  BX, Err13             { 100e:0243                                     }
  JLE  @RightNoCarry2        { 100e:0246                                     }
  SUB  BX, Dy13              { 100e:0248                                     }
  INC  SI                    { 100e:024b                                     }
@RightNoCarry2:
  ADD  SI, Stp13             { 100e:024c                                     }
  INC  CX                    { 100e:024f                                     }
  CMP  CX, ClipBottom        { 100e:0250                                     }
  JL   @RightMid             { 100e:0254                                     }
  MOV  Y3, CX                { 100e:0256                                     }
  JMP  @Span                 { 100e:0259                                     }
@RightMid:
  CMP  CX, Y2                { 100e:025c                                     }
  JL   @RightTop             { 100e:025f                                     }

@RightLower:
  CMP  CX, ClipTop           { 100e:0261                                     }
  JL   @RightStep2           { 100e:0265                                     }
  MOV  ES, BX                { 100e:0267                                     }
  MOV  BX, DX                { 100e:0269                                     }
  MOV  [BX + OFFSET EdgeBuf], DI       { 100e:026b                                     }
  MOV  BX, ES                { 100e:026f                                     }
  ADD  DX, 2                 { 100e:0271                                     }
  MOV  ES, BX                { 100e:0274                                     }
  MOV  BX, DX                { 100e:0276                                     }
  MOV  [BX + OFFSET EdgeBuf], SI       { 100e:0278                                     }
  MOV  BX, ES                { 100e:027c                                     }
  ADD  DX, 2                 { 100e:027e                                     }
@RightStep2:
  ADD  AX, Err23             { 100e:0281  DI has moved on to edge 2->3       }
  JLE  @RightNoCarry3        { 100e:0284                                     }
  SUB  AX, Dy23              { 100e:0286                                     }
  INC  DI                    { 100e:0289                                     }
@RightNoCarry3:
  ADD  DI, Stp23             { 100e:028a                                     }
  ADD  BX, Err13             { 100e:028d  SI is still on the long edge       }
  JLE  @RightNoCarry4        { 100e:0290                                     }
  SUB  BX, Dy13              { 100e:0292                                     }
  INC  SI                    { 100e:0295                                     }
@RightNoCarry4:
  ADD  SI, Stp13             { 100e:0296                                     }
  INC  CX                    { 100e:0299                                     }
  CMP  CX, ClipBottom        { 100e:029a                                     }
  JL   @RightEnd             { 100e:029e                                     }
  MOV  Y3, CX                { 100e:02a0                                     }
  JMP  @Span                 { 100e:02a3                                     }
@RightEnd:
  CMP  CX, Y3                { 100e:02a6                                     }
  JL   @RightLower           { 100e:02a9                                     }
  JMP  @Span                 { 100e:02ab                                     }

{ ======== flat top: Y1 = Y2, one pair of edges down to vertex 3 ======== }
@FlatTop:
  MOV  X1, AX                { 100e:02ae                                     }
  MOV  Y1, BX                { 100e:02b1                                     }
  MOV  X2, CX                { 100e:02b4                                     }
  MOV  Y2, DX                { 100e:02b7                                     }
  MOV  DI, Y3                { 100e:02ba                                     }
  CMP  DI, ClipTop           { 100e:02bd                                     }
  JGE  @FlatTopB             { 100e:02c1                                     }
  JMP  @Done                 { 100e:02c3                                     }
@FlatTopB:
  MOV  DI, Y1                { 100e:02c6                                     }
  CMP  DI, ClipBottom        { 100e:02c9                                     }
  JLE  @FlatTopEdges         { 100e:02cd                                     }
  JMP  @Done                 { 100e:02cf                                     }
@FlatTopEdges:
  MOV  BX, Y3                { 100e:02d2  edge 1->3, into the 1->2 slots     }
  SUB  BX, Y1                { 100e:02d5                                     }
  MOV  Dy12, BX              { 100e:02d8                                     }
  MOV  AX, X3                { 100e:02db                                     }
  SUB  AX, X1                { 100e:02de                                     }
  MOV  Dx12, AX              { 100e:02e1                                     }
  MOV  CX, AX                { 100e:02e4                                     }
  CWD                        { 100e:02e6                                     }
  IDIV BX                    { 100e:02e7                                     }
  CMP  CX, 0                 { 100e:02e9                                     }
  JGE  @FTKeep1              { 100e:02ec                                     }
  DEC  AX                    { 100e:02ee                                     }
  ADD  DX, BX                { 100e:02ef                                     }
@FTKeep1:
  MOV  Stp12, AX             { 100e:02f1                                     }
  MOV  Err12, DX             { 100e:02f4                                     }
  MOV  BX, Y3                { 100e:02f7  edge 2->3, into the 1->3 slots     }
  SUB  BX, Y2                { 100e:02fa                                     }
  MOV  Dy13, BX              { 100e:02fd                                     }
  MOV  AX, X3                { 100e:0300                                     }
  SUB  AX, X2                { 100e:0303                                     }
  MOV  Dx13, AX              { 100e:0306                                     }
  MOV  CX, AX                { 100e:0309                                     }
  CWD                        { 100e:030b                                     }
  IDIV BX                    { 100e:030c                                     }
  CMP  CX, 0                 { 100e:030e                                     }
  JGE  @FTKeep2              { 100e:0311                                     }
  DEC  AX                    { 100e:0313                                     }
  ADD  DX, BX                { 100e:0314                                     }
@FTKeep2:
  MOV  Stp13, AX             { 100e:0316                                     }
  MOV  Err13, DX             { 100e:0319                                     }
  MOV  AX, 0                 { 100e:031c                                     }
  MOV  BX, 0                 { 100e:031f                                     }
  MOV  CX, Y1                { 100e:0322                                     }
  MOV  DI, X1                { 100e:0325  the two ends of the flat top       }
  MOV  SI, X2                { 100e:0328                                     }
  XOR  DX, DX                { 100e:032b                                     }
  CMP  CX, ClipTop           { 100e:032d                                     }
  JGE  @FTLoop               { 100e:0331                                     }
  MOV  DX, ClipTop           { 100e:0333                                     }
  MOV  Y1, DX                { 100e:0337                                     }
  MOV  DX, Y1                { 100e:033a                                     }
  CMP  DX, Y3                { 100e:033d                                     }
  JNZ  @FTReset              { 100e:0340                                     }
  JMP  @Done                 { 100e:0342                                     }
@FTReset:
  XOR  DX, DX                { 100e:0345                                     }
@FTLoop:
  CMP  CX, ClipTop           { 100e:0347                                     }
  JL   @FTStep               { 100e:034b                                     }
  MOV  ES, BX                { 100e:034d                                     }
  MOV  BX, DX                { 100e:034f                                     }
  MOV  [BX + OFFSET EdgeBuf], DI       { 100e:0351                                     }
  MOV  BX, ES                { 100e:0355                                     }
  ADD  DX, 2                 { 100e:0357                                     }
  MOV  ES, BX                { 100e:035a                                     }
  MOV  BX, DX                { 100e:035c                                     }
  MOV  [BX + OFFSET EdgeBuf], SI       { 100e:035e                                     }
  MOV  BX, ES                { 100e:0362                                     }
  ADD  DX, 2                 { 100e:0364                                     }
@FTStep:
  ADD  AX, Err12             { 100e:0367                                     }
  JLE  @FTNoCarry1           { 100e:036a                                     }
  SUB  AX, Dy12              { 100e:036c                                     }
  INC  DI                    { 100e:036f                                     }
@FTNoCarry1:
  ADD  DI, Stp12             { 100e:0370                                     }
  ADD  BX, Err13             { 100e:0373                                     }
  JLE  @FTNoCarry2           { 100e:0376                                     }
  SUB  BX, Dy13              { 100e:0378                                     }
  INC  SI                    { 100e:037b                                     }
@FTNoCarry2:
  ADD  SI, Stp13             { 100e:037c                                     }
  INC  CX                    { 100e:037f                                     }
  CMP  CX, ClipBottom        { 100e:0380                                     }
  JL   @FTEnd                { 100e:0384                                     }
  MOV  Y3, CX                { 100e:0386                                     }
  JMP  @Span                 { 100e:0389                                     }
@FTEnd:
  CMP  CX, Y3                { 100e:038c                                     }
  JL   @FTLoop               { 100e:038f                                     }
  JMP  @Span                 { 100e:0391                                     }

{ ======== flat bottom: Y2 = Y3, one apex at vertex 1 ======== }
@FlatBot:
  MOV  X1, AX                { 100e:0394                                     }
  MOV  Y1, BX                { 100e:0397                                     }
  MOV  X2, CX                { 100e:039a                                     }
  MOV  Y2, DX                { 100e:039d                                     }
  MOV  DI, Y3                { 100e:03a0                                     }
  CMP  DI, ClipTop           { 100e:03a3                                     }
  JGE  @FlatBotB             { 100e:03a7                                     }
  JMP  @Done                 { 100e:03a9                                     }
@FlatBotB:
  MOV  DI, Y1                { 100e:03ac                                     }
  CMP  DI, ClipBottom        { 100e:03af                                     }
  JLE  @FlatBotEdges         { 100e:03b3                                     }
  JMP  @Done                 { 100e:03b5                                     }
@FlatBotEdges:
  MOV  BX, Y2                { 100e:03b8  edge 1->2                          }
  SUB  BX, Y1                { 100e:03bb                                     }
  MOV  Dy12, BX              { 100e:03be                                     }
  MOV  AX, X2                { 100e:03c1                                     }
  SUB  AX, X1                { 100e:03c4                                     }
  MOV  Dx12, AX              { 100e:03c7                                     }
  MOV  CX, AX                { 100e:03ca                                     }
  CWD                        { 100e:03cc                                     }
  IDIV BX                    { 100e:03cd                                     }
  CMP  CX, 0                 { 100e:03cf                                     }
  JGE  @FBKeep1              { 100e:03d2                                     }
  DEC  AX                    { 100e:03d4                                     }
  ADD  DX, BX                { 100e:03d5                                     }
@FBKeep1:
  MOV  Stp12, AX             { 100e:03d7                                     }
  MOV  Err12, DX             { 100e:03da                                     }
  MOV  BX, Y3                { 100e:03dd  edge 1->3                          }
  SUB  BX, Y1                { 100e:03e0                                     }
  MOV  Dy13, BX              { 100e:03e3                                     }
  MOV  AX, X3                { 100e:03e6                                     }
  SUB  AX, X1                { 100e:03e9                                     }
  MOV  Dx13, AX              { 100e:03ec                                     }
  MOV  CX, AX                { 100e:03ef                                     }
  CWD                        { 100e:03f1                                     }
  IDIV BX                    { 100e:03f2                                     }
  CMP  CX, 0                 { 100e:03f4                                     }
  JGE  @FBKeep2              { 100e:03f7                                     }
  DEC  AX                    { 100e:03f9                                     }
  ADD  DX, BX                { 100e:03fa                                     }
@FBKeep2:
  MOV  Stp13, AX             { 100e:03fc                                     }
  MOV  Err13, DX             { 100e:03ff                                     }
  MOV  AX, 0                 { 100e:0402                                     }
  MOV  BX, 0                 { 100e:0405                                     }
  MOV  CX, Y1                { 100e:0408                                     }
  MOV  DI, X1                { 100e:040b  both edges leave the same apex     }
  MOV  SI, X1                { 100e:040e                                     }
  XOR  DX, DX                { 100e:0411                                     }
  CMP  CX, ClipTop           { 100e:0413                                     }
  JGE  @FBLoop               { 100e:0417                                     }
  MOV  DX, ClipTop           { 100e:0419                                     }
  MOV  Y1, DX                { 100e:041d                                     }
  MOV  DX, Y1                { 100e:0420                                     }
  CMP  DX, Y3                { 100e:0423                                     }
  JNZ  @FBReset              { 100e:0426                                     }
  JMP  @Done                 { 100e:0428                                     }
@FBReset:
  XOR  DX, DX                { 100e:042b                                     }
@FBLoop:
  CMP  CX, ClipTop           { 100e:042d                                     }
  JL   @FBStep               { 100e:0431                                     }
  MOV  ES, BX                { 100e:0433                                     }
  MOV  BX, DX                { 100e:0435                                     }
  MOV  [BX + OFFSET EdgeBuf], DI       { 100e:0437                                     }
  MOV  BX, ES                { 100e:043b                                     }
  ADD  DX, 2                 { 100e:043d                                     }
  MOV  ES, BX                { 100e:0440                                     }
  MOV  BX, DX                { 100e:0442                                     }
  MOV  [BX + OFFSET EdgeBuf], SI       { 100e:0444                                     }
  MOV  BX, ES                { 100e:0448                                     }
  ADD  DX, 2                 { 100e:044a                                     }
@FBStep:
  ADD  AX, Err12             { 100e:044d                                     }
  JLE  @FBNoCarry1           { 100e:0450                                     }
  SUB  AX, Dy12              { 100e:0452                                     }
  INC  DI                    { 100e:0455                                     }
@FBNoCarry1:
  ADD  DI, Stp12             { 100e:0456                                     }
  ADD  BX, Err13             { 100e:0459                                     }
  JLE  @FBNoCarry2           { 100e:045c                                     }
  SUB  BX, Dy13              { 100e:045e                                     }
  INC  SI                    { 100e:0461                                     }
@FBNoCarry2:
  ADD  SI, Stp13             { 100e:0462                                     }
  INC  CX                    { 100e:0465                                     }
  CMP  CX, ClipBottom        { 100e:0466                                     }
  JL   @FBEnd                { 100e:046a                                     }
  MOV  Y3, CX                { 100e:046c                                     }
  JMP  @Span                 { 100e:046f                                     }
@FBEnd:
  CMP  CX, Y3                { 100e:0471                                     }
  JL   @FBLoop               { 100e:0474                                     }

{ ======== the spans, read back out of EdgeBuf from the bottom up ======== }
@Span:
  CLD                        { 100e:0476                                     }
  MOV  CX, Y3                { 100e:0477  the last row reached               }
  MOV  AX, Segment           { 100e:047a                                     }
  MOV  ES, AX                { 100e:047d                                     }
  SUB  DX, 2                 { 100e:047f  step back onto the last word       }
@SpanRow:
  MOV  BX, DX                { 100e:0482                                     }
  MOV  AX, [BX + OFFSET EdgeBuf]       { 100e:0484  the SI edge -- the right-hand X    }
  CMP  AX, ClipRight         { 100e:0488                                     }
  JLE  @SpanR                { 100e:048c                                     }
  MOV  AX, ClipRight         { 100e:048e                                     }
@SpanR:
  MOV  RightX, AX            { 100e:0491                                     }
  SUB  DX, 2                 { 100e:0494                                     }
  MOV  BX, DX                { 100e:0497                                     }
  MOV  AX, [BX + OFFSET EdgeBuf]       { 100e:0499  the DI edge -- the left-hand X     }
  CMP  AX, ClipLeft          { 100e:049d                                     }
  JGE  @SpanL                { 100e:04a1                                     }
  MOV  AX, ClipLeft          { 100e:04a3                                     }
@SpanL:
  SUB  DX, 2                 { 100e:04a6  on to the row above                }
  CMP  CX, ClipTop           { 100e:04a9                                     }
  JL   @SpanNext             { 100e:04ad                                     }
  CMP  CX, ClipBottom        { 100e:04af                                     }
  JG   @SpanNext             { 100e:04b3                                     }
  MOV  BX, CX                { 100e:04b5                                     }
  ADD  BX, BX                { 100e:04b7                                     }
  MOV  DI, [BX + OFFSET RowOfs]        { 100e:04b9                                     }
  ADD  DI, AX                { 100e:04bd  ES:DI is the left end of the span  }
  MOV  BX, RightX            { 100e:04bf                                     }
  SUB  BX, AX                { 100e:04c2  BX := the width                    }
  JLE  @SpanNext             { 100e:04c4                                     }
  MOV  AX, BX                { 100e:04c6  rotate: CX := width, BX := the row }
  MOV  BX, CX                { 100e:04c8                                     }
  MOV  CX, AX                { 100e:04ca                                     }
  MOV  AX, WORD PTR Colour   { 100e:04cc                                     }
  MOV  AH, AL                { 100e:04cf  the same byte in both halves       }
  SHR  CX, 1                 { 100e:04d1                                     }
  REP  STOSW                 { 100e:04d3                                     }
  JNC  @SpanEven             { 100e:04d5                                     }
  STOSB                      { 100e:04d7  odd width: one byte left over      }
@SpanEven:
  MOV  CX, BX                { 100e:04d8  CX is the row again                }
@SpanNext:
  DEC  CX                    { 100e:04da                                     }
  CMP  CX, Y1                { 100e:04db                                     }
  JG   @SpanRow              { 100e:04de                                     }
@Done:
  POP  DI                    { 100e:04e0                                     }
  POP  ES                    { 100e:04e1                                     }
end;

{ --------------------------------------------------------------------------
  100e:04e6 -- scene 1's own row table. The VGA unit has one; this scene does
  not use it, and builds its own at DS:$5dfe.
  -------------------------------------------------------------------------- }
procedure BuildRowTable;
var I : Integer;
begin
  for I := 0 to 199 do RowOfs[I] := I * 320;    { 100e:04f4, IMUL AX,I,$140 }
end;

{ --------------------------------------------------------------------------
  100e:050b -- the 32 x 32 grid, centred on the origin and pushed back to
  Z = 300 so the projection has something to divide by.
  -------------------------------------------------------------------------- }
procedure BuildGrid;
var I : Integer;
begin
  for I := 0 to GridVerts - 1 do
  begin
    Grid[I].X := ((I mod GridSide) - 16) * Spacing;   { 100e:051d, IDIV 32 }
    Grid[I].Y := ((I shr 5) - 16) * Spacing;          { 100e:053b, SHR -- so
                                                        unsigned, not IDIV }
    Grid[I].Z := RestZ;                               { 100e:055e }
  end;
end;

{ --------------------------------------------------------------------------
  100e:056d -- turn the height map into Z values at a given threshold.

  Anything at or below the threshold sits on the base plane; anything above it
  is pulled TOWARDS the viewer by however far it clears the threshold. So
  lowering the threshold raises more of the landscape, and that is the whole
  animation.
  -------------------------------------------------------------------------- }
procedure HeightFromMap(Threshold : Byte);
var I : Integer;
begin
  for I := 0 to GridVerts - 1 do
    if HeightMap[I] > Threshold then                  { 100e:058b, JBE }
      Grid[I].Z := BaseZ - (HeightMap[I] - Threshold)
    else
      Grid[I].Z := BaseZ;                             { 100e:05c2 }
end;

{ --------------------------------------------------------------------------
  100e:05d3 -- project the grid. HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 0 to 1023 do
      begin
        Proj[I].SX  := 160 - (Grid[I].X shl 6) div Grid[I].Z;
        Proj[I].SY  := 100 - ((-Grid[I].Y) shl 6) div Grid[I].Z;
        Proj[I].Col := ((250 - Grid[I].Z) mod 255) + 1;
      end;

  The original cannot be written that way: it USES BP AS A SCRATCH REGISTER
  for Z, which is why it pushes BP separately from the frame, and it walks
  both arrays with LODSW/STOSW rather than indexing them.
  -------------------------------------------------------------------------- }
{ @asm 005 100e:05d3 +87 Project }
procedure Project(Src, Dst : Pointer); assembler;
asm
  PUSH DS                { 100e:05d6  DS is about to be the source array     }
  PUSH BP                { 100e:05d7  and BP is about to hold Z              }
  MOV  CX, 0FFh * 4 + 3  { 100e:05d8  1023 -- written $3FF in the binary     }
  LDS  SI, Src           { 100e:05db  DS:SI := the grid                      }
  LES  DI, Dst           { 100e:05de  ES:DI := the projected vertices        }
@Point:
  PUSH CX                { 100e:05e1  CX is needed for the divide            }
  LODSW                  { 100e:05e2  AX := X                                }
  SHL  AX, 6             { 100e:05e3  X * 64 -- the focal length             }
  MOV  BX, AX            { 100e:05e6                                         }
  LODSW                  { 100e:05e8  AX := Y                                }
  NEG  AX                { 100e:05e9  screen Y runs downwards                }
  SHL  AX, 6             { 100e:05eb                                         }
  MOV  CX, AX            { 100e:05ee                                         }
  LODSW                  { 100e:05f0  AX := Z                                }
  MOV  BP, AX            { 100e:05f1  <- BP, not a frame pointer any more    }
  MOV  AX, BX            { 100e:05f3                                         }
  MOV  BX, BP            { 100e:05f5                                         }
  CWD                    { 100e:05f7                                         }
  IDIV BX                { 100e:05f8  (X*64) div Z                           }
  MOV  BX, 0A0h          { 100e:05fa  160 -- the centre of the screen        }
  SUB  BX, AX            { 100e:05fd                                         }
  MOV  AX, BX            { 100e:05ff                                         }
  STOSW                  { 100e:0601  -> SX                                  }
  MOV  AX, CX            { 100e:0602                                         }
  MOV  CX, BP            { 100e:0604                                         }
  CWD                    { 100e:0606                                         }
  IDIV CX                { 100e:0607  (-Y*64) div Z                          }
  MOV  CX, 64h           { 100e:0609  100 -- the middle row                  }
  SUB  CX, AX            { 100e:060c                                         }
  MOV  AX, CX            { 100e:060e                                         }
  STOSW                  { 100e:0610  -> SY                                  }
  MOV  AX, 0FAh          { 100e:0611  250                                    }
  SUB  AX, BP            { 100e:0614  how far this point stands proud        }
  MOV  BX, 0FFh          { 100e:0616                                         }
  CWD                    { 100e:0619                                         }
  IDIV BX                { 100e:061a                                         }
  MOV  AX, DX            { 100e:061c  the REMAINDER, not the quotient        }
  INC  AX                { 100e:061e  colour 0 is the background             }
  STOSB                  { 100e:061f  -> Col, so the record is five bytes    }
  POP  CX                { 100e:0620                                         }
  DEC  CX                { 100e:0621                                         }
  JNS  @Point            { 100e:0622  JNS, so 1024 points and not 1023       }
  POP  BP                { 100e:0624                                         }
  POP  DS                { 100e:0625                                         }
end;

{ --------------------------------------------------------------------------
  100e:062a -- draw the whole mesh. HAND ASSEMBLER, verbatim.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      ClearScreen(VirtScrSeg, 0);
      for T := 1 to 1922 do
        FillTriangle(Proj[Tri[T,1]].SX, Proj[Tri[T,1]].SY,
                     Proj[Tri[T,2]].SX, Proj[Tri[T,2]].SY,
                     Proj[Tri[T,3]].SX, Proj[Tri[T,3]].SY,
                     Proj[Tri[T,3]].Col, VirtScrSeg);
      CopyScreen(VirtScrSeg, $A000);

  Two things stop that being the same code. The vertex record is five bytes,
  so the original indexes it as I*4 + I rather than by a multiply; and the
  colour byte is fetched by reading the WORD at +3 and keeping its high half,
  which is one instruction shorter than a byte load.
  -------------------------------------------------------------------------- }
{ @asm 005 100e:062a +132 DrawMesh }
procedure DrawMesh(Verts, Tris : Pointer); assembler;
var
  { 100e:062a is ENTER $0002,0 -- one word of locals that NOTHING in the
    routine reads. It is declared so the frame is the size the binary has;
    leaving it out makes Turbo Pascal emit a bare PUSH BP / MOV BP,SP and the
    whole routine shifts. What the original meant it for is not recoverable. }
  Unused : Integer;
asm
  PUSH VirtScrSeg        { 100e:062e                                         }
  PUSH 0                 { 100e:0632                                         }
  CALL ClearScreen       { 100e:0634                                         }
  PUSH DS                { 100e:0639  DS is about to be the triangle list    }
  MOV  DX, VirtScrSeg    { 100e:063a  kept in DX for the whole loop          }
  MOV  CX, 782h          { 100e:063e  1922 triangles                         }
  LDS  SI, Tris          { 100e:0641                                         }
  LES  DI, Verts         { 100e:0644                                         }
  MOV  BX, DI            { 100e:0647  BX := the base of the vertex array     }
@Tri:
  PUSHA                  { 100e:0649  186: save everything, SI included      }
  LODSW                  { 100e:064a  the first vertex index                 }
  MOV  DI, AX            { 100e:064b                                         }
  SHL  AX, 2             { 100e:064d  I*4                                    }
  ADD  DI, AX            { 100e:0650    + I = I*5, the record size           }
  ADD  DI, BX            { 100e:0652                                         }
  MOV  AX, ES:[DI]       { 100e:0654  SX                                     }
  PUSH AX                { 100e:0657                                         }
  ADD  DI, 2             { 100e:0658                                         }
  MOV  AX, ES:[DI]       { 100e:065b  SY                                     }
  PUSH AX                { 100e:065e                                         }
  LODSW                  { 100e:065f  the second vertex                      }
  MOV  DI, AX            { 100e:0660                                         }
  SHL  AX, 2             { 100e:0662                                         }
  ADD  DI, AX            { 100e:0665                                         }
  ADD  DI, BX            { 100e:0667                                         }
  MOV  AX, ES:[DI]       { 100e:0669                                         }
  PUSH AX                { 100e:066c                                         }
  ADD  DI, 2             { 100e:066d                                         }
  MOV  AX, ES:[DI]       { 100e:0670                                         }
  PUSH AX                { 100e:0673                                         }
  LODSW                  { 100e:0674  the third vertex                       }
  MOV  DI, AX            { 100e:0675                                         }
  SHL  AX, 2             { 100e:0677                                         }
  ADD  DI, AX            { 100e:067a                                         }
  ADD  DI, BX            { 100e:067c                                         }
  MOV  AX, ES:[DI]       { 100e:067e                                         }
  PUSH AX                { 100e:0681                                         }
  ADD  DI, 2             { 100e:0682                                         }
  MOV  AX, ES:[DI]       { 100e:0685                                         }
  PUSH AX                { 100e:0688                                         }
  INC  DI                { 100e:0689  now at +3 of the third vertex          }
  MOV  AX, ES:[DI]       { 100e:068a  a WORD read spanning +3 and +4         }
  MOV  AL, AH            { 100e:068d  and only the high half is the colour   }
  XOR  AH, AH            { 100e:068f                                         }
  PUSH AX                { 100e:0691                                         }
  PUSH DX                { 100e:0692  the destination segment                }
  CALL FillTriangle      { 100e:0693                                         }
  POPA                   { 100e:0696  which puts SI back where it was        }
  ADD  SI, 6             { 100e:0697  so step it over the three indices here }
  DEC  CX                { 100e:069a                                         }
  JNZ  @Tri              { 100e:069b                                         }
  POP  DS                { 100e:069d                                         }
  PUSH VirtScrSeg        { 100e:069e                                         }
  PUSH 0A000h            { 100e:06a2                                         }
  CALL CopyScreen        { 100e:06a5                                         }
end;

{ 100e:073c -- colours 1..45 get a blue ramp from 20 to 64. }
procedure BuildRamp;
var I : Byte;
begin
  for I := $1E to $4A do SetRGB(I - $1D, 0, 0, I - $0A);
end;

{ 100e:076c -- bring colour 1 up out of black, a step every 50 ms. }
procedure FadeUpDot;
var I : Byte;
begin
  for I := 1 to $14 do
  begin
    SetRGB(1, 0, 0, I);
    Delay($32);
  end;
end;

{ --------------------------------------------------------------------------
  100e:06ae -- sweep the threshold down from A to B and back up again,
  redrawing the mesh at every step. Both loops are guarded, so an inverted
  pair simply does nothing.
  -------------------------------------------------------------------------- }
procedure Morph(A, B : Byte);
var T : Integer;
begin
  for T := A downto B do                         { 100e:06c2, JC guard }
  begin
    HeightFromMap(T);
    Project(@Grid, @Proj);
    DrawMesh(@Proj, @MeshTris);
  end;
  for T := B to A do                             { 100e:0705, JA guard }
  begin
    HeightFromMap(T);
    Project(@Grid, @Proj);
    DrawMesh(@Proj, @MeshTris);
  end;
end;

{ --------------------------------------------------------------------------
  100e:07a4 -- the scene.

  ASSETS  NEUROSIS.DAT $00153DE5, three 1024-byte greyscale height maps read
          back to back, each 32 x 32.
  -------------------------------------------------------------------------- }
procedure Scene1;
begin
  Assign(F, 'neurosis.dat');                     { 100e:07b1 }
  Reset(F, 1);
  Seek(F, DataOfs);

  SetRGB(1, 0, 0, 0);                            { 100e:07d1 -- start black }
  BuildGrid;                                     { 100e:07de }
  BuildRowTable;                                 { 100e:07e1 }

  { 100e:07e4 -- the map is still all zeroes here, so every point comes out at
    the base plane. This is what makes the first frame a flat sheet. }
  HeightFromMap($37);
  Project(@Grid, @Proj);                         { 100e:07f3 }
  DrawMesh(@Proj, @MeshTris);                    { 100e:0800 }

  FadeUpDot;                                     { 100e:0803 }
  BuildRamp;                                     { 100e:0806 }

  BlockRead(F, HeightMap, MapSize);              { 100e:081a }
  Morph($41, $14);                               { 100e:0823 }
  BlockRead(F, HeightMap, MapSize);              { 100e:0837 }
  Morph($41, $14);                               { 100e:0840 }
  BlockRead(F, HeightMap, MapSize);              { 100e:0854 }
  Morph($37, $05);                               { 100e:085d }

  ClearScreen($A000, 0);                         { 100e:0865 }
  Close(F);                                      { 100e:086f }
end;

{ 100e:0876 -- the unit's initialisation is empty. }
begin
end.
