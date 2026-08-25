{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.004, "Lemmings"
  Reconstructed from NEUROSIS_004.exe, segment 1005, in full.

  A hillside with up to 25 lemmings walking, falling, tunnelling, building
  and exploding across it, a message scrolling underneath, and two little
  animations either side of it. It runs until you press a key -- and then it
  keeps running until the music has faded out.

  THE TERRAIN IS THE ARTWORK. There is no separate collision map: a lemming
  decides whether to walk, climb, turn, fall or die by READING PIXELS out of
  the background screen with GetPixel, and two 32-byte colour sets say what
  each pixel means. Which is why part 004's VGA unit is the only one in the
  demo with a pixel read in it.

  It follows that everything which digs or builds does so by DRAWING into
  that background: the basher and the miner erase with colour 0, the builder
  lays bricks in colour $4D, and a lemming that splats stamps its last frame
  permanently into the hillside. The level is progressively destroyed and the
  destruction is the collision state.

  ADDRESS MAP
    Demo_Main            1005:1cd6   Setup                1005:1c9a
    LoadAssets           1005:00a6   Intro                1005:0a86
    MainLoop             1005:1bbb   UpdateAll            1005:1a4c
    ColumnSlideIn        1005:0000   BackdropAnim         1005:0a4f
    InitAll              1005:06c8   Spawn                1005:06e7
    Remove               1005:07d8   SetState             1005:0b22
    DrawSprite           1005:03b9   Blit                 1005:037a
    VLine                1005:0328   HLine                1005:0354
    CopyScreen           1005:0835   ScrollRender         1005:07f9
    ScrollChar           1005:0853   ScrollStep           1005:08ad
    Walker    (state 1)  1005:14d6   Faller    (state 2)  1005:0b68
    Fuse      (state 3)  1005:18fc   Digger    (state 4)  1005:0df5
    Builder   (state 5)  1005:0d1a   DeathA    (state 6)  1005:1850
    DeathB    (state 7)  1005:18a6   Splat     (state 8)  1005:17ff
    Tunneller (state 10) 1005:1166   Explode   (state 11) 1005:1954

  A NOTE ON TWO NAMES. Ghidra calls state 4 "Basher" and state 10 "Miner".
  Read against what they do, they are the other way round: state 4 advances
  X by two AND Y by one per bite, so it digs DIAGONALLY -- a Lemmings miner;
  state 10 advances X only, so it tunnels HORIZONTALLY -- a Lemmings basher.
  They are called Digger and Tunneller here to avoid inheriting the mix-up.

  There is no 386 code anywhere in part 004, so unlike parts 001, 002 and 005
  there is no TASM object to link.
  =========================================================================== }

{$G+}   { 286 instructions: SHL BX,1 with an immediate in the blits. }

unit Part4Lemmings;
{$A-}   { DATA ALIGNMENT OFF. The scroller's constants run contiguously in the
          original -- Message $0005 for 237 bytes, ScrollCol $00F2, ScrollIdx
          $00F4, ScrollPal $00F5 -- and 237 is odd. Under TP7's $A+ default the
          message is padded to 238 and everything after it is one byte out. }

interface

procedure RunPart4;

implementation

uses Crt, VGA, DemoVT;

const
  MaxLem     = 25;            { 1005:06c8 clears 1..25 }
  SpawnLimit = $50;           { 80 -- 1005:06ee, then Spawn does nothing }
  SpawnEvery = 20;            { 1005:1c33 -- a spawn every 20th frame }

  { 1005:06e7 -- where they come out of the hatch. }
  SpawnX     = $23;           { 35 }
  SpawnY     = $3C;           { 60 }

  { The states, as the byte at record +13. State 9 is reachable and has NO
    handler -- see Walker. }
  StWalker    = 1;
  StFaller    = 2;
  StFuse      = 3;
  StDigger    = 4;            { diagonal }
  StBuilder   = 5;
  StDeathA    = 6;
  StDeathB    = 7;
  StSplat     = 8;
  StStuck     = 9;            { no handler exists }
  StTunneller = 10;           { horizontal }
  StExplode   = 11;

  BrickColour = $4D;          { 1005:0d5e -- and it is in both terrain sets }
  ScrollRows  = 18;           { the scroller is 18 pixels tall }
  ScrollPitch = $155;         { 341 bytes per row: 320 visible + 21 ahead }
  ScrollSize  = ScrollRows * ScrollPitch;      { $17FA = 6138 }
  ScrollEdge  = 320;          { new pixels are fed in at column 320 }
  GlyphPitch  = $17A;         { 378 bytes per character = 21 columns of 18 }
  GlyphCols   = 21;
  FirstChar   = 32;           { the font starts at space }
  GlyphCount  = 62;           { 23436 / 378 -- space to ']' }
  TextLen     = $ED;          { 237 -- ScrollStep's own bound }

  DataOfs     = $001228CE;    { NEUROSIS.DAT -- 1,189,070 }

type
  { 21 bytes -- DS:$0311, indices 1..25, running to DS:$051D. }
  TLem = record
    X, Y       : Integer;     { +0, +2  }
    Bounces    : Integer;     { +4  -- a second hard landing splats }
    Frame      : Integer;     { +6  -- one-based, indexes the sprite banks }
    Tick       : Integer;     { +8  -- sub-frame counter }
    Timer      : Integer;     { +10 -- >0 counts down to a fuse,
                                       <0 counts up to removal }
    Active     : Byte;        { +12 -- 0 means the slot is free }
    State      : Byte;        { +13 }
    Dir        : ShortInt;    { +14 -- +1 right, -1 left }
    FallDist   : Byte;        { +15 -- 4+ switches to the tumbling sprite,
                                       11+ makes the landing fatal }
    TrigX      : Integer;     { +16 } { reach (TrigX, TrigY) and the lemming }
    TrigY      : Integer;     { +18 } {   is forced into TrigState           }
    TrigState  : Byte;        { +20 }
  end;

  TPal768 = array[0..767] of Byte;

var
  { DS:$0311 }
  Lem        : array[1..MaxLem] of TLem;
  { DS:$051E and DS:$0520 }
  LiveCount  : Integer;
  Spawned    : Integer;

  { The two screens. VirtScrSeg (VGA, DS:$CF8C here) holds the hillside and is
    what GetPixel reads; this one is composed into each frame. DS:$0305 and
    DS:$030D. }
  WorkScr    : Pointer;
  WorkSeg    : Word;

  { DS:$0309 -- 18 rows of 341, the scroller's own bitmap. }
  ScrollBuf  : Pointer;


  { DS:$030F and DS:$0310 -- the two background animations' counters. }
  SideTick   : Byte;
  HillTick   : Byte;

  { DS:$0304 -- the tracker volume as we found it. }
  SavedVol   : Byte;

  { DS:$0002 -- a 32-bit count of frames drawn, bumped by MainLoop with
    ADD [0002],1 / ADC [0004],0. NOTHING IN PART 004 EVER READS IT, and it is
    kept because the original keeps it. }
  FrameCount : LongInt;

  { DS:$0172 -- ColumnSlideIn's per-column start offset, 201 entries. }
  ColOfs     : array[0..200] of Integer;

  { DS:$CC07 -- the scene palette, which Explode fades entries $E0..$E9 up
    towards. }
  ScenePal   : TPal768;

{ --------------------------------------------------------------------------
  THE ASSETS.  Lemmings_LoadAssets (1005:00a6) seeks $001228CE and reads
  twenty blocks. Every sprite bank is indexed ONE-BASED, which is why the
  original's instructions carry base - stride and the addresses look wrong
  until you allow for it.

    assets/part004/scroll_font.bin        23436  62 glyphs of 21 x 18
    assets/part004/title_screen.pal          768
    assets/part004/title_screen.bin        64000  the picture the columns
                                                  slide in to make
    assets/part004/hillside.bin            64000  the level, and the
                                                  collision map
    assets/part004/hillside.pal              768
    assets/part004/scene.pal                 768  DS:$CC07
    assets/part004/lem_walk.bin              432  8 frames of 6 x 9
    assets/part004/lem_tumble.bin            400  4 frames of 10 x 10
    assets/part004/lem_splat.bin             480  4 frames of 12 x 10
    assets/part004/lem_dig.bin              1326  6 frames of 17 x 13
    assets/part004/lem_tunnel.bin            420  3 frames of 14 x 10
    assets/part004/lem_deathb.bin            800  5 frames of 16 x 10
    assets/part004/hill_anim.bin            3096  3 frames of 43 x 24
    assets/part004/lem_deatha.bin            648  6 frames of 9 x 12
    assets/part004/lem_build.bin             720  6 frames of 12 x 10
    assets/part004/lightning.png            3180  one 60 x 53 picture
    assets/part004/intro_anim.bin          10920  7 frames of 65 x 24
    assets/part004/side_anim.bin             840  6 frames of 14 x 10
    assets/part004/explosion.bin           24255  7 frames of 63 x 55
    assets/part004/lem_fuse.bin              750  5 frames of 10 x 15
  -------------------------------------------------------------------------- }
type
  TFont     = array[0..GlyphCount * GlyphPitch - 1] of Byte;   { DS:$CC03 }
var
  Font      : ^TFont;
  WalkBank  : array[1..8]  of array[0..53]   of Byte;   { DS:$0522 }
  TumbleBk  : array[1..4]  of array[0..99]   of Byte;   { DS:$06D2 }
  SplatBank : array[1..4]  of array[0..119]  of Byte;   { DS:$12B8 }
  DigBank   : array[1..6]  of array[0..220]  of Byte;   { DS:$1498 }
  TunnelBk  : array[1..3]  of array[0..139]  of Byte;   { DS:$19C6 }
  DeathBBk  : array[1..5]  of array[0..159]  of Byte;   { DS:$1B6A }
  DeathABk  : array[1..6]  of array[0..107]  of Byte;   { DS:$1E8A }
  BuildBank : array[1..6]  of array[0..119]  of Byte;   { DS:$2112 }
  FuseBank  : array[1..5]  of array[0..149]  of Byte;   { DS:$23E2 }
  DeathAPic : array[0..3179] of Byte;    { DS:$BF97 -- 60 x 53, the storm
                                           cloud and its lightning bolt }
  Explosion : array[1..7]  of array[0..3464] of Byte;   { DS:$26D0 }
  HillAnim  : array[1..3]  of array[0..1031] of Byte;   { DS:$858F }
  IntroAnim : array[1..7]  of array[0..1559] of Byte;   { DS:$91A7 }
  SideAnim  : array[1..6]  of array[0..139]  of Byte;   { DS:$BC4F }

{ --------------------------------------------------------------------------
  THE TWO TERRAIN SETS, read out of the code segment at 1005:0B48 / 1005:1496
  (ground) and 1005:0DD5 / 1005:1146 / 1005:14B6 (wall). Five references, two
  distinct 32-byte constants, and they differ by exactly one run:

      ground  [4,5, $0F, $15..$18, $1D, $1F, $33, $36,
               $3E..$40, $42..$47, $4D..$52]
      wall    the same PLUS [$20..$29]

  So $20..$29 is a hazard stripe: it BLOCKS you but you cannot STAND on it,
  and the walker and faller both kill on touching it. $4D is in both, which
  is the builder's brick colour -- bricks are solid and walkable.
  -------------------------------------------------------------------------- }
const
  Ground : set of Byte =
    [4, 5, $0F, $15..$18, $1D, $1F, $33, $36, $3E..$40, $42..$47, $4D..$52];
  Wall   : set of Byte =
    [4, 5, $0F, $15..$18, $1D, $1F, $20..$29, $33, $36, $3E..$40, $42..$47,
     $4D..$52];

  { 1005:14fa and 1005:0b8e -- two single colours the walker treats specially,
    outside either set. }
  DeathAColour = 3;
  StuckColour  = $12;

{ --------------------------------------------------------------------------
  DS:$00F2 to DS:$010C -- INITIALISED DATA, twenty-eight bytes read straight
  out of the image:

    00 00 | 01 | 07 07 07  07 07 07  07 07 07  07 07 07
                 1E 1E 1E  1E 1E 1E  1E 1E 1E  1E 1E 1E

  They are typed constants rather than variables because the values matter and
  nothing ever puts them back: ScrollStep rotates the palette in place from the
  first frame onwards, and MainLoop's ending counts it down towards black.

  ScrollCol starts at 0 and ScrollIdx at 1, so the message starts at character
  one and not at the #0 sitting in front of it.

  THE EIGHT TRIPLES ARE THE CONVEYOR BELT. They are written to DAC entries
  $80..$87 every frame, rotated by one, and the belt across the top of the
  hillside is drawn in exactly those eight colours -- four at intensity 7 and
  four at 30, so rotating them runs a light band along it and the belt appears
  to turn. Leaving them at zero, which is what a plain `var` gives you, writes
  black into $80..$87 and the belt simply is not there.
  -------------------------------------------------------------------------- }

{ DS:$0005 -- the message, compiled into DGROUP. Element 0 is a zero byte and
  ScrollStep indexes from 1; the $ED bound it tests is exactly this length. }
const
  Message : array[0..TextLen - 1] of Char = (
    #0,
    ' ','F','O','R',' ','T','H','O','S','E',' ','O','F',' ','Y','O','U',' ',
    'T','H','A','T',' ','R','E','A','L','L','Y',' ','H','A','T','E',' ','L',
    'O','N','G',',',' ','B','O','R','I','N','G',' ','S','C','R','O','L','L',
    'I','E','S',',',' ','W','E',' ','D','E','C','I','D','E','D',' ','T','O',
    ' ','P','U','T',' ','A',' ','N','E','W',' ','T','W','I','S','T',' ','O',
    'N',' ','I','T',' ','*','*','*',' ',' ',' ',' ',' ',' ','B','U','T',' ',
    'I','F',' ','Y','O','U',' ','D','O','N','T',' ','L','I','K','E',' ','L',
    'E','M','M','I','N','G','S',',',' ','T','H','E','N',' ','T','H','E','R',
    'E',' ','I','S',' ','N','O',' ','H','O','P','E',',',' ','H','I','T',' ',
    'A','N','Y',' ','K','E','Y',' ','N','O','W','.',' ','T','H','E',' ','A',
    'N','Y',' ','K','E','Y','?',' ','T','H','E',' ','O','N','E',' ','O','N',
    ' ','T','H','E',' ','S','I','D','E',' ','M','A','R','K','E','D',' ','-',
    'P','O','W','E','R','-',' ',' ',' ',' ',' ',' ','*','*','*',' ',' ',' ',
    ' ',' ');

const
  ScrollCol  : Integer = 0;                      { DS:$00F2 }
  ScrollIdx  : Byte    = 1;                      { DS:$00F4 }
  ScrollPal  : array[0..7, 0..2] of Byte =       { DS:$00F5 }
    ((7, 7, 7), (7, 7, 7), (7, 7, 7), (7, 7, 7),
     (30, 30, 30), (30, 30, 30), (30, 30, 30), (30, 30, 30));

procedure SetState(S : Byte; N : Integer); forward;
procedure Remove(N : Integer); forward;

{ ==========================================================================
  The drawing layer. Five routines, all hand assembler in the binary.
  ========================================================================== }

{ --------------------------------------------------------------------------
  1005:0328 -- a one-pixel-wide VERTICAL run. HAND ASSEMBLER, verbatim.

  Ghidra calls this VGA_FillRect and it is nothing of the kind: there is one
  STOSB per row and the pointer then advances by $13F, which with the store's
  own +1 is 320. The width is always one.

  RET $A, five words: X at BP+$C, YTop at BP+$A, YBottom at BP+8, Colour at
  BP+6, Segment at BP+4. Note the count is YBottom - YTop + 1 and a zero
  count returns without drawing -- it does NOT wrap round to 65536.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      D := YOfs[YTop] + X;
      for I := 1 to YBottom - YTop + 1 do
      begin
        Mem[Segment : D] := Colour;
        Inc(D, 320);
      end;
  -------------------------------------------------------------------------- }
{ @asm 004 1005:0328 }
procedure VLine(X, YTop, YBottom : Integer;
                Colour : Byte; Segment : Word); assembler;
asm
  MOV  AX, Segment      { which screen                                      }
  MOV  ES, AX           { ES:DI is the destination                          }
  MOV  BX, YTop         { the first row                                     }
  SHL  BX, 1            { * 2, a word index into the row table              }
  MOV  DI, [BX + OFFSET YOfs]   { DI := YOfs[YTop] -- VGA's row table       }
  ADD  DI, X            { + the column                                      }
  MOV  CX, YBottom      { the last row                                      }
  SUB  CX, YTop         { how many rows between them                        }
  INC  CX               { both ends inclusive                               }
  JZ   @@Out            { none -- draw nothing rather than wrap CX          }
  MOV  AX, WORD PTR Colour   { the pixel value. The original reads the whole }
                        {   word slot, not the byte -- AH is scratch here.   }
@@Row:                  { <- once per row                                   }
  STOSB                 { plot; DI advances one                             }
  ADD  DI, $13F         { 319 more, so 320 in all -- straight down          }
  DEC  CX               { one row done                                      }
  JNZ  @@Row            { round again                                       }
@@Out:                  { <- a zero count draws nothing and returns        }
end;

{ --------------------------------------------------------------------------
  1005:0354 -- a HORIZONTAL run. HAND ASSEMBLER, verbatim.

  Ghidra calls this VGA_FillTri; it is a REP STOSB along one row.

  RET $A: X1 at BP+$C, X2 at BP+$A, Y at BP+8, Colour at BP+6, Segment at
  BP+4. Both ends inclusive, and a zero count returns without drawing.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      FillChar(Mem[Segment : YOfs[Y] + X1], X2 - X1 + 1, Colour);
  -------------------------------------------------------------------------- }
{ @asm 004 1005:0354 }
procedure HLine(X1, X2, Y : Integer;
                Colour : Byte; Segment : Word); assembler;
asm
  MOV  AX, Segment      { which screen                                      }
  MOV  ES, AX           { ES:DI is the destination                          }
  MOV  BX, Y            { the row                                           }
  SHL  BX, 1            { * 2, a word index into the row table              }
  MOV  DI, [BX + OFFSET YOfs]   { DI := YOfs[Y]                             }
  ADD  DI, X1           { + the left end                                    }
  MOV  CX, X2           { the right end                                     }
  SUB  CX, X1           { the span                                          }
  INC  CX               { both ends inclusive                               }
  JZ   @@Out            { none -- draw nothing rather than wrap CX          }
  MOV  AX, WORD PTR Colour   { the pixel value, whole word slot as above    }
  REP  STOSB            { the whole run in one instruction                  }
@@Out:                  { <- a zero count draws nothing and returns        }
end;

{ --------------------------------------------------------------------------
  1005:037a -- the sprite blit. HAND ASSEMBLER, verbatim.

  Transparent: a source byte of zero advances the destination without
  storing, so the lemmings composite over the hillside. That test is why
  this cannot be a REP MOVSB.

  RET $E, so a pointer and five words: Src at BP+$E, X at BP+$C, Y at BP+$A,
  W at BP+8, H at BP+6, Segment at BP+4.

  There is NO clipping. Every caller keeps its sprites on screen, and a
  lemming that walks off the edge would wrap onto the next row -- but
  UpdateAll removes anything below row 199 before it can.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      P := Src;  D := YOfs[Y] + X;
      for Row := 1 to H do
      begin
        for Col := 1 to W do
        begin
          if P^ <> 0 then Mem[Segment : D] := P^;
          Inc(LongInt(P));  Inc(D);
        end;
        Inc(D, 320 - W);
      end;
  -------------------------------------------------------------------------- }
{ @asm 004 1005:037a }
procedure Blit(Src : Pointer; X, Y, W, H : Integer;
               Segment : Word); assembler;
asm
  PUSH DS               { DS is about to point at the sprite                }
  MOV  AX, Segment      { which screen                                      }
  MOV  ES, AX           { ES:DI is the destination                          }
  MOV  BX, Y            { the top row                                       }
  SHL  BX, 1            { * 2, a word index into the row table              }
  MOV  DI, [BX + OFFSET YOfs]   { DI := YOfs[Y]                             }
  ADD  DI, X            { + the left column                                 }
  MOV  CX, H            { CX counts rows                                    }
  MOV  BX, W            { the width...                                      }
  MOV  DX, BX           {   ...kept in DX for the whole call                }
  LDS  SI, Src          { DS:SI := the sprite, read straight through        }
@@Row:                  { <- once per row                                   }
  MOV  BX, DX           { BX counts the pixels across this row              }
@@Pixel:                { <- once per pixel                                 }
  LODSB                 { AL := the source pixel; SI moves on               }
  OR   AL, AL           { colour 0?                                         }
  JZ   @@Skip           {   transparent -- leave the screen alone           }
  STOSB                 { plot it; DI moves on                              }
  DEC  BX               { one pixel done                                    }
  JNZ  @@Pixel          { round again                                       }
  JMP  @@NextRow        { row finished                                      }
@@Skip:                 { <- the transparent case                           }
  INC  DI               { step the destination by hand instead              }
  DEC  BX               { one pixel done                                    }
  JNZ  @@Pixel          { round again                                       }
@@NextRow:              { <- both paths join here                           }
  ADD  DI, $140         { 320 -- down one screen row...                     }
  SUB  DI, DX           {   ...less the width just drawn                    }
  DEC  CX               { one row done                                      }
  JNZ  @@Row            { round again                                       }
  POP  DS               { restore our data segment                          }
end;

{ --------------------------------------------------------------------------
  1005:0835 -- 64,000-byte screen copy. HAND ASSEMBLER, verbatim.
  RET 4: SrcSeg at BP+6, DestSeg at BP+4.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Move(Mem[SrcSeg : 0], Mem[DestSeg : 0], 64000);
  -------------------------------------------------------------------------- }
{ @asm 004 1005:0835 }
procedure CopyScreen(SrcSeg, DestSeg : Word); assembler;
asm
  PUSH DS               { DS becomes the source segment below               }
  MOV  AX, DestSeg      { the second declared parameter                     }
  MOV  ES, AX           { ES: is the destination                            }
  MOV  AX, SrcSeg       { the first                                         }
  MOV  DS, AX           { DS: is the source                                 }
  MOV  SI, 0            { both start at offset 0 -- whole screens           }
  MOV  DI, 0            {                                                   }
  MOV  CX, $7D00        { 32,000 words = 64,000 bytes                       }
  REP  MOVSW            { the blit, one instruction                         }
  POP  DS               { restore our data segment                          }
end;

{ --------------------------------------------------------------------------
  1005:07f9 -- show the scroller and shift it. HAND ASSEMBLER, verbatim.
  No parameters at all; it works entirely off two globals.

  The buffer is 18 rows of 341 bytes. Only the first 320 of each row are
  visible; the remaining 21 are the run-up that ScrollChar writes into. Each
  call copies the visible part to the work screen, then slides the WHOLE
  6,138 bytes left by two.

  That shift is LINEAR, not per row -- one REP MOVSW straight across the
  buffer -- so the two bytes that fall off the left of a row reappear at the
  right of the row above. With the run-up being blank most of the time that
  is invisible, and it is what the original does.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      P := ScrollBuf;
      for Row := 0 to 17 do
      begin
        Move(P^, Mem[WorkSeg : Row * 320], 320);
        Inc(LongInt(P), 341);
      end;
      for Row := 0 to 17 do
        Mem[Seg(ScrollBuf^) : Row * 341] := 0;
      Move(Mem[Seg(ScrollBuf^) : 2], Mem[Seg(ScrollBuf^) : 0], 6136);
  -------------------------------------------------------------------------- }
{ @asm 004 1005:07f9 }
procedure ScrollRender; assembler;
asm
  PUSH DS               { DS is about to point at the scroll buffer         }
  MOV  AX, [WorkSeg]    { DS:$030D -- the frame being composed              }
  MOV  ES, AX           { ES:DI is the destination                          }
  XOR  DI, DI           { the scroller sits at the TOP of the screen        }
  LDS  SI, ScrollBuf    { DS:SI := the 341 x 18 bitmap                      }
  MOV  AX, 18           { 18 rows to show                                   }
@@Row:                  { <- once per row                                   }
  MOV  CX, $A0          { 160 words = 320 bytes, the visible part           }
  REP  MOVSW            { copy the row out                                  }
  ADD  SI, $15          { skip the 21-byte run-up to the next row           }
  DEC  AX               { one row done                                      }
  JNZ  @@Row            { round again                                       }

  MOV  BX, 18           { now blank the first byte of every row...          }
  XOR  SI, SI           { ...starting at the top of the buffer              }
  XOR  CL, CL           { the value: black                                  }
@@Clear:                { <- once per row                                   }
  MOV  [SI], CL         { clear it                                          }
  ADD  SI, $155         { down one 341-byte row                             }
  DEC  BX               { one row done                                      }
  JNZ  @@Clear          { round again                                       }

  MOV  AX, DS           { source and destination are the same buffer        }
  MOV  ES, AX           {                                                   }
  XOR  DI, DI           { write from offset 0                               }
  XOR  SI, SI           { read from...                                      }
  ADD  SI, 2            {   ...offset 2 -- a two-pixel shift                }
  MOV  CX, $BFC         { 3,068 words = 6,136 of the 6,138 bytes            }
  REP  MOVSW            { slide the whole bitmap left                       }
  POP  DS               { restore our data segment                          }
end;

{ ==========================================================================
  The scroller
  ========================================================================== }

{ --------------------------------------------------------------------------
  1005:0853 -- write ONE column of one glyph into the buffer's run-up.

  The font is 62 glyphs from space upward, each 378 bytes = 21 columns of 18
  rows stored column-major, so a column is 18 consecutive bytes. Each call
  drops one such column into buffer column 320 -- the right-hand edge, just
  off screen -- and ScrollRender then slides it into view.

  RET 4: Ch at BP+6, Col at BP+4. The original's index is
  Ch * 378 + Col * 18 + Row + 1 - 12115, and 12115 is 32 * 378 + 18 + 1, so
  the character is 32-based and the column one-based.
  -------------------------------------------------------------------------- }
procedure ScrollChar(Ch, Col : Byte);
var
  Row : Integer;
  P   : ^Byte;
begin
  for Row := 0 to ScrollRows - 1 do
  begin
    P := @Font^[(Ch - FirstChar) * GlyphPitch
                + (Col - 1) * ScrollRows + Row];
    Mem[Seg(ScrollBuf^) : Ofs(ScrollBuf^) + Row * ScrollPitch + ScrollEdge]
      := P^;
  end;
end;

{ --------------------------------------------------------------------------
  1005:08ad -- one frame of the scroller.

  The column counter advances by TWO because the bitmap slides two pixels a
  frame, so every other column of each glyph is simply never written. The
  message is therefore drawn at half its horizontal resolution -- which is
  the original's behaviour, not a transcription slip.

  It also runs the two 14 x 10 animations either side of the message, from
  the same six-frame bank read in opposite directions, and rotates the
  eight-entry colour cycle that DAC entries $80..$87 take.
  -------------------------------------------------------------------------- }
procedure ScrollStep;
var
  I, Pass : Integer;      { NOT one variable for both loops -- the inner one
                            would destroy the outer's count and never end }
  Last    : Byte;
begin
  Inc(ScrollCol, 2);                             { 1005:08b1 }
  if ScrollCol > GlyphCols then
  begin
    ScrollCol := 1;
    Inc(ScrollIdx);
  end;

  if ScrollIdx < TextLen then                    { 1005:08c8 }
    ScrollChar(Ord(Message[ScrollIdx]), ScrollCol)
  else
    ScrollChar(Ord(' '), ScrollCol);

  ScrollRender;                                  { 1005:08f4 }

  { 1005:08f7 -- the two side animations, three frames each shown four ticks
    apart, one counting up and the other down so they mirror. }
  SideTick := (SideTick mod 11) + 1;
  Blit(@SideAnim[4 - ((SideTick shr 2) + 1)], $116, $1B, 14, 10, WorkSeg);
  Blit(@SideAnim[(SideTick shr 2) + 4],       $1E,  $1B, 14, 10, WorkSeg);

  { 1005:093f -- rotate the eight-entry cycle and show it. The original does
    the whole thing TWICE per frame, so the colours run at double speed. }
  for Pass := 1 to 2 do
  begin
    Last := ScrollPal[7, 2];
    Move(ScrollPal[0, 0], ScrollPal[1, 0], 21);
    FillChar(ScrollPal[0, 0], 3, Last);
    for I := 0 to 7 do
      SetRGB($80 + I, ScrollPal[I, 0], ScrollPal[I, 1], ScrollPal[I, 2]);
  end;
end;

{ ==========================================================================
  The lemmings
  ========================================================================== }

{ 1005:06c8 -- free every slot. }
procedure InitAll;
var
  N : Integer;
begin
  for N := 1 to MaxLem do
    Lem[N].Active := 0;
end;

{ 1005:07d8 -- free one, and only count it down if it was live. }
procedure Remove(N : Integer);
begin
  if Lem[N].Active <> 0 then
  begin
    Lem[N].Active := 0;
    Dec(LiveCount);
  end;
end;

{ 1005:0b22 -- change state, and restart the animation. }
procedure SetState(S : Byte; N : Integer);
begin
  Lem[N].State := S;
  Lem[N].Frame := 1;
  Lem[N].Tick  := 0;
end;

{ --------------------------------------------------------------------------
  1005:06e7 -- put one lemming in the first free slot.

  The four `if Spawned = ...` arms are the choreography: at the 3rd, 5th,
  65th and 80th lemming a SPECIFIC slot is given a trigger, so that when
  whoever is in it reaches that pixel it is forced into a state. Slot 3
  (DS:$034B) is sent tunnelling and then exploding, slot 1 (DS:$0321) does
  the same later, and slot 5 (DS:$0375) is set digging.

  That is how the set piece is staged: the lemmings are otherwise autonomous.
  -------------------------------------------------------------------------- }
procedure Spawn;
var
  N : Integer;
begin
  if Spawned = SpawnLimit then Exit;             { 1005:06ee }
  for N := 1 to MaxLem do
    if Lem[N].Active = 0 then
    begin
      Lem[N].X         := SpawnX;
      Lem[N].Y         := SpawnY;
      Lem[N].TrigX     := SpawnX;
      Lem[N].TrigY     := SpawnY;
      Lem[N].TrigState := StFaller;
      Lem[N].Tick      := 0;
      Lem[N].Active    := 1;
      Lem[N].State     := StFaller;
      Lem[N].Dir       := 1;
      Lem[N].Frame     := 1;
      Lem[N].Timer     := 0;
      Lem[N].FallDist  := 0;
      Lem[N].Bounces   := 0;
      Inc(Spawned);

      case Spawned of                            { 1005:0761 }
        3    : begin Lem[3].TrigX := $32; Lem[3].TrigY := $66;
                     Lem[3].TrigState := StTunneller end;
        5    : begin Lem[5].TrigX := $31; Lem[5].TrigY := $66;
                     Lem[5].TrigState := StDigger end;
        $41  : begin Lem[1].TrigX := $B5; Lem[1].TrigY := $9E;
                     Lem[1].TrigState := StTunneller end;
        $50  : begin Lem[1].TrigX := $DF; Lem[1].TrigY := $9E;
                     Lem[1].TrigState := StBuilder end;
      end;

      Inc(LiveCount);
      Exit;                                      { one per call }
    end;
end;

{ --------------------------------------------------------------------------
  1005:03b9 -- one blit per state, each from its own bank.

  The sprite is drawn relative to the lemming's feet, which is what all the
  small negative offsets are. States 1 and 2 add FOUR to the frame index when
  facing left, so their banks hold the same animation twice, mirrored.
  -------------------------------------------------------------------------- }
procedure DrawSprite(N : Integer);
var
  F : Integer;
begin
  F := Lem[N].Frame;
  case Lem[N].State of
    StSplat:
      Blit(@SplatBank[F], Lem[N].X - 4, Lem[N].Y - 8, 12, 10, WorkSeg);
    StBuilder:
      Blit(@BuildBank[F], Lem[N].X - 4, Lem[N].Y - 8, 12, 10, WorkSeg);
    StFaller:
      if Lem[N].FallDist < 4 then
      begin
        if Lem[N].Dir < 1 then
          Blit(@WalkBank[F + 4], Lem[N].X - 3, Lem[N].Y - 8, 6, 9, WorkSeg)
        else
        begin
          Blit(@WalkBank[F], Lem[N].X - 3, Lem[N].Y - 8, 6, 9, WorkSeg);
          { 1005:0467 -- the only place DrawSprite changes state, and it
            steps TWICE: MOV AX,Frame / INC AX / DIV 4 / INC AX. }
          Lem[N].Frame := ((F + 1) mod 4) + 1;
        end;
      end
      else
        Blit(@TumbleBk[F], Lem[N].X - 3, Lem[N].Y - 10, 10, 10, WorkSeg);
    StWalker:
      if Lem[N].Dir < 1 then
        Blit(@WalkBank[F + 4], Lem[N].X - 3, Lem[N].Y - 8, 6, 9, WorkSeg)
      else
        Blit(@WalkBank[F], Lem[N].X - 3, Lem[N].Y - 8, 6, 9, WorkSeg);
    StTunneller:
      Blit(@TunnelBk[F], Lem[N].X - 8, Lem[N].Y - 9, 14, 10, WorkSeg);
    StDeathB:
      Blit(@DeathBBk[F], Lem[N].X - 5, Lem[N].Y - 8, 16, 10, WorkSeg);
    StDigger:
      Blit(@DigBank[F], Lem[N].X - 8, Lem[N].Y - 12, 17, 13, WorkSeg);
    StFuse:
      Blit(@FuseBank[F], Lem[N].X - 4, Lem[N].Y - 9, 15, 10, WorkSeg);
    StExplode:
      { 1005:05d1 -- frames 1..9 all show the first picture; only from 10
        does it start stepping the bank. }
      if F < 10 then
        Blit(@Explosion[1], Lem[N].X - $1F, Lem[N].Y - $30, 63, 55, WorkSeg)
      else
        Blit(@Explosion[F - 8], Lem[N].X - $1F, Lem[N].Y - $30,
             63, 55, WorkSeg);
    StDeathA:
      begin
        { 1005:068a -- on the first frame only, a picture at a FIXED place:
          the storm cloud with a lightning bolt coming out of it, 60 wide by
          53 tall at (95, 50). It lands just under the drifting cloud that
          BackdropAnim animates at (113, 50), which is the point of it. The
          four immediates are PUSH $5F, $32, $3C, $35 in that order, and Blit
          takes them as X, Y, W, H. }
        if F = 1 then
          Blit(@DeathAPic, $5F, $32, 60, 53, WorkSeg);
        Blit(@DeathABk[F], Lem[N].X - 4, Lem[N].Y - $B, 9, 12, WorkSeg);
      end;
  end;
end;

{ ==========================================================================
  The state handlers
  ========================================================================== }

{ --------------------------------------------------------------------------
  1005:14d6 -- state 1, walking.

    1. look one row down, seven columns wide, for something to stand on
         colour 3        -> DeathA
         colour $12      -> state 9, FOR WHICH THERE IS NO HANDLER
         colour $20..$29 -> DeathB
         in Ground       -> stop looking, we are standing
         nothing at all  -> Faller
    2. rows Y-9..Y-4, three columns ahead: anything in Wall turns it round
    3. rows Y-4..Y,   two columns ahead: anything in Wall is a step, and the
       lemming climbs to just above it
    4. move one pixel, and advance the animation every second tick

  STATE 9 IS A DEAD END and it is the original's. UpdateAll's dispatch has no
  arm for it, so a lemming that walks onto colour $12 stops being simulated
  and stands there being drawn by whatever DrawSprite does with an unknown
  state -- which is nothing. It is left in.
  -------------------------------------------------------------------------- }
procedure Walker(N : Integer);
var
  DX_, Row, Col, RowTo, ColTo : Integer;
  Pix                         : Byte;
  Standing, Climbed           : Boolean;
begin
  Standing := False;
  for DX_ := -3 to 3 do
  begin
    Pix := GetPixel(Lem[N].X + DX_, Lem[N].Y + 1, VirtScrSeg);
    if (Pix = DeathAColour) or (Pix = StuckColour)
       or ((Pix > $1F) and (Pix < $2A)) then
    begin
      if (Pix > $1F) and (Pix < $2A) then SetState(StDeathB, N);
      if Pix = DeathAColour then SetState(StDeathA, N);
      if Pix = StuckColour  then SetState(StStuck,  N);
      Exit;
    end;
    if Pix in Ground then
    begin
      Standing := True;
      Break;
    end;
    if DX_ = 3 then
    begin
      SetState(StFaller, N);
      Exit;
    end;
  end;

  if Standing then
  begin
    { 1005:1608 -- the wall ahead, head height }
    for Row := Lem[N].Y - 9 to Lem[N].Y - 4 do
    begin
      if Lem[N].Dir < 1 then
      begin
        ColTo := Lem[N].X - 3;  Col := Lem[N].X - 5;
      end
      else
      begin
        ColTo := Lem[N].X + 5;  Col := Lem[N].X + 3;
      end;
      while Col <= ColTo do
      begin
        if GetPixel(Col, Row, VirtScrSeg) in Wall then
        begin
          Lem[N].Dir := -Lem[N].Dir;
          Exit;
        end;
        Inc(Col);
      end;
    end;

    { 1005:16d0 -- a step it can climb rather than a wall.

      The moment this finds one it writes the new Y and jumps OUT of both
      loops to the move at 1005:1791 -- see the JMP at 1005:171b. Writing the
      new Y and letting the row loop carry on is not the same thing: the new Y
      is one LESS than the current row, so a row loop that kept going would
      step back onto the row it just left and stay there. }
    Climbed := False;
    Row   := Lem[N].Y - 4;                       { 1005:16a8 }
    RowTo := Lem[N].Y;                           { 1005:169d, read once }
    while (Row <= RowTo) and not Climbed do
    begin
      if Lem[N].Dir < 1 then                     { 1005:16bf }
      begin
        ColTo := Lem[N].X - 3;  Col := Lem[N].X - 4;
      end
      else
      begin
        ColTo := Lem[N].X + 4;  Col := Lem[N].X + 3;
      end;
      while (Col <= ColTo) and not Climbed do
      begin
        if GetPixel(Col, Row, VirtScrSeg) in Wall then
        begin
          Lem[N].Y := Row - 1;                   { 1005:170f }
          Climbed  := True;                      { 1005:171b -- and out }
        end
        else Inc(Col);
      end;
      Inc(Row);
    end;
  end;

  Inc(Lem[N].X, Lem[N].Dir);                     { 1005:1791 }
  Lem[N].Tick := (Lem[N].Tick mod 2) + 1;
  if Lem[N].Tick mod 2 = 0 then
    Lem[N].Frame := (Lem[N].Frame mod 4) + 1;
end;

{ --------------------------------------------------------------------------
  1005:0b68 -- state 2, falling.

  Looks one row down across seven columns. Landing on Ground turns it back
  into a walker unless it has fallen 11 pixels or more, in which case the
  SECOND such landing splats it -- the first is survived and counted.
  Landing on the $20..$29 hazard stripe is always fatal.

  While it has nothing under it, it drifts one pixel in its facing direction
  for the first two rows of the fall only, then drops straight.
  -------------------------------------------------------------------------- }
procedure Faller(N : Integer);
var
  { AN OUTER LOOP, and its variable is the Y offset. 1005:0b76 opens ENTER $8
    and reads the pixel at (X + [BP-4], Y + [BP-2]) -- so the Y offset is a
    VARIABLE, not the literal 1 this routine used to pass, and it is declared
    first. The outer loop never reaches a second pass: every path out of the
    body returns, which is why a single loop produced the right picture and
    the wrong code. }
  DY_ : Integer;                  { [BP-$02] }
  DX_ : Integer;                  { [BP-$04] }
  Pix : Byte;
begin
  DY_ := 1;
  repeat
    for DX_ := -3 to 3 do
    begin
      Pix := GetPixel(Lem[N].X + DX_, Lem[N].Y + DY_, VirtScrSeg);
      if Pix in Ground then
      begin
        if Lem[N].FallDist < 11 then
        begin
          SetState(StWalker, N);
          { + DY_ - 1, which is nothing while DY_ is 1 -- transcribed because
            1005:0bd5 adds it. }
          Inc(Lem[N].Y, DY_ - 1);
          Lem[N].FallDist := 0;
        end
        else
        begin
          Inc(Lem[N].Bounces);
          if Lem[N].Bounces = 2 then
            SetState(StSplat, N)
          else
          begin
            SetState(StWalker, N);
            Inc(Lem[N].Y, DY_ - 1);
            Lem[N].FallDist := 0;
          end;
        end;
        Lem[N].Frame := (Lem[N].Frame mod 4) + 1;
        Exit;
      end;
      if (Pix > $1F) and (Pix < $2A) then
      begin
        SetState(StDeathB, N);
        Exit;
      end;
    end;

    if DY_ = 1 then
    begin
      if Lem[N].FallDist < 2 then Inc(Lem[N].X, Lem[N].Dir);
      Inc(Lem[N].Y);
      Inc(Lem[N].FallDist);
      Lem[N].Frame := (Lem[N].Frame mod 4) + 1;
      Exit;
    end;
    Inc(DY_);
  until False;
end;


{ --------------------------------------------------------------------------
  1005:0df5 -- state 4, the DIAGONAL digger.

  Erases a bite out of the hillside with colour 0 and, every sixth frame,
  moves two pixels along and one down -- so it cuts a slope. It keeps going
  only while there is still something in the WALL set in front of it; the
  moment there is not, it becomes a walker again and the tunnel ends.

  The two facings are not mirror images: leftward uses three DrawLine
  strokes, rightward five VLines and an HLine. That asymmetry is the
  original's.
  -------------------------------------------------------------------------- }
procedure Digger(N : Integer);
var
  { FIVE LOCALS IN EIGHT BYTES, which is what 1005:0df5's ENTER $8 and its slots
    say: Words at [BP-$02] and [BP-$04], Bytes at [BP-$05] and [BP-$06], and a
    Word at [BP-$08] -- 2+2+1+1+2. This routine declared three.

    The pixel is READ INTO A BYTE before it is tested; writing the GetPixel
    inside the `in` test keeps it in a register and loses the slot. }
  Col, ColTo : Integer;           { [BP-$02], [BP-$04] }
  Hit        : Boolean;           { [BP-$05] }
  Pix        : Byte;              { [BP-$06] }
  Lim        : Integer;           { [BP-$08], 18 references in the original }
begin
  Hit := False;
  if Lem[N].Dir < 1 then
  begin
    ColTo := Lem[N].X + 3;
    for Col := Lem[N].X - 3 to ColTo do
    begin
      Pix := GetPixel(Col, Lem[N].Y + 1, VirtScrSeg);
      if Pix in Wall then Hit := True;
    end;
    DrawLine(Lem[N].X - 2, Lem[N].Y - 11, Lem[N].X - 2, Lem[N].Y + 1,
             0, VirtScrSeg);
    DrawLine(Lem[N].X - 1, Lem[N].Y - 11, Lem[N].X - 1, Lem[N].Y + 1,
             0, VirtScrSeg);
    DrawLine(Lem[N].X - 5, Lem[N].Y + 1,  Lem[N].X + 5, Lem[N].Y + 1,
             0, VirtScrSeg);
  end
  else
  begin
    ColTo := Lem[N].X + 4;
    for Col := Lem[N].X - 3 to ColTo do
    begin
      Pix := GetPixel(Col, Lem[N].Y + 1, VirtScrSeg);
      if Pix in Wall then Hit := True;
    end;
    VLine(Lem[N].X + 4, Lem[N].Y - 10, Lem[N].Y,     0, VirtScrSeg);
    VLine(Lem[N].X + 5, Lem[N].Y - 9,  Lem[N].Y,     0, VirtScrSeg);
    VLine(Lem[N].X + 6, Lem[N].Y - 8,  Lem[N].Y - 1, 0, VirtScrSeg);
    VLine(Lem[N].X + 7, Lem[N].Y - 7,  Lem[N].Y - 2, 0, VirtScrSeg);
    VLine(Lem[N].X + 8, Lem[N].Y - 6,  Lem[N].Y - 3, 0, VirtScrSeg);
    HLine(Lem[N].X - 3, Lem[N].X + 5,  Lem[N].Y,     0, VirtScrSeg);
  end;

  Lem[N].Tick := (Lem[N].Tick mod 3) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    Lem[N].Frame := (Lem[N].Frame mod 6) + 1;
    if Lem[N].Frame mod 6 = 0 then
    begin
      Inc(Lem[N].X, Lem[N].Dir * 2);
      Inc(Lem[N].Y);
    end;
  end;

  if not Hit then SetState(StWalker, N);
end;

{ --------------------------------------------------------------------------
  1005:1166 -- state 10, the HORIZONTAL tunneller.

  Same idea as the digger but it never changes Y, so it bores straight
  through. It tests a two-column by ten-row block ahead against the WALL set
  and stops the moment that block is empty.
  -------------------------------------------------------------------------- }
procedure Tunneller(N : Integer);
var
  Col, ColTo, Row, RowTo : Integer;
  Hit                    : Boolean;
begin
  Hit := False;
  RowTo := Lem[N].Y;
  if Lem[N].Dir < 1 then
  begin
    ColTo := Lem[N].X - 4;
    for Col := Lem[N].X - 5 to ColTo do
      for Row := Lem[N].Y - 9 to RowTo do
        if GetPixel(Col, Row, VirtScrSeg) in Wall then Hit := True;
    VLine(Lem[N].X - 4, Lem[N].Y - 9, Lem[N].Y,     0, VirtScrSeg);
    VLine(Lem[N].X - 5, Lem[N].Y - 7, Lem[N].Y - 2, 0, VirtScrSeg);
    VLine(Lem[N].X - 6, Lem[N].Y - 6, Lem[N].Y - 3, 0, VirtScrSeg);
  end
  else
  begin
    ColTo := Lem[N].X + 5;
    for Col := Lem[N].X + 4 to ColTo do
      for Row := Lem[N].Y - 9 to RowTo do
        if GetPixel(Col, Row, VirtScrSeg) in Wall then Hit := True;
    VLine(Lem[N].X + 1, Lem[N].Y - 10, Lem[N].Y,     0, VirtScrSeg);
    VLine(Lem[N].X + 2, Lem[N].Y - 9,  Lem[N].Y - 1, 0, VirtScrSeg);
    VLine(Lem[N].X + 3, Lem[N].Y - 8,  Lem[N].Y - 2, 0, VirtScrSeg);
    VLine(Lem[N].X + 4, Lem[N].Y - 7,  Lem[N].Y - 3, 0, VirtScrSeg);
    VLine(Lem[N].X + 5, Lem[N].Y - 6,  Lem[N].Y - 4, 0, VirtScrSeg);
    VLine(Lem[N].X + 6, Lem[N].Y - 5,  Lem[N].Y - 5, 0, VirtScrSeg);
  end;

  Lem[N].Frame := (Lem[N].Frame mod 3) + 1;
  if Lem[N].Frame mod 3 = 0 then
    Inc(Lem[N].X, Lem[N].Dir);

  if not Hit then SetState(StWalker, N);
end;

{ --------------------------------------------------------------------------
  1005:0d1a -- state 5, building.

  Every third tick advances the animation, and on the sixth frame it steps up
  and to the right and lays a five-pixel brick in colour $4D INTO THE
  HILLSIDE -- so the staircase it builds is real terrain that other lemmings
  can then walk on.

  It only ever builds to the right: the step is +2 X regardless of facing.
  After 500 ticks it gives up, becomes a walker and sets a 20-frame timer,
  which UpdateAll turns into a fuse.
  -------------------------------------------------------------------------- }
procedure Builder(N : Integer);
begin
  Inc(Lem[N].Tick);
  if Lem[N].Tick mod 3 = 0 then
  begin
    Lem[N].Frame := (Lem[N].Frame mod 6) + 1;
    if Lem[N].Frame = 6 then
    begin
      Inc(Lem[N].X, 2);
      Dec(Lem[N].Y);
      HLine(Lem[N].X - 2, Lem[N].X + 2, Lem[N].Y + 2,
            BrickColour, VirtScrSeg);
    end;
  end;
  if Lem[N].Tick = 500 then
  begin
    SetState(StWalker, N);
    Lem[N].Timer := $14;
  end;
end;

{ 1005:17ff -- state 8. On the fourth frame it stamps the last splat picture
  PERMANENTLY into the hillside and removes itself, so the mark stays. }
procedure Splat(N : Integer);
begin
  Inc(Lem[N].Frame);
  if Lem[N].Frame = 4 then
  begin
    Blit(@SplatBank[4], Lem[N].X - 4, Lem[N].Y - 9, 12, 10, VirtScrSeg);
    Remove(N);
  end;
end;

{ 1005:1850 -- state 6. Six frames, one every fifth tick, then gone. }
procedure DeathA(N : Integer);
begin
  Lem[N].Tick := (Lem[N].Tick mod 5) + 1;
  if Lem[N].Tick mod 5 = 0 then
  begin
    Inc(Lem[N].Frame);
    if Lem[N].Frame > 6 then Remove(N);
  end;
end;

{ 1005:18a6 -- state 7. Five frames, one every third tick, then gone. }
procedure DeathB(N : Integer);
begin
  Lem[N].Tick := (Lem[N].Tick mod 3) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    Inc(Lem[N].Frame);
    if Lem[N].Frame > 5 then Remove(N);
  end;
end;

{ 1005:18fc -- state 3, the lit fuse. Five frames, then it explodes. }
procedure Fuse(N : Integer);
begin
  Lem[N].Tick := (Lem[N].Tick mod 3) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    Inc(Lem[N].Frame);
    if Lem[N].Frame > 5 then SetState(StExplode, N);
  end;
end;

{ --------------------------------------------------------------------------
  1005:1954 -- state 11, the explosion.

  While the fireball is in its first nine frames it runs five passes bumping
  DAC entries $E0..$E9 one step up toward the scene palette. LoadAssets
  deliberately BLACKED those ten entries after loading, so this is what
  lights the explosion: the picture is already on screen in colours nobody
  can see until the flash brings them up.

  Past frame 15 it sets the timer to -60 and holds the frame, and UpdateAll
  counts that back up to -1 and removes the lemming.
  -------------------------------------------------------------------------- }
procedure Explode(N : Integer);
var
  Pass, C : Integer;
  RGB     : array[0..2] of Byte;
begin
  Lem[N].Tick := (Lem[N].Tick mod 5) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    Inc(Lem[N].Frame);
    if Lem[N].Frame < 10 then
      for Pass := 1 to 5 do
        for C := $E0 to $E9 do
        begin
          GetRGBTo(C, @RGB);
          if RGB[0] < ScenePal[C * 3    ] then Inc(RGB[0]);
          if RGB[1] < ScenePal[C * 3 + 1] then Inc(RGB[1]);
          if RGB[2] < ScenePal[C * 3 + 2] then Inc(RGB[2]);
          SetRGBFrom(C, @RGB);
        end;
    if Lem[N].Frame > 15 then
    begin
      if Lem[N].Timer >= 0 then Lem[N].Timer := -60;
      Dec(Lem[N].Frame);
    end;
  end;
end;

{ --------------------------------------------------------------------------
  1005:1a4c -- one pass over every slot.

  The trigger test, the timer and the draw all happen BEFORE the state
  handler runs, so a lemming is drawn in the state it was in at the start of
  the frame and moves afterwards.
  -------------------------------------------------------------------------- }
procedure UpdateAll;
var
  N : Integer;
begin
  for N := 1 to MaxLem do
  begin
    if Lem[N].Y > 199 then Remove(N);            { off the bottom }
    if Lem[N].Active <> 0 then
    begin
      { 1005:1a70 -- the scripted trigger }
      if (Lem[N].TrigX >= 0) and (Lem[N].TrigX = Lem[N].X)
         and (Lem[N].TrigY >= 0) and (Lem[N].TrigY = Lem[N].Y) then
      begin
        SetState(Lem[N].TrigState, N);
        Lem[N].TrigX := 0;
        Lem[N].TrigY := 0;
      end;

      if Lem[N].Timer > 0 then Dec(Lem[N].Timer);
      if Lem[N].Timer = 1 then SetState(StFuse, N);
      if Lem[N].Timer < 0 then Inc(Lem[N].Timer);
      if Lem[N].Timer = -1 then Remove(N);

      DrawSprite(N);                             { 1005:1ae3 }

      case Lem[N].State of                       { 1005:1aec }
        StWalker    : Walker(N);
        StFaller    : Faller(N);
        StTunneller : Tunneller(N);
        StDigger    : Digger(N);
        StSplat     : Splat(N);
        StBuilder   : Builder(N);
        StDeathA    : DeathA(N);
        StDeathB    : DeathB(N);
        StFuse      : Fuse(N);
        StExplode   : Explode(N);
        { state 9 has no arm -- see Walker }
      end;
    end;
  end;
end;

{ --------------------------------------------------------------------------
  1005:0a4f -- the hillside's own animation, three frames of 43 x 24 at
  (113, 50), stepping every fourth tick. Nothing to do with the lemmings; it
  just shares the frame loop.
  -------------------------------------------------------------------------- }
procedure BackdropAnim;
begin
  HillTick := (HillTick mod 11) + 1;
  Blit(@HillAnim[(HillTick shr 2) + 1], $71, $32, 43, 24, WorkSeg);
end;

{ ==========================================================================
  The scene
  ========================================================================== }

{ --------------------------------------------------------------------------
  1005:0000 -- the title screen slides in one column at a time.

  Every column of the screen gets a random head start of Random(200) - 400,
  so they all begin off the top by different amounts. Each of 400 passes
  walks the 200 columns and, for any whose offset has reached zero, copies
  that column down the screen; the rest just count up. The result is 200
  vertical strips arriving at staggered times.
  -------------------------------------------------------------------------- }
{ @asm 004 1005:0029 }
procedure ColumnSlideIn;
{ --------------------------------------------------------------------------
  EQUIVALENT PASCAL -- REFERENCE ONLY, not what is compiled.

    for C := 200 downto 1 do
    begin
      Ofs := ColOfs[C];
      if Ofs < 1 then
      begin
        Src := C + 60;  Dst := Src;
        while (Ofs < 0) and (Src <= 64000) do
        begin Inc(Ofs); Inc(Src, 320) end;
        if Ofs = 0 then
          while Src <= 64000 do
          begin
            Mem[$A000 : Dst] := Mem[VirtScrSeg : Src];
            Inc(Dst, 320); Inc(Src, 320);
          end;
      end;
      Inc(ColOfs[C]);
    end;

  That reads the same but does not RUN the same, and the difference is the
  whole point of the routine being hand written. Pascal's Mem[Seg:Ofs] reloads
  a segment register for every byte; the original loads ES and DS ONCE per
  column and then runs a MOVSB loop, so the title screen assembles at the
  speed the demo was timed for rather than a crawl.
  -------------------------------------------------------------------------- }
var
  C, Pass : Integer;
  SrcSeg  : Word;
begin
  { 1005:0004 -- this part IS compiled Pascal in the original: it calls
    Random, so it has to be. }
  for C := 0 to 200 do
    ColOfs[C] := Random(200) - 400;              { 1005:000E }

  { 1005:0029 to 1005:0097, transcribed instruction for instruction. }
  asm
        MOV     AX, VirtScrSeg  { 1005:0029  the assembled title screen      }
        MOV     SrcSeg, AX      { 1005:002C                                  }
        MOV     Pass, 1         { 1005:002F  first of four hundred passes    }
        JMP     @@PassTop       { 1005:0034                                  }
    @@NextPass:
        INC     Pass            { 1005:0036                                  }
    @@PassTop:
        MOV     SI, OFFSET ColOfs
                                { 1005:0039                                  }
        ADD     SI, 400         { 1005:003C  one past the last entry         }
        MOV     DX, SI          { 1005:0040  DX walks the table DOWNWARDS    }
        MOV     CX, 200         { 1005:0042  and doubles as the column index }
    @@Column:
        PUSH    DS              { 1005:0045  DS is about to stop being DGROUP}
        MOV     SI, DX          { 1005:0046                                  }
        MOV     AX, [SI]        { 1005:0048  this column's offset            }
        MOV     BX, 0A000h      { 1005:004A                                  }
        MOV     ES, BX          { 1005:004D  ES is the DISPLAY               }
        MOV     BX, SrcSeg      { 1005:004F                                  }
        MOV     DS, BX          { 1005:0052  DS is the picture               }
        MOV     SI, CX          { 1005:0054                                  }
        ADD     SI, 3Ch         { 1005:0056  column CX, sixty bytes in       }
        MOV     DI, SI          { 1005:0059  the column arrives at the TOP   }
        CMP     AX, 1           { 1005:005B                                  }
        JGE     @@Done          { 1005:005E  offset reached 1: it is home    }
    @@Walk:
        CMP     AX, 0           { 1005:0060                                  }
        JZ      @@Copy          { 1005:0063  offset is zero: copy it now     }
        INC     AX              { 1005:0065  still counting up to zero       }
        ADD     SI, 140h        { 1005:0066  walk the SOURCE down a row --   }
        CMP     SI, 0FA00h      { 1005:006A    the destination stays put,    }
        JA      @@Done          { 1005:006E    which is what makes the strip }
        JMP     @@Walk          { 1005:0070    look like it slides in        }
    @@Copy:
        MOVSB                   { 1005:0072  one pixel, ES:DI <- DS:SI       }
        ADD     DI, 13Fh        { 1005:0073  MOVSB already added one, so     }
        ADD     SI, 13Fh        { 1005:0077    both steps are 320            }
        CMP     SI, 0FA00h      { 1005:007B                                  }
        JA      @@Done          { 1005:007F  off the bottom of the picture   }
        JMP     @@Copy          { 1005:0081                                  }
    @@Done:
        POP     DS              { 1005:0083  DGROUP again                    }
        MOV     SI, DX          { 1005:0084                                  }
        MOV     AX, [SI]        { 1005:0086                                  }
        INC     AX              { 1005:0088  every column, arrived or not,   }
        MOV     [SI], AX        { 1005:0089    is one step closer            }
        SUB     DX, 2           { 1005:008B  the previous entry              }
        LOOP    @@Column        { 1005:008E  200 columns per pass            }
        CMP     Pass, 190h      { 1005:0090                                  }
        JNZ     @@NextPass      { 1005:0095                                  }
  end;
end;

{ --------------------------------------------------------------------------
  1005:00a6 -- everything off NEUROSIS.DAT, and the title sequence.
  -------------------------------------------------------------------------- }
procedure LoadAssets;
var
  F   : file;
  Pal : TPal768;
  I   : Integer;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);

  GetMem(Font, SizeOf(TFont));                   { 1005:00BE }
  BlockRead(F, Font^, SizeOf(TFont));

  ClearScreen($A000, 0);
  BlockRead(F, Pal, SizeOf(Pal));
  SetPalette768(@Pal);
  BlockRead(F, Mem[VirtScrSeg : 0], 64000);      { the title screen }

  ColumnSlideIn;                                 { 1005:0116 }
  Delay($514);                                   { 1300 }
  GetPalette768(@Pal);
  for I := 1 to $40 do FadeStep;                 { 1005:0132 }

  ClearScreen($A000, 0);
  BlockRead(F, Mem[VirtScrSeg : 0], 64000);      { the hillside }
  BlockRead(F, Pal, SizeOf(Pal));
  BlockRead(F, ScenePal, SizeOf(ScenePal));      { DS:$CC07 }

  BlockRead(F, WalkBank,  SizeOf(WalkBank));
  BlockRead(F, TumbleBk,  SizeOf(TumbleBk));
  BlockRead(F, SplatBank, SizeOf(SplatBank));
  BlockRead(F, DigBank,   SizeOf(DigBank));
  BlockRead(F, TunnelBk,  SizeOf(TunnelBk));
  BlockRead(F, DeathBBk,  SizeOf(DeathBBk));
  BlockRead(F, HillAnim,  SizeOf(HillAnim));
  BlockRead(F, DeathABk,  SizeOf(DeathABk));
  BlockRead(F, BuildBank, SizeOf(BuildBank));
  BlockRead(F, DeathAPic, SizeOf(DeathAPic));
  BlockRead(F, IntroAnim, SizeOf(IntroAnim));
  BlockRead(F, SideAnim,  SizeOf(SideAnim));
  BlockRead(F, Explosion, SizeOf(Explosion));
  BlockRead(F, FuseBank,  SizeOf(FuseBank));
  Close(F);

  SetPalette768(@Pal);                           { 1005:0304 }
  { 1005:030F -- black out the ten entries the explosion will light. }
  for I := $E0 to $E9 do SetRGB(I, 0, 0, 0);
end;

{ --------------------------------------------------------------------------
  1005:0a86 -- blank the DAC, put the hillside up, fade it in, then run a
  seven-frame animation BACKWARDS at (5, 50) and start the music.
  -------------------------------------------------------------------------- }
procedure Intro;
var
  Pal : TPal768;
  I   : Integer;
begin
  GetPalette768(@Pal);                           { 1005:0A8A }
  for I := 0 to 255 do SetRGB(I, 0, 0, 0);
  CopyScreen(VirtScrSeg, $A000);
  PaletteFadeUp(@Pal, 0);                        { 1005:0AB6 }

  for I := 6 downto 1 do                         { 1005:0ABF }
  begin
    FillRect(5, $32, $46, $4A, 0, VirtScrSeg);
    Blit(@IntroAnim[I], 5, $32, 65, 24, VirtScrSeg);
    CopyScreen(VirtScrSeg, $A000);
    Delay($96);                                  { 150 }
  end;

  MusicStart;                                    { 1005:0B1D }
end;

{ 1005:1c9a -- the two heap blocks the scene needs beyond the virtual screen. }
procedure Setup;
begin
  GetMem(WorkScr, 64000);
  GetMem(ScrollBuf, ScrollSize);
  FillChar(ScrollBuf^, ScrollSize, 0);
  WorkSeg := Seg(WorkScr^);
end;

{ --------------------------------------------------------------------------
  1005:1bbb -- the frame loop.

  IT DOES NOT EXIT ON A KEY. A keypress -- or the last lemming dying -- only
  starts the ending: from then on every frame fades the palette one step and
  drops the tracker volume TWICE, and the loop ends when the volume reaches
  zero. So how long the scene runs past the keypress depends on how loud the
  music was, and with no tracker resident GetVolume returns 0 and it stops on
  the first frame.
  -------------------------------------------------------------------------- }
procedure MainLoop;
var
  Frame, I : Integer;
  V        : Byte;
  Done     : Boolean;
begin
  LiveCount := 0;
  Spawned   := 0;
  Frame     := 0;
  HillTick  := 1;                                { 1005:1BCD }
  InitAll;
  Spawn;
  Done := False;
  repeat
    CopyScreen(VirtScrSeg, WorkSeg);             { the clean hillside }
    BackdropAnim;
    UpdateAll;
    ScrollStep;
    Inc(FrameCount);                             { 1005:1BF1 }
    CopyScreen(WorkSeg, $A000);

    Inc(Frame);
    if Frame mod SpawnEvery = 0 then Spawn;

    if KeyPressed or (LiveCount = 0) then        { 1005:1C46 }
    begin
      FadeStep;
      { 1005:1C5B -- fade the scroller's colour cycle out with it }
      for I := 0 to 7 do
      begin
        if ScrollPal[I, 0] <> 0 then Dec(ScrollPal[I, 0]);
        if ScrollPal[I, 1] <> 0 then Dec(ScrollPal[I, 1]);
        if ScrollPal[I, 2] <> 0 then Dec(ScrollPal[I, 2]);
      end;

      V := GetVolume;
      if V = 0 then Done := True else SetVolume(V - 1);
      V := GetVolume;
      if V = 0 then Done := True else SetVolume(V - 1);
    end;
  until Done;
end;

{ --------------------------------------------------------------------------
  1005:1cd6 -- Demo_Main.
  -------------------------------------------------------------------------- }
procedure RunPart4;
begin
  MusicDetect;                                   { 11d9:0000 }
  Setup;
  LoadAssets;
  Intro;
  SavedVol := GetVolume;                         { 1005:1CE7 }
  MainLoop;
  FreeMem(WorkScr, 64000);
  FreeMem(ScrollBuf, ScrollSize);
  MusicStop;                                     { 11d9:004E }
  SetVolume(SavedVol);                           { put it back as we found it }
end;

{ 1005:1d3a -- the unit's initialisation body is empty. }
begin
end.
