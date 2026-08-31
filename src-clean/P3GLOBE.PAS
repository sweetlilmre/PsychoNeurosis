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
  makes the globe appear to turn. }

{$G+}   { 286: the original's procedures open with ENTER, a 286 instruction. }
{$I-}   { NO I/O CHECK, and this unit was the last of part 003's to be told so.
          Every other unit in the part already had it. The original follows each
          file call with nothing; ours followed all eighteen of them with a far
          call to System:04f4, the runtime's I/O result check, which $I+ --
          the default -- emits and $I- does not. Ninety bytes, and they were
          what displaced the runtime: this unit measured 1,456 bytes against the
          original's 1,376, P3Stars was sixteen over, and those ninety-six bytes
          moved System six paragraphs, so all thirty-four of part 003's
          remaining unaligned bytes were the low byte of a far-call operand.
          Nothing else in the segment differed -- every prologue was at an
          identical offset and the tail matched byte for byte, shifted. }

unit P3Globe;

interface

procedure Scene4;

implementation

uses VGA, Crt;

{ Where each asset sits inside NEUROSIS.DAT. }
{$I gen/DATOFS.INC}

const
  { All four screens share ONE palette, loaded once at the start of the scene.
    That is what lets them cross-fade into each other without a palette
    reload -- only the pixels change. }
  DataOfs     = DAT_P3_S4PAL;   { $0C0E2E -- palette + the two offset tables }
  PaletteSize = $300;         { 768 }
  TableSize   = $B3AA;        { 45994 bytes = 22997 words }
  Entries     = TableSize div 2;

  { The four full-screen images, in the order the scene uses them. }
  ImgTitle    = DAT_P3_S4SCRN1;   { $0D7882 -- "ReAl TiMe" gold lettering -- shown 3 times }
  ImgCity     = DAT_P3_S4SCRN2;   { $0E7282 -- city skyline against clouds }
  ImgFigures  = DAT_P3_S4SCRN3;   { $0F6C82 -- two figures against clouds }
  ImgDeth     = DAT_P3_S4SCRN4;   { $106682 -- fiery DETH logo }

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
  Palette_FadeOut
  The same shape, but every non-zero channel steps down toward black. No
  target table needed.
  -------------------------------------------------------------------------- }
procedure FadeOut;
var
  Unread  : Word;                 { never read }
  I       : Word;
  B, G, R : Byte;
  Spare   : Byte;                 { never read }
begin
  WaitRetrace;
  for I := 0 to 255 do
  begin
    GetRGB(I, R, G, B);
    { > 0, NOT <> 0. The original tests each component with CMP byte,0 / JBE
      (76 03); <> 0 compiles to JZ (74 03), the same two bytes with the wrong
      condition. For an unsigned Byte the two behave identically, so only the
      comparison against the 1994 image says which was written. }
    if R > 0 then Dec(R);
    if G > 0 then Dec(G);
    if B > 0 then Dec(B);
    SetRGB(I, R, G, B);
  end;
end;

{ --------------------------------------------------------------------------
  Demo_Scene4
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
  { DstOfs FIRST, so that SrcOfs lands at [link-$0A] and DstOfs at [link-$06].
    Pointers go down from BP in declaration order, four bytes each, so whichever
    is named first gets the HIGHER slot -- and the original's LoadTables stores
    its first GetMem result to [$0A]. Declared SrcOfs, DstOfs the two GetMem
    calls came out storing to the other one's slot, and so did the two FreeMem
    calls at the end of Scene4, which is why the unit's last two call pairs were
    in the opposite order from the original. One declaration, two sites. }
  DstOfs, SrcOfs : ^TOffsets;      { two GetMem'd 45994-byte tables }
  { TWO HUNDRED AND FIFTY-SIX TRIPLES, NOT 768 FLAT BYTES, and the instruction
    stream is what says so. FadeIn's three loads are ss:[di-$030a],
    ss:[di-$0309] and ss:[di-$0308] -- the component offset is folded into the
    DISPLACEMENT and there is no arithmetic for it at all. Written flat as
    Target[I * 3 + 1] the compiler evaluates the whole subscript instead and
    emits INC AX, then INC AX twice for the third, keeping one displacement:
    three bytes the original does not spend. A constant second subscript folds;
    a constant added to the first does not. Same 768 bytes, same $30A slot, and
    BlockRead still fills it in one call. }
  Target         : array[0..255] of array[0..2] of Byte;

  { --------------------------------------------------------------------------
    Palette_FadeIn
    Read each DAC entry back, step any channel that is below its target up by
    one, write it out. Called 64 times, which is the full 6-bit range.
    -------------------------------------------------------------------------- }
  procedure FadeIn;
  var
    Unread     : Word;              { never read }
    I          : Word;
    B, G, R    : Byte;
    Spare      : Byte;              { never read }
  begin
    if KeyPressed then Exit;
    WaitRetrace;
    for I := 0 to 255 do
    begin
      GetRGB(I, R, G, B);
      { Target[I][c] and never Target[I * 3 + c] -- see the declaration's note.
        The first subscript multiplies by the element size, three, exactly as
        the flat form did; the second is a constant and folds away. }
      if R < Target[I][0] then Inc(R);
      if G < Target[I][1] then Inc(G);
      if B < Target[I][2] then Inc(B);
      SetRGB(I, R, G, B);
    end;
  end;

{ --------------------------------------------------------------------------
  Globe_LoadTables
  ASSETS  NEUROSIS.DAT $0C0E2E, 92,756 bytes in three reads:
            assets/part003/S4PAL.PAL      768 B, shared by all four
                                                   images -- see note above
            assets/part003/GLOBESRC.BIN   45,994 B, source offsets
            assets/part003/GLOBEDST.BIN   45,994 B, destination offsets
          Coverage maps (generated, not in the demo):
            assets/part003/GLBWRPDS.PNG      a filled disc, 22,996 px
            assets/part003/GLBWRPSR.PNG      a 300x150 band, 16,316 px
          The destination is a disc and the source a rectangle sampled
          many-to-one at the edges: that is a sphere map.
          See docs/10-part3-scene4-globe.md.
  -------------------------------------------------------------------------- }
  procedure LoadTables;
  var
    Unread : array[0..127] of Byte;
  begin
    GetMem(SrcOfs, TableSize);                 { -> SS:[link-$0A] }
    GetMem(DstOfs, TableSize);                 { -> SS:[link-$06] }
    BlockRead(F, Target,  PaletteSize);        { SS:[link-$30A]  }
    BlockRead(F, SrcOfs^, TableSize);
    BlockRead(F, DstOfs^, TableSize);
  end;

{ --------------------------------------------------------------------------
  Globe_RenderFrame
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
  procedure RenderFrame;
  var
    { -- RenderFrame's OWN two words: the segments of
      the parent's two tables, copied down here once so the loop can reload DS
      from a register three times a pixel. }
    SrcSeg, DstSeg : Word;
    Unread         : Word;
  begin
    { the frame is abandoned the moment a key is down. }
    if KeyPressed then Exit;

    SrcSeg := Seg(SrcOfs^);
    DstSeg := Seg(DstOfs^);

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
    ADD  SI, ScrollSkip
    DEC  BX                      { one row done                                 }
    JNZ  @Row                    { round again until all 150 are shifted        }
    POP  DS                      { restore our data segment                     }
    end;
  end;


{  So they are written out. The `I` they each declared is the scene's own now,
  which is also why the scene's frame did not move. }
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  LoadTables;

  for I := 0 to 255 do SetRGB(I, 0, 0, 0);    { start from black }

  { ---- ShowFlat(ImgTitle) ---- }
  Seek(F, ImgTitle);
  BlockRead(F, VirtScr^, 64000);
  if not KeyPressed then CopyScreen(VirtScrSeg, $A000);
  ClearScreen(VirtScrSeg, 0);
  for I := 1 to FadeSteps do FadeIn;
  if not KeyPressed then Delay(HoldMs);
  for I := 1 to FadeSteps do FadeOut;

  { ---- ShowGlobe(ImgCity) ---- }
  Seek(F, ImgCity);
  if not KeyPressed then BlockRead(F, VirtScr^, 64000);
  ClearScreen($A000, 0);
  for I := 1 to FadeSteps do begin FadeIn;  RenderFrame end;
  for I := 1 to FadeSteps do begin FadeOut; RenderFrame end;

  { ---- ShowFlat(ImgTitle) ---- }
  Seek(F, ImgTitle);
  if not KeyPressed then BlockRead(F, VirtScr^, 64000);
  if not KeyPressed then CopyScreen(VirtScrSeg, $A000);
  ClearScreen(VirtScrSeg, 0);
  for I := 1 to FadeSteps do FadeIn;
  if not KeyPressed then Delay(HoldMs);
  for I := 1 to FadeSteps do FadeOut;

  { ---- ShowGlobe(ImgFigures) ---- }
  Seek(F, ImgFigures);
  if not KeyPressed then BlockRead(F, VirtScr^, 64000);
  ClearScreen($A000, 0);
  for I := 1 to FadeSteps do begin FadeIn;  RenderFrame end;
  for I := 1 to FadeSteps do begin FadeOut; RenderFrame end;

  { ---- ShowFlat(ImgTitle) ---- }
  Seek(F, ImgTitle);
  if not KeyPressed then BlockRead(F, VirtScr^, 64000);
  if not KeyPressed then CopyScreen(VirtScrSeg, $A000);
  ClearScreen(VirtScrSeg, 0);
  for I := 1 to FadeSteps do FadeIn;
  if not KeyPressed then Delay(HoldMs);
  for I := 1 to FadeSteps do FadeOut;

  { ---- ShowGlobe(ImgDeth) ---- }
  Seek(F, ImgDeth);
  if not KeyPressed then BlockRead(F, VirtScr^, 64000);
  ClearScreen($A000, 0);
  for I := 1 to FadeSteps do begin FadeIn;  RenderFrame end;
  for I := 1 to FadeSteps do begin FadeOut; RenderFrame end;

  Close(F);
  FreeMem(SrcOfs, TableSize);
  FreeMem(DstOfs, TableSize);
end;

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

  OPEN
  * Nothing outstanding.
  =========================================================================== }
