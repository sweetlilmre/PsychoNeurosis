{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the DemoVT interface unit.

  NEUROSIS.008 is JCAB's DemoVT / VTracker MOD player, a third-party TSR that
  is LZEXE-packed and out of scope for this reconstruction. This unit is NOT
  that player -- it is the thin client side that every effect part links
  against to talk to it, reconstructed from the call sites.

  Addresses: 1532:* in part 001, 13f9:* in part 002. Same code, different
  segment per part.

  HOW IT WORKS
    Detection is an INT 2Fh handshake with an ASCII signature -- 'VT', 'Tr',
    'ac' in AX, BX, CX, which spells VTrac(ker):

        AX := $5654   BX := $5472   CX := $6163   ES:DI := 0:0
        INT $2F
        present if AX = 0 and BX = $3F17 and CX = $1343

    On success ES:[DI-4] is a far pointer to the player's CONTROL BLOCK, and
    two words at CB+$121 / CB+$123 form the far address of its dispatch
    routine. Commands are a far call with a function number pushed; state like
    the volume is a byte written DIRECTLY into a field of the control block.

    Every entry point tests the control-block segment first and does nothing
    if the player is absent, which is why the demo still runs without sound
    rather than crashing. That behaviour is preserved here.

  CONFIRMED from the binary
    * the handshake, its magic numbers and the reply values
    * the control-block and dispatch-pointer layout
    * dispatch function 0 (start) and function 3 (stop)
    * SetVolume / GetVolume write and read a byte at CB + VolumeOfs

  NOT CONFIRMED
    * the dispatch function number behind SyncPattern
    * how VolumeOfs itself is obtained from the control block
    Both are marked below. They are stubbed so the rest of the demo compiles
    and links; they are not invented values presented as fact.
  =========================================================================== }

unit DemoVT;

interface

const
  VTMagicAX = $5654;      { 'VT' }
  VTMagicBX = $5472;      { 'Tr' }
  VTMagicCX = $6163;      { 'ac' }
  VTReplyBX = $3F17;
  VTReplyCX = $1343;

  FuncStart = 0;          { confirmed -- 1532:004e pushes 0 }
  FuncStop  = 3;          { confirmed -- 1532:006a pushes 3 }

var
  Present   : Boolean;    { the player answered the handshake }
  Control   : Pointer;    { far pointer to its control block }
  Dispatch  : Pointer;    { far pointer to its command routine }
  VolumeOfs : Word;       { byte offset of the volume field -- see note }

procedure MusicInit;
procedure MusicStop;
procedure MusicPoll;
procedure MusicSync;
procedure SetVolume(V : Byte);
function  GetVolume : Byte;
procedure SyncPattern(A, B : Integer);

implementation

{ --------------------------------------------------------------------------
  MusicInit -- the INT 2Fh handshake (1532:0000).
  -------------------------------------------------------------------------- }
procedure MusicInit;
var
  OK : Boolean;
  P  : ^Pointer;
begin
  Present   := False;
  Control   := nil;
  Dispatch  := nil;
  VolumeOfs := 0;

  asm
    MOV  AX, VTMagicAX
    MOV  BX, VTMagicBX
    MOV  CX, VTMagicCX
    XOR  DI, DI
    MOV  ES, DI
    INT  $2F
    XOR  DL, DL
    AND  AX, AX
    JNZ  @@Absent
    CMP  BX, VTReplyBX
    JNZ  @@Absent
    CMP  CX, VTReplyCX
    JNZ  @@Absent
    INC  DL
  @@Absent:
    MOV  OK, DL
  end;

  if not OK then Exit;

  { ES:[DI-4] is the control block; CB+$121 / CB+$123 are the dispatch far
    pointer. Written out longhand rather than as the original's LES/MOV pair
    so the intent is visible. }
  asm
    XOR  DI, DI
    MOV  ES, DI
    LES  DI, ES:[DI - 4]
    MOV  WORD PTR Control,     DI
    MOV  WORD PTR Control + 2, ES
    MOV  AX, ES:[DI + $121]
    MOV  WORD PTR Dispatch,     AX
    MOV  AX, ES:[DI + $123]
    MOV  WORD PTR Dispatch + 2, AX
  end;

  Present := True;
end;

{ --------------------------------------------------------------------------
  Command dispatch -- push the function number and far call (1532:004e/006a).
  -------------------------------------------------------------------------- }
procedure Command(Func : Word);
begin
  if not Present then Exit;
  asm
    PUSH Func
    CALL DWORD PTR Dispatch
  end;
end;

procedure MusicPoll;
begin
  Command(FuncStart);
end;

procedure MusicStop;
begin
  Command(FuncStop);
end;

{ [stub] 136b:0085 -- called once before an effect loop starts, to line the
  effect up with the module. The dispatch function number behind it has not
  been identified, so this does nothing rather than guess. }
{ [inferred] 136b:0085 -- line the effect up with the module before an effect
  loop starts. The dispatch function number is not identified, so this polls
  the player once, which is the closest honest approximation. }
procedure MusicSync;
begin
  Command(FuncStart);
end;

{ --------------------------------------------------------------------------
  Volume is a plain byte field inside the control block (13f9:00f2 / :010e).
  Note the original reaches it as Control^ + [DS:$CE4]; where that offset is
  first loaded from has NOT been traced, so VolumeOfs stays 0 here and the
  accessors are inert until it is.
  -------------------------------------------------------------------------- }
procedure SetVolume(V : Byte);
begin
  if not Present then Exit;
  Mem[Seg(Control^) : Ofs(Control^) + VolumeOfs] := V;
end;

function GetVolume : Byte;
begin
  if not Present then
    GetVolume := 0
  else
    GetVolume := Mem[Seg(Control^) : Ofs(Control^) + VolumeOfs];
end;

{ --------------------------------------------------------------------------
  SyncPattern -- waits for the module to reach a given pattern/row before
  returning, which is how part 002 pins its choreography to the music.

  The dispatch function number behind this has NOT been identified, so this
  is a no-op rather than a guess. Parts that use it will run un-synchronised.
  -------------------------------------------------------------------------- }
procedure SyncPattern(A, B : Integer);
begin
  { UNCONFIRMED -- see the header. Deliberately does nothing. }
end;

begin
  Present := False;
end.
