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
; ============================================================================

; .386 for REP MOVSD; USE16 keeps the object file 16-bit, since after .386
; TASM defaults segments to USE32 and TP7 answers those with "Error 47".
        .386

CODE    SEGMENT BYTE PUBLIC USE16 'CODE'
        ASSUME  CS:CODE

        PUBLIC  Copy32

Copy32  PROC    NEAR
        push    bp
        mov     bp,sp
        push    es
        push    ds
        mov     ax,[bp+04h]             ; Dest
        mov     es,ax
        mov     ax,[bp+06h]             ; Src
        mov     ds,ax
        xor     di,di
        xor     si,si
        mov     cx,3E80h                ; 16,000 dwords = 64,000 bytes
        rep     movsd
        pop     ds
        pop     es
        pop     bp
        ret     4
Copy32  ENDP

CODE    ENDS
        END
