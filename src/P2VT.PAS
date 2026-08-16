{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.002, the music unit.

  Segment 13f9 in NEUROSIS_002_fpu.exe, transcribed in full -- all ten
  routines, nothing inferred.

  This is not a player. It is the client side of a resident tracker, found
  through the multiplex interrupt:

      INT $2F with AX = $5654, BX = $5472, CX = $6163      'VT' 'Tr' 'ac'
      resident if AX = 0, BX = $3F17, CX = $1343

  The far pointer at ES:[DI-4] is the TSR's data block; the routine entry
  point lives at block+$121 and its segment at block+$123. Everything else is
  reached by poking fields of that block:

      block + [$0CDC]   the song position, a LongInt
      block + [$0CDE]   a three-byte sync slot: a flag then two values
      block + [$0CE4]   the volume, one byte

  Every entry point checks DS:$0CD4 (the block's segment) for zero first and
  does nothing if the tracker is not resident, so all of this is harmless
  without it. The offsets at $0CDC/$0CDE/$0CE4 are initialised data, read from
  DGROUP.
  =========================================================================== }

unit P2VT;

interface

procedure MusicDetect;                    far;   { 13f9:0000 }
procedure MusicPoll;                      far;   { 13f9:0040  function 2 }
procedure MusicStart;                     far;   { 13f9:004e  function 0 }
procedure MusicStop;                      far;   { 13f9:005c  function 1 }
function  MusicPos : LongInt;             far;   { 13f9:006a }
procedure MusicCue;                       far;   { 13f9:0085 }
procedure SyncPattern(A, B : Byte);       far;   { 13f9:00ca }
procedure SetVolume(V : Byte);            far;   { 13f9:00f2 }
function  GetVolume : Byte;               far;   { 13f9:010e }

var
  { DS:$0CD2/$0CD4 the block, DS:$0CD6/$0CD8 the entry point. Zero when the
    tracker is not resident, which is what every routine below tests. }
  BlockOfs, BlockSeg : Word;
  EntryOfs, EntrySeg : Word;
implementation

const
  CuePosition = $19;      { 13f9:00af -- MusicCue polls until the position
                            reaches 25, then zeroes it }

  { DS:$0CDC, $0CDE and $0CE4 are INITIALISED DATA -- nothing in the
    executable writes them, so these are the compiled-in values read straight
    out of DGROUP. ($0CE0 = $0204 and $0CE2 = $0205 hold the second and third
    sync bytes as separate constants; the code reaches them with INC SI
    instead, so they are not needed here.) }
  PosField  = $0125;      { DS:$0CDC -- the song position, a LongInt }
  SyncField = $0203;      { DS:$0CDE -- flag, then two values }
  VolField  = $0206;      { DS:$0CE4 -- the volume byte }

{ 13f9:0000 -- probe for the resident tracker and cache its block and entry. }
procedure MusicDetect; assembler;
asm
  mov  ax, $5654
  mov  bx, $5472
  mov  cx, $6163
  xor  di, di
  mov  es, di
  int  $2F
  and  ax, ax
  jnz  @@none
  cmp  bx, $3F17
  jnz  @@none
  cmp  cx, $1343
  jnz  @@none
  les  di, es:[di-4]
  mov  BlockOfs, di
  mov  BlockSeg, es
  mov  ax, es:[di+$121]
  mov  EntryOfs, ax
  mov  ax, es:[di+$123]
  mov  EntrySeg, ax
@@none:
end;

{ Call the tracker's entry point with a function number.
  13f9:0040 passes 2, 13f9:004e passes 0, 13f9:005c passes 1.

  The original is `PUSH n / CALLF [$0CD6]` with no stack fixup afterwards, so
  the tracker cleans up its own argument -- the ordinary Pascal convention,
  which is what a procedural type gives us here. }
type
  TTrackerProc = procedure(Func : Word);

procedure Call(Func : Word);
var
  Proc : TTrackerProc;
begin
  if BlockSeg = 0 then Exit;
  @Proc := Ptr(EntrySeg, EntryOfs);
  Proc(Func);
end;

procedure MusicPoll;  begin Call(2); end;    { 13f9:0040 }
procedure MusicStart; begin Call(0); end;    { 13f9:004e }
procedure MusicStop;  begin Call(1); end;    { 13f9:005c }

{ 13f9:006a -- read the LongInt at block + PosField. Zero when not resident. }
function MusicPos : LongInt;
begin
  if BlockSeg = 0 then
    MusicPos := 0
  else
    MusicPos := MemL[BlockSeg : BlockOfs + PosField];
end;

{ --------------------------------------------------------------------------
  13f9:0085 -- cue the module to a known place.

      zero the position
      repeat  MusicPoll  until  MusicPos - $19 = 0
      zero the position again

  So it spins the tracker forward until it reports position 25, then resets
  the counter -- which is how the scene's timing gets pinned to the music.
  -------------------------------------------------------------------------- }
procedure MusicCue;
var
  Target : LongInt;
begin
  if BlockSeg = 0 then Exit;
  Target := MusicPos;                        { 13f9:008c, result discarded }
  MemL[BlockSeg : BlockOfs + PosField] := 0;
  Target := 0;
  repeat
    MusicPoll;
  until MusicPos - CuePosition = Target;
  MemL[BlockSeg : BlockOfs + PosField] := 0;
end;

{ --------------------------------------------------------------------------
  13f9:00ca -- write the three-byte sync slot at block + SyncField:

      [0] := 1          the "there is a request" flag
      [1] := A          BP+8, the FIRST declared parameter
      [2] := B          BP+6

  Scene1_Run calls it as (5, 1).
  -------------------------------------------------------------------------- }
procedure SyncPattern(A, B : Byte);
begin
  if BlockSeg = 0 then Exit;
  Mem[BlockSeg : BlockOfs + SyncField]     := 1;
  Mem[BlockSeg : BlockOfs + SyncField + 1] := A;
  Mem[BlockSeg : BlockOfs + SyncField + 2] := B;
end;

{ 13f9:00f2 / 13f9:010e -- the volume byte at block + VolField. }
procedure SetVolume(V : Byte);
begin
  if BlockSeg = 0 then Exit;
  Mem[BlockSeg : BlockOfs + VolField] := V;
end;

function GetVolume : Byte;
begin
  if BlockSeg = 0 then
    GetVolume := 0
  else
    GetVolume := Mem[BlockSeg : BlockOfs + VolField];
end;

{ 13f9:0123 -- the unit's initialisation body is empty. }
begin
end.
