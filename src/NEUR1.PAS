{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.001, the program itself.

  THIS IS THE MAIN BODY, NOT A UNIT CALLED BY A HARNESS. It replaces
  P1INTRO.PAS, which held this code as a unit with a RunIntro entry, and the
  generated TPART1.PAS that called it. Neither has a counterpart in the 1994
  binary -- the original's main body IS its program -- and carrying them put
  Turbo Pascal's runtime on a different paragraph.

  THE PROGRAM SEGMENT IS 288 BYTES, 1000:0000..1011, and every byte of it was
  read before this file was written. It was worth reading, because the two
  things recorded as blocking part 001's program were both WRONG, and the bytes
  say so in one pass:

    "the original's program calls no VirtScrAlloc"  -- it does, at 1000:003f,
      LCALL 0491:0006. That routine is PUSH BP / PUSH $FA00 / call the RTL's
      GetMem / store the pointer at DS:$AB54 / FillChar it to 0 -- which is
      VirtScrAlloc and nothing else. VGA:0000 beside it is three instructions,
      MOV AX,$13 / INT $10 / RETF, so it is SetMode13h.

    "it calls 1012:0798 for Scene1 where P1S1.PAS records 0678" -- it calls
      1012:0678, exactly as P1S1.PAS records. There is no 0798 in the segment.

  Both were readings of something else, and both cost weeks of the part being
  described as blocked. The lesson is the cheap one: 288 bytes is twenty minutes.

  ADDRESS MAP OF THE BODY

      1000:0000   the unit-initialisation chain, twelve far calls -- and it is
                  a FREE READING OF THE LINK ORDER, in reverse of the segment
                  order: System, DemoVT, Crt, VGA, FixMath, P1S5, P1Star, P1S4,
                  P1S3, P1S2, P1S1
      1000:003c   PUSH BP / MOV BP,SP -- a frame with no locals; both of the
                  body's variables are GLOBALS, at DS:$02E8 and DS:$02E9, and
                  they are BYTES: 1000:00cb is MOV BYTE PTR [$02E8],AL
      1000:003f   VirtScrAlloc      1491:0006
      1000:0044   SetMode13h        1491:0000
      1000:0049   MusicDetect       1532:0000
      1000:004e   MusicFunc3        1532:006a
      1000:0053   MusicCue          1532:0093
      1000:0058   MusicStart        1532:004e
      1000:005d   Scene1            1012:0678
      1000:0062   drain the keyboard, INLINE
      1000:0072   Scene2            1082:056f
      1000:0087   Scene3            10e3:0206
      1000:009c   Scene4            1107:0977
      1000:00b1   Scene5            12c5:0a89
      1000:00c6   the music fade
      1000:0106   VirtScrFree       1491:0033
      1000:010b   SetRGB            1491:0187
      1000:0119   the exit

  ALLOC BEFORE MODE, WHICH IS THE OTHER WAY ROUND FROM EVERY OTHER PART. Parts
  002, 003 and 004 all set mode 13h and then allocate; 1000:003f allocates and
  1000:0044 sets the mode. P1INTRO.PAS had it in the usual order and its own
  comment beside SetMode13h even said "1000:0044", which is the address of the
  call AFTER it. Do not tidy this.

  THE DRAIN IS INLINE AT ALL FIVE SITES, not a called procedure. 1000:0062 is
  LCALL Crt.KeyPressed / OR AL,AL / JE / LCALL Crt.ReadKey / JMP -- sixteen
  bytes where a call would be five, and parts 002 and 003 each taught this the
  expensive way. P1INTRO declared a FlushKeys deliberately, to stop VGA's copy
  being smart-linked in ahead of VGA's initialisation section; with the drain
  inline nothing anywhere references a FlushKeys, so VGA's is not linked either
  and that note's purpose is served without the procedure.

  SetRGB(7, 0, 0, 0) AND NOT SetRGB(0, 0, 0, 7). 1491:0187 is PUSH BP / MOV
  DX,$3C8 / MOV AL,[BP+$0C] / OUT / INC DX / then [BP+$0A], [BP+$08], [BP+$06]
  to $3C9, RETF 8 -- four byte parameters, and the FIRST one pushed sits at the
  DEEPEST slot, [BP+$0C], which is the DAC index. The original pushes 7, 0, 0,
  0, so it blacks out DAC entry 7. P1INTRO had the arguments reversed, which
  set entry 0 to a dim blue instead and is a visible difference on the last
  frame rather than a byte count.

  THE FADE READS GetVolume TWICE A TURN, exactly as part 003's does. 1000:00ce
  stores it into Vol, 1000:00dd passes Vol-1 to SetVolume, 1000:00e2 stores it
  AGAIN, and it is that second value 1000:00f1 tests. There is no test before
  the first turn, so it is repeat..until. Written as SetVolume(GetVolume - 1)
  with `until GetVolume = 0` the intermediate stores disappear and nothing
  matches.

  THERE IS NO SetTextMode: part 001 leaves the adapter in mode 13h for whatever
  PSYCHO.EXE ran next. RUNPART.BAT restores it with VIDMODE.
  =========================================================================== }

{$G+}   { 286, AND THE PROGRAM SEGMENT NEEDS IT AS MUCH AS ANY UNIT. Without it
          the body came out ten bytes over: 1000:00ea is PUSH $0A for Delay's
          argument and 1000:010b is four PUSH imm8 for SetRGB's, which are 286
          instructions, and the 8086 forms TP7 falls back on are MOV AX,imm /
          PUSH AX -- two bytes more each, five times over. The frame teardown
          goes the same way, LEAVE against POP BP. $G is per-file and a program
          is a file; nothing inherits it from the units. }

program Neur1;

{ THE USES CLAUSE IS THE LINK ORDER, REVERSED, and it is the harness's clause
  followed by P1Intro's. The units named first finish first in the depth-first
  walk and so land LAST in code: DemoVT (1532), Crt (14d0), VGA (1491). FixMath
  (1483) is NOT named -- nothing names it directly and the scene that needs it
  pulls it in there, which is where the original has it. Then the scenes in
  reverse of their segments, with P1Star between P1S5 and P1S4 exactly as the
  initialisation chain at 1000:0000 places it. }
{ AND THE SCENE ORDER IS BACKWARDS ON PURPOSE. Carried from P1INTRO.PAS, which
  this file replaces: on 25 Aug 2026 segpair.py measured the clause both ways,
  and in scene order SIX of the nine paired segments came out transposed --
  P1S5, P1S4, FixMath, P1S3, P1S2, P1S1 -- while as written below all nine
  match. The initialised data improved with it too, 420 differing bytes to 393.
  spans.py CANNOT TELL THESE APART, because it locates each segment by content;
  read segpair.py and dgimage.py for this, never the walk. }
uses DemoVT, Crt, VGA,
     P1S5, P1STAR, P1S4, P1S3, P1S2, P1S1;

var
  Saved : Byte;         { DS:$02E8 -- a GLOBAL, not a local, and a Byte }
  Vol   : Byte;         { DS:$02E9 }

{ 1000:003c }
begin
  VirtScrAlloc;                   { 1000:003f -> 1491:0006 }
  SetMode13h;                     { 1000:0044 -> 1491:0000 }

  MusicDetect;                    { 1000:0049 -> 1532:0000 }
  MusicFunc3;                     { 1000:004e -> 1532:006a }
  MusicCue;                       { 1000:0053 -> 1532:0093 }
  MusicStart;                     { 1000:0058 -> 1532:004e }

  Scene1;   while KeyPressed do ReadKey;   { 1000:005d, drain at 0062 }
  Scene2;   while KeyPressed do ReadKey;   { 1000:0072, drain at 0077 }
  Scene3;   while KeyPressed do ReadKey;   { 1000:0087, drain at 008c }
  Scene4;   while KeyPressed do ReadKey;   { 1000:009c, drain at 00a1 }
  Scene5;   while KeyPressed do ReadKey;   { 1000:00b1, drain at 00b6 }

  { 1000:00c6 -- ramp the volume down, stop, then put it back }
  Saved := GetVolume;             { 1000:00c6 }
  repeat
    Vol := GetVolume;             { 1000:00ce }
    SetVolume(Vol - 1);           { 1000:00dd }
    Vol := GetVolume;             { 1000:00e2 }
    Delay(10);                    { 1000:00ec }
  until Vol = 0;                  { 1000:00f1 }
  MusicStop;                      { 1000:00f8 -> 1532:005c }
  SetVolume(Saved);               { 1000:0101 -> 1532:00d8 }

  VirtScrFree;                    { 1000:0106 -> 1491:0033 }
  SetRGB(7, 0, 0, 0);             { 1000:010b -> 1491:0187 }

  { NO Halt(0), AND THAT IS THE WHOLE OF THE LAST SEVEN BYTES. `end.` already
    emits the exit -- LEAVE / XOR AX,AX / LCALL System:0116 at 1000:0118 -- so
    an explicit Halt(0) puts that sequence in TWICE, once for the statement and
    once for the end of the body. The original has one. Parts 002, 003, 004, 006
    and 007 each carry a Halt(0) with a comment pointing at the address of the
    single copy the original has, and they should be checked for the same. }
end.
