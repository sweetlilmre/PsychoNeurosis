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
{$I-}   { NO I/O CHECK, and this unit had no I directive at all so it took the
          command line's default of $I+. LoadAssets' compiled I/O carries a
          five-byte near call to the runtime's check routine after Reset, Seek
          and every BlockRead; the original has none of them -- 1005:00c0's
          Reset is followed straight by the next MOV DI. Twenty-nine call
          sites in this unit, 145 bytes, and every instruction after the first
          of them was out of step. Every other part's units carry the
          directive; this one was simply missed. }

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
  TextLen     = $EC;          { 236 -- and 1005:08C7 compares ScrollIdx against
                                exactly this, so the message is 236 characters
                                indexed from ONE, not 237 indexed from zero }

  DataOfs     = $001228CE;    { NEUROSIS.DAT -- 1,189,070 }

type
  { 21 bytes -- DS:$0311, indices 1..25, running to DS:$051D. }
  TLem = record
    X          : Word;        { +0  -- UNSIGNED, and the arithmetic proves it:
                                       1005:14EC computes Lem[N].X + DX_ in
                                       THIRTY-TWO bits (CWD on the offset, XOR
                                       DX,DX on X, then ADD/ADC), which is what
                                       Turbo Pascal does when a Word meets a
                                       signed Integer. Two Integers would have
                                       stayed 16-bit. }
    Y          : Word;        { +2  -- UNSIGNED TOO, and UpdateAll is where it
                                       shows: 1005:1A9D reads Y and follows it
                                       with XOR DX,DX while 1005:1AAB reads
                                       TrigY and follows it with CWD, so the
                                       comparison Y = TrigY is a Word against an
                                       Integer widened to LongInt. An earlier
                                       pass left Y signed on the grounds that
                                       nothing promoted around it; nothing did
                                       in Walker, and this routine is where it
                                       does. }
    { THREE MORE UNSIGNED FIELDS, and the divide instruction names them: every
      `mod` on Frame and Tick is XOR DX,DX / DIV -- 1005:1960 and 1005:1979 --
      where a signed Integer would give CWD / IDIV. Bounces goes with them. }
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
  { THE ORDER IS THE ORIGINAL'S AND THE ADDRESSES CHAIN EXACTLY. ColOfs is at
    DS:$0172 and 402 bytes long, so it ends at $0303; SavedVol is the byte at
    $0304; WorkScr and ScrollBuf are the two pointers at $0305 and $0309;
    WorkSeg is the word at $030D; SideTick and HillTick are the bytes at $030F
    and $0310; and Lem begins at $0311, 25 records of 21 bytes, ending exactly
    where LiveCount sits at $051E. Not one byte of slack anywhere in that run.

    Declared with Lem first, as this block was, ColOfs came out at $0414 instead
    of $0172 -- 674 bytes late, which is Lem's 525 plus what follows it -- and
    every absolute reference in the part carried the difference.

    WHAT IS STILL MISSING IS THE EIGHTY BYTES BELOW ColOfs. The typed constants
    end at $0121 and ColOfs starts at $0172, so something occupies $0122..$0171
    and this unit does not declare it. }

  { DS:$0172 -- ColumnSlideIn's per-column start offset, 201 entries. }
  ColOfs     : array[0..200] of Integer;

  { DS:$0304 -- the tracker volume as we found it. }
  SavedVol   : Byte;

  { The two screens. VirtScrSeg (VGA, DS:$CF8C here) holds the hillside and is
    what GetPixel reads; this one is composed into each frame. DS:$0305 and
    DS:$030D. }
  WorkScr    : Pointer;

  { DS:$0309 -- 18 rows of 341, the scroller's own bitmap. }
  ScrollBuf  : Pointer;

  WorkSeg    : Word;

  { DS:$030F and DS:$0310 -- the two background animations' counters. }
  SideTick   : Byte;
  HillTick   : Byte;

  { DS:$0311 }
  Lem        : array[1..MaxLem] of TLem;
  { DS:$051E and DS:$0520 }
  LiveCount  : Integer;
  { A WORD, NOT AN INTEGER, and the WriteLn at the end of Demo_Main is what
    says so: 1005:1d28 widens it with XOR DX,DX where an Integer widens with
    CWD. Nothing else in the part distinguishes them -- every comparison is
    against a small positive constant. }
  Spawned    : Word;




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
  { THREE DIMENSIONS, NOT ONE, and the subscripts are the raw character and
    column. ScrollChar computes its address as IMUL AX,[BP+$06],$17A then
    IMUL AX,[BP+$04],$12 then + (Row + 1) -- two strides of 378 and 18 against a
    single folded displacement of -$2F53. A flat array indexed with the
    subtractions written out computes them at run time instead; here they are in
    the low bounds, and -(32 * 378 + 18 + 1) is exactly -$2F53, which is what
    fixes FirstChar at 32 and the bounds at 1 and 1. }
  TFont     = array[FirstChar..FirstChar + GlyphCount - 1,
                    1..GlyphPitch div ScrollRows,
                    1..ScrollRows] of Byte;                    { DS:$CC03 }
var
  WalkBank  : array[1..8]  of array[0..53]   of Byte;   { DS:$0522 }
  TumbleBk  : array[1..4]  of array[0..99]   of Byte;   { DS:$06D2 }
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
  Unknown   : array[1..7]  of array[0..377]  of Byte;   { DS:$0862, 2,646 }
  SplatBank : array[1..4]  of array[0..119]  of Byte;   { DS:$12B8 }
  DigBank   : array[1..6]  of array[0..220]  of Byte;   { DS:$1498 }
  TunnelBk  : array[1..3]  of array[0..139]  of Byte;   { DS:$19C6 }
  DeathBBk  : array[1..5]  of array[0..159]  of Byte;   { DS:$1B6A }
  DeathABk  : array[1..6]  of array[0..107]  of Byte;   { DS:$1E8A }
  BuildBank : array[1..6]  of array[0..119]  of Byte;   { DS:$2112 }
  FuseBank  : array[1..5]  of array[0..149]  of Byte;   { DS:$23E2 }
  Explosion : array[1..7]  of array[0..3464] of Byte;   { DS:$26D0 }
  HillAnim  : array[1..3]  of array[0..1031] of Byte;   { DS:$858F }
  IntroAnim : array[1..7]  of array[0..1559] of Byte;   { DS:$91A7 }
  SideAnim  : array[1..6]  of array[0..139]  of Byte;   { DS:$BC4F }

  { --------------------------------------------------------------------------
    AND THESE FOUR ARE LAST, in this order, because the addresses tile from
    SideAnim to the next unit's first variable with nothing left over:

        SideAnim   $BC4F   840
        DeathAPic  $BF97  3180
        Font       $CC03     4   -- a POINTER, which is why the gap is four
        ScenePal   $CC07   768
        F          $CF07   128   -> ends $CF87, and VGA's VirtScr is $CF88

    Declared at the FRONT of this block, as ScenePal, F and Font were, they put
    900 bytes ahead of WalkBank -- 768 + 128 + 4 -- and every sprite bank's
    folded displacement carried it: 1005:043c reaches WalkBank[Frame] with
    ADD DI,$4EC where ours emitted ADD DI,$870, and $870 - $4EC is exactly 900.
    DeathAPic sat between FuseBank and Explosion for the same kind of reason
    and moved the four banks after it.
    -------------------------------------------------------------------------- }
  DeathAPic : array[0..3179] of Byte;    { DS:$BF97 -- 60 x 53, the storm
                                           cloud and its lightning bolt }
  Font      : ^TFont;                                   { DS:$CC03 }
  { DS:$CC07 -- the scene palette, which Explode fades entries $E0..$E9 up
    towards. TWO-DIMENSIONAL, entry by channel: Explode addresses its three
    channels as three consecutive displacements off one index of C*3, which is
    a constant second subscript. A flat array[0..767] adds the channel at run
    time. Same 768 bytes either way. }
  ScenePal   : array[0..255, 0..2] of Byte;
  { DS:$CF07 -- A GLOBAL, and LoadAssets had it as a local. 1005:00b1 is
    MOV DI,$CF07 / PUSH DS / PUSH DI into Assign, and every Reset, Seek,
    BlockRead and Close in the routine passes the same absolute address; a
    frame slot would be LEA DI,[BP-n] / PUSH SS. Three bytes against four, at
    twenty-two call sites, which is why the whole routine was out of step.

    AND THE ADDRESS TILES, which is what makes the placement here rather than
    anywhere else. ScenePal ends at $CF07 and VGA's VirtScr begins at $CF88 --
    129 bytes further on, which is this record plus one byte of padding. So it
    is the LAST variable this unit declares. }
  F          : file;                                  { DS:$CF07 }

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
  { UNTYPED, WHICH IS WHAT PUTS THEM IN THE CODE SEGMENT. A typed constant
    `Ground : set of Byte = [...]` is DGROUP data and every `in` test reads it
    with no segment prefix; an untyped set constant is a compile-time value and
    Turbo Pascal emits a fresh copy in CS at each use, which is why there are
    five copies of two distinct 32-byte constants rather than two. 1005:0BC9 is
    `TEST BYTE PTR CS:[DI+$B48], AL` and the prefix is the whole tell. }
  Ground =
    [4, 5, $0F, $15..$18, $1D, $1F, $33, $36, $3E..$40, $42..$47, $4D..$52];
  Wall   =
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

{ DS:$0006 -- the message, compiled into DGROUP, and ONE-BASED with no leading
  zero. The two images' DGROUPs settle it byte for byte: the original opens
  `00 00 00 00 00 00 20` and ours opened `00 00 00 20`. Six zeros then the
  leading space means two bytes, then FrameCount's four, then the text at
  $0006 -- so FrameCount is a TYPED CONSTANT in the initialised region and not
  a `var` in BSS, and the message has 236 characters rather than 237 with a #0
  in front. }
const
  { DS:$0002 -- a 32-bit count of frames drawn, bumped by MainLoop with
    ADD [0002],1 / ADC [0004],0. NOTHING IN PART 004 EVER READS IT, and it is
    kept because the original keeps it -- as initialised data, which is the
    only way it reaches $0002 at all. }
  FrameCount : LongInt = 0;                      { DS:$0002 }

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
  ScrollCol  : Integer = 0;                      { DS:$00F2 }
  ScrollIdx  : Byte    = 1;                      { DS:$00F4 }
  { FLAT AND ONE-BASED, not eight triples. Every reference computes the index
    at run time from a single byte counter -- 1005:098D is MOV SI,AX / SHL AX,1
    / ADD AX,SI / INC AX, which is `Last * 3 + 1` -- against a base displacement
    of $00F4, and $00F4 with a low bound of 1 is this array's own $00F5. A
    two-dimensional array folds the second subscript into the displacement
    instead, and MainLoop's fade then needs three statements where the original
    has one loop over all twenty-four bytes. }
  ScrollPal  : array[1..24] of Byte =            { DS:$00F5 }
    (7, 7, 7,  7, 7, 7,  7, 7, 7,  7, 7, 7,
     30, 30, 30,  30, 30, 30,  30, 30, 30,  30, 30, 30);

procedure SetState(N : Integer; S : Byte); forward;
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
  { TEN BYTES, NOT SIX. 1005:0000 opens ENTER $A and its slots are [BP-$02] four
    times, [BP-$04] three times and [BP-$0A] twice -- and SrcSeg, which the asm
    block reads and writes once each, is the pair at $0A. So the four bytes
    between [BP-$04] and [BP-$0A] are a declaration nothing reads. }
  C, Pass : Integer;              { [BP-$02], [BP-$04] }
  Unread  : LongInt;              { [BP-$08], four bytes, never read }
  SrcSeg  : Word;                 { [BP-$0A] }
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

{ --------------------------------------------------------------------------
  1005:00a6 -- everything off NEUROSIS.DAT, and the title sequence.
  -------------------------------------------------------------------------- }
procedure LoadAssets;
var
  { ENTER $686 -- 1,670 bytes -- and this routine declared 898. The arithmetic
    picks the missing item out on its own: 128 for the file record plus 768 for
    a palette is 896, and the original's two scalar slots are at [BP-$681] and
    [BP-$683], so everything above $681 is buffers. 128 + 768 + 768 is 1,664,
    which fills BP-1 down to BP-$680 exactly -- there is a SECOND 768-byte
    palette. Nothing in the routine reads it, and a local is allocated whether
    or not it is read. }
  { ENTER $686 -- 1,670 bytes -- AND ONLY TWO SLOTS ARE EVER TOUCHED:
    [BP-$683] seven times and [BP-$681] five. The whole layout follows from
    those two addresses and the total.

    [BP-$681] is the palette buffer -- 1005:0109 is LEA DI,[BP-$681] / PUSH SS
    in front of a 768-byte BlockRead -- so it occupies BP-$681 up to BP-$382.
    That leaves 897 bytes ABOVE it and five below, and the five are [BP-$683]
    for the loop counter plus one more slot and Turbo Pascal's rounding of an
    odd total up to even.

    THE 897 ABOVE IS TOUCHED BY NOTHING, and 768 + 128 + 1 is exactly 897 --
    a second palette, a file record, and a byte. The file record is the one
    worth naming: the routine's real file is the unit-level global at DS:$CF07
    now, so these 128 bytes are a SECOND record that is never opened. That is
    the seventh routine in this target to reserve storage it never uses.

    ORDER IS THE WHOLE POINT HERE. These same six declarations in the order
    F, Pal, Pal2, Spare, I, Spare2 also sum to $686, and the frame matched
    while the palette sat at [BP-$380] instead of [BP-$681] -- so every
    reference to it was four bytes of displacement different from the
    original's. A frame that matches says nothing about where inside it
    anything is. }
  Pal2   : TPal768;               { [BP-$300], never read }
  Unread : file;                  { [BP-$380], never opened }
  Spare  : Byte;                  { [BP-$381] }
  Pal    : TPal768;               { [BP-$681] }
  I      : Integer;               { [BP-$683] }
  Spare2 : Integer;               { [BP-$685] -- and BP-$686 is the pad }
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);

  GetMem(Font, SizeOf(TFont));                   { 1005:00BE }
  BlockRead(F, Font^, SizeOf(TFont));

  ClearScreen($A000, 0);
  BlockRead(F, Pal, SizeOf(Pal));
  SetPalette768(@Pal);
  { THE POINTER VARIABLE, not a Mem subscript. 1005:017a is LES DI,[$CF88] /
    PUSH ES / PUSH DI -- VGA's VirtScr loaded whole and pushed -- where
    `Mem[VirtScrSeg : 0]` reads the SEGMENT word at $CF8C and builds a pointer
    round it: MOV AX,[$CF8C] / PUSH AX / XOR DI,DI / POP ES / PUSH ES / PUSH DI.
    Same address either way, six bytes more to say it. }
  BlockRead(F, VirtScr^, 64000);                 { the title screen }

  ColumnSlideIn;                                 { 1005:0116 }
  Delay($514);                                   { 1300 }
  GetPalette768(@Pal);
  for I := 1 to $40 do FadeStep;                 { 1005:0132 }

  ClearScreen($A000, 0);
  BlockRead(F, VirtScr^, 64000);                 { the hillside }
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
{ IT TAKES THE LEMMING, NOT ITS INDEX, and it has no locals at all. 1005:03b9
  opens PUSH BP / MOV BP,SP with no ENTER, and every field access is
  `LES DI, [BP+$04]` followed by `ES:[DI+n]` -- so the parameter is a four-byte
  reference to the record and the routine reads through it. There is no F
  either: 1005:03C7 is `IMUL DI, ES:[DI+$06], $78`, the frame read straight out
  of the record at the point of use. A local F and an Integer index between them
  accounted for twelve of this part's unaligned spans. }
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
        if L.Dir < 1 then
          Blit(@WalkBank[L.Frame + 4], L.X - 3, L.Y - 8, 6, 9, WorkSeg)
        else
        begin
          Blit(@WalkBank[L.Frame], L.X - 3, L.Y - 8, 6, 9, WorkSeg);
          { 1005:0467 -- the only place DrawSprite changes state, and it
            steps TWICE: MOV AX,Frame / INC AX / DIV 4 / INC AX. }
          L.Frame := ((L.Frame + 1) mod 4) + 1;
        end;
      end
      else
        Blit(@TumbleBk[L.Frame], L.X - 3, L.Y - 10, 10, 10, WorkSeg);
    StWalker:
      { THE BARE-FRAME ARM COMES FIRST, and the order of the two branches is
        what says so rather than the condition. 1005:050e ends the first arm
        and JMPs over the second, and the second -- at 1005:0513 -- is the one
        that does MOV AX,ES:[DI+6] / ADD AX,4 before the IMUL, so `Frame + 4`
        is the ELSE. Written `if Dir < 1 then <+4> else <bare>` the two arms
        come out the other way round; the test is the same either way. }
      if L.Dir >= 1 then
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
      { 1005:05d1 -- frames 1..9 all show the first picture; only from 10
        does it start stepping the bank. }
      if L.Frame < 10 then
        Blit(@Explosion[1], L.X - $1F, L.Y - $30, 63, 55, WorkSeg)
      else
        Blit(@Explosion[L.Frame - 8], L.X - $1F, L.Y - $30,
             63, 55, WorkSeg);
    StDeathA:
      begin
        { 1005:068a -- on the first frame only, a picture at a FIXED place:
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

{ 1005:06c8 -- free every slot. }
procedure InitAll;
var
  N : Integer;
begin
  for N := 1 to MaxLem do
    Lem[N].Active := 0;
end;

{ 1005:07d8 -- free one, and only count it down if it was live. }

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
  { SIX BYTES, AND THE FOUR BELOW THE COUNTER ARE THE `with`'s. 1005:06e7 opens
    ENTER $06 and [BP-$02] is the only slot anything names -- but the four below
    it are not a dead declaration, they are the record address a `with` is
    allocated whether or not it ends up needing them. Here it does not: the
    compiler keeps the address in ES:DI for the whole block, because nothing in
    the block calls anything.

    THE BODY IS WHAT SAYS SO. 1005:070d computes the element's address ONCE --
    IMUL DI,[BP-2],$15 / ADD DI,$2FC / PUSH DS / POP ES -- and then writes all
    thirteen fields through ES:[DI+n]. Naming the element at each field, which
    is what was here, recomputes that address thirteen times over. It is the
    exact opposite reading from part 003's star field, where the original
    recomputes and OUR `with` was the defect: the frame alone cannot tell them
    apart, and the body can. }
  N : Integer;                    { [BP-$02]; the `with` has [BP-$06] }
begin
  if Spawned = SpawnLimit then Exit;             { 1005:06ee }
  for N := 1 to MaxLem do
    if Lem[N].Active = 0 then
    with Lem[N] do                               { 1005:070d }
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

      { THE LOOP IS BROKEN BY ASSIGNING ITS LIMIT, not by Exit, and the ORDER
        is measured too: 1005:07c4 is MOV WORD PTR [BP-2],$19 and only then
        1005:07c9 is INC WORD PTR [$51E]. Falling out of the loop and off the
        end of the routine is the same thing as returning, since nothing
        follows. }
      N := MaxLem;                               { 1005:07c4 }
      Inc(LiveCount);                            { 1005:07c9 }
    end;
end;

{ --------------------------------------------------------------------------
  1005:03b9 -- one blit per state, each from its own bank.

  The sprite is drawn relative to the lemming's feet, which is what all the
  small negative offsets are. States 1 and 2 add FOUR to the frame index when
  facing left, so their banks hold the same animation twice, mirrored.
  -------------------------------------------------------------------------- }
{ IT TAKES THE LEMMING, NOT ITS INDEX, and it has no locals at all. 1005:03b9
  opens PUSH BP / MOV BP,SP with no ENTER, and every field access is
  `LES DI, [BP+$04]` followed by `ES:[DI+n]` -- so the parameter is a four-byte
  reference to the record and the routine reads through it. There is no F
  either: 1005:03C7 is `IMUL DI, ES:[DI+$06], $78`, the frame read straight out
  of the record at the point of use. A local F and an Integer index between them
  accounted for twelve of this part's unaligned spans. }

{ 1005:07d8 -- free one, and only count it down if it was live. }
procedure Remove(N : Integer);
begin
  { A GUARD CLAUSE, NOT A WRAPPING `if`, and the branch pair says which.
    1005:07e4 is JNE over a JMP -- two jumps, four bytes -- where a wrapping
    `if Active <> 0 then begin ... end` emits one short JE, two bytes. The
    conditional-over-unconditional shape is what `if cond then Exit` gives:
    the JNE skips the JMP, and the JMP goes to 1005:07f5, which is the LEAVE.
    `Dec(LiveCount)` is right as it stands -- 1005:07f1 is DEC WORD PTR [$51E],
    the short form, because LiveCount is a plain variable and not an indexed
    field like the Frame and Tick increments in the state routines. }
  if Lem[N].Active = 0 then Exit;                { 1005:07e4 }
  Lem[N].Active := 0;
  Dec(LiveCount);
end;

{ 1005:0b22 -- change state, and restart the animation. }
{ THE LEMMING COMES FIRST. 1005:0b22 reads the state byte from [BP+$04] and the
  index from [BP+$06], and parameters are pushed left to right, so the one
  nearest BP is the LAST declared -- which makes N the first parameter and the
  state the second. Every call site had them the other way round, and that is
  two differing instructions per call across nine routines. }

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
  { SIX BYTES AND ONE OF THEM IS THE ONLY VARIABLE THAT MATTERS. 1005:0853
    opens ENTER $06 and touches [BP-$02], the row, and [BP-$06], which is
    assigned $140 at 1005:0857 and never read again. Nothing reaches [BP-$04].
    There is no pointer local either: 1005:0889 reads the font byte straight
    into DL. }
  Row    : Integer;               { [BP-$02] }
  Unread : Integer;               { [BP-$04], never touched }
  Edge   : Integer;               { [BP-$06], assigned and never read }
begin
  Edge := ScrollEdge;                            { 1005:0857 }
  for Row := 0 to ScrollRows - 1 do
    { AND THE DESTINATION CARRIES NO Ofs(). 1005:088E does LES DI / MOV AX,ES
      and uses only the SEGMENT of ScrollBuf; the offset is the arithmetic
      below and nothing else. }
    Mem[Seg(ScrollBuf^) : Row * ScrollPitch + ScrollEdge] :=
      Font^[Ch, Col, Row + 1];
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
  { ONE BYTE, AND IT DOES BOTH JOBS. 1005:08ad opens ENTER $02 and the only slot
    it touches is [BP-$01]: 1005:0950 stores the palette entry it is about to
    overwrite, and 1005:0974 sets the same byte to zero and 1005:097A increments
    it -- the `for` counter. There is no Pass either, because the rotation is
    written out TWICE rather than looped; a Pass counter and a separate index
    put the frame at $06. }
  Last : Byte;                    { [BP-$01], then the colour index }
begin
  Inc(ScrollCol, 2);                             { 1005:08b1 }
  if ScrollCol > GlyphCols then
  begin
    ScrollCol := 1;
    Inc(ScrollIdx);
  end;

  { THE SPACE ARM COMES FIRST. 1005:08CC is CMP/JBE, which jumps to the message
    arm and falls through to the space, so the test is `ScrollIdx > TextLen - 1`
    with the space as the THEN. }
  if ScrollIdx > TextLen then                   { 1005:08C7 -- CMP AL,$EC }
    ScrollChar(Ord(' '), ScrollCol)
  else
    ScrollChar(Ord(Message[ScrollIdx]), ScrollCol);

  ScrollRender;                                  { 1005:08f4 }

  { 1005:08f7 -- the two side animations, three frames each shown four ticks
    apart, one counting up and the other down so they mirror. }
  SideTick := (SideTick mod 11) + 1;
  Blit(@SideAnim[4 - ((SideTick shr 2) + 1)], $116, $1B, 14, 10, WorkSeg);
  Blit(@SideAnim[(SideTick shr 2) + 4],       $1E,  $1B, 14, 10, WorkSeg);

  { 1005:093f -- rotate the eight-entry cycle and show it. The original does
    the whole thing TWICE per frame, so the colours run at double speed. }
  Last := ScrollPal[24];                       { 1005:094D }
  Move(ScrollPal[1], ScrollPal[4], 21);    { 1005:0953 }
  FillChar(ScrollPal[1], 3, Last);            { 1005:0964 }
  for Last := 0 to 7 do                          { 1005:0974 -- the same byte }
    SetRGB($80 + Last, ScrollPal[Last * 3 + 1],
           ScrollPal[Last * 3 + 1 + 1], ScrollPal[Last * 3 + 1 + 1 + 1]);

  { and again, written out rather than looped }
  Last := ScrollPal[24];
  Move(ScrollPal[1], ScrollPal[4], 21);
  FillChar(ScrollPal[1], 3, Last);
  for Last := 0 to 7 do
    SetRGB($80 + Last, ScrollPal[Last * 3 + 1],
           ScrollPal[Last * 3 + 1 + 1], ScrollPal[Last * 3 + 1 + 1 + 1]);
end;

{ ==========================================================================
  The lemmings
  ========================================================================== }

{ 1005:06c8 -- free every slot. }

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
{ --------------------------------------------------------------------------
  1005:0a86 -- blank the DAC, put the hillside up, fade it in, then run a
  seven-frame animation BACKWARDS at (5, 50) and start the music.
  -------------------------------------------------------------------------- }
procedure Intro;
var
  { I IS DECLARED FIRST, and the difference is a byte of displacement on every
    one of its nine references. 1005:0a8a passes LEA DI,[BP-$302] to
    GetPalette768 and 0a97 writes the counter at [BP-$02]; first declared is
    nearest BP, so the counter comes first and the 768-byte buffer sits below
    it. Ours had them the other way round, which put the counter at [BP-$302]
    -- a 16-bit displacement where the original has an 8-bit one, two bytes
    longer at every reference and everything after them out of step. }
  I   : Integer;                  { [BP-$02] }
  Pal : TPal768;                  { [BP-$302] }
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

{ THE LEMMING COMES FIRST. 1005:0b22 reads the state byte from [BP+$04] and the
  index from [BP+$06], and parameters are pushed left to right, so the one
  nearest BP is the LAST declared -- which makes N the first parameter and the
  state the second. Every call site had them the other way round, and that is
  two differing instructions per call across nine routines. }
procedure SetState(N : Integer; S : Byte);
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
  { AN OUTER LOOP THAT RUNS EXACTLY ONCE -- `for DY_ := 1 to 1`. Its variable is
    the Y offset, and it is a VARIABLE rather than the literal 1 this routine
    once passed: 1005:0B97 reads [BP-$02] and adds it to Lem[N].Y.

    THE BOUND IS THE CONSTANT 1, and the tell is at the bottom. 1005:0CA1 is
    `CMP [BP-$02],1 / JE / JMP 0B73` -- which is `JNE @inc` written the long way
    because @inc is 818 bytes back, out of a short branch's reach. That is a for
    loop's bound test, not an `if DY_ = 1`, so the code at 1005:0CAA is AFTER
    the loop rather than inside it. Written as a repeat with the increment at
    the bottom, the increment lands in the wrong place: the original's is at
    1005:0B73, above the body, which is where a `for` puts it. }
  DY_ : Integer;                  { [BP-$02] }
  DX_ : Integer;                  { [BP-$04] }
  Pix : Byte;                     { [BP-$05] }
begin
  for DY_ := 1 to 1 do
  begin
    for DX_ := -3 to 3 do
    begin
      Pix := GetPixel(Lem[N].X + DX_, Lem[N].Y + DY_, VirtScrSeg);
      if Pix in Ground then
      begin
        { THE HARD-LANDING ARM COMES FIRST. 1005:0BDC is CMP/JBE, which jumps
          to the survivable branch, so the test is `FallDist > 10` with the
          bounce as the THEN and not `< 11` with it as the ELSE. }
        if Lem[N].FallDist > 10 then
        begin
          Inc(Lem[N].Bounces);                   { 1005:0BE2 }
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
            1005:0bd5 adds it. }
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

  { 1005:0CAA -- and this is AFTER the loop, reached when nothing was found. }
  if Lem[N].FallDist < 2 then Inc(Lem[N].X, Lem[N].Dir);
  Inc(Lem[N].Y);
  Inc(Lem[N].FallDist);
  Lem[N].Frame := (Lem[N].Frame mod 4) + 1;
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
      { LONGHAND: the original loads, INCs the register and stores back, and
        recomputes the subscript's IMUL for each -- 1005:1884 in DeathA is the
        pattern. `Inc` on an indexed field increments in place and needs a slot
        for the address, which is what gave these routines a frame the original
        has none of. NOT every Inc in this unit is wrong: Bounces at 1005:0BE2
        really is the short form. }
  Lem[N].Tick := Lem[N].Tick + 1;
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
    SetState(N, StWalker);
    Lem[N].Timer := $14;
  end;
end;

{ 1005:17ff -- state 8. On the fourth frame it stamps the last splat picture
  PERMANENTLY into the hillside and removes itself, so the mark stays. }

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
  { FOUR DECLARED LOCALS AND ONE COMPILER TEMPORARY, in eight bytes. Digger's
    range contains the WALL set as CS data at 1005:1146, which desynchronises a
    linear disassembly -- an earlier reading of this frame counted 23 references
    to [BP-$02] that are in fact Tunneller's, because the walk ran straight
    through the data and past the next routine's ENTER. Digger itself never
    touches [BP-$02] at all.

    So: an Integer at [BP-$02] that is never read, the column at [BP-$04], the
    flag and the pixel as bytes at [BP-$05] and [BP-$06], and [BP-$08] is the
    upper bound of the `for` -- evaluated once into a temporary, which is why
    there is no ColTo. }
  Unread : Integer;               { [BP-$02], never read }
  Col    : Integer;               { [BP-$04] }
  Hit    : Boolean;               { [BP-$05] }
  Pix    : Byte;                  { [BP-$06] }
begin
  Hit := False;
  { THE RIGHTWARD BRANCH COMES FIRST. 1005:0E01 is CMP/JG, which jumps INTO
    this branch and falls through to the other -- so the source tests
    `Dir >= 1`, not `Dir < 1`. }
  if Lem[N].Dir >= 1 then
  begin
    for Col := Lem[N].X - 3 to Lem[N].X + 3 + 1 do   { 1005:0E0B }
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
          0, VirtScrSeg);                            { 1005:0E6D }
    VLine(Lem[N].X + 3 + 1 + 1, Lem[N].Y - 9 - 0,     Lem[N].Y - 0,
          0, VirtScrSeg);                            { 1005:0E98 }
    VLine(Lem[N].X + 3 + 3,     Lem[N].Y - 9 + 1,     Lem[N].Y - 1,
          0, VirtScrSeg);                            { 1005:0ECA }
    VLine(Lem[N].X + 3 + 4,     Lem[N].Y - 9 + 1 + 1, Lem[N].Y - 1 - 1,
          0, VirtScrSeg);                            { 1005:0EF9 }
    VLine(Lem[N].X + 3 + 5,     Lem[N].Y - 9 + 3,     Lem[N].Y - 3,
          0, VirtScrSeg);                            { 1005:0F2A }
    HLine(Lem[N].X - 3, Lem[N].X + 3 + 1 + 1, Lem[N].Y,
          0, VirtScrSeg);                            { 1005:0F5D }
  end
  else
  begin
    for Col := Lem[N].X - 3 to Lem[N].X + 3 do       { 1005:0F8B }
    begin
      Pix := GetPixel(Col, Lem[N].Y + 1, VirtScrSeg);
      if Pix in Wall then Hit := True;
    end;

    DrawLine(Lem[N].X - 3 + 1,     Lem[N].Y - 9 - 1 - 1,
             Lem[N].X - 3 + 1,     Lem[N].Y + 1,
             0, VirtScrSeg);                         { 1005:0FEC }
    DrawLine(Lem[N].X - 3 + 1 + 1, Lem[N].Y - 9 - 1 - 1,
             Lem[N].X - 3 + 1 + 1, Lem[N].Y + 1,
             0, VirtScrSeg);                         { 1005:1029 }
    DrawLine(Lem[N].X - 3 - 1 - 1, Lem[N].Y + 1,
             Lem[N].X + 3 + 1 + 1, Lem[N].Y + 1,
             0, VirtScrSeg);                         { 1005:1068 }
  end;

  Lem[N].Tick := (Lem[N].Tick mod 3) + 1;            { 1005:10A3 }
  if Lem[N].Tick mod 3 = 0 then
  begin
    Lem[N].Frame := (Lem[N].Frame mod 6) + 1;
    if Lem[N].Frame mod 6 = 0 then
    begin
      Inc(Lem[N].X, Lem[N].Dir * 2);
      Inc(Lem[N].Y);
    end;
  end;

  if not Hit then SetState(N, StWalker);
end;


procedure Tunneller(N : Integer);
var
  { FOUR DECLARATIONS AND TWO TEMPORARIES, in ten bytes. 1005:1166 opens
    ENTER $A and touches [BP-$02], [BP-$04], [BP-$05], [BP-$06], [BP-$08] and
    [BP-$0A]. The last two are the compiler's: 1005:1189 stores the outer
    loop's limit into [BP-$08] and 1005:11AD stores the inner loop's into
    [BP-$0A], recomputed on every outer pass -- so neither ColTo nor RowTo is a
    variable, and declaring them produced them twice over. }
  Row  : Integer;                 { [BP-$02] }
  Col  : Integer;                 { [BP-$04] }
  Hit  : Boolean;                 { [BP-$05] }
  Pix  : Byte;                    { [BP-$06] -- the pixel is READ INTO A BYTE
                                    before it is tested; inside the `in` test
                                    it stays in a register and loses the slot }
begin
  Hit := False;
  { THE RIGHTWARD BRANCH COMES FIRST: 1005:1172 is CMP/JG, which jumps into it
    and falls through to the other, so the test is `Dir >= 1`. }
  if Lem[N].Dir >= 1 then
  begin
    for Col := Lem[N].X + 3 + 1 to Lem[N].X + 3 + 1 + 1 do   { 1005:117C }
      for Row := Lem[N].Y - 9 to Lem[N].Y do                 { 1005:11A5 }
      begin
        Pix := GetPixel(Col, Row, VirtScrSeg);
        if Pix in Wall then Hit := True;
      end;

    { Every constant is written as the original computes it -- one operation
      per operator, so `+ 3 + 1 + 1` is ADD AX,3 / INC AX / INC AX and `+ 3 + 0`
      really does emit ADD AX,0. See the wiki's one-operation-per-operator. }
    VLine(Lem[N].X + 3 - 1 - 1, Lem[N].Y - 9 - 1,     Lem[N].Y,
          0, VirtScrSeg);                                    { 1005:1204 }
    VLine(Lem[N].X + 3 - 1,     Lem[N].Y - 9,         Lem[N].Y - 1,
          0, VirtScrSeg);                                    { 1005:1230 }
    VLine(Lem[N].X + 3 + 0,     Lem[N].Y - 9 + 1,     Lem[N].Y - 1 - 1,
          0, VirtScrSeg);                                    { 1005:125C }
    VLine(Lem[N].X + 3 + 1,     Lem[N].Y - 9 + 1 + 1, Lem[N].Y - 3,
          0, VirtScrSeg);                                    { 1005:128C }
    VLine(Lem[N].X + 3 + 1 + 1, Lem[N].Y - 9 + 3,     Lem[N].Y - 4,
          0, VirtScrSeg);                                    { 1005:12BC }
    VLine(Lem[N].X + 3 + 3,     Lem[N].Y - 9 + 4,     Lem[N].Y - 5,
          0, VirtScrSeg);                                    { 1005:12EE }
  end
  else
  begin
    for Col := Lem[N].X - 3 - 1 - 1 to Lem[N].X - 3 - 1 do   { 1005:1324 }
      for Row := Lem[N].Y - 9 to Lem[N].Y do
      begin
        Pix := GetPixel(Col, Row, VirtScrSeg);
        if Pix in Wall then Hit := True;
      end;

    VLine(Lem[N].X - 3 - 1,     Lem[N].Y - 9,         Lem[N].Y,
          0, VirtScrSeg);                                    { 1005:13A6 }
    VLine(Lem[N].X - 3 - 1 - 1, Lem[N].Y - 9 + 1 + 1, Lem[N].Y - 1 - 1,
          0, VirtScrSeg);                                    { 1005:13D0 }
    VLine(Lem[N].X - 3 - 3,     Lem[N].Y - 9 + 3,     Lem[N].Y - 3,
          0, VirtScrSeg);                                    { 1005:1400 }
  end;

  Lem[N].Frame := (Lem[N].Frame mod 3) + 1;
  if Lem[N].Frame mod 3 = 0 then
    Inc(Lem[N].X, Lem[N].Dir);

  if not Hit then SetState(N, StWalker);
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
label
  Stand, Move;
var
  { TEN BYTES, AND ONLY SIX OF THEM ARE DECLARED. 1005:14d6 opens ENTER $A with
    slots at [BP-$02] x16, [BP-$04] x16, [BP-$06] x6, [BP-$08] x6 and
    [BP-$0A] x12, and the last two are not variables at all. A `for` whose
    upper bound is an expression evaluates it ONCE into a compiler temporary,
    and the loops here nest one deep, so two temporaries are live: [BP-$08]
    holds the row bound and [BP-$0A] the column bound, in all three loops.

    THAT IS ALSO WHY THERE IS NO Standing AND NO Climbed. The original leaves a
    loop with a GOTO straight to the code that follows it -- 1005:156E jumps to
    the wall check and 1005:171B jumps to the move. A Boolean flag set inside
    the loop and tested after it is the re-expression, and it costs the flag,
    the test and the branch around it. }
  DX_   : Integer;                { [BP-$02] -- the ground offset first, then
                                    the ROW of both later loops: one variable
                                    doing three jobs }
  Col   : Integer;                { [BP-$04] }
  Spare : Byte;                   { [BP-$05], never read -- a byte declared
                                    after a word lands here, and Pix is at
                                    $06, so something occupies $05 }
  Pix   : Byte;                   { [BP-$06] }
begin
  for DX_ := -3 to 3 do
  begin
    Pix := GetPixel(Lem[N].X + DX_, Lem[N].Y + 1, VirtScrSeg);
    { A CASE, NOT AN `or` CHAIN. 1005:1511 loads the pixel into AL ONCE and then
      runs CMP AL,3 / JE / CMP AL,$12 / JE / CMP AL,$20 / JB / CMP AL,$29 / JA
      -- one selector and three label groups, which is a case statement's
      dispatch. An `or` of three comparisons reloads the byte for each and
      compares memory against an immediate instead. The body then re-reads the
      pixel to decide which state, and that part was already right. }
    case Pix of
      DeathAColour, StuckColour, $20..$29 :
        begin
          { THREE MORE CASES, not three ifs. 1005:1524, 1537 and 1546 each
            reload the pixel into AL and then compare -- `MOV AL,[BP-$06]` then
            `CMP AL,imm` -- which is a case statement's selector load. An `if`
            on a byte variable compares memory against the immediate directly
            and never touches AL. }
          case Pix of $20..$29     : SetState(N, StDeathB) end;
          case Pix of DeathAColour : SetState(N, StDeathA) end;
          case Pix of StuckColour  : SetState(N, StStuck)  end;
          Exit;
        end;
    end;
    if Pix in Ground then goto Stand;            { 1005:156E }
  end;

  { 1005:1579 -- the loop ran out, so there is nothing under it anywhere. This
    is the code AFTER the for loop, which is why the loop's own bottom test at
    1005:1570 branches straight into it. }
  SetState(N, StFaller);
  Exit;

Stand:
  { 1005:1584 -- the wall ahead, head height. The bound is written as two
    additions because that is what the original computes: ADD AX,3 then INC AX
    twice, which is `+ 3 + 2` and not `+ 5` -- Turbo Pascal emits one operation
    per operator rather than folding the constants first. }
  for DX_ := Lem[N].Y - 9 to Lem[N].Y - 4 do
    if Lem[N].Dir >= 1 then
    begin
      for Col := Lem[N].X + 3 to Lem[N].X + 3 + 2 do   { 1005:15B8 }
        if GetPixel(Col, DX_, VirtScrSeg) in Wall then
        begin
          Lem[N].Dir := -Lem[N].Dir;
          Exit;
        end;
    end
    else
      for Col := Lem[N].X - 3 - 2 to Lem[N].X - 3 do   { 1005:1622 }
        if GetPixel(Col, DX_, VirtScrSeg) in Wall then
        begin
          Lem[N].Dir := -Lem[N].Dir;
          Exit;
        end;

  { 1005:1695 -- a step it can climb rather than a wall.

    The moment this finds one it writes the new Y and jumps OUT of both loops
    to the move -- the JMP at 1005:171B. Writing the new Y and letting the row
    loop carry on is not the same thing: the new Y is one LESS than the current
    row, so a row loop that kept going would step back onto the row it just
    left and stay there. }
  for DX_ := Lem[N].Y - 4 to Lem[N].Y do
    if Lem[N].Dir >= 1 then
    begin
      for Col := Lem[N].X + 3 to Lem[N].X + 3 + 1 do   { 1005:16C6 }
        if GetPixel(Col, DX_, VirtScrSeg) in Wall then
        begin
          Lem[N].Y := DX_ - 1;                         { 1005:170F }
          goto Move;                                   { 1005:171B }
        end;
    end
    else
      for Col := Lem[N].X - 3 - 1 to Lem[N].X - 3 do   { 1005:1727 }
        if GetPixel(Col, DX_, VirtScrSeg) in Wall then
        begin
          Lem[N].Y := DX_ - 1;
          goto Move;
        end;

Move:
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

{ 1005:17ff -- state 8. On the fourth frame it stamps the last splat picture
  PERMANENTLY into the hillside and removes itself, so the mark stays. }
procedure Splat(N : Integer);
begin
  { LONGHAND, NOT `Inc`, and the original's prologue is how the difference was
    found rather than the statement. 1005:17ff is PUSH BP / MOV BP,SP with NO
    ENTER -- no frame at all -- where ours opened ENTER $08, and a routine with
    no declared locals that still wants eight bytes is holding temporaries.

    1005:1802 is IMUL DI,[BP+4],$15 / MOV AX,[DI+$302] / INC AX / IMUL again /
    MOV [DI+$302],AX -- the value loaded into a register, incremented there and
    stored back, with the subscript's multiply done TWICE. `Inc` on an indexed
    field emits an increment in place and needs somewhere to keep the address.
    The original recomputes IMUL DI,[BP+4],$15 five times in this routine and
    keeps nothing, which is what leaves it with no frame. }
  Lem[N].Frame := Lem[N].Frame + 1;                { 1005:1802 }
  if Lem[N].Frame = 4 then
  begin
    Blit(@SplatBank[4], Lem[N].X - 4, Lem[N].Y - 9, 12, 10, VirtScrSeg);
    Remove(N);
  end;
end;

{ 1005:1850 -- state 6. Six frames, one every fifth tick, then gone. }

{ 1005:1850 -- state 6. Six frames, one every fifth tick, then gone. }
procedure DeathA(N : Integer);
begin
  Lem[N].Tick := (Lem[N].Tick mod 5) + 1;
  if Lem[N].Tick mod 5 = 0 then
  begin
    Lem[N].Frame := Lem[N].Frame + 1;
    if Lem[N].Frame > 6 then Remove(N);
  end;
end;

{ 1005:18a6 -- state 7. Five frames, one every third tick, then gone. }

{ 1005:18a6 -- state 7. Five frames, one every third tick, then gone. }
procedure DeathB(N : Integer);
begin
  Lem[N].Tick := (Lem[N].Tick mod 3) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    Lem[N].Frame := Lem[N].Frame + 1;
    if Lem[N].Frame > 5 then Remove(N);
  end;
end;

{ 1005:18fc -- state 3, the lit fuse. Five frames, then it explodes. }

{ 1005:18fc -- state 3, the lit fuse. Five frames, then it explodes. }
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
  1005:1954 -- state 11, the explosion.

  While the fireball is in its first nine frames it runs five passes bumping
  DAC entries $E0..$E9 one step up toward the scene palette. LoadAssets
  deliberately BLACKED those ten entries after loading, so this is what
  lights the explosion: the picture is already on screen in colours nobody
  can see until the flash brings them up.

  Past frame 15 it sets the timer to -60 and holds the frame, and UpdateAll
  counts that back up to -1 and removes the lemming.
  -------------------------------------------------------------------------- }

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
  { C IS DECLARED FIRST. 1005:19a4 puts Pass at [BP-$04] and 19ae puts C at
    [BP-$02], and first declared is nearest BP -- ours had them the other way
    round, which put a two-byte displacement difference on every one of the
    fourteen references in the loop. }
  C, Pass : Integer;              { [BP-$02], [BP-$04] }
  RGB     : array[0..2] of Byte;  { [BP-$07]..[BP-$05] }
begin
  Lem[N].Tick := (Lem[N].Tick mod 5) + 1;
  if Lem[N].Tick mod 3 = 0 then
  begin
    { WRITTEN OUT, NOT Inc(). 1005:1988 computes the address, LOADS the frame,
      INCs the register and computes the address a second time to store it --
      five instructions where `Inc` gives one `INC WORD PTR [DI+n]`. Faller's
      Inc(Lem[N].Bounces) really is the short form at 1005:0BE2, so the two
      spellings are both in the original and this is the long one. }
    Lem[N].Frame := Lem[N].Frame + 1;            { 1005:1988 }
    if Lem[N].Frame < 10 then
      for Pass := 1 to 5 do
        for C := $E0 to $E9 do
        begin
          { ALL THREE TESTS READ RGB[0], AND THAT IS A BUG IN THE ORIGINAL.
            1005:19c6, 19db and 19f0 are three identical MOV AL,[BP-7] loads,
            and [BP-7] is where GetRGBTo's buffer starts -- so it is RGB[0]
            every time -- while the increments at 19d8, 19ed and 1a02 go to
            [BP-7], [BP-6] and [BP-5] in turn. The RED channel is compared
            against the green and blue targets.

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
            channel into the displacement. The original computes C*3 in DI --
            MOV DI,[BP-2] / MOV SI,DI / SHL DI,1 / ADD DI,SI -- and then
            addresses the three channels as [DI-$33F9], [DI-$33F8] and
            [DI-$33F7], three consecutive displacements off one index. A flat
            `ScenePal[C * 3 + 1]` adds the 1 at RUN TIME instead: ours emitted
            INC AX after the multiply, once for green and twice for blue.
            Declaring the array as [0..255, 0..2] puts the channel in the
            SECOND subscript, where it is a constant the compiler folds.

            (An earlier version of this note claimed the comparison had to be
            written `ScenePal[..] > RGB[0]` to make Turbo Pascal load RGB[0]
            first. It does not: both spellings emit the same code, and the
            81-byte span shrank because of the C/Pass declaration order in the
            var block above, not because of the operator. Kept because the
            wrong reason survived a measurement that appeared to confirm it --
            two changes went in together and only one of them did anything.) }
          GetRGBTo(C, @RGB);
          if RGB[0] < ScenePal[C, 0] then Inc(RGB[0]);        { 1005:19c6 }
          if RGB[0] < ScenePal[C, 1] then Inc(RGB[1]);        { 1005:19db }
          if RGB[0] < ScenePal[C, 2] then Inc(RGB[2]);        { 1005:19f0 }
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
      { 1005:1a7a -- the scripted trigger, and it is TWO comparisons, not four.
        There is no test against zero anywhere in the original; the `>= 0`
        guards this used to carry were four comparisons it does not make.

        THE TRIG FIELD IS ON THE LEFT even though the binary reads Lem[N].X
        first. For a comparison widened to LongInt Turbo Pascal evaluates the
        RIGHT operand first: written the other way round our build emitted
        TrigX at 1005:1A7E and X at 1005:1A8C, the reverse of the original.
        Each side is widened because X and Y are Words and the Trig fields
        Integers. }
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

      DrawSprite(Lem[N]);                        { 1005:1ae3 }

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
  { THE ORDER IS Frame, V, Done, I, and the byte offsets say so: 1005:1bbb's
    frame is $06 and its slots are [BP-$02] a word, [BP-$03] a byte with six
    references, [BP-$04] a byte with four, and [BP-$06] a word with five.
    1005:1BCB stores Frame and 1005:1BD9 stores Done, in that order, so the
    volume byte is declared BETWEEN them and the loop counter last. }
  Frame : Integer;                { [BP-$02] }
  V     : Byte;                   { [BP-$03] }
  Done  : Boolean;                { [BP-$04] }
  I     : Integer;                { [BP-$06] }
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
      { 1005:1C2E -- fade the scroller's colour cycle out with it, and it is
        ONE loop over all twenty-four bytes rather than eight passes of three:
        1005:1C38 indexes [DI+$F4] with DI the counter itself, no multiply, and
        1005:1C49 compares it against $18. }
      for I := 1 to 24 do
        { `> 0`, not `<> 0`: 1005:1C40 is JBE, which is what an unsigned
          greater-than gives; a not-equal gives JE. }
        if ScrollPal[I] > 0 then Dec(ScrollPal[I]);

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
  { A LEFTOVER DEBUG PRINT, and it is the last thing the part does. 1005:1d20
    pushes DS:$D232 -- the System unit's `Output` text record -- then Spawned
    widened with XOR DX,DX and a field width of 0, calls the runtime's
    write-a-LongInt routine and then its WriteLn. That is Borland's chaining
    convention: the write routine leaves the file pointer on the stack for the
    WriteLn to pop, which is why the second call pushes nothing.

    XOR DX,DX AND NOT CWD, so Spawned is a Word rather than an Integer -- an
    Integer widens signed. Kept as it is: the number lands on the console
    behind the demo's own screen and nobody sees it, but it is what ships. }
  WriteLn(Spawned);                              { 1005:1d20 }
end;

{ 1005:1d3a -- the unit's initialisation body is empty. }

begin
end.
