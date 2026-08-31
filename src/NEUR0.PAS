{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.000, the setup program.

  Read from bin/NEUROSIS.000; the chart is docs/31-startup.md. The appended
  debug info names the source (NEUR0.PAS, saved 6 Feb 1994, 00:11 -- the
  night before the demo shipped), every routine, and every local.

  What it does: paints a shaded backdrop, walks up to five menus (sound
  card, IRQ, DMA, port, sampling rate) with the arrow keys, and writes
  NEUROSIS.CFG -- five switch lines, /v:127, a blank line, and the seven
  part lines that ARE the demo's running order. DemoVT plays that script.

  Exit codes are a protocol with PSYCHO.EXE (docs/29-psycho-launcher.md):
    0  run the demo          (normal completion, and Previous Setup)
    1  end screen only       (the Exit menu option)
    2  quit silently         (not enough memory)

  TWO OF THE ORIGINAL'S DEFECTS ARE PRESERVED DELIBERATELY, and neither is to
  be fixed: this program is what the 1994 setup did, defects included.

  [re] TWO ORIGINAL DEFECTS ARE PRESERVED DELIBERATELY, per docs/31:
    - IsVGA computes its answer into AX inside the asm block and never
      assigns the function result, so the value returned is whatever sits
      at [BP-1] -- the high byte of a return segment pushed earlier, which
      is nonzero on any real machine. The VGA gate has passed by accident
      since 1994. Do not "fix" it: no machine exists where the fix would
      change behaviour, and the bytes would stop matching.
    - Failed detections print 'ByeBye' and Halt(0), which the launcher
      reads as run-the-demo-anyway.

  Original quirks kept: the DMA menu is titled 'Please Select your IRQ
  setting:', the port menu 'Please Select your Sampling rate:', and the
  'SB Pas 16' option writes the Sound Blaster Pro line.

  Directives are measured: $G+ (PUSH imm, PUSHA-era encodings, SMSW in
  Detect, IMUL r,r,imm in WriteStr) and $S+ (every routine calls the
  stack check) -- see docs/31, "Build flags".

  [re] DGROUP: no program globals; everything lives on the stack, laid out by
  the declaration orders below, which are the debug info's.
  =========================================================================== }

{$G+,S+}
program NEUR0;

uses
  Crt, Detect;

procedure YesNo;
var
  ch : Char;
begin
  Write('                            Hit ''Y'' or ''N''');
  repeat
    ch := UpCase(ReadKey);
  until ch in ['N', 'Y'];
  if ch = 'N' then
  begin
    WriteLn;
    WriteLn;
    WriteLn('Later, dudes!');
    Halt(0);
  end;
end;

{ Straight into text video memory: character byte, then attribute byte.
  X and Y are 1-based here the way the callers use them. }
procedure WriteStr(s : String; x, y, col : Byte);
var
  loop1 : Integer;
begin
  for loop1 := 1 to Length(s) do
  begin
    Mem[$B800:x * 2 + loop1 * 2 + y * 160 - 2] := Ord(s[loop1]);
    Mem[$B800:x * 2 + loop1 * 2 + y * 160 - 1] := col;
  end;
end;

procedure detected;
begin
  WriteStr('DETECTED :', 45, 18, 30);
  WriteStr('VGA Card      ', 50, 20, 7);
  WriteStr('386/486       ', 50, 21, 7);
  if IsProtMode then
    WriteStr('Protected mode', 50, 22, 7)
  else
    WriteStr('Real mode     ', 50, 22, 7);
end;

procedure ChooseCard;
var
  loop1, loop2 : Integer;
  opt          : array[1..7] of String;
  ch           : Char;
  forfile      : array[1..5] of String;
  f            : Text;
begin
  for loop1 := 1 to 5 do
    forfile[loop1] := '';

  for loop1 := 0 to 25 do
    for loop2 := 0 to 80 do
      WriteStr(#176, loop2, loop1, 5);
  opt[1] := '         Sound Blaster (Mono)          ';
  opt[2] := '       Sound Blaster Pro (Stereo)      ';
  opt[3] := '          Gravis UltraSound            ';
  opt[4] := '              SB Pas 16                ';
  opt[5] := '              No Music                 ';
  opt[6] := '           Previous Setup              ';
  opt[7] := '                Exit                   ';
  WriteStr('    Psycho Neurosis     by ASPHYXIA    ', 22, 5, 15);
  WriteLn;
  WriteStr('Please Select your Sound Card:', 27, 7, 11);
  for loop1 := 1 to 7 do
    WriteStr(opt[loop1], 22, loop1 + 8, 9);
  loop2 := 1;
  WriteStr(opt[loop2], 22, loop2 + 8, 30);
  detected;
  repeat
    ch := ReadKey;
    if ch = #0 then
    begin
      ch := ReadKey;
      case ch of
        'P' :
          begin
            WriteStr(opt[loop2], 22, loop2 + 8, 9);
            loop2 := loop2 + 1;
            if loop2 > 7 then loop2 := 1;
            WriteStr(opt[loop2], 22, loop2 + 8, 30);
          end;
        'H' :
          begin
            WriteStr(opt[loop2], 22, loop2 + 8, 9);
            loop2 := loop2 - 1;
            if loop2 < 1 then loop2 := 7;
            WriteStr(opt[loop2], 22, loop2 + 8, 30);
          end;
      end;
    end;
  until ch = #13;

  case loop2 of
    6 :
      begin
        ClrScr;
        TextColor(0);
        Halt(0);
      end;
    7 :
      begin
        ClrScr;
        TextColor(7);
        Halt(1);
      end;
  end;

  case loop2 of
    1 : forfile[2] := '     /d:DMA-SB-Mono';
    2 : forfile[2] := '     /d:DMA-SB-Stereo';
    3 : forfile[2] := '     /d:GUS';
    4 : forfile[2] := '     /d:DMA-SB-Stereo';
    5 : forfile[2] := '     /d:Silence';
  end;

  if loop2 <> 5 then
  begin
    for loop1 := 0 to 25 do
      for loop2 := 0 to 80 do
        WriteStr(#176, loop2, loop1, 5);
    opt[1] := '               IRQ 7                   ';
    opt[2] := '               IRQ 5                   ';
    WriteStr('    Psycho Neurosis     by ASPHYXIA    ', 22, 5, 15);
    WriteLn;
    WriteStr('Please Select your IRQ setting:', 27, 7, 11);
    for loop1 := 1 to 2 do
      WriteStr(opt[loop1], 22, loop1 + 8, 9);
    loop2 := 1;
    WriteStr(opt[loop2], 22, loop2 + 8, 30);
    detected;
    repeat
      ch := ReadKey;
      if ch = #0 then
      begin
        ch := ReadKey;
        case ch of
          'P' :
            begin
              WriteStr(opt[loop2], 22, loop2 + 8, 9);
              loop2 := loop2 + 1;
              if loop2 > 2 then loop2 := 1;
              WriteStr(opt[loop2], 22, loop2 + 8, 30);
            end;
          'H' :
            begin
              WriteStr(opt[loop2], 22, loop2 + 8, 9);
              loop2 := loop2 - 1;
              if loop2 < 1 then loop2 := 2;
              WriteStr(opt[loop2], 22, loop2 + 8, 30);
            end;
        end;
      end;
    until ch = #13;
    case loop2 of
      1 : forfile[4] := '     /irq:7';
      2 : forfile[4] := '     /irq:5';
    end;

    for loop1 := 0 to 25 do
      for loop2 := 0 to 80 do
        WriteStr(#176, loop2, loop1, 5);
    opt[1] := '               DMA 0                   ';
    opt[2] := '               DMA 1                   ';
    opt[3] := '               DMA 3                   ';
    opt[4] := '               DMA 5                   ';
    opt[5] := '               DMA 7                   ';
    WriteStr('    Psycho Neurosis     by ASPHYXIA    ', 22, 5, 15);
    WriteLn;
    WriteStr('Please Select your IRQ setting:', 27, 7, 11);
    for loop1 := 1 to 5 do
      WriteStr(opt[loop1], 22, loop1 + 8, 9);
    loop2 := 1;
    WriteStr(opt[loop2], 22, loop2 + 8, 30);
    detected;
    repeat
      ch := ReadKey;
      if ch = #0 then
      begin
        ch := ReadKey;
        case ch of
          'P' :
            begin
              WriteStr(opt[loop2], 22, loop2 + 8, 9);
              loop2 := loop2 + 1;
              if loop2 > 5 then loop2 := 1;
              WriteStr(opt[loop2], 22, loop2 + 8, 30);
            end;
          'H' :
            begin
              WriteStr(opt[loop2], 22, loop2 + 8, 9);
              loop2 := loop2 - 1;
              if loop2 < 1 then loop2 := 5;
              WriteStr(opt[loop2], 22, loop2 + 8, 30);
            end;
        end;
      end;
    until ch = #13;
    case loop2 of
      1 : forfile[5] := '     /dma:0';
      2 : forfile[5] := '     /dma:1';
      3 : forfile[5] := '     /dma:3';
      4 : forfile[5] := '     /dma:5';
      5 : forfile[5] := '     /dma:7';
    end;

    for loop1 := 0 to 25 do
      for loop2 := 0 to 80 do
        WriteStr(#176, loop2, loop1, 5);
    opt[1] := '               210 H                   ';
    opt[2] := '               220 H                   ';
    opt[3] := '               230 H                   ';
    opt[4] := '               240 H                   ';
    opt[5] := '               250 H                   ';
    opt[6] := '               260 H                   ';
    opt[7] := '               270 H                   ';
    WriteStr('    Psycho Neurosis     by ASPHYXIA    ', 22, 5, 15);
    WriteLn;
    WriteStr('Please Select your Sampling rate:', 27, 7, 11);
    for loop1 := 1 to 7 do
      WriteStr(opt[loop1], 22, loop1 + 8, 9);
    loop2 := 1;
    WriteStr(opt[loop2], 22, loop2 + 8, 30);
    detected;
    repeat
      ch := ReadKey;
      if ch = #0 then
      begin
        ch := ReadKey;
        case ch of
          'P' :
            begin
              WriteStr(opt[loop2], 22, loop2 + 8, 9);
              loop2 := loop2 + 1;
              if loop2 > 7 then loop2 := 1;
              WriteStr(opt[loop2], 22, loop2 + 8, 30);
            end;
          'H' :
            begin
              WriteStr(opt[loop2], 22, loop2 + 8, 9);
              loop2 := loop2 - 1;
              if loop2 < 1 then loop2 := 7;
              WriteStr(opt[loop2], 22, loop2 + 8, 30);
            end;
        end;
      end;
    until ch = #13;
    case loop2 of
      1 : forfile[3] := '     /port:$210';
      2 : forfile[3] := '     /port:$220';
      3 : forfile[3] := '     /port:$230';
      4 : forfile[3] := '     /port:$240';
      5 : forfile[3] := '     /port:$250';
      6 : forfile[3] := '     /port:$260';
      7 : forfile[3] := '     /port:$270';
    end;

    for loop1 := 0 to 25 do
      for loop2 := 0 to 80 do
        WriteStr(#176, loop2, loop1, 5);
    opt[1] := '               8000 Hz                 ';
    opt[2] := '              12000 Hz                 ';
    opt[3] := '              16000 Hz                 ';
    opt[4] := '              20000 Hz                 ';
    opt[5] := '              28000 Hz                 ';
    opt[6] := '              34000 Hz                 ';
    opt[7] := '              40000 Hz                 ';
    WriteStr('    Psycho Neurosis     by ASPHYXIA    ', 22, 5, 15);
    WriteLn;
    WriteStr('Please Select your Sampling rate:', 27, 7, 11);
    for loop1 := 1 to 7 do
      WriteStr(opt[loop1], 22, loop1 + 8, 9);
    loop2 := 1;
    WriteStr(opt[loop2], 22, loop2 + 8, 30);
    detected;
    repeat
      ch := ReadKey;
      if ch = #0 then
      begin
        ch := ReadKey;
        case ch of
          'P' :
            begin
              WriteStr(opt[loop2], 22, loop2 + 8, 9);
              loop2 := loop2 + 1;
              if loop2 > 7 then loop2 := 1;
              WriteStr(opt[loop2], 22, loop2 + 8, 30);
            end;
          'H' :
            begin
              WriteStr(opt[loop2], 22, loop2 + 8, 9);
              loop2 := loop2 - 1;
              if loop2 < 1 then loop2 := 7;
              WriteStr(opt[loop2], 22, loop2 + 8, 30);
            end;
        end;
      end;
    until ch = #13;
    case loop2 of
      1 : forfile[1] := '     /f:8000';
      2 : forfile[1] := '     /f:12000';
      3 : forfile[1] := '     /f:16000';
      4 : forfile[1] := '     /f:20000';
      5 : forfile[1] := '     /f:28000';
      6 : forfile[1] := '     /f:34000';
      7 : forfile[1] := '     /f:40000';
    end;
  end;

  Assign(f, 'neurosis.cfg');
  Rewrite(f);
  for loop1 := 1 to 5 do
    WriteLn(f, forfile[loop1]);
  WriteLn(f, '     /v:127');
  WriteLn(f);
  WriteLn(f, '         neurosis.001 /off:38528 /sh:neurosis.001');
  WriteLn(f, '     /   neurosis.002 /off:38832 /sh:neurosis.002');
  WriteLn(f, '     /   neurosis.003 /off:72240 /sh:neurosis.003');
  WriteLn(f, '     /   neurosis.004 /off:15008 /sh:neurosis.004');
  WriteLn(f, '     /   neurosis.005 /off:38496 /sh:neurosis.005');
  WriteLn(f, '     /   neurosis.006 /off:55984 /sh:neurosis.006');
  WriteLn(f, '     /   neurosis.007 /off:20112 /sh:neurosis.007');
  Close(f);
end;

{ The asm computes the answer into AX and the function result is never
  assigned -- see the header: preserved, not fixed. Equivalent Pascal of
  the INTENT (not of the behaviour):

    Regs.AX := $1A00; Intr($10, Regs);
    IsVGA := Regs.BL in [7..12]

  (and even the intent has a slip: the second JNC sends BL >= 13 to the
  "is VGA" side, so the test degenerates to BL >= 7). }
function IsVGA : Boolean;
begin
  asm
    XOR  BX, BX              { BL := 0 so an old BIOS leaves it 0        }
    MOV  AX, 1A00h           { VGA read display combination code         }
    INT  10h                 { BL = active display code on a VGA BIOS    }
    MOV  AX, 1               { assume yes                                }
    CMP  BL, 7               { 7 = VGA mono, 8 = VGA colour, ...         }
    JNC  @Done               { BL >= 7 -- call it a VGA                  }
    CMP  BL, 0Dh             { (intended 7..12; JNC makes it moot)       }
    JNC  @Done
    XOR  AX, AX              { BL < 7 -- no VGA                          }
  @Done:
  end;
end;

procedure Detections;
begin
  if not IsVGA then
  begin
    WriteLn('VGA not detected! ByeBye');
    Halt(0);
  end;
  if not Is386 then
  begin
    WriteLn('386 processor not detected! ByeBye');
    Halt(0);
  end;
  if IsProtMode then
  begin
    WriteLn;
    WriteLn('  Protected mode programs detected! Hit Y to continue anyway, or N to quit.');
    WriteLn('   Note that running this program in protected mode will make it sluggish. ');
    WriteLn('    Perhaps try rebooting without EMM386, QEMM, Windows, Desqview etc.     ');
    WriteLn;
    YesNo;
  end;
  WriteLn;
end;

begin
  if MemAvail + 28944 < 620000 then
  begin
    WriteLn;
    WriteLn('You do not have enough memory to run this demo.');
    WriteLn('You need : ', 620000 - MemAvail - 28944, ' extra bytes free');
    Halt(2);
  end;
  ClrScr;
  TextColor(7);
  asm
    MOV  AH, 1               { set cursor shape                          }
    MOV  CH, 0FFh            { start row off the glyph -- hides it       }
    MOV  CL, 9
    INT  10h
  end;
  Detections;
  ChooseCard;
  ClrScr;
  TextColor(0);
end.
