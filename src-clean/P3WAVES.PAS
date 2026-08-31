{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 6
  Reconstructed from NEUROSIS_003_fpu.exe, segment 120f.

  800 particles tracing precomputed curves, swept across the screen four
  times with different parameters each pass.

  The curve shapes are not computed at run time. A 36,414-byte table holds
  51 curves of 357 X-offsets each; a particle is just (curve index, phase,
  row), and advancing its phase walks it along its curve.

  Nothing is ever cleared. Each particle erases its own previous pixel and
  draws the new one, so the cost is two byte writes per particle per frame. }

unit P3Waves;

{ 286 instructions are permitted -- the step loop shifts by two bits. }
{$G+}
{ 80x87 code on: the palette ramp is computed in floating point. }
{$N+}
{ No I/O checking: a failed read is silent, as the original has it. }
{$I-}

interface

procedure Scene6;

implementation

uses VGA, Crt;

{ Where each asset sits inside NEUROSIS.DAT. }
{$I gen/DATOFS.INC}

const
  DataOfs    = DAT_P3_WAVECURV;   { $116082 -- NEUROSIS.DAT -- 1,138,818 }
  DataSize   = $8E3E;        { 36,414 }

  CurveBytes = $2CA;         { 714 bytes = 357 words per curve }
  CurveSteps = 357;
  Curves     = DataSize div CurveBytes;

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
  F      : file;

{ --------------------------------------------------------------------------
  Waves_LoadCurves
  ASSETS  NEUROSIS.DAT $116082, 36,414 bytes:
            assets/part003/WAVECURV.BIN
          51 curves x 357 signed 16-bit X offsets. 51 * 714 = 36,414 exactly,
          which is what fixes the stride.
          See docs/12-part3-scene6-waves.md.

  so a particle is BRIGHTEST MID-PHASE and dim at both ends of its curve.
  An earlier version of this unit ended at the Close, leaving whatever
  palette the previous scene had -- under scene 5's monotone ramp the low
  phases (the left half of the shape) rendered dark, which is the defect
  the first observation run reported (plan: part3-s6-left-dark). Measured
  from the screenshots: ours stepped from median blue 84 on the left to
  108 on the right; the original sits near 107 across the whole shape.
  -------------------------------------------------------------------------- }
procedure LoadCurves;
var
  Unread : array[0..127] of Byte;   { never read }
  I      : Integer;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  GetMem(CurveTab, DataSize);
  BlockRead(F, CurveTab^, DataSize);
  Close(F);

  { colour 89 is written by both loops, same value both times. }
  for I := 1 to 89 do
    SetRGB(I, 0, 0, Round(I * 0.4) + 27);
  for I := 89 to 178 do
    SetRGB(I, 0, 0, Round((178 - I) * 0.4) + 27);
end;

{ --------------------------------------------------------------------------
  Waves_Step
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

  so the stray store writes Col into the CURVE TABLE at offset 356 + NewX,
  i.e. bytes 357..675 -- the back half of curve 0, the straight centre
  line. Colour bytes are 0..178, so a corrupted LOW byte moves a curve-0
  point from x = 160 to x = 0..178, the left half of the screen; a
  corrupted HIGH byte pushes the point past 320 and it just stops drawing.
  The corruption accumulates across all four passes (the table is loaded
  once), and a point corrupted between its draw and its erase leaves the
  old pixel lit for good.

  (An earlier note here blamed this corruption for the left half of the
  shape rendering darker in the reconstruction. It was not the cause --
  the shape was dark on the left because LoadCurves' own TRIANGLE palette
  was missing, see above it -- but the stray store is real, the bytes at
 prove it, and it stays transcribed verbatim.)
  -------------------------------------------------------------------------- }
procedure Step;
var
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
  Waves_Run
  Four passes. Each seeds the particle array differently, spreads the phases
  so the particles are staggered along their curves, then sweeps SweepX from
  -320 to +320.

  The phase spread is done the slow way in the original -- a loop that
  advances one particle's phase (i * 15) mod 360 times, one step at a time --
  which costs a couple of hundred thousand iterations but only happens four
  times, between passes.
  -------------------------------------------------------------------------- }
procedure Run;
var
  I, J : Integer;
begin

  { --- pass 1: every particle on curve 30, rows 0..199 --- }
  for I := 1 to Particles do
  begin
    P[I].Curve := 30;
    P[I].Phase := 0;
    P[I].Row   := I mod 200;
  end;
  for J := 1 to Particles do
    for I := 1 to (J * 15) mod 360 do
      P[J].Phase := P[J].Phase mod PhaseWrap + 1;

  { The sweep. SweepX := SweepX + 1 is an ASSIGNMENT and not Inc:
    MOV AX,[SweepX] / INC AX / MOV [SweepX],AX, seven bytes through the
    accumulator where Inc would emit four. }
  SweepX := SweepFrom;
  repeat
    Step;
    SweepX := SweepX + 1;
  until SweepX = SweepTo;

  { --- pass 2: curves spread, rows x4 --- }
  for I := 1 to Particles do
  begin
    P[I].Curve := (I mod 100) div 2;
    P[I].Phase := 0;
    P[I].Row   := (I * 4) mod 200;               { SHL AX,2 }
  end;
  for J := 1 to Particles do
    for I := 1 to (J * 15) mod 360 do
      P[J].Phase := P[J].Phase mod PhaseWrap + 1;

  { The sweep. SweepX := SweepX + 1 is an ASSIGNMENT and not Inc:
    MOV AX,[SweepX] / INC AX / MOV [SweepX],AX, seven bytes through the
    accumulator where Inc would emit four. }
  SweepX := SweepFrom;
  repeat
    Step;
    SweepX := SweepX + 1;
  until SweepX = SweepTo;

  { --- pass 3: the same curves, rows x8 --- }
  for I := 1 to Particles do
  begin
    P[I].Curve := (I mod 100) div 2;
    P[I].Phase := 0;
    P[I].Row   := (I * 8) mod 200;               { SHL AX,3 }
  end;
  for J := 1 to Particles do
    for I := 1 to (J * 15) mod 360 do
      P[J].Phase := P[J].Phase mod PhaseWrap + 1;

  { The sweep. SweepX := SweepX + 1 is an ASSIGNMENT and not Inc:
    MOV AX,[SweepX] / INC AX / MOV [SweepX],AX, seven bytes through the
    accumulator where Inc would emit four. }
  SweepX := SweepFrom;
  repeat
    Step;
    SweepX := SweepX + 1;
  until SweepX = SweepTo;

  { --- pass 4: curves spread wider, rows x8 --- }
  for I := 1 to Particles do
  begin
    P[I].Curve := (I mod 200) div 4;
    P[I].Phase := 0;
    P[I].Row   := (I * 8) mod 200;
  end;
  for J := 1 to Particles do
    for I := 1 to (J * 15) mod 360 do
      P[J].Phase := P[J].Phase mod PhaseWrap + 1;

  { The sweep. SweepX := SweepX + 1 is an ASSIGNMENT and not Inc:
    MOV AX,[SweepX] / INC AX / MOV [SweepX],AX, seven bytes through the
    accumulator where Inc would emit four. }
  SweepX := SweepFrom;
  repeat
    Step;
    SweepX := SweepX + 1;
  until SweepX = SweepTo;
end;

procedure Scene6;
begin
  LoadCurves;
  Run;
  FreeMem(CurveTab, DataSize);
end;

begin
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

    All 51 overlaid: assets/part003/WAVECRVA.PNG

  RESOLVED -- WHY THE LEFT HALF RENDERED DARKER THAN THE ORIGINAL
  * LoadCurves builds the scene's own palette after the BlockRead: a blue
    TRIANGLE over colours 1..178, peaking at 89 -- brightest MID-PHASE. The
    reconstruction had ended the routine at the Close, inheriting scene 5's
    monotone ramp, under which low phases (the shape's left half) are dark.
    Confirmed by measuring both screenshots; details above LoadCurves.
  * Separately, Step's erase/draw is hand BASM with ES and the row offset
    set up only in the erase branch. A particle re-entering the screen
    draws through the stale registers instead -- a colour byte into the
    curve table at offset 356 + NewX, corrupting the back half of curve 0.
    That is the original's own bug, transcribed verbatim; it was once
    blamed for the left-half difference and is not the cause.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
