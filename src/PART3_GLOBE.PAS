{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 4
  Reconstructed from NEUROSIS_003_fpu.exe, segment 119d.

  A picture show with cross-fades, alternating a title image with three
  others, and between each pair a rotating globe: a scrolling cloud band
  mapped onto a sphere through a precomputed scatter blit.

  There is no sphere maths at run time. Two 45,994-byte tables of 16-bit
  offsets are loaded from disk; rendering a frame is just

      for i := 1 to 22996 do
        Mem[$A000 : Dst[i]] := Mem[VirtScr : Src[i]];

  and then the source band is scrolled one pixel left. The scroll is what
  makes the globe appear to turn.

  ADDRESS MAP
    Demo_Scene4        119d:0211     Globe_LoadTables   119d:010f
    Palette_FadeIn     119d:0064     Palette_FadeOut    119d:0000
    Globe_RenderFrame  119d:018b
  =========================================================================== }

{$G+}   { 286: the original's procedures open with ENTER, a 286 instruction. }

unit Part3Globe;

interface

procedure Scene4;

implementation

uses VGA, Crt;

const
  { All four screens share ONE palette, loaded once at the start of the scene.
    That is what lets them cross-fade into each other without a palette
    reload -- only the pixels change. }
  DataOfs     = $0C0E2E;      { palette + the two offset tables }
  PaletteSize = $300;         { 768 }
  TableSize   = $B3AA;        { 45994 bytes = 22997 words }
  Entries     = TableSize div 2;

  { The four full-screen images, in the order the scene uses them. }
  ImgTitle    = $0D7882;      { "ReAl TiMe" gold lettering -- shown 3 times }
  ImgCity     = $0E7282;      { city skyline against clouds }
  ImgFigures  = $0F6C82;      { two figures against clouds }
  ImgDeth     = $106682;      { fiery DETH logo }

  FadeSteps   = 64;           { $40 -- one DAC step per frame, 6-bit range }
  HoldMs      = 1000;

  { The scrolled band: rows 1..150, 300 bytes wide, inside the 320-wide
    virtual screen. Exactly the region the src offset table samples. }
  ScrollTop   = 1;
  ScrollRows  = 150;          { $96 }
  ScrollWords = 150;          { $96 -- 300 bytes }
  ScrollSkip  = 20;           { $14 -- rest of the 320-byte row }

type
  TOffsets = array[0..Entries - 1] of Word;

var
  F : file;                        { NEUROSIS.DAT, open for the whole scene }

{ --------------------------------------------------------------------------
  Palette_FadeOut (119d:0000)
  The same shape, but every non-zero channel steps down toward black. No
  target table needed.
  -------------------------------------------------------------------------- }
procedure FadeOut;
var
  { EIGHT BYTES, NOT SIX. 119d:0000's slots are [BP-$02] never touched,
    [BP-$04] five times, [BP-$06] four times and [BP-$08] never touched, with
    the lowest touched byte at [BP-$07] -- so the three colour bytes are at
    $05, $06 and $07, the counter is the word at $04, and there is an unread
    word declared BEFORE it and an unread byte declared AFTER the colours. An
    unreferenced local is still allocated, so the operand counts both and
    nothing in the instruction stream points at either. }
  Unread  : Word;                 { [BP-$02], never read }
  I       : Word;                 { [BP-$04] }
  R, G, B : Byte;                 { [BP-$05], [BP-$06], [BP-$07] }
  Spare   : Byte;                 { [BP-$08], never read }
begin
  WaitRetrace;
  for I := 0 to 255 do
  begin
    GetRGB(I, R, G, B);
    if R <> 0 then Dec(R);
    if G <> 0 then Dec(G);
    if B <> 0 then Dec(B);
    SetRGB(I, R, G, B);
  end;
end;

{ --------------------------------------------------------------------------
  Demo_Scene4 (119d:0211)

  The pattern repeats three times: show the title image, fade it up, hold,
  fade it down; then load the next image into the *virtual* screen, blank the
  visible screen, and fade in and out again -- this time with the globe
  running, so the new image is what wraps around the sphere.
  -------------------------------------------------------------------------- }
procedure Scene4;
var
  I : Integer;

  { Scene4's frame, and the layout is load-bearing: LoadTables and RenderFrame
    are nested below because they are nested in the original, and they reach
    these three through a static link.
        SS:[link-$0A]  SrcOfs        SS:[link-$06]  DstOfs
        SS:[link-$30A] Target                                                 }
  SrcOfs, DstOfs : ^TOffsets;      { two GetMem'd 45994-byte tables }
  Target         : array[0..767] of Byte;   { fade-in destination palette }

  { --------------------------------------------------------------------------
    Palette_FadeIn (119d:0064)
    Read each DAC entry back, step any channel that is below its target up by
    one, write it out. Called 64 times, which is the full 6-bit range.
    -------------------------------------------------------------------------- }
  procedure FadeIn;
  var
    { THE SAME EIGHT-BYTE SHAPE AS FadeOut, and the same slots: 119d:0064 has
      [BP-$02] and [BP-$08] never touched around a word at $04 and the three
      colour bytes at $05..$07. Two routines written from one template, and
      both declared two of their locals and never read them. }
    Unread     : Word;              { [BP-$02], never read }
    I          : Word;              { [BP-$04] }
    R, G, B    : Byte;              { [BP-$05], [BP-$06], [BP-$07] }
    Spare      : Byte;              { [BP-$08], never read }
  begin
    if KeyPressed then Exit;
    WaitRetrace;
    for I := 0 to 255 do
    begin
      GetRGB(I, R, G, B);
      if R < Target[I * 3 + 0] then Inc(R);
      if G < Target[I * 3 + 1] then Inc(G);
      if B < Target[I * 3 + 2] then Inc(B);
      SetRGB(I, R, G, B);
    end;
  end;

{ --------------------------------------------------------------------------
  Globe_LoadTables (119d:010f)

  ASSETS  NEUROSIS.DAT $0C0E2E, 92,756 bytes in three reads:
            assets/part003/scene4_palette.pal      768 B, shared by all four
                                                   images -- see note above
            assets/part003/globe_src_offsets.bin   45,994 B, source offsets
            assets/part003/globe_dst_offsets.bin   45,994 B, destination offsets
          Coverage maps (generated, not in the demo):
            assets/part003/globe_warp_dst.png      a filled disc, 22,996 px
            assets/part003/globe_warp_src.png      a 300x150 band, 16,316 px
          The destination is a disc and the source a rectangle sampled
          many-to-one at the edges: that is a sphere map.
          See docs/10-part3-scene4-globe.md.
  -------------------------------------------------------------------------- }
  procedure LoadTables;
  var
    { ONE HUNDRED AND TWENTY-EIGHT BYTES THIS ROUTINE NEVER READS. 119d:010f
      opens ENTER $80 and there is not one BP-relative reference in the whole
      routine -- everything it touches is either the static link at [BP+$04] or
      DGROUP. 128 is the size of an untyped `file` variable, so the likeliest
      reading is a second file record declared here and abandoned when the
      author moved it to the unit's own storage. Whatever it was, the space is
      reserved and the operand says so. }
    Unread : array[0..127] of Byte;
  begin
    GetMem(SrcOfs, TableSize);                 { 119d:0113 -> SS:[link-$0A] }
    GetMem(DstOfs, TableSize);                 { 119d:0126 -> SS:[link-$06] }
    BlockRead(F, Target,  PaletteSize);        { 119d:0141, SS:[link-$30A]  }
    BlockRead(F, SrcOfs^, TableSize);
    BlockRead(F, DstOfs^, TableSize);
  end;

{ --------------------------------------------------------------------------
  Globe_RenderFrame (119d:018b)

  Two passes, and the whole effect is in them.

  1. Scatter blit. Walk both offset tables in step and copy one byte each
     time, virtual screen -> $A000. Because the tables were precomputed, an
     arbitrary warp costs one MOVSB per pixel and no arithmetic at all.

  2. Scroll the source band one pixel left, wrapping the leading word to the
     end of the row. Next frame the same sphere map samples shifted texture,
     so the globe appears to rotate.

  Hand assembler: it juggles DS/ES per pixel to read an offset from one
  table's segment, another from the second, then move a byte between two
  further segments.

  DS IS REPOINTED THREE TIMES PER PIXEL, so the segment values have to be in
  registers before the loop starts. Reading them by name inside it --
  `MOV DS,[DstSeg]` -- looks like Pascal and compiles, but by the second
  iteration DS is the virtual screen, so it fetches the "segment" out of video
  memory and the blit scatters bytes at random. 119d:01be caches both in CX
  and DX ahead of the loop for exactly this reason.

  THE TABLES ARE THE PARENT'S LOCALS, not unit variables. LoadTables and
  RenderFrame are both nested inside Demo_Scene4 in the original and reach
  SrcOfs and DstOfs through a static link -- 119d:011b and 119d:019a are both
  MOV DI,[BP+4] followed by an SS-relative access. Hoisting the tables to unit
  variables turns every one of those into a DGROUP read, which is what an
  earlier pass did; the routine then stops matching the binary.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      for I := 1 to TableSize div 2 - 1 do
        Mem[$A000 : DstOfs^[I]] := Mem[VirtScrSeg : SrcOfs^[I]];

      for Y := 1 to ScrollRows do
      begin
        W := MemW[VirtScrSeg : Y*320 + 1];
        Move(Mem[VirtScrSeg : Y*320 + 1], Mem[VirtScrSeg : Y*320],
             ScrollWords * 2);
        MemW[VirtScrSeg : Y*320 + ScrollWords*2] := W;
      end;

  It cannot be written that way and still work: DstOfs and SrcOfs are not
  Pascal arrays but two far heap blocks read a word at a time with DS pointed
  at each in turn, and the wrap in pass 2 writes back to where DI ended up
  rather than to a recomputed address.
  -------------------------------------------------------------------------- }
{ @asm 003 119d:018b }
  procedure RenderFrame;
  var
    { 119d:01a3 and 119d:01af -- RenderFrame's OWN two words: the segments of
      the parent's two tables, copied down here once so the loop can reload DS
      from a register three times a pixel. }
    SrcSeg, DstSeg : Word;          { [BP-$02], [BP-$04] }
    Unread         : Word;          { [BP-$06], never read -- 119d:018b's
                                      ENTER is $06 and the lowest slot the
                                      routine touches is [BP-$04] }
  begin
    { 119d:018f -- the frame is abandoned the moment a key is down. }
    if KeyPressed then Exit;

    { 119d:019a -- the two table segments. THIS IS PASCAL, not assembler, and
      it has to be: SrcOfs and DstOfs are Scene4's locals, so reaching them
      means following the static link, and Turbo Pascal's inline assembler
      will not do that. Written as `LES DI, SrcOfs` inside the asm block it
      compiles to LES DI,[BP-6] -- RenderFrame's own frame, the wrong one, and
      silently wrong at run time. As Pascal it compiles to exactly what the
      binary has: MOV DI,[BP+4] / LES DI,SS:[DI-$0A] / MOV AX,ES / MOV
      [BP-2],AX, and the same again for DstOfs. }
    SrcSeg := Seg(SrcOfs^);      { 119d:019a                                    }
    DstSeg := Seg(DstOfs^);      { 119d:01a6                                    }

    asm
    { ---- pass 1: precomputed scatter blit ---- }
    PUSH DS                      { DS is about to be used as scratch            }
    MOV  AX, $A000               { video memory                                 }
    MOV  ES, AX                  { destination is always video                  }
    MOV  BX, 2                   { entry 0 is skipped -- the tables are 1-based }
    MOV  AX, [VirtScrSeg]        { DS is still DGROUP here -- read it now       }
    MOV  CX, SrcSeg              { the source-offset table's segment            }
    MOV  DX, DstSeg              { the destination-offset table's segment       }
@Blit:                           { <- once per pixel of the sphere map          }
    MOV  DS, DX                  { DS := the destination-offset table           }
    MOV  SI, BX                  { SI := the byte index of this entry           }
    MOV  DI, [SI]                { DI := DstOfs[i], the screen offset           }
    MOV  DS, CX                  { DS := the source-offset table                }
    MOV  CX, [SI]                { CX := SrcOfs[i] -- through CX and not        }
    MOV  DS, AX                  {   straight into SI, because SI is still the  }
    MOV  SI, CX                  {   table index until DS has been repointed    }
    MOV  CX, SrcSeg              { CX held the source segment: put it back      }
    ADD  BX, 2                   { step to the next pair of table entries       }
    MOVSB                        { ES:[DI] <- DS:[SI] -- one warped pixel       }
    CMP  BX, TableSize           { end of the tables?                           }
    JNZ  @Blit                   {   no: round again                            }

  { ---- pass 2: scroll rows 1..150 left by one pixel, with wrap ---- }
    MOV  ES, AX                  { both source and destination are the          }
    MOV  DS, AX                  {   virtual screen for this pass               }
    MOV  DI, 320                 { row 1, column 0 -- the write pointer         }
    MOV  SI, 321                 { one pixel along -- the read pointer          }
    MOV  BX, ScrollRows          { 150 rows of texture to shift                 }
@Row:                            { <- once per row                              }
    MOV  AX, [SI]                { save the word about to be shifted off        }
    MOV  CX, ScrollWords         { how many words make up the band              }
    REP  MOVSW                   { slide the row one pixel left                 }
    MOV  ES:[DI], AX             { and wrap it to the end of the row -- DI is   }
                                 {   already there after the REP                }
    ADD  DI, ScrollSkip          { step both pointers to the next row           }
    ADD  SI, ScrollSkip          {                                              }
    DEC  BX                      { one row done                                 }
    JNZ  @Row                    { round again until all 150 are shifted        }
    POP  DS                      { restore our data segment                     }
    end;
  end;


  procedure ShowFlat(FileOfs : LongInt);      { straight to the visible screen }
  var I : Integer;
  begin
    Seek(F, FileOfs);
    BlockRead(F, VirtScr^, 64000);
    if not KeyPressed then CopyScreen(VirtScrSeg, $A000);
    ClearScreen(VirtScrSeg, 0);
    for I := 1 to FadeSteps do FadeIn;
    if not KeyPressed then Delay(HoldMs);
    for I := 1 to FadeSteps do FadeOut;
  end;

  procedure ShowGlobe(FileOfs : LongInt);         { texture for the sphere }
  var I : Integer;
  begin
    Seek(F, FileOfs);
    if not KeyPressed then BlockRead(F, VirtScr^, 64000);
    ClearScreen($A000, 0);
    for I := 1 to FadeSteps do begin FadeIn;  RenderFrame end;
    for I := 1 to FadeSteps do begin FadeOut; RenderFrame end;
  end;

begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  LoadTables;

  for I := 0 to 255 do SetRGB(I, 0, 0, 0);    { start from black }

  ShowFlat(ImgTitle);   ShowGlobe(ImgCity);
  ShowFlat(ImgTitle);   ShowGlobe(ImgFigures);
  ShowFlat(ImgTitle);   ShowGlobe(ImgDeth);

  Close(F);
  FreeMem(SrcOfs, TableSize);
  FreeMem(DstOfs, TableSize);
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
  NOTES

  * The globe costs one MOVSB per pixel and nothing else. All the geometry
    was baked into the two offset tables at build time, so the run-time code
    knows nothing about spheres.
  * 22,996 destination pixels drawn from 16,316 distinct source pixels: the
    same source pixel is read several times near the sphere's limb, which is
    exactly the foreshortening you want.
  * The scrolled band (rows 1..150, 300 bytes wide) matches the source
    coverage map exactly -- good evidence the two tables and the scroll were
    authored together.
  * Every loop is guarded by KeyPressed so the scene can be skipped mid-fade.

  RESOLVED
  * 119d:054f is an EMPTY PROCEDURE -- PUSH BP / MOV BP,SP / LEAVE / RETF and
    nothing else. A `procedure X; begin end;` that was never filled in.
  * The title image IS re-seeked and re-read from disk on every pass. That is
    simply what the code does; whether the authors meant it as a cheap way to
    reset the buffer or never noticed the cost is not a question the binary
    can answer.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
