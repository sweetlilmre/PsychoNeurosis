{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- PSYCHO.EXE, the launcher.

  This is the program the viewer runs, and it is the whole of it: 63 lines
  that start three other programs in turn and get out of the way.

  It never draws anything and it never runs parts 001..007. It EXECs
  exactly three children -- the setup program, DemoVT with the config file
  as its command line, and the end screen -- and the demo chain itself
  lives inside DemoVT, which loads and runs each part. So the sequence a
  viewer sees is not described anywhere in this file.

  Setup's exit code is a protocol, and it is the only branching here:
    1  skip the demo, still show the end screen
    2  quit silently
    anything else  run the demo

  SwapVectors brackets every EXEC, in pairs. Turbo Pascal installs its own
  interrupt handlers; a child process must not inherit them, so they are
  swapped out before the child starts and back in when it returns. Miss one
  and the surviving handler belongs to a program that is no longer resident.

  The config file is passed as `@neurosis.cfg`. The leading `@` is DemoVT's
  own response-file syntax, documented in its shipped DEMOVT.DOC -- so the
  player reads the file itself, and nothing here parses it.

  The memory directive below matters more than it looks: an EXEC parent
  stays resident while its child runs, so the launcher asks for the smallest
  heap it can and leaves the rest of the machine for the demo.

  =========================================================================== }

{ The two early exits are written as gotos rather than as nested ifs, which
  is worth knowing before somebody tidies them: each exit-code test jumps
  forward past the work it skips, and the three EXEC calls stay at one
  level. Reading the sequence top to bottom is the point of the shape. }


{ 286 instruction encodings are permitted. The demo requires a 386 in any
  case -- Detect.Is386 is the first thing setup asks. }
{$G+}
{$M $800,0,0}
program Psycho;

uses
  Dos;

label
  RunEnd, Done;

var
  Code : Byte;   { setup's exit code, low byte  }

begin
  SwapVectors;
  Exec('Neurosis.000', '');            { the setup program }
  SwapVectors;
  Code := Lo(DosExitCode);             { AH=4Dh, low byte  }
  if Code = 1 then goto RunEnd;        { skip the demo, keep the ending }
  if Code = 2 then goto Done;          { quit silently                  }
  SwapVectors;
  Exec('neurosis.008', '@neurosis.cfg');       { DemoVT    }
  SwapVectors;
RunEnd:
  SwapVectors;
  Exec('neurosis.009', '');            { the end screen    }
  SwapVectors;
Done:
end.
