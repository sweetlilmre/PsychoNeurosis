{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the Mode-X unit.

  Segment 107c in NEUROSIS_002_fpu.exe, transcribed in full -- all four
  routines and the unit initialisation, nothing inferred.

  WHAT MAKES THIS UNIT UNUSUAL

  It is not 320x200 Mode X. The CRTC Offset register ($13) is loaded from the
  byte at DS:$0002, and Demo_Scene1 sets that to $A0 = 160 before calling in.
  The Offset register counts in units of two bytes per plane, so a logical
  scanline is 320 bytes PER PLANE -- four planes of 320 bytes, which is

      320 * 4 = 1280 pixels wide

  and the row table is built to match: 800 entries of LogicalWidth * I * 2 =
  320 * I. Video memory holds 65,536 bytes per plane, so about 204 of those
  rows actually fit and the table wraps in 16-bit arithmetic beyond that; the
  scene only ever uses row 0.

  That is what the scene pans across: one 1280 x 200 image spread over the
  four planes, 64,000 bytes each.
  =========================================================================== }

unit P2ModeX;

interface

const
  RowCount = 800;                       { $320 -- the table 107c:0000 fills }

var
  { DS:$0002 -- the CRTC Offset value, and the multiplier BuildRowTable uses.
    It is INITIALISED DATA: the compiled-in value is $50, which is a 640-pixel
    canvas. Demo_Scene1 stores $A0 over it (1008:0727) before calling in, which
    is what makes the canvas 1280 wide for that scene. It has to be a variable,
    not a constant, because the compiled-in default is the other value. }
  LogicalWidth : Byte;
  { DS:$4B08 -- RowOfs[I] = LogicalWidth * I * 2. }
  RowOfs : array[0..RowCount - 1] of Word;

procedure BuildRowTable;                       far;   { 107c:0000 }
procedure ShowFrame(X, Row : Integer);         far;   { 107c:002a }
procedure SetModeX;                            far;   { 107c:006d }
procedure SelectPlane(P : Byte);               far;   { 107c:00ca }

implementation

{ --------------------------------------------------------------------------
  107c:0000

      for I := 0 to $31F do
        RowOfs[I] := (LogicalWidth * I) shl 1

  The multiply is an 8-bit MUL of DS:$0002 by the loop counter, then SHL 1.
  Sixteen bit, so it wraps past row 204; that is the original's behaviour.
  -------------------------------------------------------------------------- }
procedure BuildRowTable;
var
  I : Integer;
begin
  for I := 0 to RowCount - 1 do
    RowOfs[I] := Word(LogicalWidth) * Word(I) shl 1;
end;

{ --------------------------------------------------------------------------
  107c:002a -- point the CRTC at (X, Row) and pan.

      BX := RowOfs[Row] + (X shr 2)
      CRTC $0C := hi(BX)                start address high
      CRTC $0D := lo(BX)                start address low
      wait for the START of vertical retrace
      ATC  $13 := (X and 3) * 2         horizontal pixel panning
      ATC      := $20                   re-enable the palette

  PARAMETER ORDER. RET 4, so two words: BP+8 and BP+6. BP+8 is the higher, so
  it is the FIRST declared -- and BP+8 is the one used as X (it is shifted
  right by two for the byte offset and masked with 3 for the pan). BP+6 is the
  row. Scene1_Run calls it as (I, 0) while I sweeps 0..960, which is the pan.

  Note the start address is written BEFORE the wait, not after. That is what
  the code does.
  -------------------------------------------------------------------------- }
procedure ShowFrame(X, Row : Integer);
var
  B : Word;
begin
  B := RowOfs[Row] + Word(X) shr 2;
  PortW[$3D4] := (B and $FF00) or $0C;
  PortW[$3D4] := ((B and $00FF) shl 8) or $0D;

  while (Port[$3DA] and 8) <> 0 do ;
  while (Port[$3DA] and 8) =  0 do ;

  Port[$3C0] := $13;
  Port[$3C0] := (X and 3) shl 1;
  Port[$3C0] := $20;
end;

{ --------------------------------------------------------------------------
  107c:006d -- unchained 256-colour mode with a wide logical line.

      INT $10, AX = $0013
      SEQ  $04 := (v and $F7) or $04      Chain-4 off, odd/even off
      GC   $05 := v and $EF               shift/odd-even off
      GC   $06 := v and $FD               chain odd/even off
      SEQ  $02 := $0F                     all four planes enabled
      clear $A000 for $8000 words         = 65,536 bytes
      CRTC $14 := v and $BF               dword mode off
      CRTC $17 := v or $40                byte mode on
      CRTC $13 := DS:$0002                the logical line width
  -------------------------------------------------------------------------- }
procedure SetModeX; assembler;
asm
  mov  ax, $0013
  int  $10

  mov  dx, $03C4
  mov  al, $04
  out  dx, al
  inc  dx
  in   al, dx
  and  al, $F7
  or   al, $04
  out  dx, al

  mov  dx, $03CE
  mov  al, $05
  out  dx, al
  inc  dx
  in   al, dx
  and  al, $EF
  out  dx, al

  dec  dx
  mov  al, $06
  out  dx, al
  inc  dx
  in   al, dx
  and  al, $FD
  out  dx, al

  mov  dx, $03C4
  mov  ax, $0F02
  out  dx, ax

  mov  ax, $A000
  mov  es, ax
  sub  di, di
  mov  ax, 0
  mov  cx, $8000
  cld
  rep  stosw

  mov  dx, $03D4
  mov  al, $14
  out  dx, al
  inc  dx
  in   al, dx
  and  al, $BF
  out  dx, al

  dec  dx
  mov  al, $17
  out  dx, al
  inc  dx
  in   al, dx
  or   al, $40
  out  dx, al

  mov  dx, $03D4
  mov  al, $13
  out  dx, al
  inc  dx
  mov  al, [LogicalWidth]
  out  dx, al
end;

{ 107c:00ca -- Map Mask := 1 shl P, written as a single word OUT to $3C4. }
procedure SelectPlane(P : Byte);
begin
  PortW[$3C4] := ((Word(1) shl (P and 3)) shl 8) or $02;
end;

{ 107c:00de -- the unit's initialisation calls BuildRowTable.

  DS:$0002 is initialised data, so it already holds $50 when the table is
  first built; a scene that wants a different width stores its own value and
  calls BuildRowTable again, which is what Demo_Scene1 does through SetModeX. }
begin
  LogicalWidth := $50;
  BuildRowTable;
end.
