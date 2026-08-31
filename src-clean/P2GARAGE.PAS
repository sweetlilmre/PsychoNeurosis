{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, scene 1: the garage.

  Segment 1008 in NEUROSIS_002_fpu.exe, transcribed in full -- every routine
  the scene reaches, read from the disassembly. No inference, no stubs.

  WHAT THE SCENE IS

  A 1280 x 200 painting sits across the four Mode-X planes. The scene pans
  right across it for 960 pixels, then stops in front of a garage door, and
  the door rolls up to reveal a night sky with fifty stars drifting across it.
  Then the palette brightens, the screen is blanked plane by plane, and the
  palette fades out.

  The door is not composited with the sky. The sky IS the door bitmap: as the
  door scrolls up out of its own buffer, a row of colour $80 is fed in at the
  bottom, and the stars are plotted into that $80 area before each blit and
  taken back out again afterwards. }

{ 286 instructions are permitted -- the star field packs a coordinate pair
  into one word with multi-bit shifts. }
{$G+}

unit P2GARAGE;

{ Variable alignment off -- a Word sits at an odd offset in this unit, which
  only byte alignment can produce. }
{$A-}


(* I/O CHECKING OFF: no runtime check after each file call, so a failed read
   is silent. That is the original's setting. *)
{$I-}

interface

procedure Scene1;

implementation

uses Crt, VGA, ModeX, DemoVT;

{ Where each asset sits inside NEUROSIS.DAT. }
{$I gen/DATOFS.INC}

const
  DoorW    = $92;               { 146 }
  DoorH    = $55;
  DoorSize = 2 + DoorW * DoorH; { $307C = 12,412, and that is the read length }

  SkyColour = $80;              { what Door_RaiseOneRow feeds in }

  NumStars  = $32;              { 50 stars                                }
  StarMaxX  = $92;              { 146 -- the field's width, and the wrap  }
  StarMaxY  = $55;              { 85 -- the field's height               }
  StarCols  = 3;                { plus the base below }
  StarCol0  = $19;              { 25 -- the first of the star colours    }

  { the CRTC Offset this scene runs at, giving a 1280-wide
    canvas. Scene1_Run pans X from 0 to $3C0 across it. }
  SceneWidth = $A0;
  PanEnd     = $3C0;            { 960 }

  { where the door is blitted. Bitmap_Blit adds its two X
    parameters, so the door lands at 960 + 92 = 1052, which is 92 pixels in
    from the left of the screen once the pan has finished. }
  DoorX    = $5C;
  DoorY    = $5E;
  DoorBase = $3C0;              { 960 }

  RaiseFrames  = $55;           { 85 -- one row per frame                }
  HoldFrames   = $19;           { 25 frames of hold                      }

  { the seek, as a LongInt pushed high word first. }
  DataOfs = DAT_P2_HOUSEPAL;   { $03BE36 }

type
  { A HEADER AND A TWO-DIMENSIONAL BITMAP, not a flat byte array. The star
    plotting computes its address as `IMUL DI, Star[I].Y, $92` then `ADD DI, AX`
    with Star[I].X in AX and a displacement of $0CB5, and there is no
    subtraction anywhere -- so both subscripts are folded, which Turbo Pascal
    only does for a subscript that is not an arithmetic expression. Two 1-based
    dimensions after a two-byte header put the fold at exactly $0CB5:
    $0D46 + 2 - $92 - 1. A flat array with `(Y - 1) * DoorW + (X - 1) + 2`
    written out computes all three corrections at run time, and wrapping that in
    a function costs a far call per pixel on top. }
  TDoor = record
    W, H : Byte;
    Pix  : array[1..DoorH, 1..DoorW] of Byte;
  end;
  TStar = record
    X, Y : Integer;
    C    : Byte;
  end;

var
  Door : TDoor;
  { 256 RGB triples. }
  Pal  : TPalette;
  { and the folded bases $40BD, $40BF and $40C1 are one stride
    below it: 50 records of five bytes, immediately after Pal's 768. Declared
    BEFORE Pal it took $3DC2 and pushed the palette 250 bytes up, which moved
    every one of the 31 folded reads. }
  Star : array[1..NumStars] of TStar;
  { 2,250 bytes NOTHING IN NEUROSIS.002 TOUCHES. Star ends at
    $41BB and the .DAT handle is at $4A86, and between them the original
    carries this much DGROUP that no absolute operand, no folded array base
    and no immediate anywhere in the part refers to. Its size and position are
    measured; what it was is not recoverable from the binary, because nothing
    names it. It is the same habit LoadFrames shows on the stack a few lines
    down -- ENTER $80 with not one slot read -- only at unit level, and it is
    the reason DatFile and everything above it sat 2,250 bytes low. }
  Dead1 : array[1..2250] of Byte;
  DatFile : file;
  { two more dead bytes. DatFile's 128 end at $4B05 and the next
    live variable is at $4B08, with alignment off, so these two are real and
    not padding. }
  Dead2 : array[1..2] of Byte;

{ The one-based pixel index Scene1_DoorLoop uses. }
{ DoorPix is gone: the original has no such routine and no call to one. Its
  arithmetic is now the declaration's, and the sites read Door.Pix[Y, X]. }

{ --------------------------------------------------------------------------
Bitmap_Blit(Src, XOfs, Y, XBase)

  A per-pixel Mode-X blit with colour 0 transparent. It takes the width and
  height out of the source's own first two bytes, then walks the row rotating
  the Map Mask one plane at a time and stepping the destination byte only when
  the mask wraps past plane 3.

      DI      := RowOfs[Y] + (X shr 2)
      X       := XBase + XOfs
      plane   := X and 3
      per row : DI := DI + $140 - (bytes advanced)

  $140 is 320, the plane-row stride, so each row simply restarts at
  RowOfs[Y + row] + (X shr 2) -- which is how it is written here.

  PARAMETER ORDER. RET $A, so a pointer and three words. Taking the highest
  BP offset as the first declared: Src at BP+$A, XOfs at BP+8, Y at BP+6,
  XBase at BP+4. Scene1_DoorLoop calls it (@Door, $5C, $5E, $3C0).

  The plane walk is the interesting part. Rather than recomputing
  `1 shl (X and 3)` per pixel, it keeps the mask in the high byte of BP and
  shifts it LEFT once per pixel. When it passes plane 3 the value reaches
  $1000, and SUB BP,$F00 brings it back to $100 -- plane 0 -- while INC DI
  steps the destination on by one byte. One shift, one compare, and the
  addressing falls out of it.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      P := Src;
      W := P^;  Inc(LongInt(P));
      H := P^;  Inc(LongInt(P));
      X := XBase + XOfs;
      D     := RowOfs[Y] + (X shr 2);
      Plane := X and 3;
      for R := 0 to H - 1 do
      begin
        Mask := Plane;
        for C := 0 to W - 1 do
        begin
          SelectPlane(Mask);
          if P^ <> 0 then Mem[VGASeg : D] := P^;
          Inc(LongInt(P));
          Inc(Mask);
          if Mask = 4 then begin Mask := 0; Inc(D) end;
        end;
        Inc(D, 320 - W div 4);
      end;

  That Pascal is close but not the same in two ways worth knowing. The
  original selects the plane BEFORE testing the pixel, so it writes the
  Sequencer even for transparent pixels; and its per-row correction is
  `320 - (W div 4) - (1 if the mask ended in plane 0 or 1)`, which is not
  expressible as one subtraction because it depends on where the mask
  happened to stop.
  -------------------------------------------------------------------------- }
procedure BlitBitmapX(Src : Pointer; XOfs, Y, XBase : Integer); assembler;
asm
  PUSH DS                 { DS points at the source below                   }
  PUSH BP                 { BP is about to become the plane mask            }
  MOV  AX, $A000          { video memory                                    }
  MOV  ES, AX             { ES:DI is the destination throughout             }
  MOV  BX, Y              { the top row                                     }
  SHL  BX, 1              { * 2, a word index                               }
  MOV  DI, [BX + OFFSET RowOfs]   { DI := RowOfs[Y] -- ModeX's table      }
  MOV  AX, XBase          { the pan base, $3C0                              }
  ADD  AX, XOfs           { + the bitmap's own X                            }
  LDS  SI, Src            { DS:SI := the bitmap, header first               }
  MOV  CX, AX             { keep the pixel X for the plane number           }
  SHR  AX, 2              { X div 4 -- four pixels to a byte offset         }
  ADD  DI, AX             { DI := the first destination byte                }
  AND  CX, 3              { CL := X mod 4 = the starting plane              }
  XOR  AL, AL             { AL := 0, so AX is a clean mask<<8 below         }
  MOV  AH, 1              { one bit, plane 0                                }
  SHL  AH, CL             { moved to the starting plane                     }
  MOV  BP, AX             { BP := the mask in its high byte                 }
  MOV  BH, AH             { and BH keeps the row's starting mask            }
  MOV  DX, $3C4           { Sequencer address register                      }
  MOV  AL, 2              { register 2 -- Map Mask                          }
  OUT  DX, AX             { select the first plane                          }
  LODSB                   { AL := the bitmap's width byte                   }
  MOV  BL, AL             { park it                                         }
  LODSB                   { AL := the height byte                           }
  MOV  CL, AL             { CL counts rows                                  }
  MOV  CH, BL             { CH holds the width                              }
  MOV  AL, AH             { overwritten at the top of @@Row         }
@@Row:                    { <- once per row of the bitmap                   }
  MOV  BL, CH             { BL counts the pixels across this row            }
  MOV  AL, BH             { the row's starting plane mask                   }
  SHL  AX, 8              { into the high byte                              }
  MOV  BP, AX             { BP := the live mask, ready for the Sequencer    }
@@Pixel:                  { <- once per pixel                               }
  MOV  AX, BP             { AH := the mask                                  }
  MOV  AL, 2              { AL := register 2, Map Mask                      }
  OUT  DX, AX             { enable just this plane                          }
  LODSB                   { AL := the source pixel; SI moves on             }
  OR   AL, AL             { colour 0?                                       }
  JZ   @@Skip             {   transparent -- draw nothing                   }
  STOSB                   { write it; DI moves on...                        }
  DEC  DI                 {   ...but it must not, so undo that. DI only     }
                          {   advances when the mask wraps past plane 3     }
@@Skip:                   { <- transparent pixels join here                 }
  SHL  BP, 1              { rotate the mask to the next plane               }
  CMP  BP, $1000          { has it passed plane 3?                          }
  JL   @@NoWrap           {   no                                            }
  SUB  BP, $F00           {   yes: $1000 back to $100, plane 0 again        }
  INC  DI                 {   and NOW the destination byte steps on         }
@@NoWrap:                 { <- both cases join here                         }
  DEC  BL                 { one pixel done                                  }
  JNZ  @@Pixel            { round again until the row is finished           }
  MOV  AX, CX             { CH still holds the width                        }
  SHR  AX, 8              { AX := the width                                 }
  SHR  AX, 2              { div 4 = whole bytes the row advanced            }
  CMP  BP, $200           { did the mask stop in plane 0 or 1?              }
  JG   @@NoExtra          {   no                                            }
  INC  AX                 {   yes: one more byte was consumed               }
@@NoExtra:                { <- both cases join here                         }
  ADD  DI, $140           { 320 -- one plane-row of the 1280-wide canvas    }
  SUB  DI, AX             { less what the row already advanced              }
  DEC  CL                 { one row done                                    }
  JNZ  @@Row              { round again until the bitmap is drawn           }
  POP  BP                 { BP is a frame pointer again                     }
  POP  DS                 { restore our data segment                        }
end;

{ --------------------------------------------------------------------------
Door_RaiseOneRow(Src)

      W  := lo(word at Src)            the header byte, $92
      copy $2FE8 bytes from Src+2+W to Src+2      all but the last row
      fill the last W bytes with $80              a fresh row of sky

  $2FE8 is 12,264 = 146 * 85 - 146. So the whole image shifts up one row and
  sky comes in at the bottom: the door rolling open.

  Note $2FE8 is a LITERAL in the original, not W * H - W computed from the
  header -- only the width comes out of the header, and only to size the sky
  row at the end. The height is baked in.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      W := Mem[Seg(Src^) : Ofs(Src^)];
      Move(Mem[Seg(Src^) : Ofs(Src^) + 2 + W],
           Mem[Seg(Src^) : Ofs(Src^) + 2], $2FE8);
      FillChar(Mem[Seg(Src^) : Ofs(Src^) + 2 + $2FE8], W, SkyColour);

  which is genuinely equivalent -- Move and FillChar are REP MOVSB and REP
  STOSB. It is assembler because the original is, and because the original
  does both with one pair of pointers instead of two calls.
  -------------------------------------------------------------------------- }
procedure DoorRaiseOneRow(Src : Pointer); assembler;
asm
  PUSH DS                 { DS points at the bitmap below                   }
  CLD                     { forwards -- this one really does set it         }
  LDS  SI, Src            { DS:SI := the bitmap, for reading                }
  LES  DI, Src            { ES:DI := the same bitmap, for writing           }
  ADD  DI, 2              { the destination is the FIRST pixel row          }
  LODSW                   { AX := the two header bytes; SI now at pixel 0   }
  XOR  AH, AH             { keep the width only                             }
  MOV  BX, AX             { park it -- the sky row below needs it           }
  ADD  SI, AX             { the source is one row further in                }
  MOV  CX, $2FE8          { 12,264 = 146 * 85 - 146, all but the last row   }
  REP  MOVSB              { slide the whole image up by one row             }
  MOV  CX, BX             { one row's worth of bytes                        }
  MOV  AX, $80            { the sky colour                                  }
  REP  STOSB              { and fill the row that came free at the bottom   }
  POP  DS                 { restore our data segment                        }
end;

{ --------------------------------------------------------------------------
Scene1_LoadFrames

  NEUROSIS.DAT from $0003BE36:

        768   palette bytes
     64,000   plane 0                      -> the staging buffer, then $A000
     64,000   plane 1
     64,000   plane 2
     64,000   plane 3
     12,412   the door bitmap

  Four planes of 64,000 bytes is 1280 x 200: 320 bytes per plane-row, 200
  rows. Each plane is read into the staging buffer and pushed across with
  CopyScreen while the Map Mask selects that plane.
  -------------------------------------------------------------------------- }
procedure LoadFrames;
var
  { ENTER $80 is 128 bytes and NOT ONE BP-relative slot is touched -- the
    handle is a global and the plane loop is unrolled, so nothing here is
    read. 128 bytes declared and never used, which is this unit's habit
    elsewhere too. }
  Unused : array[1..128] of Byte;
begin
  Assign(DatFile, 'neurosis.dat');
  Reset(DatFile, 1);
  Seek(DatFile, DataOfs);
  BlockRead(DatFile, Pal, 768);
  SelectPlane(0);
  BlockRead(DatFile, VirtScr^, 64000);
  CopyScreen(VirtScrSeg, VGASeg);
  SelectPlane(1);
  BlockRead(DatFile, VirtScr^, 64000);
  CopyScreen(VirtScrSeg, VGASeg);
  SelectPlane(2);
  BlockRead(DatFile, VirtScr^, 64000);
  CopyScreen(VirtScrSeg, VGASeg);
  SelectPlane(3);
  BlockRead(DatFile, VirtScr^, 64000);
  CopyScreen(VirtScrSeg, VGASeg);
  BlockRead(DatFile, Door, DoorSize);
  Close(DatFile);
end;

{ --------------------------------------------------------------------------
Scene1_Init

      blank the DAC (every colour to 0, 0, 0)
      LoadFrames
      write the loaded palette out, colour by colour
      Door[0] := $92 ; Door[1] := $55

  The DAC is blanked BEFORE the load so the panorama does not appear while it
  is being pushed into the planes; Palette_BrightenStep is what brings it up
  later. The two header bytes are set here rather than trusted from the file.
  -------------------------------------------------------------------------- }
procedure Init;
var
  Col : Byte;
begin
  for Col := 0 to 255 do
    SetRGB(Col, 0, 0, 0);

  LoadFrames;

  for Col := 0 to 255 do
    SetRGB(Col, Pal[Col, 0], Pal[Col, 1], Pal[Col, 2]);

  Door.W := DoorW;
  Door.H := DoorH;
end;


{ --------------------------------------------------------------------------
Palette_BrightenStep }
procedure PaletteBrightenStep;
var
  Spare1  : Integer;                 { never touched }
  Col     : Integer;
  B, G, R : Byte;                    { declared backwards -- see the note above }
  Spare2  : Byte;                    { never touched }
begin
  for Col := 0 to 255 do
  begin
    GetRGB(Col, R, G, B);
    if R < $3F then Inc(R);
    if G < $3F then Inc(G);
    if B < $3F then Inc(B);
    if R < $3F then Inc(R);
    if G < $3F then Inc(G);
    if B < $3F then Inc(B);
    if R < $3F then Inc(R);
    if G < $3F then Inc(G);
    if B < $3F then Inc(B);
    SetRGB(Col, R, G, B);
  end;
end;

{ --------------------------------------------------------------------------
Palette_FadeOut. This is the SCENE's own fade, not VGA's
  PaletteFadeOut -- it steps five per channel per pass and takes
  no delay parameter. Named SceneFadeOut here so the two do not collide.

      for Pass := 1 to $40 do
        WaitRetrace
        for Col := 0 to $FF do
          GetRGB; five rounds of "if above zero, drop by one"; SetRGB

  64 passes of -5 per channel.
  -------------------------------------------------------------------------- }
procedure SceneFadeOut;
var
  Pass, Col, K : Integer;
  B, G, R      : Byte;
begin
  for Pass := 1 to $40 do
  begin
    WaitRetrace;
    for Col := 0 to 255 do
    begin
      GetRGB(Col, R, G, B);
      for K := 1 to 5 do
      begin
        if R > 0 then Dec(R);
        if G > 0 then Dec(G);
        if B > 0 then Dec(B);
      end;
      SetRGB(Col, R, G, B);
    end;
  end;
end;

{ --------------------------------------------------------------------------
Scene1_DoorLoop

  Three phases, and the first two share the same body:

 85 frames: raise the door one row, plot the stars, blit,
                un-plot the stars, drift them right
 25 frames: the same minus the raise, plus one call to
                Palette_BrightenStep per frame
 clear the staging buffer and push it to all four planes,
                then Palette_FadeOut

  The star plot is conditional both ways round, and that is the whole trick:

      draw    if Door[star] = $80 then Door[star] := star colour
      erase   if Door[star] = star colour then Door[star] := $80

  A star is only drawn where the sky already is, so it never lands on the
  door itself, and it is only erased where it is still the colour it was
  drawn in -- so a star that got covered is left alone rather than punching a
  hole in the artwork.
  -------------------------------------------------------------------------- }
procedure DoorLoop;
var
  Frame  : Integer;
  Unread : LongInt;                    { four bytes, never read }
  I      : Integer;                    { 46 references }
begin
  for Frame := 0 to RaiseFrames do
  begin
    DoorRaiseOneRow(@Door);
    { DrawStars, inline }
    for I := 1 to NumStars do
      if Door.Pix[Star[I].Y, Star[I].X] = SkyColour then
        Door.Pix[Star[I].Y, Star[I].X] := Star[I].C;
    BlitBitmapX(@Door, DoorX, DoorY, DoorBase);
    { EraseStars, inline }
    for I := 1 to NumStars do
      if Door.Pix[Star[I].Y, Star[I].X] = Star[I].C then
        Door.Pix[Star[I].Y, Star[I].X] := SkyColour;
    { DriftStars, inline }
    for I := 1 to NumStars do
    begin
      Star[I].X := Star[I].X + 1;
      if Star[I].X > StarMaxX then Star[I].X := 1;
    end;
  end;

  { phase 2 -- hold, and bring the palette up. Same shape. }
  for Frame := 0 to HoldFrames do
  begin
    { DrawStars, inline }
    for I := 1 to NumStars do
      if Door.Pix[Star[I].Y, Star[I].X] = SkyColour then
        Door.Pix[Star[I].Y, Star[I].X] := Star[I].C;
    BlitBitmapX(@Door, DoorX, DoorY, DoorBase);
    { EraseStars, inline }
    for I := 1 to NumStars do
      if Door.Pix[Star[I].Y, Star[I].X] = Star[I].C then
        Door.Pix[Star[I].Y, Star[I].X] := SkyColour;
    { DriftStars, inline }
    for I := 1 to NumStars do
    begin
      Star[I].X := Star[I].X + 1;
      if Star[I].X > StarMaxX then Star[I].X := 1;
    end;
    PaletteBrightenStep;
  end;

  { phase 3 -- blank all four planes, then fade the palette out }
  ClearScreen(VirtScrSeg, 0);                  { once }
  { longhand, as LoadFrames does it -- the frame has no counter to spare }
  SelectPlane(0);  CopyScreen(VirtScrSeg, VGASeg);
  SelectPlane(1);  CopyScreen(VirtScrSeg, VGASeg);
  SelectPlane(2);  CopyScreen(VirtScrSeg, VGASeg);
  SelectPlane(3);  CopyScreen(VirtScrSeg, VGASeg);
  SceneFadeOut;
end;

{ --------------------------------------------------------------------------
Scene1_Run

      Init
      ShowFrame(0, 0)
      Delay($7D0)                          2000 ms
      MusicDetect  /  MusicCue  /  SyncPattern(5, 1)
      for X := 0 to $3C0 do                the pan, 960 pixels
        MusicPoll
        ShowFrame(X, 0)
      MusicStart
      Delay($7D0)
      seed the fifty stars
      DoorLoop

  The pan has no delay in it: one MusicPoll and one ShowFrame per step, and
  ShowFrame waits for vertical retrace, so the pan runs at the refresh rate --
  960 frames, about sixteen seconds at 60 Hz.
  -------------------------------------------------------------------------- }
procedure Run;
var
  Spare : Byte;                            { never touched }
  X     : Integer;                         { BOTH loops }
begin
  Init;
  ShowFrame(0, 0);
  Delay($7D0);

  MusicDetect;
  MusicCue;
  SyncPattern(5, 1);

  for X := 0 to PanEnd do
  begin
    MusicPoll;
    ShowFrame(X, 0);
  end;

  MusicStart;
  Delay($7D0);

  for X := 1 to NumStars do
  begin
    Star[X].X := Random(StarMaxX) + 1;
    Star[X].Y := Random(StarMaxY) + 1;
    Star[X].C := Random(StarCols) + StarCol0;
  end;

  DoorLoop;
end;

{ --------------------------------------------------------------------------
  Demo_Scene1

      LogicalWidth := $A0    the wide canvas -- 1280 pixels
      SetModeX               which programs the CRTC from it
      BuildRowTable          which uses it as the row multiplier
      Run

  The order matters: the width has to be in place before either of the other
  two reads it.
  -------------------------------------------------------------------------- }
procedure Scene1;
begin
  LogicalWidth := SceneWidth;
  SetModeX;
  BuildRowTable;
  Run;
end;

begin
end.
