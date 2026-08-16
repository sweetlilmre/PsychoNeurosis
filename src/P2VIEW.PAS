{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the 320x400 unit.

  Segment 140c in NEUROSIS_002_fpu.exe, transcribed in full -- all seven
  routines and the unit initialisation, nothing inferred.

  This is the OTHER video unit in part 002, and it is nothing like P2ModeX.
  Scene 2 runs unchained 320 x 400 with two pages stacked in the same 64K:

      page 0   offset $0000        DS:$A696
      page 1   offset $4B00        DS:$A698     ($4B00 = 19,200 = 80 * 240)
      current  DS:$A69A            what Plot and FillRect write through

  80 bytes per plane-row, four planes, so 320 pixels across; the CRTC table
  below turns off the 200-line double scan and stretches the vertical timing
  to 400 lines, which is what makes room for two 320x200 pages.
  =========================================================================== }

unit P2View;

interface

const
  PlaneWidth = 80;         { bytes per plane per row }
  Page0Base  = $0000;      { 140c:01cf }
  Page1Base  = $4B00;      { 140c:01d2 }
  CrtcCount  = 10;         { DS:$0CEE, and the table below has ten entries }

type
  TCrtcTable = array[0..CrtcCount - 1] of Word;

var
  { DS:$A696, $A698, $A69A. }
  PageBase : array[0..1] of Word;
  WritePage : Word;
  { DS:$0CEC -- which of the two pages is being drawn into. Initialised data;
    the compiled-in value is 1. The renderers toggle it after every flip. }
  PageIndex : Integer;
  { DS:$A69C -- SetMode400 fills this then hands it to SetMode. }
  Crtc : TCrtcTable;

procedure FillCrtcTable(var T : TCrtcTable);                        { 140c:0000 }
procedure SetMode(var T : TCrtcTable);                              { 140c:0045 }
procedure SetMode400;                                        far;   { 140c:009c }
procedure Plot(X, Y : Integer; Colour : Byte);               far;   { 140c:00b1 }
procedure FlipPage(StartAddr : Word);                        far;   { 140c:00f4 }
procedure FillRect(X1, Y1, X2, Y2 : Integer;
                   Page : Word; Colour : Byte);              far;   { 140c:011e }
procedure SetColour(Col, R, G, B : Byte);                    far;   { 140c:01af }

{ The two nibble masks the planar span writers need. Scene 2's triangle filler
  at 108b:0461 reads its own copies from DS:$0676 and DS:$067A, which hold the
  same four bytes each as this unit's tables at DS:$0CF0 and DS:$0CF4. }
function LeftMaskOf(X : Integer) : Byte;
function RightMaskOf(X : Integer) : Byte;

implementation

const
  { 140c:014a / 140c:0155 -- DS:$0CF0 and DS:$0CF4, initialised data. }
  LeftMask  : array[0..3] of Byte = ($0F, $0E, $0C, $08);
  RightMask : array[0..3] of Byte = ($0F, $01, $03, $07);

function LeftMaskOf(X : Integer) : Byte;
begin
  LeftMaskOf := LeftMask[X and 3];
end;

function RightMaskOf(X : Integer) : Byte;
begin
  RightMaskOf := RightMask[X and 3];
end;

{ --------------------------------------------------------------------------
  140c:0000 -- ten CRTC index/value pairs written out longhand, one MOV each.
  As index:value they are the standard 320x400 unchained set:

      $06 := $0D    vertical total
      $07 := $3E    overflow
      $09 := $41    maximum scan line -- bit 7 clear, so NO double scan
      $10 := $EA    vertical retrace start
      $11 := $AC    vertical retrace end
      $12 := $DF    vertical display end
      $14 := $00    underline location -- dword mode off
      $15 := $E7    start vertical blank
      $16 := $06    end vertical blank
      $17 := $E3    mode control -- byte mode
  -------------------------------------------------------------------------- }
procedure FillCrtcTable(var T : TCrtcTable);
begin
  T[0] := $0D06;  T[1] := $3E07;  T[2] := $4109;  T[3] := $EA10;
  T[4] := $AC11;  T[5] := $DF12;  T[6] := $0014;  T[7] := $E715;
  T[8] := $0616;  T[9] := $E317;
end;

{ --------------------------------------------------------------------------
  140c:0045

      INT $10, AX = $0013
      SEQ  $04 := $06          chain-4 off and odd/even off in one write
      SEQ  $00 := $01          synchronous reset
      MISC ($3C2) := $E3       clocks and polarity for 400 lines
      SEQ  $00 := $03          end reset
      CRTC $11 := v and $7F    unprotect registers 0..7
      write the ten table words to $3D4    count from DS:$0CEE
      SEQ  $02 := $0F          all planes
      clear $A000, $8000 words = 64K

  Note it never puts the CRTC write protect back.
  -------------------------------------------------------------------------- }
procedure SetMode(var T : TCrtcTable);
var
  I : Integer;
begin
  asm
    mov ax, $0013
    int $10
    mov dx, $03C4
    mov ax, $0604
    out dx, ax
    mov ax, $0100
    out dx, ax
    mov dx, $03C2
    mov al, $E3
    out dx, al
    mov dx, $03C4
    mov ax, $0300
    out dx, ax
    mov dx, $03D4
    mov al, $11
    out dx, al
    inc dx
    in  al, dx
    and al, $7F
    out dx, al
  end;

  for I := 0 to CrtcCount - 1 do
    PortW[$3D4] := T[I];

  asm
    mov dx, $03C4
    mov ax, $0F02
    out dx, ax
    mov ax, $A000
    mov es, ax
    sub di, di
    sub ax, ax
    mov cx, $8000
    cld
    rep stosw
  end;
end;

{ 140c:009c -- fill the table at DS:$A69C, then set the mode from it. }
procedure SetMode400;
begin
  FillCrtcTable(Crtc);
  SetMode(Crtc);
end;

{ --------------------------------------------------------------------------
  140c:00b1 -- Plot(X, Y, Colour)

      offset := Y * 80 + (X shr 2) + WritePage
      Map Mask := 1 shl (X and 3)
      $A000:[offset] := Colour

  The Y * 80 is done as (Y shl 4) + (Y shl 6). RETF 6, so X is at BP+$A (the
  first declared), Y at BP+8, Colour at BP+6.
  -------------------------------------------------------------------------- }
procedure Plot(X, Y : Integer; Colour : Byte);
begin
  PortW[$3C4] := ((Word(1) shl (X and 3)) shl 8) or $02;
  Mem[$A000 : Word(Y) * PlaneWidth + (Word(X) shr 2) + WritePage] := Colour;
end;

{ --------------------------------------------------------------------------
  140c:00f4 -- FlipPage(StartAddr)

      wait while ($3DA and 1) <> 0        out of horizontal retrace
      CRTC $0D := lo(StartAddr)
      CRTC $0C := hi(StartAddr)
      wait while ($3DA and 8)  = 0        into vertical retrace

  Low byte first, then high, and both BEFORE the vertical retrace wait -- the
  wait afterwards is what stops the caller running ahead, not what protects
  the write.
  -------------------------------------------------------------------------- }
procedure FlipPage(StartAddr : Word); assembler;
asm
  mov bl, $0D
  mov bh, byte ptr StartAddr
  mov cl, $0C
  mov ch, byte ptr StartAddr+1
  mov dx, $03DA
@@1:
  in  al, dx
  test al, 1
  jnz @@1
  mov dx, $03D4
  mov ax, bx
  out dx, ax
  mov ax, cx
  out dx, ax
  mov dx, $03DA
@@2:
  in  al, dx
  test al, 8
  jz  @@2
end;

{ --------------------------------------------------------------------------
  140c:011e -- FillRect(X1, Y1, X2, Y2, Page, Colour)

  A planar rectangle fill. The left and right edge bytes are written with
  partial Map Masks out of the two tables above, and the span between them
  with mask $0F, so a whole four-pixel column goes down in one STOSB.

      DI := Y1 * 80 + (X1 shr 2) + Page
      BH := LeftMask[X1 and 3]
      BL := RightMask[X2 and 3]
      if X2 <= X1 then exit
      CX := ((X2 - 1) - (X1 and $FFFC)) shr 2         middle byte count
      if CX = 0 then BH := BH and BL                  one byte wide
      SI := Y2 - Y1 ; if SI <= 0 then exit
      per row: left byte, middle run at mask $0F, right byte, DI += 80 - CX - 1

  RETF $C, six words. Highest first: X1 at BP+$10, Y1 at BP+$E, X2 at BP+$C,
  Y2 at BP+$A, Page at BP+8, Colour at BP+6.
  -------------------------------------------------------------------------- }
procedure FillRect(X1, Y1, X2, Y2 : Integer; Page : Word; Colour : Byte);
var
  D       : Word;
  LM, RM  : Byte;
  Mid     : Integer;
  Rows, R : Integer;
  I       : Integer;
begin
  if X2 <= X1 then Exit;
  Rows := Y2 - Y1;
  if Rows <= 0 then Exit;

  D   := Word(Y1) * PlaneWidth + (Word(X1) shr 2) + Page;
  LM  := LeftMask[X1 and 3];
  RM  := RightMask[X2 and 3];
  Mid := ((X2 - 1) - (X1 and $FFFC)) shr 2;
  if Mid = 0 then LM := LM and RM;

  for R := 1 to Rows do
  begin
    Port[$3C4] := 2;
    Port[$3C5] := LM;
    Mem[$A000 : D] := Colour;

    if Mid > 0 then
    begin
      Port[$3C5] := $0F;
      for I := 1 to Mid - 1 do
        Mem[$A000 : D + I] := Colour;
      Port[$3C5] := RM;
      Mem[$A000 : D + Mid] := Colour;
    end;

    Inc(D, PlaneWidth);
  end;
end;

{ 140c:01af -- out $3C8 := Col, then $3C9 := R, G, B. RETF 8, so Col is at
  BP+$C and is declared first. Identical in shape to P2VGA's SetRGB; part 002
  simply has one in each unit. }
procedure SetColour(Col, R, G, B : Byte);
begin
  Port[$3C8] := Col;
  Port[$3C9] := R;
  Port[$3C9] := G;
  Port[$3C9] := B;
end;

{ 140c:01ca -- the unit's initialisation. }
begin
  PageBase[0] := Page0Base;
  PageBase[1] := Page1Base;
  WritePage   := PageBase[0];
  PageIndex   := 1;                   { DS:$0CEC, the compiled-in value }
end.
