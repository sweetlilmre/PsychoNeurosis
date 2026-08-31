; ============================================================================
; STARMATH.ASM -- Psycho Neurosis (Asphyxia, 1994)
;
; TWO 32-BIT INTEGER HELPERS for part 003 scene 2's star field: multiply and
; divide, each done in three 386 instructions instead of a call into Turbo
; Pascal's 16-bit runtime routines. `DivLong` is why the scene needs a 386 at
; all -- it is on the projection path for every point of every frame.
;
; They are an object module because Turbo Pascal 7's built-in assembler stops
; at the 80286 and rejects `MOV EAX,[BP+8]` outright, so 386 code has to arrive
; through a linked object and `external`, exactly as DEMOMATH.ASM does for the
; fixed-point maths.
;
; NOTHING CALLS MulLong. It ships anyway, because an object file is linked
; WHOLE -- per module, not per procedure -- where an unused private Pascal
; routine would be smart-linked away. So a dead routine in an object survives
; and a dead routine in the Pascal does not, and a reader hunting for MulLong's
; caller will not find one.
;
; BOTH ARE 32-BIT, NOT FIXED POINT, and that is the difference from FixMul and
; FixDiv in DEMOMATH.ASM. Those two shift by 16 to keep a 16.16 result out of a
; 64-bit product. These reassemble the LOW 32 bits into DX:AX and throw the top
; away, which is a plain LongInt multiply and a plain LongInt divide -- done in
; three 386 instructions instead of a call into the runtime's 16-bit routines.
; Scene 2 needing a 386 at all is down to DivLong: it is on the projection path
; for every point of every frame.
; ============================================================================

; .386 for the instruction set; USE16 on the segment for a 16-bit object file.
; After .386 TASM defaults segments to USE32, which emits 32-bit OMF records
; and TP7 answers those with "Error 47: Invalid object file record".
        .386

CODE    SEGMENT BYTE PUBLIC USE16 'CODE'
        ASSUME  CS:CODE

        PUBLIC  MulLong, DivLong

; ----------------------------------------------------------------------------
; MulLong -- function MulLong(A, B : LongInt) : LongInt;
;
; Multiply two 32-bit integers. Plain LongInt arithmetic -- NOT the 16.16 fixed
; point of DEMOMATH.ASM's FixMul, which is the easy mistake to make when
; reading the two files together.
;
;   A   [BP+08h]    B   [BP+04h]
;
; EQUIVALENT PASCAL, REFERENCE ONLY -- and here the Pascal really is equivalent.
; It is replaced only because Turbo Pascal compiles it to a far call into the
; runtime's 16-bit multiply, where this is three 386 instructions:
;
;       function MulLong(A, B : LongInt) : LongInt;
;       begin
;         MulLong := A * B
;       end;
;
; THE RESULT IS PUT BACK TOGETHER, not shifted. IMUL leaves the full 64-bit
; product in EDX:EAX and Turbo Pascal returns a LongInt in DX and AX as two
; separate 16-bit registers, so the low 32 bits have to be split across them:
; AX already holds bits 0..15, and copying EAX into EDX and shifting it right
; by 16 puts bits 16..31 into DX. The top half of the product is discarded --
; this is a 32-bit multiply, not the 16.16 one in DEMOMATH.ASM.
; ----------------------------------------------------------------------------
MulLong PROC    NEAR
        push    bp
        mov     bp,sp
        mov     eax,[bp+08h]            ; A
        mov     edx,[bp+04h]            ; B
        imul    edx                     ; EDX:EAX := A * B
        mov     edx,eax
        shr     edx,16                  ; DX := bits 16..31
        pop     bp
        ret     8
MulLong ENDP

; ----------------------------------------------------------------------------
; DivLong -- function DivLong(A, B : LongInt) : LongInt;
;
; Divide one 32-bit integer by another, and THIS is the routine the scene
; needs a 386 for: it sits on the projection path for every point of every
; frame, where a runtime call would cost far more than the divide.
;
;   A   [BP+08h]    B   [BP+04h]
;
; EQUIVALENT PASCAL, REFERENCE ONLY:
;
;       function DivLong(A, B : LongInt) : LongInt;
;       begin
;         DivLong := A div B
;       end;
;
; ESI IS NOT SAVED. The divisor is loaded into it and the routine returns with
; it clobbered, which is legal for Turbo Pascal -- SI is not one of the
; registers a called routine must preserve -- and is why the divisor is not
; simply divided from memory. Kept as written.
;
; CDQ AFTER the ESI load, not before: the sign extension is of EAX, and loading
; ESI does not touch it. The 66h-prefixed CWD in the original IS CDQ.
; ----------------------------------------------------------------------------
DivLong PROC    NEAR
        push    bp
        mov     bp,sp
        mov     eax,[bp+08h]            ; A
        mov     esi,[bp+04h]            ; B
        cdq                             ; EDX:EAX := A sign-extended
        idiv    esi                     ; EAX := A div B
        mov     edx,eax
        shr     edx,16                  ; DX := bits 16..31
        pop     bp
        ret     8
DivLong ENDP

CODE    ENDS
        END
