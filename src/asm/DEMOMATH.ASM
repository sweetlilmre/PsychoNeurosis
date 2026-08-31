; ============================================================================
; DEMOMATH.ASM -- Psycho Neurosis (Asphyxia, 1994)
;
; THE DEMO'S 3-D MATHS, and every 3-D scene goes through this file: multiply,
; divide, sine and cosine, rotate a point about three axes, and project one
; onto the screen. Five routines and one table, all 386, all 16.16 fixed point.
;
; It is assembled once and linked into three separate units, so parts 001, 002
; and 005 each end up carrying their own copy of the code and of the table.
;
; [re] The three 386 fixed-point maths routines the demo's 3-D scenes share, and
; the cosine table they read. Transcribed instruction for instruction from the
; binaries; this file is assembled once and linked into three units with
; {$L DEMOMATH.OBJ}, which is what the original does -- the same code appears
; three times, once per unit's code segment:
;     part 001 scene 4   1107:1804  SinCos   1107:18B6  RotatePoint
;                        1107:1A04  Project  table at CS:$09F0
;     part 001 scene 5   12C5:192D  SinCos   12C5:19DF  RotatePoint
;                        12C5:1B2D  Project  table at CS:$0B19
;     part 002 scene 2   108B:342F  SinCos   108B:34E1  RotatePoint
;                        108B:362F  Project  table at CS:$261B
;
; WHY THIS IS A .ASM AND NOT AN asm BLOCK. Turbo Pascal 7's built-in assembler
; stops at the 80286 -- {$G+} is documented as "Generate 80286 Code Switch",
; and the shipped help file has no mention of the 386, of EAX, or of SHRD. It
; rejects `MOV EAX, EBX` outright. So 386 code has to come in through
; {$L file.OBJ} and `external`, which is TP7's documented route for exactly
; this.
;
; [re] and the binary shows that is what the original did:
;   * 1107:180E, 1828, 1830 and 186E are NOP NOP immediately after a forward
;     conditional jump. That is TASM's jump-sizing padding -- it reserves four
;     bytes for a Jcc near (a .386 encoding) and pads when the short form
;     turns out to fit. A hand-written asm block never produces it.
;   * 1107:1A66 `ADD EBX,8000h` is seven bytes, a real 32-bit immediate. A
;     hand-prefixed `DB 66h` in front of a 16-bit ADD would emit five and the
;     processor would swallow the next two bytes as part of the immediate.
;
; THE NUMBER FORMAT is 16.16 fixed point throughout: one signed 32-bit word
; holding a whole part and a 1/65536 fraction. The multiply is the reason none
; of this can be Pascal. Every product below is
;
;       IMUL dword    -- EDX:EAX := a * b, a full 64-bit result
;       SHR  EAX,16   -- take the top half of the low word...
;       SHL  EDX,16   -- ...and the bottom half of the high word...
;       OR   EAX,EDX  -- ...and glue them into the MIDDLE 32 bits
;
; which is (a * b) / 65536 without ever losing the high bits. A Turbo Pascal
; LongInt multiply overflows long before it gets there.
;
; SHARED SYMBOLS. Every unit that links this object must declare these before
; the {$L} directive, with these exact names:
;
;       MCos1, MSin1, MCos2, MSin2, MCos3, MSin3 : LongInt   16.16 sin/cos
;       MScale                                   : LongInt   16.16 projection
;       MViewW, MViewH                           : Word      FULL view size
;
; MViewW and MViewH are halved inside Project, so they are the whole width and
; height, not the centre. Part 001 scene 5 really does set MViewH to 0 -- see
; the note there; it is not a mistake to be tidied away.
;
; THE NOPs IN SinCos ARE NOT DEAD SPACE and must not be tidied away. They are
; forward-jump padding, and every jump in this file is written `short`
; explicitly for the same reason: an assembler that sizes its own jumps decides
; where the padding lands, which makes the emitted bytes a function of how many
; passes it takes rather than of what this file says. Written out by hand, the
; output is the same every time.
;
; [re] THE NOPs IN SinCos ARE DELIBERATE. They are the 1994 assembler's forward-jump
; padding: it reserved the near form of a forward branch and, on finding the
; short form fitted, filled the slack rather than moving anything. TASM 4.1
; pads in the same places but not in all the same ones, so every jump here is
; written `short` explicitly and the padding is written out as `nop`. That
; makes the output deterministic instead of a function of the assembler's pass
; count -- and it is what makes the three routines come out byte for byte
; identical to the original, which tools/asmverify.py checks.
;
; ============================================================================

; .386 enables the instruction set. USE16 on the segment is what keeps the
; object file 16-bit: after .386 TASM defaults segments to USE32, which emits
; 32-bit OMF records, and TP7 answers those with "Error 47: Invalid object
; file record". The code is 386 instructions inside a 16-bit segment, which is
; exactly what the original is.
        .386

; The shared variables have to be declared INSIDE a DATA segment that is part
; of DGROUP, and DS has to be ASSUMEd to it. Declaring them at the top level
; instead leaves TASM thinking they live in CODE, and it puts a CS: override
; in front of every reference -- five bytes where the original has four, and
; reading the cosine table's segment instead of the data segment.
DATA    SEGMENT WORD PUBLIC USE16 'DATA'
        EXTRN   MCos1:DWORD, MSin1:DWORD
        EXTRN   MCos2:DWORD, MSin2:DWORD
        EXTRN   MCos3:DWORD, MSin3:DWORD
        EXTRN   MScale:DWORD
        EXTRN   MViewW:WORD, MViewH:WORD
DATA    ENDS

DGROUP  GROUP   DATA

CODE    SEGMENT BYTE PUBLIC USE16 'CODE'
        ASSUME  CS:CODE, DS:DGROUP

        PUBLIC  FixMul, FixDiv, SinCos, RotatePoint, Project

; ----------------------------------------------------------------------------
; FixMul -- function FixMul(A, B : LongInt) : LongInt;
;
; Multiply two 16.16 fixed-point numbers. This is the operation the whole file
; exists for: a 16.16 product needs the MIDDLE 32 bits of a 64-bit result, and
; Turbo Pascal's own LongInt multiply throws the top half away long before it
; gets there.
;
;   A   [BP+08h]    B   [BP+04h]        both 16.16
;
; EQUIVALENT PASCAL, REFERENCE ONLY -- this is not what is assembled, and it
; cannot be: no Pascal expression reaches a 64-bit intermediate here.
;
;       function FixMul(A, B : LongInt) : LongInt;
;       begin
;         FixMul := (Int64(A) * B) shr 16     { the middle 32 bits }
;       end;
;
; NO SHIFT PAIR IS NEEDED. IMUL leaves the 64-bit product in EDX:EAX, and Turbo
; Pascal returns a LongInt in DX:AX -- two SEPARATE registers. So shifting EAX
; alone by 16 puts product bits 16..31 in AX, and DX already holds bits 32..47
; from EDX. The 16.16 result assembles itself.
; ----------------------------------------------------------------------------
FixMul  PROC    NEAR
        push    bp                      ; 1102:0391
        mov     bp,sp                   ; 1102:0392
        mov     eax,[bp+08h]            ; 1102:0394  A
        imul    dword ptr [bp+04h]      ; 1102:0398  EDX:EAX := A * B
        shr     eax,16                  ; 1102:039C  AX := bits 16..31
        pop     bp                      ; 1102:03A0    and DX is bits 32..47
        ret     8                       ; 1102:03A1
FixMul  ENDP

; EVERY ROUTINE HERE STARTS ON AN EVEN OFFSET, and `EVEN` before each is what
; guarantees it: it emits one NOP where the offset is odd and nothing where it
; is already even, so the alignment is stated once and the assembler works out
; whether it costs anything. FixMul is 19 bytes, which is the odd one.
;
; [re] ONE BYTE OF PADDING, AND IT IS IN THE ORIGINAL. FixMul is 19 bytes, so FixDiv
; would start at an ODD offset in this object -- and every one of the three
; binaries this file is linked into has a NOP there instead: 12c5:0af8, and the
; same byte in part 001 scene 4 and part 002 scene 2. EVEN emits exactly that
; 90 and nothing when the offset is already even, which is why it is written as
; an alignment directive rather than a bare `nop`.
;
; [re] IT WAS WORTH 3,391 BYTES. Without it every byte of part 001 scene 5 from
; 12c5:0af8 to the end of the segment was one place out -- the whole
; hand-assembler tail and all three external routines -- and the same one-byte
; drift showed in scene 4 and in part 002 as a row progseg labels
; "past the init -- .OBJ". A coverage walk cannot see it, because it locates
; each segment by content and one byte of slide still matches almost everything.
;
        EVEN

; ----------------------------------------------------------------------------
; FixDiv -- function FixDiv(A, B : LongInt) : LongInt;
;
; Divide one 16.16 fixed-point number by another. The difficulty is the mirror
; of FixMul's: the dividend has to be widened BEFORE the divide, or the
; quotient comes out whole and the fraction is gone.
;
;   A   [BP+08h]    B   [BP+04h]        both 16.16
;
; EQUIVALENT PASCAL, REFERENCE ONLY:
;
;       function FixDiv(A, B : LongInt) : LongInt;
;       begin
;         FixDiv := (Int64(A) shl 16) div B
;       end;
;
; A is widened to 48 bits in EDX:EAX by SHRD/SAR -- that is A shifted left 16
; without losing the top -- divided, and the quotient put back together with
; SHLD so that DX:AX is the 16.16 answer.
; ----------------------------------------------------------------------------
FixDiv  PROC    NEAR
        push    bp                      ; 1102:03A5
        mov     bp,sp                   ; 1102:03A6
        mov     edx,[bp+08h]            ; 1102:03A8  A
        xor     eax,eax                 ; 1102:03AC
        shrd    eax,edx,16              ; 1102:03AF  EDX:EAX := A shl 16
        sar     edx,16                  ; 1102:03B4    sign-correct the top
        idiv    dword ptr [bp+04h]      ; 1102:03B8
        shld    edx,eax,16              ; 1102:03BC  DX := quotient bits 16..31
        pop     bp                      ; 1102:03C1
        ret     8                       ; 1102:03C2
FixDiv  ENDP

        INCLUDE COSTAB.INC

; ----------------------------------------------------------------------------
; SinCos -- procedure SinCos(A : Integer; var C, S : LongInt);
;
; Sine and cosine of one angle, both from a single quarter-turn table. Storing
; a whole turn would cost four times the space for no new information, so the
; quadrant is worked out first and the one quadrant read forwards or backwards
; with the signs adjusted.
;
;   A       [BP+0Ch]    the angle in TENTHS of a degree
;   var C   [BP+08h]    receives the cosine, 16.16
;   var S   [BP+04h]    receives the sine
;
; EQUIVALENT PASCAL, REFERENCE ONLY -- the quadrant table below is the real
; documentation; this says only what shape the routine has:
;
;       procedure SinCos(A : Integer; var C, S : LongInt);
;       begin
;         while A <    0 do Inc(A, 3600);      { wrap into one turn }
;         while A > 3600 do Dec(A, 3600);
;         case A div 900 of                    { pick the quadrant, then }
;           ...                                {   read CosTab forwards  }
;         end                                  {   or backwards, signed  }
;       end;
;
; The angle is first wrapped into 0..3600 by repeated add/subtract rather than
; a modulo -- exact here because callers never step by more than a few degrees
; a frame. Then one of four quadrant cases reads the single cosine quadrant
; forwards or backwards with the signs flipped:
;
;       0..900      C :=  T[a]           S :=  T[900-a]
;       901..1800   C := -T[1800-a]      S :=  T[a-900]
;       1801..2700  C := -T[a-1800]      S := -T[2700-a]
;       2701..3600  C :=  T[3600-a]      S := -T[a-2700]
;
; T[900-a] falls out of `NEG BX` plus a displacement of 3600 = 900*4, so the
; backwards read costs one instruction. The FIRST var parameter takes the
; COSINE -- checked against RotatePoint below, which needs it in the cosine
; position for the matrix to come out orthogonal.
; ----------------------------------------------------------------------------
; [re] EVEN before this one too -- see the note above FixDiv. Every routine in this
; object starts at an EVEN offset in the original: taking FixMul's address as
; the segment base, FixDiv is at 20, SinCos at 3,656, RotatePoint at 3,834 and
; Project at 4,168. EVEN costs nothing where the offset is already even, so it
; is written before each and the assembler decides.
;
        EVEN
SinCos  PROC    NEAR
        push    bp
        mov     bp,sp
        mov     bx,[bp+0Ch]             ; the angle, tenths of a degree
        and     bx,bx                   ; negative?
        jns     short @@Wrapped         ;   no -- go and test the upper end
        nop                             ; 1107:180E -- see the padding note
        nop
@@AddTurn:
        add     bx,3600                 ; wrap up one whole turn
        js      short @@AddTurn         ; still negative -- again
        jmp     short @@Wrapped
@@SubTurn:
        sub     bx,3600                 ; wrap down one whole turn
@@Wrapped:
        cmp     bx,3600                 ; past a full turn?
        jg      short @@SubTurn         ;   yes -- take one off and retest
        cmp     bx,1800                 ; bottom half of the circle?
        ja      short @@Lower           ;   no, it is 1801..3600
        nop                             ; 1107:1828
        nop
        cmp     bx,900                  ; first quadrant?
        ja      short @@Quad2           ;   no, it is 901..1800
        nop                             ; 1107:1830
        nop

; --- quadrant 1, 0..900: cos and sin both positive ---
        shl     bx,2                    ; * 4, a dword index
        mov     eax,cs:[bx+offset CosTab]        ; C := T[a]
        neg     bx                      ; index backwards from entry 900
        mov     edx,cs:[bx+offset CosTab+3600]   ; S := T[900-a]
        jmp     short @@Store
        nop                             ; 1107:1845

; --- quadrant 2, 901..1800: cos negative, sin positive ---
@@Quad2:
        neg     bx
        add     bx,1800                 ; BX := 1800 - a
        shl     bx,2
        mov     eax,cs:[bx+offset CosTab]        ; T[1800-a]
        neg     eax                     ; C := -T[1800-a]
        neg     bx
        mov     edx,cs:[bx+offset CosTab+3600]   ; S := T[a-900]
        jmp     short @@Store

; --- the bottom half: fold it about 3600 first ---
@@Lower:
        neg     bx
        add     bx,3600                 ; BX := 3600 - a
        cmp     bx,900                  ; which of the two quadrants?
        ja      short @@Quad3           ;   1801..2700
        nop                             ; 1107:186E
        nop

; --- quadrant 4, 2701..3600: cos positive, sin negative ---
        shl     bx,2
        mov     eax,cs:[bx+offset CosTab]        ; C := T[3600-a]
        neg     bx
        mov     edx,cs:[bx+offset CosTab+3600]   ; T[a-2700]
        neg     edx                     ; S := -T[a-2700]
        jmp     short @@Store

; --- quadrant 3, 1801..2700: cos and sin both negative ---
@@Quad3:
        neg     bx
        add     bx,1800                 ; BX := a - 1800
        shl     bx,2
        mov     eax,cs:[bx+offset CosTab]        ; T[a-1800]
        neg     eax                     ; C := -T[a-1800]
        neg     bx
        mov     edx,cs:[bx+offset CosTab+3600]   ; T[2700-a]
        neg     edx                     ; S := -T[2700-a]

@@Store:
        les     bx,[bp+08h]             ; the first var parameter
        mov     es:[bx],eax             ;   := the cosine
        les     bx,[bp+04h]             ; the second
        mov     es:[bx],edx             ;   := the sine
        pop     bp
        ret     0Ah
SinCos  ENDP

; ----------------------------------------------------------------------------
; RotatePoint -- procedure RotatePoint(var X, Y, Z : LongInt);
;
; Turn one point about all three axes, in place. Call SinCos three times first
; to load MCos1..MSin3 -- this routine does no trigonometry of its own, it only
; applies what is already there, which is what makes it cheap enough to run per
; vertex.
;
;   var X   [BP+0Ch]
;   var Y   [BP+08h]
;   var Z   [BP+04h]
;
; EQUIVALENT PASCAL, REFERENCE ONLY -- the three pairs below are the whole
; algorithm and the assembler is a transcription of them:
;
;       procedure RotatePoint(var X, Y, Z : LongInt);
;       var Y1, Z1, X2, Z2 : LongInt;
;       begin
;         Y1 := FixMul(Y,  MCos1) + FixMul(Z,  MSin1);
;         Z1 := FixMul(Z,  MCos1) - FixMul(Y,  MSin1);
;         X2 := FixMul(X,  MCos2) - FixMul(Z1, MSin2);
;         Z2 := FixMul(Z1, MCos2) + FixMul(X,  MSin2);
;         X  := FixMul(X2, MCos3) + FixMul(Y1, MSin3);
;         Y  := FixMul(Y1, MCos3) - FixMul(X2, MSin3);
;         Z  := Z2
;       end;
;
; Three concatenated 2-D rotations in 16.16, using the six values SinCos left
; in MCos1..MSin3:
;
;       about the first axis    Y1 := Y*C1 + Z*S1     Z1 := Z*C1 - Y*S1
;       about the second        X2 := X*C2 - Z1*S2    Z2 := Z1*C2 + X*S2
;       about the third         X3 := X2*C3 + Y1*S3   Y3 := Y1*C3 - X2*S3
;
; All three coordinates stay in registers for the whole routine -- EBX is X,
; ECX is Y, EDI is Z, ESI is the term being built -- and only the six IMULs
; touch memory. There is no clipping and no depth test; Project does that.
; ----------------------------------------------------------------------------
; [re] EVEN before this one too -- see the note above FixDiv. Every routine in this
; object starts at an EVEN offset in the original: taking FixMul's address as
; the segment base, FixDiv is at 20, SinCos at 3,656, RotatePoint at 3,834 and
; Project at 4,168. EVEN costs nothing where the offset is already even, so it
; is written before each and the assembler decides.
;
        EVEN
RotatePoint PROC NEAR
        push    bp
        mov     bp,sp
        les     bx,[bp+08h]
        mov     ecx,es:[bx]             ; ECX := Y
        les     bx,[bp+04h]
        mov     edi,es:[bx]             ; EDI := Z
        les     bx,[bp+0Ch]
        mov     ebx,es:[bx]             ; EBX := X

; --- first axis: Y and Z turn about X ---
        mov     eax,ecx                 ; Y
        imul    MCos1                   ; EDX:EAX := Y * cos1
        shr     eax,16                  ; take the middle 32 bits of the
        shl     edx,16                  ;   64-bit product, which is the
        or      eax,edx                 ;   16.16 result
        mov     esi,eax                 ; ESI := Y*C1
        mov     eax,edi                 ; Z
        imul    MSin1                   ; EDX:EAX := Z * sin1
        shr     eax,16
        shl     edx,16
        or      eax,edx
        add     esi,eax                 ; ESI := Y*C1 + Z*S1  -- the new Y
        mov     eax,edi                 ; Z
        imul    MCos1                   ; EDX:EAX := Z * cos1
        shr     eax,16
        shl     edx,16
        or      eax,edx
        mov     edi,eax                 ; EDI := Z*C1
        mov     eax,ecx                 ; Y
        imul    MSin1                   ; EDX:EAX := Y * sin1
        shr     eax,16
        shl     edx,16
        or      eax,edx
        neg     eax                     ; the original negates and adds
        add     edi,eax                 ; EDI := Z*C1 - Y*S1  -- the new Z
        mov     ecx,esi                 ; ECX := the new Y

; --- second axis: Z and X turn about Y ---
        mov     eax,ebx                 ; X
        imul    MCos2                   ; EDX:EAX := X * cos2
        shr     eax,16
        shl     edx,16
        or      eax,edx
        mov     esi,eax                 ; ESI := X*C2
        mov     eax,edi                 ; Z
        imul    MSin2                   ; EDX:EAX := Z * sin2
        shr     eax,16
        shl     edx,16
        or      eax,edx
        sub     esi,eax                 ; ESI := X*C2 - Z*S2  -- the new X
        mov     eax,edi                 ; Z
        imul    MCos2                   ; EDX:EAX := Z * cos2
        shr     eax,16
        shl     edx,16
        or      eax,edx
        mov     edi,eax                 ; EDI := Z*C2
        mov     eax,ebx                 ; X
        imul    MSin2                   ; EDX:EAX := X * sin2
        shr     eax,16
        shl     edx,16
        or      eax,edx
        add     edi,eax                 ; EDI := Z*C2 + X*S2  -- the new Z
        mov     ebx,esi                 ; EBX := the new X

; --- third axis: X and Y turn about Z ---
        mov     eax,ebx                 ; X
        imul    MCos3                   ; EDX:EAX := X * cos3
        shr     eax,16
        shl     edx,16
        or      eax,edx
        mov     esi,eax                 ; ESI := X*C3
        mov     eax,ecx                 ; Y
        imul    MSin3                   ; EDX:EAX := Y * sin3
        shr     eax,16
        shl     edx,16
        or      eax,edx
        add     esi,eax                 ; ESI := X*C3 + Y*S3  -- the new X
        mov     eax,ecx                 ; Y
        imul    MCos3                   ; EDX:EAX := Y * cos3
        shr     eax,16
        shl     edx,16
        or      eax,edx
        mov     ecx,eax                 ; ECX := Y*C3
        mov     eax,ebx                 ; X
        imul    MSin3                   ; EDX:EAX := X * sin3
        shr     eax,16
        shl     edx,16
        or      eax,edx
        sub     ecx,eax                 ; ECX := Y*C3 - X*S3  -- the new Y
        mov     ebx,esi                 ; EBX := the new X (redundant, kept)

        mov     eax,ebx
        les     bx,[bp+0Ch]
        mov     es:[bx],eax             ; X := the rotated X
        mov     eax,ecx
        les     bx,[bp+08h]
        mov     es:[bx],eax             ; Y := the rotated Y
        mov     eax,edi
        les     bx,[bp+04h]
        mov     es:[bx],eax             ; Z := the rotated Z
        pop     bp
        ret     0Ch
RotatePoint ENDP

; ----------------------------------------------------------------------------
; Project -- procedure Project(var X, Y, Z : LongInt);
;
; Turn a rotated 3-D point into a screen pixel: divide by depth, scale, and
; offset to the middle of the view. This is the last step before something is
; drawn, and it is where the perspective comes from -- dividing by Z is what
; makes distant things small.
;
;   var X   [BP+0Ch]    in: rotated X.  out: SCREEN X, zero-extended
;   var Y   [BP+08h]    in: rotated Y.  out: SCREEN Y, zero-extended
;   var Z   [BP+04h]    the divisor, left alone
;
; EQUIVALENT PASCAL, REFERENCE ONLY:
;
;       procedure Project(var X, Y, Z : LongInt);
;       begin
;         X := FixMul(FixDiv(X, Z), MScale) + MViewW div 2;
;         Y := MViewH div 2 - FixMul(FixDiv(Y, Z), MScale)
;       end;
;
;       sx := Round(X / Z * MScale) + MViewW div 2
;       sy := MViewH div 2 - Round(Y / Z * MScale)
;
; The divide is the expensive part and it is done properly: SHRD/SAR builds a
; 48-bit dividend (X shifted left 16 with the sign carried into EDX) so that
; IDIV yields a 16.16 quotient rather than a whole number. That result is then
; scaled by the same middle-32-bits multiply RotatePoint uses.
;
; Rounding is `ADD 8000h` then a shift, i.e. + 0.5 before truncating.
;
; THERE IS NO GUARD ON Z. A point that reaches Z = 0 divides by zero and the
; program dies. Callers keep their objects at negative Z so it does not come
; up; the original takes the same bet.
;
; The two results are written back ZERO-extended -- XOR EDI,EDI then MOV DI,BX
; keeps only the low 16 bits and clears the top -- so a negative screen
; coordinate comes back as a large positive LongInt. Callers truncate to
; Integer, which puts the sign back. That is the original's behaviour and the
; reason its clipping tests read the way they do.
; ----------------------------------------------------------------------------
; [re] EVEN before this one too -- see the note above FixDiv. Every routine in this
; object starts at an EVEN offset in the original: taking FixMul's address as
; the segment base, FixDiv is at 20, SinCos at 3,656, RotatePoint at 3,834 and
; Project at 4,168. EVEN costs nothing where the offset is already even, so it
; is written before each and the assembler decides.
;
        EVEN
Project PROC    NEAR
        push    bp
        mov     bp,sp
        les     bx,[bp+04h]
        mov     edi,es:[bx]             ; EDI := Z, the divisor
        les     bx,[bp+08h]
        mov     ecx,es:[bx]             ; ECX := Y
        les     bx,[bp+0Ch]
        mov     ebx,es:[bx]             ; EBX := X

        mov     edx,ebx                 ; the X divide
        sub     eax,eax                 ; EDX:EAX := X << 16, sign-extended,
        shrd    eax,edx,16              ;   so the quotient comes out 16.16
        sar     edx,16                  ;   rather than whole
        idiv    edi                     ; EAX := (X << 16) / Z
        imul    MScale                  ; * the projection scale...
        shr     eax,16                  ;   ...taking the middle 32 bits
        shl     edx,16
        or      eax,edx
        mov     ebx,eax                 ; EBX := the scaled X

        mov     edx,ecx                 ; the Y divide, identically
        sub     eax,eax
        shrd    eax,edx,16
        sar     edx,16
        idiv    edi                     ; EAX := (Y << 16) / Z
        imul    MScale
        shr     eax,16
        shl     edx,16
        or      eax,edx
        mov     ecx,eax                 ; ECX := the scaled Y

        add     ebx,8000h               ; + 0.5, so the shift rounds
        add     ecx,8000h               ;   rather than truncates
        shr     ebx,16                  ; -> whole pixels
        shr     ecx,16
        xor     edi,edi
        mov     di,bx                   ; EDI := the pixel X, zero-extended
        mov     ax,MViewW
        shr     ax,1                    ; the horizontal centre
        add     di,ax                   ; screen X grows rightwards
        xor     edx,edx
        mov     dx,MViewH
        shr     dx,1                    ; the vertical centre
        sub     dx,cx                   ; screen Y grows DOWNWARDS, so this
                                        ;   subtracts rather than adds
        mov     eax,edi
        les     bx,[bp+0Ch]
        mov     es:[bx],eax             ; X := the screen X
        mov     eax,edx
        les     bx,[bp+08h]
        mov     es:[bx],eax             ; Y := the screen Y
        pop     bp
        ret     0Ch
Project ENDP

CODE    ENDS
        END
