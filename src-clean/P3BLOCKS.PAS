{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 5
  Reconstructed from NEUROSIS_003_fpu.exe, segment 11f3.

  A block dissolve. An image is revealed by repeatedly brightening 10x10
  pixel blocks in a precomputed order, then hidden again by running the same
  order backwards.

  Nothing is ever drawn: the pixels are already there. Every frame simply
  adds 1 to the pixel VALUES of 72 blocks, and because the palette is a ramp,
  higher values are brighter. Run it 91 times and the picture emerges. }

{$G+}   { 286 instructions -- the block loops below use them }
{ 80x87 code on: the palette ramp is computed in floating point. }
{$N+}

unit P3Blocks;
{$I-}   { no I/O check: the original goes straight on after each file
          call, with no near CALL to the RTL's check routine. }

interface

procedure Scene5;

implementation

uses VGA, Crt;

{ Where each asset sits inside NEUROSIS.DAT. }
{$I gen/DATOFS.INC}

const
  DataOfs   = DAT_P3_BLKORDER;   { $1A047D -- NEUROSIS.DAT -- the very last region, 1,705,085 }
  DataSize  = 13104;

  Frames    = 91;         { 0..$5A }
  BlocksX   = 8;          { inner loop 1..8  }
  BlocksY   = 9;          { inner loop 1..9  }
  BlockW    = 10;
  BlockH    = 10;
  RowStride = 320;

  { 91 * 8 * 9 * 2 = 13104 -- exactly the file read. Each entry is the screen
    offset of one 10x10 block. }
  Entries   = Frames * BlocksX * BlocksY;

  RampTop   = $DD;        { 221 -- palette entries 1..221 get the ramp }
  HoldMs    = 1000;

type
  { [frame][col][row] -- strides $90, $12, 2 bytes, straight from the
    address arithmetic in the original. }
  TOrder = array[0..Frames - 1, 1..BlocksX, 1..BlocksY] of Word;


{ --------------------------------------------------------------------------
  Blocks_Run

  ASSETS  NEUROSIS.DAT $1A047D, 13,104 bytes:
            assets/part003/BLKORDER.BIN
          6,552 16-bit screen offsets: 91 frames x 8 x 9 blocks. The size
          being exactly 91*8*9*2 is what identifies the layout.
          See docs/11-part3-scene5-blocks.md.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
 -- the block read-modify-write.

  Blocks_Run itself is compiled Pascal, but the innermost loop is hand
  assembler embedded in it: ten rows of ten pixels, each read back from video
  memory, stepped by one and written out again. Because the palette is a ramp
  over entries 1..221, "add one to the pixel" IS "make it one shade brighter",
  which is the whole effect. Subtracting one on the way out reverses it.

  $136 is 310 = 320 - 10, the rest of the screen row after ten pixels.

  EQUIVALENT PASCAL, for reference -- the assembler below is what runs:

      P := BlockAt;
      for Y := 1 to 10 do
      begin
        for X := 1 to 10 do
        begin
          Inc(Mem[$A000 : P]);      -- or Dec, for StepBlockDown
          Inc(P);
        end;
        Inc(P, 310);
      end;
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  STEPPING A BLOCK IS NOT A PROCEDURE IN THE ORIGINAL. }
procedure Run;
var
  {    AND A SECOND FILE RECORD, unopened -- the 128 bytes between the table and
    F. That is the FIFTH routine in this target to declare a file it never
    touches, and the size is exact rather than inferred. What those bytes are
    is not measurable from here: 128 is also a buffer or a String[127]. A file
    is what the rest of the corpus says. }
  X, Y       : Integer;                 { never read }
  BlockAt    : Word;
  I, C, R    : Integer;
  { ON THE STACK, and the original's is too -- ENTER $343C spends it there.
    As a unit-level var this was 13,104 bytes of DGROUP that the original
    never spends, and it is what took the data segment over 64K once the six
    shape slots were carved: TP7 stops with Error 49, which the build did not
    report. }
  Order      : TOrder;
  Unread     : file;                    { 128 bytes nothing references }
  F          : file;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  { clears the VISIBLE screen, not the virtual one -- the blocks are
    read back from and written to $A000 directly, so this is the surface the
    effect actually works on. ClearVirtual here left whatever was on screen in
    place and the brighten pass then stepped that instead of black. }
  ClearScreen(VGASeg, 0);

  { Blank everything, then lay a ramp over entries 1..221. The ramp is what
    turns "increment a pixel" into "brighten a pixel". }
  for I := 1 to 255 do SetRGB(I, 0, 0, 0);
  for I := 1 to RampTop do SetRGB(I, 0, 0, Round(I * 0.2) + 19);

  BlockRead(F, Order, DataSize);
  Close(F);

  { ---- reveal: walk the order forwards, adding 1 to each block ---- }
  for I := 0 to Frames - 1 do
    for C := 1 to BlocksX do
      for R := 1 to BlocksY do
      begin
        BlockAt := Order[I, C, R];
        asm
          PUSH ES               { the original saves ES around it }
          MOV  AX, $A000        { video memory                                 }
          MOV  ES, AX           { ES := video memory                           }
          MOV  DI, BlockAt      { this block's screen offset                   }
          MOV  CX, 10           { CX counts the ten rows                       }
        @@Row:                  { the row loop comes back to this label, so    }
          MOV  DX, 10           {    here: there is no second MOV DX further   }
        @@Pixel:                {   the block is drawn downwards               }
          MOV  AL, ES:[DI]      { read the pixel back out of video memory      }
          INC  AL               { one shade brighter along the ramp            }
          STOSB                 { write it back; DI advances one pixel         }
          DEC  DX               { one pixel done                               }
          JNZ  @@Pixel          { across until the row is finished             }
          ADD  DI, $136         { 310 = the rest of the 320-byte row           }
          DEC  CX               { one row done                                 }
          JNZ  @@Row            { down until all ten rows are done             }
          POP  ES               { restore ES                                   }
        end;
      end;

  Delay(HoldMs);

  { ---- hide: the identical walk in reverse, subtracting 1 ---- }
  for I := Frames - 1 downto 0 do
    for C := BlocksX downto 1 do
      for R := BlocksY downto 1 do
      begin
        BlockAt := Order[I, C, R];
        asm
          PUSH ES               { as above, stepping the other way }
          MOV  AX, $A000        { video memory                                 }
          MOV  ES, AX           { ES := video memory                           }
          MOV  DI, BlockAt      { this block's screen offset                   }
          MOV  CX, 10           { ten rows                                     }
        @@Row:                  { the row loop's target                        }
          MOV  DX, 10           { ten pixels across                            }
        @@Pixel:                { the pixel loop's                             }
          MOV  AL, ES:[DI]      { read the pixel back                          }
          DEC  AL               { one shade darker along the ramp              }
          STOSB                 { write it back; DI advances                   }
          DEC  DX               { one pixel done                               }
          JNZ  @@Pixel          { across until the row is finished             }
          ADD  DI, $136         { rest of the row                              }
          DEC  CX               { one row done                                 }
          JNZ  @@Row            { down until all ten rows are done             }
          POP  ES               { restore ES                                   }
        end;
      end;
end;

procedure Scene5;
begin
  Run;
end;

begin
end.

{ ===========================================================================
  NOTES

  * The whole effect is arithmetic on pixel values against a ramp palette --
    no blitting, no source image copy, no per-frame clear.
  * The reverse pass is an exact mirror: same table, all three loops running
    backwards, Dec instead of Inc. That guarantees the screen returns to its
    starting state with no accumulated error.
  * 6,552 block positions x 100 pixels = 655,200 increments over a 64,000
    pixel screen, so an average pixel is touched about ten times -- the
    brightness build-up is gradual rather than a hard on/off reveal.

  RESOLVED -- WHAT BLOCKS_RUN ACTUALLY DOES
  * The scene CLEARS the virtual screen first, so nothing is inherited from
    the previous scene -- the image is built here, by arithmetic on pixel
    values rather than by drawing.
  * The effect is 72 blocks of 10x10 pixels (8 x 9, screen stride $140), whose
    addresses come from a precomputed pointer table indexed [step][col][row]
    with strides $90, $12 and 2.
  * 91 steps (0..90) each ADD 1 to every pixel of every block, in row-major
    order; then a Crt_Delay(1000); then 91 steps each SUBTRACT 1, walking the
    three loops backwards. So the picture ramps up through the palette and
    back down again, and the palette ramp is what turns a pixel COUNT into a
    colour. The image is literally painted by counting.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
