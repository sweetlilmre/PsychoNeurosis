{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the VGA unit.

  This is segment 1436 in NEUROSIS_002_fpu.exe, transcribed in full -- every
  routine in the segment, in address order, nothing inferred. Part 002 has its
  own copy of this unit and it is NOT the same as part 001's VGA.PAS: the
  staging buffer is a single global here, the palette helpers take pointers,
  and the row table is 320-stride rather than the Mode-X one in P2ModeX.
  =========================================================================== }

unit P2VGA;

interface

const
  ScrWidth  = 320;
  ScrHeight = 200;
  VGASeg    = $A000;

var
  { DS:$A6B0 pointer, DS:$A6B4 its segment, DS:$A6B6 the row table. }
  Buffer    : Pointer;
  BufferSeg : Word;
  YOfs      : array[0..ScrHeight - 1] of Word;

procedure VirtScrAlloc;                              far;   { 1436:0006 }
procedure VirtScrFree;                               far;   { 1436:0033 }
procedure SetRGB(Col, R, G, B : Byte);               far;   { 1436:0048 }
procedure GetRGB(Col : Byte; var R, G, B : Byte);    far;   { 1436:0063 }
procedure SetPalette(P : Pointer);                   far;   { 1436:0083 }
procedure GetPalette(P : Pointer);                   far;   { 1436:009b }
procedure PaletteDim(P : Pointer);                   far;   { 1436:00b3 }
procedure PaletteFade(Pause : Word);                 far;   { 1436:00d6 }
procedure WaitRetrace;                               far;   { 1436:011a }
procedure CopyToPlane(SrcSeg, DestSeg : Word);       far;   { 1436:0128 }
procedure ClearSeg(Segment : Word; Colour : Byte);   far;   { 1436:0144 }
procedure BuildYOfs;                                        { 1436:015a }

implementation

uses Crt;      { 1436:010a calls Crt's Delay }

type
  TPalBuf = array[0..767] of Byte;

{ 1436:0006 -- GetMem(Buffer, 64000), copy the segment out to BufferSeg, then
  FillChar the whole thing with 0. }
procedure VirtScrAlloc;
begin
  GetMem(Buffer, 64000);
  BufferSeg := Seg(Buffer^);
  FillChar(Buffer^, 64000, 0);
end;

{ 1436:0033 -- FreeMem(Buffer, 64000). }
procedure VirtScrFree;
begin
  FreeMem(Buffer, 64000);
end;

{ 1436:0048 -- out $3C8 := Col, then $3C9 := R, G, B.
  RET 8, so four word slots: Col at BP+$C (the FIRST declared), R at BP+$A,
  G at BP+8, B at BP+6. }
procedure SetRGB(Col, R, G, B : Byte);
begin
  Port[$3C8] := Col;
  Port[$3C9] := R;
  Port[$3C9] := G;
  Port[$3C9] := B;
end;

{ 1436:0063 -- out $3C7 := Col, then three reads of $3C9 stored through the
  three var parameters. RET $E: Col at BP+$12, @R at BP+$E, @G at BP+$A,
  @B at BP+6. }
procedure GetRGB(Col : Byte; var R, G, B : Byte);
begin
  Port[$3C7] := Col;
  R := Port[$3C9];
  G := Port[$3C9];
  B := Port[$3C9];
end;

{ 1436:0083 -- out $3C8 := 0 then REP OUTSB 768 bytes from P^. }
procedure SetPalette(P : Pointer);
var
  Pal : ^TPalBuf;
  I   : Integer;
begin
  Pal := P;
  Port[$3C8] := 0;
  for I := 0 to 767 do
    Port[$3C9] := Pal^[I];
end;

{ 1436:009b -- out $3C7 := 0 then REP INSB 768 bytes into P^. }
procedure GetPalette(P : Pointer);
var
  Pal : ^TPalBuf;
  I   : Integer;
begin
  Pal := P;
  Port[$3C7] := 0;
  for I := 0 to 767 do
    Pal^[I] := Port[$3C9];
end;

{ 1436:00b3 -- walk 768 bytes; every NON-ZERO one is decremented in place and
  written back, zeroes are stepped over (the JZ at 1436:00c3 skips the STOSB
  and just bumps DI). One step of a fade held in a palette buffer. }
procedure PaletteDim(P : Pointer);
var
  Pal : ^TPalBuf;
  I   : Integer;
begin
  Pal := P;
  for I := 0 to 767 do
    if Pal^[I] <> 0 then Dec(Pal^[I]);
end;

{ 1436:00d6 -- read the live palette into a 768-byte local, then 64 passes of
  WaitRetrace / PaletteDim / SetPalette / Delay(Pause). The counter runs 0..$3F
  at 1436:010f. }
procedure PaletteFade(Pause : Word);
var
  Buf  : TPalBuf;
  Step : Byte;
begin
  GetPalette(@Buf);
  Step := 0;
  repeat
    WaitRetrace;
    PaletteDim(@Buf);
    SetPalette(@Buf);
    Delay(Pause);
    Inc(Step);
  until Step = $3F;
end;

{ 1436:011a -- wait out any retrace in progress, then wait for the next one to
  start. }
procedure WaitRetrace; assembler;
asm
  mov dx, $03DA
@@1:
  in  al, dx
  test al, 8
  jnz @@1
@@2:
  in  al, dx
  test al, 8
  jz  @@2
end;

{ 1436:0128 -- REP MOVSW of $7D00 words = 64,000 bytes, SI = DI = 0.
  DS comes from BP+8 and ES from BP+6, so the FIRST declared parameter is the
  SOURCE and the second the destination. }
procedure CopyToPlane(SrcSeg, DestSeg : Word); assembler;
asm
  push ds
  mov  ax, DestSeg
  mov  es, ax
  mov  ax, SrcSeg
  mov  ds, ax
  xor  si, si
  xor  di, di
  mov  cx, $7D00
  cld
  rep  movsw
  pop  ds
end;

{ 1436:0144 -- REP STOSW of $7D00 words with the colour doubled into AX.
  ES comes from BP+8 and the colour from BP+6, so the segment is declared
  first. }
procedure ClearSeg(Segment : Word; Colour : Byte); assembler;
asm
  mov  cx, $7D00
  mov  es, Segment
  xor  di, di
  mov  al, Colour
  mov  ah, al
  cld
  rep  stosw
end;

{ 1436:015a -- YOfs[I] := I * $140, for I = 0..$C7. Note this is the LINEAR
  320-byte stride, not the Mode-X one; P2ModeX keeps its own table. }
procedure BuildYOfs;
var
  Y : Integer;
begin
  for Y := 0 to ScrHeight - 1 do
    YOfs[Y] := Y * ScrWidth;
end;

{ 1436:017f -- the unit's initialisation calls BuildYOfs and nothing else. }
begin
  BuildYOfs;
end.
