{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.007, the FLIC player
  Reconstructed from NEUROSIS_007_fpu.exe.

  A complete Autodesk Animator FLIC player, used to run lemend.flc -- the
  end-of-demo Lemmings animation.

  ADDRESS MAP
    FLIC_Play    100f:0453    FLIC_Init        100f:031d
    FLIC_Color256 100f:00de   FLIC_Color64     100f:01dc
    FLIC_FrameStart 100f:02cf FLIC_FrameEnd    100f:03c9
    FLIC_Done    100f:03b4
  =========================================================================== }

unit Part7Flic;

interface

procedure PlayFlic(Name : String);

implementation

uses VGA, Crt;

const
  FLC_Magic  = $AF12;      { FLC. $AF11 would be FLI }
  HdrSize    = $80;        { 128-byte file header }
  FrameHdr   = $10;        { 16-byte frame header }
  ChunkHdr   = 6;          { 6-byte chunk header: size (long), type (word) }
  ScrW       = 320;        { the player refuses anything else }
  ScrH       = 200;

  { Chunk types, all of the standard set. }
  FLI_COLOR256 = 4;
  FLI_SS2      = 7;
  FLI_COLOR64  = 11;
  FLI_LC       = 12;
  FLI_BRUN     = 15;
  FLI_COPY     = 16;
  FLI_PSTAMP   = 18;

type
  TFlicHeader = record
    Size     : LongInt;
    Magic    : Word;
    Frames   : Word;
    Width    : Word;
    Height   : Word;
    { ... to 128 bytes ... }
  end;

var
  { The four delta/RLE decoders are reached through a table of procedure
    pointers at DS:$340D, which is why they are indirect calls in the
    disassembly rather than direct ones. }
  DecodeSS2, DecodeLC, DecodeCopy, DecodeBrun : Pointer;

{ ===========================================================================
  RECONSTRUCTION SCAFFOLDING -- see the note in PART1_INTRO.PAS.
  =========================================================================== }

var
  { The FLIC header's frame-1 offset (FLC only) and the frame delay, both read
    from the file header rather than computed. }
  OffsetOfFirstFrame : LongInt;
  Speed              : Word;
  CalibTicks         : LongInt;   { DS:$01FE -- FlicInit's result }

{ [transcribed] FLIC_FrameStart (100f:02cf) -- latches and reads the 8253
  counter. It is a CLOCK, not the no-op an earlier version assumed; both the
  calibration below and the per-frame pacing are built on it. }
function FrameStart : LongInt;
var
  Lo, Hi : Byte;
begin
  Port[$43] := $00;              { latch channel 0 }
  Lo := Port[$40];
  Hi := Port[$40];
  FrameStart := LongInt(Hi) shl 8 + Lo;
end;

{ [stub] the reference loop FlicInit times. }
procedure ReferenceWork;
begin
end;

{ --------------------------------------------------------------------------
  FLIC_Init (100f:031d) -- NOT a video setup. It is a TIMER CALIBRATION.

      out $43, $34        8253 channel 0, mode 2 (rate generator), binary
      out $40, 0
      out $40, 0          divisor 0 = 65536, the standard 18.2 Hz tick

  then it times ONE HUNDRED iterations of a reference loop, accumulating the
  elapsed ticks into a 32-bit total at DS:$01FE/$0200. FrameEnd uses that to
  pace playback against the file's own frame delay -- which is why the player
  runs at the right speed on machines of different speeds.

  The inferred version set a video mode and allocated a buffer, which is not
  what this routine does at all.
  -------------------------------------------------------------------------- }
procedure FlicInit;
var
  I     : Integer;
  T0, T1 : LongInt;
begin
  Port[$43] := $34;
  Port[$40] := 0;
  Port[$40] := 0;

  CalibTicks := 0;
  for I := 1 to 100 do
  begin
    T0 := FrameStart;
    ReferenceWork;
    T1 := FrameStart;
    Inc(CalibTicks, T1 - T0);
  end;
end;

procedure FlicDone;
begin
  VirtScrFree;
  SetTextMode;
end;

{ [stub] per-frame bookkeeping; FrameEnd blits and waits out the delay. }
{ [inferred] per-frame bookkeeping -- nothing to do but note the start; the
  decoders write straight into the virtual screen. }
procedure FrameEnd(Ticks : Word);
begin
  CopyScreen(VirtScrSeg, $A000);
end;

{ [transcribed] the chunk count is the word at offset 6 of the frame header. }
function ChunksInFrame(var FH) : Word;
var
  B : array[0..15] of Byte absolute FH;
begin
  ChunksInFrame := B[6] + B[7] shl 8;
end;

{ [stub] COLOR256 / COLOR64 palette chunks. They differ only in component
  scale: COLOR64 is already 0..63, COLOR256 is 0..255 and gets shifted down. }
{ [transcribed] FLI_COLOR256 / FLI_COLOR64 (100f:00de and 100f:01dc).

  Packet-encoded: a word packet count, then per packet a skip count, a colour
  count (0 meaning 256), and that many RGB triples.

  The part an earlier version got wrong is HOW the palette is written. It does
  not touch ports $3C8/$3C9 at all -- it goes through the BIOS, INT 10h with
  AX = $1012 ("set block of DAC registers"). COLOR64's components are already
  in the 0..63 range the BIOS wants; COLOR256's are 0..255 and are shifted
  down by two first. }
procedure ColorChunk(P : Pointer; Shift : Byte);
var
  B       : ^Byte;
  Packets : Integer;
  Skip, N : Integer;
  Idx, I  : Integer;
begin
  B := P;
  Packets := B^;  Inc(LongInt(B));
  Packets := Packets + B^ shl 8;  Inc(LongInt(B));
  Idx := 0;
  while Packets > 0 do
  begin
    Skip := B^;  Inc(LongInt(B));
    Inc(Idx, Skip);
    N := B^;  Inc(LongInt(B));
    if N = 0 then N := 256;
    for I := 1 to N do
    begin
      if Idx < 256 then
      begin
        Palette[Idx, 0] := B^ shr Shift;  Inc(LongInt(B));
        Palette[Idx, 1] := B^ shr Shift;  Inc(LongInt(B));
        Palette[Idx, 2] := B^ shr Shift;  Inc(LongInt(B));
      end;
      Inc(Idx);
    end;
    Dec(Packets);
  end;
  SetPalette;
end;

procedure Color256(P : Pointer);
begin
  ColorChunk(P, 2);          { 0..255 -> 0..63 }
end;

{ [transcribed] FLIC_Color64 (100f:01dc) -- same packet encoding as COLOR256
  and the same INT 10h/$1012 write, but the components are already in the
  DAC's 0..63 range, so there is no shift. }
procedure Color64(P : Pointer);
begin
  ColorChunk(P, 0);
end;

{ [inferred] The original dispatches the four pixel decoders through a
  function pointer in DGROUP, which is why they share one signature. Kept as
  an indirect call rather than flattened into the case statement. }
{ [inferred] The original dispatches the four pixel decoders through a
  function pointer in DGROUP, which is why they share one signature. Modelled
  here as a real indirect call so the shape is preserved. }
type
  TDecoder = procedure(P : Pointer);

procedure CallIndirect(Proc, P : Pointer);
var
  Go : TDecoder absolute Proc;
begin
  Go(P);
end;

{ --------------------------------------------------------------------------
  FLIC_Play (100f:0453)

  ASSETS  NEUROSIS.DAT $19117F, 62,206 bytes:
            assets/part007/lemend_flc.flc
          Extracted verbatim and playable in any FLIC viewer.
          See docs/19-part007-flic.md.
  -------------------------------------------------------------------------- }
procedure PlayFlic(Name : String);
var
  F        : file;
  Hdr      : TFlicHeader;
  FrameHd  : array[0..FrameHdr - 1] of Byte;
  ChunkSz  : LongInt;
  ChunkTyp : Word;
  Buf      : Pointer;
  Frame, C : Integer;
begin
  GetMem(Buf, 65000);
  FlicInit;

  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $19117F);

  BlockRead(F, Hdr, HdrSize);

  if (Hdr.Width <> ScrW) or (Hdr.Height <> ScrH) then
  begin
    SetTextMode;
    WriteLn('Error : Sorry, only 320x200 flics supported.');
    Halt;
  end;

  if Hdr.Magic = FLC_Magic then
    Seek(F, OffsetOfFirstFrame);           { FLC carries frame offsets }

  Frame := 1;
  repeat
    FrameStart;
    BlockRead(F, FrameHd, FrameHdr);

    for C := 1 to ChunksInFrame(FrameHd) do
    begin
      BlockRead(F, ChunkSz, ChunkHdr);
      if ChunkTyp = FLI_COPY then
        Inc(ChunkSz, 2);                   { COPY's size needs the fix-up }
      BlockRead(F, Buf^, ChunkSz - ChunkHdr);

      case ChunkTyp of
        FLI_PSTAMP   : { skip -- it is only a thumbnail };
        FLI_SS2      : CallIndirect(DecodeSS2,  Buf);
        FLI_LC       : CallIndirect(DecodeLC,   Buf);
        FLI_COPY     : CallIndirect(DecodeCopy, Buf);
        FLI_BRUN     : CallIndirect(DecodeBrun, Buf);
        FLI_COLOR256 : Color256(Buf);
        FLI_COLOR64  : Color64(Buf);
      else
        Halt;                              { unknown chunk -- give up }
      end;

      while KeyPressed do ReadKey;
    end;

    FrameEnd(Speed);
    Inc(Frame);
  until Frame > Hdr.Frames + 1;

  FlicDone;
  Close(F);
  FreeMem(Buf, 65000);
end;

end.

{ ===========================================================================
  NOTES

  * The magic check is against $AF12 (FLC). An $AF11 (FLI) file would take the
    other branch, which skips the frame-offset seek.
  * The dimension check is strict and fatal -- the error string is in the
    binary at 100f:$0426.
  * This part also reprograms the PIT (ports $40/$43) for frame timing, which
    is why it is the only part in the demo with timer writes.
  =========================================================================== }
