{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the shared VGA unit.
  Reconstructed from NEUROSIS_003_fpu.exe, segments 12f8 and 1192.

  THIS UNIT IS HAND-WRITTEN ASSEMBLER, not compiled Pascal, and is written
  back as `assembler` procedures so the original instruction sequences are
  preserved rather than paraphrased.

  How we can tell: VGA_WaitRetrace has no procedure prologue whatsoever, the
  blit and clear are REP MOVSW / REP STOSW with CX preloaded, and PutPixel
  indexes a precomputed row table and falls straight into STOSB. Borland
  Pascal 7 does not generate any of that shape -- it would emit ENTER/LEAVE,
  BP-relative locals and a multiply for the row offset.

  All of them end in RETF n, i.e. far procedures using the Pascal calling
  convention with callee stack cleanup -- so they are `procedure ...; far;
  assembler;` in the original source.

  ADDRESS MAP
    PutPixel        12f8:0048      SetRGB          12f8:0064
    GetRGB          12f8:007f      WaitRetrace     12f8:009f
    CopyScreen      12f8:00ad      ClearScreen     12f8:00c9
    SetMode         1192:002a      SelectPlane     1192:0087
  =========================================================================== }

{ ===========================================================================
  A NOTE ON PARAMETER ORDER -- read this before changing any signature here.

  Borland Pascal pushes parameters LEFT TO RIGHT, and the stack grows DOWN.
  So inside the callee the FIRST (leftmost) parameter is at the HIGHEST [BP+n]
  offset, and the last is at the lowest:

      procedure P(A, B, C);   near   ->   [BP+8]=A  [BP+6]=B  [BP+4]=C

  Ghidra's decompiler prints arguments in ASCENDING [BP+n] order, which is the
  REVERSE of the declaration. Taking that listing as the signature is how the
  whole of this unit ended up backwards on the first pass -- the behaviour was
  right, because the call sites were reversed to match, but the signatures did
  not correspond to the binary at all.

  The orders below are read off the disassembly and are the originals.
  =========================================================================== }

unit VGA;

interface

const
  ScrWidth  = 320;
  ScrHeight = 200;
  VGASeg    = $A000;

const
  { DS:$76B6 -- the Mode-X plane stride: 80 bytes per row = 320 pixels.
    SetMode writes it straight to CRTC register $13 (Offset), and
    BuildRowTable doubles it, giving a 640-pixel LOGICAL width so the visible
    320 is a window that can be panned. It sits in the executable's
    initialised data, so it was a typed constant -- which in Borland Pascal is
    writable, and that is what lets a scene change the stride at run time. }
  LogicalWidth : Byte = 80;

var
  { Row offset lookup, DS:$E772 -- YOfs[y] = y * 320. PutPixel indexes this
    rather than multiplying, which is why it needs no MUL. }
  YOfs : array[0..ScrHeight - 1] of Word;

type
  { The DAC in the order the hardware wants it: R, G, B per entry, 0..63. }
  TPalette = array[0..255, 0..2] of Byte;

var
  { The virtual screen every part draws into before blitting to $A000.
    64,000 bytes on the heap; VirtScrSeg is its segment, and because GetMem
    returns a normalised pointer the offset is always 0 -- which is why every
    part addresses it as a bare segment. }
  VirtScr    : Pointer;
  VirtScrSeg : Word;
  Palette    : TPalette;

procedure SetMode13h;
procedure SetTextMode;
procedure BuildRowTable;
procedure VirtScrAlloc;
procedure VirtScrFree;
procedure ClearVirtual;
procedure FlushKeys;
procedure SetPalette;
procedure GetPalette;
procedure DrawLine(X1, Y1, X2, Y2 : Integer; Colour : Byte; Segment : Word);

procedure PutPixel(X, Y : Word; Colour : Byte; Segment : Word); far;
procedure SetRGB(Col, R, G, B : Byte); far;
procedure GetRGB(Col : Byte; var R, G, B : Byte); far;
procedure WaitRetrace; far;
procedure CopyScreen(SrcSeg, DestSeg : Word); far;
procedure ClearScreen(Segment : Word; Colour : Byte); far;
procedure SetMode; far;
procedure SelectPlane(Plane : Byte); far;

implementation

uses Crt;   { FlushKeys needs KeyPressed/ReadKey }

{ --------------------------------------------------------------------------
  12f8:0048 -- plot one pixel via the row table.
  -------------------------------------------------------------------------- }
procedure PutPixel(X, Y : Word; Colour : Byte; Segment : Word); assembler;
asm
  MOV  AX, Segment
  MOV  ES, AX
  MOV  BX, Y
  SHL  BX, 1
  MOV  DI, [BX + OFFSET YOfs]   { DS:$E772 }
  ADD  DI, X
  MOV  AL, Colour
  STOSB
end;

{ --------------------------------------------------------------------------
  12f8:0064 -- write one DAC entry. Index to $3C8, then R,G,B to $3C9.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  12f8:0064 -- one DAC entry.

  ARGUMENT ORDER MATTERS and the reconstruction had it backwards. The original
  pushes the COLOUR INDEX FIRST:

      [BP+$C] -> $3C8   index      (first pushed)
      [BP+$A] -> $3C9   R
      [BP+$8] -> $3C9   G
      [BP+$6] -> $3C9   B          (last pushed)

  Declared as (B, G, R, Col) the body still worked, but call sites disagreed
  with each other -- and the tunnel's `for I := 0 to 255 do SetRGB(I,0,0,0)`
  set colour ZERO's blue 256 times instead of blanking the palette. That is
  the blue screen.
  -------------------------------------------------------------------------- }
procedure SetRGB(Col, R, G, B : Byte); assembler;
asm
  MOV  DX, $3C8
  MOV  AL, Col
  OUT  DX, AL
  INC  DX
  MOV  AL, R
  OUT  DX, AL
  MOV  AL, G
  OUT  DX, AL
  MOV  AL, B
  OUT  DX, AL
end;

{ --------------------------------------------------------------------------
  12f8:007f -- read one DAC entry back. Index to $3C7, three reads from $3C9.
  Results go straight to the var parameters with LES/STOSB.
  -------------------------------------------------------------------------- }
procedure GetRGB(Col : Byte; var R, G, B : Byte); assembler;
asm
  MOV  DX, $3C7
  MOV  AL, Col
  OUT  DX, AL
  ADD  DX, 2
  IN   AL, DX
  LES  DI, R
  STOSB
  IN   AL, DX
  LES  DI, G
  STOSB
  IN   AL, DX
  LES  DI, B
  STOSB
end;

{ --------------------------------------------------------------------------
  12f8:009f -- wait for the start of vertical retrace.

  No prologue and no epilogue beyond RETF: this one is unmistakably hand
  assembler. It waits for retrace to END first, then for it to BEGIN, so the
  caller always gets a full frame of blanking rather than joining one late.
  -------------------------------------------------------------------------- }
procedure WaitRetrace; assembler;
asm
  MOV  DX, $3DA
@WaitEnd:
  IN   AL, DX
  TEST AL, 8
  JNZ  @WaitEnd
@WaitStart:
  IN   AL, DX
  TEST AL, 8
  JZ   @WaitStart
end;

{ --------------------------------------------------------------------------
  12f8:00ad -- 64000-byte screen copy (32000 words).

  Used two different ways: as a mode 13h page flip (virtual screen -> $A000),
  and in Scene 1 to push one 64000-byte Mode-X plane into video memory with
  the Map Mask already set.
  -------------------------------------------------------------------------- }
procedure CopyScreen(SrcSeg, DestSeg : Word); assembler;
asm
  PUSH DS
  MOV  AX, DestSeg
  MOV  ES, AX
  MOV  AX, SrcSeg
  MOV  DS, AX
  XOR  SI, SI
  XOR  DI, DI
  MOV  CX, 32000
  REP  MOVSW
  POP  DS
end;

{ --------------------------------------------------------------------------
  12f8:00c9 -- fill 64000 bytes with a colour (STOSW, so the byte is doubled).
  -------------------------------------------------------------------------- }
procedure ClearScreen(Segment : Word; Colour : Byte); assembler;
asm
  MOV  CX, 32000
  MOV  ES, Segment
  XOR  DI, DI
  MOV  AL, Colour
  MOV  AH, AL
  REP  STOSW
end;

{ --------------------------------------------------------------------------
  1192:002a -- mode 13h, then unchain to Mode-X at 640 logical width.
  -------------------------------------------------------------------------- }
procedure SetMode; assembler;
asm
  MOV  AX, $0013
  INT  $10

  MOV  DX, $3C4          { Sequencer 4: chain-4 off, extended memory on }
  MOV  AL, 4
  OUT  DX, AL
  INC  DX
  IN   AL, DX
  AND  AL, $F7
  OR   AL, 4
  OUT  DX, AL

  MOV  DX, $3CE          { Graphics 5: odd/even off }
  MOV  AL, 5
  OUT  DX, AL
  INC  DX
  IN   AL, DX
  AND  AL, $EF
  OUT  DX, AL

  MOV  DX, $3CE          { Graphics 6: chain odd/even off }
  MOV  AL, 6
  OUT  DX, AL
  INC  DX
  IN   AL, DX
  AND  AL, $FD
  OUT  DX, AL

  MOV  DX, $3C4          { Map Mask: enable all four planes... }
  MOV  AX, $0F02
  OUT  DX, AX
  { ...then clear all 64K, which with all planes live wipes the whole 256K }

  MOV  DX, $3D4          { CRTC $14: doubleword mode off }
  MOV  AL, $14
  OUT  DX, AL
  INC  DX
  IN   AL, DX
  AND  AL, $BF
  OUT  DX, AL

  MOV  DX, $3D4          { CRTC $17: byte mode on }
  MOV  AL, $17
  OUT  DX, AL
  INC  DX
  IN   AL, DX
  OR   AL, $40
  OUT  DX, AL

  MOV  DX, $3D4          { CRTC $13: logical width = 80*8 = 640 pixels }
  MOV  AL, $13
  OUT  DX, AL
  INC  DX
  MOV  AL, [LogicalWidth]      { DS:$76B6, set to 80 by the caller }
  OUT  DX, AL
end;

{ --------------------------------------------------------------------------
  1192:0087 -- Mode-X plane select (Sequencer register 2, Map Mask).
  -------------------------------------------------------------------------- }
procedure SelectPlane(Plane : Byte); assembler;
asm
  MOV  CL, Plane
  MOV  AH, 1
  SHL  AH, CL
  MOV  AL, 2
  MOV  DX, $3C4
  OUT  DX, AX
end;

{ ===========================================================================
  Shared screen management.

  These are the helpers every effect part assumes exist. Unlike the assembler
  routines above they are NOT transcribed instruction by instruction -- BP7
  inlines or duplicates most of them per part, so there is no single original
  to transcribe. They are written as ordinary Pascal doing the same job.
  =========================================================================== }

procedure BuildRowTable;
var
  Y : Integer;
begin
  for Y := 0 to ScrHeight - 1 do
    YOfs[Y] := Y * ScrWidth;
end;

procedure SetMode13h;
begin
  asm
    MOV  AX, $0013
    INT  $10
  end;
  BuildRowTable;
end;

procedure SetTextMode;
begin
  asm
    MOV  AX, $0003
    INT  $10
  end;
end;

procedure VirtScrAlloc;
begin
  GetMem(VirtScr, 64000);
  VirtScrSeg := Seg(VirtScr^);
end;

procedure VirtScrFree;
begin
  if VirtScr <> nil then
  begin
    FreeMem(VirtScr, 64000);
    VirtScr := nil;
    VirtScrSeg := 0;
  end;
end;

procedure ClearVirtual;
begin
  ClearScreen(VirtScrSeg, 0);
end;

procedure FlushKeys;
var
  C : Char;
begin
  while KeyPressed do C := ReadKey;
end;

{ Palette transfer. Port $3C8 selects the entry for writing ($3C7 for
  reading), then $3C9 takes R, G, B in turn and auto-increments, so the whole
  table moves in one burst. }
procedure SetPalette;
var
  I : Integer;
begin
  WaitRetrace;
  Port[$3C8] := 0;
  for I := 0 to 255 do
  begin
    Port[$3C9] := Palette[I, 0];
    Port[$3C9] := Palette[I, 1];
    Port[$3C9] := Palette[I, 2];
  end;
end;

procedure GetPalette;
var
  I : Integer;
begin
  Port[$3C7] := 0;
  for I := 0 to 255 do
  begin
    Palette[I, 0] := Port[$3C9];
    Palette[I, 1] := Port[$3C9];
    Palette[I, 2] := Port[$3C9];
  end;
end;

{ --------------------------------------------------------------------------
  DrawLine -- Bresenham. Part 001's copy of this unit is LARGER than part
  003's precisely because it carries this routine (1491:0048); parts that
  never draw a line do not link it.

  Argument order is the original's: segment, colour, then the two endpoints
  as (Y, X) pairs rather than (X, Y).
  -------------------------------------------------------------------------- }
procedure DrawLine(X1, Y1, X2, Y2 : Integer; Colour : Byte; Segment : Word);
var
  DX, DY, SX, SY, Err, E2 : Integer;
begin
  DX := Abs(X2 - X1);
  DY := Abs(Y2 - Y1);
  if X1 < X2 then SX := 1 else SX := -1;
  if Y1 < Y2 then SY := 1 else SY := -1;
  Err := DX - DY;
  while True do
  begin
    if (X1 >= 0) and (X1 < ScrWidth) and (Y1 >= 0) and (Y1 < ScrHeight) then
      PutPixel(X1, Y1, Colour, Segment);
    if (X1 = X2) and (Y1 = Y2) then Exit;
    E2 := Err * 2;
    if E2 > -DY then
    begin
      Dec(Err, DY);
      Inc(X1, SX);
    end;
    if E2 < DX then
    begin
      Inc(Err, DX);
      Inc(Y1, SY);
    end;
  end;
end;

begin
  VirtScr    := nil;
  VirtScrSeg := 0;
end.

{ ===========================================================================
  NOTE ON THE ROW TABLE

  PutPixel reads YOfs from DS:$E772 for the mode 13h path (y*320). Scene 1
  builds a *different* table for its Mode-X screen -- 800 entries of y*160 at
  DS:$9F1E-ish -- because the logical line there is 160 bytes per plane, not
  320. The two coexist; do not conflate them.
  =========================================================================== }
