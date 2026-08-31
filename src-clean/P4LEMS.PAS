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

  A NOTE ON TWO NAMES. Ghidra calls state 4 "Basher" and state 10 "Miner".
  Read against what they do, they are the other way round: state 4 advances
  X by two AND Y by one per bite, so it digs DIAGONALLY -- a Lemmings miner;
  state 10 advances X only, so it tunnels HORIZONTALLY -- a Lemmings basher.
  They are called Digger and Tunneller here to avoid inheriting the mix-up.

  There is no 386 code anywhere in part 004, so unlike parts 001, 002 and 005
  there is no TASM object to link.
  =========================================================================== }

{$G+}   { 286 instructions: SHL BX,1 with an immediate in the blits. }
{ I/O CHECKING OFF, and it must stay off. With it on, Turbo Pascal puts a
  five-byte call to the runtime's error check after every file operation, and
  LoadAssets does twenty-nine of them. The routine then has to test IOResult
  itself, which it does not; this part simply assumes its assets are there. }
{$I-}

unit P4Lems;
{$A-}   { DATA ALIGNMENT OFF. The scroller's constants run contiguously in the
          original -- Message $0005 for 237 bytes, ScrollCol $00F2, ScrollIdx
          $00F4, ScrollPal $00F5 -- and 237 is odd. Under TP7's $A+ default the
          message is padded to 238 and everything after it is one byte out. }

interface

procedure RunPart4;

implementation

uses Crt, VGA, DemoVT;

{ Where each asset sits inside NEUROSIS.DAT. Untyped constants, so including
  the whole set costs no storage. }
{$I gen/DATOFS.INC}

const
  MaxLem     = 25;            { clears 1..25 }
  SpawnLimit = $50;           { 80 lemmings, then Spawn does nothing }
  SpawnEvery = 20;            { a spawn every 20th frame }

  { where they come out of the hatch. }
  SpawnX     = $23;
  SpawnY     = $3C;

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

  BrickColour = $4D;          { and it is in both terrain sets }
  ScrollRows  = 18;           { the scroller is 18 pixels tall }
  ScrollPitch = $155;         { 341 bytes per row: 320 visible + 21 ahead }
  ScrollSize  = ScrollRows * ScrollPitch;      { $17FA = 6138 }
  ScrollEdge  = 320;          { new pixels are fed in at column 320 }
  GlyphPitch  = $17A;         { 378 bytes per character = 21 columns of 18 }
  GlyphCols   = 21;
  FirstChar   = 32;           { the font starts at space }
  GlyphCount  = 62;           { 23436 / 378 -- space to ']' }
  { THE MESSAGE IS 236 CHARACTERS INDEXED FROM ONE, not 237 from zero. The
    scroller compares its index against this value directly, so an off-by-one
    here drops a character or reads one past the text. }
  TextLen     = $EC;          { 236 }

  DataOfs     = DAT_P4_LEMFONT;   { $1228CE -- NEUROSIS.DAT -- 1,189,070 }

type
  { ONE LEMMING, and the record is exactly 21 bytes. }
  TLem = record
    X          : Word;        { +0  -- UNSIGNED, and the arithmetic proves it:
 computes Lem[N].X + DX_ in
                                       THIRTY-TWO bits (CWD on the offset, XOR
                                       DX,DX on X, then ADD/ADC), which is what
                                       Turbo Pascal does when a Word meets a
                                       signed Integer. Two Integers would have
                                       stayed 16-bit. }
    { Y IS UNSIGNED TOO, for the same reason X is: it is compared against a
      signed trigger value, and the mixed comparison is what the original's
      widening shows. Making it an Integer changes the arithmetic around every
      use of it. }
    Y          : Word;        { +2 }
    { THREE MORE UNSIGNED FIELDS. Frame and Tick are cycled with `mod`, and an
      unsigned `mod` is a plain divide where a signed one needs a sign-extend
      first -- so the choice is visible in the emitted code. Bounces goes with
      them. }
    Bounces    : Word;        { +4  -- a second hard landing splats }
    Frame      : Word;        { +6  -- one-based, indexes the sprite banks }
    Tick       : Word;        { +8  -- sub-frame counter }
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
  { THE ORDER IS THE ORIGINAL'S, AND THE ADDRESSES CHAIN WITH NO SLACK -- each
    of these variables begins exactly where the one before it ends. Declaring
    them in any other order moves every absolute reference in the part.

    Declared with Lem first, as this block was, ColOfs came out at $0414 instead
    of $0172 -- 674 bytes late, which is Lem's 525 plus what follows it -- and
    every absolute reference in the part carried the difference.

    WHAT IS STILL MISSING IS THE EIGHTY BYTES BELOW ColOfs. The typed constants
    end at $0121 and ColOfs starts at $0172, so something occupies $0122..$0171
    and this unit does not declare it. }

  { ColumnSlideIn's per-column start offset, 201 entries. }
  ColOfs     : array[0..200] of Integer;

  { the tracker volume as we found it. }
  SavedVol   : Byte;

  { The two screens. VGA's VirtScr holds the hillside and is what GetPixel
    reads; this one is composed into each frame. }
  WorkScr    : Pointer;

  { 18 rows of 341, the scroller's own bitmap. }
  ScrollBuf  : Pointer;

  WorkSeg    : Word;

  { -- the two background animations' counters. }
  SideTick   : Byte;
  HillTick   : Byte;

  Lem        : array[1..MaxLem] of TLem;
  LiveCount  : Integer;
  { A WORD, NOT AN INTEGER. Nothing in the part's own arithmetic distinguishes
    the two -- every comparison is against a small positive constant -- so the
    only thing that settles it is how the value is widened when it is printed. }
  Spawned    : Word;




{ --------------------------------------------------------------------------
  THE ASSETS.  LoadAssets seeks once into NEUROSIS.DAT and reads twenty blocks
  in order. Every sprite bank is indexed ONE-BASED. }
type
  { THREE DIMENSIONS, NOT ONE, and the subscripts are the raw character code
    and the raw column -- the low bounds do the offsetting, so a lookup needs no
    subtraction at run time. Flattening this array would move that arithmetic
    into every access. }
  TFont     = array[FirstChar..FirstChar + GlyphCount - 1,
                    1..GlyphPitch div ScrollRows,
                    1..ScrollRows] of Byte;
var
  WalkBank  : array[1..8]  of array[0..53]   of Byte;
  TumbleBk  : array[1..4]  of array[0..99]   of Byte;
  { --------------------------------------------------------------------------
    TWO THOUSAND SIX HUNDRED AND FORTY-SIX BYTES THAT THIS UNIT DOES NOT
    IDENTIFY, and the size is measured while the contents are not. TumbleBk
    begins at $06D2 and is 400 bytes, so it ends at $0862; SplatBank is at
    $12B8. The gap is $A56, which is 2,646.

    It is not a guess that something is there. Before this block existed every
    absolute reference from SplatBank upwards carried the difference, and
    dsmap paired FIFTY of them at exactly -2646 with every other reference in
    the part at +0 -- a bounded run of one shift, which is the signature of a
    misplaced or missing block rather than a wrong size somewhere.

    WHAT IT PROBABLY IS: 2,646 is 7 x 378, and 378 is this part's glyph stride
    -- the same number the font type folds with. Seven somethings of 378 bytes,
    or six of 441; LoadAssets reads TWENTY blocks and this unit names about
    fifteen, so several assets are still unaccounted for. Identifying it means
    reading the seeks in LoadAssets against NEUROSIS.DAT, which is a separate
    job from getting the layout right.
    -------------------------------------------------------------------------- }
  Unknown   : array[1..7]  of array[0..377]  of Byte;   { 2,646 }
  SplatBank : array[1..4]  of array[0..119]  of Byte;
  DigBank   : array[1..6]  of array[0..220]  of Byte;
  TunnelBk  : array[1..3]  of array[0..139]  of Byte;
  DeathBBk  : array[1..5]  of array[0..159]  of Byte;
  DeathABk  : array[1..6]  of array[0..107]  of Byte;
  BuildBank : array[1..6]  of array[0..119]  of Byte;
  FuseBank  : array[1..5]  of array[0..149]  of Byte;
  Explosion : array[1..7]  of array[0..3464] of Byte;
  HillAnim  : array[1..3]  of array[0..1031] of Byte;
  IntroAnim : array[1..7]  of array[0..1559] of Byte;
  SideAnim  : array[1..6]  of array[0..139]  of Byte;

  { --------------------------------------------------------------------------
    AND THESE FOUR ARE LAST, in this order, because the addresses tile from
    SideAnim to the next unit's first variable with nothing left over:

        SideAnim   $BC4F   840
        DeathAPic  $BF97  3180
        Font       $CC03     4   -- a POINTER, which is why the gap is four
        ScenePal   $CC07   768
        F          $CF07   128   -> ends $CF87, and VGA's VirtScr is $CF88 }
  DeathAPic : array[0..3179] of Byte;    { 60 x 53, the storm
                                           cloud and its lightning bolt }
  Font      : ^TFont;
  { The scene palette, which Explode fades entries $E0..$E9 up towards.
    TWO-DIMENSIONAL, entry by channel, so a channel is a constant subscript and
    costs nothing at run time. }
  ScenePal   : array[0..255, 0..2] of Byte;
  { THE FILE VARIABLE IS A GLOBAL, not a local of LoadAssets. A global is
    passed by its absolute address and a local through the frame, which is one
    byte less at each of twenty-two call sites -- so getting this wrong puts the
    whole routine out of step.

    AND IT IS THE LAST VARIABLE THIS UNIT DECLARES, because the next address
    along belongs to the VGA unit. Adding anything after it here would overlap. }
  F          : file;

{ --------------------------------------------------------------------------
  THE TWO TERRAIN SETS, and they differ by exactly one run:

      ground  [4,5, $0F, $15..$18, $1D, $1F, $33, $36,
               $3E..$40, $42..$47, $4D..$52]
      wall    the same PLUS [$20..$29]

  So $20..$29 is a hazard stripe: it BLOCKS you but you cannot STAND on it,
  and the walker and faller both kill on touching it. $4D is in both, which
  is the builder's brick colour -- bricks are solid and walkable.
  -------------------------------------------------------------------------- }
const
  { UNTYPED, AND THAT IS NOT A DETAIL. A typed `Ground : set of Byte = [...]`
    would be data in DGROUP, declared once; an untyped set constant is a
    compile-time value, and Turbo Pascal emits a fresh copy of it in the code
    segment at every place it is used. Five uses here, so five copies of two
    distinct 32-byte constants. Writing these as typed constants changes both
    where the bytes live and how many there are. }
  Ground =
    [4, 5, $0F, $15..$18, $1D, $1F, $33, $36, $3E..$40, $42..$47, $4D..$52];
  Wall   =
    [4, 5, $0F, $15..$18, $1D, $1F, $20..$29, $33, $36, $3E..$40, $42..$47,
     $4D..$52];

  { -- two single colours the walker treats specially,
    outside either set. }
  DeathAColour = 3;
  StuckColour  = $12;

{ --------------------------------------------------------------------------
  THE SCROLLER'S STATE IS INITIALISED DATA, not variables. The values matter
  and nothing ever puts them back -- ScrollStep rotates the palette in place
  from the first frame onwards -- so they are typed constants.

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

{ THE MESSAGE IS ONE-BASED WITH NO LEADING ZERO -- 236 characters, not 237
  with a #0 in front of them. It is a typed constant so that it lands in the
  initialised data rather than being built at run time, and FrameCount below is
  one for the same reason. }
const
  { A 32-bit count of frames drawn, which NOTHING IN PART 004 EVER READS. It is
    kept because the original keeps it, and it is a typed constant rather than a
    `var` because that is what puts it in the initialised data. }
  FrameCount : LongInt = 0;

  Message : array[1..TextLen] of Char = (
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
  { A WORD, NOT AN INTEGER, and the comparison against it is unsigned as a
    result. }
  ScrollCol  : Word = 0;
  ScrollIdx  : Byte    = 1;
  { FLAT AND ONE-BASED, not eight triples. The index is computed at run time
    from a single byte counter, so the cycle can be walked as one array of
    twenty-four bytes -- which is what lets MainLoop's fade be one loop rather
    than three statements. }
  ScrollPal  : array[1..24] of Byte =
    (7, 7, 7,  7, 7, 7,  7, 7, 7,  7, 7, 7,
     30, 30, 30,  30, 30, 30,  30, 30, 30,  30, 30, 30);

procedure SetState(N : Integer; S : Byte); forward;
procedure Remove(N : Integer); forward;

{ ==========================================================================
  The drawing layer. Five routines, all hand assembler in the binary.
  ========================================================================== }

{ --------------------------------------------------------------------------
  a one-pixel-wide VERTICAL run. HAND ASSEMBLER, verbatim.

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
  { TEN BYTES OF FRAME, AND ONE DECLARATION NOTHING READS. The original
    reserves four bytes here that no instruction touches; they are declared so
    that the slots below them land where the assembler block expects. }
  C, Pass : Integer;
  Unread  : LongInt;              { four bytes, never read }
  SrcSeg  : Word;
begin
  { this part IS compiled Pascal in the original: it calls
    Random, so it has to be. }
  for C := 0 to 200 do
    ColOfs[C] := Random(200) - 400;

  asm
        MOV     AX, VirtScrSeg  { the assembled title screen      }
        MOV     SrcSeg, AX
        MOV     Pass, 1         { first of four hundred passes    }
        JMP     @@PassTop
    @@NextPass:
        INC     Pass
    @@PassTop:
        MOV     SI, OFFSET ColOfs
        ADD     SI, 400         { one past the last entry         }
        MOV     DX, SI          { DX walks the table DOWNWARDS    }
        MOV     CX, 200         { and doubles as the column index }
    @@Column:
        PUSH    DS              { DS is about to stop being DGROUP}
        MOV     SI, DX
        MOV     AX, [SI]        { this column's offset            }
        MOV     BX, 0A000h
        MOV     ES, BX          { ES is the DISPLAY               }
        MOV     BX, SrcSeg
        MOV     DS, BX          { DS is the picture               }
        MOV     SI, CX
        ADD     SI, 3Ch         { column CX, sixty bytes in       }
        MOV     DI, SI          { the column arrives at the TOP   }
        CMP     AX, 1
        JGE     @@Done          { offset reached 1: it is home    }
    @@Walk:
        CMP     AX, 0
        JZ      @@Copy          { offset is zero: copy it now     }
        INC     AX              { still counting up to zero       }
        ADD     SI, 140h        { walk the SOURCE down a row --   }
        CMP     SI, 0FA00h      { the destination stays put,    }
        JA      @@Done          { which is what makes the strip }
        JMP     @@Walk          { look like it slides in        }
    @@Copy:
        MOVSB                   { one pixel, ES:DI <- DS:SI       }
        ADD     DI, 13Fh        { MOVSB already added one, so     }
        ADD     SI, 13Fh        { both steps are 320            }
        CMP     SI, 0FA00h
        JA      @@Done          { off the bottom of the picture   }
        JMP     @@Copy
    @@Done:
        POP     DS              { DGROUP again                    }
        MOV     SI, DX
        MOV     AX, [SI]
        INC     AX              { every column, arrived or not,   }
        MOV     [SI], AX        { is one step closer            }
        SUB     DX, 2           { the previous entry              }
        LOOP    @@Column        { 200 columns per pass            }
        CMP     Pass, 190h
        JNZ     @@NextPass
  end;
end;

{ --------------------------------------------------------------------------
  everything off NEUROSIS.DAT, and the title sequence.
  -------------------------------------------------------------------------- }
procedure LoadAssets;
var
  { SIX LOCALS, OF WHICH TWO ARE USED, AND THE ORDER MATTERS MORE THAN THE
    TOTAL. This routine's frame is 1,670 bytes: one 768-byte palette it reads,
    a second it never reads, a file record it never opens, a loop counter, and
    two bytes of padding. The unused ones are declared because the original
    reserves the space, and a local costs its room whether or not anything
    touches it.

    The ORDER is the part that cannot be got wrong quietly. The same six
    declarations rearranged still sum to 1,670 and the frame still matches --
    but every reference to the palette is then at a different displacement. A
    frame that matches says nothing about where inside it anything sits. }
  Pal2   : TPal768;               { never read }
  Unread : file;                  { never opened }
  Spare  : Byte;
  Pal    : TPal768;
  I      : Integer;
  Spare2 : Integer;               { and BP-$686 is the pad }
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);

  GetMem(Font, SizeOf(TFont));
  BlockRead(F, Font^, SizeOf(TFont));

  ClearScreen($A000, 0);
  BlockRead(F, Pal, SizeOf(Pal));
  SetPalette768(@Pal);
  { THE POINTER VARIABLE, not a Mem subscript -- VGA's VirtScr is loaded whole
    and passed, where a Mem[Seg:Ofs] form would read the segment word and build
    a pointer around it. Same address either way, six bytes more to say it. }
  BlockRead(F, VirtScr^, 64000);                 { the title screen }

  ColumnSlideIn;
  Delay($514);
  GetPalette768(@Pal);
  for I := 1 to $40 do FadeStep;

  ClearScreen($A000, 0);
  BlockRead(F, VirtScr^, 64000);                 { the hillside }
  BlockRead(F, Pal, SizeOf(Pal));
  BlockRead(F, ScenePal, SizeOf(ScenePal));

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

  SetPalette768(@Pal);
  { black out the ten entries the explosion will light. }
  for I := $E0 to $E9 do SetRGB(I, 0, 0, 0);
end;

{ --------------------------------------------------------------------------
  blank the DAC, put the hillside up, fade it in, then run a
  seven-frame animation BACKWARDS at (5, 50) and start the music.
  -------------------------------------------------------------------------- }

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
  a HORIZONTAL run. HAND ASSEMBLER, verbatim.

  Ghidra calls this VGA_FillTri; it is a REP STOSB along one row.

  RET $A: X1 at BP+$C, X2 at BP+$A, Y at BP+8, Colour at BP+6, Segment at
  BP+4. Both ends inclusive, and a zero count returns without drawing.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      FillChar(Mem[Segment : YOfs[Y] + X1], X2 - X1 + 1, Colour);
  -------------------------------------------------------------------------- }
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
  the sprite blit. HAND ASSEMBLER, verbatim.

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
64,000-byte screen copy. HAND ASSEMBLER, verbatim.
  RET 4: SrcSeg at BP+6, DestSeg at BP+4.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      Move(Mem[SrcSeg : 0], Mem[DestSeg : 0], 64000);
  -------------------------------------------------------------------------- }
{ IT TAKES THE LEMMING ITSELF, NOT ITS INDEX, and it has no locals at all --
  the parameter is a reference to the record and every field is read through
  it. There is no local frame number either: the frame is read out of the
  record at the point of use. }
procedure DrawSprite(var L : TLem);
begin
  case L.State of
    StSplat:
      Blit(@SplatBank[L.Frame], L.X - 4, L.Y - 8, 12, 10, WorkSeg);
    StBuilder:
      Blit(@BuildBank[L.Frame], L.X - 4, L.Y - 8, 12, 10, WorkSeg);
    StFaller:
      if L.FallDist < 4 then
      begin
        { FACING RIGHT USES FRAMES 1..4 AND STEPS THE COUNTER; facing left uses the
          mirrored set at 5..8 and does not. So the `Dir > 0` arm has to come
          first and carry the step -- writing the test the other way round puts
          the step on the wrong arm and the walk animates only one way. }
        if L.Dir > 0 then
        begin
          Blit(@WalkBank[L.Frame], L.X - 3, L.Y - 8, 6, 9, WorkSeg);
          { the only place DrawSprite changes state, and it
            steps TWICE: MOV AX,Frame / INC AX / DIV 4 / INC AX. }
          L.Frame := ((L.Frame + 1) mod 4) + 1;
        end
        else
          Blit(@WalkBank[L.Frame + 4], L.X - 3, L.Y - 8, 6, 9, WorkSeg);
      end
      else
        Blit(@TumbleBk[L.Frame], L.X - 3, L.Y - 10, 10, 10, WorkSeg);
    StWalker:
      { FACING RIGHT USES FRAMES 1..4, facing left the mirrored set at 5..8, and
        the two arms must stay in this order: the compiler emits the THEN arm
        first, so swapping the condition swaps which sprite bank offset is
        reached by falling through.

        AND THE TEST IS `> 0`, NOT `>= 1` -- the same comparison, but the two
        spellings emit different immediates and different conditions, so only
        one of them matches. }
      if L.Dir > 0 then
        Blit(@WalkBank[L.Frame], L.X - 3, L.Y - 8, 6, 9, WorkSeg)
      else
        Blit(@WalkBank[L.Frame + 4], L.X - 3, L.Y - 8, 6, 9, WorkSeg);
    StTunneller:
      Blit(@TunnelBk[L.Frame], L.X - 8, L.Y - 9, 14, 10, WorkSeg);
    StDeathB:
      Blit(@DeathBBk[L.Frame], L.X - 5, L.Y - 8, 16, 10, WorkSeg);
    StDigger:
      Blit(@DigBank[L.Frame], L.X - 8, L.Y - 12, 17, 13, WorkSeg);
    StFuse:
      Blit(@FuseBank[L.Frame], L.X - 4, L.Y - 9, 15, 10, WorkSeg);
    StExplode:
      { frames 1..9 all show the first picture; only from 10
        does it start stepping the bank. }
      if L.Frame < 10 then
        Blit(@Explosion[1], L.X - $1F, L.Y - $30, 63, 55, WorkSeg)
      else
        Blit(@Explosion[L.Frame - 8], L.X - $1F, L.Y - $30,
             63, 55, WorkSeg);
    StDeathA:
      begin
        { on the first frame only, a picture at a FIXED place:
          the storm cloud with a lightning bolt coming out of it, 60 wide by
          53 tall at (95, 50). It lands just under the drifting cloud that
          BackdropAnim animates at (113, 50), which is the point of it. The
          four immediates are PUSH $5F, $32, $3C, $35 in that order, and Blit
          takes them as X, Y, W, H. }
        if L.Frame = 1 then
          Blit(@DeathAPic, $5F, $32, 60, 53, WorkSeg);
        Blit(@DeathABk[L.Frame], L.X - 4, L.Y - $B, 9, 12, WorkSeg);
      end;
  end;
end;

{ ==========================================================================
  The state handlers
  ========================================================================== }

{ free every slot. }
procedure InitAll;
var
  N : Integer;
begin
  for N := 1 to MaxLem do
    Lem[N].Active := 0;
end;

{ free one, and only count it down if it was live. }

{ --------------------------------------------------------------------------
  put one lemming in the first free slot.

  The four `if Spawned = ...` arms are the choreography: at the 3rd, 5th,
  65th and 80th lemming a SPECIFIC slot is given a trigger, so that when
  whoever is in it reaches that pixel it is forced into a state. Slot 3 is sent
  tunnelling and then exploding, slot 1 does the same later, and slot 5 is set
  digging.

  That is how the set piece is staged: the lemmings are otherwise autonomous.
  -------------------------------------------------------------------------- }
procedure Spawn;
var
  { SIX BYTES, AND THE FOUR BELOW THE COUNTER BELONG TO THE `with`. They are
    not a dead declaration: a `with` is allocated room for the record address
    whether or not it ends up needing it, and here it does not, because nothing
    in the block calls anything and the address stays in registers throughout.

    AND THE BODY IS WHAT SAYS SO, NOT THE FRAME. A `with` computes the
    record's address once and writes every field through it; naming the element
    at each field recomputes that address every time. Part 003's star field is
    the exact opposite reading -- there the original recomputes and a `with`
    was the defect -- and the frame alone cannot tell the two apart. }
  N : Integer;                    { the `with` takes the four bytes below it }
begin
  if Spawned = SpawnLimit then Exit;
  for N := 1 to MaxLem do
    if Lem[N].Active = 0 then
    with Lem[N] do
    begin
      X         := SpawnX;
      Y         := SpawnY;
      TrigX     := SpawnX;
      TrigY     := SpawnY;
      TrigState := StFaller;
      Tick      := 0;
      Active    := 1;
      State     := StFaller;
      Dir       := 1;
      Frame     := 1;
      Timer     := 0;
      FallDist  := 0;
      Bounces   := 0;
      Inc(Spawned);

      case Spawned of
        3    : begin Lem[3].TrigX := $32; Lem[3].TrigY := $66;
                     Lem[3].TrigState := StTunneller end;
        5    : begin Lem[5].TrigX := $31; Lem[5].TrigY := $66;
                     Lem[5].TrigState := StDigger end;
        $41  : begin Lem[1].TrigX := $B5; Lem[1].TrigY := $9E;
                     Lem[1].TrigState := StTunneller end;
        $50  : begin Lem[1].TrigX := $DF; Lem[1].TrigY := $9E;
                     Lem[1].TrigState := StBuilder end;
      end;

      { THE LOOP IS BROKEN BY ASSIGNING ITS LIMIT, not by Exit -- and the
        limit is set BEFORE the counter is bumped, not after. Falling out of
        the loop and off the end of the routine amounts to returning, since
        nothing follows it. }
      N := MaxLem;
      Inc(LiveCount);
    end;
end;

{ --------------------------------------------------------------------------
  one blit per state, each from its own bank.

  The sprite is drawn relative to the lemming's feet, which is what all the
  small negative offsets are. States 1 and 2 add FOUR to the frame index when
  facing left, so their banks hold the same animation twice, mirrored.
  -------------------------------------------------------------------------- }
{ free one, and only count it down if it was live. }
procedure Remove(N : Integer);
begin
  { A GUARD CLAUSE, NOT A WRAPPING `if`. A guard emits a conditional jump over
    an unconditional one; wrapping the body in an `if` emits a single short
    branch instead. Two shapes, different lengths.

    AND `Dec(LiveCount)` IS RIGHT AS IT STANDS. LiveCount is a plain variable,
    not an indexed field, so the short in-place form is what the original uses
    -- unlike the state routines, where the longhand is required. }
  if Lem[N].Active = 0 then Exit;
  Lem[N].Active := 0;
  Dec(LiveCount);
end;

{ change state, and restart the animation. }
{ THE LEMMING COMES FIRST, then the state. Parameter order is not free here:
  it decides which slot each argument occupies in the frame, so getting it the
  wrong way round changes the code at every call site rather than failing to
  compile. }

procedure ScrollRender; assembler;
asm
  PUSH DS               { DS is about to point at the scroll buffer         }
  MOV  AX, [WorkSeg]    { the frame being composed              }
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
  MOV  ES, AX
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
  write ONE column of one glyph into the buffer's run-up.

  The font is 62 glyphs from space upward, each 378 bytes = 21 columns of 18
  rows stored column-major, so a column is 18 consecutive bytes. Each call
  drops one such column into buffer column 320 -- the right-hand edge, just
  off screen -- and ScrollRender then slides it into view.

  RET 4: Ch at BP+6, Col at BP+4. The original's index is
  Ch * 378 + Col * 18 + Row + 1 - 12115, and 12115 is 32 * 378 + 18 + 1, so
  the character is 32-based and the column one-based.
  -------------------------------------------------------------------------- }

procedure CopyScreen(SrcSeg, DestSeg : Word); assembler;
asm
  PUSH DS               { DS becomes the source segment below               }
  MOV  AX, DestSeg      { the second declared parameter                     }
  MOV  ES, AX           { ES: is the destination                            }
  MOV  AX, SrcSeg       { the first                                         }
  MOV  DS, AX           { DS: is the source                                 }
  MOV  SI, 0            { both start at offset 0 -- whole screens           }
  MOV  DI, 0
  MOV  CX, $7D00        { 32,000 words = 64,000 bytes                       }
  REP  MOVSW            { the blit, one instruction                         }
  POP  DS               { restore our data segment                          }
end;

{ --------------------------------------------------------------------------
  show the scroller and shift it. HAND ASSEMBLER, verbatim.
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
{ --------------------------------------------------------------------------
  write ONE column of one glyph into the buffer's run-up.

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
  { SIX BYTES, OF WHICH ONE IS THE ONLY VARIABLE THAT MATTERS. One slot is
    written once and never read, and one is never reached at all -- both are
    the original's, kept so the frame is the size it should be. There is no
    pointer local: the font byte is read straight into a register. }
  Row    : Integer;
  Unread : Integer;               { never touched }
  Edge   : Integer;               { assigned and never read }
begin
  Edge := ScrollEdge;
  for Row := 0 to ScrollRows - 1 do
    { AND THE DESTINATION CARRIES NO Ofs(): only the SEGMENT of ScrollBuf is
      used, and the offset is the arithmetic below and nothing else. }
    Mem[Seg(ScrollBuf^) : Row * ScrollPitch + ScrollEdge] :=
      Font^[Ch, Col, Row + 1];
end;

{ --------------------------------------------------------------------------
  one frame of the scroller.

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
  { ONE BYTE OF FRAME, AND IT DOES BOTH JOBS -- it holds the palette entry
    about to be overwritten and then serves as the `for` counter. There is no
    separate pass counter, because the rotation is written out twice rather
    than looped; adding one would grow the frame. }
  Last : Byte;                    { then the colour index }
begin
  Inc(ScrollCol, 2);
  { `>= GlyphCols + 1`, NOT `> GlyphCols` -- the same test, but the two
    spellings compare against different immediates and invert the condition. }
  if ScrollCol >= GlyphCols + 1 then
  begin
    ScrollCol := 1;
    Inc(ScrollIdx);
  end;

  { PAST THE END OF THE MESSAGE THE SCROLLER FEEDS SPACES, and that arm is the
    THEN rather than the ELSE -- the compiler emits it first, so writing the
    test the other way round exchanges the two arms. }
  if ScrollIdx > TextLen then                   { CMP AL,$EC }
    ScrollChar(Ord(' '), ScrollCol)
  else
    ScrollChar(Ord(Message[ScrollIdx]), ScrollCol);

  ScrollRender;

  { the two side animations, three frames each shown four ticks
    apart, one counting up and the other down so they mirror. }
  SideTick := (SideTick mod 11) + 1;
  Blit(@SideAnim[4 - ((SideTick shr 2) + 1)], $116, $1B, 14, 10, WorkSeg);
  Blit(@SideAnim[(SideTick shr 2) + 4],       $1E,  $1B, 14, 10, WorkSeg);

  { rotate the eight-entry cycle and show it. The original does
    the whole thing TWICE per frame, so the colours run at double speed. }
  Last := ScrollPal[24];
  Move(ScrollPal[1], ScrollPal[4], 21);
  FillChar(ScrollPal[1], 3, Last);
  for Last := 0 to 7 do                          { the same byte }
    SetRGB($80 + Last, ScrollPal[Last * 3 + 1],
           ScrollPal[Last * 3 + 2], ScrollPal[Last * 3 + 3]);

  { and again, written out rather than looped }
  Last := ScrollPal[24];
  Move(ScrollPal[1], ScrollPal[4], 21);
  FillChar(ScrollPal[1], 3, Last);
  for Last := 0 to 7 do
    SetRGB($80 + Last, ScrollPal[Last * 3 + 1],
           ScrollPal[Last * 3 + 2], ScrollPal[Last * 3 + 3]);
end;

{ ==========================================================================
  The lemmings
  ========================================================================== }

{ free every slot. }

{ --------------------------------------------------------------------------
  the hillside's own animation, three frames of 43 x 24 at
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
  the title screen slides in one column at a time.

  Every column of the screen gets a random head start of Random(200) - 400,
  so they all begin off the top by different amounts. Each of 400 passes
  walks the 200 columns and, for any whose offset has reached zero, copies
  that column down the screen; the rest just count up. The result is 200
  vertical strips arriving at staggered times.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  blank the DAC, put the hillside up, fade it in, then run a
  seven-frame animation BACKWARDS at (5, 50) and start the music.
  -------------------------------------------------------------------------- }
procedure Intro;
var
  { I IS DECLARED FIRST, and declaration order decides which local gets the
    one-byte displacement -- so this costs a byte on each of nine references if
    it is the other way round. }
  I   : Integer;
  Pal : TPal768;
begin
  GetPalette768(@Pal);
  for I := 0 to 255 do SetRGB(I, 0, 0, 0);
  CopyScreen(VirtScrSeg, $A000);
  PaletteFadeUp(@Pal, 0);

  for I := 6 downto 1 do
  begin
    FillRect(5, $32, $46, $4A, 0, VirtScrSeg);
    Blit(@IntroAnim[I], 5, $32, 65, 24, VirtScrSeg);
    CopyScreen(VirtScrSeg, $A000);
    Delay($96);                                  { 150 }
  end;

  MusicStart;
end;

{ the two heap blocks the scene needs beyond the virtual screen. }

{ THE LEMMING COMES FIRST, then the state. Parameter order is not free here:
  it decides which slot each argument occupies in the frame, so getting it the
  wrong way round changes the code at every call site rather than failing to
  compile. }
procedure SetState(N : Integer; S : Byte);
begin
  Lem[N].State := S;
  Lem[N].Frame := 1;
  Lem[N].Tick  := 0;
end;

{ --------------------------------------------------------------------------
  state 2, falling.

  Looks one row down across seven columns. Landing on Ground turns it back
  into a walker unless it has fallen 11 pixels or more, in which case the
  SECOND such landing splats it -- the first is survived and counted.
  Landing on the $20..$29 hazard stripe is always fatal.

  While it has nothing under it, it drifts one pixel in its facing direction
  for the first two rows of the fall only, then drops straight.
  -------------------------------------------------------------------------- }
procedure Faller(N : Integer);
var
  { AN OUTER LOOP THAT RUNS EXACTLY ONCE -- `for DY_ := 1 to 1`. Odd as it
    looks, the loop variable is used: it is the Y offset added to the lemming's
    position, so replacing it with the literal 1 changes the code.

    AND IT IS A `for`, NOT A `repeat`. The distinction decides where the
    increment goes -- a `for` puts it above the body -- and therefore whether
    the code after the loop is inside it or outside. }
  DY_ : Integer;
  DX_ : Integer;
  Pix : Byte;
begin
  for DY_ := 1 to 1 do
  begin
    for DX_ := -3 to 3 do
    begin
      Pix := GetPixel(Lem[N].X + DX_, Lem[N].Y + DY_, VirtScrSeg);
      if Pix in Ground then
      begin
        { A FALL OF MORE THAN TEN BOUNCES; anything shorter is survived outright.
          The bounce is the THEN arm, not the ELSE -- `> 10` and `< 11` are the
          same condition but put the two arms in opposite orders. }
        if Lem[N].FallDist > 10 then
        begin
          Inc(Lem[N].Bounces);
          if Lem[N].Bounces = 2 then
            SetState(N, StSplat)
          else
          begin
            SetState(N, StWalker);
            Lem[N].Y := Lem[N].Y + DY_ - 1;
            Lem[N].FallDist := 0;
          end;
        end
        else
        begin
          SetState(N, StWalker);
          { + DY_ - 1, which is nothing while DY_ is 1 -- transcribed because
 adds it. }
          Lem[N].Y := Lem[N].Y + DY_ - 1;
          Lem[N].FallDist := 0;
        end;
        Lem[N].Frame := (Lem[N].Frame mod 4) + 1;
        Exit;
      end;
      case Pix of $20..$29 :
        begin
          SetState(N, StDeathB);
          Exit;
        end;
      end;
    end;

  end;

  { and this is AFTER the loop, reached when nothing was found.

    WRITTEN OUT IN FULL, NOT WITH `Inc`, AND THAT IS DELIBERATE. `Inc` on an
    indexed field increments the memory in place and computes the subscript
    once; the longhand form loads the field into a register, changes it there
    and stores it back, recomputing the subscript for each access. The two are
    not interchangeable here -- roughly forty bytes separate them in this
    routine alone. Do not tidy these into `Inc`.

    AND THE WALK PRICED IT AT ONE BYTE. Because it locates code by content it
    found both frame-step blocks, just 40 bytes apart instead of the original's
    spacing, and reported only the single byte where a JMP changed from near to
    short. The way it was actually found was to locate the same recognisable
    block in both images and compare its OFFSETS: 0c6b and 0d01 in the
    original, 0c6b and 0cd9 in ours. }
  if Lem[N].FallDist < 2 then
    Lem[N].X := Lem[N].X + Lem[N].Dir;
  Lem[N].Y := Lem[N].Y + 1;
  Lem[N].FallDist := Lem[N].FallDist + 1;
  Lem[N].Frame := (Lem[N].Frame mod 4) + 1;
end;


{ --------------------------------------------------------------------------
  state 5, building.

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
      { WRITTEN OUT IN FULL RATHER THAN WITH `Inc`, as elsewhere in this unit,
        and the difference shows in the FRAME as well as the length: `Inc` on
        an indexed field needs a slot for the address, so using it here gives
        the routine locals the original does not have.

        NOT EVERY `Inc` IN THIS UNIT IS WRONG -- Bounces really is the short
        form. The rule is about indexed fields, not about `Inc`. }
  Lem[N].Tick := Lem[N].Tick + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    Lem[N].Frame := (Lem[N].Frame mod 6) + 1;
    if Lem[N].Frame = 6 then
    begin
      { WRITTEN OUT IN FULL, as the note at the top of this routine says. One
        detail is worth keeping in view: the original steps by two with two
        INCs rather than an ADD of 2 -- two bytes against three -- and writing
        `+ 2` is what produces that. }
      Lem[N].X := Lem[N].X + 2;
      Lem[N].Y := Lem[N].Y - 1;
      HLine(Lem[N].X - 2, Lem[N].X + 2, Lem[N].Y + 2,
            BrickColour, VirtScrSeg);
    end;
  end;
  if Lem[N].Tick = 500 then
  begin
    SetState(N, StWalker);
    Lem[N].Timer := $14;
  end;
end;

{ state 8. On the fourth frame it stamps the last splat picture
  PERMANENTLY into the hillside and removes itself, so the mark stays. }

{ --------------------------------------------------------------------------
  state 4, the DIAGONAL digger.

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
  { FOUR DECLARED LOCALS AND ONE COMPILER TEMPORARY, in eight bytes. The
    temporary is the `for` loop's upper bound, evaluated once -- which is why
    there is no variable for it and why declaring one would be wrong. }
  Unread : Integer;               { never read }
  Col    : Integer;
  Hit    : Boolean;
  Pix    : Byte;
begin
  Hit := False;
  { THE RIGHTWARD BRANCH IS THE THEN ARM, and the test is `Dir > 0` -- neither
    `Dir < 1`, which exchanges the arms, nor `Dir >= 1`, which is the same
    condition written with a different immediate. }
  if Lem[N].Dir > 0 then
  begin
    for Col := Lem[N].X - 3 to Lem[N].X + 3 + 1 do
    begin
      Pix := GetPixel(Col, Lem[N].Y + 1, VirtScrSeg);
      if Pix in Wall then Hit := True;
    end;

    { EVERY CONSTANT IS WRITTEN THE WAY THE ORIGINAL COMPUTES IT, because Turbo
      Pascal emits one operation per operator instead of folding first: `+ 3 + 5`
      is ADD AX,3 / ADD AX,5, `+ 3 + 1 + 1` is ADD AX,3 / INC AX / INC AX, and
      `- 9 - 0` really does emit SUB AX,0. Collapsing them to + 8 and - 9 is a
      different instruction stream for the same arithmetic. }
    VLine(Lem[N].X + 3 + 1,     Lem[N].Y - 9 - 1,     Lem[N].Y,
          0, VirtScrSeg);
    VLine(Lem[N].X + 3 + 1 + 1, Lem[N].Y - 9 - 0,     Lem[N].Y - 0,
          0, VirtScrSeg);
    VLine(Lem[N].X + 3 + 3,     Lem[N].Y - 9 + 1,     Lem[N].Y - 1,
          0, VirtScrSeg);
    VLine(Lem[N].X + 3 + 4,     Lem[N].Y - 9 + 1 + 1, Lem[N].Y - 1 - 1,
          0, VirtScrSeg);
    VLine(Lem[N].X + 3 + 5,     Lem[N].Y - 9 + 3,     Lem[N].Y - 3,
          0, VirtScrSeg);
    HLine(Lem[N].X - 3, Lem[N].X + 3 + 1 + 1, Lem[N].Y,
          0, VirtScrSeg);
  end
  else
  begin
    for Col := Lem[N].X - 3 to Lem[N].X + 3 do
    begin
      Pix := GetPixel(Col, Lem[N].Y + 1, VirtScrSeg);
      if Pix in Wall then Hit := True;
    end;

    DrawLine(Lem[N].X - 3 + 1,     Lem[N].Y - 9 - 1 - 1,
             Lem[N].X - 3 + 1,     Lem[N].Y + 1,
             0, VirtScrSeg);
    DrawLine(Lem[N].X - 3 + 1 + 1, Lem[N].Y - 9 - 1 - 1,
             Lem[N].X - 3 + 1 + 1, Lem[N].Y + 1,
             0, VirtScrSeg);
    DrawLine(Lem[N].X - 3 - 1 - 1, Lem[N].Y + 1,
             Lem[N].X + 3 + 1 + 1, Lem[N].Y + 1,
             0, VirtScrSeg);
  end;

  Lem[N].Tick := (Lem[N].Tick mod 3) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    Lem[N].Frame := (Lem[N].Frame mod 6) + 1;
    if Lem[N].Frame mod 6 = 0 then
    begin
      { THE X STEP IS EVALUATED IN 32 BITS, because X is a Word and Dir is
        signed: mixing the two promotes the whole expression, and the result is
        assigned back into a Word. That is why there is a cast here at all.

        AND THE CAST GOES OUTSIDE THE DOUBLING, not inside it. Doubling in
        sixteen bits and then widening is not the same as widening first and
        then multiplying -- the second calls the runtime's 32-bit multiply. }
      Lem[N].X := Lem[N].X + LongInt(Lem[N].Dir * 2);
      Lem[N].Y := Lem[N].Y + 1;
    end;
  end;

  if not Hit then SetState(N, StWalker);
end;


procedure Tunneller(N : Integer);
var
  { FOUR DECLARATIONS AND TWO TEMPORARIES, in ten bytes. The two temporaries
    are the nested loops' upper bounds, each evaluated once -- so neither bound
    is a variable here, and declaring them would produce them twice over. }
  Row  : Integer;
  Col  : Integer;
  Hit  : Boolean;
  Pix  : Byte;                    { the pixel is READ INTO A BYTE
                                    before it is tested; inside the `in` test
                                    it stays in a register and loses the slot }
begin
  Hit := False;
  { THE RIGHTWARD BRANCH IS THE THEN ARM HERE TOO, and the test is `Dir > 0`
    for the same reason as the digger's above. }
  if Lem[N].Dir > 0 then
  begin
    for Col := Lem[N].X + 3 + 1 to Lem[N].X + 3 + 1 + 1 do
      for Row := Lem[N].Y - 9 to Lem[N].Y do
      begin
        Pix := GetPixel(Col, Row, VirtScrSeg);
        if Pix in Wall then Hit := True;
      end;

    { Every constant is written as the original computes it -- one operation
      per operator, so `+ 3 + 1 + 1` is ADD AX,3 / INC AX / INC AX and `+ 3 + 0`
      really does emit ADD AX,0. See the wiki's one-operation-per-operator. }
    VLine(Lem[N].X + 3 - 1 - 1, Lem[N].Y - 9 - 1,     Lem[N].Y,
          0, VirtScrSeg);
    VLine(Lem[N].X + 3 - 1,     Lem[N].Y - 9,         Lem[N].Y - 1,
          0, VirtScrSeg);
    VLine(Lem[N].X + 3 + 0,     Lem[N].Y - 9 + 1,     Lem[N].Y - 1 - 1,
          0, VirtScrSeg);
    VLine(Lem[N].X + 3 + 1,     Lem[N].Y - 9 + 1 + 1, Lem[N].Y - 3,
          0, VirtScrSeg);
    VLine(Lem[N].X + 3 + 1 + 1, Lem[N].Y - 9 + 3,     Lem[N].Y - 4,
          0, VirtScrSeg);
    VLine(Lem[N].X + 3 + 3,     Lem[N].Y - 9 + 4,     Lem[N].Y - 5,
          0, VirtScrSeg);
  end
  else
  begin
    for Col := Lem[N].X - 3 - 1 - 1 to Lem[N].X - 3 - 1 do
      for Row := Lem[N].Y - 9 to Lem[N].Y do
      begin
        { USED WHERE IT IS PRODUCED, HERE AND ONLY HERE. The other three sites
          of this pair store the pixel into Pix first and match as written;
          this one uses the returned value directly, because storing it and
          reading it back costs six bytes for a byte already in the register. }
        if GetPixel(Col, Row, VirtScrSeg) in Wall then Hit := True;
      end;

    VLine(Lem[N].X - 3 - 1,     Lem[N].Y - 9,         Lem[N].Y,
          0, VirtScrSeg);
    VLine(Lem[N].X - 3 - 1 - 1, Lem[N].Y - 9 + 1 + 1, Lem[N].Y - 1 - 1,
          0, VirtScrSeg);
    VLine(Lem[N].X - 3 - 3,     Lem[N].Y - 9 + 3,     Lem[N].Y - 3,
          0, VirtScrSeg);
  end;

  Lem[N].Frame := (Lem[N].Frame mod 3) + 1;
  if Lem[N].Frame mod 3 = 0 then
    { WRITTEN OUT AND WIDENED, like the tunneller's step above and for the
      same reason: a Word plus a signed value is a 32-bit expression assigned
      back into sixteen bits. }
    Lem[N].X := Lem[N].X + LongInt(Lem[N].Dir);

  if not Hit then SetState(N, StWalker);
end;

{ --------------------------------------------------------------------------
  state 1, walking.

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
label
  Stand, Move;
var
  { TEN BYTES, AND ONLY SIX OF THEM ARE DECLARED -- the other four are the
    COMPILER'S. A `for` whose upper bound is an expression evaluates it once
    into a temporary, and these loops nest one deep, so two such temporaries
    are live at a time. They cannot be declared and must not be: declaring them
    would give the routine fourteen bytes of frame instead of ten.

    AND THAT IS WHY THERE IS NO Standing AND NO Climbed FLAG. The loops are
    left by jumping straight to the code that follows them; a Boolean set
    inside the loop and tested after it is the re-expression, and it costs the
    flag, the test and the branch around it. }
  DX_   : Integer;                { the ground offset first, then
                                    the ROW of both later loops: one variable
                                    doing three jobs }
  Col   : Integer;
  Spare : Byte;                   { never read -- a byte declared
                                    after a word lands here, and Pix is at
                                    $06, so something occupies $05 }
  Pix   : Byte;
begin
  for DX_ := -3 to 3 do
  begin
    Pix := GetPixel(Lem[N].X + DX_, Lem[N].Y + 1, VirtScrSeg);
    { A CASE, NOT AN `or` CHAIN. A case loads the selector into a register once
      and compares against it; an `or` of three comparisons re-reads the byte
      from memory for each. The two are not interchangeable. }
    case Pix of
      DeathAColour, StuckColour, $20..$29 :
        begin
          { THREE MORE CASES, not three ifs, and for the same reason as above:
            a case loads the selector into a register, an `if` on a byte
            variable compares memory against the immediate directly. }
          case Pix of $20..$29     : SetState(N, StDeathB) end;
          case Pix of DeathAColour : SetState(N, StDeathA) end;
          case Pix of StuckColour  : SetState(N, StStuck)  end;
          Exit;
        end;
    end;
    if Pix in Ground then goto Stand;
  end;

  { the loop ran out, so there is nothing under it anywhere. This
    is the code AFTER the for loop, which is why the loop's own bottom test at
 branches straight into it. }
  SetState(N, StFaller);
  Exit;

Stand:
  { the wall ahead, head height. The bound is written as two
    additions because that is what the original computes: ADD AX,3 then INC AX
    twice, which is `+ 3 + 2` and not `+ 5` -- Turbo Pascal emits one operation
    per operator rather than folding the constants first. }
  for DX_ := Lem[N].Y - 9 to Lem[N].Y - 4 do
    if Lem[N].Dir > 0 then
    begin
      for Col := Lem[N].X + 3 to Lem[N].X + 3 + 2 do
        if GetPixel(Col, DX_, VirtScrSeg) in Wall then
        begin
          Lem[N].Dir := -Lem[N].Dir;
          Exit;
        end;
    end
    else
      for Col := Lem[N].X - 3 - 2 to Lem[N].X - 3 do
        if GetPixel(Col, DX_, VirtScrSeg) in Wall then
        begin
          Lem[N].Dir := -Lem[N].Dir;
          Exit;
        end;

  { a step it can climb rather than a wall.

    The moment this finds one it writes the new Y and jumps OUT of both loops
    to the move. Letting the row loop carry on instead is NOT the same thing:
    the new Y is one less than the current row, so a loop that kept going would
    step back onto the row it just left and stay there. }
  for DX_ := Lem[N].Y - 4 to Lem[N].Y do
    if Lem[N].Dir > 0 then
    begin
      for Col := Lem[N].X + 3 to Lem[N].X + 3 + 1 do
        if GetPixel(Col, DX_, VirtScrSeg) in Wall then
        begin
          Lem[N].Y := DX_ - 1;
          goto Move;
        end;
    end
    else
      for Col := Lem[N].X - 3 - 1 to Lem[N].X - 3 do
        if GetPixel(Col, DX_, VirtScrSeg) in Wall then
        begin
          Lem[N].Y := DX_ - 1;
          goto Move;
        end;

Move:
  { WRITTEN OUT AND WIDENED, the third site of this shape in the unit. }
  Lem[N].X := Lem[N].X + LongInt(Lem[N].Dir);
  Lem[N].Tick := (Lem[N].Tick mod 2) + 1;
  if Lem[N].Tick mod 2 = 0 then
    Lem[N].Frame := (Lem[N].Frame mod 4) + 1;
end;

{ state 8. On the fourth frame it stamps the last splat picture
  PERMANENTLY into the hillside and removes itself, so the mark stays. }
procedure Splat(N : Integer);
begin
  { WRITTEN OUT IN FULL RATHER THAN WITH `Inc`, and here the give-away was the
    PROLOGUE rather than the statement: this routine declares no locals, so a
    frame of any size means it is holding temporaries -- which `Inc` on an
    indexed field does not need and the longhand form does. }
  Lem[N].Frame := Lem[N].Frame + 1;
  if Lem[N].Frame = 4 then
  begin
    Blit(@SplatBank[4], Lem[N].X - 4, Lem[N].Y - 9, 12, 10, VirtScrSeg);
    Remove(N);
  end;
end;

{ state 6. Six frames, one every fifth tick, then gone. }

{ state 6. Six frames, one every fifth tick, then gone. }
procedure DeathA(N : Integer);
begin
  Lem[N].Tick := (Lem[N].Tick mod 5) + 1;
  if Lem[N].Tick mod 5 = 0 then
  begin
    Lem[N].Frame := Lem[N].Frame + 1;
    if Lem[N].Frame > 6 then Remove(N);
  end;
end;

{ state 7. Five frames, one every third tick, then gone. }

{ state 7. Five frames, one every third tick, then gone. }
procedure DeathB(N : Integer);
begin
  Lem[N].Tick := (Lem[N].Tick mod 3) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    Lem[N].Frame := Lem[N].Frame + 1;
    if Lem[N].Frame > 5 then Remove(N);
  end;
end;

{ state 3, the lit fuse. Five frames, then it explodes. }

{ state 3, the lit fuse. Five frames, then it explodes. }
procedure Fuse(N : Integer);
begin
  Lem[N].Tick := (Lem[N].Tick mod 3) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    Lem[N].Frame := Lem[N].Frame + 1;
    if Lem[N].Frame > 5 then SetState(N, StExplode);
  end;
end;

{ --------------------------------------------------------------------------
  state 11, the explosion.

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
  { C IS DECLARED FIRST, and the order is not cosmetic: first declared sits
    nearest BP and gets the shorter displacement, on every one of the fourteen
    references in the loop below. }
  C, Pass : Integer;
  RGB     : array[0..2] of Byte;
begin
  Lem[N].Tick := (Lem[N].Tick mod 5) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    { WRITTEN OUT, NOT `Inc()`, as elsewhere in this unit -- and note that BOTH
      spellings appear in the original: Faller's `Inc(Lem[N].Bounces)` really
      is the short form. The rule is per site, not per unit. }
    Lem[N].Frame := Lem[N].Frame + 1;
    if Lem[N].Frame < 10 then
      for Pass := 1 to 5 do
        for C := $E0 to $E9 do
        begin
          { ALL THREE TESTS READ RGB[0], AND THAT IS A BUG IN THE ORIGINAL --
            the RED channel is compared against the green and blue targets,
            while the increments go to each channel in turn. It is reproduced
            because it is what the original does, and the fade it produces is
            what the demo actually looks like.

            It is not subtle in effect. Red is also the channel the first test
            may have just incremented, so the green and blue comparisons read a
            value one higher than the one that was measured. Where red is
            already at or above a target the other channel stops rising even
            though it has not arrived, and where red is below all three, all
            three rise together. The explosion's flash comes up REDDER than the
            scene palette it is fading towards.

            Transcribed as it is. A reconstruction that reads RGB[1] and RGB[2]
            is the tidier program and the wrong one.

            AND THE PALETTE IS TWO-DIMENSIONAL, which is what folds the
            channel into the displacement -- a constant second subscript costs
            nothing at run time where a flat `C * 3 + 1` adds the offset each
            time.

            (An earlier version of this note claimed the comparison had to be
            written `ScenePal[..] > RGB[0]` to make Turbo Pascal load RGB[0]
            first. It does not: both spellings emit the same code, and the
            81-byte span shrank because of the C/Pass declaration order in the
            var block above, not because of the operator. Kept because the
            wrong reason survived a measurement that appeared to confirm it --
            two changes went in together and only one of them did anything.) }
          GetRGBTo(C, @RGB);
          if RGB[0] < ScenePal[C, 0] then Inc(RGB[0]);
          if RGB[0] < ScenePal[C, 1] then Inc(RGB[1]);
          if RGB[0] < ScenePal[C, 2] then Inc(RGB[2]);
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
  one pass over every slot.

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
      { the scripted trigger, and it is TWO comparisons, not four.
        There is no test against zero anywhere in the original; the `>= 0`
        guards this used to carry were four comparisons it does not make.

        THE TRIG FIELD IS ON THE LEFT, and it has to be: for a comparison
        widened to LongInt Turbo Pascal evaluates the RIGHT operand first, so
        the operand order in the source is the reverse of the order in the
        code. }
      if (Lem[N].TrigX = Lem[N].X) and (Lem[N].TrigY = Lem[N].Y) then
      begin
        SetState(N, Lem[N].TrigState);
        Lem[N].TrigX := 0;
        Lem[N].TrigY := 0;
      end;

      if Lem[N].Timer > 0 then Dec(Lem[N].Timer);
      if Lem[N].Timer = 1 then SetState(N, StFuse);
      if Lem[N].Timer < 0 then Inc(Lem[N].Timer);
      if Lem[N].Timer = -1 then Remove(N);

      DrawSprite(Lem[N]);

      case Lem[N].State of
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
  the frame loop.

  IT DOES NOT EXIT ON A KEY. A keypress -- or the last lemming dying -- only
  starts the ending: from then on every frame fades the palette one step and
  drops the tracker volume TWICE, and the loop ends when the volume reaches
  zero. So how long the scene runs past the keypress depends on how loud the
  music was, and with no tracker resident GetVolume returns 0 and it stops on
  the first frame.
  -------------------------------------------------------------------------- }
procedure MainLoop;
var
  { THE DECLARATION ORDER IS Frame, V, Done, I, and it decides the frame's
    layout: consecutive declarations take consecutive slots, so rearranging
    these four moves every reference to them. }
  Frame : Integer;
  V     : Byte;
  Done  : Boolean;
  I     : Integer;
begin
  LiveCount := 0;
  Spawned   := 0;
  Frame     := 0;
  HillTick  := 1;
  InitAll;
  Spawn;
  Done := False;
  repeat
    CopyScreen(VirtScrSeg, WorkSeg);             { the clean hillside }
    BackdropAnim;
    UpdateAll;
    ScrollStep;
    Inc(FrameCount);
    CopyScreen(WorkSeg, $A000);

    Inc(Frame);
    if Frame mod SpawnEvery = 0 then Spawn;

    if KeyPressed or (LiveCount = 0) then
    begin
      FadeStep;
      { fade the scroller's colour cycle out with it, and it is
        ONE loop over all twenty-four bytes rather than eight passes of three:
 indexes [DI+$F4] with DI the counter itself, no multiply, and
 compares it against $18. }
      for I := 1 to 24 do
        { `> 0`, not `<> 0` -- the two are equivalent for an unsigned value
          but emit different branches. }
        if ScrollPal[I] > 0 then Dec(ScrollPal[I]);

      V := GetVolume;
      if V = 0 then Done := True else SetVolume(V - 1);
      V := GetVolume;
      if V = 0 then Done := True else SetVolume(V - 1);
    end;
  until Done;
end;

{ --------------------------------------------------------------------------
  Demo_Main.
  -------------------------------------------------------------------------- }

{ the two heap blocks the scene needs beyond the virtual screen. }
procedure Setup;
begin
  GetMem(WorkScr, 64000);
  GetMem(ScrollBuf, ScrollSize);
  FillChar(ScrollBuf^, ScrollSize, 0);
  WorkSeg := Seg(WorkScr^);
end;

{ --------------------------------------------------------------------------
  Demo_Main.
  -------------------------------------------------------------------------- }
procedure RunPart4;
begin
  MusicDetect;
  Setup;
  LoadAssets;
  Intro;
  SavedVol := GetVolume;
  MainLoop;
  FreeMem(WorkScr, 64000);
  FreeMem(ScrollBuf, ScrollSize);
  MusicStop;
  SetVolume(SavedVol);                           { put it back as we found it }
  { A LEFTOVER DEBUG PRINT, and it is the last thing the part does. It is kept
    because the original has it -- the count of lemmings spawned, written to
    the screen as part 004 ends.

    XOR DX,DX AND NOT CWD, so Spawned is a Word rather than an Integer -- an
    Integer widens signed. Kept as it is: the number lands on the console
    behind the demo's own screen and nobody sees it, but it is what ships. }
  WriteLn(Spawned);
end;

{ the unit's initialisation body is empty. }

begin
end.
