(* ===========================================================================
  LOADPART -- run a file DOS refuses to launch by name. A tool, not part of the
  reconstruction.

  WHY IT EXISTS. The shipped parts are called NEUROSIS.001 .. NEUROSIS.007 and
  every one of them is a perfectly good MZ executable, but COMMAND.COM will not
  start one. Its command-line parser decides what is executable purely by
  extension -- .COM, then .EXE, then .BAT -- and anything else is "Bad command
  or file name". That is a rule of the SHELL and not of the loader.

  DOS's loader does not care at all. INT 21h/4B00h takes a path, reads the MZ
  header and applies its relocations whatever the file is called, which is how
  the demo itself ran: PSYCHO.PAS EXECs `Neurosis.000`, `neurosis.008` and
  `neurosis.009` by those names. This is that call with a command line in front
  of it, so a shipped part can be run beside the reconstruction without being
  copied to a new name first.

  Usage, from the folder holding the file:

      LOADPART NEUROSIS.001
      LOADPART NEUROSIS.008 @neurosis.cfg

  Everything after the first argument is passed to the child as its command
  line, which is what the second example needs -- DemoVT reads its settings
  from a response file named that way.

  THIS HEADER USES THE PARENTHESIS-STAR DELIMITERS RATHER THAN BRACES, because
  it quotes a compiler directive below. A closing brace ends a brace comment
  wherever it appears, so with braces the block would have ended inside the
  quoted directive and every line after it would have been parsed as code --
  paslint reported exactly that, twice, and refused the build. BLITCLIP.INC
  carries these delimiters for the same reason. Note that the parenthesis-star
  form does not nest either, so a header must not quote its own delimiters.

  THE MEMORY DIRECTIVE BELOW IS LOAD-BEARING, NOT TIDINESS. An EXEC parent
  stays resident while its child runs, and Turbo Pascal's default heap takes
  all of free memory, so the child gets "Not enough memory" or simply fails to
  load. A zero heap hands it all back. The parts are the reason this matters:
  they want the memory, and it is the same constraint that made RUNPART.BAT a
  batch file instead of a Pascal launcher.

  EXEC DOES NOT SEARCH PATH. It is a raw loader call, so the name has to be
  findable from the current directory or be a full path. Nothing here tries to
  be clever about that: a file DOS cannot find is reported as DosError 2 and
  the message says so.

  VERIFIED BY A WATCHED RUN, 28 Aug 2026: the maintainer ran the shipped
  NEUROSIS.001 through it under DOSBox-X and part 001 ran and exited cleanly.
  That is the only instrument there is for this -- a loader either hands the
  child a correctly relocated image or it does not, and no static check on
  either file can tell you which happened.

  WHAT IT DELIBERATELY DOES NOT DO. It does not set a video mode, restore one,
  or look for NEUROSIS.DAT. A part is entitled to leave the adapter as it
  pleases -- see VIDMODE.PAS and RUNPART.BAT for that reasoning -- and this
  program's whole job is to be a loader and nothing else. Follow it with
  `VIDMODE TEXT` if the child leaves you in mode 13h, exactly as RUNPART does.
  =========================================================================== *)

{$M 2048,0,0}

program LoadPart;

uses Dos;

var
  Args : String;
  I    : Integer;

begin
  if ParamCount < 1 then
  begin
    WriteLn('LOADPART - run a file DOS will not launch by name.');
    WriteLn;
    WriteLn('  Usage:  LOADPART file [arguments]');
    WriteLn;
    WriteLn('  COMMAND.COM only starts .COM, .EXE and .BAT. This loads any');
    WriteLn('  MZ executable whatever it is called, e.g.');
    WriteLn('  LOADPART NEUROSIS.001');
    Halt(1);
  end;

  { Everything past the first argument, rebuilt as one command line. DOS gives
    the child a single counted string, so this is the shape it wants anyway. }
  Args := '';
  for I := 2 to ParamCount do
  begin
    if Args <> '' then Args := Args + ' ';
    Args := Args + ParamStr(I);
  end;

  { SwapVectors on BOTH sides. The child installs its own interrupt handlers --
    every part of this demo hooks the timer for its music -- and the parent's
    have to be out of the way while it runs and back afterwards. Skipping the
    second call leaves the child's handlers pointing into memory the parent is
    about to reuse. }
  SwapVectors;
  Exec(ParamStr(1), Args);
  SwapVectors;

  if DosError <> 0 then
  begin
    Write('LOADPART: could not run ', ParamStr(1), ' -- DosError ', DosError);
    case DosError of
      2 : WriteLn(' (no such file in this directory)');
      8 : WriteLn(' (not enough memory)');
     10 : WriteLn(' (bad environment)');
     11 : WriteLn(' (bad format -- not an MZ executable?)');
    else
      WriteLn;
    end;
    Halt(1);
  end;

  { The child's own exit code, so this is transparent in a batch file. }
  if DosExitCode <> 0 then Halt(DosExitCode);
end.
