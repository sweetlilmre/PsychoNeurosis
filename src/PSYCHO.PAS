{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- PSYCHO.EXE, the launcher.

  Read from bin/PSYCHO.EXE (1,936 bytes); the chart is
  docs/29-psycho-launcher.md and every routine below it is Borland's own
  Dos unit, so this file is the whole reconstruction. The original's own
  code is main at 1000:0036 -- 122 bytes -- plus five string literals.

  The launcher never runs parts 001..007. It EXECs exactly three children:
  the setup program, DemoVT with the config file as its command line, and
  the end screen. The demo chain lives inside DemoVT.

  Setup's exit code is a protocol:
    1  skip the demo, still show the end screen
    2  quit silently
    anything else  run the demo

  The $M directive below is measured, not style: the binary's MZ header
  has minalloc = maxalloc = 166 paragraphs, the smallest footprint that
  still loads -- an EXEC parent must leave RAM for its children.

  DGROUP (106d)
    DS:$0050  the child's exit code       DS:$0052  DosError
    DS:$0054  Exec's saved SP             DS:$0056  Exec's saved SS
    DS:$0258  SwapVectors' 19-entry saved-vector table
  =========================================================================== }

{ The gotos are the original's: TP7 compiles "if X then goto L" to the
  JNZ-over-JMP at 1000:0064 and 1000:006d, and the byte comparison against
  the binary only closes with this shape -- a nested if reorders the tests
  and shortens the jumps, moving every relocation after it by four bytes. }

{$G+}   { measured: the original closes main with LEAVE (C9), a 286
          encoding -- with $G- TP7 emits POP BP (5D) there instead, the
          one byte of 1,936 that then differs }
{$M $800,0,0}
program Psycho;

uses
  Dos;

label
  RunEnd, Done;

var
  Code : Byte;   { DS:$0050 }

begin
  SwapVectors;
  Exec('Neurosis.000', '');            { 1000:0043 -- the setup program }
  SwapVectors;
  Code := Lo(DosExitCode);             { 1000:0057 -- AH=4Dh, low byte  }
  if Code = 1 then goto RunEnd;        { skip the demo, keep the ending }
  if Code = 2 then goto Done;          { quit silently                  }
  SwapVectors;
  Exec('neurosis.008', '@neurosis.cfg');       { 1000:0080 -- DemoVT    }
  SwapVectors;
RunEnd:
  SwapVectors;
  Exec('neurosis.009', '');            { 1000:0099 -- the end screen    }
  SwapVectors;
Done:
end.
