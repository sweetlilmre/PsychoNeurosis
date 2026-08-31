{ ===========================================================================
  VIDMODE -- set a video mode from the command line. A tool, not part of the
  reconstruction.

  WHY IT EXISTS. The demo ran under PSYCHO.EXE, which launched each part in
  turn, so a part is entitled to leave the adapter however the next one wants
  it. Part 004 does exactly that: its program calls SetMode13h at 1000:001c
  and never calls SetTextMode, because NEUROSIS.005 was going to run next.
  Running one part on its own is not how any of them were invoked, and a part
  that ends in mode 13h leaves the DOS prompt unreadable.

  So the tidying up lives out here, in RUNPART.BAT, rather than being added to
  a part where the original has none. That is the same reasoning that moved the
  NEUROSIS.DAT check out of the parts: anything the 1994 binary does not do
  belongs outside it.

  Usage:

      VIDMODE TEXT     mode 3, 80x25 colour text
      VIDMODE VGA      mode 13h, 320x200 in 256 colours

  Two words rather than a number on purpose. "VIDMODE 13" is ambiguous -- mode
  13h is 19 decimal -- and a video mode is not worth a parsing bug.

  No Crt, no VGA, no DemoVT: this is a few bytes of INT 10h and it should stay
  that way. It writes nothing on success, so it cannot scribble on a screen
  another program is about to use.
  =========================================================================== }

program VidMode;

var
  Mode : Byte;
  Arg  : String;
  I    : Integer;

begin
  if ParamCount <> 1 then
  begin
    WriteLn('VIDMODE: set a video mode.  Usage:  VIDMODE TEXT | VGA');
    Halt(2);
  end;

  { Upper-case in place rather than pulling in a unit for UpCase. }
  Arg := ParamStr(1);
  for I := 1 to Length(Arg) do
    if (Arg[I] >= 'a') and (Arg[I] <= 'z') then
      Arg[I] := Chr(Ord(Arg[I]) - 32);

  if Arg = 'TEXT' then
    Mode := $03
  else if Arg = 'VGA' then
    Mode := $13
  else
  begin
    WriteLn('VIDMODE: "', Arg, '" is neither TEXT nor VGA.');
    Halt(2);
  end;

  asm
    MOV  AH, 0          { set video mode }
    MOV  AL, Mode
    INT  10h
  end;
end.
