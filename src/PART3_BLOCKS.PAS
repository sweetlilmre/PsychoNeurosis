{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- NEUROSIS.003 "Techno Tick", Scene 5
  Reconstructed from NEUROSIS_003_fpu.exe, segment 11f3.

  A block dissolve. An image is revealed by repeatedly brightening 10x10
  pixel blocks in a precomputed order, then hidden again by running the same
  order backwards.

  Nothing is ever drawn: the pixels are already there. Every frame simply
  adds 1 to the pixel VALUES of 72 blocks, and because the palette is a ramp,
  higher values are brighter. Run it 91 times and the picture emerges.

  ADDRESS MAP
    Demo_Scene5  11f3:01ac      Blocks_Run  11f3:0017
  =========================================================================== }

{$G+}   { 286 instructions -- the block loops below use them }

unit Part3Blocks;

interface

procedure Scene5;

implementation

uses VGA, Crt;

const
  DataOfs   = $1A047D;    { NEUROSIS.DAT -- the very last region, 1,705,085 }
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

var
  Order : TOrder;         { held on the stack in the original -- 13K of it }

{ [transcribed] The palette ramp, read off the x87 stream at 11f3:0085:

      FILD  word ptr [BP-8]              ; I
      FLD   extended double ptr CS:[$0D] ; 0.2 exactly
      FMULP
      call  Round
      ADD   AX,$13                       ; + 19

  So Ramp(I) = Round(I / 5) + 19: it starts at 19 and reaches 63 -- the top of
  the VGA DAC -- at I = 220, one short of the end of the loop. }
function Ramp(I : Integer) : Byte;
begin
  Ramp := Round(I * 0.2) + 19;
end;

{ --------------------------------------------------------------------------
  Blocks_Run (11f3:0017)

  ASSETS  NEUROSIS.DAT $1A047D, 13,104 bytes:
            assets/part003/blocks_order.bin
          6,552 16-bit screen offsets: 91 frames x 8 x 9 blocks. The size
          being exactly 91*8*9*2 is what identifies the layout.
          See docs/11-part3-scene5-blocks.md.
  -------------------------------------------------------------------------- }
{ --------------------------------------------------------------------------
  11f3:0105 and 11f3:0178 -- the block read-modify-write.

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
procedure StepBlockUp(BlockAt : Word); assembler;
asm
  PUSH ES               { the original saves ES around the block             }
  MOV  AX, $A000
  MOV  ES, AX           { ES := video memory                                 }
  MOV  DI, BlockAt      { DI := this block's screen offset, from the table   }
  MOV  CX, 10           { CX counts the ten rows                             }
  MOV  DX, 10           { DX counts the ten pixels across a row              }
@@Pixel:
  MOV  AL, ES:[DI]      { read the pixel back out of video memory            }
  INC  AL               { one shade brighter along the ramp                  }
  STOSB                 { write it back; DI advances one pixel               }
  DEC  DX               { one pixel done                                     }
  JNZ  @@Pixel
  ADD  DI, $136         { 310 = the rest of the 320-byte row                 }
  MOV  DX, 10           { reload the across-count for the next row           }
  DEC  CX               { one row done                                       }
  JNZ  @@Pixel
  POP  ES               { restore ES                                         }
end;

procedure StepBlockDown(BlockAt : Word); assembler;
asm
  PUSH ES               { as above, but stepping the other way              }
  MOV  AX, $A000
  MOV  ES, AX           { ES := video memory                                 }
  MOV  DI, BlockAt      { DI := this block's screen offset                   }
  MOV  CX, 10           { ten rows                                           }
  MOV  DX, 10           { ten pixels across                                  }
@@Pixel:
  MOV  AL, ES:[DI]      { read the pixel back                                }
  DEC  AL               { one shade darker along the ramp                    }
  STOSB                 { write it back; DI advances                         }
  DEC  DX
  JNZ  @@Pixel
  ADD  DI, $136         { rest of the row                                    }
  MOV  DX, 10
  DEC  CX
  JNZ  @@Pixel
  POP  ES
end;

procedure Run;
var
  F          : file;
  I, C, R    : Integer;
  X, Y       : Integer;
  P          : Word;
begin
  Assign(F, 'neurosis.dat');
  Reset(F, 1);
  Seek(F, DataOfs);
  { 11f3:0048 clears the VISIBLE screen, not the virtual one -- the blocks are
    read back from and written to $A000 directly, so this is the surface the
    effect actually works on. ClearVirtual here left whatever was on screen in
    place and the brighten pass then stepped that instead of black. }
  ClearScreen(VGASeg, 0);

  { Blank everything, then lay a ramp over entries 1..221. The ramp is what
    turns "increment a pixel" into "brighten a pixel". }
  for I := 1 to 255 do SetRGB(I, 0, 0, 0);
  { SetRGB takes (B, G, R, Col), and the ramp is on BLUE only -- read off the
    x87 at 11f3:0072..00a7. See the note at the foot of this file. }
  for I := 1 to RampTop do SetRGB(I, 0, 0, Ramp(I));

  BlockRead(F, Order, DataSize);
  Close(F);

  { ---- reveal: walk the order forwards, adding 1 to each block ---- }
  for I := 0 to Frames - 1 do
    for C := 1 to BlocksX do
      for R := 1 to BlocksY do
      begin
        StepBlockUp(Order[I, C, R]);
      end;

  Delay(HoldMs);

  { ---- hide: the identical walk in reverse, subtracting 1 ---- }
  for I := Frames - 1 downto 0 do
    for C := BlocksX downto 1 do
      for R := BlocksY downto 1 do
      begin
        StepBlockDown(Order[I, C, R]);
      end;
end;

procedure Scene5;
begin
  Run;
end;

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

  RESOLVED -- THE PALETTE RAMP
  * Read off the patched x87 stream at 11f3:0072..00a7. The whole loop is:

        FILD  word ptr [BP-8]              ; I
        FLD   extended double ptr CS:[$0D] ; 0.2
        FMULP                              ; I * 0.2
        call  Round                        ; -> DX:AX
        ADD   AX,$13                       ; + 19

    and VGA_SetPalette (12f8:0064) takes its parameters in the order
    (Index, R, G, B) -- first pushed goes to port $3C8, the rest to $3C9 in
    that order. The loop pushes I, 0, 0, then the computed value, so the ramp
    is on BLUE:

        for I := 1 to 255 do SetPalette(I, 0, 0, 0);              (* blank *)
        for I := 1 to 221 do SetPalette(I, 0, 0, Round(I * 0.2) + 19);

    The constant at CS:$000D is exactly 0.2 (cd cc .. fc 3f), so the ramp is
    I/5 + 19: it starts at 19 and reaches 63 -- the top of the VGA DAC -- at
    I = 220, one short of the end. The whole scene is a single blue gradient.

  OPEN
  * Nothing outstanding.
  =========================================================================== }
