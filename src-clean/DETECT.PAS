{ ===========================================================================
  Psycho Neurosis (Asphyxia, 1994) -- the Detect unit of NEUROSIS.000.

  The three questions the setup program asks about the machine before it
  will start the demo: is the processor a 386, is it already running in
  protected mode, and is a mouse driver installed. Each takes no arguments
  and answers Boolean.

  None of the three is written here. All are hand-written assembler and
  arrive as one whole TASM object -- src/asm/DETECT.ASM holds the code and
  its per-line documentation -- so this unit is only the Pascal declaration
  that makes them callable.

  HasMouse is part of the program although nothing in the demo calls it,
  and that is a consequence of how it arrives: an object file is linked
  WHOLE, where Turbo Pascal's own smart-linking drops a routine nobody
  references. So the mouse probe ships unused, and a reader looking for its
  caller will not find one.

  =========================================================================== }

unit Detect;

interface

function Is386      : Boolean;
function IsProtMode : Boolean;
function HasMouse   : Boolean;

implementation

{$L DETECT.OBJ}

{ True on a 386 or better. The demo needs one: its fixed-point maths is
  386 code, which is why that maths is a separate TASM object rather than
  inline assembler. }
function Is386 : Boolean; external;

{ True if the processor is already running in protected mode -- under a
  memory manager or a DOS box rather than on the bare machine. The demo
  drives the hardware directly and cannot run there. }
function IsProtMode : Boolean; external;

{ True if a mouse driver is installed. Nothing in the demo calls this; it
  ships because the object it belongs to is linked whole. See the unit
  header. }
function HasMouse : Boolean; external;

end.
