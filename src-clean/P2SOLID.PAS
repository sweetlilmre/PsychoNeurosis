{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, scene 2.

  Segment 108b, transcribed from the disassembly. No inference, no stubs.
  See docs/22-part002-scene2.md for the working notes.

  WHAT THE SCENE IS

  Solid-filled 3-D objects over a 500-point starfield, in unchained 320x400
  with two 320x240 pages, plus a 320x40 banner strip along the bottom that two
  lines of text type themselves onto a character at a time.

  ROUTINE MAP }

unit P2SOLID;

{ I/O checking off -- see the note in P2GARAGE. }
{$I-}

(* 80x87 CODE ON: the projection scale is computed in floating point.

   Found the same way as FixMath's, one span later. *)
(* DATA ALIGNMENT OFF, and the frame layout is what says so.

   SizeOf(TObj) is 2897 either way -- Turbo Pascal packs record FIELDS
   regardless, and this switch governs only where a VARIABLE starts. So the
   record layout was never the discrepancy, and looking there first cost a
   while. *)
{$A-}

{$N+}

{ 286 instructions are permitted -- every routine here is ENTER-framed. }
{$G+}

interface

procedure Scene2;

implementation

uses Crt, VGA, FixMath, P2View, DemoVT;

{ Where each asset sits inside NEUROSIS.DAT. }
{$I gen/DATOFS.INC}

{$I gen/P2OBJ.INC}

const
  { 240 rows of 80 bytes per plane. }
  Rows        = 240;
  { The object record is $B51 bytes and the sub-arrays tile it exactly:
    4 + 75*12 + 75*6 + 65*23 + 4*12 = 2897. }
  MaxVerts    = 75;
  MaxFaces    = 65;
  FaceVerts   = 8;

  { initialised data. The projection
    centre is (160, 120), the 320x240 field, NOT (160, 100). They are typed
    constants further down rather than consts here, because Project reads
    them FROM MEMORY and the shared maths object resolves them by name. }
  ScaleDivisor = 2.0;
  ScaleFactor  = 0.9;

  { The clip box moved to a TYPED constant block beside Tri_Fill, which
    is the only reader and reads it FROM MEMORY. }

  StarCount = 500;                { $1F4 }
  TextY1    = 210;                { $D2 }
  TextY2    = 217;                { $D9 }
  TextCol   = $42;                { the green set by Scene2_Setup }
  RewindW   = 34;                 { $22 }
  RewindH   = 43;                 { $2B }
  BannerTop = 200;                { $C8 }
  BannerH   = 40;
  FontFirst = 32;                 { the glyph table starts at char $20 }
  FontCount = 62;                 { 1550 bytes / 25 }
  GlyphSide = 5;

  DataOfs   = DAT_P2_BANNSTRP;   { where the scene's assets start          }

type
  TVertex = record X, Y, Z : LongInt end;    { 16.16, hence 12 bytes }
  TScreen = record X, Y, D : Integer end;
  { 23 bytes in the original: count, eight indices, colour, two spare bytes,
    then the average depth the sort writes at +$15. }
  TFace = record
    Count  : Integer;
    Idx    : array[1..FaceVerts] of Integer;
    Colour : Byte;
    Spare1 : Byte;
    Spare2 : Byte;
    Depth  : Integer;
  end;
  { Named so a renderer's local copy can be ASSIGNED from the field: an
    anonymous array type is not assignment-compatible with another. }
  TFaceArray = array[1..MaxFaces] of TFace;
  TVec3 = record X, Y, Z : LongInt end;   { +0, +4, +8 }
  TObj = record
    VertCount : Integer;                        { +$000 }
    FaceCount : Integer;                        { +$002 }
    Vert  : array[1..MaxVerts] of TVertex;      { +$004 }
    Scr   : array[1..MaxVerts] of TScreen;      { +$388 }
    Face  : TFaceArray;                         { +$54A }
    { RECORDS, NOT array[1..3], and a probe settled it rather than an
      argument. ObjTransform's frame is ENTER $36 and the reconstruction's
      was $30 with the declared locals already matching byte for byte; the
      six-byte gap is two far-pointer spills the compiler makes for NESTED
      `with` over a RECORD. probe/WITHTMP.PAS compiles the same routine four
      ways with identical declarations -- arrays plain $30, arrays with $34,
      records plain $30, RECORDS WITH $36 -- so it takes both changes and
      neither alone. Confirmed in the rebuild: ObjTransform now opens
      ENTER $36 and part 002's coverage walk moved 51.0% to 53.0%. }
    Angle : TVec3;                              { +$B21 }
    Trans : TVec3;                              { +$B2D }
    Pivot : TVec3;                              { +$B39 }
    Accum : TVec3;                              { +$B45 }
  end;
  TObjPtr = ^TObj;

  TStar = record X, Y, Z : Integer end;         { stride 6 }
  { 1,550 bytes -- assets/part002/FONT5X5.BIN }
  TFont = array[FontFirst..FontFirst + FontCount - 1,
                1..GlyphSide, 1..GlyphSide] of Byte;
  { the GetMem'd 12,800 bytes -- assets/part002/BANNER.PNG }
  TBanner = array[0..BannerH - 1, 0..ScrWidth - 1] of Byte;
  { 1,462 bytes -- assets/part002/REWIND.BIN }
  TRewind = array[1..RewindH, 1..RewindW] of Byte;

{ THE WHOLE OF THIS UNIT'S BSS IS IN ADDRESS ORDER, and the order was read off
  the original rather than chosen. Every anchor below is a displacement in the
  original's own code, paired against ours instruction by instruction -- which
  is only sound because every routine in segment 108b is already the right
  LENGTH, so a memory operand at a given code offset on one side is the
  counterpart of the operand at that offset on the other.

      $5148  Pal        768        $A043  DatFile    128
      $5448  Font      1550        $A0C3  Banner       4
      $5A56  Obj      11588        $A0C7  SaveVol      1
      $879A  Dead1       18        $A0C8  CurVol       1
      $87AC  MCos1..MSin3 24       $A0C9  Dead4        1
      $87C4  MScale       4        $A0CA  RowOfs     480
      $87C8  FaceCopy  1495        $A2AA  Span       964
             Dead2      305        $A66E  Dead5       40
      $8ED0  SetupDone    1        $A696  -- P2View's block begins
      $8ED1  Frame        4
      $8ED5  Rewind    1462
      $948B  Star      3000

  FOUR OF THOSE ROWS ARE DEAD SPACE, 364 bytes of it, and they are declared
  because the original's DGROUP contains them. Nothing in NEUROSIS.002
  references any byte of Dead1, Dead2, Dead4 or Dead5 -- no absolute operand,
  no folded array base, no immediate loaded into a register -- so their SIZES
  and POSITIONS are measured and their identities are not recoverable from the
  binary. FaceCopy is unreferenced too and is the same kind of thing: 1,495
  bytes the compiler allocates for a snapshot array no code reads. That it
  shares the 1,800-byte hole with Dead2 is certain; where inside the hole it
  sits is not, so this puts it first and the padding after.

  Leaving them out is what put every variable above them at the wrong address
  and, through P2View, put part 002's whole upper DGROUP 2,614 bytes early. }

var
  Pal    : TPalette;
  Font   : TFont;
  Obj    : array[1..4] of TObj;
  { see the table above. Obj ends at $8799, MCos1 is at
    $87AC, and nothing reads the eighteen bytes between. }
  Dead1  : array[1..18] of Byte;

{ --------------------------------------------------------------------------
  THE SHARED 386 MATHS MODULE.

  The nine names below are the module's EXTRNs, so they have to be declared
  BEFORE the $L directive and spelled exactly this way.
  -------------------------------------------------------------------------- }
  MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt;
  { the projection scale, 16.16 }
  MScale : LongInt;
  { the snapshot Obj_SortFaces was to work from, and NOTHING reads
    it, here or in the original. 1,495 bytes. }
  FaceCopy : array[1..MaxFaces] of TFace;
  { The 305 bytes that close the 1,800-byte hole between MScale and
    SetupDone. }
  Dead2  : array[1..305] of Byte;
  SetupDone : Byte;
  { a LongInt frame counter, and what drives the text. }
  Frame  : LongInt;
  { 1,462 bytes -- assets/part002/REWIND.BIN }
  Rewind : TRewind;
  { 500 records of six bytes, immediately after Rewind. The star
    plot's folded base is $9485, one stride below. }
  Star   : array[1..StarCount] of TStar;
  DatFile : file;
  { the GetMem'd 12,800 bytes, and its pointer begins exactly
    where DatFile's 128 bytes end. }
  Banner : ^TBanner;
  SaveVol : Byte;
  CurVol  : Byte;
  { A THIRD BYTE, and the unit's A-minus is what makes it visible.
    With alignment off RowOfs would follow CurVol at $A0C9; the original has it
    at $A0CA, so one more byte stands between them. Under A-plus this would be
    indistinguishable from padding. }
  Dead4  : Byte;
  { RowOfs80[I] = I * 80. }
  RowOfs : array[0..Rows - 1] of Word;
  Span : array[0..2 * Rows + 1] of Integer;
  Dead5  : array[1..38] of Byte;



const
  MViewW : Word = 320;
  MViewH : Word = 240;

  Msg1 : String = 'CAPTAINS LOG, STARDATE 426987.2, SUPPLIMENTAL  :           ';
  Msg2 : String = '     PICTURE IT,   SICILY,   1942 ....               ';

{$L DEMOMATH.OBJ}

{ --------------------------------------------------------------------------
SinCos(Angle : Integer; var C, S : LongInt)

RotatePoint(var X, Y, Z : LongInt)

  Three concatenated 2-D rotations, X then Y then Z:

      y1 = y*C1 + z*S1      z1 = z*C1 - y*S1
      x2 = x*C2 - z1*S2     z2 = z1*C2 + x*S2
      x3 = x2*C3 + y1*S3    y3 = y1*C3 - x2*S3

Project(var X, Y, Z : LongInt)

      Sx := Round(X/Z * MScale) + MViewW div 2
      Sy := MViewH div 2 - Round(Y/Z * MScale)

  All three are in src/asm/DEMOMATH.ASM, commented there. An earlier version
  of this file had them as Pascal over Reals, which is a different program:
  the original's multiply is 32x32->64 taking the MIDDLE 32 bits, and its
  divide builds a 48-bit dividend so the quotient comes out 16.16. Neither
  fits in a Turbo Pascal LongInt.
  -------------------------------------------------------------------------- }
procedure SinCos(A : Integer; var C, S : LongInt);      external;
procedure RotatePoint(var X, Y, Z : LongInt);           external;
procedure Project(var X, Y, Z : LongInt);               external;


{ --------------------------------------------------------------------------
DrawText(X, Y, S)

  a clean 5 x 5 glyph biased by 32, the same shape as the fonts in part 001.
  R is the horizontal axis and C the vertical; the pen steps 6 per character.
  Every pixel is drawn in colour $42.
  -------------------------------------------------------------------------- }
procedure DrawText(X, Y : Integer; S : String);
var
  I, R, C, Pen : Integer;
begin
  Pen := 0;
  for I := 1 to Length(S) do
  begin
    for R := 1 to GlyphSide do
      for C := 1 to GlyphSide do
        if Font[Ord(S[I]), R, C] <> 0 then
          Plot(R + X + Pen, C + Y, TextCol);
    Inc(Pen, 6);
  end;
end;


{ --------------------------------------------------------------------------
Obj_SetRotation(var Obj; A1, A2, A3)

  Also badly named: this is the whole per-frame transform.

  Step 2's sines and cosines are therefore used only for the pivot. That is
  what the code does.
  -------------------------------------------------------------------------- }
{  THE TWO DEAD BLOCKS ARE TRANSCRIBED DELIBERATELY. Their sizes and positions
  are measured; their types are not recoverable, because nothing reads them --
  12 bytes in the same place as V and P is most likely a third vector the
  author stopped using. Leaving them out is not a tidier reconstruction, it is
  a wrong one: every local after them moves, and the frame stops being $36. }
procedure ObjTransform(var O : TObj; A1, A2, A3 : LongInt);
var
  Unused1 : array[1..2] of LongInt;   { never read }
  I       : Integer;
  Unused2 : array[1..3] of LongInt;   { never read }
  { TVec3, NOT `array[1..3] of LongInt`: the whole-variable assignments
    below only compile if the two sides are the SAME type, and the pivot
    they copy is a TVec3 field of the object. }
  V       : TVertex;                  { the working vertex, and
                                        TVertex because that is what Vert
                                        holds and the assignment needs the
                                        same type on both sides }
  P       : TVec3;                    { the rotated pivot }
begin
  with O do
  begin
    with Accum do
    begin
      if X < 0 then X := X + 3600;
      if Y < 0 then Y := Y + 3600;
      if Z < 0 then Z := Z + 3600;
      SinCos(X, MCos1, MSin1);          { through the same temp }
      SinCos(Y, MCos2, MSin2);
      SinCos(Z, MCos3, MSin3);
    end;

    P := Pivot;                         { a 12-byte copy }
    RotatePoint(P.X, P.Y, P.Z);

    with Angle do
    begin
      { the scratch temp is set up BEFORE these wraps, which is what says the
        `with` opens here rather than after them }
      if A1 < 0 then A1 := A1 + 3600;
      if A2 < 0 then A2 := A2 + 3600;
      if A3 < 0 then A3 := A3 + 3600;
      X := A1;  Y := A2;  Z := A3;
      SinCos(X, MCos1, MSin1);
      SinCos(Y, MCos2, MSin2);
      SinCos(Z, MCos3, MSin3);
    end;

    for I := 1 to VertCount do
    begin
      V := Vert[I];                     { likewise }
      RotatePoint(V.X, V.Y, V.Z);
      V.X := V.X + P.X;
      V.Y := V.Y + P.Y;
      V.Z := V.Z + P.Z;
      V.X := V.X + O.Trans.X;
      V.Y := V.Y + O.Trans.Y;
      V.Z := V.Z + O.Trans.Z;
      Project(V.X, V.Y, V.Z);
      { both come back zero-extended, so the low word carries the sign }
      Scr[I].X := Integer(V.X);
      Scr[I].Y := Integer(V.Y);
      Scr[I].D := FixedToInt(V.Z);     { AFTER Project }
    end;
  end;
end;


{ --------------------------------------------------------------------------
Obj_AddRotation(var Obj; DX, DY, DZ)

  Despite the name, it adds to the TRANSLATION at Obj+$B2D, one IntToFixed per
  component. The call sites pass sign-extended LongInts of which the routine
  reads only the low word.
  -------------------------------------------------------------------------- }
procedure ObjTranslate(var O : TObj; DX, DY, DZ : LongInt);
begin
  with O.Trans do
  begin
    X := X + IntToFixed(DX);
    Y := Y + IntToFixed(DY);
    Z := Z + IntToFixed(DZ);
  end;
end;


{ --------------------------------------------------------------------------
DrawSprite }
procedure DrawRewind;
var
  X, Y : Integer;
begin
  for Y := 1 to RewindH do
    for X := 1 to RewindW do
      Plot(X, Y, Rewind[Y, X]);
end;


{ --------------------------------------------------------------------------
Tri_Fill, and it is HAND-WRITTEN ASSEMBLER

  And one MEASUREMENT, which is the one that does not rely on reading style.
  Of the 62 two-byte register-to-register ALU and MOV ops in this routine, 62
  use the store direction (`MOV AX,BX` as 89 D8) and NONE the load direction
  (8B C3). Every compiled-Pascal routine in this same segment is mixed --
  DrawText 56%, Obj_SortFaces 57%, Scene2_Setup 36%, Obj_SetRotation 27% --
  and so is DEMOMATH.OBJ at 30%, which TASM assembled. A 62-of-62 split is
  not a tendency, it is a tool that only ever emits one form.

  WHICH tool the rebuild then answered, and it is worth recording that the
  first reading of that measurement was WRONG. Because TASM came out mixed
  too, the inference drawn from it was that Tri_Fill's producer was neither
  the Pascal code generator nor TASM -- something foreign -- and that
  transcribing it through Borland's own assembler would therefore cost
  roughly 62 one-bit differences. Both halves of that were wrong. Borland's
  BASM emits the store direction consistently, so the split identifies BASM
  rather than excluding it, and the rebuild is byte-for-byte identical
  through all 64 bytes of the prologue and sort chain, `89 D8` and `89 D1`
  and `89 F2` included.

  WHAT THE REBUILD MEASURES, and it is the reason to believe the rest of this
  comment: 1,250 of 1,360 bytes identical, 91.9%, in 56 differing runs of
  which NONE is longer than two bytes and none is an opcode. Fifty-four are
  DGROUP addresses, which is what the coverage walk's default rule exists to
  forgive -- $066E against our clip box, $A2AA against our Span, $A0CA
  against RowOfs, $A69A against WritePage. The other two are single bytes at
 where a conditional has to bridge to a target too
  far for a short jump and BASM picks the opposite sense to the original's:
  ours is `JL` to a bridge that jumps to the flat-top walk, the original's is
  `JGE` to a bridge that jumps to the exit. The two are the same branch and
  the same behaviour. Poly_FillFan below rebuilds byte-identical, all 88.

  THE CALLING CONVENTION. Four arguments arrive in registers and three on
  the stack, and Poly_FillFan below is the only caller and cooperates:

  so only the last three can be declared. X1, Y1, X2 and Y2 are spilled to
  the first four locals immediately and then live in AX, BX, CX, DX.

  There are FOUR walk variants, not one, and which runs is decided by shape:

  and the two general ones are chosen by a 32-bit cross product at
(X2-X1)*(Y3-Y1) against (X3-X1)*(Y2-Y1), high words compared
  signed and low words unsigned, with equality meaning degenerate and
  exiting. Each general variant is itself two loops: the first runs to Y2
  with the short edge, the second to Y3 with the third edge swapped in. }
const
  ClipYMin : Integer = 0;
  ClipYMax : Integer = 239;
  ClipXMin : Integer = 0;
  ClipXMax : Integer = 319;
  LeftMask4  : array[0..3] of Byte = ($0F, $0E, $0C, $08);
  RightMask4 : array[0..3] of Byte = ($0F, $01, $03, $07);

{$I gen/P2OBJ2.INC}

procedure TriFill(X3, Y3 : Integer; Colour : Byte); assembler;
var
  SX1, SY1, SX2, SY2 : Integer;     { the sorted vertices }
  NumA, NumB, NumC   : Integer;     { the three dividends }
  DenA, DenB, DenC   : Integer;     { the three divisors  }
  RemA, RemB, RemC   : Integer;     { floored remainders  }
  StepA, StepB, StepC : Integer;    { floored quotients   }
  FillL, FillR       : Integer;     { the clipped span    }
  FillY              : Integer;     { the scanline being filled     }
  SpanIdx            : Integer;     { a BYTE index into Span        }
(* EQUIVALENT PASCAL -- REFERENCE ONLY, and it is NOT what is compiled. The
  assembler below is the transcription; this says what it means, so that a
  reader can follow the four walk variants without holding the register
  allocation in their head. It is deliberately not a working procedure: the
  four register arguments cannot be expressed, and the two dead instructions
  and the clip-clamped loop bounds are elided here but present below.

    procedure TriFill(X1, Y1, X2, Y2, X3, Y3 : Integer; Colour : Byte);
    var Step, Rem, Den : array['A'..'C'] of Integer;
        L, R, EL, ER, Y, Idx : Integer;

      procedure Edge(var Step, Rem, Den : Integer; DX, DY : Integer);
      begin                             { one edge's floored DDA setup      }
        Den  := DY;
        Step := DX div DY;              { truncated ...                     }
        Rem  := DX mod DY;
        if DX < 0 then                  { ... then floored, by hand         }
        begin Dec(Step); Inc(Rem, Den) end;
      end;

      procedure Walk(var AL, AR : Integer; SL, SR : Char);
      begin                             { one scanline of both edges        }
        if Y >= ClipYMin then
        begin
          Span[Idx] := AL; Span[Idx + 1] := AR; Inc(Idx, 2);
        end;
        Inc(EL, Rem[SL]);
        if EL > 0 then begin Dec(EL, Den[SL]); Inc(AL) end;
        Inc(AL, Step[SL]);
        Inc(ER, Rem[SR]);
        if ER > 0 then begin Dec(ER, Den[SR]); Inc(AR) end;
        Inc(AR, Step[SR]);
        Inc(Y);
      end;

    begin
      if (X1 = X2) and (X2 = X3) then Exit;
      SortThreeByY(X1, Y1, X2, Y2, X3, Y3);
      if (Y1 = Y2) and (Y2 = Y3) then Exit;
      if Y3 < ClipYMin then Exit;
      if Y1 > ClipYMax then Exit;

      Edge(Step['A'], Rem['A'], Den['A'], X2 - X1, Y2 - Y1);
      Edge(Step['B'], Rem['B'], Den['B'], X3 - X1, Y3 - Y1);
      if Y3 - Y2 > 0 then
        Edge(Step['C'], Rem['C'], Den['C'], X3 - X2, Y3 - Y2);

      { which side the middle vertex falls on, as a 32-bit cross product }
      if LongInt(X2 - X1) * (Y3 - Y1) = LongInt(X3 - X1) * (Y2 - Y1) then
        Exit;                           { collinear                         }
      if LongInt(X2 - X1) * (Y3 - Y1) > LongInt(X3 - X1) * (Y2 - Y1) then
      begin                             { A then C on the right }
        L := X1; R := X1; Y := Y1; Idx := 0; EL := 0; ER := 0;
        while Y < Y2 do Walk(L, R, 'B', 'A');
        while Y < Y3 do Walk(L, R, 'B', 'C');
      end
      else
      begin                             { A then C on the left  }
        L := X1; R := X1; Y := Y1; Idx := 0; EL := 0; ER := 0;
        while Y < Y2 do Walk(L, R, 'A', 'B');
        while Y < Y3 do Walk(L, R, 'C', 'B');
      end;
      { the flat-top and flat-bottom cases need only one loop each, and start
        L and R on the two ends of the flat edge }

      for Y := Y3 downto Y1 + 1 do      { BACKWARDS            }
      begin
        Dec(Idx, 2);
        R := Span[Idx + 1];  if R > ClipXMax then R := ClipXMax;
        L := Span[Idx];      if L < ClipXMin then L := ClipXMin;
        if (Y < ClipYMin) or (Y > ClipYMax) then Continue;
        D    := RowOfs[Y] + (L shr 2) + WritePage;
        Mid  := ((R - 1) - (L and $FFFC)) shr 2;
        LM   := LeftMask4[L and 3];
        RM   := RightMask4[R and 3];
        if R <= L then Continue;
        if Mid = 0 then LM := LM and RM;
        Port[$3C4] := 2;
        Port[$3C5] := LM;  Mem[$A000 : D] := Colour;
        if Mid > 0 then
        begin
          if Mid > 1 then
          begin
            Port[$3C5] := $0F;
            FillChar(Mem[$A000 : D + 1], Mid - 1, Colour);
          end;
          Port[$3C5] := RM;  Mem[$A000 : D + Mid] := Colour;
        end;
      end;
    end;
    EQUIVALENT PASCAL ends here -- REFERENCE ONLY, none of it compiled  *)
asm
  { ---- spill the four register arguments, keeping a copy ------- }
  MOV  SX1, BX            { SX1 := X1                                       }
  MOV  AX, BX             { AX now carries X1                               }
  MOV  SY1, CX            { SY1 := Y1                                       }
  MOV  BX, CX             { BX now carries Y1                               }
  MOV  SX2, DX            { SX2 := X2                                       }
  MOV  CX, DX             { CX now carries X2                               }
  MOV  SY2, SI            { SY2 := Y2                                       }
  MOV  DX, SI             { DX now carries Y2                               }
                          { from here AX=X1 BX=Y1 CX=X2 DX=Y2               }
  { ---- degenerate: all three X equal is a zero-width sliver ---- }
  CMP  AX, CX             { X1 against X2                                   }
  JNE  @@SortY            { differ -- not that degeneracy                   }
  CMP  CX, X3             { X2 against X3                                   }
  JNE  @@SortY            { differ                                          }
  JMP  @@Done             { X1 = X2 = X3, nothing to fill                   }

  { ---- sort the three vertices by Y, three compare-and-swap ---- }
@@SortY:                  { <- SortY                                      }
  CMP  BX, DX             { Y1 against Y2                                   }
  JG   @@Swap12           { out of order                                    }
  JMP  @@Test23           { in order                                        }
@@Swap12:                 { <- Swap12                                     }
  XCHG CX, AX             { swap X1 and X2                                  }
  XCHG BX, DX             { swap Y1 and Y2                                  }
@@Test23:                 { <- Test23                                     }
  CMP  DX, Y3             { Y2 against Y3                                   }
  JG   @@Swap23           { out of order                                    }
  JMP  @@Flat1            { in order -- the sort is finished                }
@@Swap23:                 { <- Swap23                                     }
  XCHG X3, CX             { swap X2 and X3, X3 being on the stack           }
  XCHG Y3, DX             { swap Y2 and Y3                                  }
  CMP  BX, DX             { Y1 against the new Y2                           }
  JG   @@Swap12b          { out of order again                              }
  JMP  @@Flat1            { sorted                                          }
@@Swap12b:                { <- Swap12b                                    }
  XCHG CX, AX             { swap X1 and X2                                  }
  XCHG BX, DX             { swap Y1 and Y2                                  }

  { ---- pick the variant: flat top, flat bottom, or general ----- }
@@Flat1:                  { <- Flat1                                      }
  CMP  BX, DX             { Y1 = Y2 ?                                       }
  JE   @@IsFlatTop        { yes -- the flat-top walk                        }
  JMP  @@Flat2            { no                                              }
@@IsFlatTop:              { <- IsFlatTop                                  }
  CMP  DX, Y3             { Y2 = Y3 as well ?                               }
  JNE  @@FlatTopOrder     { no -- a real flat top                           }
  JMP  @@Done             { all three Y equal, nothing to fill              }
@@FlatTopOrder:           { <- FlatTopOrder                               }
  CMP  AX, CX             { X1 against X2, the flat edge                    }
  JG   @@FlatTopSwap      { X1 > X2, swap so X1 is the left end             }
  JGE  @@DoneA            { equal -- zero-width, nothing to fill            }
  JMP  @@FlatTop          { already left-to-right                           }
@@DoneA:                  { the BRIDGE, WRITTEN OUT ON PURPOSE. @@Done is  }
  JMP  @@Done             { too far for a short jump from here, and left to }
                          { itself BASM bridges the OTHER arm: it inverts   }
                          { JGE to JL, sends that at @@FlatTop's bridge and }
                          { falls through to @@Done. Same branch, same      }
                          { behaviour, one byte different.                  }
                          { Naming the bridge keeps the original's shape --  }
                          { JGE to a bridge, then JMP @@FlatTop.            }
@@FlatTopSwap:            { <- FlatTopSwap                                }
  XCHG CX, AX             { swap X1 and X2                                  }
  JMP  @@FlatTop          { to FlatTop                                    }

@@Flat2:                  { <- Flat2                                      }
  CMP  DX, Y3             { Y2 = Y3 ?                                       }
  JE   @@IsFlatBot        { yes -- the flat-bottom walk                     }
  JMP  @@General          { no -- the general case                          }
@@IsFlatBot:              { <- IsFlatBot                                  }
  CMP  CX, X3             { X2 against X3, the flat edge                    }
  JG   @@FlatBotSwap      { X2 > X3, swap so X2 is the left end             }
  JGE  @@DoneB            { equal -- zero-width                             }
  JMP  @@FlatBot          { already left-to-right                           }
@@DoneB:                  { the same bridge again                           }
  JMP  @@Done
@@FlatBotSwap:            { <- FlatBotSwap                                }
  XCHG X3, CX             { swap X2 and X3                                  }
  JMP  @@FlatBot          { to FlatBot                                    }

  { ======== THE GENERAL CASE ==================================== }
@@General:                { <- General                                    }
  MOV  SX1, AX            { re-spill, the sort moved them                   }
  MOV  SY1, BX            { SY1 := BX                                     }
  MOV  SX2, CX            { SX2 := CX                                     }
  MOV  SY2, DX            { SY2 := DX                                     }
  MOV  DI, Y3             { the bottom vertex                               }
  CMP  DI, ClipYMin       { entirely above the clip box ?                   }
  JGE  @@GenInBox         { >= : to GenInBox                              }
  JMP  @@Done             { to Done                                       }
@@GenInBox:               { <- GenInBox                                   }
  MOV  DI, SY1            { the top vertex                                  }
  CMP  DI, ClipYMax       { entirely below the clip box ?                   }
  JLE  @@GenEdges         { <= : to GenEdges                              }
  JMP  @@Done             { to Done                                       }

  { ---- edge A, vertex 1 to vertex 2 --------------------------- }
@@GenEdges:               { <- GenEdges                                   }
  MOV  BX, DX             { Y2                                              }
  SUB  BX, SY1            { DenA := Y2 - Y1                                 }
  MOV  DenA, BX           { DenA := BX                                    }
  MOV  AX, SX2            { AX := SX2                                     }
  SUB  AX, SX1            { NumA := X2 - X1                                 }
  MOV  NumA, AX           { NumA := AX                                    }
  MOV  CX, AX             { keep the numerator's sign                       }
  CWD                     { sign-extend AX into DX:AX                       }
  IDIV BX                 { AX := quotient, DX := remainder, both truncated }
  CMP  CX, 0              { was the numerator negative ?                    }
  JGE  @@GenAOk           { no -- truncation was already floor              }
  DEC  AX                 { floor the quotient                              }
  ADD  DX, BX             { and bring the remainder back positive           }
@@GenAOk:                 { <- GenAOk                                     }
  MOV  StepA, AX          { StepA := AX                                   }
  MOV  RemA, DX           { RemA := DX                                    }

  { ---- edge B, vertex 1 to vertex 3, the long edge ------------ }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY1            { DenB := Y3 - Y1                                 }
  MOV  DenB, BX           { DenB := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX1            { NumB := X3 - X1                                 }
  MOV  NumB, AX           { NumB := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@GenBOk           { >= : to GenBOk                                }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@GenBOk:                 { <- GenBOk                                     }
  MOV  StepB, AX          { StepB := AX                                   }
  MOV  RemB, DX           { RemB := DX                                    }

  { ---- edge C, vertex 2 to vertex 3, skipped when flat -------- }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY2            { Y3 - Y2                                         }
  JLE  @@GenCross         { not positive -- edge C is never walked          }
  MOV  DenC, BX           { DenC := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX2            { NumC := X3 - X2                                 }
  MOV  NumC, AX           { NumC := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@GenCOk           { >= : to GenCOk                                }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@GenCOk:                 { <- GenCOk                                     }
  MOV  StepC, AX          { StepC := AX                                   }
  MOV  RemC, DX           { RemC := DX                                    }

  { ---- the winding test, 32-bit, decides which side is which -- }
@@GenCross:               { <- GenCross                                   }
  MOV  AX, NumA           { X2 - X1                                         }
  IMUL DenB               { * (Y3 - Y1), signed, into DX:AX                 }
  MOV  BX, AX             { park the low word                               }
  MOV  CX, DX             { park the high word                              }
  MOV  AX, NumB           { X3 - X1                                         }
  IMUL DenA               { * (Y2 - Y1), into DX:AX                         }
  CMP  CX, DX             { high words, SIGNED                              }
  JG   @@WalkAC           { first product is the greater                    }
  JGE  @@CrossLow         { equal -- the low words decide                   }
  JMP  @@WalkBB           { to WalkBB                                     }
@@CrossLow:               { <- CrossLow                                   }
  CMP  BX, AX             { low words, UNSIGNED, as a 32-bit compare needs  }
  JA   @@WalkAC           { above, unsigned : to WalkAC                   }
  JAE  @@GenDegenerate    { both products equal -- the three are collinear  }
  JMP  @@WalkBB           { to WalkBB                                     }
@@GenDegenerate:          { <- GenDegenerate                              }
  JMP  @@Done             { to Done                                       }

  { ======== general walk, edges A then C on the RIGHT ==========
    DI is the left X and steps edge B; SI is the right X and steps edge A,
    then edge C once Y passes Y2. AX is DI's error, BX is SI's error, CX is
    the scanline, DX is the byte index into Span. -------------------------- }
@@WalkAC:                 { <- WalkAC                                     }
  MOV  AX, 0              { DI's error accumulator                          }
  MOV  BX, 0              { SI's error accumulator                          }
  MOV  CX, SY1            { start at the top vertex                         }
  MOV  DI, SX1            { both edges start at X1                          }
  MOV  SI, DI             { SI := DI                                      }
  XOR  DX, DX             { Span is written from the beginning              }
  CMP  CX, ClipYMin       { does the walk start above the clip box ?        }
  JGE  @@AC1              { >= : to AC1                                   }
  MOV  DX, ClipYMin       { it does -- the first STORED scanline is the top }
  MOV  SY1, DX            { of the box, and SY1 is where the fill will stop }
  MOV  DX, SY1            { DX := SY1                                     }
  CMP  DX, Y3             { is the whole triangle above the box ?           }
  JNE  @@AC1a             { <> : to AC1a                                  }
  JMP  @@Done             { to Done                                       }
@@AC1a:                   { <- AC1a                                       }
  XOR  DX, DX             { DX := 0                                       }
@@AC1:                    { <- AC1                                        }
  CMP  CX, ClipYMin       { above the box -- step the edges but store nothing }
  JL   @@AC1Step          { < : to AC1Step                                }
  MOV  ES, BX             { park SI's error so BX can index Span            }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI      { the left end                           }
  MOV  BX, ES             { unpark                                          }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI      { the right end                          }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@AC1Step:                { <- AC1Step                                    }
  ADD  AX, RemB           { DI's error += edge B's remainder                }
  JLE  @@AC1StepDI        { <= : to AC1StepDI                             }
  SUB  AX, DenB           { crossed -- pull it back                         }
  INC  DI                 { and take the extra pixel                        }
@@AC1StepDI:              { <- AC1StepDI                                  }
  ADD  DI, StepB          { DI := DI + StepB                              }
  ADD  BX, RemA           { SI's error += edge A's remainder                }
  JLE  @@AC1StepSI        { <= : to AC1StepSI                             }
  SUB  BX, DenA           { BX := BX - DenA                               }
  INC  SI                 { SI := SI + 1                                  }
@@AC1StepSI:              { <- AC1StepSI                                  }
  ADD  SI, StepA          { SI := SI + StepA                              }
  INC  CX                 { next scanline                                   }
  CMP  CX, ClipYMax       { off the bottom of the box ?                     }
  JL   @@AC1More          { < : to AC1More                                }
  MOV  Y3, CX             { yes -- the fill starts here instead of at Y3    }
  JMP  @@Fill             { to Fill                                       }
@@AC1More:                { <- AC1More                                    }
  CMP  CX, SY2            { still in the first half ?                       }
  JL   @@AC1              { < : to AC1                                    }
  { ---- second half: SI switches from edge A to edge C --------- }
@@AC2:                    { <- AC2                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@AC2Step          { < : to AC2Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@AC2Step:                { <- AC2Step                                    }
  ADD  AX, RemB           { AX := AX + RemB                               }
  JLE  @@AC2StepDI        { <= : to AC2StepDI                             }
  SUB  AX, DenB           { AX := AX - DenB                               }
  INC  DI                 { DI := DI + 1                                  }
@@AC2StepDI:              { <- AC2StepDI                                  }
  ADD  DI, StepB          { DI := DI + StepB                              }
  ADD  BX, RemC           { edge C now                                      }
  JLE  @@AC2StepSI        { <= : to AC2StepSI                             }
  SUB  BX, DenC           { BX := BX - DenC                               }
  INC  SI                 { SI := SI + 1                                  }
@@AC2StepSI:              { <- AC2StepSI                                  }
  ADD  SI, StepC          { SI := SI + StepC                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@AC2More          { < : to AC2More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
@@AC2More:                { <- AC2More                                    }
  CMP  CX, Y3             { compare CX with Y3                            }
  JL   @@AC2              { < : to AC2                                    }
  JMP  @@Fill             { to Fill                                       }

  { ======== general walk, edges A then C on the LEFT ===========
    The mirror of the above: DI steps edge A then edge C, SI steps edge B
    the whole way down. ---------------------------------------------------- }
@@WalkBB:                 { <- WalkBB                                     }
  MOV  AX, 0              { AX := 0                                       }
  MOV  BX, 0              { BX := 0                                       }
  MOV  CX, SY1            { CX := SY1                                     }
  MOV  DI, SX1            { DI := SX1                                     }
  MOV  SI, SX1            { SI := SX1                                     }
  XOR  DX, DX             { DX := 0                                       }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JGE  @@BB1              { >= : to BB1                                   }
  MOV  DX, ClipYMin       { DX := ClipYMin                                }
  MOV  SY1, DX            { SY1 := DX                                     }
  MOV  DX, SY1            { DX := SY1                                     }
  CMP  DX, Y3             { compare DX with Y3                            }
  JNE  @@BB1a             { <> : to BB1a                                  }
  JMP  @@Done             { to Done                                       }
@@BB1a:                   { <- BB1a                                       }
  XOR  DX, DX             { DX := 0                                       }
@@BB1:                    { <- BB1                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@BB1Step          { < : to BB1Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@BB1Step:                { <- BB1Step                                    }
  ADD  AX, RemA           { DI takes edge A here                            }
  JLE  @@BB1StepDI        { <= : to BB1StepDI                             }
  SUB  AX, DenA           { AX := AX - DenA                               }
  INC  DI                 { DI := DI + 1                                  }
@@BB1StepDI:              { <- BB1StepDI                                  }
  ADD  DI, StepA          { DI := DI + StepA                              }
  ADD  BX, RemB           { SI takes the long edge B                        }
  JLE  @@BB1StepSI        { <= : to BB1StepSI                             }
  SUB  BX, DenB           { BX := BX - DenB                               }
  INC  SI                 { SI := SI + 1                                  }
@@BB1StepSI:              { <- BB1StepSI                                  }
  ADD  SI, StepB          { SI := SI + StepB                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@BB1More          { < : to BB1More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
  JMP  @@Fill             { to Fill                                       }
@@BB1More:                { <- BB1More                                    }
  CMP  CX, SY2            { compare CX with SY2                           }
  JL   @@BB1              { < : to BB1                                    }
  { ---- second half: DI switches from edge A to edge C --------- }
@@BB2:                    { <- BB2                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@BB2Step          { < : to BB2Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@BB2Step:                { <- BB2Step                                    }
  ADD  AX, RemC           { AX := AX + RemC                               }
  JLE  @@BB2StepDI        { <= : to BB2StepDI                             }
  SUB  AX, DenC           { AX := AX - DenC                               }
  INC  DI                 { DI := DI + 1                                  }
@@BB2StepDI:              { <- BB2StepDI                                  }
  ADD  DI, StepC          { DI := DI + StepC                              }
  ADD  BX, RemB           { BX := BX + RemB                               }
  JLE  @@BB2StepSI        { <= : to BB2StepSI                             }
  SUB  BX, DenB           { BX := BX - DenB                               }
  INC  SI                 { SI := SI + 1                                  }
@@BB2StepSI:              { <- BB2StepSI                                  }
  ADD  SI, StepB          { SI := SI + StepB                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@BB2More          { < : to BB2More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
  JMP  @@Fill             { to Fill                                       }
@@BB2More:                { <- BB2More                                    }
  CMP  CX, Y3             { compare CX with Y3                            }
  JL   @@BB2              { < : to BB2                                    }
  JMP  @@Fill             { to Fill                                       }

  { ======== flat top: Y1 = Y2, so two edges leave the top ====== }
@@FlatTop:                { <- FlatTop                                    }
  MOV  SX1, AX            { SX1 := AX                                     }
  MOV  SY1, BX            { SY1 := BX                                     }
  MOV  SX2, CX            { SX2 := CX                                     }
  MOV  SY2, DX            { SY2 := DX                                     }
  MOV  DI, Y3             { DI := Y3                                      }
  CMP  DI, ClipYMin       { compare DI with ClipYMin                      }
  JGE  @@FTInBox          { >= : to FTInBox                               }
  JMP  @@Done             { to Done                                       }
@@FTInBox:                { <- FTInBox                                    }
  MOV  DI, SY1            { DI := SY1                                     }
  CMP  DI, ClipYMax       { compare DI with ClipYMax                      }
  JLE  @@FTEdges          { <= : to FTEdges                               }
  JMP  @@Done             { to Done                                       }
@@FTEdges:                { <- FTEdges                                    }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY1            { DenA := Y3 - Y1                                 }
  MOV  DenA, BX           { DenA := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX1            { NumA := X3 - X1, the left edge                   }
  MOV  NumA, AX           { NumA := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@FTAOk            { >= : to FTAOk                                 }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@FTAOk:                  { <- FTAOk                                      }
  MOV  StepA, AX          { StepA := AX                                   }
  MOV  RemA, DX           { RemA := DX                                    }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY2            { DenB := Y3 - Y2                                 }
  MOV  DenB, BX           { DenB := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX2            { NumB := X3 - X2, the right edge                 }
  MOV  NumB, AX           { NumB := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@FTBOk            { >= : to FTBOk                                 }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@FTBOk:                  { <- FTBOk                                      }
  MOV  StepB, AX          { StepB := AX                                   }
  MOV  RemB, DX           { RemB := DX                                    }
  MOV  AX, 0              { AX := 0                                       }
  MOV  BX, 0              { BX := 0                                       }
  MOV  CX, SY1            { CX := SY1                                     }
  MOV  DI, SX1            { the left end starts at X1                       }
  MOV  SI, SX2            { the right end at X2 -- the flat edge            }
  XOR  DX, DX             { DX := 0                                       }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JGE  @@FT1              { >= : to FT1                                   }
  MOV  DX, ClipYMin       { DX := ClipYMin                                }
  MOV  SY1, DX            { SY1 := DX                                     }
  MOV  DX, SY1            { DX := SY1                                     }
  CMP  DX, Y3             { compare DX with Y3                            }
  JNE  @@FT1a             { <> : to FT1a                                  }
  JMP  @@Done             { to Done                                       }
@@FT1a:                   { <- FT1a                                       }
  XOR  DX, DX             { DX := 0                                       }
@@FT1:                    { <- FT1                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@FT1Step          { < : to FT1Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@FT1Step:                { <- FT1Step                                    }
  ADD  AX, RemA           { AX := AX + RemA                               }
  JLE  @@FT1StepDI        { <= : to FT1StepDI                             }
  SUB  AX, DenA           { AX := AX - DenA                               }
  INC  DI                 { DI := DI + 1                                  }
@@FT1StepDI:              { <- FT1StepDI                                  }
  ADD  DI, StepA          { DI := DI + StepA                              }
  ADD  BX, RemB           { BX := BX + RemB                               }
  JLE  @@FT1StepSI        { <= : to FT1StepSI                             }
  SUB  BX, DenB           { BX := BX - DenB                               }
  INC  SI                 { SI := SI + 1                                  }
@@FT1StepSI:              { <- FT1StepSI                                  }
  ADD  SI, StepB          { SI := SI + StepB                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@FT1More          { < : to FT1More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
  JMP  @@Fill             { to Fill                                       }
@@FT1More:                { <- FT1More                                    }
  CMP  CX, Y3             { compare CX with Y3                            }
  JL   @@FT1              { < : to FT1                                    }
  JMP  @@Fill             { to Fill                                       }

  { ======== flat bottom: Y2 = Y3, two edges meet at the top ==== }
@@FlatBot:                { <- FlatBot                                    }
  MOV  SX1, AX            { SX1 := AX                                     }
  MOV  SY1, BX            { SY1 := BX                                     }
  MOV  SX2, CX            { SX2 := CX                                     }
  MOV  SY2, DX            { SY2 := DX                                     }
  MOV  DI, Y3             { DI := Y3                                      }
  CMP  DI, ClipYMin       { compare DI with ClipYMin                      }
  JGE  @@FBInBox          { >= : to FBInBox                               }
  JMP  @@Done             { to Done                                       }
@@FBInBox:                { <- FBInBox                                    }
  MOV  DI, SY1            { DI := SY1                                     }
  CMP  DI, ClipYMax       { compare DI with ClipYMax                      }
  JLE  @@FBEdges          { <= : to FBEdges                               }
  JMP  @@Done             { to Done                                       }
@@FBEdges:                { <- FBEdges                                    }
  MOV  BX, SY2            { BX := SY2                                     }
  SUB  BX, SY1            { DenA := Y2 - Y1                                 }
  MOV  DenA, BX           { DenA := BX                                    }
  MOV  AX, SX2            { AX := SX2                                     }
  SUB  AX, SX1            { NumA := X2 - X1, the left edge                  }
  MOV  NumA, AX           { NumA := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@FBAOk            { >= : to FBAOk                                 }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@FBAOk:                  { <- FBAOk                                      }
  MOV  StepA, AX          { StepA := AX                                   }
  MOV  RemA, DX           { RemA := DX                                    }
  MOV  BX, Y3             { BX := Y3                                      }
  SUB  BX, SY1            { DenB := Y3 - Y1                                 }
  MOV  DenB, BX           { DenB := BX                                    }
  MOV  AX, X3             { AX := X3                                      }
  SUB  AX, SX1            { NumB := X3 - X1, the right edge                 }
  MOV  NumB, AX           { NumB := AX                                    }
  MOV  CX, AX             { CX := AX                                      }
  CWD                     { sign-extend AX into DX:AX                     }
  IDIV BX                 { AX := DX:AX div BX, DX := the remainder       }
  CMP  CX, 0              { compare CX with 0                             }
  JGE  @@FBBOk            { >= : to FBBOk                                 }
  DEC  AX                 { AX := AX - 1                                  }
  ADD  DX, BX             { DX := DX + BX                                 }
@@FBBOk:                  { <- FBBOk                                      }
  MOV  StepB, AX          { StepB := AX                                   }
  MOV  RemB, DX           { RemB := DX                                    }
  MOV  AX, 0              { AX := 0                                       }
  MOV  BX, 0              { BX := 0                                       }
  MOV  CX, SY1            { CX := SY1                                     }
  MOV  DI, SX1            { both edges leave the same apex                  }
  MOV  SI, SX1            { SI := SX1                                     }
  XOR  DX, DX             { DX := 0                                       }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JGE  @@FB1              { >= : to FB1                                   }
  MOV  DX, ClipYMin       { DX := ClipYMin                                }
  MOV  SY1, DX            { SY1 := DX                                     }
  MOV  DX, SY1            { DX := SY1                                     }
  CMP  DX, Y3             { compare DX with Y3                            }
  JNE  @@FB1a             { <> : to FB1a                                  }
  JMP  @@Done             { to Done                                       }
@@FB1a:                   { <- FB1a                                       }
  XOR  DX, DX             { DX := 0                                       }
@@FB1:                    { <- FB1                                        }
  CMP  CX, ClipYMin       { compare CX with ClipYMin                      }
  JL   @@FB1Step          { < : to FB1Step                                }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], DI { [BX + OFFSET Span] := DI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
  MOV  ES, BX             { ES := BX                                      }
  MOV  BX, DX             { BX := DX                                      }
  MOV  [BX + OFFSET Span], SI { [BX + OFFSET Span] := SI                      }
  MOV  BX, ES             { BX := ES                                      }
  ADD  DX, 2              { DX := DX + 2                                  }
@@FB1Step:                { <- FB1Step                                    }
  ADD  AX, RemA           { AX := AX + RemA                               }
  JLE  @@FB1StepDI        { <= : to FB1StepDI                             }
  SUB  AX, DenA           { AX := AX - DenA                               }
  INC  DI                 { DI := DI + 1                                  }
@@FB1StepDI:              { <- FB1StepDI                                  }
  ADD  DI, StepA          { DI := DI + StepA                              }
  ADD  BX, RemB           { BX := BX + RemB                               }
  JLE  @@FB1StepSI        { <= : to FB1StepSI                             }
  SUB  BX, DenB           { BX := BX - DenB                               }
  INC  SI                 { SI := SI + 1                                  }
@@FB1StepSI:              { <- FB1StepSI                                  }
  ADD  SI, StepB          { SI := SI + StepB                              }
  INC  CX                 { CX := CX + 1                                  }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JL   @@FB1More          { < : to FB1More                                }
  MOV  Y3, CX             { Y3 := CX                                      }
  JMP  @@Fill             { to Fill                                       }
@@FB1More:                { <- FB1More                                    }
  CMP  CX, Y3             { compare CX with Y3                            }
  JL   @@FB1              { < : to FB1                                    }

  { ======== fill the collected spans, LAST scanline first ======
    DX still holds one past the last word written, so the walk backwards is
    free. Direction matters to the bytes even though it cannot matter to a
    solid fill, so it is kept. -------------------------------------------- }
@@Fill:                   { <- Fill                                       }
  CLD                     { STOSB/STOSW forwards within a span              }
  MOV  CX, Y3             { the last scanline the walk actually stored      }
  MOV  AX, $A000          { AX := $A000                                   }
  MOV  ES, AX             { ES:DI addresses video memory from here          }
  SUB  DX, 2              { step back onto the last word                    }
  MOV  SpanIdx, DX        { SpanIdx := DX                                 }
@@FillRow:                { <- FillRow                                    }
  MOV  FillY, CX          { FillY := CX                                   }
  MOV  BX, SpanIdx        { BX := SpanIdx                                 }
  MOV  DX, [BX + OFFSET Span]      { the right end                          }
  CMP  DX, ClipXMax       { compare DX with ClipXMax                      }
  JLE  @@FillRIn          { <= : to FillRIn                               }
  MOV  DX, ClipXMax       { clip right                                      }
@@FillRIn:                { <- FillRIn                                    }
  MOV  FillR, DX          { FillR := DX                                   }
  SUB  SpanIdx, 2         { SpanIdx := SpanIdx - 2                        }
  MOV  BX, SpanIdx        { BX := SpanIdx                                 }
  MOV  DX, [BX + OFFSET Span]      { the left end                           }
  CMP  DX, ClipXMin       { compare DX with ClipXMin                      }
  JGE  @@FillLIn          { >= : to FillLIn                               }
  MOV  DX, ClipXMin       { clip left                                       }
@@FillLIn:                { <- FillLIn                                    }
  MOV  FillL, DX          { FillL := DX                                   }
  SUB  SpanIdx, 2         { SpanIdx := SpanIdx - 2                        }
  CMP  CX, ClipYMin       { the scanline itself may be outside the box      }
  JL   @@FillNext         { < : to FillNext                               }
  CMP  CX, ClipYMax       { compare CX with ClipYMax                      }
  JG   @@FillNext         { > : to FillNext                               }
  PUSH BP                 { BP becomes a scratch register below             }
  MOV  BX, CX             { BX := CX                                      }
  ADD  BX, BX             { Y * 2, a word index                             }
  MOV  DI, [BX + OFFSET RowOfs]    { DI := RowOfs[Y], the 80-byte row table }
  MOV  BX, FillL          { BX := FillL                                   }
  SHR  BX, 2              { X div 4 -- four pixels to the byte in Mode X    }
  ADD  DI, BX             { DI := DI + BX                                 }
  ADD  DI, WritePage      { and the page being drawn on                     }
  MOV  DX, $3C4           { Sequencer address register                      }
  MOV  AL, 2              { register 2 -- Map Mask                          }
  OUT  DX, AL             { write AL to port DX                           }
  INC  DX                 { DX now addresses the data register              }
  MOV  SI, FillL          { SI := FillL                                   }
  AND  SI, 3              { the left end's plane                            }
  MOV  BH, [SI + OFFSET LeftMask4]     { both masks packed into one register }
  MOV  SI, FillR          { SI := FillR                                   }
  AND  SI, 3              { the right end's plane                           }
  MOV  BL, [SI + OFFSET RightMask4] { BL := [SI + OFFSET RightMask4]                }
  MOV  CX, FillR          { CX := FillR                                   }
  MOV  SI, FillL          { SI := FillL                                   }
  CMP  CX, SI             { empty or inverted span ?                        }
  JLE  @@FillPop          { <= : to FillPop                               }
  DEC  CX                 { the last pixel is exclusive                     }
  AND  SI, $FFFC          { back to the byte the left end sits in           }
  SUB  CX, SI             { CX := CX - SI                                 }
  SHR  CX, 1              { CX := CX shr 1                                }
  SHR  CX, 1              { CX := how many whole bytes past the first       }
  JNE  @@FillWide         { <> : to FillWide                              }
  AND  BH, BL             { one byte only -- both masks apply to it         }
@@FillWide:               { <- FillWide                                   }
  MOV  SI, FillY          { DEAD in the original: SI is never read again    }
  MOV  AH, Colour         { AH carries the colour for every store below     }
  MOV  BP, $50            { DEAD in the original: 80, the row stride, minus }
  SUB  BP, CX             { the byte count, less one -- and never read      }
  DEC  BP                 { before POP BP puts the frame pointer back       }
  MOV  AL, BH             { the left mask                                   }
  OUT  DX, AL             { write AL to port DX                           }
  MOV  AL, AH             { AL := AH                                      }
  STOSB                   { the first, partly-masked byte                   }
  DEC  CX                 { CX := CX - 1                                  }
  JS   @@FillPop          { that was the whole span                         }
  JE   @@FillRight        { nothing in the middle                          }
  MOV  AL, $0F            { all four planes for the middle                  }
  OUT  DX, AL             { write AL to port DX                           }
  MOV  AL, AH             { AL := AH                                      }
  SHR  CX, 1              { bytes to words                                  }
  REP  STOSW              { fill CX words with AX                         }
  ADC  CX, CX             { the carry out of SHR is the odd byte            }
  REP  STOSB              { fill CX bytes with AL                         }
@@FillRight:              { <- FillRight                                  }
  MOV  AL, BL             { the right mask                                  }
  OUT  DX, AL             { write AL to port DX                           }
  MOV  AL, AH             { AL := AH                                      }
  STOSB                   { the last, partly-masked byte                    }
@@FillPop:                { <- FillPop                                    }
  POP  BP                 { the frame pointer is a frame pointer again      }
@@FillNext:               { <- FillNext                                   }
  MOV  CX, FillY          { CX := FillY                                   }
  DEC  CX                 { upwards, one scanline at a time                 }
  CMP  CX, SY1            { back at the top vertex ?                        }
  JLE  @@Done             { <= : to Done                                  }
  JMP  @@FillRow          { to FillRow                                    }
@@Done:                   { <- Done                                       }
end;


{ --------------------------------------------------------------------------
Poly_FillFan(Pts, Count, Colour, Page), ALSO assembler

  It is the only caller of Tri_Fill and it cooperates with that private
  register interface -- BX, CX, DX and SI loaded, three words pushed -- which
  no Pascal caller could do, so it is assembler too. It takes its own
  arguments the ordinary Pascal way.

  Count - 3 into the counter and `DEC` / `JNS` runs it Count-2 times, one
  triangle per step, all of them sharing Pts[1]. ES:DI is saved into locals
  across each call and restored after, because Tri_Fill uses both.
  -------------------------------------------------------------------------- }
type
  TPointList = array[1..FaceVerts] of record X, Y : Integer end;

procedure FillFan(var Pts : TPointList; Count : Integer; Colour : Word;
                  Page : Word); assembler;
var
  FanX1, FanY1 : Integer;     { the shared first vertex }
  FanLeft      : Integer;     { triangles still to do             }
  FanSeg, FanOfs : Word;      { ES:DI across the call   }
(* EQUIVALENT PASCAL -- REFERENCE ONLY, and it is NOT what is compiled. The
  assembler below is the transcription. This cannot be a working procedure
  either, because the call it makes passes four arguments in registers.

    procedure FillFan(var Pts : TPointList; Count : Integer;
                      Colour : Byte; Page : Word);
    var I : Integer;
    begin
      if Count < 3 then Exit;           { a fan needs three points          }
      for I := 2 to Count - 1 do        { Count-2 triangles, DEC/JNS below  }
        TriFill(Pts[1].X, Pts[1].Y,     { the shared first vertex           }
                Pts[I].X, Pts[I].Y,
                Pts[I + 1].X, Pts[I + 1].Y, Colour);
      { Page is declared and never read -- TriFill takes the page from the
        WritePage global. It is what makes the epilogue RET $0A and not 8. }
    end;
    EQUIVALENT PASCAL ends here -- REFERENCE ONLY, none of it compiled  *)
asm
  MOV  CX, Count          { CX := Count                                   }
  CMP  CX, 3              { a fan needs three points                        }
  JL   @@FanDone          { < : to FanDone                                }
  SUB  CX, 3              { CX := CX - 3                                  }
  MOV  FanLeft, CX        { Count-3, so DEC/JNS turns Count-2 times         }
  LES  DI, Pts            { ES:DI := the point list                         }
  MOV  AX, ES:[DI]        { AX := ES:[DI]                                 }
  MOV  FanX1, AX          { the vertex every triangle shares                }
  MOV  AX, ES:[DI + 2]    { AX := ES:[DI + 2]                             }
  MOV  FanY1, AX          { FanY1 := AX                                   }
@@FanTri:                 { <- FanTri                                     }
  ADD  DI, 4              { on to the next pair                             }
  MOV  BX, FanX1          { Tri_Fill's X1, in a register                    }
  MOV  CX, FanY1          { Y1                                              }
  MOV  DX, ES:[DI]        { X2                                              }
  MOV  SI, ES:[DI + 2]    { Y2                                              }
  MOV  AX, ES:[DI + 4]    { AX := ES:[DI + 4]                             }
  PUSH AX                 { X3, on the stack                                }
  MOV  AX, ES:[DI + 6]    { AX := ES:[DI + 6]                             }
  PUSH AX                 { Y3                                             }
  MOV  AX, WORD PTR Colour  { read as a WORD, not a Byte                     }
  PUSH AX                 { parameter still occupies a whole stack word     }
  MOV  FanSeg, ES         { Tri_Fill uses ES:DI, so keep them               }
  MOV  FanOfs, DI         { FanOfs := DI                                  }
  CALL TriFill            { call TriFill                                  }
  MOV  ES, FanSeg         { ES := FanSeg                                  }
  MOV  DI, FanOfs         { DI := FanOfs                                  }
  DEC  FanLeft            { FanLeft := FanLeft - 1                        }
  JNS  @@FanTri           { not negative : to FanTri                      }
@@FanDone:                { <- FanDone                                    }
end;

{ --------------------------------------------------------------------------
RowOfs[I] := I * 80, for I = 0..$EF.
  -------------------------------------------------------------------------- }
procedure BuildRowTable80;
var
  I : Integer;
begin
  for I := 0 to Rows - 1 do
    RowOfs[I] := I * PlaneWidth;
end;


{ takes the object BY VALUE }
procedure RenderC(O : TObj);
var
  Pts   : TPointList;                    { 32 bytes }
  { A LOCAL COPY OF THE FACE ARRAY, taken before anything else runs:
 pushes both addresses and $5D7 = 1,495 and calls the runtime
    Move. Count, Idx and Colour are all read from this copy afterwards, while
    the screen coordinates come from the value parameter's copy. }
  Faces : TFaceArray;                    { 1,495 bytes }
  F     : Integer;                       { 14 references }
  K     : Integer;
  Flag2 : Word;   { never read -- the frame does not close
                    without it, see below }
  Flag  : Byte;   { written 0 per face and never read }
begin
  Faces := O.Face;
  for F := 1 to O.FaceCount do
  begin
    Flag := 0;
    for K := 1 to Faces[F].Count do
    begin
      Pts[K].X := O.Scr[Faces[F].Idx[K]].X;
      Pts[K].Y := O.Scr[Faces[F].Idx[K]].Y;
    end;
    FillFan(Pts, Faces[F].Count, Faces[F].Colour, WritePage);
  end;
  { FlipAndSwap, inline }
  FlipPage(WritePage);
  PageIndex := (PageIndex + 1) mod 2;
end;


{ --------------------------------------------------------------------------
the three renderers }
{ takes the object BY VALUE }
procedure RenderA(O : TObj);
var
  Pts   : TPointList;                    { 32 bytes }
  { A LOCAL COPY OF THE FACE ARRAY, taken before anything else runs:
 pushes both addresses and $5D7 = 1,495 and calls the runtime
    Move. Count, Idx and Colour are all read from this copy afterwards, while
    the screen coordinates come from the value parameter's copy. }
  Faces : TFaceArray;                    { 1,495 bytes }
  F     : Integer;                       { 14 references }
  K     : Integer;
  Flag2 : Word;   { never read -- the frame does not close
                    without it, see below }
  Flag  : Byte;   { written 0 per face and never read }
begin
  Faces := O.Face;
  for F := 1 to StarCount do
    Plot(Star[F].X, Star[F].Y, Star[F].Z);
  for F := 1 to O.FaceCount do
  begin
    Flag := 0;
    for K := 1 to Faces[F].Count do
    begin
      Pts[K].X := O.Scr[Faces[F].Idx[K]].X;
      Pts[K].Y := O.Scr[Faces[F].Idx[K]].Y;
    end;
    FillFan(Pts, Faces[F].Count, Faces[F].Colour, WritePage);
  end;
  { FlipAndSwap, inline }
  FlipPage(WritePage);
  PageIndex := (PageIndex + 1) mod 2;
end;


{ takes the object BY VALUE }
procedure RenderB(O : TObj);
var
  Pts   : TPointList;                    { 32 bytes }
  { A LOCAL COPY OF THE FACE ARRAY, taken before anything else runs:
 pushes both addresses and $5D7 = 1,495 and calls the runtime
    Move. Count, Idx and Colour are all read from this copy afterwards, while
    the screen coordinates come from the value parameter's copy. }
  Faces : TFaceArray;                    { 1,495 bytes }
  F     : Integer;                       { 14 references }
  K     : Integer;
  Flag2 : Word;   { never read -- the frame does not close
                    without it, see below }
  Flag  : Byte;   { written 0 per face and never read }
begin
  Faces := O.Face;
  for F := 1 to StarCount do
    Plot(Star[F].X, Star[F].Y, Star[F].Z);
  DrawRewind;
  for F := 1 to O.FaceCount do
  begin
    Flag := 0;
    for K := 1 to Faces[F].Count do
    begin
      Pts[K].X := O.Scr[Faces[F].Idx[K]].X;
      Pts[K].Y := O.Scr[Faces[F].Idx[K]].Y;
    end;
    FillFan(Pts, Faces[F].Count, Faces[F].Colour, WritePage);
  end;
  { FlipAndSwap, inline }
  FlipPage(WritePage);
  PageIndex := (PageIndex + 1) mod 2;
end;


{ --------------------------------------------------------------------------
Obj_SortFaces(var Obj)

  Copies the object, keys every face with the average of its vertices' D, then
  selection-sorts back into the ORIGINAL, farthest first:

      repeat
        find the face with the SMALLEST key   (best starts at 0)
        if none is below zero then stop
        copy it into the next slot and zero its key
      until done

  Two consequences worth stating, because both are visible and both are the
  original's behaviour:

    * anything with D >= 0 is culled -- the objects sit at negative Z, so this
      is a near-plane cull;
    * the number of faces that survived is NEVER written back to Obj+2, so the
      renderers still walk FaceCount faces and the tail of the array holds
      whatever the previous frame left there.
  -------------------------------------------------------------------------- }
procedure ObjSortFaces(var O : TObj);
var
  { ENTER $1136 is 4,406 bytes and the seven scalars are the DEEPEST slots,
    so 4,392 bytes of aggregate are declared before them. 4,392 is
    2,897 + 1,495 exactly -- one whole TObj and one array[1..MaxFaces] of
    TFace -- and only the first of those is ever addressed.

    That is worth more than the byte count. The reconstruction worked through
    the far `var` pointer for every read, which costs an ES: override and a
    segment load per access; the original pays one bulk copy and then uses
    near addressing throughout. It is a candidate mechanism for the pacing
    investigation -- ours slower wherever 3-D code runs -- and it is the
    opposite of what a bulk copy looks like from the outside. }
  Tmp     : TObj;
  Unused  : array[1..MaxFaces] of TFace;
  F       : Integer;                          { 17 references }
  K       : Integer;
  BestKey : Integer;                          { INTEGER, not LongInt }
  Best    : Integer;
  Slot    : Integer;
begin
  Tmp := O;                                   { Move of $B51 bytes }
  for F := 1 to Tmp.FaceCount do
  begin
    { THE ACCUMULATOR IS THE DEPTH FIELD ITSELF and it is SIXTEEN BIT. The
      reconstruction summed into a LongInt and divided that; the original adds
      each vertex's D straight into Tmp.Face[F].Depth with a word ADD at
 and stores it back each time. }
    Tmp.Face[F].Depth := 0;
    for K := 1 to Tmp.Face[F].Count do
      Tmp.Face[F].Depth := Tmp.Face[F].Depth
                         + Tmp.Scr[Tmp.Face[F].Idx[K]].D;
    Tmp.Face[F].Depth := Tmp.Face[F].Depth div Tmp.Face[F].Count;
  end;

  Slot := 1;
  repeat
    BestKey := 0;
    Best    := 0;
    for F := 1 to Tmp.FaceCount do            { re-read per pass }
      if Tmp.Face[F].Depth < BestKey then     { smallest key wins }
      begin
        BestKey := Tmp.Face[F].Depth;
        Best    := F;
      end;
    if Best > 0 then
    begin
      O.Face[Slot] := Tmp.Face[Best];         { Move of 23 bytes }
      Tmp.Face[Best].Depth := 0;
      Inc(Slot);
    end;
  until Best = 0;
end;


{ --------------------------------------------------------------------------
Present

  The typewriter, driven entirely by the frame counter:

      100 < Frame < 150     message 1, character Frame-100
      250 < Frame < 300     message 2, character Frame-250 }
{ Present, and Emit is INLINED into it }
procedure Present;
begin
  if Frame > 100 then
  begin
    if (Frame > 100) and (Frame < 150) then
    begin
      WritePage := PageBase[0];
      DrawText((Frame - 100) * 6 + 15, TextY1, Msg1[Frame - 100]);
      WritePage := PageBase[1];
      DrawText((Frame - 100) * 6 + 15, TextY1, Msg1[Frame - 100]);
    end;
    if (Frame > 250) and (Frame < 300) then
    begin
      WritePage := PageBase[0];
      DrawText((Frame - 250) * 6 + 15, TextY2, Msg2[Frame - 250]);
      WritePage := PageBase[1];
      DrawText((Frame - 250) * 6 + 15, TextY2, Msg2[Frame - 250]);
    end;
  end;
end;


{ --------------------------------------------------------------------------
DrawBanner

  Colours 100..200 are loaded from the palette, then the
  12,800-byte block read into the heap is plotted into rows 200..239 -- of
  BOTH pages, a pixel at a time. 12,800 is 320 x 40, exactly that strip.
  -------------------------------------------------------------------------- }
procedure DrawBanner;
var
  X, Y : Integer;
begin
  for X := 100 to 200 do
    SetRGB(X, Pal[X, 0], Pal[X, 1], Pal[X, 2]);

  for X := 0 to ScrWidth - 1 do
    for Y := BannerTop to Rows - 1 do
    begin
      WritePage := PageBase[0];
      Plot(X, Y, Banner^[Y - BannerTop, X]);
      WritePage := PageBase[1];
      Plot(X, Y, Banner^[Y - BannerTop, X]);
    end;
end;


{ ===========================================================================
Scene2_Choreography

  Fourteen phases. The body of a phase frame is always the same shape:

      ObjTranslate(O, dx, dy, dz)
      ObjTransform(O, PC, PA, PB)
      WritePage := PageBase[PageIndex]
      FillRect(0, 0, 320, H, WritePage, 0)          H = 200 or 240
      ObjSortFaces(O)
      RenderA / RenderB / RenderC
      Frame := Frame + 1                            phases 1..11 only
      Present                                       phases 1..11 only }
procedure Choreography;
var
  PC, PB, PA : Integer;
  Dead1, Dead2, Dead3 : Integer;
  I   : Integer;                 { 62 references }
  Buf : array[0..767] of Byte;
begin
  { a blue ramp into colours 70..90 }
  for I := $46 to $5A do
    SetRGB(I, 0, 0, (I - $46) * 3);

  for I := 1 to StarCount do
  begin
    Star[I].X := Random(320);
    Star[I].Y := Random(200);
    Star[I].Z := Random(20) + 70;
  end;

  PA := 0;  PB := 0;  PC := 0;
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);

  for I := 1 to 100 do
  begin
    ObjTranslate(Obj[1], 0, 0, 3);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Frame := Frame + 1;
    Present;
  end;
  SyncPattern(2, 1);
  for I := 1 to  80 do
  begin
    ObjTranslate(Obj[1], 0, 0, 3);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Frame := Frame + 1;
    Present;
  end;
  for I := 1 to  20 do
  begin
    ObjTranslate(Obj[1], -1, 0, 3);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Frame := Frame + 1;
    Present;
  end;

  for I := 1 to 50 do
  begin
    Inc(PB, 5);  Dec(PC, 2);
    ObjTranslate(Obj[1], -2, 0, 2);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Frame := Frame + 1;
    Present;
  end;
  for I := 1 to 50 do
  begin
    Dec(PB, 5);  Inc(PA, 20);  Inc(PC, 2);
    ObjTranslate(Obj[1], -3, 0, 0);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Frame := Frame + 1;
    Present;
  end;
  for I := 1 to 50 do
  begin
    ObjTranslate(Obj[1], -3, 0, 0);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderA(Obj[1]);
    Frame := Frame + 1;
    Present;
  end;

  { the banner beat, inline: the original has no procedure here }
  SyncPattern(3, 1);
  WaitRetrace;
  DrawBanner;
  for I := 1 to 50 do WaitRetrace;
  { and the strip clear, also inline }
  WritePage := PageBase[0];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  WritePage := PageBase[1];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  Delay(300);
  { the banner beat, inline: the original has no procedure here }
  SyncPattern(3, 1);
  WaitRetrace;
  DrawBanner;
  for I := 1 to 50 do WaitRetrace;
  { and the strip clear, also inline }
  WritePage := PageBase[0];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  WritePage := PageBase[1];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  Delay(300);
  { the banner beat, inline: the original has no procedure here }
  SyncPattern(3, 1);
  WaitRetrace;
  DrawBanner;
  for I := 1 to 50 do WaitRetrace;
  { and the strip clear, also inline }
  WritePage := PageBase[0];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  WritePage := PageBase[1];
  FillRect(0, BannerTop, ScrWidth, Rows, WritePage, 0);
  {    DO NOT "FIX" THIS. Putting Present back costs 15 bytes and the frame counter
    about 100 more, and it would undo part of what took this part from 99.9% to
    100.0% with no unaligned span at all. If it is ever changed, it should be
    because somebody decided the demo should look different from its own
    binary -- which is a decision, not a correction. }

  for I := 1 to 12 do
  begin
    ObjTranslate(Obj[1], 12, 0, 0);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
  end;
  SyncPattern(4, 1);
  for I := 1 to 12 do
  begin
    Inc(PB, 20);  Dec(PA, 80);  Dec(PC, 8);
    ObjTranslate(Obj[1], 12, 0, 0);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
  end;
  for I := 1 to 12 do
  begin
    Dec(PB, 20);  Inc(PC, 8);
    ObjTranslate(Obj[1], 8, 0, -8);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
  end;
  for I := 1 to  5 do
  begin
    ObjTranslate(Obj[1], 4, 0, -12);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
  end;
  for I := 1 to 45 do
  begin
    ObjTranslate(Obj[1], 0, 0, -12);
    ObjTransform(Obj[1], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, 200, WritePage, 0);
    ObjSortFaces(Obj[1]);
    RenderB(Obj[1]);
  end;

  PA := 0;  PB := 0;  PC := 0;
  SyncPattern(6, 1);
  GetPalette768(@Buf);
  PaletteFadeOut(10);
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);
  SetPalette768(@Buf);
  SetRGB($18, $1E, $1E, $1E);

  for I := 1 to 120 do
  begin
    Inc(PB, 10);  Dec(PA, 40);  Dec(PC, 8);
    ObjTranslate(Obj[2], -20, 0, 10);
    ObjTransform(Obj[2], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, Rows, WritePage, 0);
    ObjSortFaces(Obj[2]);
    RenderC(Obj[2]);
  end;

  PA := 270;  PB := 180;  PC := 180;
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);
  ObjTransform(Obj[3], PC, PA, PB);

  for I := 1 to 120 do
  begin
    Inc(PA, 10);  Inc(PB, 10);  Inc(PC, 10);
    ObjTranslate(Obj[3], 20, 0, 10);
    ObjTransform(Obj[3], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, Rows, WritePage, 0);
    ObjSortFaces(Obj[3]);
    RenderC(Obj[3]);
  end;

  SetRGB($20, $3F, $3F, $3F);
  PA := 0;  PB := 0;  PC := 0;
  FillRect(0, 0, ScrWidth, Rows, Page0Base, 0);
  FillRect(0, 0, ScrWidth, Rows, Page1Base, 0);

  for I := 1 to 99 do
  begin
    { here the nudge comes AFTER the translate, not before }
    ObjTranslate(Obj[4], 0, 0, 10);
    Inc(PA, 37);  Inc(PB, 10);
    ObjTransform(Obj[4], PC, PA, PB);
    WritePage := PageBase[PageIndex];
    FillRect(0, 0, ScrWidth, Rows, WritePage, 0);
    ObjSortFaces(Obj[4]);
    RenderC(Obj[4]);
  end;
end;


{ --------------------------------------------------------------------------
Scene2_Setup }
{ and its three siblings zero the angle, translation and pivot
  blocks before writing whichever components the object needs. }
procedure Setup;
var
  I : Integer;      { 79 refs -- the outer index, and the palette
                      ramp counter earlier in the routine }
  K : Integer;      { 16 refs -- the inner face-index counter }
  P : Integer;      { 28 refs -- the flat face stream's position }
  Unused : array[1..128] of Byte;      { never read }
begin
  { a grey ramp with a period of 53 }
  for I := 1 to 255 do
    SetRGB(I, (I mod 53) + 10, (I mod 53) + 10, (I mod 53) + 10);

  { the thirteen overrides, in the order the code writes them }
  SetRGB($18, $0A, $00, $3C);
  SetRGB($30, $0A, $00, $3C);
  SetRGB($42, $00, $32, $00);
  SetRGB($D5, $32, $28, $1E);
  SetRGB($D6, $3C, $32, $28);
  SetRGB($D7, $37, $2D, $23);
  SetRGB($D8, $2D, $23, $19);
  SetRGB($D9, $28, $1E, $14);
  SetRGB($D1, $32, $28, $1E);
  SetRGB($D2, $3C, $32, $28);
  SetRGB($D3, $37, $2D, $23);
  SetRGB($D4, $2D, $23, $19);
  SetRGB($D5, $28, $1E, $14);

  { Scale := CentreX / 2.0 * 0.9 = 144.0.

    So `MScale := RealToFixed(MViewW / ScaleDivisor * ScaleFactor)` was tried.
    It made a specific prediction -- the LongInt spill would appear and the
    frame would go from $86 to the original's $8a -- and the prediction FAILED:
    the frame did not move and part 002's walk went 57.3% to 57.2%. Whatever
    produces that spill, this is not it. The Round form is kept because it is
    the one that measures better, not because it is believed. }
  SetupDone := 1;                     { written and never read }
  MScale := RealToFixed(MViewW / ScaleDivisor * ScaleFactor);

  { Enterprise. The counts are written as immediates before the
    loops and read back OUT of the object by them. }
  Obj[1].VertCount := NVertEnterprise;
  Obj[1].FaceCount := NFaceEnterprise;
  for I := 1 to Obj[1].VertCount do
  begin
    Obj[1].Vert[I].X := IntToFixed(VertEnterprise[(I - 1) * 3] div 2);
    Obj[1].Vert[I].Y := IntToFixed(VertEnterprise[(I - 1) * 3 + 1] div 2);
    Obj[1].Vert[I].Z := IntToFixed(VertEnterprise[(I - 1) * 3 + 1 + 1] div 2);
  end;
  P := 0;
  for I := 1 to Obj[1].FaceCount do
  begin
    Obj[1].Face[I].Count := FaceEnterprise[P];
    for K := 1 to Obj[1].Face[I].Count do
    begin
      Inc(P);
      Obj[1].Face[I].Idx[K] := FaceEnterprise[P] + 1;
    end;
    Inc(P);
    Obj[1].Face[I].Colour := FaceEnterprise[P] div 2;
    Obj[1].Face[I].Spare1 := 0;
    Obj[1].Face[I].Spare2 := 0;
    Inc(P);
  end;
  Obj[1].Angle.X := 0;
  Obj[1].Angle.Y := 0;
  Obj[1].Angle.Z := 0;
  Obj[1].Accum.X := 0;
  Obj[1].Accum.Y := 0;
  Obj[1].Accum.Z := 0;
  Obj[1].Trans.X := 0;
  Obj[1].Trans.Y := 0;
  Obj[1].Trans.Z := IntToFixed(-850);
  Obj[1].Pivot.X := IntToFixed(150);
  Obj[1].Pivot.Y := 0;
  Obj[1].Pivot.Z := IntToFixed(0);

  { Revolver. The counts are written as immediates before the
    loops and read back OUT of the object by them. }
  Obj[2].VertCount := NVertRevolver;
  Obj[2].FaceCount := NFaceRevolver;
  for I := 1 to Obj[2].VertCount do
  begin
    Obj[2].Vert[I].X := IntToFixed(VertRevolver[(I - 1) * 3] div 2);
    Obj[2].Vert[I].Y := IntToFixed(VertRevolver[(I - 1) * 3 + 1] div 2);
    Obj[2].Vert[I].Z := IntToFixed(VertRevolver[(I - 1) * 3 + 1 + 1] div 2);
  end;
  P := 0;
  for I := 1 to Obj[2].FaceCount do
  begin
    Obj[2].Face[I].Count := FaceRevolver[P];
    for K := 1 to Obj[2].Face[I].Count do
    begin
      Inc(P);
      Obj[2].Face[I].Idx[K] := FaceRevolver[P];
    end;
    Inc(P);
    Obj[2].Face[I].Colour := FaceRevolver[P];
    Obj[2].Face[I].Spare1 := 0;
    Obj[2].Face[I].Spare2 := 0;
    Inc(P);
  end;
  Obj[2].Angle.X := 0;
  Obj[2].Angle.Y := 0;
  Obj[2].Angle.Z := 0;
  Obj[2].Accum.X := 0;
  Obj[2].Accum.Y := 0;
  Obj[2].Accum.Z := 0;
  Obj[2].Trans.X := IntToFixed(1500);
  Obj[2].Trans.Y := 0;
  Obj[2].Trans.Z := IntToFixed(-1500);
  Obj[2].Pivot.X := IntToFixed(150);
  Obj[2].Pivot.Y := 0;
  Obj[2].Pivot.Z := IntToFixed(0);

  { Sailboat. The counts are written as immediates before the
    loops and read back OUT of the object by them. }
  Obj[3].VertCount := NVertSailboat;
  Obj[3].FaceCount := NFaceSailboat;
  for I := 1 to Obj[3].VertCount do
  begin
    Obj[3].Vert[I].X := IntToFixed(VertSailboat[(I - 1) * 3] div 2);
    Obj[3].Vert[I].Y := IntToFixed(VertSailboat[(I - 1) * 3 + 1] div 2);
    Obj[3].Vert[I].Z := IntToFixed(VertSailboat[(I - 1) * 3 + 1 + 1] div 2);
  end;
  P := 0;
  for I := 1 to Obj[3].FaceCount do
  begin
    Obj[3].Face[I].Count := FaceSailboat[P];
    for K := 1 to Obj[3].Face[I].Count do
    begin
      Inc(P);
      Obj[3].Face[I].Idx[K] := FaceSailboat[P];
    end;
    Inc(P);
    Obj[3].Face[I].Colour := FaceSailboat[P];
    Obj[3].Face[I].Spare1 := 0;
    Obj[3].Face[I].Spare2 := 0;
    Inc(P);
  end;
  Obj[3].Angle.X := 0;
  Obj[3].Angle.Y := 0;
  Obj[3].Angle.Z := 0;
  Obj[3].Accum.X := 0;
  Obj[3].Accum.Y := 0;
  Obj[3].Accum.Z := 0;
  Obj[3].Trans.X := IntToFixed(-1500);
  Obj[3].Trans.Y := 0;
  Obj[3].Trans.Z := IntToFixed(-1500);
  Obj[3].Pivot.X := IntToFixed(0);
  Obj[3].Pivot.Y := IntToFixed(0);
  Obj[3].Pivot.Z := IntToFixed(0);

  { Quad. The counts are written as immediates before the
    loops and read back OUT of the object by them. }
  Obj[4].VertCount := NVertQuad;
  Obj[4].FaceCount := NFaceQuad;
  for I := 1 to Obj[4].VertCount do
  begin
    Obj[4].Vert[I].X := IntToFixed(VertQuad[(I - 1) * 3] div 2);
    Obj[4].Vert[I].Y := IntToFixed(VertQuad[(I - 1) * 3 + 1] div 2);
    Obj[4].Vert[I].Z := IntToFixed(VertQuad[(I - 1) * 3 + 1 + 1] div 2);
  end;
  P := 0;
  for I := 1 to Obj[4].FaceCount do
  begin
    Obj[4].Face[I].Count := FaceQuad[P];
    for K := 1 to Obj[4].Face[I].Count do
    begin
      Inc(P);
      Obj[4].Face[I].Idx[K] := FaceQuad[P];
    end;
    Inc(P);
    Obj[4].Face[I].Colour := FaceQuad[P];
    Obj[4].Face[I].Spare1 := 0;
    Obj[4].Face[I].Spare2 := 0;
    Inc(P);
  end;
  Obj[4].Angle.X := 0;
  Obj[4].Angle.Y := 0;
  Obj[4].Angle.Z := 0;
  Obj[4].Accum.X := 0;
  Obj[4].Accum.Y := 0;
  Obj[4].Accum.Z := 0;
  Obj[4].Trans.X := 0;
  Obj[4].Trans.Y := 0;
  Obj[4].Trans.Z := IntToFixed(-1000);
  Obj[4].Pivot.X := IntToFixed(0);
  Obj[4].Pivot.Y := IntToFixed(0);
  Obj[4].Pivot.Z := IntToFixed(0);
end;


{ --------------------------------------------------------------------------
Demo_Scene2

  NEUROSIS.DAT from $0007D9B2, in four reads:

      12,800   the 320 x 40 banner strip
       1,550   the 5 x 5 font, 62 glyphs
         768   palette
       1,462   the 34 x 43 badge

  with the mode set and the first two objects built between the second and
  third reads, exactly as below.
  -------------------------------------------------------------------------- }
procedure Scene2;
var
  { ENTER $80 is 128 bytes and no BP-relative slot is touched at all: the
    whole frame is the untyped `file`, which is 128 bytes in Turbo Pascal.
    There was a `Vol : Byte` here that the routine wrote and never read, and
    it put the frame at $82. The saved volume is a global -- see SaveVol. }
  { 128 bytes declared and never read, as LoadFrames has: the handle is the
    global DatFile and no BP-relative slot in this routine is touched. }
  Unused : array[1..128] of Byte;
begin
  Assign(DatFile, 'neurosis.dat');
  Reset(DatFile, 1);
  Seek(DatFile, DataOfs);
  GetMem(Banner, SizeOf(TBanner));
  BlockRead(DatFile, Banner^, SizeOf(TBanner));
  BlockRead(DatFile, Font, SizeOf(TFont));

  MusicStart;
  Frame := 0;
  SetMode400;
  BuildRowTable80;
  FlipPage(0);

  BlockRead(DatFile, Pal, 768);
  Setup;
  BlockRead(DatFile, Rewind, SizeOf(TRewind));
  Close(DatFile);

  { six fixed colours before the choreography }
  VGA.SetRGB(1, $3F, $3F, $3F);
  VGA.SetRGB(2, $1B, $1B, $1B);
  VGA.SetRGB(3, $27, $27, $27);
  VGA.SetRGB(4, $03, $33, $03);
  VGA.SetRGB(5, $0F, $27, $0F);
  VGA.SetRGB(6, $16, $16, $16);

  Choreography;

  { ramp the volume to zero, then stop }
  { the ramp, and the body really is written out TWICE with a
    test between the halves. Every GetVolume result goes to CurVol and the
    sequence is: read, step down, read, and if that is not yet zero do the
    three again, then Delay and test. Reading it as a `while GetVolume > 0`
    loop gave one copy of the body and a different test. }
  SaveVol := GetVolume;
  repeat
    CurVol := GetVolume;
    SetVolume(CurVol - 1);
    CurVol := GetVolume;
    if CurVol <> 0 then
    begin
      CurVol := GetVolume;
      SetVolume(CurVol - 1);
      CurVol := GetVolume;
    end;
    Delay(10);
  until CurVol = 0;
  SyncPattern(1, 1);
  MusicStop;
  SetVolume(SaveVol);

  FreeMem(Banner, SizeOf(TBanner));
end;


begin
end.
