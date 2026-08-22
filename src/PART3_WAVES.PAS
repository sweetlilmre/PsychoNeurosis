{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 6
  Reconstructed from NEUROSIS_003_fpu.exe, segment 120f.

  800 particles tracing precomputed curves, swept across the screen four
  times with different parameters each pass.

  The curve shapes are not computed at run time. A 36,414-byte table holds
  51 curves of 357 X-offsets each; a particle is just (curve index, phase,
  row), and advancing its phase walks it along its curve.

  Nothing is ever cleared. Each particle erases its own previous pixel and
  draws the new one, so the cost is two byte writes per particle per frame.

  ADDRESS MAP
    Demo_Scene6  120f:04d0     Waves_LoadCurves  120f:0017
    Waves_Run    120f:01f8     Waves_Step        120f:00fe
  =========================================================================== }

unit Part3Waves;

{$G+}   { 286: the binary's Step is 286 codegen -- SHL DI,2 as C1 E7 02 and
          curve*714 as IMUL AX,AX,2CAh. This is not cosmetic here: with $G-
          the compiler multiplies with MUL DX instead, which forces the
          phase*2 temp OUT of DX into CX -- and CX still holding 356 from
          the phase-update IDIV is half of what the erase/draw bug in Step
          writes through. Measured: 120f:012f..014b vs a $G- build. }

interface

procedure Scene6;

implementation

uses VGA, Crt;

const
  DataOfs    = $116082;      { NEUROSIS.DAT -- 1,138,818 }
  DataSize   = $8E3E;        { 36,414 }

  CurveBytes = $2CA;         { 714 bytes = 357 words per curve }
  CurveSteps = 357;
  Curves     = DataSize div CurveBytes;   { 51 }

  Particles  = 800;
  PhaseWrap  = $164;         { 356 }
  SweepFrom  = -320;         { $FEC0 }
  SweepTo    = 320;          { $140  }

type
  { Four bytes per particle, exactly as laid out in DGROUP:
      +0 curve index, +1..2 phase (word), +3 screen row }
  TParticle = record
    Curve : Byte;
    Phase : Integer;
    Row   : Byte;
  end;

{ TP7 has no anonymous array types in a pointer declaration. }
type
  TCurves = array[0..Curves - 1, 0..CurveSteps - 1] of Integer;

var
  { Not simply `Curve` -- TParticle already has a Curve field, and inside
    `with P[I] do` the field would win. }
  CurveTab : ^TCurves;                              { 36,414 bytes }
  P      : array[1..Particles] of TParticle;
  SweepX : Integer;

{ --------------------------------------------------------------------------
  Waves_LoadCurves (120f:0017)

  ASSETS  NEUROSIS.DAT $116082, 36,414 bytes:
            assets/part003/waves_curves.bin
          51 curves x 357 signed 16-bit X offsets. 51 * 714 = 36,414 exactly,
          which is what fixes the stride.
          See docs/12-part3-scene6-waves.md.
  -------------------------------------------------------------------------- }
procedure LoadCurves;
var
  F : file;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  GetMem(CurveTab, DataSize);
  BlockRead(F, CurveTab^, DataSize);
  Close(F);
end;

{ --------------------------------------------------------------------------
  Waves_Step (120f:00fe)

  One frame. For each particle: work out where it was, advance its phase,
  work out where it is now, erase the old pixel and draw the new one.

  Colour is Phase div 2, so a particle's colour changes as it travels -- the
  trail reads as a gradient rather than a flat line.

  The erase and the draw are a hand BASM block in the original (the STOSB
  and the XOR/MOV/SHL row-table setup are the tells; compiled TP7 never
  emits STOSB for a single store), and the block carries a REAL BUG this
  unit must reproduce: ES and CX are set up INSIDE the erase branch only,
  so a particle whose old pixel is offscreen but whose new pixel is not
  gets its draw stored through whatever ES:CX already hold. The compiled
  code above the block leaves both deterministic every iteration:

      CX = 356               parked there by `Phase mod PhaseWrap`
                             (MOV CX,164h / IDIV CX at 120f:0161)
      ES = Seg(CurveTab^)    left by the LES that read the new curve X
                             (120f:0190)

  so the stray store writes Col into the CURVE TABLE at offset 356 + NewX,
  i.e. bytes 357..675 -- the back half of curve 0, the straight centre
  line. Colour bytes are 0..178, so a corrupted LOW byte moves a curve-0
  point from x = 160 to x = 0..178, the left half of the screen; a
  corrupted HIGH byte pushes the point past 320 and it just stops drawing.
  The corruption accumulates across all four passes (the table is loaded
  once), and a point corrupted between its draw and its erase leaves the
  old pixel lit for good. That drift and litter is why the original's dot
  object is BRIGHTER on the left half: an earlier Pascal-isation of this
  block re-derived ES and the row offset for the draw, rendered every
  pixel correctly, and so came out darker (plan: part3-s6-left-dark).
  -------------------------------------------------------------------------- }
procedure Step;
var
  { Declared in this order so the frame matches the binary's:
    I at [BP-2], Row [BP-3], Col [BP-4], OldX [BP-6], NewX [BP-8]. }
  I    : Integer;
  Row  : Byte;
  Col  : Byte;
  OldX : Integer;
  NewX : Integer;
begin
  if KeyPressed then Exit;
  { No `with P[I] do` here, for two measured reasons: the binary recomputes
    DI := I*4 before EVERY field access, which is what explicit P[I].x
    compiles to (a with-statement caches the base once); and inside the asm
    block below a with-scope makes BASM resolve `Row` to the FIELD -- which
    assembles as MOV BL,3, the field's offset, not a load of the local. }
  for I := 1 to Particles do
    begin
      Row  := P[I].Row;
      OldX := CurveTab^[P[I].Curve, P[I].Phase] + SweepX - 1;
      P[I].Phase := P[I].Phase mod PhaseWrap + 1;
      NewX := CurveTab^[P[I].Curve, P[I].Phase] + SweepX;
      Col  := P[I].Phase shr 1;

      { EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

            if (OldX > 0) and (OldX < 320) then
              Mem[VGASeg : YOfs[Row] + OldX] := 0;
            if (NewX > 0) and (NewX < 320) then
              Mem[VGASeg : YOfs[Row] + NewX] := Col;

        Where that Pascal is not the same thing: it re-derives the segment
        and the row offset for the draw, which is exactly the bug it fails
        to reproduce -- see the block comment above this routine. }

      { @asm 003 120f:01b1 +59 StepEraseDraw }
      asm
        CMP  OldX, 0             { old pixel off the left edge (x <= 0)?     }
        JLE  @@NoErase           {   then nothing to erase                   }
        CMP  OldX, 320           { off the right edge (x >= 320)?            }
        JGE  @@NoErase           {   same                                    }
        MOV  AX, VGASeg          { $A000                                     }
        MOV  ES, AX              { ES := the screen -- set ONLY here         }
        XOR  BX, BX              { clear BH ahead of the byte load           }
        MOV  BL, Row             { BL := the particle's row                  }
        SHL  BX, 1               { byte index -> word index                  }
        MOV  CX, [BX + OFFSET YOfs]  { CX := Row * 320 -- set ONLY here      }
        MOV  DI, CX              { DI := start of the row                    }
        ADD  DI, OldX            { DI := the old pixel                       }
        MOV  AL, 0               { black                                     }
        STOSB                    { erase it                                  }
      @@NoErase:
        CMP  NewX, 0             { new pixel off the left edge?              }
        JLE  @@NoDraw            {   then nothing to draw                    }
        CMP  NewX, 320           { off the right edge?                       }
        JGE  @@NoDraw            {   same                                    }
        MOV  DI, CX              { DI := row start -- STALE (356) if the     }
                                 {   erase above was skipped                 }
        ADD  DI, NewX            { DI := the new pixel                       }
        MOV  AL, Col             { the colour, Phase shr 1                   }
        STOSB                    { draw -- through ES, which is still the    }
                                 {   CURVE TABLE if the erase was skipped    }
      @@NoDraw:
      end;
    end;
end;

{ --------------------------------------------------------------------------
  Waves_Run (120f:01f8)

  Four passes. Each seeds the particle array differently, spreads the phases
  so the particles are staggered along their curves, then sweeps SweepX from
  -320 to +320.

  The phase spread is done the slow way in the original -- a loop that
  advances one particle's phase (i * 15) mod 360 times, one step at a time --
  which costs a couple of hundred thousand iterations but only happens four
  times, between passes.
  -------------------------------------------------------------------------- }
procedure Run;

  procedure Pass(SeedCurve, SeedRow : Integer);
  var
    I, J, N : Integer;
  begin
    for I := 1 to Particles do
    begin
      case SeedCurve of
        0 : P[I].Curve := 30;                    { pass 1: one curve for all }
        1 : P[I].Curve := (I mod 100) div 2;     { passes 2 and 3 }
        2 : P[I].Curve := (I mod 200) div 4;     { pass 4 }
      end;
      P[I].Phase := 0;
      case SeedRow of
        0 : P[I].Row := I mod 200;
        1 : P[I].Row := (I * 4) mod 200;
        2 : P[I].Row := (I * 8) mod 200;
      end;
    end;

    for I := 1 to Particles do
    begin
      N := (I * 15) mod 360;
      for J := 1 to N do
        P[I].Phase := P[I].Phase mod PhaseWrap + 1;
    end;

    SweepX := SweepFrom;
    repeat
      Step;
      Inc(SweepX);
    until SweepX = SweepTo;
  end;

begin
  Pass(0, 0);      { flat: every particle on curve 30, rows 0..199 }
  Pass(1, 1);      { curves spread, rows x4 }
  Pass(1, 2);      { curves spread, rows x8 }
  Pass(2, 2);      { curves spread wider, rows x8 }
end;

procedure Scene6;
begin
  LoadCurves;
  Run;
  FreeMem(CurveTab, DataSize);
end;

end.

{ ===========================================================================
  NOTES

  * Erase-then-draw instead of clear-and-redraw. With 800 particles that is
    1,600 byte writes per frame against 64,000 for a full clear.
  * The sweep runs 640 frames per pass, so each pass is roughly 9 seconds at
    70 Hz and the scene about 36 seconds in total.
  * Particles write straight to $A000; there is no virtual screen in this
    scene, which is consistent with never needing a full-screen operation.

  RESOLVED -- WHAT THE 51 CURVES LOOK LIKE
  * They are ABSOLUTE X COORDINATES, not signed offsets: every value is in
    0..317 and every curve starts at x = 160, the centre of the screen. (The
    earlier note in this file called them offsets; that was wrong.)
  * The 51 curves are one shape at 51 amplitudes. Each traces a decaying
    oscillation away from centre -- out to one side, back, out to the other --
    and the peak-to-peak amplitude grows STRICTLY MONOTONICALLY with the curve
    index:

        curve  0    amplitude   0     a dead straight vertical line
        curve  1    amplitude   6
        curve 15    amplitude  95
        curve 30    amplitude 190
        curve 50    amplitude 317     the full width of the screen

    so the index is effectively an amplitude dial. That is exactly why the
    passes work the way they do: pass 0 puts every particle on curve 30 (mid
    amplitude, so they all trace the same wave), and the later passes spread
    the indices to fan the particles out into a family of nested waves.

    All 51 overlaid: assets/part003/waves_curves_all.png

  RESOLVED -- WHY THE LEFT HALF IS BRIGHTER IN THE ORIGINAL
  * Step's erase/draw is hand BASM with ES and the row offset set up only in
    the erase branch. A particle re-entering the screen draws through the
    stale registers instead -- a colour byte into the curve table at offset
    356 + NewX, corrupting the back half of curve 0. The drift and the
    unerased litter it causes are part of the original's look, so the block
    is transcribed verbatim, bug included. Details above Waves_Step.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
