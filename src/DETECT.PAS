{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the Detect unit of NEUROSIS.000.

  Three hand-written detection probes, 49 bytes at segment 11ad, named by
  the appended debug info (docs/31-startup.md). The code is a TASM object
  (src/asm/DETECT.ASM) linked whole with $L, which is what the original
  did -- two measured tells: HasMouse is in the binary although nothing
  calls it (an object links whole; Pascal smart-links per routine and
  drops it), and XOR AX,AX is encoded 33 C0, TASM's operand order, where
  TP7's built-in assembler emits 31 C0.

  No initialisation section: the original's entry calls only Crt's.
  =========================================================================== }

unit Detect;

interface

function Is386      : Boolean;
function IsProtMode : Boolean;
function HasMouse   : Boolean;

implementation

{$L DETECT.OBJ}

{ @asm 000 11ad:0000 }
function Is386 : Boolean; external;

{ @asm 000 11ad:0014 }
function IsProtMode : Boolean; external;

{ @asm 000 11ad:001b }
function HasMouse : Boolean; external;

end.
