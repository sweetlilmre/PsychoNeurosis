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

  CONFIDENCE
    Structure, port programming, table contents, texture offset/size and the
    initial angle/radius are all read directly out of the binary and each was
    cross-checked (see notes at the end). Items marked (?) are inferred.
  =========================================================================== }

unit P3Tunnel;
{ Data alignment off -- the palette bytes sit at consecutive odd offsets,
  which only byte alignment produces. }
{$A-}

{ No I/O checking: a failed read is silent, which is the original's setting. }
{$I-}

{ 286 instructions are permitted. }
{$G+}

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

{ Where each asset sits inside NEUROSIS.DAT. }
{$I gen/DATOFS.INC}

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
  TextureOfs  = DAT_P3_TUNNPLN0;   { $081A76 -- 531062 }
  PlaneSize   = 64000;

  { Pan path. Radius 100 is exactly the largest circle that keeps the 320x200
    window inside the 400-line image, which is a good sign the values are right. }
  CentreX     = (LogWidth  - ViewWidth)  div 2;   { 160 }
  CentreY     = (LogHeight - ViewHeight) div 2;   { 100 }
  StartRadius = 100.0;
  StartAngle  = 0.0;

  RadiusFloor = 1.0;
  RadiusDecay = 0.1;
  AngleStep   = 3.0;     { degrees per frame -> a full turn every 120 frames }
  AngleWrap   = 360.0;

type
  TColourTable = array[1..NumColours] of Byte;

{ Three separate R/G/B channel tables, not interleaved triples. These are
  TYPED CONSTANTS, not vars: they sit in the executable's initialised data at
 / $00E3 / $01C4 (225 bytes each, contiguous, running straight into
  the sine table at $02A8). A plain `var` would land in BSS and would not be
  in the file image at all.

  Borland makes typed constants writable, which is what lets RotateBandsFine
  and RotateBandsCoarse shuffle them in place every frame.

  The ramp is symmetric across the 15 bands -- peak red 0,16,24,34,51, holding
  through the middle, then back down -- with black at both ends of every band,
  which draws the dark grid lines between the tunnel tiles.

  ASSETS  assets/part003/TUNNELPL.PAL   (rebuilt 768-byte DAC image)
          Rendering the texture with this instead of a neutral ramp shows the
          tunnel is red-tiled with a repeated letter "A". }
{$I gen/P3PAL.INC}       { const Red, Green, Blue : TColourTable = (...) }

var
  { y * BytesPerRow, 800 entries (the table is built larger than the 400 lines
    actually used). Built at run time by InitTables, so a plain var. }
  YOffset  : array[0..799] of Word;

  { 1 shl (x mod 4) -- the Map Mask value for each column. }
  PlaneOf  : array[0..LogWidth - 1] of Byte;

  PanX, PanY    : Integer;      { $A7DE, $A7E0 }
  Angle, Radius : Real;         { $A7E2, $A7E8 }

  PalIdx        : Word;         { $A7EE }

  RotTmp   : array[1..BandCount] of Byte;   { $A7F0, 1-based: DI = Band+1 }

  F             : file;

  { NO `Unread : LongInt` HERE ANY MORE, and its removal is the measurement.
    Four bytes were declared at this point to make the block reach $A880,
    because with PanX/PanY, Angle/Radius and RotTmp all in the wrong places the
    block really did finish four bytes early. It was compensating for them. With
    the order corrected above and the $A7EE hole declared, RotTmp[1] lands at
    $A7F0 exactly and the file record then ends at $A880 on its own -- so these
    four bytes became a surplus that pushed PART3_STARS' every variable up by
    four. A declaration that exists to make a total come out is a declaration to
    re-examine the moment anything under it moves. }

{  FOR REFERENCE ONLY, the equivalent Pascal -- not what the binary does:
    Port[$3C8] := 1;
    for I := 0 to NumColours - 1 do begin
      Port[$3C9] := Red[I + 1];  Port[$3C9] := Green[I + 1];
      Port[$3C9] := Blue[I + 1];
    end;
}
{ SETMODEX IS NOT DECLARED HERE, AND THAT IS NOW SETTLED. It is ModeX's, at
 in part 002, and ModeX is in this unit's uses clause -- so the call
  in Scene1 resolves to it exactly as the SelectPlane calls do. The note that
  used to sit here said SetModeX "is either inlined into Scene1 or lives in
  another unit" and left it open; the measurement that closed it is the segment
  length. This unit was 2,752 bytes against the original's 2,608, and the 144
  were a private copy of SetModeX sitting after Scene1: our tail ran
  ENTER 2,0 / MOV AX,$13 / INT $10 and on through the Sequencer and CRTC writes
  to B0 50 into CRTC $13, where the original has only the five bytes of an empty
  unit initialisation. Every routine before it was already at an identical
  offset, which is what said the excess was all in one place.

  The local copy also made the call NEAR. ModeX's is far, which is two bytes
  more at the call site and what the original has -- the same trap the
  SelectPlane note below describes. }

procedure UploadPalette; assembler;
var
  Pad1 : Byte;    { declared, NEVER READ }
  Ctr  : Byte;    { the colour counter }
  Pad2 : Byte;    { declared, NEVER READ }
  PR   : Word;    { DS offset of Red,   $0002 }
  PG   : Word;    { DS offset of Green, $00E3 }
  PB   : Word;    { DS offset of Blue,  $01C4 }
  Pad3 : Byte;    { declared, NEVER READ }
asm
  MOV  PR, OFFSET Red
  MOV  PG, OFFSET Green
  MOV  PB, OFFSET Blue
  MOV  DX, $03C8             { the DAC write-index port       }
  MOV  AL, 1                 { colour 1, not 0                }
  MOV  Ctr, 0
  OUT  DX, AL
  INC  DX                    { $03C9, and DX stays live       }
  MOV  CX, NumColours        { $E1 = 225                      }
@@Next:
  MOV  BX, PR
  ADD  BL, Ctr               { byte index into the low half   }
  ADC  BH, 0                 { and carry it by hand           }
  MOV  AL, [BX]
  OUT  DX, AL
  MOV  BX, PG
  ADD  BL, Ctr
  ADC  BH, 0
  MOV  AL, [BX]
  OUT  DX, AL
  MOV  BX, PB
  ADD  BL, Ctr
  ADC  BH, 0
  MOV  AL, [BX]
  OUT  DX, AL
  ADD  Ctr, 1                { ADD, not INC                   }
  LOOP @@Next
end;

{ UNROLLED PER TABLE, and no nested procedure and no Move. The original is
  three groups of three loops -- save the last band, shift everything up by one
  band, put the saved band at the front -- written out once for each table. }
procedure RotateBandsCoarse;
var
  I : Integer;                    { the only local }
begin
  { Red }
  for I := 1 to BandSize do
    RotTmp[I] := Red[I + (NumColours - BandSize)];
  for I := NumColours - BandSize downto 1 do
    Red[I + BandSize] := Red[I];
  for I := 1 to BandSize do
    Red[I] := RotTmp[I];

  { Green }
  for I := 1 to BandSize do
    RotTmp[I] := Green[I + (NumColours - BandSize)];
  for I := NumColours - BandSize downto 1 do
    Green[I + BandSize] := Green[I];
  for I := 1 to BandSize do
    Green[I] := RotTmp[I];

  { Blue }
  for I := 1 to BandSize do
    RotTmp[I] := Blue[I + (NumColours - BandSize)];
  for I := NumColours - BandSize downto 1 do
    Blue[I + BandSize] := Blue[I];
  for I := 1 to BandSize do
    Blue[I] := RotTmp[I];
end;

{ --------------------------------------------------------------------------
  VGA_SetDisplayStart
  Coarse pan via the CRTC start address (4-pixel granularity, because four
  pixels share a byte address across the planes) and fine pan via Attribute
  Controller register $13. Together they give single-pixel smooth scrolling.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  Tunnel_RotateBandsFine
  Rotates each 15-colour band left by one, independently, in all three tables.
  Unrolled in the original -- fifteen explicit moves per band.
  -------------------------------------------------------------------------- }
procedure RotateBandsFine;
var
  Band : Integer;
begin
  for Band := 0 to BandCount - 1 do
  begin
    { Red }
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

    { Green }
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

    { Blue }
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
  Tunnel_RotateBandsCoarse
  Rotates the whole 225-entry table right by one complete band: the last 15
  entries are saved, everything shifts up by 15, the saved block goes to front.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  Tunnel_InitTables
  -------------------------------------------------------------------------- }
procedure InitTables;
var
  I : Word;
  P : Byte;
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
  Tunnel_LoadTexture
  Reads the four planes straight into VGA memory -- one BlockRead into a
  staging buffer per plane, then a 32,000-word copy to video memory.

  ASSETS  NEUROSIS.DAT $081A76, four consecutive 64000-byte planes:
            assets/part003/TUNNPLN0.RAW   plane 0  (x mod 4 = 0)
            assets/part003/TUNNPLN1.RAW   plane 1
            assets/part003/TUNNPLN2.RAW   plane 2
            assets/part003/TUNNPLN3.RAW   plane 3
          De-interleaved, these are one 640x400 image:
            assets/part003/TUNNEL.PNG
          A single plane viewed at 320 wide shows a phantom second ring
          centre -- that is a stride artefact, not the artwork.
          See docs/06-part3-scene1-tunnel.md.
  -------------------------------------------------------------------------- }
{ HAND ASSEMBLER, transcribed verbatim. The tell is the CRTC pair: the
  original loads Addr into BX ONCE and writes both halves as 16-bit OUT
  DX,AX -- index in AL, data in AH -- reusing BH then BL. Turbo Pascal has
  no way to say that: PortW with `$0C or (Hi(Addr) shl 8)` does emit the
  16-bit OUT, and then builds the word as MOV AL / XOR AH,AH / SHL AX,8 /
  OR AX,$000C -- eleven bytes where the original spends four. Measured.
  The attribute-controller tail is the same story: AND BL,3 / SHL BL,1 /
  MOV AL,BL rather than working in AL throughout.

  FOR REFERENCE ONLY, the equivalent Pascal -- not what the binary does:
    Addr := LogicalWidth * Y * 2 + (X shr 2);
    Port[$3D4] := $0C; Port[$3D5] := Hi(Addr);
    Port[$3D4] := $0D; Port[$3D5] := Lo(Addr);
    Dummy := Port[$3DA];  Port[$3C0] := $13;
    Port[$3C0] := (X and 3) shl 1;  Port[$3C0] := $20;
}
procedure SetDisplayStart(X, Y : Integer);
var
  Addr  : Word;
  Dummy : Byte;    { declared, never stored }
begin
  { COMPILED, not assembler, and two bytes proved it. The arithmetic below
    is byte-identical to the original only when Pascal emits it: the
    compiler writes MOV CX,AX as 8B C8 and ADD AX,CX as 03 C1, while BASM
    writes the SAME MNEMONICS as 89 C1 and 01 C8 -- the other direction
    bit. Transcribing this half as asm left exactly those two bytes wrong.
    So a register-to-register op is a DISCRIMINATOR between compiled code
    and an asm block inside the same binary, built by the same tool. }
  Addr := LogicalWidth * Y * 2 + (X shr 2);

  { HAND ASSEMBLER from here, and the CRTC pair is the tell:
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
    MOV  BX, Addr       { both halves are used                }
    MOV  AH, BH
    MOV  AL, $0C        { CRTC start address HIGH             }
    MOV  DX, $03D4
    OUT  DX, AX         { ONE 16-bit write: index AND data    }
    MOV  AH, BL
    MOV  AL, $0D        { CRTC start address LOW              }
    MOV  DX, $03D4
    OUT  DX, AX
    MOV  DX, $03DA
    IN   AL, DX         { reset the attribute flip-flop       }
    MOV  DX, $03C0
    MOV  AL, $13        { horizontal pixel panning            }
    OUT  DX, AL
    MOV  BX, X
    AND  BL, 3
    SHL  BL, 1
    MOV  AL, BL
    OUT  DX, AL
    MOV  AL, $20        { re-enable video output              }
    OUT  DX, AL
  end;
end;

{ --------------------------------------------------------------------------
  Tunnel_UpdateMotion
  The window spirals inward: it turns 3 degrees per frame (a full revolution
  every 120 frames) while the radius decays 0.1 per frame from 100 down to 1.
  That is ~990 frames of travel and roughly eight revolutions, so the tunnel
  mouth appears to swing round and slowly settle to centre.
  -------------------------------------------------------------------------- }
procedure UpdateMotion;

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
  Demo_Scene1
  -------------------------------------------------------------------------- }

{ NO PARAMETER, NO LOOP, AND THE BUFFER IS VGA'S VIRTUAL SCREEN. }
procedure LoadTexture;
var
  Spare : array[1..512] of Byte;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, TextureOfs);

  SelectPlane(0);
  BlockRead(F, VirtScr^, PlaneSize);
  CopyScreen(VirtScrSeg, $A000);

  SelectPlane(1);
  BlockRead(F, VirtScr^, PlaneSize);
  CopyScreen(VirtScrSeg, $A000);

  SelectPlane(2);
  BlockRead(F, VirtScr^, PlaneSize);
  CopyScreen(VirtScrSeg, $A000);

  SelectPlane(3);
  BlockRead(F, VirtScr^, PlaneSize);
  CopyScreen(VirtScrSeg, $A000);

  Close(F);
end;

{ --------------------------------------------------------------------------
  Tunnel_UploadPalette
  225 colours from index 1 up. Note R, G and B come from three separate
  arrays -- the rotations below are what make this worth re-uploading.
  -------------------------------------------------------------------------- }
{  FOR REFERENCE ONLY, the equivalent Pascal -- not what the binary does:
    Port[$3C8] := 1;
    for I := 0 to NumColours - 1 do begin
      Port[$3C9] := Red[I + 1];  Port[$3C9] := Green[I + 1];
      Port[$3C9] := Blue[I + 1];
    end;
}

{ --------------------------------------------------------------------------
  Demo_Scene1
  -------------------------------------------------------------------------- }
procedure Scene1;
begin
  { FIRST, before anything else. ModeX's LogicalWidth is set here
    and not inside InitTables. }
  LogicalWidth := 80;
  InitTables;
  SetModeX;

  { the counter is the UNIT-LEVEL PalIdx, not a local. }
  for PalIdx := 0 to 255 do                   { blank the palette first }
    SetRGB(PalIdx, 0, 0, 0);

  LoadTexture;

  Angle  := StartAngle;
  Radius := StartRadius;

  MusicCue;                                   { spin
                                                the module to position 25 }
  repeat
    MusicPoll;                                { keep the player ticking }
    RotateBandsFine;
    RotateBandsCoarse;
    WaitRetrace;                              { palette upload must not tear }
    UploadPalette;
    UpdateMotion;
  until Radius < 1.0;   { FCOMP against CS:[0989] = 1.0 -- exactly 990 frames }

  { NO FreeMem. The buffer was VGA's virtual screen all along and the part's
    main body frees it with VirtScrFree; scene 1 neither allocates nor releases
    it. }
end;


{ --------------------------------------------------------------------------
  VGA_SetMode -- mode 13h, then unchain into Mode-X.
  -------------------------------------------------------------------------- }
{ SelectPlane IS NOT DECLARED HERE -- it is MODEX's, reached by a far call. }

{ --------------------------------------------------------------------------
  Tunnel_InitTables
  -------------------------------------------------------------------------- }

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

  OPEN ITEMS
  * None outstanding for this scene. }
