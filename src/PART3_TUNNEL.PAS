{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 1
  Reconstructed from NEUROSIS_003_fpu.exe.  The tunnel / concentric-ring scene.

  HOW IT WORKS
    A 640x400 tunnel image is precomputed and stored in NEUROSIS.DAT as four
    64000-byte Mode-X planes. It is loaded once, straight into VGA memory --
    there is no per-frame pixel work at all.

    The illusion comes from two things happening every frame:
      1. The visible 320x200 window is panned around the 640x400 image along a
         circular path (CRTC start address + Attribute Controller pixel pan).
      2. The 225-entry palette is rotated, both within each 15-colour band and
         by whole bands, so the rings appear to flow inward.

    That is why the source artwork looks like static concentric rings: all the
    motion is palette animation plus hardware panning.

  ADDRESS MAP (part 003)
    Tunnel_UploadPalette      1015:0000      Tunnel_InitTables     1015:0654
    Tunnel_RotateBandsCoarse  1015:004d      VGA_SetDisplayStart   1015:06b0
    Tunnel_RotateBandsFine    1015:017f      Tunnel_UpdateMotion   1015:075a
    Demo_Scene1               1015:098d      Tunnel_LoadTexture    1015:08a7
    VGA_SetMode               1192:002a      VGA_SelectPlane       1192:0087
    VGA_WaitRetrace           12f8:009f      VGA_CopyToPlane       12f8:00ad

  CONFIDENCE
    Structure, port programming, table contents, texture offset/size and the
    initial angle/radius are all read directly out of the binary and each was
    cross-checked (see notes at the end). Items marked (?) are inferred.
  =========================================================================== }

unit Part3Tunnel;
{$A-}   { DATA ALIGNMENT OFF, and the palette's own recorded addresses say so:
          the three 225-byte tables sit at DS:$0002, $00E3 and $01C4 in the
          original -- ODD offsets, one after another with no gap. Under TP7's
          $A+ default each odd-sized typed constant gets a pad byte, which put
          Blue at $01C6 and everything after it two bytes out for the whole
          part: CollapseFrames, the sine table, all six shape slots. }

{$G+}   { 286: Demo_Scene1 1015:098d opens ENTER 2; every framed routine
          in 1015 does. }

{$N+}   { 80x87 CODE ON. The original's segment 1015 carries 18 emulator
          traps -- INT $34..$3E, which is how an 80x87 instruction ships
          under $E+ -- and this unit had no N directive at all, so it took
          the command line's default and emitted NONE. $N- generates no
          80x87 instructions and therefore no traps either: floating point
          becomes far calls into the software six-byte-Real library, so a
          trap is positive evidence of $N+ rather than against it. Counted
          in 1015, which also holds Angle and Radius as Reals. Nothing here gains a coprocessor --
          Turbo Pascal's emulator ran these in 1994 and runs them now. }

interface

procedure Scene1;

implementation

uses VGA, Crt, DemoVT, ModeX;   { ModeX for LogicalWidth -- see SetDisplayStart }

const
  { Mode-X logical screen. CRTC Offset register is programmed to 80, i.e.
    80*8 = 640 pixels per logical line; 64000 bytes per plane / 160 bytes per
    plane-line = 400 lines. Hence 640x400, of which 320x200 is displayed. }
  LogWidth    = 640;
  LogHeight   = 400;
  BytesPerRow = LogWidth div 4;        { 160 -- per plane }
  CrtcOffset  = LogWidth div 8;        { 80  -- value written to CRTC $13 }

  ViewWidth   = 320;
  ViewHeight  = 200;

  { The palette is 225 entries starting at colour 1, arranged as 15 bands of
    15. Both rotations below depend on this split. }
  BandCount   = 15;
  BandSize    = 15;
  NumColours  = BandCount * BandSize;  { 225 }

  { Texture location inside NEUROSIS.DAT, recovered from the Seek constant. }
  TextureOfs  = $081A76;               { 531062 }
  PlaneSize   = 64000;

  { Pan path. Radius 100 is exactly the largest circle that keeps the 320x200
    window inside the 400-line image, which is a good sign the values are right. }
  CentreX     = (LogWidth  - ViewWidth)  div 2;   { 160 }
  CentreY     = (LogHeight - ViewHeight) div 2;   { 100 }
  StartRadius = 100.0;
  StartAngle  = 0.0;

  { Read from the CODE segment at CS:$0744/$0748/$0752/$0756 -- Borland parks
    floating-point literals beside the procedures that use them, which is why
    they are CS-relative rather than in DGROUP.

      $0744  Single    1.0     radius floor
      $0748  Extended  0.1     radius decay per frame
      $0752  Single    3.0     angle step per frame
      $0756  Single  360.0     angle wrap
      $06FA  Extended  Pi      used by the degrees->radians helper

    The wrap at 360 and the Pi constant together show the angle is kept in
    DEGREES and converted on each use. }
  RadiusFloor = 1.0;
  RadiusDecay = 0.1;
  AngleStep   = 3.0;     { degrees per frame -> a full turn every 120 frames }
  AngleWrap   = 360.0;

type
  { ONE-BASED, and the subscript fold says so. 1015:018d computes
    Band*BandSize + 1 into DI and folds +1 into the displacement -- base
    $0002 minus a low bound of 1. A 0-based table gives DI = Band*BandSize
    and a displacement of 2, which is what this emitted before. It also
    makes the unrolled moves read naturally: band b is b*15+1 .. b*15+15. }
  TColourTable = array[1..NumColours] of Byte;

{ Three separate R/G/B channel tables, not interleaved triples. These are
  TYPED CONSTANTS, not vars: they sit in the executable's initialised data at
  DS:$0002 / $00E3 / $01C4 (225 bytes each, contiguous, running straight into
  the sine table at $02A8). A plain `var` would land in BSS and would not be
  in the file image at all.

  Borland makes typed constants writable, which is what lets RotateBandsFine
  and RotateBandsCoarse shuffle them in place every frame.

  The ramp is symmetric across the 15 bands -- peak red 0,16,24,34,51, holding
  through the middle, then back down -- with black at both ends of every band,
  which draws the dark grid lines between the tunnel tiles.

  ASSETS  assets/part003/tunnel_palette.pal   (rebuilt 768-byte DAC image)
          Rendering the texture with this instead of a neutral ramp shows the
          tunnel is red-tiled with a repeated letter "A". }
{$I gen/P3PAL.INC}       { const Red, Green, Blue : TColourTable = (...) }

var
  { y * BytesPerRow, 800 entries (the table is built larger than the 400 lines
    actually used). Built at run time by InitTables, so a plain var. }
  YOffset  : array[0..799] of Word;

  { 1 shl (x mod 4) -- the Map Mask value for each column. }
  PlaneOf  : array[0..LogWidth - 1] of Byte;

  { THE ORDER OF THE NEXT FIVE IS READ STRAIGHT OFF THE ADDRESSES, and it is
    not the order a person would write them in. 1015:088d pushes [$A7DE] then
    [$A7E0] as SetDisplayStart's two parameters, so PanX and PanY come FIRST;
    Angle's three words are $A7E2, $A7E4, $A7E6 and Radius's are $A7E8..$A7ED;
    and 1015:0191 stores through [DI+$A7EF], putting RotTmp[1] at $A7F0.

    UNRESOLVED, AND MEASURED THREE WAYS. Our PanX lands at $A7DC where the
    original's is $A7DE, so this unit wants two more bytes BEFORE PanX -- and
    it cannot simply have them. Adding a Word here fixed every address in this
    unit and pushed PART3_STARS' variables up by 2 (its base was already
    right), costing 569 bytes of the coverage walk. Putting the Word between
    Radius and RotTmp instead left the -2 shift untouched and cost the same
    569. So the two bytes are a REDISTRIBUTION inside this unit, not an
    addition: something declared here is two bytes larger than the original's.
    YOffset at 800 entries and PlaneOf at LogWidth are the candidates, and
    neither has been checked against the binary. Do that before adding
    anything. }
  PanX, PanY    : Integer;      { $A7DE, $A7E0 }
  Angle, Radius : Real;         { $A7E2, $A7E8 }

  { The byte RotateBandsFine lifts out of each band before shifting it. Every
    reference in 1015:0191 is indexed BY THE BAND, so the original kept fifteen
    of them rather than one scalar. }
  RotTmp   : array[1..BandCount] of Byte;   { $A7F0, 1-based: DI = Band+1 }

  { UNIT-LEVEL, and the chain of addresses is what says so. This unit's vars run
    from Crt's at DS:$9F0E: YOffset 1,600 bytes, PlaneOf 640, RotTmp 15, then
    Angle at $A7E2 and Radius at $A7E8 -- 1015:075E loads a six-byte Real from
    each -- and PanX and PanY at $A7EE and $A7F0. PART3_STARS' first variable is
    at $A880, and TUNNEL and STARS are ADJACENT in the link order, so the 142
    bytes between belong to this unit and nothing else can put them there. A
    file record is 128 of them.

    LoadTexture had it as a local, which is behaviourally identical and 128
    bytes short: every variable in the part below $A880 sat 132 bytes low
    because of it. Every other scene unit in part 003 already keeps its handle
    here. }
  F             : file;

  { FOUR MORE BYTES THIS UNIT DECLARES AND NOBODY READS. $A872..$A87F is
    fourteen bytes with not one reference to it anywhere in the part, and
    PART3_STARS' first variable is at $A880, so all fourteen are this unit's.
    With the file record above, our block still finished four bytes early. }
  Unread        : LongInt;

{ --------------------------------------------------------------------------
  VGA_SetMode (1192:002a) -- mode 13h, then unchain into Mode-X.
  -------------------------------------------------------------------------- }
procedure SetModeX;
var
  Dummy : Byte;
begin
  asm mov ax,0013h; int 10h end;             { start from mode 13h }

  PortW[$3C4] := $0604;                      { Seq 4: chain-4 off, ext mem on }
  Port[$3CE] := 5;  Port[$3CF] := Port[$3CF] and $EF;   { GC 5: odd/even off }
  Port[$3CE] := 6;  Port[$3CF] := Port[$3CF] and $FD;   { GC 6: chain o/e off }

  PortW[$3C4] := $0F02;                      { Map Mask: all four planes }
  { All 256K at once -- Map Mask $0F means one write hits all four planes.
    Split in two because FillChar's count is a Word and 65536 will not
    fit in one. }
  FillChar(Mem[$A000 : 0],     32768, 0);
  FillChar(Mem[$A000 : 32768], 32768, 0);

  Port[$3D4] := $14; Port[$3D5] := Port[$3D5] and $BF; { CRTC 14: dword off }
  Port[$3D4] := $17; Port[$3D5] := Port[$3D5] or  $40; { CRTC 17: byte mode }
  Port[$3D4] := $13; Port[$3D5] := CrtcOffset;         { CRTC 13: 640 wide }
end;

{ --------------------------------------------------------------------------
  VGA_SelectPlane (1192:0087) -- Sequencer Map Mask.
  -------------------------------------------------------------------------- }
procedure SelectPlane(Plane : Byte);
begin
  PortW[$3C4] := (Word(1 shl Plane) shl 8) or 2;
end;

{ --------------------------------------------------------------------------
  Tunnel_InitTables (1015:0654)
  -------------------------------------------------------------------------- }
procedure InitTables;
var
  I : Word;      { [BP-2] }
  P : Byte;      { [BP-3] -- a BYTE, and the widening is the proof: 1015:0685
                   reads it with MOV AL / XOR AH,AH / MOV DX,AX before the
                   shift count reaches CX, and 1015:069a..06a3 increments and
                   compares it with the byte forms INC BYTE PTR / CMP BYTE PTR
                   / MOV BYTE PTR. A Word here loads straight into CX and
                   costs three instructions less, which is what ours did. }
begin
  for I := 0 to 799 do
    YOffset[I] := I * BytesPerRow;

  P := 0;
  for I := 0 to LogWidth - 1 do
  begin
    PlaneOf[I] := 1 shl P;
    Inc(P);
    if P = 4 then P := 0;
  end;
end;

{ --------------------------------------------------------------------------
  Tunnel_LoadTexture (1015:08a7)

  Reads the four planes straight into VGA memory -- one BlockRead into a
  staging buffer per plane, then a 32000-word copy to A000:0000.

  ASSETS  NEUROSIS.DAT $081A76, four consecutive 64000-byte planes:
            assets/part003/tunnel_plane0.raw   plane 0  (x mod 4 = 0)
            assets/part003/tunnel_plane1.raw   plane 1
            assets/part003/tunnel_plane2.raw   plane 2
            assets/part003/tunnel_plane3.raw   plane 3
          De-interleaved, these are one 640x400 image:
            assets/part003/tunnel_640x400.png
          A single plane viewed at 320 wide shows a phantom second ring
          centre -- that is a stride artefact, not the artwork.
          See docs/06-part3-scene1-tunnel.md.
  -------------------------------------------------------------------------- }
procedure LoadTexture(Buffer : Pointer);
var
  Plane : Byte;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, TextureOfs);
  for Plane := 0 to 3 do
  begin
    SelectPlane(Plane);
    BlockRead(F, Buffer^, PlaneSize);
    Move(Buffer^, Mem[$A000:0], PlaneSize);   { VGA_CopyToPlane, 12f8:00ad }
  end;
  Close(F);
end;

{ --------------------------------------------------------------------------
  Tunnel_UploadPalette (1015:0000)
  225 colours from index 1 up. Note R, G and B come from three separate
  arrays -- the rotations below are what make this worth re-uploading.
  -------------------------------------------------------------------------- }
{ HAND ASSEMBLER, transcribed verbatim. Three signals, each of which Turbo
  Pascal's code generator does not produce: LOOP at 1015:0049, the 8-bit
  pointer arithmetic ADD BL,Ctr / ADC BH,0 -- adding a byte index into the
  low half of an offset and carrying by hand -- and the three table
  addresses held in locals rather than folded into each reference.

  THE FRAME IS ENTER $0A AND THE SLOTS ARE ODD: a byte at [BP-2] and words
  at [BP-5], [BP-7] and [BP-9], which leaves [BP-1], [BP-3] and [BP-10]
  untouched. Three bytes the original declared and never read, so they are
  declared here too -- omitting them puts every slot after them at the
  wrong offset. WHAT they were is not recoverable from the binary; that
  they exist, and exactly where, is.

  FOR REFERENCE ONLY, the equivalent Pascal -- not what the binary does:
    Port[$3C8] := 1;
    for I := 0 to NumColours - 1 do begin
      Port[$3C9] := Red[I + 1];  Port[$3C9] := Green[I + 1];
      Port[$3C9] := Blue[I + 1];
    end;
}
procedure UploadPalette; assembler;
var
  Pad1 : Byte;    { [BP-1]  -- declared, NEVER READ }
  Ctr  : Byte;    { [BP-2]  -- the colour counter }
  Pad2 : Byte;    { [BP-3]  -- declared, NEVER READ }
  PR   : Word;    { [BP-5]  -- DS offset of Red,   $0002 }
  PG   : Word;    { [BP-7]  -- DS offset of Green, $00E3 }
  PB   : Word;    { [BP-9]  -- DS offset of Blue,  $01C4 }
  Pad3 : Byte;    { [BP-10] -- declared, NEVER READ }
asm
  MOV  PR, OFFSET Red        { 1015:0004                                 }
  MOV  PG, OFFSET Green      { 1015:0009                                 }
  MOV  PB, OFFSET Blue       { 1015:000e                                 }
  MOV  DX, $03C8             { 1015:0013  the DAC write-index port       }
  MOV  AL, 1                 { 1015:0016  colour 1, not 0                }
  MOV  Ctr, 0                { 1015:0018                                 }
  OUT  DX, AL                { 1015:001c                                 }
  INC  DX                    { 1015:001d  $03C9, and DX stays live       }
  MOV  CX, NumColours        { 1015:001e  $E1 = 225                      }
@@Next:
  MOV  BX, PR                { 1015:0021                                 }
  ADD  BL, Ctr               { 1015:0024  byte index into the low half   }
  ADC  BH, 0                 { 1015:0027  and carry it by hand           }
  MOV  AL, [BX]              { 1015:002a                                 }
  OUT  DX, AL                { 1015:002c                                 }
  MOV  BX, PG                { 1015:002d                                 }
  ADD  BL, Ctr               { 1015:0030                                 }
  ADC  BH, 0                 { 1015:0033                                 }
  MOV  AL, [BX]              { 1015:0036                                 }
  OUT  DX, AL                { 1015:0038                                 }
  MOV  BX, PB                { 1015:0039                                 }
  ADD  BL, Ctr               { 1015:003c                                 }
  ADC  BH, 0                 { 1015:003f                                 }
  MOV  AL, [BX]              { 1015:0042                                 }
  OUT  DX, AL                { 1015:0044                                 }
  ADD  Ctr, 1                { 1015:0045  ADD, not INC                   }
  LOOP @@Next                { 1015:0049                                 }
end;

{ --------------------------------------------------------------------------
  Tunnel_RotateBandsFine (1015:017f)
  Rotates each 15-colour band left by one, independently, in all three tables.
  Unrolled in the original -- fifteen explicit moves per band.
  -------------------------------------------------------------------------- }
procedure RotateBandsFine;
var
  Band : Integer;
begin
  { UNROLLED, and not a nested procedure taking `var T`. 1015:0191 names the
    three tables at their own displacements and writes fifteen explicit moves
    per band per table -- no parameter is ever loaded, and there is no inner
    loop counter. Our version was a nested RotateEachBand(var T) called three
    times, which cost 1145 bytes of the coverage walk in one span. }
  for Band := 0 to BandCount - 1 do
  begin
    { Red -- DS:$0002 }
    RotTmp[Band + 1] := Red[Band * BandSize + 1];
    Red[Band * BandSize + 1] := Red[Band * BandSize + 2];
    Red[Band * BandSize + 2] := Red[Band * BandSize + 3];
    Red[Band * BandSize + 3] := Red[Band * BandSize + 4];
    Red[Band * BandSize + 4] := Red[Band * BandSize + 5];
    Red[Band * BandSize + 5] := Red[Band * BandSize + 6];
    Red[Band * BandSize + 6] := Red[Band * BandSize + 7];
    Red[Band * BandSize + 7] := Red[Band * BandSize + 8];
    Red[Band * BandSize + 8] := Red[Band * BandSize + 9];
    Red[Band * BandSize + 9] := Red[Band * BandSize + 10];
    Red[Band * BandSize + 10] := Red[Band * BandSize + 11];
    Red[Band * BandSize + 11] := Red[Band * BandSize + 12];
    Red[Band * BandSize + 12] := Red[Band * BandSize + 13];
    Red[Band * BandSize + 13] := Red[Band * BandSize + 14];
    Red[Band * BandSize + 14] := Red[Band * BandSize + 15];
    Red[Band * BandSize + 15] := RotTmp[Band + 1];

    { Green -- DS:$00E3 }
    RotTmp[Band + 1] := Green[Band * BandSize + 1];
    Green[Band * BandSize + 1] := Green[Band * BandSize + 2];
    Green[Band * BandSize + 2] := Green[Band * BandSize + 3];
    Green[Band * BandSize + 3] := Green[Band * BandSize + 4];
    Green[Band * BandSize + 4] := Green[Band * BandSize + 5];
    Green[Band * BandSize + 5] := Green[Band * BandSize + 6];
    Green[Band * BandSize + 6] := Green[Band * BandSize + 7];
    Green[Band * BandSize + 7] := Green[Band * BandSize + 8];
    Green[Band * BandSize + 8] := Green[Band * BandSize + 9];
    Green[Band * BandSize + 9] := Green[Band * BandSize + 10];
    Green[Band * BandSize + 10] := Green[Band * BandSize + 11];
    Green[Band * BandSize + 11] := Green[Band * BandSize + 12];
    Green[Band * BandSize + 12] := Green[Band * BandSize + 13];
    Green[Band * BandSize + 13] := Green[Band * BandSize + 14];
    Green[Band * BandSize + 14] := Green[Band * BandSize + 15];
    Green[Band * BandSize + 15] := RotTmp[Band + 1];

    { Blue -- DS:$01C4 }
    RotTmp[Band + 1] := Blue[Band * BandSize + 1];
    Blue[Band * BandSize + 1] := Blue[Band * BandSize + 2];
    Blue[Band * BandSize + 2] := Blue[Band * BandSize + 3];
    Blue[Band * BandSize + 3] := Blue[Band * BandSize + 4];
    Blue[Band * BandSize + 4] := Blue[Band * BandSize + 5];
    Blue[Band * BandSize + 5] := Blue[Band * BandSize + 6];
    Blue[Band * BandSize + 6] := Blue[Band * BandSize + 7];
    Blue[Band * BandSize + 7] := Blue[Band * BandSize + 8];
    Blue[Band * BandSize + 8] := Blue[Band * BandSize + 9];
    Blue[Band * BandSize + 9] := Blue[Band * BandSize + 10];
    Blue[Band * BandSize + 10] := Blue[Band * BandSize + 11];
    Blue[Band * BandSize + 11] := Blue[Band * BandSize + 12];
    Blue[Band * BandSize + 12] := Blue[Band * BandSize + 13];
    Blue[Band * BandSize + 13] := Blue[Band * BandSize + 14];
    Blue[Band * BandSize + 14] := Blue[Band * BandSize + 15];
    Blue[Band * BandSize + 15] := RotTmp[Band + 1];
  end;
end;

{ --------------------------------------------------------------------------
  Tunnel_RotateBandsCoarse (1015:004d)
  Rotates the whole 225-entry table right by one complete band: the last 15
  entries are saved, everything shifts up by 15, the saved block goes to front.
  -------------------------------------------------------------------------- }
procedure RotateBandsCoarse;

  procedure RotateWholeTable(var T : TColourTable);
  var
    I   : Integer;
    Tmp : array[0..BandSize - 1] of Byte;
  begin
    Move(T[NumColours - BandSize + 1], Tmp, BandSize);
    for I := NumColours downto BandSize + 1 do
      T[I] := T[I - BandSize];
    Move(Tmp, T[1], BandSize);
  end;

begin
  RotateWholeTable(Red);
  RotateWholeTable(Green);
  RotateWholeTable(Blue);
end;

{ --------------------------------------------------------------------------
  VGA_SetDisplayStart (1015:06b0)
  Coarse pan via the CRTC start address (4-pixel granularity, because four
  pixels share a byte address across the planes) and fine pan via Attribute
  Controller register $13. Together they give single-pixel smooth scrolling.
  -------------------------------------------------------------------------- }
{ HAND ASSEMBLER, transcribed verbatim. The tell is the CRTC pair: the
  original loads Addr into BX ONCE and writes both halves as 16-bit OUT
  DX,AX -- index in AL, data in AH -- reusing BH then BL. Turbo Pascal has
  no way to say that: PortW with `$0C or (Hi(Addr) shl 8)` does emit the
  16-bit OUT, and then builds the word as MOV AL / XOR AH,AH / SHL AX,8 /
  OR AX,$000C -- eleven bytes where the original spends four. Measured.
  The attribute-controller tail is the same story: AND BL,3 / SHL BL,1 /
  MOV AL,BL rather than working in AL throughout.

  The frame is ENTER 4 for three bytes of declarations, so [BP-4] is the
  compiler's padding. Dummy is never stored -- the $3DA read at 1015:06e1
  discards AL -- but it is declared, because it is what puts Addr at [BP-2].

  FOR REFERENCE ONLY, the equivalent Pascal -- not what the binary does:
    Addr := LogicalWidth * Y * 2 + (X shr 2);
    Port[$3D4] := $0C; Port[$3D5] := Hi(Addr);
    Port[$3D4] := $0D; Port[$3D5] := Lo(Addr);
    Dummy := Port[$3DA];  Port[$3C0] := $13;
    Port[$3C0] := (X and 3) shl 1;  Port[$3C0] := $20;
}
procedure SetDisplayStart(X, Y : Integer);
var
  Addr  : Word;    { [BP-2] }
  Dummy : Byte;    { [BP-3] -- declared, never stored }
begin
  { COMPILED, not assembler, and two bytes proved it. The arithmetic below
    is byte-identical to the original only when Pascal emits it: the
    compiler writes MOV CX,AX as 8B C8 and ADD AX,CX as 03 C1, while BASM
    writes the SAME MNEMONICS as 89 C1 and 01 C8 -- the other direction
    bit. Transcribing this half as asm left exactly those two bytes wrong.
    So a register-to-register op is a DISCRIMINATOR between compiled code
    and an asm block inside the same binary, built by the same tool. }
  Addr := LogicalWidth * Y * 2 + (X shr 2);   { 1015:06b4..06c8 }

  { 1015:06cb -- HAND ASSEMBLER from here, and the CRTC pair is the tell:
    Addr is loaded into BX ONCE and both halves are written as 16-bit OUT
    DX,AX, index in AL and data in AH. PortW with `$0C or (Hi(Addr) shl 8)`
    does emit the 16-bit OUT and then builds the word as MOV AL / XOR AH,AH
    / SHL AX,8 / OR AX,$000C -- eleven bytes where the original spends
    four. Measured, 25 Aug 2026.

    FOR REFERENCE ONLY, the equivalent Pascal -- not what the binary does:
      Port[$3D4] := $0C; Port[$3D5] := Hi(Addr);
      Port[$3D4] := $0D; Port[$3D5] := Lo(Addr);
      Dummy := Port[$3DA];  Port[$3C0] := $13;
      Port[$3C0] := (X and 3) shl 1;  Port[$3C0] := $20; }
  asm
    MOV  BX, Addr       { 1015:06cb  both halves are used                }
    MOV  AH, BH         { 1015:06ce                                      }
    MOV  AL, $0C        { 1015:06d0  CRTC start address HIGH             }
    MOV  DX, $03D4      { 1015:06d2                                      }
    OUT  DX, AX         { 1015:06d5  ONE 16-bit write: index AND data    }
    MOV  AH, BL         { 1015:06d6                                      }
    MOV  AL, $0D        { 1015:06d8  CRTC start address LOW              }
    MOV  DX, $03D4      { 1015:06da                                      }
    OUT  DX, AX         { 1015:06dd                                      }
    MOV  DX, $03DA      { 1015:06de                                      }
    IN   AL, DX         { 1015:06e1  reset the attribute flip-flop       }
    MOV  DX, $03C0      { 1015:06e2                                      }
    MOV  AL, $13        { 1015:06e5  horizontal pixel panning            }
    OUT  DX, AL         { 1015:06e7                                      }
    MOV  BX, X          { 1015:06e8                                      }
    AND  BL, 3          { 1015:06eb                                      }
    SHL  BL, 1          { 1015:06ee                                      }
    MOV  AL, BL         { 1015:06f0                                      }
    OUT  DX, AL         { 1015:06f2                                      }
    MOV  AL, $20        { 1015:06f3  re-enable video output              }
    OUT  DX, AL         { 1015:06f5                                      }
  end;
end;

{ --------------------------------------------------------------------------
  Tunnel_UpdateMotion (1015:075a)

  The window spirals inward: it turns 3 degrees per frame (a full revolution
  every 120 frames) while the radius decays 0.1 per frame from 100 down to 1.
  That is ~990 frames of travel and roughly eight revolutions, so the tunnel
  mouth appears to swing round and slowly settle to centre.
  -------------------------------------------------------------------------- }
procedure UpdateMotion;

  { 1015:0708 -- a NESTED function, and it has to be one. Each call site
    pushes the six-byte Angle and then BP, and the routine opens ENTER 6,0
    and closes RET 8 -- six bytes of Real parameter plus two of static
    link, which is what TP passes into a routine declared inside another.
    The body is FLD A, FLD Pi from CS:$06FA, FMULP, FDIV the single at
    CS:$0704, then the result through the six-byte-Real temp at [BP-6].

    WRITING `Angle * Pi / 180` INLINE AT BOTH CALL SITES COMPILES, RUNS
    THE SAME, AND IS WRONG: the multiply and the divide are emitted twice
    instead of once, which is three x87 sites more than the original
    ships. The coverage walk cannot see it -- fpusites.py --diff can. }
  function DegToRad(A : Real) : Real;
  begin
    DegToRad := A * Pi / 180;
  end;

begin
  PanX := Round(Radius * Cos(DegToRad(Angle))) + CentreX;
  PanY := Round(Radius * Sin(DegToRad(Angle))) + CentreY;

  if Radius > RadiusFloor then
    Radius := Radius - RadiusDecay;

  Angle := Angle + AngleStep;
  if Angle > AngleWrap then
    Angle := Angle - AngleWrap;

  SetDisplayStart(PanX, PanY);
end;

{ --------------------------------------------------------------------------
  Demo_Scene1 (1015:098d)
  -------------------------------------------------------------------------- }
procedure Scene1;
var
  Buffer : Pointer;
  I      : Word;
begin
  { Buffer was passed to LoadTexture without ever being allocated -- a wild
    pointer that BlockRead then wrote 64,000 bytes through, four times over.
    That is what hung the scene. }
  GetMem(Buffer, PlaneSize);

  InitTables;
  SetModeX;

  for I := 0 to 255 do                        { blank the palette first }
    SetRGB(I, 0, 0, 0);

  LoadTexture(Buffer);

  Angle  := StartAngle;
  Radius := StartRadius;

  MusicCue;                                   { DemoVT 136b:0085 -- spin
                                                the module to position 25 }
  repeat
    MusicPoll;                                { DemoVT 136b:0040 }
    RotateBandsFine;
    RotateBandsCoarse;
    WaitRetrace;                              { palette upload must not tear }
    UploadPalette;
    UpdateMotion;
  until Radius < 1.0;   { FCOMP against CS:[0989] = 1.0 -- exactly 990 frames }

  FreeMem(Buffer, PlaneSize);
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
  CROSS-CHECKS -- why the reconstruction is trusted

  * CRTC Offset register is set to 80  ->  logical width 640.
  * 64000 bytes per plane / 160 bytes per plane-line  ->  400 lines.
  * De-interleaving the four DAT planes as 640x400 yields a single centred
    tunnel; reading them as 320x200 gives a twin-centre artefact, so the
    640x400 interpretation is the correct one.
  * PlaneOf[] is built for exactly 640 entries.
  * The initial radius stored as a Borland Real48 decodes to exactly 100.0,
    matching (400-200) div 2 -- the largest circle that keeps the window in
    bounds vertically.
  * SelectPlane writes Sequencer register 2 (Map Mask), confirming the four
    64000-byte chunks are planes rather than four separate images.

  * The motion constants are CS-relative, not DGROUP: 1.0 / 0.1 / 3.0 / 360.0
    at CS:$0744/$0748/$0752/$0756, plus Pi at CS:$06FA. The 360 wrap and the
    Pi multiply together prove the angle is held in degrees.
  * Radius 100 decaying by 0.1 to a floor of 1.0 gives ~990 frames, and 3
    degrees per frame gives ~8 revolutions over that span -- a spiral-in, which
    is consistent with a scene of roughly 15-20 seconds.

  * Sin is RTL 137b:3252, Cos is RTL 137b:3257. Three lines of evidence:
    they sit in a contiguous 5-byte-stub math block right after Sqrt
    (137b:324e, INT 35h + $FA = FSQRT), which is the order Turbo Pascal's
    System unit groups them in; Scene 1 drives screen-X from $EE and screen-Y
    from $EC; and Scene 2's point generator does the same. x = r*cos,
    y = r*sin follows.
  * The loop runs WHILE Radius >= 1.0 -- `FCOMP float ptr CS:[0989]` (= 1.0)
    then JNC back to the top. It is not a music threshold at all. Combined
    with the 0.1 decay from 100, that fixes the scene at exactly 990 frames.

  OPEN ITEMS
  * None outstanding for this scene.

  NOTE ON GHIDRA
  * The decompiler still prints nonsense for these constants because it
    resolves CS-relative operands against the image base rather than the
    owning segment. The disassembly is correct (`FCOMP float ptr CS:[0x744]`)
    and the values above were read directly from CS:$0744 onwards.
  =========================================================================== }
