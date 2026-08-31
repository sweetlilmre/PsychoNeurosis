; ============================================================================
; DETECT.ASM -- Psycho Neurosis (Asphyxia, 1994), NEUROSIS.000's Detect unit.
;
; THE THREE QUESTIONS THE SETUP PROGRAM ASKS ABOUT THE MACHINE before it will
; start the demo: is the processor a 386, is it already in protected mode, and
; is a mouse driver installed. Each answers Boolean and takes no arguments.
;
; They are here rather than in DETECT.PAS because none of them can be written
; in Pascal at all -- one reads FLAGS, one reads the machine status word, and
; one reads the interrupt vector table. The language has no name for any of
; those.
;
; The NOPs are written out and every forward jump is SHORT, per the
; DEMOMATH.ASM precedent, so the layout is deterministic rather than a
; function of the assembler's pass count.
;
; [re] Transcribed instruction for instruction from bin/NEUROSIS.000, segment
; 11ad, 49 bytes. Assembled by TASM and linked with {$L DETECT.OBJ} from
; DETECT.PAS, which is what the original did. Two tells, both measured:
;   * HasMouse is in the binary although nothing calls it -- TP7 links an
;     object WHOLE, while a unit compiled from Pascal is smart-linked per
;     routine and drops it (our first build proved that by losing it).
;   * XOR AX,AX is encoded 33 C0 -- TASM's operand order. TP7's built-in
;     assembler emits 31 C0 for the same mnemonic.
;
; ============================================================================

        .286P                           ; SMSW is a privileged-class encoding

CODE    SEGMENT BYTE PUBLIC 'CODE'
        ASSUME  CS:CODE

        PUBLIC  Is386, IsProtMode, HasMouse

; ----------------------------------------------------------------------------
; function Is386 : Boolean;
; [re] 11ad:0000 .. 0013
;
; True on a 386 or better, and the demo needs one: its fixed-point maths is
; 386 code. Written by trying to set FLAGS bits an older processor refuses to
; hold, which is the only way to ask before CPUID existed.
;
; Equivalent Pascal, reference only -- it cannot BE Pascal, because FLAGS
; has no name in the language:
;
;     Is386 := try to store 7000h into FLAGS bits 12..14 and read it back;
;     an 8086 forces the bits to 1, a 286 in real mode forces them to 0,
;     only a 386+ keeps what was written.
; ----------------------------------------------------------------------------
Is386   PROC FAR
        pushf                           ; keep the caller's flags
        mov     ax, 7000h               ; NT | IOPL -- bits 12..14
        push    ax
        popf                            ; try to load them into FLAGS
        pushf
        pop     ax                      ; read back what stuck
        and     ax, 7000h               ; 286 real mode reads back zero
        jz      short @@not386          ; nothing stuck -- not a 386
        nop                             ; the original's jump padding
        nop
        mov     ax, 1                   ; 386 or better
@@not386:
        popf                            ; caller's flags back
        retf
Is386   ENDP

; ----------------------------------------------------------------------------
; function IsProtMode : Boolean;
; [re] 11ad:0014 .. 001a
;
; True if the processor is already in protected mode -- under a memory manager
; or in a DOS box rather than on the bare machine. The demo drives the hardware
; directly and cannot run there.
;
; Equivalent Pascal, reference only:  the machine status word's bit 0 is
; the protected-mode enable, and SMSW (286+) is its only reader here.
; ----------------------------------------------------------------------------
IsProtMode PROC FAR
        smsw    ax                      ; machine status word
        and     ax, 1                   ; bit 0 = protected mode enable
        retf
IsProtMode ENDP

; ----------------------------------------------------------------------------
; function HasMouse : Boolean;
; [re] 11ad:001b .. 0030
;
; True if a mouse driver is installed. NOTHING IN THE DEMO CALLS THIS: it ships
; because an object file is linked whole, where Turbo Pascal's own smart-linking
; would drop a routine nobody references. A reader looking for its caller will
; not find one.
;
; Equivalent Pascal, reference only:
;
;     if the INT 33h vector -- segment 0, offset 00CCh, because 33h * 4 is CCh
;     -- is null then HasMouse := False
;     else issue INT 33h AX=0 -- a driver answers with AX = FFFFh.
;
; The vector check must come first: INT 33h with no handler is a jump
; into nothing, not a False.
; ----------------------------------------------------------------------------
HasMouse PROC FAR
        xor     ax, ax
        mov     es, ax                  ; segment 0 -- the vector table
        mov     ax, es:[00CCh]          ; INT 33h vector, offset word
        or      ax, es:[00CEh]          ; or in the segment word
        jz      short @@nomouse         ; null vector -- no driver
        nop                             ; the original's jump padding
        nop
        xor     ax, ax
        int     33h                     ; mouse reset: AX = FFFFh if present
@@nomouse:
        retf
HasMouse ENDP

CODE    ENDS
        END
