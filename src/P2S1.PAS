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
  taken back out again afterwards.

  ROUTINE MAP

      Demo_Scene1           1008:0724
      Scene1_Run            1008:066f
      Scene1_Init           1008:01c7
      Scene1_LoadFrames     1008:00b9
      Scene1_DoorLoop       1008:0362
      Bitmap_Blit           1008:0000
      Door_RaiseOneRow      1008:0086
      Palette_BrightenStep  1008:0246
      Palette_FadeOut       1008:02de
  =========================================================================== }

{$G+}   { 286 instructions: 1008:0045 is SHL AX,8 and 1008:0069 SHR AX,8
          in the blit. The original targets 386 and above. }

unit P2S1;

(* I/O CHECKING OFF. Under the default {$I+} Turbo Pascal emits a far CALL to
   the runtime's check after every I/O operation that can fail, and the
   original has none: 1008:00d3 calls Reset and 1008:00d8 goes straight on to
   the next argument setup. Measured -- adding this removed exactly that call.
   The command-line form does NOT work here: /$I- was added to build.toml's
   switch line and the extra call was still emitted, so it was taken out again
   rather than left sitting in the config looking effective. *)
{$I-}

interface

procedure Scene1;

implementation

uses Crt, VGA, ModeX, DemoVT;

const
  { 1008:023a / 1008:023f -- Scene1_Init stores these into the door bitmap's
    own two header bytes at DS:$0D46. }
  DoorW    = $92;               { 146 }
  DoorH    = $55;               { 85 }
  DoorSize = 2 + DoorW * DoorH; { $307C = 12,412, and that is the read length }

  SkyColour = $80;              { 1008:00a2 -- what Door_RaiseOneRow feeds in }

  NumStars  = $32;              { 50   -- 1008:0719 }
  StarMaxX  = $92;              { 146  -- 1008:06d1 and the wrap at 1008:0497 }
  StarMaxY  = $55;              { 85   -- 1008:06eb }
  StarCols  = 3;                { 1008:0700, plus the base below }
  StarCol0  = $19;              { 25   -- 1008:0707 }

  { 1008:0727 -- the CRTC Offset this scene runs at, giving a 1280-wide
    canvas. Scene1_Run pans X from 0 to $3C0 across it. }
  SceneWidth = $A0;
  PanEnd     = $3C0;            { 960 }

  { 1008:03ef -- where the door is blitted. Bitmap_Blit adds its two X
    parameters, so the door lands at 960 + 92 = 1052, which is 92 pixels in
    from the left of the screen once the pan has finished. }
  DoorX    = $5C;               { 92 }
  DoorY    = $5E;               { 94 }
  DoorBase = $3C0;              { 960 }

  RaiseFrames  = $55;           { 85 -- 1008:04b6, one row per frame }
  HoldFrames   = $19;           { 25 -- 1008:060a }

  { 1008:00df -- the seek, as a LongInt pushed high word first. }
  DataOfs = $0003BE36;

type
  TDoor = array[0..DoorSize - 1] of Byte;
  TStar = record
    X, Y : Integer;
    C    : Byte;
  end;

var
  { DS:$0D46 -- two header bytes then DoorW * DoorH pixels. The star plotting
    at 1008:03a4 indexes it as [$0CB5 + X + Y * $92] with X and Y both
    ONE-BASED, and $0D46 - $0CB5 = $91, so that lands on pixel (X, Y) with the
    two-byte header skipped. DoorPix below is that same arithmetic. }
  Door : TDoor;
  { DS:$40BD, $40BF, $40C1 -- stride 5, indices 1..50. }
  Star : array[1..NumStars] of TStar;
  { DS:$3DC2 -- 256 RGB triples. }
  Pal  : array[0..767] of Byte;
  { DS:$4A86 -- the .DAT handle is a GLOBAL, not a local of LoadFrames.
    1008:00bd is `MOV DI,$4A86 / PUSH DS / PUSH DI` for every one of Assign,
    Reset, Seek, BlockRead and Close; a local would be
    `LEA DI,[BP-n] / PUSH SS / PUSH DI`. }
  DatFile : file;

{ The one-based pixel index Scene1_DoorLoop uses. }
function DoorPix(X, Y : Integer) : Word;
begin
  DoorPix := 2 + (X - 1) + (Y - 1) * DoorW;
end;

{ --------------------------------------------------------------------------
  1008:0000 -- Bitmap_Blit(Src, XOfs, Y, XBase)

  A per-pixel Mode-X blit with colour 0 transparent. It takes the width and
  height out of the source's own first two bytes, then walks the row rotating
  the Map Mask one plane at a time and stepping the destination byte only when
  the mask wraps past plane 3.

      DI      := RowOfs[Y] + (X shr 2)
      X       := XBase + XOfs             1008:0013 adds BP+4 to BP+8
      plane   := X and 3
      per row : DI := DI + $140 - (bytes advanced)

  $140 is 320, the plane-row stride, so each row simply restarts at
  RowOfs[Y + row] + (X shr 2) -- which is how it is written here.

  PARAMETER ORDER. RET $A, so a pointer and three words. Taking the highest
  BP offset as the first declared: Src at BP+$A, XOfs at BP+8, Y at BP+6,
  XBase at BP+4. Scene1_DoorLoop calls it (@Door, $5C, $5E, $3C0).

  HAND ASSEMBLER, transcribed verbatim. Like P2View's FillRect it uses BP as
  a scratch register -- BP holds the Map Mask shifted up a byte, so the whole
  16-bit Sequencer write is one MOV AX,BP away -- which is why it pushes BP
  at the top and why nothing after 1008:002d can name a parameter.

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
{ @asm 002 1008:002d }
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
  MOV  AL, AH             { dead -- overwritten at the top of @@Row         }
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
  1008:0086 -- Door_RaiseOneRow(Src)

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
{ @asm 002 1008:0086 }
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
  1008:0246 -- Palette_BrightenStep

  For every colour 0..255: GetRGB, then THREE rounds of "if the channel is
  below $3F, bump it" on each of R, G and B, then SetRGB. So +3 per call,
  clamped at $3F. The three rounds are written out longhand in the original
  (1008:026c through 1008:02ba) rather than looped.
  -------------------------------------------------------------------------- }
procedure PaletteBrightenStep;
var
  Col, K  : Integer;
  R, G, B : Byte;
begin
  for Col := 0 to 255 do
  begin
    GetRGB(Col, R, G, B);
    for K := 1 to 3 do
    begin
      if R < $3F then Inc(R);
      if G < $3F then Inc(G);
      if B < $3F then Inc(B);
    end;
    SetRGB(Col, R, G, B);
  end;
end;

{ --------------------------------------------------------------------------
  1008:02de -- Palette_FadeOut. This is the SCENE's own fade, not VGA's
  PaletteFadeOut (1491:0330) -- it steps five per channel per pass and takes
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
  R, G, B      : Byte;
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
  1008:00b9 -- Scene1_LoadFrames

  NEUROSIS.DAT from $0003BE36:

        768   palette                      -> DS:$3DC2
     64,000   plane 0                      -> the staging buffer, then $A000
     64,000   plane 1
     64,000   plane 2
     64,000   plane 3
     12,412   the door bitmap              -> DS:$0D46

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
  { THE FOUR PLANES ARE WRITTEN OUT LONGHAND, not looped: 1008:00fd, 0127 and
    the two after them push the literals 0, 1, 2 and 3 into SelectPlane. A
    `for P := 0 to 3` needs a counter and the frame has no room for one. }
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
  1008:01c7 -- Scene1_Init

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
  Col : Integer;
begin
  for Col := 0 to 255 do
    SetRGB(Col, 0, 0, 0);

  LoadFrames;

  for Col := 0 to 255 do
    SetRGB(Col, Pal[Col * 3], Pal[Col * 3 + 1], Pal[Col * 3 + 2]);

  Door[0] := DoorW;
  Door[1] := DoorH;
end;

{ --------------------------------------------------------------------------
  1008:0362 -- Scene1_DoorLoop

  Three phases, and the first two share the same body:

    1008:036d   85 frames: raise the door one row, plot the stars, blit,
                un-plot the stars, drift them right
    1008:04c6   25 frames: the same minus the raise, plus one call to
                Palette_BrightenStep per frame
    1008:0613   clear the staging buffer and push it to all four planes,
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
  { ENTER $08 is eight bytes: the frame counter, FOUR BYTES NOBODY READS, and
    the star index. 1008:0362's slots are [BP-$02] with 6 references and
    [BP-$08] with 46, and nothing touches [BP-$04] or [BP-$06]. The star
    loops are INLINED here -- there is no DrawStars, EraseStars or DriftStars
    routine in the original, which is why the same 167-byte block recurs at
    1008:039a, 0441, 04eb and 0592. }
  Frame  : Integer;                    { [BP-$02] }
  Unread : LongInt;                    { [BP-$06], four bytes, never read }
  I      : Integer;                    { [BP-$08], 46 references }
begin
  { phase 1 -- the door rolls up. A `for`, NOT a `repeat`: the original's
    counter is incremented on the loop's BACK EDGE, after the test -- 1008:060a
    compares [BP-$02] and only then reaches the INC -- which is exactly how
    Turbo Pascal lays out `for`. Written as `repeat ... Inc(Frame) until` the
    increment lands BEFORE the compare, and the loop also ran one iteration
    short: `for Frame := 0 to $55` turns 86 times, not 85. }
  for Frame := 0 to RaiseFrames do
  begin
    DoorRaiseOneRow(@Door);
    { DrawStars, inline }
    for I := 1 to NumStars do
      if Door[DoorPix(Star[I].X, Star[I].Y)] = SkyColour then
        Door[DoorPix(Star[I].X, Star[I].Y)] := Star[I].C;
    BlitBitmapX(@Door, DoorX, DoorY, DoorBase);
    { EraseStars, inline }
    for I := 1 to NumStars do
      if Door[DoorPix(Star[I].X, Star[I].Y)] = Star[I].C then
        Door[DoorPix(Star[I].X, Star[I].Y)] := SkyColour;
    { DriftStars, inline }
    for I := 1 to NumStars do
    begin
      Inc(Star[I].X);
      if Star[I].X > StarMaxX then Star[I].X := 1;
    end;
  end;

  { phase 2 -- hold, and bring the palette up. Same shape. }
  for Frame := 0 to HoldFrames do
  begin
    { DrawStars, inline }
    for I := 1 to NumStars do
      if Door[DoorPix(Star[I].X, Star[I].Y)] = SkyColour then
        Door[DoorPix(Star[I].X, Star[I].Y)] := Star[I].C;
    BlitBitmapX(@Door, DoorX, DoorY, DoorBase);
    { EraseStars, inline }
    for I := 1 to NumStars do
      if Door[DoorPix(Star[I].X, Star[I].Y)] = Star[I].C then
        Door[DoorPix(Star[I].X, Star[I].Y)] := SkyColour;
    { DriftStars, inline }
    for I := 1 to NumStars do
    begin
      Inc(Star[I].X);
      if Star[I].X > StarMaxX then Star[I].X := 1;
    end;
    PaletteBrightenStep;
  end;

  { phase 3 -- blank all four planes, then fade the palette out }
  ClearScreen(VirtScrSeg, 0);                  { 1008:0619, once }
  { longhand, as LoadFrames does it -- the frame has no counter to spare }
  SelectPlane(0);  CopyScreen(VirtScrSeg, VGASeg);
  SelectPlane(1);  CopyScreen(VirtScrSeg, VGASeg);
  SelectPlane(2);  CopyScreen(VirtScrSeg, VGASeg);
  SelectPlane(3);  CopyScreen(VirtScrSeg, VGASeg);
  SceneFadeOut;
end;

{ --------------------------------------------------------------------------
  1008:066f -- Scene1_Run

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
  X, I : Integer;
begin
  Init;                                    { 1008:0673 }
  ShowFrame(0, 0);                         { 1008:067a }
  Delay($7D0);                             { 1008:0682 }

  MusicDetect;                             { 1008:0687 -> 13f9:0000 }
  MusicCue;                                { 1008:068c -> 13f9:0085 }
  SyncPattern(5, 1);                       { 1008:0695 -> 13f9:00ca }

  for X := 0 to PanEnd do
  begin
    MusicPoll;                             { 1008:06a4 -> 13f9:0040 }
    ShowFrame(X, 0);
  end;

  MusicStart;                              { 1008:06ba -> 13f9:004e }
  Delay($7D0);                             { 1008:06c2 }

  for I := 1 to NumStars do
  begin
    Star[I].X := Random(StarMaxX) + 1;     { 1008:06d1 }
    Star[I].Y := Random(StarMaxY) + 1;     { 1008:06eb }
    Star[I].C := Random(StarCols) + StarCol0;
  end;

  DoorLoop;                                { 1008:071f }
end;

{ --------------------------------------------------------------------------
  1008:0724 -- Demo_Scene1

      DS:$0002 := $A0        the wide canvas
      SetModeX               107c:006d, which writes that to CRTC $13
      BuildRowTable          107c:0000, which uses it as the row multiplier
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

end.
