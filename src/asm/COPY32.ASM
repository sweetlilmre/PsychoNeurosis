; ============================================================================
; COPY32.ASM -- Psycho Neurosis (Asphyxia, 1994)
;
; A WHOLE 64,000-BYTE SCREEN COPIED AS SIXTEEN THOUSAND DWORDS -- one REP
; MOVSD where the shared VGA unit does REP MOVSW. That is half the bus cycles
; for the same bytes, and it is the only reason part 001 scene 5 carries its
; own copy routine instead of calling the shared one.
;
; WHY IT IS AN OBJECT MODULE RATHER THAN AN asm BLOCK. `REP MOVSD` is a 386
; instruction and Turbo Pascal 7's built-in assembler stops at the 286, so
; there is nowhere in the Pascal source it could be written.
;
;   Src   [BP+06h]   the segment to read
;   Dest  [BP+04h]   the segment to write
;
; Both are whole segments and the offsets are zero, so DI and SI are simply
; cleared. The routine preserves ES and DS because Turbo Pascal requires it.
;
; EQUIVALENT PASCAL, REFERENCE ONLY -- and it is not equivalent in the way that
; matters, which is the point: Move copies words, this copies dwords, and the
; whole reason the routine exists is the difference.
;
;       procedure Copy32(Src, Dest : Word);
;       begin
;         Move(Ptr(Src, 0)^, Ptr(Dest, 0)^, 64000)
;       end;
;
; [re] Part 001 scene 5's screen copy, at 12C5:0AC6. Sixty-four thousand bytes as
; SIXTEEN THOUSAND DWORDS -- one REP MOVSD instead of the VGA unit's REP MOVSW,
; which is half the bus cycles and is why the scene has its own copy rather
; than calling the shared one.
;
; [re] WHY THIS IS AN OBJECT MODULE. `REP MOVSD` is a 386 instruction and Turbo
; Pascal 7's built-in assembler stops at the 286, so it cannot be written in an
; asm block at all; and the POSITION agrees, which is the stronger argument.
; 12C5:0AC1 is the unit's initialisation stub -- PUSH BP / MOV BP,SP / LEAVE /
; RETF, five bytes -- and Turbo Pascal emits that LAST in a unit's code
; segment. This routine sits five bytes after it, so it cannot have come from
; the Pascal source. See the wiki's `Code past the initialisation section came
; from an object file`.
;
; [re] AND THE TWO PROLOGUE BYTES SAY TASM RATHER THAN THE COMPILER. 12C5:0AC7 is
; 8B EC for MOV BP,SP where Turbo Pascal's code generator emits 89 E5, and
; 12C5:0AD5 is 33 FF for XOR DI,DI where the compiler emits 31 FF. Both are the
; reg,r/m direction an assembler picks by default; the compiler picks the other.
; That pair distinguishes assembled code from compiled code in one glance and
; is worth more here than the instruction set, because a 16-bit routine would
; carry the same tell.
;
; ============================================================================

; .386 for REP MOVSD; USE16 keeps the object file 16-bit, since after .386
; TASM defaults segments to USE32 and TP7 answers those with "Error 47".
        .386

CODE    SEGMENT BYTE PUBLIC USE16 'CODE'
        ASSUME  CS:CODE

        PUBLIC  Copy32

Copy32  PROC    NEAR
        push    bp                      ; 12C5:0AC6
        mov     bp,sp                   ; 12C5:0AC7
        push    es                      ; 12C5:0AC9
        push    ds                      ; 12C5:0ACA
        mov     ax,[bp+04h]             ; 12C5:0ACB  Dest
        mov     es,ax                   ; 12C5:0ACE
        mov     ax,[bp+06h]             ; 12C5:0AD0  Src
        mov     ds,ax                   ; 12C5:0AD3
        xor     di,di                   ; 12C5:0AD5
        xor     si,si                   ; 12C5:0AD7
        mov     cx,3E80h                ; 12C5:0AD9  16,000 dwords = 64,000 bytes
        rep     movsd                   ; 12C5:0ADC  F3 66 A5
        pop     ds                      ; 12C5:0ADF
        pop     es                      ; 12C5:0AE0
        pop     bp                      ; 12C5:0AE1
        ret     4                       ; 12C5:0AE2
Copy32  ENDP

CODE    ENDS
        END
