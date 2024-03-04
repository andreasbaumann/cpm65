	.title          '6502 interpreter for Pascal-M V2K1'
;
;  MIT License
;
;  Copyright (c) 1978, 2021 Hans Otten
;
;  Permission is hereby granted, free of charge, to any person obtaining a copy
;  of this software and associated documentation files (the "Software"), to deal
;  in the Software without restriction, including without limitation the rights
;  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
;  copies of the Software, and to permit persons to whom the Software is
;  furnished to do so, subject to the following conditions:
;
;  The above copyright notice and this permission notice shall be included in all
;  copies or substantial portions of the Software.
;
;  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
;  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
;  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
;  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
;  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
;  SOFTWARE.
;
;
; First version by G.J.v.d. Grinten 1978,1979
; 
; Hans Otten 1982- 2006 -june 2007  
;   - typed in as is, adapted for TASM , exact binary identical to original! 
;   - bugfixed KIM-1 routines
;   - lowercase
;   - KIM in character no echo
;   - SFA GFA mcode for files handles, no meaning though
;
; Hans Otten V2  October 2021
; interpreter only, loader removed
; expects pascalm mcode and procedure buffer loaded externally
;
; Memory layout
; - $0000 zeropage, starts at 0 
; - $2000 interpreter code, readonly
; - PRCBUF
; - M-code (from BASE)
; - Heap (after last M-code)
; - stack down from ENDCOR
;
; interpreter start 2000 readonly 
; procedure buffer after interpreter at page boundary readonly 
; base memory pcode readonly
; end base memory (stack growing down) read/write
; prcbuf  placed before base memory
;
; TODO
;
; - check if prcbuf is handled right in CUP2
; - align naming conventions with Pascal interpreter
;
; zero page 
;
pc      = $00  	        ; program counter
stack  	= pc + 2        ; software stack pointer
hp      = stack + 2     ; heap pointer
mp      = hp + 2
mpsave  = mp + 2
jtabp   = mpsave + 2	; jump table pointer
jtab2p	= jtabp + 2	; jump table 2
strptr	= jtab2p + 2	; string print pointer
eolb    = strptr + 1	        ; end of input line boolean
eofb   	= eolb + 1	        ; end of file boolean
op     	= eofb + 1	        ; last op code
fa      = op + 1                ; file address handle (ignored in this version)
;
tmp1l8  = op + 1                ; 8 byte temp field
tmp2l2 	= tmp1l8 + 8   	        ; 2 byte temp
tmp3l2	= tmp2l2 + 2            ; 2 byte temp
ytmp    = tmp3l2 + 1            ; temporary Y save
;
; KIM-1 monitor definitions
	;
comman 	=	$1c4f           ; cold start KIM monitor
ttyin  	= 	$1e5a           ; character in from keyboard with echo
ttyout 	=	$1ea0           ; character to video
SBD     =       $1742           ; for PB0 TTYout echo prevention
;
; constants
;
CR      = $0D                   ; Carriage return
LF      = $0A                   ; Linefeed

	.org 	$2000 	        ; start point entry KIM memory starts   
;
contin	jmp	pgo             ; enter here for run pcode program
;
; memory locations, patchable 
;
base    .word $3000             ; start of memory 
endcor  .word $9FFF             ; top of memory
prcbuf  .word $2F00	        ; room for 100 procedures; 
ldaddr   .word $4000            ; end of mcode loaded (has to be patched in!)
;
;
; Interpreter 
;
; Initialize interpreter
pgo     lda     #mstart  / $0100 ; start of mcode 
        sta     pc + 1
        lda     #mstart & $00FF
        sta     pc
        lda     ldaddr          ; clear heap
        sta     hp
        lda     ldaddr + 1        
        sta     hp + 1
        lda     endcor          ; clear stack           ;
        sta     stack
        sta     mp      
        lda     endcor + 1
        sta     stack   + 1
        sta     mp + 1
;
; say hello
;
	lda	#msg002 / $0100	; send message and fatal error exit
	ldx	#msg002 & $00FF
	jsr	prstrng
       
;
; initialize files
;        
        lda     #0              ; clear file flags
        sta     eolb
        sta     eofb
;        
        jmp     interpr            ; start interpreting
        ;
;
exit   	jmp 	comman
	;
	; useful routines
	;
	; increment a 16 bit pointer
	;
incr	clc
	lda	0,x		; X pointing to pointer
	adc	#01
	sta	0,x			
	bcc	incr1		; if no carry
	lda	1,x
	adc	#00
	sta	1,x
incr1	ldx	#0		; clear X
	rts
	;
	; decrement a 16 bit pointer
	;
decr	sec
	lda	0,x		; X pointing to pointer
	sbc	#$01
	sta	0,x
	bcs	decr1		; if carry set no adjust
	lda	01,x
	sbc	#$00
	sta	1,x
decr1	ldx	#0
	rts
	;
	; Add fast 2 to PC
	;
incpc2	clc
	lda	pc
	adc	#$02
	sta	pc
	bcc	incpca		; adjust upper?
	lda	pc + 1
	adc	#$00
	sta	pc + 1
incpca	ldx	#$00
	rts
	;
	; to HEX
	;
hexit	cmp	#$3A
	php
	and	#$0F
	plp
	bcc	hexit1		; 0 .. 9
	adc	#$08		 
hexit1	rts
	;
	; stack operations PULL and PUSH
	; PULL2 and PUSH2
	; enter or exit with val in A or A + Y
	; A contains upper 8 bits , Y lower 8 bits
	;
pull2	jsr	pull		; get Y first
	tay	
pull	ldx	#stack
	jsr	incr
	lda	(stack,x)
	rts
	;
push2	ldx	#00		; clear X
	jsr 	push		; save A
	tya	
push	sta	(stack,x)
	ldx	#stack
	jsr	decr
	rts
	;
	; fatal error message 
	; output string (max 256, with CRLF, end at CR
	; exit to monitor after print
	;
prstrng	sta	strptr + 1	; high part of address
	stx	strptr
	jsr	crlf		; clear line
strina	lda	(strptr),Y
	cmp	#$0d		; test for CR
	beq	stinb
	jsr	wrt		; print char
	iny	
	bne	strina		; interpr 
stinb	jsr	crlf
        rts
string  jsr prstrng             ; print string 
	jmp	exit		; leave 
	;
	; Compute base address of level (op-x)
	; leave result in tmp2l2
	;
basead	lda	mp		; Mark pointer is default
	sta	tmp2l2
	lda	mp + 1
	sta	tmp2l2 + 1
	lda	op		; check level
	and 	#$0F		; isolate level
	beq	bas2		; if level = 0 then finished
	tax			; x := level
bas1	sec			; offset for mark pointrer in stack
	lda	tmp2l2
	sbc	#$01		; point do base MP
	sta	tmp2l2
	lda	tmp2l2 + 1
	sbc	#$00		; adjust upper address
	sta	tmp2l2 + 1
	ldy	#$01		; point to upper part of inirect MP
	lda	(tmp2l2),y	; high part
	pha			; save on stack
	dey	
	lda 	(tmp2l2),Y	; get low part
	sta	tmp2l2
	pla
	sta 	tmp2l2 + 1	; high part
	dex			; level = level - 1
	bne	bas1		; not finished
bas2	rts			; ready 
;
; 	
; Addget get a address of level X 16 bit
;
addget	jsr	basead	        ; get base address of proper level
	ldy	#$01		; get low part of address
	sec
	lda	tmp2l2		; PC points to high part
	sbc	(pc),y		; low part add
	sta	tmp2l2		; replace
	dey			; get high part
	lda	tmp2l2 + 1
	sbc	(pc),y
	sta	tmp2l2 + 1	; tmp2l2 now points to address
	ldx	#pc
	jsr	incr
addg1	ldx	#pc
	jsr	incr
	ldx	#tmp2l2		; subtract 1 from address because LCAP
	jsr	incr		; this is correct for all calls
	rts			; return
;
; Get small address of proper level (same as addget)
;
sadget	jsr	basead
	sec
	ldy	#0
	lda	tmp2l2		; get address pointer
	sbc	(pc),y
	sta	tmp2l2
	lda	tmp2l2 + 1
	sbc	#$00
	sta	tmp2l2 + 1
	jmp	addg1
;	
; Jump table (Starts at 144)
;
jtab	.word	leq2		; 2 bytes less than or equal test
	.word	mfor		; for interpr processing
	.word	leqm		; less or equal test for arrays
	.word	les2		; less than test for 2-byte data items
	.word	leq8		; is contained in test for sets
	.word	lesm		; less test
	.word	equ2		; equal test for 2 bytes
	.word	geq8		; contains test for sets
	.word	equm		; equal test for records and arrays
	.word	equ8		; equal test for sets
	.word	ind1		; indirectly load 1-byte data item
	.word	ind2		; indirectly load 2-byte data item
	.word	ind8		;  indirectly load 8-byte data item
	.word	sto1		; store 1 byte
	.word	sto2		; store 2 byte
	.word	sto8		; store 8 byte
	.word	ldc		; load 2-byte constant
	.word	retp		; return from procedure or function
	.word	adi		; add integer
	.word	andb		; booelan and
	.word	dif		; set difference
	.word	dvi		; integer divide
	.word	inn		; test if element in set
	.word	int		; set interaction
	.word	ior		; inclusive or
	.word	mod		; modulus function
	.word	mpi		; integer multiply
	.word	ngi		; negate integer
	.word	not		; negate boolean
	.word	sbi		; subtract integer
	.word	sgs		; generate singleton set
	.word	uni		; set union
	.word	lnc		; load negative constant
	.word	fjp		; false jump
	.word	ujp		; unconditionally jump
	.word	decb		; decrement
	.word	incb		; increment
	.word	ent		; enter block
	.word	cas		; case statement processor
	.word	mov		; move storage
	.word	dec1		; decrement by 1
	.word	inc1		; increment by 1
	.word	ldcs		; load set constant (8 bytes)
	.word	cap		; call assembly procedure
	.word	lca		; load constant address
	.word	csp		; call standard procedure
	.word	cup1		; call user procedure simple
	.word	cup2		; complex call user procedure
	.word	fix21		; clean up stack  after call to single
	.word	lns		; load null set
        .word   sfa             ; set file handle
        .word   gfa             ; get file handle
;
; additional addresses for routines
;
jtab2	.word	ldcis		; load small integer constant (0..15)
	.word	ldas		; load short address
	.word	ldad		; load address
	.word	msto		; mark stack without return bytes
	.word	mstn		; mark stack with return bytes
	.word	lod1		; load 1 byte data item on stack
	.word	lod2		; load 2 byte data item on stack
	.word	str1		; store 1 byte into memory
	.word	str2		; store 2 byte into memory
;
; no more can go into jtab2 because range 0-8
;
;
;Standard M-code procedure to start M-code interpretation,
;
;  CSP   11   Standard proc Stop 
; 
mstart	.byte	$30		; MST0 mark stack
	.byte	$BE,0		; CUP1  0    proc nr 0call procedure 0
	.byte	$BD,$0B		; CSP   11   Standard procedure  Stop 
;
; Start of Pascal-M code interpreter
;
; test if stack will overflow
;
tststk	sec			; test if stack and heap will meet
	lda	stack	
	sbc	hp
	sta	tmp2l2
	lda	stack + 1
	sbc	hp + 1
	bcs	tst1x1		; overflow already
ovfl	lda	#msg005 / $0100	; send message and fatal error exit
	ldx	#msg005 & $00FF
	jmp	string
tst1x1	bne	interpr
	lda	tmp2l2
	cmp	#$30		; reserve $30 on stack?
	bcc	ovfl
;
; main interpr starts here
;
interpr	ldx	#0
	lda	(pc,x)
	sta	op
	inc	pc
	bne	intrpr1
	inc	pc + 1
intrpr1	cmp	#$C3
	bcc	intrpr2		; opcode in range
	lda	#msg003 / $0100
	ldx	#msg003 & $00FF
	jmp	string
intrpr2	cmp	#$90		; test if direct op
	bcs	pacop		; packed opcode
	lsr	a
	lsr	a
	lsr	a
	and	#$1E
	tay			; use y for index
	lda	jtab2,y
	sta	jtabp
	iny
	lda	jtab2,y
	sta	jtabp + 1
	jmp	(jtabp)		; enter routine
pacop	sbc	#$90		; carry was set
	asl	a
	tay
	lda	jtab,y
	sta	jtabp
	iny
	lda	jtab,y
	sta	jtabp + 1
	jmp	(jtabp)		; jump 
;     
notimp	lda	#msg007 / $0100
	ldx	#msg007 & $00FF
	jmp	string		; not implemented message, fatal
;
; setup1 and setup2 are subroutines to setup 
;
; variables for various functions (ADD, SUBTR etc)
;
setup2	jsr	pull2		; get first operand
	sta	tmp3l2 + 1
	sty	tmp3l2
setup1	jsr	pull2		; next item goes into tmp2l2
	sta	tmp2l2 + 1
	sty	tmp2l2
	rts
;
; simple m-codes
;
; LDCS (0X) load small integer constant 
;
ldcis	ldy	op		; load small scalar constant
	lda	#0		; push single byte value 0
	jsr	push2
	jmp	interpr
;
; GFA
;
gfa	ldy	fa		; load file handle constant
	lda	#0		; push single byte value 0
	jsr	push2
	jmp	interpr

;
; SFA
;
sfa     jsr pull2               ; get file handle constant
        sty fa                  ; store fa
	jmp	interpr
;
;
; LDA (1X YY) load short address
;
ldas	jsr	sadget		; load small address
	lda	tmp2l2 + 1	; get high part
	ldy	tmp2l2		; low part
	jsr	push2		;	
	jmp	tststk
;
; LDA (2X YY YY) load address
;
ldad	jsr	addget		; load 16 bit address
	lda	tmp2l2 + 1	; get high part of indirect address
	ldy	tmp2l2		; lw part
	jsr	push2
	jmp	tststk
;
; MST0	(3X) mark stack without return bytes
;
msto	jsr	basead		; get base address of proper level X
	lda	stack		; move stack pointer to mpsave
	sta	mpsave
	lda	stack + 1
	sta	mpsave + 1
	lda	tmp2l2 + 1	; push base address
	ldy	tmp2l2		; as saved by basead
	jsr	push2
	lda	mp + 1		; save mark pointer
	ldy	mp
	jsr	push2
	lda	#0		; push dummy for p counter save
	tay	 
	jsr	push2
	jmp	tststk		; test for overflow
;
; MSTN	(4X YY) mark stack with return bytes for function
;
mstn	ldy	#$0
	lda	(pc),y		; get operand (nr of bytes to fill)
	tay	
	ldx	#pc		; increment PC
	jsr	incr
mstn1	txa			; get a zero in A reg
	jsr	push		; push a dummy onto stack
	dey	
	bne	mstn1		; not done yet
	jmp	msto		; now mark stack as normal
;
; LOD1 (5X YY) load 1 byte item onto stack
;
lod1	jsr	sadget		; get item address in reserved stack
	ldx	#0
	lda	(tmp2l2,x)	; load item
	tay			; low part
	txa			; push zero
	jsr	push2		; all items on stack are 16 bit
	jmp	tststk
	;
	; LOD2 (6X YY) load 2 byte data item
	;
lod2	jsr	sadget		; get address in tmp2l2 of item
	ldx	#0		; index 0
	lda	(tmp2l2,x)	; low part
	tay			; save A in Y
	ldx	#tmp2l2		; high part
	jsr	incr
	lda	(tmp2l2,x)	; get high part
	jsr	push2		; push all
	jmp	tststk		; 
	;
	; STR1 (7X YY) store 1 byte data item
	;
str1	jsr	sadget
	jsr	pull2		; get 16 bit with 8 valid bit item
	tya			; low part, X is zero
	sta	(tmp2l2,x)	; store in memory
	jmp	interpr
;
; STR2 (8X YY) store 2 byte data item in memory
;
str2	jsr	sadget		; store 16 bits
	jsr	pull2		; high part in A
	pha
	tya			; store low part first
	sta	(tmp2l2,x)
	ldx	#tmp2l2		; decrement address on stack
	jsr	incr
	pla			; get high part
	sta	(tmp2l2,x)	; store high part
	jmp	interpr
;
; indirect routines
;
; 90 LEQ2
;
leq2	jsr	cmp2		; compare next to top with top
	bne	leq2x1		; false
leq2x0	ldy	#$01		; true = 1
	bne	leq2x2		; always
leq2x1	ldy	#$00		; false
leq2x2	lda	#$00		; dummy
	jsr	push2		; push boolean on stack
	jmp	interpr
;
; FOR
;
mfor	ldy	#$01		; point to first cell on stack
	lda	(stack),y	; test for init interpr cell
	bmi	for1		; been here before
	ora	#$80		; set been here 
	sta	(stack),y
	jsr	forin		; init interpr cell
	jmp	for5		; process for interpr
for1	ldy	#$07		; get address of cell in tmp2
	lda	(stack),y
	sta	tmp2l2
	iny
	lda	(stack),y	
	sta	tmp2l2 + 1
	ldy	#0		; get the interpr count
	lda	(tmp2l2),y
	sta	tmp3l2
	iny
	lda	(stack),y	; test for 1 or 2 bytes
	and	#$01
	sta	tmp3l2 + 1 	; init tmp3l2 =1 for zero
	beq	for2
	lda	(tmp2l2),y	; get second byte
	sta	tmp3l2 + 1
for2	lda	(stack),y	; y is still 1
	and	#$04		; to or downto test
	bne	for3		; down
	ldx	#tmp3l2
	jsr	incr		; 16 bit increment by 1
	jmp	for4
for3	ldx	#tmp3l2
	jsr	decr		; 16 bit decrement 
for4	ldy	#$00		; save new interpr counter
	lda	tmp3l2
	sta	(tmp2l2),y
	iny
	lda	(stack),y
	and	#$01		; 1 or 2 bytes to save?
	beq	for5		; 
	lda	tmp3l2 + 1
	sta	(tmp2l2),y	; save second byte
for5	ldy	#$01			
	lda	(stack),y
	and	#$04		; test to or downto
	bne	for6		; downto?
	sec
	ldy	#03		; point to end value
	lda	(stack),y
	sbc	tmp3l2
	iny
	lda	(stack),y	; 16 bit test
	sbc	tmp3l2 + 1
	bmi	forend
forlp	ldy	#$00
	lda	(pc),y		; get jump address in tmp2
	sta	tmp2l2 + 1
	iny	
	lda	(pc),y	
	sta	tmp2l2
	jmp	cas2		; jump
for6	sec			; downto
	ldy	#$03
	lda	tmp3l2
	sbc	(stack),y
	iny
	lda	tmp3l2 + 1
	sbc	(stack),y
	bpl	forlp		; do the jump
forend	clc
	lda	stack
	adc	#$08
	sta	stack
	lda	stack + 1
	adc	#$00
	sta	stack + 1	; remove for table
	jsr	incpc2		; increment pc by 2
	jmp	interpr
	;
	; 92 LEQM
	;
leqm	jsr	compar
	lda	#$00
	ldy	tmp1l8
	dey	
	bpl	leqm2
	ldy	#$01
leqm1	jsr	push2
	jmp	tststk
leqm2	tay	
	beq	leqm1
	;
	; LES2
les2	jsr	cmp2		; same as leq2 without equal
	jmp	leq2x1		; minus test should have been catched
	;
cmp2	jsr	setup2		; first OP in tmp3, second in tmp2
	sec			
	lda	tmp2l2
	sbc	tmp3l2
	sta	tmp2l2		; save for equal test
	lda	tmp2l2 + 1
	sbc	tmp3l2 + 1
	bmi	cmp2a		; if less than (15 bits) 
	bne	cmp2b		; not equal high pat
	lda	tmp2l2		; possible high part equal
	rts
cmp2a	pla			; full return address
	pla
	jmp	leq2x0
cmp2b	pla
	pla
	jmp	leq2x1
	;
	; 94 LEQ8
	;
leq8	ldy	#$08		; nr of set words and offset in set
	ldx	#0	
	sty	tmp2l2		; tmp2l2 is count
	stx	tmp3l2		; test for end result
leq8a	jsr	pull		; get a member
	and 	(stack),y	; delete non-interesting parts
	eor	(stack),y	; flip remaining bits
	beq	leq8b		; if all bits flipped
	inc	tmp3l2		; not al bits flipped not same
leq8b	dec	tmp2l2		; we did the interpr again
	bne	leq8a		; repeat 8 times
	jsr	pull2		; second stack from set
	jsr	pull2	
	jsr	pull2	
	jsr	pull2	
	lda	tmp3l2
	bne	leq8c
	jmp	leq2x0		; set was contained in
leq8c	jmp	leq2x1		; not contained in
	;
	; 95 LESM
	; 
lesm	jsr	compar
	lda	#$00
	ldy	tmp1l8
	bpl	lesm2
	ldy	#$01
lesm1	jsr	push2
	jmp	tststk
lesm2	tay
	beq	lesm1
	;
	; 96 EQU2
	;
equ2	jsr	setup2		; compare tmp2 and tmp3
	lda	tmp3l2		; test lower part
	cmp	tmp2l2
	bne	equ2x1		
	lda	tmp3l2 + 1
	cmp	tmp2l2 + 1
	bne	equ2x1		; not equal
	jmp	leq2x0		; push 1
equ2x1	jmp	leq2x1
	;
	; 97 GEQ8
	;
geq8	ldy	#$08		; offset n stack and count
	ldx	#$00
	sty	tmp2l2		; read comment at ISTR 94
	stx	tmp3l2
geq8a	jsr	pull
	sta	tmp2l2 + 1
	lda	(stack),y	; get member to test
	and	tmp2l2
	eor	tmp2l2 + 1
	beq	geq8b
	inc	tmp3l2
geq8b	dec	tmp2l2
	bne	geq8a
	jsr	pull2
	jsr	pull2
	jsr	pull2
	jsr	pull2
	lda	tmp3l2
	bne	geq8c
	jmp	leq2x1
geq8c	jmp	leq2x1		; send false
	;
	; 98 EQUM
	;
equm	jsr	compar
	lda	#$00
	ldy	tmp1l8
	bne	equm2
	iny
equm1	jsr	push2
	jmp	tststk
equm2	tay
	beq	equm1
	;
	; 99 EQU8
	;
equ8	ldy	#$08		; 8 bytes to compare
	sty	tmp2l2		; use as count also
	ldx	#$00
	stx	tmp2l2 + 1	; use as switch zero on end
equ8x1	jsr	pull		; get a char in A to compare
	cmp	(stack),y	; compare in stack
	beq	equ8x2		; if equal
	inc	tmp2l2 + 1	; not equal set switch
equ8x2	dec	tmp2l2
	bne	equ8x1
	jsr 	pull2		; clean up stack
	jsr	pull2
	jsr	pull2
	jsr	pull2
	lda	tmp2l2 + 1
	bne	equ8x3		; if not equal
	jmp	leq2x0		; send 1
equ8x3	jmp	leq2x1		; send 0
	;
	; 9A IND1
	;
ind1	jsr	setup1		; get indirect address from stack
	ldy	#$00		; index
	lda	(tmp2l2),y	; get 1 byte operand
	tay
	lda	#$00		; dummy
	jsr	push2	
	jmp	interpr
	;
	; 9B IND2
	;
ind2	jsr	setup1		; get address to 16 byte indirect op
	ldx	#$00
	lda	(tmp2l2,x)
	tay			; setup for push
	ldx	#tmp2l2		; increment pointer
	jsr	incr		; point to upper part
	lda	(tmp2l2,x)
	jsr	push2		; push item onto stack
	jmp	interpr
	;
	; 9C IND8
	;
ind8	jsr	setup1		; get indirect address
ind8x1	ldy	#$07
ind8x2	lda	(tmp2l2),y	; lineair move
	jsr	push
	dey			; point to upper part
	bpl	ind8x2		; repeat until 8 worrds done
	jmp	tststk
	;
	; 9D STO1
	;
sto1	jsr	setup2
	ldy	#$00
	lda	tmp3l2		; op to store
	sta	(tmp2l2),y
	jmp	interpr
	;
	; 9E STO2
	;
sto2	jsr	setup2		; get 16 bit address in tmp3 and address
	ldx	#$00
	lda	tmp3l2
	sta	(tmp2l2,x)
	ldx	#tmp2l2
	jsr	incr
	lda	tmp3l2 + 1 	; upper half
	sta	(tmp2l2,x)
	jmp	interpr
	;
	; 9F STO8
	;
sto8	ldy	#$09		; add 10 to stackpointer to read add
	lda	(stack),y	; lower part of address
	sta	tmp2l2
	iny	
	lda	(stack),y
	sta	tmp2l2 + 1
	ldy	#$00
sto8x1	jsr	pull		; get item from stack
	sta	(tmp2l2),y	; linear move
	iny
	cpy	#$08		; do 8 words
	bne	sto8x1
	jsr	pull2		; and for final get address from stack
	jmp	interpr
	;
	; A0 LDC
	;
ldc	lda	(pc,x)		; load 16 bit constant
	pha			; save high part
	inc	pc
	bne	ldc1
	inc	pc + 1
ldc1	lda	(pc,x)		; get low part
	tay			; ready for push
	inc	pc
	bne	ldc2
	inc	pc + 1
ldc2	pla			; high part
	jsr	push2		
	jmp	tststk
	;
	; A1 RETP
	;
retp	lda	mp		; reset stackpointer
	sec
	sbc	#$06
	sta	stack
	lda	mp + 1
	sbc	#$00		; setup stack 6 bytes away from MP
	sta	stack + 1
	jsr	pull2		; get PC from stack
	sty	pc
	sta	pc + 1
	jsr 	pull2		; get Mark pointer
	sty	mp
	sta	mp + 1
	jsr	pull2		; get dummy mp base address from stack
	jmp	interpr
	;
	; A2 ADI
	;
adi	jsr	setup2		; add 2 16 bit numbers
	clc
	lda	tmp2l2
	adc	tmp3l2		; add low part
	tay			; result to Y
	lda	tmp2l2 + 1
	adc	tmp3l2 + 1
	jsr	push2
	jmp	interpr
	;
	; A3 ANDB
	;
andb	jsr	setup2		; and for boolean
	lda	tmp3l2
	and	tmp2l2
	tay
	lda	#$00		; dummy
	jsr	push2
	jmp	interpr
	; A4 DIF
	;
dif	ldy	#$08
	sty	tmp2l2		; counter 8
dif1	jsr	pull
	and	(stack),y
	eor	(stack),y
	sta	(stack),y
	dec	tmp2l2
	bne	dif1
	jmp	interpr
	;
	; A5 DVI
	;
dvi	jsr	mdset		; setup for divide
	jsr	divide
	lda	tmp1l8 + 6	; get sign of result
	and	#$01
	beq	dvi1		; no correction
	lda	tmp1l8 + 4
	eor	#$FF
	sta	tmp1l8 + 4
	lda	tmp1l8 + 5
	eor	#$FF
	sta	tmp1l8 + 5
	ldx	#tmp1l8 + 4
	jsr	incr
dvi1	ldy	tmp1l8 + 4
	lda	tmp1l8 + 5
	jsr	push2
	jmp	interpr
	;
	; A6 INN
	;
inn	ldy	#$00		; get set from stack
inn1	jsr	pull
	sta	tmp1l8,y
	iny
	cpy	#$08		; sets are 8 bytes
	bne	inn1
	jsr	pull2		; get the bit to test
	tya	
	and	#$07		; bit on word
	tax
	tya
	lsr	a
	lsr	a
	lsr	a
	tay			; word nr offset in tmp1l8
	lda	#$00		; repeat
	sec			;  shift bit in a
inn2	ror	a		;
	dex			; decr bit nr
	bpl	inn2
	and	tmp1l8,y	; test bit
	beq	inn3		; if not set
	ldy	#$01
	bne	inn4
inn3	ldy	#$00		; true
inn4	lda	#$00		; dummmy for 16 bits
	jsr	push2
	jmp	interpr
	;
	; A7 INT
int	ldy	#$08
	sty	tmp2l2
int1	jsr	pull
	and	(stack),y
	sta	(stack),y
	dec	tmp2l2
	bne	int1
	jmp	interpr
	;
	; A8 IOR
	;
ior	jsr	setup1
	ldy	#$01
	lda	(stack),y
	ora	tmp2l2
	sta	(stack),y
	jmp	interpr
	;
	; A9 MOD
	;
mod	jsr	mdset
	jsr	divide
	lda	tmp1l8 + 6
	and	#$01
	beq	mod1
	lda	tmp1l8 + 2
	eor	#$FF
	sta	tmp1l8 + 2
	lda	tmp1l8 + 3
	eor	#$FF
	sta	tmp1l8 + 3
	ldx	#tmp1l8 + 2
	jsr	incr
mod1	ldy	tmp1l8 + 2
	lda	tmp1l8 + 3
	jsr	push2
	jmp	interpr
	;
	; AA MPI
	;
mpi	jsr	mdset
	jsr	mply
	lda	tmp1l8 + 6 
	and	#$01
	beq	mpi1
	lda	tmp1l8 + 4
	eor	#$FF
	sta	tmp1l8 + 4
	lda	tmp1l8 + 5
	eor	#$FF
	sta	tmp1l8 + 5
	ldx	#tmp1l8 + 4
	jsr	incr
mpi1	ldy	tmp1l8 + 4
	lda	tmp1l8 + 5
	jsr	push2
	jmp	interpr
	;
	; AB NGI
	;
ngi	jsr	setup1		; get number to complement
	lda	tmp2l2
	eor	#$FF
	sta	tmp2l2
	lda	tmp2l2 + 1
	eor	#$FF
	sta	tmp2l2 + 1
	ldx	#tmp2l2
	jsr	incr		; ones complement
	ldy	tmp2l2
	lda	tmp2l2 + 1
	jsr	push2
	jmp	interpr
	;
	; AC NOT
	;
not	ldy	#$01		; complement boolean on stack
	lda	(stack),y
	eor	#$01		; only bit 0 to do
	sta	(stack),y
	jmp	interpr
	;
	; AD SBI
	;
sbi	jsr	setup2		; subtract two 16 bit numbers on stack
	sec			
	lda	tmp2l2
	sbc	tmp3l2
	tay			; result low part in Y
	lda	tmp2l2 + 1
	sbc	tmp3l2 + 1
	jsr	push2		; result ok
	jmp	interpr
	;
	; AE SGS
	;
sgs	ldx	#$00		; geneterate single bit set
	ldy	#$07		; clear tmp1l8
sgs1	stx	tmp1l8,y
	dey
	bpl	sgs1
	jsr	pull2		; get bit number of set
	tya
	and	#$07		; get bit no
	tax
	tya
	lsr	a
	lsr	a
	lsr	a
	tay			; byte no in y
	lda	#$00
	sec
sgs2	ror	a		; shift the bit in
	dex
	bpl	sgs2
	sta	tmp1l8,y	; now bit in word is formed
	ldy	#$07			; now push set onto stack
	ldx	#$00			; 
sgs3	lda	tmp1l8,y		; high bit first
	jsr	push
	dey
	bpl	sgs3
	jmp	tststk
	;
	; AF UNI
	;
uni	ldy	#$08
	sty	tmp2l2
uni1	jsr	pull
	ora	(stack),y
	sta	(stack),y
	dec	tmp2l2
	bne	uni1
	jmp	interpr
	; 
	; B0 LNC
	;
lnc	ldy	#$01
	lda	(pc),y
	eor	#$FF		; complement
	sta	tmp2l2
	dey
	lda	(pc),y
	eor	#$FF
	sta	tmp2l2 + 1
	ldx	#tmp2l2
	jsr	incr
	lda	tmp2l2 + 1	;
	jmp	decx1		; use common end
	;
	; B1 FJP
	;
fjp	jsr	setup1		; get boolean from stack
	lda	tmp2l2
	beq	ujp		; false jump
	jsr	incpc2		; next 
	jmp	interpr
	; 
	; B2 UJP
	;
ujp	ldy	#$01
	lda	(pc),Y
	sta	tmp2l2
	dey
	lda	(pc),Y
	sta	tmp2l2 + 1
	jmp	cas2		; do jump via use common end
	;
	; B3 DECB
	;
decb	jsr	setup1
	ldy	#$01
	sec
	lda	tmp2l2
	sbc	(pc),y
	sta	tmp2l2
	dey
	lda	tmp2l2 + 1
	sbc	(pc),y
decx1	ldy	tmp2l2
	jsr	push2
	jsr	incpc2
	jmp	interpr
	;
	; B4 INCB
	;
incb	jsr	setup1
	ldy	#$01
	clc
	lda	tmp2l2
	adc	(pc),y
	sta	tmp2l2
	dey	
	lda	tmp2l2 + 1
	adc	(pc),y
	jmp	decx1
	;
	; B5 ENT
	;
ent	ldy	#$01		; index to low part of bytes
	lda	stack		; nr of bytes to reserve on stack
	sec
	sbc	(pc),y
	sta	stack
	dey
	lda	stack + 1
	sbc	(pc),y
	sta	stack + 1	; words are reserved now
	jsr	incpc2
	jmp	tststk		; check if stack has room
	;
	; B6 CAS
	;
cas	jsr	setup1		; case nr
	ldy	#$01
	sec	
	lda	tmp2l2		; test for less than
	sbc	(pc),y
	sta	tmp3l2		; save as index
	dey
	lda	tmp2l2 + 1
	sbc	(pc),y
	sta	tmp3l2 + 1
	bmi	casex		; less than minimum test for else clause
	ldy	#$03		; else is standardized to otherwise
	sec
	lda	(pc),y		; test for larger than max
	sbc	tmp2l2
	dey
	lda	(pc),y
	sbc	tmp2l2 + 1 
	bmi	casex		; if larger than max
	asl	tmp3l2		; multiply by two for dual word index
	rol	tmp3l2 + 1
	clc			; case of
	lda	tmp3l2
	adc	pc
	sta	tmp3l2		; add index to PC to look into
	lda	tmp3l2 + 1
	adc	pc + 1
	sta	tmp3l2 + 1
	ldy 	#$07		; offset in table
	lda	(tmp3l2),y
	sta	tmp2l2		; lower part of new PC
	dey	
	lda	(tmp3l2),y
	sta	tmp2l2 + 1
	clc
	adc	tmp2l2
	bne	cas2		; if no nill pointer
	bcc	casex		
cas2	clc
	lda	tmp2l2		; adjust address in tmp2 with
	adc	base
	sta	pc
	lda	tmp2l2 + 1
	adc	base + 1
	sta	pc + 1
	jmp	interpr
casex	ldy	#$05		; test for otherwise
	lda	(pc),y
	sta	tmp2l2
	dey
	lda	(pc),y
	sta	tmp2l2 + 1
	clc
	adc	tmp2l2		; test for nil
	bne	cas2
	bcs	cas2
	lda	#msg006 / $0100
	ldx	#msg006 & $00FF
	jmp	string
	;
	; B7 MOV
	;
mov	jsr	setup2			; tmp2l2 is to and tmp3l2 is from
	ldy	#$00
	lda	(pc),y
	sta	tmp1l8 + 1
	ldx	#pc
	jsr 	incr
	lda	(pc),y
	sta	tmp1l8
	ldx	#pc
	jsr	incr			; pc is now next instruction
mov1	lda	(tmp3l2),y		;
	sta	(tmp2l2),y		; move the data
	ldx	#tmp2l2
	jsr	incr			; next from
	ldx	#tmp3l2
	jsr	incr			; next to
	ldx	#tmp1l8
	jsr	decr			; how many?
	lda	tmp1l8
	bne	mov1			; interpr
	lda	tmp1l8 + 1
	bne	mov1 
	jmp	interpr
	;
	; B8 DEC1
	;
dec1	jsr	setup1			; get operand in tmp2l2
	ldx	#tmp2l2
	jsr	decr			; minus 1
dec1a	ldy	tmp2l2			; setup for push of result
	lda	tmp2l2 + 1
	jsr	push2			; onto stack
	jmp	interpr
	;
	; B9 INC1
	;
inc1	jsr	setup1
	ldx	#tmp2l2
	jsr	incr
	jmp	dec1a			; push on stack
	;
	; BA LDCS
	;
ldcs	ldy	#$07
ldcs1	lda	(pc),y			; get char
	jsr push
	dey
	bpl	ldcs1			; if not 8 done interpr
	clc
	lda	#$08			; PC := pc + 8
	adc	pc
	sta	pc
	lda	pc + 1
	adc 	#$00
	sta	pc + 1
	jmp	tststk 			
	; 
	; BB CAP
	;
cap	ldx	#$00
	lda	(pc,x)
	sta	tmp2l2 + 1
	ldx	#pc
	jsr	incr			; pc := pc + 1
	lda	(pc,x)
	sta	tmp2l2
	ldx	#pc
	jsr	incr
	jmp	(tmp2l2)		; jump to new address
	;
	; BC LCA
lca	ldy	#$00
	lda	(pc),y			; nr of bytes as string length
	pha
	ldx	#pc
	jsr	incr
	lda	pc + 1
	ldy	pc			; address of string on stack
	jsr	push2
	clc
	pla
	adc	pc			; nr of bytes, add lenth to PC
	sta	pc
	lda	#$00
	adc	pc + 1
	sta	pc + 1
	jmp	tststk
	; 
	; BD CSP
	;
csp	ldy	#$00
	lda	(pc),y			; get csp number
	asl	a			; *2 for jump table index
	tay	
	ldx	#pc
	jsr	incr
	lda	csptab,y
	sta	jtabp			; indirect jump
	iny
	lda	csptab,y		; page nr
	sta	jtabp + 1
	jmp	(jtabp)			; jump to procedure
	;
	; standard procedure table
csptab	.word	wri			; write integer
	.word	wrc			; write character
	.word	wrs			; write string
	.word	rdi			; read integer
	.word	rln			; read end of line
	.word	rdc			; read character
	.word	wln			; write end of line
	.word	new			; new pointer
	.word	eof			; check for end of file
	.word	rst			; reset heap pointer
	.word	eln			; test if end of line
	.word	stp			; stop pascal program
	.word	odd			; check if number on stack is odd
	.word	rset			; reset eof boolean
	;
	; BE CUP1
	;
cup1	lda	mpsave			;
	sta	mp
	lda	mpsave + 1
	sta	mp + 1
	jmp	cupgo
	;
	; BF CUP2
	;
cup2	jsr	pull2			; complex call with function room
	sty	tmp2l2			; nr of stack to reserve
	clc
	lda	stack			; stack room
	adc	tmp2l2
	sta	tmp2l2
	lda	stack + 1
	adc	#$00
	sta	tmp2l2 + 1
	lda	tmp2l2
	clc
	adc	#$06			; offset for markstack
	sta	mp
	lda	tmp2l2 + 1
	adc	#$00
	sta	mp + 1
cupgo	ldy	#$00
	lda	(pc),y			; get procedure number
	pha				; save on stack
	ldx	#pc			; pc := pc + 1
	jsr	incr
	sec
	lda	mp			; get right place to store PC
	sbc	#$05
	sta	tmp2l2
	lda	mp + 1
	sbc	#$00
	sta	tmp2l2 + 1
	ldy	#$01			; index into mark package
	lda	pc + 1			; high part PC
	sta	(tmp2l2),y		; store in frame
	dey				; next ell
	lda	pc
	sta	(tmp2l2),y		; low part pc
	pla				; index
	asl	a				; *2 as index for jumptable
	tax				;
	lda	prcbuf,x		; 
	sta	pc
	inx
	lda	prcbuf,x		; pc from table
	sta	pc + 1
	jmp	interpr			; jump to new procedure
	;
	; C0 FIX21
	;
fix21	jsr	pull			; get operand
	tay				; put to correct position
	lda	#$00			; dummy zero
	jsr	push2			; for truncated functions
	jmp	interpr
	; 
	; C1 LNS
	;
lns	ldy	#$08
lnsx1	lda	#$08
	jsr	push
	dey				; interpr
	bne	lnsx1
	jmp	tststk
;
; end of m-code machine instructions
;
; Standard procedure handlers
;
; PROC 0 WRI
	;
wri	jsr	setup2			; tmp3 is length to write
	lda	tmp2l2 + 1		; tmp2 is intger to write
	sta	tmp1l8 + 1		; save for sign
	bpl	wri1			; not to be complemented
	eor	#$FF
	sta	tmp2l2 + 1
	lda	tmp2l2
	eor	#$FF			; lower byte
	sta	tmp2l2
	ldx	#tmp2l2
	jsr	incr			; form ones complement
wri1	ldy	#$05
wri1a	ldx	#$00
	stx	tmp1l8 + 2, y
	dey
	bpl	wri1a			; clear six cells
	jsr	cvdec			; convert to decimal in tmp1l8 + 3 - 7
	lda	tmp1l8 + 1
	bmi	wri2			; setup for output number
	ldy	#$20			; space
	sty	tmp1l8 + 1
	sty	tmp1l8 + 2
	lda	tmp1l8 + 3		; leading spaces
	bne	wri3
	sty	tmp1l8 + 3		; insert space
	lda	tmp1l8 + 4		; leading spaces
	bne	wri3
	sty	tmp1l8 + 4		; insert space
	lda	tmp1l8 + 5		; leading spaces
	bne	wri3
	sty	tmp1l8 + 5		; insert space
	lda	tmp1l8 + 6
	bne	wri3
	sty	tmp1l8 + 6		; insert space
	jmp	wri3
wri2	ldx	#$20			; so far for positive numbers
	stx	tmp1l8 + 1
	ldy	#$2D			; sign char
	sty	tmp1l8 + 2
	lda	tmp1l8 + 3
	bne	wri3
	stx	tmp1l8 + 2
	sty	tmp1l8 + 3
	lda	tmp1l8 + 4
	bne	wri3
	stx	tmp1l8 + 3
	sty	tmp1l8 + 4
	lda	tmp1l8 + 5
	bne	wri3
	stx 	tmp1l8 + 4
	sty	tmp1l8 + 5
	lda	tmp1l8 + 6
	bne	wri3
	stx	tmp1l8 + 5
	sty	tmp1l8 + 6
wri3	lda	tmp1l8 + 7
	ora	#$30			; adjust to ascii
	sta	tmp1l8 + 7
	lda	tmp1l8 + 6
	cmp	#$0A			; higher bits?
	bcs	wri4			; finished
	ora	#$30
	sta	tmp1l8 + 6
	lda	tmp1l8 + 5
	cmp	#$0A			; higher bits?
	bcs	wri4			; finished
	ora	#$30
	sta	tmp1l8 + 5
	lda	tmp1l8 + 4
	cmp	#$0A			; higher bits?
	bcs	wri4			; finished
	ora	#$30
	sta	tmp1l8 + 4
	lda	tmp1l8 + 3
	cmp	#$0A	
	bcs	wri4
	ora	#$30
	sta	tmp1l8 + 3
wri4	sec				; subtract length
	lda	tmp3l2
	sbc	#$06
	bmi	wri5			; less or equal?
	beq	wri5
	tay				; y is nr of leading spaces
wri4a	lda	#$20			; blank
	jsr 	wrt
	dec	tmp3l2
	dey
	bne	wri4a			; print blanks 
wri5	ldy	tmp3l2			; nr of bytes to write
	beq	wri6			; finished?
	sec
	lda	#tmp1l8 + 8		; address of first to print
	sbc	tmp3l2			; subtract length of string
	sta	tmp2l2			;
	ldx	#$00
	stx	tmp2l2 + 1		; high part zero, tmp3l8 is ZP
wri5a	lda	(tmp2l2,x)
	jsr	wrt
	inc	tmp2l2
	ldx	#$00
	dey
	bne	wri5a
wri6	jmp	interpr
;
; proc 1 WRC 
;
wrc	jsr	pull2			; nr of sapces
wrc1	dey
	beq	wrc2			; y =1 of length = 1
	bmi	wrc2			; length is zero
	lda	#$20			; space
	jsr	wrt			;
	jmp	wrc1			; do all spaces
wrc2	jsr	pull2			; get char and dummy
	tya	
	jsr	wrt
	jmp	interpr
;
; PROC 2 WRS
;
wrs	jsr	setup2			; tmp2l2 contains actual length
	sec				; and tmp2l2 actual length
	lda	tmp2l2
	sbc	tmp3l2			; spaces := actual - specified
	tay
	bpl	wrs1			; no spaces
	lda	tmp2l2
	beq	wrs4			; specified = 0 ?
	sta	tmp3l2			; overwrite actual
	bne	wrs2			; start printing
wrs1	beq	wrs2			; nr of spaces = 0?
	lda	#$20
	jsr	wrt
	dey
	bne	wrs1
wrs2	jsr	setup1			; address of string
	ldy	#$00			; y index into string
wrs3	lda	(tmp2l2),y		; get char
	jsr	wrt			; print char
	iny
	dec	tmp3l2			; decrement actual
	bne	wrs3
wrs4	jmp	interpr
	;
	; PROC 3 RDI
	;
	; this procedure is not checking overflow
	;
rdi	lda	#$00			; int = 0
	sta	tmp1l8
	sta	tmp1l8 + 1		;
	sta	tmp1l8 + 2		; sign = +
rdi1	jsr 	getch			; get a char
	cmp	#$20			; skip spaces
	beq	rdi1
	cmp	#$2b			; + sign?
	beq	rdi2
	cmp	#$2d			; - sign?
	bne	rdi3
	inc	tmp1l8 + 2		; set to minus
rdi2	jsr	getch			
rdi3	sec				; 
	sbc	#$30			; between 0 and 9 ?
	bmi	rdi4		
	cmp	#$0a			
	bcs	rdi4			
	sta	tmp1l8 + 3		; save number 
	jsr	mul10			; shift number in by adding + current number* 10		
	clc
	lda	tmp1l8
	adc	tmp1l8 + 3
	sta	tmp1l8
	lda	tmp1l8 + 1
	adc	#$00			; add to word
	sta	tmp1l8 + 1
	jmp	rdi2			; get next part of integer
rdi4	jsr	setup1				
	ldy	#$00
	lda	tmp1l8	+ 2		; sign flag?
	beq	rdi5			; complemnet
	lda	tmp1l8
	eor	#$FF			
	sta	tmp1l8
	lda	tmp1l8 + 1
	eor	#$FF
	sta	tmp1l8 + 1
	ldx	#tmp1l8
	jsr	incr
rdi5	lda	tmp1l8
	sta	(tmp2l2),y
	iny
	lda	tmp1l8 + 1
	sta	(tmp2l2),y
	jmp	interpr
	;
	; PROC 4 RLN
	;
rln	lda	eolb			; eol set?
	bne	rln1			; clear
	jsr	getch			; skip until eoln
	jmp	rln
rln1	lda	#$00			; clear eoln
	sta	eolb
	jmp	interpr
	;
	; PROC 5 RDC
	;
rdc	jsr	setup1
	jsr 	getch
	ldy	#$00
	sta	(tmp2l2),y		; store char
	jmp	interpr
	;
	; PROC 6 WLN
wln	lda	#$80			; why?
	jsr	crlf
	jmp	interpr
	;
	; PROC 7 NEW
	;
new	jsr	setup2			; tmp3 length of room wanted
	ldy	#$00			; tmp2	address to save old HP
	lda	hp
	sta	(tmp2l2),y		; put hp in frame
	clc
	adc	tmp3l2			; add number of cells to hp
	sta	hp
	lda	hp + 1
	iny	
	sta	(tmp2l2),y
	adc	tmp3l2 + 1
	sta	hp + 1	
	jmp	tststk
	;
	; PROC 8 EOF
	;
eof	ldy	eofb			; end of file boolean
	lda	#$00
	jsr	push2
	jmp	tststk
	;
	; PROC 9 RST
	;
rst	jsr	pull2			; get old heap pointer
	sta	hp + 1
	sty	hp
	jmp	interpr 
	;
	; PROC A ELN
	;
eln	ldy	eolb			; get EOLN boolean
	lda	#$00
	jsr	push2			; push EOLN boolean on stack
	jmp	tststk
	;
	; PROC B STP
	;
stp	lda	#msg002 / $0100
	ldx	#msg002 & $00FF
	jmp	string			; Print End pascal and stop
	;
        ; TODO: new standard procedures 
;      12 : ODDM ;
;      13 : RSFRWW  ;
;      14 : RSFRWW  ;
;      15 : STT  ;
;      16 : CLS         
	; routines
	;
getch	jsr	rdt			; read from input
	cmp	#$20			; printable?
	bcc	getch2
	cmp	#$7F
	beq	getch			; ignore rubout
	ldy	#$00			; no EOLN flag
getch1	sty	eolb
	rts
getch2	cmp	#$0D			; CR, then fake space and EOLN true
	bne	getch3			; ignore other control chars except OF
	lda	#$20
	ldy	#$01
	bne	getch1
getch3	cmp	#$17			; CTRL/Z is EOF
	bne	getch
	ldy	#$01
	sty	eofb			; set eof boolean
	lda	#$20			; fake space
	bne	getch1			; return with eol true also
	;
	; PROC C ODD
	;
	; why push and pull, do it on the stack is faster?
	;
odd	jsr	pull2			; get integer from stack
	tya				; bit 0?
	and	#$01			; pos or neg?
	tay	
	lda	#$00			; pos  = 1
	jsr	push2			; push boolean on stack
	jmp	interpr
	;
	; PROC D RSET
	;
rset	lda	#$00			; false
	sta	eofb
	jmp	interpr
	;
	; MUL10 multiply tmp1l8 by 10
mul10	asl	tmp1l8
	rol	tmp1l8 + 1
	lda	tmp1l8
	sta	tmp1l8 + 4
	lda	tmp1l8 + 1
	sta	tmp1l8 + 5
	asl	tmp1l8 + 4
	rol	tmp1l8 + 5
	asl	tmp1l8 + 4
	rol	tmp1l8 + 5		; * 8
	clc
	lda	tmp1l8			; add 2 times and
	adc	tmp1l8 + 4
	sta	tmp1l8
	lda	tmp1l8 + 1
	adc	tmp1l8 +5
	sta	tmp1l8 + 1
	rts
	;
	; CVDEC convert hex to decimal
	; results in
	; tmp1l8 + 3  10000 count 
	; tmp1l8 + 4  1000 count
	; tmp1l8 + 5  100 count
	; tmp1l8 + 6  10 count
	; tmp1l8 + 7  rest
cvdec	sec
	lda	tmp2l2
	sbc	#$10			; subtract 10000
	pha
	lda	tmp2l2 + 1
	sbc	#$27
	bcc	cvdec2			; still larger
	sta	tmp2l2 + 1		
	pla
	sta	tmp2l2
	inc 	tmp1l8 + 3		; increment 10000 count
	bne	cvdec			; interpr 
cvdec2	pla
cvdec3	sec
	lda	tmp2l2			; subtract 1000's
	sbc	#$E8			
	pha
	lda	tmp2l2 + 1
	sbc	#$03
	bcc	cvdec4
	sta	tmp2l2 + 1
	pla
	sta	tmp2l2
	inc	tmp1l8 + 4		; incremnent 1000 count
	bne	cvdec3			; interpr
cvdec4	pla
cvdec5	sec
	lda	tmp2l2			; subtract 100's
	sbc	#$64			
	pha
	lda	tmp2l2 + 1
	sbc	#$00
	bcc	cvdec6
	sta	tmp2l2 + 1
	pla
	sta	tmp2l2
	inc	tmp1l8 + 5		; incremnent 100 count
	bne	cvdec5			; interpr
cvdec6	pla				; 10's
cvdec7	sec
	lda	tmp2l2			; subtract 100's
	sbc	#$0A			
	bcc	cvdec8
	sta	tmp2l2
	inc	tmp1l8 + 6		; incremnent 10 count
	bne	cvdec7			; interpr
cvdec8	lda	tmp2l2
	sta	tmp1l8 + 7
	rts
	;
	; FORIN initialize FOR interpr
	;
forin	ldy	#$05
	lda	(stack),y
	sta	tmp3l2 			; initial interpr coount
	iny
	lda	(stack),y
	sta	tmp3l2 + 1
	iny
	lda	(stack),y		; initial interpr count to cell
	sta	tmp2l2
	iny
	lda	(stack),y
	sta	tmp2l2 + 1
	ldy	#$00			; initial interpr count to cell
	lda	tmp3l2 
	sta	(tmp2l2),y		; store initial count in cell
	iny
	lda	(stack),y		; test for 1 or 2 bytes
	and	#$01
	beq	forin1			; one byte?
	lda	tmp3l2 + 1
	sta	(tmp2l2),y		; save upper byte
forin1	rts
	;
	; MPLY multiply two integers
	; call mdset first to setup 
mply	ldy	#$0F
mply1	lsr	tmp1l8 + 3		; get lsbit
	ror	tmp1l8 + 2
	bcc	mply2			; more?
	clc
	lda	tmp1l8 
	adc	tmp1l8 + 4
	sta 	tmp1l8 + 4
	lda	tmp1l8 + 1
	adc	tmp1l8 + 5
	sta 	tmp1l8 + 5
mply2	asl	tmp1l8
	rol	tmp1l8 + 1
	dey
	bne	mply1			; interpr
	rts
	;
	; MDSET setup for multiply/divide
	;
mdset	jsr	pull2			; get divisor/multiplicant
	sty	tmp1l8			; in tmp1l8 word
	sta	tmp1l8 + 1
	jsr	pull2			; get divedent/multiplier
	sty	tmp1l8 + 2		; in tmp1l8 + 2 word
	sta	tmp1l8 + 3
	lda	#$00			; clear rest of tmp1l8 space
	sta	tmp1l8 + 7		; no of shifts in multiply
	sta	tmp1l8 + 6		; end sign 1 = neg, 2 is pos
	sta	tmp1l8 + 4		; clear end result
	sta	tmp1l8 + 5		; in tmp1l8 + 4 word
	lda	tmp1l8 + 1		; test sign
	bpl	mdset1
	eor	#$FF			; convert to one's complement
	sta	tmp1l8 + 1
	lda	tmp1l8
	eor	#$FF
	sta	tmp1l8
	ldx	#$tmp1l8
	jsr	incr
	inc	tmp1l8 + 6
mdset1	lda	tmp1l8 + 3		; test sign
	bpl	mdset2
	eor	#$FF			; convert to one's complement
	sta	tmp1l8 + 3
	lda	tmp1l8 + 2
	eor	#$FF
	sta	tmp1l8 + 2
	ldx	#$tmp1l8 + 2
	jsr	incr
	inc	tmp1l8 + 6		; adjust end sign
mdset2	rts
	;
	; divide integers 
	; multiple subtraction
	; call mdset first to setup 
divide	ldy	#$01			; do it at least once 
div1	sec	
	lda	tmp1l8 + 2
	sbc	tmp1l8
	lda	tmp1l8 + 3
	sbc	tmp1l8 + 1
	bcc	div2			; divisor is larger than divent
	iny
	asl	tmp1l8
	rol	tmp1l8 + 1
	cpy	#$10			; more than 16 times?
	bne	div1
	ldx	#msg008 & $00FF		; divison by zero, stop
	lda	#msg008 / $0100
	jmp	string
div2	sty	tmp1l8 + 7
div3	sec
	lda	tmp1l8 + 2
	sbc	tmp1l8
	pha				; save result
	lda	tmp1l8 + 3
	sbc	tmp1l8 + 1
	php				; save status
	rol	tmp1l8 + 4
	rol	tmp1l8 + 5
	plp
	bcc 	div4
	sta	tmp1l8 + 3
	pla	
	sta	tmp1l8 + 2
	jmp	div5
div4	pla
div5	lsr	tmp1l8 + 1
	ror	tmp1l8
	dec	tmp1l8 + 7
	bne	div3
	rts
	;
	; COMPAR 
	;
compar	jsr	setup2			; tmp3 is right side of compare
	ldy	#$00
	lda	(pc),y			; no to compare
	sta	tmp1l8 + 1
	ldx	#pc
	jsr	incr
	lda	(pc),y
	sta	tmp1l8
	ldx	#pc
	jsr	incr
compa1	sec
	lda	(tmp2l2),y
	sbc	(tmp3l2),y
	beq	compa4			; if still the same check end
	bpl	compa2			; if tmp2 smaller
	dey
	bne	compa3
compa2	iny
compa3	sty	tmp1l8			; leave result
	rts
compa4	ldx	#tmp2l2
	jsr	incr
	ldx	#tmp3l2
	jsr	incr			; next word to compare
	ldx	#tmp1l8			; length to compare
	jsr	decr
	lda	tmp1l8
	bne	compa1			; done?
	lda	tmp1l8 + 1
	bne	compa1
	sty	tmp1l8 			; leave result
	rts
;
; character in/out
;
; Read one char from TTY without the KIM hardware echo
;
rdt	sty	ytmp
        lda SBD         ;  set tty bit PB0 to 0 
        and #$FE  
        sta SBD         ; 
        jsr ttyin       ; get character from input
        pha ; save
        lda SBD         ; set tty bit PB0 back 
        ora #$01 
        sta SBD 
        pla             ; restore received character        
	ldy	ytmp
	rts
; 
; Write one char to TTY
;
wrt	sty	ytmp	
	jsr	ttyout
	ldy	ytmp
	rts
;
; CRLF on output 
;
crlf   	lda	#CR
	jsr	wrt
	lda	#LF
	jsr	wrt
  	rts
;
; messages
;
msg005	.byte	" Out of stack", $0D
msg006	.byte	" Case index",$0D
msg007	.byte	" Not implemented", $0D
msg008	.byte	" Div by zero", $0D
msg003
msg002	.byte   "Pascal-M", $0D	;
;
	.end