; ============================================================================
; STARMATH.ASM -- Psycho Neurosis (Asphyxia, 1994)
;
; Part 003 scene 2's two 386 long-integer helpers, at 10B8:07DB and 10B8:07F4.
; Transcribed instruction for instruction.
;
; WHY THIS IS AN OBJECT MODULE AND NOT AN asm BLOCK, and the evidence is the
; POSITION rather than the instructions. Turbo Pascal 7's built-in assembler
; stops at the 80286 -- it rejects MOV EAX,[BP+8] outright -- so 386 code has
; to arrive through {$L file.OBJ} and `external`, exactly as DEMOMATH.ASM does
; for the fixed-point maths. But the placement is what proves it here: both
; routines sit AFTER the unit's initialisation section, which ends at 10B8:07DA.
; Turbo Pascal emits a unit's initialisation code last, and nothing can be
; declared after it -- so code beyond it did not come from the Pascal source at
; all. A linked object's code is appended to the unit's segment, which is the
; only way to be there.
;
; AND IT EXPLAINS WHY MulLong SURVIVES UNCALLED. Nothing in part 003 calls it:
; the four call sites in segment 10B8 all go to DivLong, and no far call to
; either address appears anywhere in the image. An unused private Pascal
; routine is smart-linked away; an external OBJ is linked WHOLE, per module and
; not per procedure. So a dead routine in the object file ships, and one in the
; Pascal does not. Part 005 scene 3's source records the same rule from the
; other direction.
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
;   A   [BP+08h]    B   [BP+04h]
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
;   A   [BP+08h]    B   [BP+04h]
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
