{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.004, the Lemmings game
  Reconstructed from NEUROSIS_004.exe.

  A WORKING LEMMINGS ENGINE -- pixel-accurate terrain collision, destructible
  terrain and a ten-state skill machine -- playing a scripted level that
  solves itself, with the scroll text running alongside. That is the "new
  twist" the text promises.

  No floating point at all; the only effect part that never touches the x87
  emulator.

  ADDRESS MAP
    Demo_Main            1005:1cd6   Lemmings_LoadAssets  1005:00a6
    Lemmings_Intro       1005:0a86   Lemmings_MainLoop    1005:1bbb
    Lem_UpdateAll        1005:1a4c   Lem_Spawn            1005:06e7
    Lem_SetState         1005:0b22   Lem_Remove           1005:07d8
    LemState1_Walker     1005:14d6   LemState2_Faller     1005:0b68
    LemState4_Basher     1005:0df5   LemState10_Miner     1005:1166
    LemState8_Splat      1005:17ff   LemState11_Countdown 1005:1954
    VGA_GetPixel         11e3:0048   Scroller_Step        1005:08ad
    Effect_ColumnSlideIn 1005:0000
  =========================================================================== }

unit Part4Lemmings;

interface

procedure RunPart4;

implementation

uses VGA, Crt, DemoVT;

const
  { The scroll text is 237 characters, and the code bounds-checks against
    $ED = 237 exactly. }
  ScrollLen   = 237;

  CharStep    = 2;        { columns advanced per frame }
  CharWrap    = 21;       { $15 -- about 11 characters visible at a time }
  WalkStates  = 11;       { the walk counter cycles 1..11 }
  BigSprite   = 1032;     { $408 bytes per walk frame }
  SmallSprite = 140;      { $8C  bytes per walk frame }
  IntroSprite = 1560;     { $618 bytes per intro frame }
  CycleFirst  = $80;      { palette entries $80..$87 colour-cycle }
  CycleCount  = 8;


const
  MaxLems   = 25;         { $19 concurrent slots }
  TotalLems = 80;         { $50 released in all }
  LemRec    = 21;         { $15 bytes per lemming, based at DS:$02FC }
  HatchX    = 35;         { $23 }
  HatchY    = 60;         { $3C }
  SplatDrop = 11;         { fall further than this and the lemming splats }

type
  { Terrain solidity is a SET of colours tested against the pixel read back
    from the virtual screen -- the level artwork IS the collision data, and
    digging just draws colour 0 over it.

    Both sets are 32-byte constants in the CODE segment (CS:$1496 and
    CS:$14B6 in segment 1005), reached through a CS: override -- Borland puts
    constant sets next to the code that tests them, not in DGROUP. }
  TColourSet = set of Byte;

const
  { Can a lemming stand on it? }
  Ground : TColourSet =
    [$04..$05, $0F, $15..$18, $1D, $1F, $33, $36,
     $3E..$40, $42..$47, $4D..$52];

  { Does it block a lemming? Ground plus the hazard stripe. You cannot stand
    on $20..$29 and touching it kills you, but it still stops you walking. }
  Wall : TColourSet =
    [$04..$05, $0F, $15..$18, $1D, $1F..$29, $33, $36,
     $3E..$40, $42..$47, $4D..$52];

  BrickColour = $4D;      { the builder's bricks -- note $4D is IN Ground,
                            so a laid brick is walkable the moment it exists }

type
  { Offsets are what Lem_Spawn and Lem_SetState actually write. }
  TLemming = record
    X, Y      : Integer;    { +0  +2  }
    { +4 is NOT unused: LemState2_Faller counts hard landings in it, and
      splats on the second. }
    HardLandings : Integer; { +4 }
    Frame     : Integer;    { +6   reset to 1 by Lem_SetState }
    Tick      : Integer;    { +8   reset to 0 by Lem_SetState }
    Countdown : Integer;    { +10  ticks DOWN to 1 -> state 3
                                   ticks UP to -1 -> removed }
    Alive     : Byte;       { +12  the free-slot test }
    State     : Byte;       { +13  written by Lem_SetState }
    Dir       : ShortInt;   { +14  +1 or -1 }
    FallDist  : Byte;       { +15 }
    TargetX   : Integer;    { +16 }
    TargetY   : Integer;    { +18 }
    TargetSt  : Byte;       { +20 }
  end;

var
  Lem      : array[1..MaxLems] of TLemming;
  Released : Integer;

{ ===========================================================================
  RECONSTRUCTION SCAFFOLDING -- see the note in PART1_INTRO.PAS.
    [transcribed] read out of the binary   [inferred] implied by call sites
    [stub] signature only
  =========================================================================== }

const
  BigBank    = 0;            { offset of the 1032-byte walk frames }
  SmallBank  = 0;            { offset of the 140-byte carrier frames }
  LastColour = 0;

  { Sprite bank offsets within the asset block, from Lem_DrawSprite. }
  WalkBank   = $04EC;        { walker and faller share it, 8 frames }
  FallBank   = $066E;
  MinerBank  = $13BB;
  SplatBank  = $1240;
  BashBank   = $193A;
  DeathBBank = $1ACA;
  DeathABank = $1E1E;
  BuildBank  = $209A;
  TimerBank  = $234C;

var
  BackdropSeg : Word;
  FrameCounter: LongInt;
  { the PART-level countdown that ends the scene, not a lemming field }
  Countdown   : Integer;
  Virt, Aux   : Pointer;
  BackSeg     : Word;        { DS:$030D -- the draw target }
  LiveCount   : Integer;     { DS:$051E }
  { DS:$CC07 -- the target palette the explosion flash walks toward }
  FlashTarget : array[0..255, 0..2] of Byte;
  Cycle       : array[0..23] of Byte;    { the 8-entry colour band, RGB }
  ScrollText  : String;
  SignOff     : String;

{ [transcribed] VGA_GetPixel 11e3:0048 -- reads the VIRTUAL screen. This is
  the whole collision system: the level artwork is the collision data. }
function GetPixel(X, Y : Integer; Segment : Word) : Byte;
begin
  if (X < 0) or (X > 319) or (Y < 0) or (Y > 199) then
    GetPixel := 0
  else
    GetPixel := Mem[Segment : Y * 320 + X];
end;

{ [transcribed] VGA_FillRect 1005:0328 and VGA_FillTri 1005:0354.

  Both names are misnomers -- they are SPAN fills, one pixel thick:

    FillRect  vertical   column X, rows YTop..YBottom   (STOSB, DI += 319)
    FillTri   horizontal row Y,    columns X1..X2       (REP STOSB)

  Both index the same row table the sprite blitter uses, at DS:$CF8E. The
  original pushes its arguments in the opposite order to this declaration
  (X innermost, Segment last); the behaviour is identical. }
procedure FillRect(X, YTop, YBottom : Integer; Colour : Byte; Segment : Word);
var
  Y : Integer;
begin
  for Y := YTop to YBottom do
    if (Y >= 0) and (Y < 200) and (X >= 0) and (X < 320) then
      Mem[Segment : Y * 320 + X] := Colour;
end;

procedure FillTri(X1, X2, Y : Integer; Colour : Byte; Segment : Word);
var
  X : Integer;
begin
  if (Y < 0) or (Y > 199) then Exit;
  for X := X1 to X2 do
    if (X >= 0) and (X < 320) then
      Mem[Segment : Y * 320 + X] := Colour;
end;

{ Forward declarations -- Lem_UpdateAll dispatches to all of these before any
  of them is defined. }
procedure Remove(N : Integer); forward;
procedure SetState(S : Byte; N : Integer); forward;
procedure Faller(N : Integer); forward;
procedure Miner(N : Integer); forward;      { state 4  -- diagonal }
procedure Basher(N : Integer); forward;     { state 10 -- horizontal }
procedure DeathA(N : Integer); forward;
procedure DeathB(N : Integer); forward;
procedure Splat(N : Integer); forward;
procedure Countdown11(N : Integer); forward;
procedure Walker(N : Integer); forward;
procedure ColumnSlideIn; forward;      { 1005:0000 }
procedure FadeStep; forward;
procedure TimerState(N : Integer); forward;
procedure Builder(N : Integer); forward;

{ --------------------------------------------------------------------------
  The sprite banks live at FIXED DGROUP ADDRESSES, not in one heap block.
  Lemmings_LoadAssets reads each one straight to its own DS offset -- $0522,
  $06D2, $12B8, $1498, $19C6, $1B6A, $1E8A, $2112, $23E2, $26D0, $858F,
  $91A7, $BC4F, $BF97 -- so DrawSprite's constants are data-segment addresses.

  That also disposes of an earlier worry about the 202,007-byte total not
  fitting a single GetMem: it never was one allocation. The total is one
  23,436-byte heap block, two 64,000-byte screen loads, three 768-byte
  palettes and these fourteen DGROUP arrays.

  Modelled as one array indexed by the original DS offset, so the bank
  constants below read exactly as they do in the binary.
  -------------------------------------------------------------------------- }
var
  SpriteMem : array[$0400..$CBFF] of Byte;

function Bank(At : LongInt) : Pointer;
begin
  Bank := @SpriteMem[At];
end;

{ [transcribed] Sprite_Blit 1005:037a -- transparent blit, zero bytes skipped.
  H rows of W columns, stepping DI by 320 - W between rows. }
procedure Blit(Src : Pointer; X, Y, W, H : Integer; Segment : Word);
var
  Row, Col : Integer;
  P        : ^Byte;
  V        : Byte;
begin
  P := Src;
  for Row := 0 to H - 1 do
    for Col := 0 to W - 1 do
    begin
      V := P^;
      Inc(LongInt(P));
      if (V <> 0) and (Y + Row >= 0) and (Y + Row < 200)
         and (X + Col >= 0) and (X + Col < 320) then
        Mem[Segment : (Y + Row) * 320 + X + Col] := V;
    end;
end;

{ --------------------------------------------------------------------------
  Lem_DrawSprite (1005:03b9) -- one blit per state, from a different bank.

  Offsets are into the asset block loaded by LoadAssets; the frame stride is
  always H * W, which is what fixes each sprite's dimensions:

      walker/faller   9 x 6   stride $36   bank $04EC
      splat          10 x 12  stride $78   bank $1240
      builder        10 x 12  stride $78   bank $209A
      long fall      10 x 10  stride 100   bank $066E
      basher         10 x 14  stride $8C   bank $193A
      death B        10 x 16  stride $A0   bank $1ACA
      miner          13 x 17  stride $DD   bank $13BB
      timer          10 x 15  stride $96   bank $234C
      death A        12 x  9  stride $6C   bank $1E1E
      explosion      55 x 63  stride $D89  bank $1947 / $26D0

  The walker and faller share a bank: frames 1..4 face one way and frames
  5..8 the other, which is why a leftward lemming indexes (Frame + 4).
  -------------------------------------------------------------------------- }
procedure DrawSprite(N : Integer);
begin
  with Lem[N] do
    case State of
      1 : if Dir < 1 then                                   { walker }
            Blit(Bank(WalkBank + (Frame + 4) * 54), X - 3, Y - 8, 6, 9, BackSeg)
          else
            Blit(Bank(WalkBank + Frame * 54), X - 3, Y - 8, 6, 9, BackSeg);

      2 : if FallDist < 4 then                              { faller, short }
          begin
            if Dir < 1 then
              Blit(Bank(WalkBank + (Frame + 4) * 54), X - 3, Y - 8, 6, 9, BackSeg)
            else
            begin
              Blit(Bank(WalkBank + Frame * 54), X - 3, Y - 8, 6, 9, BackSeg);
              Frame := (Frame + 1) mod 4 + 1;
            end;
          end
          else                                              { faller, long }
            Blit(Bank(FallBank + Frame * 100), X - 3, Y - 10, 10, 10, BackSeg);

      3 : Blit(Bank(TimerBank + Frame * 150), X - 4, Y - 9, 15, 10, BackSeg);
      4 : Blit(Bank(MinerBank + Frame * 221), X - 8, Y - 12, 17, 13, BackSeg);
      5 : Blit(Bank(BuildBank + Frame * 120), X - 4, Y - 8, 12, 10, BackSeg);

      6 : begin                                             { death A }
            if Frame = 1 then
              Blit(Bank($BF97), 95, 50, 60, 53, BackSeg);   { the flash }
            Blit(Bank(DeathABank + Frame * 108), X - 4, Y - 11, 9, 12, BackSeg);
          end;

      7 : Blit(Bank(DeathBBank + Frame * 160), X - 5, Y - 8, 16, 10, BackSeg);
      8 : Blit(Bank(SplatBank + Frame * 120), X - 4, Y - 8, 12, 10, BackSeg);
     10 : Blit(Bank(BashBank + Frame * 140), X - 8, Y - 9, 14, 10, BackSeg);

     11 : if Frame < 10 then                                { explosion }
            Blit(Bank($26D0), X - 31, Y - 48, 63, 55, BackSeg)
          else
            Blit(Bank($1947 + (Frame - 8) * $D89), X - 31, Y - 48, 63, 55, BackSeg);
    end;
end;

{ [transcribed] the spawn script writes a target and skill into a SLOT. }
procedure Script(Slot, TX, TY : Integer; St : Byte);
begin
  Lem[Slot].TargetX  := TX;
  Lem[Slot].TargetY  := TY;
  Lem[Slot].TargetSt := St;
end;

{ [stub] one column of Effect_ColumnSlideIn. }
{ [transcribed] one column of Effect_ColumnSlideIn: move the column up by
  Amount pixels and blank what it leaves behind. The stride is $140 = 320, so
  it works on the linear mode-13h buffer. }
procedure ShiftColumnUp(Col, Amount : Integer);
var
  Row : Integer;
begin
  for Row := 0 to 199 - Amount do
    Mem[VirtScrSeg : Row * ScrWidth + Col] :=
      Mem[VirtScrSeg : (Row + Amount) * ScrWidth + Col];
  for Row := 200 - Amount to 199 do
    Mem[VirtScrSeg : Row * ScrWidth + Col] := 0;
end;

{ [stub] one scroller character. }
procedure DrawChar(Pos : Integer; Ch : Char);
begin
end;

{ [stub] level setup and the periodic refresh every 20 frames. }
procedure Setup;
begin
end;

procedure SetupPeriodic;
begin
end;

{ [stub] one step of the closing palette fade. }
{ [inferred] one step of the closing fade: every channel down by one until
  the whole DAC is black. }
{ [transcribed] 11e3:0260 -- one step of the 64-step fade IN, run while the
  column slide-in is on screen. }
procedure FadeStep;
var
  I       : Integer;
  R, G, B : Byte;
begin
  WaitRetrace;
  for I := 0 to 255 do
  begin
    GetRGB(I, R, G, B);
    if R < Palette[I, 0] then Inc(R);
    if G < Palette[I, 1] then Inc(G);
    if B < Palette[I, 2] then Inc(B);
    SetRGB(I, R, G, B);
  end;
end;

procedure FadePaletteStep;
var
  I       : Integer;
  R, G, B : Byte;
begin
  WaitRetrace;
  for I := 0 to 255 do
  begin
    GetRGB(I, R, G, B);
    if B > 0 then Dec(B);
    if G > 0 then Dec(G);
    if R > 0 then Dec(R);
    SetRGB(I, R, G, B);
  end;
end;

{ [stub] the twenty asset reads from NEUROSIS.DAT $1228CE. }
{ [inferred] Lemmings_LoadAssets 1005:00a6 -- twenty reads from NEUROSIS.DAT
  $1228CE totalling 202,007 bytes: three palettes, two 320x200 screens and
  fourteen sprite banks between 400 and 24,255 bytes. The banks are the
  per-skill animation sets DrawSprite indexes. }
{ --------------------------------------------------------------------------
  Lemmings_LoadAssets (1005:00a6) -- transcribed.

  Not a single bulk load: it interleaves reading with the opening effect, so
  the column slide-in plays while the rest of the level is still on disk.
  -------------------------------------------------------------------------- }
procedure LoadAssets;
var
  F   : file;
  Pal : TPalette;
  I   : Integer;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, $1228CE);

  GetMem(Aux, $5B8C);                          { 23,436-byte block }
  BlockRead(F, Aux^, $5B8C);

  ClearScreen($A000, 0);
  BlockRead(F, Pal, 768);
  SetPalette;
  BlockRead(F, Mem[VirtScrSeg : 0], 64000);

  ColumnSlideIn;                               { plays before the rest loads }
  Delay($514);
  GetPalette;
  for I := 1 to 64 do FadeStep;

  ClearScreen($A000, 0);
  BlockRead(F, Mem[VirtScrSeg : 0], 64000);
  BlockRead(F, Pal, 768);
  BlockRead(F, FlashTarget, 768);              { DS:$CC07 -- the explosion }

  { the fourteen sprite banks, each to its own fixed DGROUP address }
  BlockRead(F, SpriteMem[$0522], $01B0);
  BlockRead(F, SpriteMem[$06D2], 400);
  BlockRead(F, SpriteMem[$12B8], $01E0);
  BlockRead(F, SpriteMem[$1498], $052E);
  BlockRead(F, SpriteMem[$19C6], $01A4);
  BlockRead(F, SpriteMem[$1B6A], 800);
  BlockRead(F, SpriteMem[$858F], $0C18);
  BlockRead(F, SpriteMem[$1E8A], $0288);
  BlockRead(F, SpriteMem[$2112], $02D0);
  BlockRead(F, SpriteMem[$BF97], $0C6C);
  BlockRead(F, SpriteMem[$91A7], $2AA8);
  BlockRead(F, SpriteMem[$BC4F], $0348);
  BlockRead(F, SpriteMem[$26D0], $5EBF);
  BlockRead(F, SpriteMem[$23E2], $02EE);

  Close(F);
  SetPalette;
  for I := $E0 to $E9 do SetRGB(I, 0, 0, 0);   { the explosion band starts black }
end;

{ [stub] six frames played backwards with Delay(150). }
{ [inferred] six frames played BACKWARDS with Delay(150) between them -- the
  level assembles itself before the simulation starts. }
procedure Intro;
var
  Frame : Integer;
begin
  for Frame := 6 downto 1 do
  begin
    Blit(Bank(LongInt(Frame - 1) * 64000), 0, 0, 320, 200, BackSeg);
    CopyScreen(BackSeg, $A000);
    Delay(150);
  end;
end;

procedure RestoreTextMode;
begin
  SetTextMode;
end;

{ --------------------------------------------------------------------------
  Lem_UpdateAll (1005:1a4c) -- one frame of the simulation.

  Terrain trigger colours, tested by the walker:
      3          -> death animation A (state 6)
      $12        -> state 9
      $20..$29   -> death animation B (state 7)
  -------------------------------------------------------------------------- }
procedure UpdateAll;
var
  I : Integer;
begin
  for I := 1 to MaxLems do
    with Lem[I] do
    begin
      if Y > 199 then Remove(I);           { fell off the bottom }
      if Alive = 0 then Continue;

      { a scripted skill fires when this lemming reaches its target }
      if (TargetX >= 0) and (TargetX = X) and
         (TargetY >= 0) and (TargetY = Y) then
      begin
        SetState(TargetSt, I);
        TargetX := 0;  TargetY := 0;
      end;

      if Countdown > 0  then Dec(Countdown);
      if Countdown = 1  then SetState(3, I);
      if Countdown < 0  then Inc(Countdown);
      if Countdown = -1 then Remove(I);

      DrawSprite(I);

      case State of
        1  : Walker(I);       2  : Faller(I);
        3  : TimerState(I);   4  : Miner(I);
        5  : Builder(I);      6  : DeathA(I);
        7  : DeathB(I);       8  : Splat(I);
        10 : Basher(I);      11  : Countdown11(I);
      end;
    end;
end;

{ --------------------------------------------------------------------------
  Lem_Spawn (1005:06e7)

  Releases from the hatch, and scripts the level: the Nth lemming released is
  handed a target position and the skill to use when it gets there, which is
  what makes the level solve itself with nobody at the controls.
  -------------------------------------------------------------------------- }
procedure Spawn;
var
  I : Integer;
begin
  if Released = TotalLems then Exit;
  for I := 1 to MaxLems do
    if Lem[I].Alive = 0 then
    begin
      with Lem[I] do
      begin
        X := HatchX;  Y := HatchY;
        TargetX := HatchX;  TargetY := HatchY;  TargetSt := 2;
        Tick := 0;  Alive := 1;  State := 2;  Dir := 1;
        Frame := 1;  Countdown := 0;  FallDist := 0;
      end;
      Inc(Released);
      { The release count is used purely as a clock -- the script writes into a
        chosen SLOT, and with only 25 slots the last two both target slot 1. }
      case Released of
         3 : Script(3, 50, 102, 10);       { slot 3 -> miner   }
         5 : Script(5, 49, 102,  4);       { slot 5 -> basher  }
        65 : Script(1, 181, 158, 10);      { slot 1 -> miner   }
        80 : Script(1, 223, 158,  5);      { slot 1 -> builder }
      end;
      Exit;
    end;
end;



{ --------------------------------------------------------------------------
  Bodies for the forward declarations above.
  -------------------------------------------------------------------------- }

{ [transcribed] Lem_Remove 1005:07d8 -- clears the alive flag and decrements
  the live count, but only if the slot WAS alive. }
procedure Remove(N : Integer);
begin
  if Lem[N].Alive <> 0 then
  begin
    Lem[N].Alive := 0;
    Dec(LiveCount);
  end;
end;

{ [transcribed] Lem_SetState 1005:0b22 -- state at +13, frame := 1, tick := 0. }
procedure SetState(S : Byte; N : Integer);
begin
  Lem[N].State := S;
  Lem[N].Frame := 1;
  Lem[N].Tick  := 0;
end;

{ --------------------------------------------------------------------------
  LemState2_Faller (1005:0b68)

  Scans the row directly below for ground. Landing depends on FallDist:

    < 11        land and walk, FallDist := 0
    >= 11       increment the hard-landing counter at +4; on the SECOND one
                the lemming splats, otherwise it lands normally

  While falling it drifts sideways for the first two rows only, which is what
  makes a lemming step off a ledge rather than drop vertically.
  -------------------------------------------------------------------------- }
procedure Faller(N : Integer);
var
  Dx : Integer;
  C  : Byte;
begin
  with Lem[N] do
  begin
    for Dx := -3 to 3 do
    begin
      C := GetPixel(X + Dx, Y + 1, VirtScrSeg);
      if C in Ground then
      begin
        if FallDist < SplatDrop then
        begin
          SetState(1, N);
          FallDist := 0;
        end
        else
        begin
          Inc(HardLandings);
          if HardLandings = 2 then
            SetState(8, N)                   { splat }
          else
          begin
            SetState(1, N);
            FallDist := 0;
          end;
        end;
        Frame := (Frame mod 4) + 1;
        Exit;
      end;
      if C in [$20..$29] then begin SetState(7, N); Exit end;
    end;

    if FallDist < 2 then Inc(X, Dir);        { drift, first two rows only }
    Inc(Y);
    Inc(FallDist);
    Frame := (Frame mod 4) + 1;
  end;
end;

{ --------------------------------------------------------------------------
  LemState4_Miner (1005:0df5) -- digs DIAGONALLY down-forward.

  Erases terrain by drawing colour 0, then every third tick advances a 6-frame
  cycle; on the frame wrap it moves TWO across and ONE down. Reverts to walker
  the moment nothing solid remains ahead.
  -------------------------------------------------------------------------- }
procedure Miner(N : Integer);
var
  Col  : Integer;
  Hit  : Boolean;
begin
  Hit := False;
  with Lem[N] do
  begin
    if Dir < 1 then
    begin
      for Col := X - 3 to X + 3 do
        if GetPixel(Col, Y + 1, VirtScrSeg) in Ground then Hit := True;
      DrawLine(X - 2, Y + 1, X - 2, Y - 11, 0, VirtScrSeg);
      DrawLine(X - 1, Y + 1, X - 1, Y - 11, 0, VirtScrSeg);
      DrawLine(X + 5, Y + 1, X - 5, Y + 1, 0, VirtScrSeg);
    end
    else
    begin
      for Col := X - 3 to X + 4 do
        if GetPixel(Col, Y + 1, VirtScrSeg) in Ground then Hit := True;
      FillRect(X + 4, Y, Y - 10, 0, VirtScrSeg);
      FillRect(X + 5, Y, Y -  9, 0, VirtScrSeg);
      FillRect(X + 6, Y - 1, Y -  8, 0, VirtScrSeg);
      FillRect(X + 7, Y - 2, Y -  7, 0, VirtScrSeg);
      FillRect(X + 8, Y - 3, Y -  6, 0, VirtScrSeg);
      FillTri(X - 3, X + 5, Y, 0, VirtScrSeg);
    end;

    Tick := (Tick mod 3) + 1;
    if Tick mod 3 = 0 then
    begin
      Frame := (Frame mod 6) + 1;
      if Frame mod 6 = 0 then
      begin
        Inc(X, Dir * 2);                     { two across ... }
        Inc(Y);                              { ... one down }
      end;
    end;

    if not Hit then SetState(1, N);
  end;
end;

{ --------------------------------------------------------------------------
  LemState10_Basher (1005:1166) -- digs HORIZONTALLY.

  Scans a vertical column ahead rather than the ground below, erases a slab,
  and moves ONE across every third frame with no vertical movement at all.
  -------------------------------------------------------------------------- }
procedure Basher(N : Integer);
var
  Col, Row : Integer;
  Hit      : Boolean;
begin
  Hit := False;
  with Lem[N] do
  begin
    if Dir < 1 then
    begin
      for Col := X - 5 to X - 4 do
        for Row := Y - 9 to Y do
          if GetPixel(Col, Row, VirtScrSeg) in Ground then Hit := True;
      FillRect(X - 4, Y, Y - 9, 0, VirtScrSeg);
      FillRect(X - 5, Y - 2, Y - 7, 0, VirtScrSeg);
      FillRect(X - 6, Y - 3, Y - 6, 0, VirtScrSeg);
    end
    else
    begin
      for Col := X + 4 to X + 5 do
        for Row := Y - 9 to Y do
          if GetPixel(Col, Row, VirtScrSeg) in Ground then Hit := True;
      FillRect(X + 1, Y, Y - 10, 0, VirtScrSeg);
      FillRect(X + 2, Y - 1, Y -  9, 0, VirtScrSeg);
      FillRect(X + 3, Y - 2, Y -  8, 0, VirtScrSeg);
      FillRect(X + 4, Y - 3, Y -  7, 0, VirtScrSeg);
      FillRect(X + 5, Y - 4, Y -  6, 0, VirtScrSeg);
      FillRect(X + 6, Y - 5, Y -  5, 0, VirtScrSeg);
    end;

    Frame := (Frame mod 3) + 1;
    if Frame mod 3 = 0 then Inc(X, Dir);     { one across, no Y change }

    if not Hit then SetState(1, N);
  end;
end;

{ --------------------------------------------------------------------------
  The three terminal animations. Transcribed -- the first reconstruction of
  these was inferred and got every detail wrong except the frame counts.

  Each removes the slot DIRECTLY when it runs out of frames. None of them uses
  the negative countdown, which is what an earlier version assumed.
  -------------------------------------------------------------------------- }

{ [transcribed] LemState6_DeathA 1005:1850 -- 7 frames, one every 5th tick. }
procedure DeathA(N : Integer);
begin
  with Lem[N] do
  begin
    Tick := (Tick mod 5) + 1;
    if Tick mod 5 = 0 then
    begin
      Inc(Frame);
      if Frame > 6 then Remove(N);
    end;
  end;
end;

{ [transcribed] LemState7_DeathB 1005:18a6 -- 6 frames, one every 3rd tick.
  Faster than death A. }
procedure DeathB(N : Integer);
begin
  with Lem[N] do
  begin
    Tick := (Tick mod 3) + 1;
    if Tick mod 3 = 0 then
    begin
      Inc(Frame);
      if Frame > 5 then Remove(N);
    end;
  end;
end;

{ [transcribed] LemState8_Splat 1005:17ff -- 4 frames, ungated, and then the
  detail that makes it worth reading: the splat mark is blitted into the
  VIRTUAL screen, not the back buffer. That buffer is also the collision map,
  so the stain is permanent -- it stays on the level for the rest of the part
  and every later lemming walks over it. }
procedure Splat(N : Integer);
begin
  with Lem[N] do
  begin
    Inc(Frame);
    if Frame = 4 then
    begin
      Blit(Bank($1420), X - 4, Y - 9, 12, 10, VirtScrSeg);
      Remove(N);
    end;
  end;
end;

{ --------------------------------------------------------------------------
  LemState11_Countdown (1005:1954) -- the explosion.

  Tick cycles 1..5 and the work happens on every third tick. While the frame
  is under 10 it runs FIVE passes of a one-step fade over palette entries
  $E0..$E9, each channel walking up towards a target palette held in DGROUP --
  so the flash builds rather than being a computed colour ramp.

  Past frame 15 it arms the countdown at -60 (only if it is not already
  negative) and then DECREMENTS the frame, which pins it at 15 while the
  countdown runs up to -1 and Lem_UpdateAll removes the slot.

  NOTE: in the original all three channel comparisons appear to test the same
  variable -- the red one -- rather than one each. That is either a decompiler
  artefact or a genuine bug in the 1994 code; it is written the natural way
  here, per channel.
  -------------------------------------------------------------------------- }
procedure Countdown11(N : Integer);
var
  Pass, I : Integer;
  R, G, B : Byte;
begin
  with Lem[N] do
  begin
    Tick := (Tick mod 5) + 1;
    if Tick mod 3 <> 0 then Exit;

    Inc(Frame);
    if Frame < 10 then
      for Pass := 1 to 5 do
        for I := $E0 to $E9 do
        begin
          GetRGB(I, R, G, B);
          if R < FlashTarget[I, 0] then Inc(R);
          if G < FlashTarget[I, 1] then Inc(G);
          if B < FlashTarget[I, 2] then Inc(B);
          SetRGB(I, R, G, B);
        end;

    if Frame > 15 then
    begin
      if Countdown >= 0 then Countdown := -60;
      Dec(Frame);
    end;
  end;
end;

{ --------------------------------------------------------------------------
  LemState1_Walker (1005:14d6)
  -------------------------------------------------------------------------- }
procedure Walker;
{ The goto mirrors the original's control flow -- LemState1_Walker jumps to
  LAB_1005_1791 from inside the step-climb scan -- so it is kept rather than
  restructured. }
label
  Step;
var
  Dx, Row, Col : Integer;
  C            : Byte;
begin
  with Lem[N] do
  begin
    { 1 -- is there ground under us, and is any of it lethal? }
    for Dx := -3 to 3 do
    begin
      C := GetPixel(X + Dx, Y + 1, VirtScrSeg);
      if C = 3            then begin SetState(6, N); Exit end;   { death A }
      if C = $12          then begin SetState(9, N); Exit end;   { see NOTES }
      if C in [$20..$29]  then begin SetState(7, N); Exit end;   { death B }
      if C in Ground      then Break;
      if Dx = 3           then begin SetState(2, N); Exit end;   { no ground }
    end;

    { 2 -- a wall taller than about five pixels turns us around }
    for Row := Y - 9 to Y - 4 do
      for Col := X + 3 * Dir to X + 5 * Dir do
        if GetPixel(Col, Row, VirtScrSeg) in Wall then
        begin
          Dir := -Dir;
          Exit;
        end;

    { 3 -- otherwise a step up to five pixels is climbed }
    for Row := Y - 4 to Y do
      for Col := X + 3 * Dir to X + 4 * Dir do
        if GetPixel(Col, Row, VirtScrSeg) in Wall then
        begin
          Y := Row - 1;
          Goto Step;
        end;

  Step:
    Inc(X, Dir);
    Tick := (Tick mod 2) + 1;
    if Tick mod 2 = 0 then
      Frame := (Frame mod 4) + 1;          { 4-frame cycle at half rate }
  end;
end;

{ --------------------------------------------------------------------------
  LemState2_Faller (1005:0b68) -- the shape shared by the digging states.

    for Step := 1 to .. do
      for Dx := -3 to 3 do
        if GetPixel(X + Dx, Y + Step, VirtScrSeg) in Ground then
        begin
          if FallDist < SplatDrop then SetState(1, N)    (* land and walk *)
          else                         SetState(8, N);   (* splat *)
          Exit;
        end;
    Inc(Y);  Inc(FallDist);

  LemState4_Basher and LemState10_Miner share that shape but ERASE terrain --
  drawing colour 0 with VGA_DrawLine / VGA_FillRect / VGA_FillTri, horizontally
  for the basher and diagonally down-forward for the miner. Both revert to
  walker once nothing solid remains ahead.
  -------------------------------------------------------------------------- }

{ --------------------------------------------------------------------------
  LemState3_Timer (1005:18fc) -- the "oh no" animation.

  Five frames at one per three ticks, then straight into the explosion.
  -------------------------------------------------------------------------- }
procedure TimerState;
begin
  with Lem[N] do
  begin
    Tick := (Tick mod 3) + 1;
    if Tick mod 3 = 0 then
    begin
      Inc(Frame);
      if Frame > 5 then SetState(11, N);
    end;
  end;
end;

{ --------------------------------------------------------------------------
  LemState5_Builder (1005:0d1a)

  Every third tick advances a 6-frame cycle; frame 6 lays a brick. The
  staircase climbs two pixels across for every one up, and because BrickColour
  ($4D) is in the Ground set the brick is walkable the instant it is drawn.

  After 500 ticks the builder reverts to a walker AND arms its countdown at 20
  -- so twenty frames later the countdown reaches 1, which triggers state 3,
  which triggers state 11. The builder finishes its staircase and then blows
  itself up.
  -------------------------------------------------------------------------- }
procedure Builder;
begin
  with Lem[N] do
  begin
    Inc(Tick);
    if Tick mod 3 = 0 then
    begin
      Frame := (Frame mod 6) + 1;
      if Frame = 6 then
      begin
        Inc(X, 2);
        Dec(Y);
        FillTri(X + 2, X - 2, Y + 2, BrickColour, VirtScrSeg);
      end;
    end;

    if Tick = 500 then
    begin
      SetState(1, N);
      Countdown := 20;                     { ... and self-destruct }
    end;
  end;
end;

{ --------------------------------------------------------------------------
  LemState11_Countdown (1005:1954)
  Flashes palette entries $E0..$E9 over five steps, then arms the countdown at
  -60, which counts UP to -1 and removes the lemming.
  -------------------------------------------------------------------------- }

var
  CharPos, CharIndex, WalkCounter, WalkPhase : Integer;
  Band : array[1..24] of Byte;

{ --------------------------------------------------------------------------
  Effect_ColumnSlideIn (1005:0000)

  200 columns spanning x = 60..259 each scroll into place at the same rate but
  with a random head start, so the image assembles as a ragged vertical wipe.
  The stride $140 = 320 confirms it works on the linear mode-13h buffer.
  -------------------------------------------------------------------------- }
procedure ColumnSlideIn;
var
  Offs          : array[0..200] of Integer;
  I, Frame, Col : Integer;
begin
  for I := 0 to 200 do
    Offs[I] := Random(200) - 400;        { all negative: -400..-201 }

  for Frame := 1 to 400 do
    for Col := 200 downto 1 do
    begin
      if Offs[Col] <= 0 then
        ShiftColumnUp(Col + 60, -Offs[Col]);
      Inc(Offs[Col]);
    end;
end;

{ --------------------------------------------------------------------------
  Lemming_Walk (1005:0a4f)
  A 3-frame walk cycle running at a quarter of the frame rate, taken off an
  11-state counter: frame := (counter shr 2) + 1.
  -------------------------------------------------------------------------- }
procedure LemmingWalk;
begin
  WalkCounter := (WalkCounter mod WalkStates) + 1;
  Blit(Bank(BigBank + LongInt((WalkCounter shr 2) + 1) * BigSprite), 113, 50, 43, 24, BackSeg);
end;

{ --------------------------------------------------------------------------
  Scroller_Step (1005:08ad)

  Advances the text, draws the two carrying lemmings -- one facing each way,
  indexed (4 - frame) and (frame + 4) into the same bank -- then rotates the
  8-entry colour band twice per frame.

  ASSETS  assets/part004/ -- twenty reads from NEUROSIS.DAT $1228CE totalling
          202,007 bytes: sprite banks, three palettes and two 320x200 screens.
  -------------------------------------------------------------------------- }
procedure ScrollerStep;
var
  I, J : Integer;
begin
  Inc(CharPos, CharStep);
  if CharPos > CharWrap then
  begin
    CharPos := 1;
    Inc(CharIndex);
  end;

  if CharIndex < ScrollLen then
    DrawChar(CharPos, ScrollText[CharIndex])
  else
    DrawChar(CharPos, ' ');

  WalkPhase := (WalkPhase mod WalkStates) + 1;
  Blit(Bank(SmallBank + LongInt(4 - ((WalkPhase shr 2) + 1)) * SmallSprite), 278, 27, 14, 10, BackSeg);
  Blit(Bank(SmallBank + LongInt((WalkPhase shr 2) + 4) * SmallSprite), 30, 27, 14, 10, BackSeg);

  for I := 1 to 2 do
  begin
    Move(Cycle[1], Cycle[0], 21);          { rotate the band }
    FillChar(Cycle[20], 3, LastColour);
    for J := 0 to CycleCount - 1 do
      SetRGB(CycleFirst + J, Cycle[J * 3], Cycle[J * 3 + 1], Cycle[J * 3 + 2]);
  end;
end;

{ --------------------------------------------------------------------------
  Lemmings_MainLoop (1005:1bbb)
  -------------------------------------------------------------------------- }
procedure MainLoop;
var
  Frame : LongInt;
  I     : Integer;
  Done  : Boolean;
begin
  Frame := 0;
  Done  := False;
  Setup;
  SetupPeriodic;
  repeat
    CopyScreen(VirtScrSeg, BackSeg);
    LemmingWalk;                           { the two text carriers }
    UpdateAll;                             { the game simulation }
    ScrollerStep;
    Inc(FrameCounter);                     { 32-bit }
    CopyScreen(BackSeg, $A000);

    Inc(Frame);
    if Frame mod 20 = 0 then SetupPeriodic;

    if KeyPressed or (Countdown = 0) then
    begin
      FadePaletteStep;
      for I := 1 to 24 do
        if Band[I] <> 0 then Dec(Band[I]);
      { step the music volume down twice per frame; zero means finished }
      if GetVolume = 0 then Done := True else SetVolume(GetVolume - 1);
      if GetVolume = 0 then Done := True else SetVolume(GetVolume - 1);
    end;
  until Done;
end;

procedure RunPart4;
begin
  SetMode13h;
  VirtScrAlloc;
  LoadAssets;
  Intro;                                   { six frames backwards, Delay(150) }
  MainLoop;
  FreeMem(Virt, 64000);
  FreeMem(Aux, 6138);
  RestoreTextMode;
  WriteLn(SignOff);
end;

end.

{ ===========================================================================
  THE SCROLL TEXT (1005:$3926 in the image)

    FOR THOSE OF YOU THAT REALLY HATE LONG, BORING SCROLLIES, WE DECIDED TO
    PUT A NEW TWIST ON IT ***      BUT IF YOU DONT LIKE LEMMINGS, THEN THERE
    IS NO HOPE, HIT ANY KEY NOW. THE ANY KEY? THE ONE ON THE SIDE MARKED
    -POWER-      ***

  237 characters, matching the bound the code tests against.
  =========================================================================== }

{ ===========================================================================
  NOTES

  STATE 9 DOES NOT EXIST.
  The dispatch chain in Lem_UpdateAll handles exactly ten states: 1, 2, 3, 4,
  5, 6, 7, 8, 10 and 11. The walker sets state 9 when it reads terrain colour
  $12, and nothing ever handles it -- the lemming is still drawn every frame
  but never moves, never ages its countdown, and never frees its slot. It
  freezes on the spot for the rest of the part.

  Whether $12 was meant to be the level's exit or this is simply an oversight
  cannot be told from the code. The behaviour is deterministic either way, and
  since the level is fully scripted it does not matter to what you see.
  =========================================================================== }
