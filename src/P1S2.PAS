{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, scene 2, "ASPHYXIA PRESENTS"

  Split out of PART1_INTRO.PAS so this scene can be compiled and run on its
  own. Markers: [transcribed] read out of the binary, [inferred] implied by
  its call sites, [stub] signature only.
  =========================================================================== }

unit P1S2;

{$G+}   { 286: Title_Load 1082:0000 opens ENTER $182; every framed routine
          in the segment does. }

{$N+}   { 80x87 CODE ON. The original's segment 1082 carries 10 emulator
          traps -- INT $34..$3E, which is how an 80x87 instruction ships
          under $E+ -- and this unit had no N directive at all, so it took
          the command line's default and emitted NONE. $N- generates no
          80x87 instructions and therefore no traps either: floating point
          becomes far calls into the software six-byte-Real library, so a
          trap is positive evidence of $N+ rather than against it. Counted
          in 1082:0128's clipped blit region. Nothing here gains a coprocessor --
          Turbo Pascal's emulator ran these in 1994 and runs them now. }

interface

procedure Scene2;

implementation

uses VGA, Crt, DemoVT;

const
  { 1082:00BB and 1082:05BB both pass 10 -- the delay between fade frames. }
  FadePause   = 10;
  CometFrames = 10;
  CometW      = 65;
  CometH      = 48;
  CometSize   = CometW * CometH;   { 3120 -- the stride in the loaded buffer }
  RevealOfs   = 614;               { $266 -- where DrawRevealed lands }
  FontBias    = 8209;              { = 32*256 + 17, see DrawChar }

type
  TWorkBuf   = array[0..5199] of Byte;
  TCometBank = array[0..CometFrames * CometSize - 1] of Byte;
  TFontBuf   = array[0..15103] of Byte;

var
  { All four are HEAP blocks in the original -- Title_Load GetMem's 5,200,
    64,000, 31,200 and 15,104 bytes in that order. }
  WorkBuf     : ^TWorkBuf;      { DS:$56CE }
  Backdrop    : Pointer;        { DS:$56C4, segment kept at DS:$56C8 }
  BackdropSeg : Word;
  CometBank   : ^TCometBank;    { DS:$56C0 -- 10 frames of 65 x 48 }
  FontBuf     : ^TFontBuf;      { DS:$56CA -- 59 glyphs of 16 x 16 }

{ --------------------------------------------------------------------------
  Title_Load (1082:0000)

  This was missing entirely, which is why the scene hung: WorkBuf was nil and
  BlurBuffer WRITES through it -- 3,900 bytes straight over the interrupt
  vector table at 0000:xxxx.

  NEUROSIS.DAT $00FD00, 111,072 bytes in four reads:

      768     palette
      31,200  the comet, 10 frames of 65 x 48 (10 * 3120)
      64,000  the backdrop screen
      15,104  the font, 59 glyphs of 16 x 16 (59 * 256)

  Between the screen read and the font read it blanks all 256 DAC entries,
  shows the screen, FADES UP to the palette it just loaded, and only then
  lays a RED ramp over entries 1..121 (R := I div 2) and shows it again.

  THE FADE-UP IS 1491:0215, a 64-step walk with Delay(10) between frames.
  An earlier version of this file did a plain SetPalette here, so the
  backdrop appeared instantly instead of coming up out of black. The
  matching fade-DOWN at the end of the scene was missing too -- see Scene2.

  The font block is GetMem'd LATE, after the fade, which is the original's
  order (1082:03A0) and is why it is not with the other three.
  -------------------------------------------------------------------------- }
procedure Load;
var
  F : file;
  I : Integer;
begin
  GetMem(WorkBuf,   SizeOf(TWorkBuf));        { 1082:0000 }
  GetMem(Backdrop,  64000);
  BackdropSeg := Seg(Backdrop^);
  GetMem(CometBank, SizeOf(TCometBank));

  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $00FD00);

  BlockRead(F, Palette, 768);
  BlockRead(F, CometBank^, SizeOf(TCometBank));
  ClearScreen($A000, 0);
  BlockRead(F, Mem[VirtScrSeg : 0], 64000);

  { Blank, show, then fade UP to the palette just loaded. Only after that
    does the red ramp go over entries 1..121.

    An earlier version blanked the DAC and set nothing but the ramp, which
    left colours 122..255 BLACK. Most of the backdrop is in that range, so the
    scene ran correctly and displayed nothing. }
  for I := 0 to 255 do SetRGB(I, 0, 0, 0);        { 1082:0086 }
  CopyScreen(VirtScrSeg, $A000);                  { 1082:00B0 }
  PaletteFadeUp(@Palette, FadePause);             { 1082:00BB -- 1491:0215 }
  for I := 1 to 121 do SetRGB(I, I div 2, 0, 0);  { 1082:00C6, the red ramp }
  CopyScreen(VirtScrSeg, $A000);
  CopyScreen(VirtScrSeg, BackdropSeg);            { keep a clean copy }

  GetMem(FontBuf, SizeOf(TFontBuf));              { 1082:03A0 -- late }
  BlockRead(F, FontBuf^, SizeOf(TFontBuf));
  Close(F);
end;

procedure Unload;
begin
  FreeMem(FontBuf,   SizeOf(TFontBuf));
  FreeMem(CometBank, SizeOf(TCometBank));
  FreeMem(Backdrop,  64000);
  FreeMem(WorkBuf,   SizeOf(TWorkBuf));
end;

{ [transcribed] 1082:01d0 -- redraws the characters revealed so far.

  A 150-row by 26-column masked blit out of the working buffer at DS:$56CE.
  The mask is a THRESHOLD, not a key: source bytes of 20 or less are skipped,
  so the anti-aliased edges of the glyphs drop out and only the solid core is
  copied. }
procedure DrawRevealed;
var
  Row, Col : Integer;
  V        : Byte;
  D, P     : Word;
begin
  { The destination stride is 318, NOT 320: after 26 columns the original does
    ADD DI,$124 (292), and DI is already 26 further on, so each row starts two
    bytes EARLIER than the one above. Over 150 rows that is a 300-pixel lean --
    the revealed block is deliberately SHEARED, not upright.

    Source and destination both advance on every pixel; only the STORE is
    conditional, on the byte exceeding 20. }
  P := 0;
  D := RevealOfs;
  for Row := 1 to 150 do
  begin
    for Col := 1 to 26 do
    begin
      V := WorkBuf^[P];
      if V > 20 then Mem[VirtScrSeg : D] := V;
      Inc(P);
      Inc(D);
    end;
    Inc(D, 292);            { 26 + 292 = 318 }
  end;
end;

{ [stub] 1082:0200 -- draws the character currently animating. Phase is
  Trunc(Phase) from ShowWord: one of 1, 3, 5, 7, 9, 11, 13, 15. }
{ --------------------------------------------------------------------------
  1082:0200 -- draw one character into the work buffer.

  It does TWO font rows per call, Phase and Phase + 1, which is what makes the
  glyph unroll two scanlines at a time as Phase steps 1, 3, 5 .. 15.

  The font is 16 x 16: 256 bytes per glyph, 16 per row -- which is where the
  15,104-byte read comes from (59 * 256). The work buffer is 26 bytes per row,
  the same 26 that DrawRevealed blits and BlurBuffer smears.

      if Font[Ord(Ch)*256 + Phase*16 + C - 8209] <> 0 then
        Work[((Index-1)*17 + Phase + 1) * 26 + C + 5 - 27] := 121

  The -8209 is not decoration: the font holds 59 glyphs, so a raw Ord('A')*256
  would run 1,500 bytes off the end of the 15,104-byte buffer. 8209 = 32*256
  + 17, i.e. the table starts at space and each glyph is 17 bytes short of a
  full 256 -- which is what brings 'A'..'Z' back inside it.

  Every lit pixel is written as colour $79 = 121; there is no shading here,
  the gradient comes from BlurBuffer afterwards.
  -------------------------------------------------------------------------- }
procedure DrawChar(Ch : Char; Phase, Index : Integer);
var
  C, Row, Src : Integer;
begin
  for C := 1 to 16 do
  begin
    Src := Ord(Ch) * 256 + Phase * 16 + C - FontBias;
    if FontBuf^[Src] <> 0 then
    begin
      Row := (Index - 1) * 17 + Phase + 1;
      WorkBuf^[Row * 26 + C + 5 - 27] := 121;
    end;
  end;
  for C := 1 to 16 do
  begin
    Src := Ord(Ch) * 256 + (Phase + 1) * 16 + C - FontBias;
    if FontBuf^[Src] <> 0 then
    begin
      Row := (Index - 1) * 17 + Phase + 2;
      WorkBuf^[Row * 26 + C + 5 - 27] := 121;
    end;
  end;
end;

{ --------------------------------------------------------------------------
  1082:02ba -- NOT an outro. It is a BLUR.

  3,900 iterations of a diagonal four-neighbour average over the working
  buffer:

      P[0] := (P[-27] + P[-25] + P[+25] + P[+27]) shr 2

  With a row width of 26 those offsets are the four DIAGONAL neighbours, and
  3,900 is exactly 26 x 150 -- the same buffer DrawRevealed reads. Running it
  100 times is what dissolves the finished word into a smear rather than
  cutting away from it.

  The earlier name and body were guesses from the call site alone.
  -------------------------------------------------------------------------- }
procedure BlurBuffer;
var
  I : Integer;
begin
  for I := 27 to 27 + 3899 do
    WorkBuf^[I] := (LongInt(WorkBuf^[I - 27]) + WorkBuf^[I - 25] +
                    WorkBuf^[I + 25] + WorkBuf^[I + 27]) shr 2;
end;

{ ===========================================================================
  Scene 2 -- "ASPHYXIA PRESENTS"                  Demo_Scene2  1082:056f
  =========================================================================== }


{ --------------------------------------------------------------------------
  Sprite_BlitClipped (1082:0128)

  A 65x48 blit with transparency (zero bytes are skipped) and clipping
  against four bounds held at DS:$04/$06 (x) and DS:$08/$0A (y). The clip is
  done by adjusting the start pointer and the row/column counts before the
  copy loop, not per pixel.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  Sprite_BlitClipped (1082:0128) -- the comet.

  A 65 x 48 transparent blit, clipped against four bounds in DGROUP:

      DS:$0004  ClipX1 = 0      DS:$0006  ClipX2 = 319
      DS:$0008  ClipY1 = 0      DS:$000A  ClipY2 = 199

  The clip is done by adjusting the START POINTER and the row and column
  COUNTS before the copy, never per pixel: a top clip advances the source by
  (rows * 65), a left clip advances it by the column count and shortens the
  row, and the leftover is added back between rows. Zero bytes are skipped.

  This was left as a comment on the first pass, which is why the scene drew
  nothing at all.
  -------------------------------------------------------------------------- }
const
  { TYPED, so they live in DGROUP where the original reads them from. The four
    addresses recorded above -- DS:$0004, $0006, $0008, $000A -- are the whole
    argument: an untyped const folds into the instruction and occupies no data
    at all, and part 001's initialised region opened eight bytes short because
    of it. P1S4's four bounds two lines further up DGROUP were already typed for
    exactly this reason. }
  ClipX1 : Integer = 0;      { DS:$0004 }
  ClipX2 : Integer = 319;    { DS:$0006 }
  ClipY1 : Integer = 0;      { DS:$0008 }
  ClipY2 : Integer = 199;    { DS:$000A }

procedure BlitClipped(Src : Pointer; X, Y : Integer; Segment : Word);
var
  P            : ^Byte;
  Rows, Cols   : Integer;
  SkipL, SkipR : Integer;
  Row, Col     : Integer;
  D            : Word;
  V            : Byte;
begin
  P     := Src;
  Rows  := CometH;
  Cols  := CometW;
  SkipL := 0;
  SkipR := 0;

  { --- vertical --- }
  if ClipY1 - Y > 0 then
  begin
    if ClipY1 - Y >= Rows then Exit;         { entirely above }
    Dec(Rows, ClipY1 - Y);
    Inc(LongInt(P), LongInt(ClipY1 - Y) * CometW);
    Y := ClipY1;
  end;
  if ClipY2 - Y <= 0 then Exit;              { entirely below }
  if ClipY2 - Y < Rows then Rows := ClipY2 - Y + 1;

  { --- horizontal --- }
  if ClipX1 - X > 0 then
  begin
    if ClipX1 - X >= Cols then Exit;
    SkipL := ClipX1 - X;
    Dec(Cols, SkipL);
    X := ClipX1;
  end;
  if ClipX2 - X <= 0 then Exit;
  if ClipX2 - X < Cols then
  begin
    SkipR := Cols - (ClipX2 - X);
    Cols  := ClipX2 - X;
  end;

  for Row := 0 to Rows - 1 do
  begin
    Inc(LongInt(P), SkipL);
    D := (Y + Row) * ScrWidth + X;
    for Col := 0 to Cols - 1 do
    begin
      V := P^;
      if V <> 0 then Mem[Segment : D] := V;
      Inc(LongInt(P));
      Inc(D);
    end;
    Inc(LongInt(P), SkipR);
  end;
end;

{ --------------------------------------------------------------------------
  Title_ShowWord (1082:02fd)

  Called twice -- once with 'ASPHYXIA' (1082:$055E) and once with
  'PRESENTS' (1082:$0567). A counter runs from 80 down to -18 while a comet
  sprite flies across; as it passes, characters are revealed one at a time.
  When the counter reaches -18 a 100-frame outro plays.

  ASSETS  NEUROSIS.DAT $00FD00, 111,072 bytes:
            assets/part001/intro_palette.pal    768 B
            assets/part001/comet0.png .. comet9.png
                                      10 frames of 65x48 -- a flaming comet
            assets/part001/intro_backdrop.png   64,000 B
            assets/part001/00FD00_03.bin        15,104 B = a 59-character
                                      16x16 font (59 x 256), drawn two
                                      rows at a time by 1082:0200
          A 5,200-byte working buffer is allocated separately.
  -------------------------------------------------------------------------- }
procedure ShowWord(S : String);
{ Read instruction by instruction off 1082:02fd. Three of the four state
  variables are Borland Reals held in the stack frame, and the four constants
  are FP operands in the code segment -- decoded with tools/fpconst.py:

      CS:$02E7  single  2.0     added to Phase AND to CometX
      CS:$02EB  single 15.0     Phase wrap
      CS:$02EF  ext80   0.3     added to Frame
      CS:$02F9  single 10.0     Frame wrap

  and the initial Real48 values in the frame are CometPos = -48.0, Frame = 1.0,
  Phase = 1.0. Nothing here is fixed point -- this really is the FP scene. }
var
  CometPos, Frame, Phase : Real;
  Count, CharIdx       : Integer;
begin
  CometPos := -48.0;
  Frame   :=   1.0;
  Phase   :=   1.0;
  CharIdx :=  -1;

  { 1082:0354 -- FillChar(WorkBuf, 5200, 0). ShowWord clears the work buffer
    on EVERY call, which is what stops the first word's blurred remains (and,
    on the first call, raw heap garbage) showing through. DrawRevealed stores
    any byte above 20, so without this there is a permanent stripe. }
  FillChar(WorkBuf^, SizeOf(TWorkBuf), 0);

  Count := 80;

  repeat
    CopyScreen(BackdropSeg, VirtScrSeg);
    DrawRevealed;                    { 1082:01d0 -- the characters so far }

    { The comet. The push order at 1082:03a6 settles which is which:
      Count*4 goes to [BP+8] = X and Trunc(CometPos) to [BP+6] = Y. So the
      COUNTER drives X and the accumulating Real drives Y -- the opposite of
      an earlier reading.

          X = Count * 4      320 down to -72     right to left
          Y = CometPos       -48  up to  148     top to bottom

      so it sweeps from the top right down to the bottom left. The bank index
      is (Frame - 1), which the original writes as +$F3D0, i.e. -CometSize. }
    BlitClipped(@CometBank^[(Trunc(Frame) - 1) * CometSize],
                Count * 4, Trunc(CometPos), VirtScrSeg);

    { Only the character currently animating is drawn here; Trunc(Phase) is
      its animation step, one of 1, 3, 5, 7, 9, 11, 13, 15. }
    if (CharIdx > 0) and (CharIdx <= Length(S)) then
      DrawChar(S[CharIdx], Trunc(Phase), CharIdx);

    Phase := Phase + 2.0;
    if Phase > 15.0 then
    begin
      Phase := 1.0;
      Inc(CharIdx);                  { eight frames per character }
    end;

    CopyScreen(VirtScrSeg, $A000);

    Frame := Frame + 0.3;            { ~31 frames for the 10-frame cycle }
    if Frame > 10.0 then Frame := 1.0;

    CometPos := CometPos + 2.0;

    Dec(Count);
  until KeyPressed or (Count = -18);

  { --------------------------------------------------------------------
    The outro, 1082:051a..054a -- 100 frames, and it REDRAWS every one:

        CopyScreen(Backdrop -> Virt)
        DrawRevealed                    (* the work buffer as it stands *)
        BlurBuffer                      (* 1082:02ba, one pass *)
        CopyScreen(Virt -> $A000)

    That is the fade. BlurBuffer alone changes nothing on screen; it is the
    re-blit each frame that makes the smear visible, and because DrawRevealed
    only stores bytes above 20, the letters stop being drawn at all once the
    blur has pulled them under that threshold. Running the 100 passes without
    redrawing -- which is what an earlier version did -- leaves the finished
    word sitting there and then cuts away.
    -------------------------------------------------------------------- }
  for Count := 1 to 100 do
  begin
    CopyScreen(BackdropSeg, VirtScrSeg);
    DrawRevealed;
    BlurBuffer;
    CopyScreen(VirtScrSeg, $A000);
  end;
end;


procedure Scene2;
begin
  Load;                                   { 1082:0000 }
  ShowWord('ASPHYXIA');                   { 1082:0592 }
  ShowWord('PRESENTS');                   { 1082:059D }
  PaletteFadeOut(FadePause);              { 1082:05BB -- 1491:0330 }
  Unload;                                 { 1082:05C1, four FreeMems }
end;

end.
