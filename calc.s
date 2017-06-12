linksize:	EQU 5
stacksize:	EQU 5

%macro prtmsg 1
	push	%1
	call	printf
	add		esp, 4
%endmacro

%macro malloclink 0
	push	linksize
	call 	malloc
	add 	esp, 4		; get the malloc number out
%endmacro

%macro calc_push 1
	push 	edx
	mov		edx, [nums_on_stack]
	mov 	[calc_stack + edx*4], %1
	add 	edx, 1
	mov		[nums_on_stack], edx
	pop 	edx
%endmacro

%macro calc_pop 1
	push 	edx
	mov		edx, [nums_on_stack]
	dec 	edx
	mov 	%1, [calc_stack + edx*4]
	mov 	[nums_on_stack], edx
	pop 	edx
%endmacro

%macro calc_peek 1
	push 	edx
	mov 	edx, [nums_on_stack]
	dec 	edx
	mov 	%1, [calc_stack + edx*4]
	pop 	edx
%endmacro

%macro  dbg_reg 1
	cmp 	byte [dbgmode], 0
	je  	%%nodbg
	pushad
	push %1
	push debugformat
	call printf
	add esp, 8
	popad
%%nodbg:
%endmacro

%macro inc_op 0
	push 	eax
	mov 	eax,[op_counter]
	inc 	eax
	mov 	[op_counter],eax
	pop 	eax
%endmacro

%macro funcstart 0
	push	ebp
	mov		ebp, esp
%endmacro

%macro funcend 0
	mov		esp, ebp
	pop		ebp
	ret
%endmacro

%macro cmp_and_call 4
	cmp 	byte [%1], %2
	jne 	%%neq
	call 	%3
	cmp 	eax, 0
	je 		%%endcall
	prtmsg	eax
%%endcall:
	xor 	eax, eax
	jmp 	%4
%%neq:
%endmacro

section .rodata
	nl:				DB 	10,0
	outputprefix:	DB 	">> ",0
	inputprefix:	DB 	">>calc: ",0
	hexformat:		DB 	"%02x",0
	decformat: 		DB 	"%d",0
	debugformat: 	DB 	"DBG@ requested register: %x", 10, 0
	strformat:		DB 	"%s", 10, 0
	err_overflow:	DB	"Error: Operand Stack Overflow", 10, 0
	err_input:		DB	"Error: Illegal Input", 10, 0
	err_stack:		DB 	"Error: Insufficient Number of Arguments on Stack", 10, 0
	err_exp:		DB 	"Error: exponent too large", 10, 0

	dbg_mode:		DB 	"running in debug mode ", 10, 0

section .data
	op_counter:		DD	0
	nums_on_stack:	DD	0
	dbgmode: 		DB 	0

section .bss
	buffer:			resb 80
	calc_stack:		resb stacksize*4

section .text
	align 16
	global main
	extern exit
	extern printf
	extern fprintf
	extern malloc
	extern free
	extern fgets
	extern stderr
	extern stdin
	extern stdout
	
main:
	push	ebp
	mov		ebp, esp
	pushad

	mov 	eax, [ebp + 8]
	mov 	ebx, [ebp + 12]
	cmp 	eax, 1
	jle 	.calcloop
	mov 	ecx, [ebx + 4]
	cmp 	word [ecx], "-d"
	jne 	.calcloop
	mov 	byte [dbgmode], 1
	push 	dbg_mode
	call 	printf
	add 	esp, 4

.calcloop:
	call 	my_calc
	cmp 	eax, 0
	je 		.calcloop

.end_main:
	push 	dword [op_counter]
	push 	decformat
	call 	printf
	add 	esp, 8

	push 	nl
	call 	printf
	add 	esp, 4

	popad
	mov		esp, ebp
	pop		ebp
	push	0
	call	exit

my_calc:
	funcstart

	prtmsg	inputprefix

	push	dword [stdin]	;---------------
	push	dword 80		;
	push	dword buffer	; read input
	call 	fgets			;
	add		esp, 12			;---------------
	
	mov 	eax, buffer

	cmp_and_call	eax, 'p', popandprint_op, .end_calc
	cmp_and_call 	eax, 'd', duplicate_op, .end_calc
	cmp_and_call 	eax, '+', addition_op, .end_calc
	cmp_and_call 	eax, 'r', shright_op, .end_calc
	cmp_and_call 	eax, 'l', shleft_op, .end_calc
	
	cmp 	byte [eax], 10
	jne  	.quitcheck
	xor		eax, eax, 
	jmp 	.end_read
.quitcheck:
	cmp		byte [eax], 'q'
	je  	.quit

	call 	readnum
	cmp 	eax, 0
	je		.end_read
	prtmsg 	eax
	xor 	eax, eax
 .end_read:
	jmp 	.end_calc

.quit:
	mov 	eax, -1
.end_calc:
 	funcend


readnum:
	funcstart

	cmp		dword [nums_on_stack], stacksize
	jl		.startreading
	mov 	eax, err_overflow
	jmp		.end_readnum

.startreading:
	malloclink				; new link on eax
	xor		ecx, ecx		; zero the counter

.goto_endofbuff:
	cmp		byte [buffer + ecx], 0
	je		.start
	cmp		byte [buffer + ecx], 10
	je		.start
	inc ecx
	jmp .goto_endofbuff

.start:
	push	eax
	dbg_reg eax
	
.nextlink:
	xor		ebx, ebx					; zero b register
	mov 	byte bl, [buffer + ecx - 1]	; next byte (right to left)
	sub		byte bl, '0'				; get the numeric value
	mov		byte [eax], bl				; save the number in the link
	dec 	ecx
	cmp		ecx, 0
	je		.finalizelink
	
	mov		byte dl, [buffer + ecx - 1]	; get second byte
	sub		byte dl, '0'				; get the numeric value
	shl		byte dl, 4					; move the number to the first nibble
	add 	byte bl, dl
	mov		byte [eax], bl
	dec		ecx
	
.finalizelink:
	cmp		ecx, 0
	je		.finalizenum
	
	push 	ecx
	push	eax						; save last link
	malloclink						; new link on eax
	pop		ebx						; retreive the last link
	pop		ecx
	mov		dword [ebx + 1], eax	; bind the link
	jmp 	.nextlink

.finalizenum:
	mov 	dword [eax + 1], 0		; null trm the last link
	pop 	eax
	dbg_reg eax
	calc_push eax
	xor 	eax, eax

.end_readnum:
	funcend

shright_op:

	

shleft_op:
	funcstart
	calc_pop 	ecx				;pop exponent
	calc_pop 	ebx				;pop number to multiply
	xor 	eax,eax
	push 	ecx
.compute_exponent:
	add 	byte al, [ecx]		;sum the exponent
	daa
	cmp 	byte al,99			;check if greater them 99
	jg 		.unvalid_input
	cmp 	dword[ecx+1],0
	mov 	dword ecx,[ecx+1]	;move to the next pointer in exponent list
	jne 	.compute_exponent

.start_shiftl_op:
	pop 	ecx
	push 	eax					;push the computed exponent
	calc_push 	ebx
	call 	duplicate_op		;duplicate number to multiply
	cmp 	byte[eax],0
	jne 	.duplicate_failed
	call 	addition_op 		;multiply by 2
	cmp 	byte[eax],0
	jne 	.addition_failed
	pop 	eax
	dec 	eax  				;decrease counter by 1
	cmp 	eax, 0				;check if exponent is zero
	je 		.end_shiftl
	jmp 	.start_shiftl_op

.unvalid_input:
	pop 	ecx
	calc_push	ebx				;return the number to stack
	calc_push 	ecx				;return the exponent to stack
	mov 	eax,err_exp
	prtmsg 		eax
	jmp 	.end_shiftl

.duplicate_failed:
	prtmsg 		eax
	jmp		.end_shiftl

.addition_failed:
	prtmsg 		eax

.end_shiftl:
	xor 	eax, eax
	funcend



duplicate_op:
	funcstart

	cmp		dword [nums_on_stack], stacksize
	jl		.checkunderflow
	mov 	eax, err_overflow
	jmp		.end_duplicate

.checkunderflow:
	cmp 	dword [nums_on_stack], 0
	jg 		.continue_dup
	mov 	eax, err_stack
	jmp 	.end_duplicate

.continue_dup:
	malloclink		; new link on eax

	calc_pop ebx
	push 	eax
	push 	ebx

.copy_loop:		; eax - destination
				; ebx - source
	xor 	ecx, ecx 		; zero the c register
	mov		byte cl, [ebx]	; get the first byte to copy
	mov		byte [eax], cl	; copy the byte

	cmp		dword [ebx + 1], 0	; check if last byte on the chain
	jz		.finalize_duplicate

	push 	ebx 		; save source
	push 	eax			; save destination
	malloclink			; new link on eax

	pop 	ecx				; last destination link
	pop 	ebx				; last sourse link

	mov 	dword ebx, [ebx + 1]	; advance the source link
	mov 	dword [ecx + 1], eax	; the old link now points to the new allocated link
	jmp		.copy_loop
	
.finalize_duplicate:
	mov 	dword [eax + 1], 0	; end with null terminator	
	pop 	eax
	pop 	ebx
	calc_push eax
	calc_push ebx
	inc_op
	xor 	eax, eax

.end_duplicate:
	funcend

popandprint_op:
	funcstart

	cmp		dword [nums_on_stack], 0
	jg		.popit
	mov 	eax, err_stack
	jmp		.end_print
.popit:
	calc_pop	eax
	push	eax					; save the first node pointer
	xor 	ecx, ecx			; zero the counter
.pushnode:
	xor 	ebx, ebx			; zero the register
	mov 	byte bl, [eax]		; get the num byte
	push 	ebx					; push number to stack
	inc		ecx					; counter++
	mov 	dword eax, [eax + 1]; get next node
	cmp		eax, 0				; null trm check
	jne		.pushnode
	
	push 	ecx
	prtmsg 	outputprefix		; print the prefix
	pop		ecx

.nopadding:
	cmp		ecx, 0				; if we're in this spot and ecx is 0 then its the number 0
	jne 	.nopadding_cont
	push 	0
	push 	decformat
	call	printf				; print the number 0
	add		esp, 8
	jmp		.finishprint		; finish the printing segment
	
.nopadding_cont:
	pop 	ebx					; by this point ecx is not 0, so we pop a number
	dec 	ecx
	cmp		ebx, 0				; if the number is 0, then it's a padding
	je		.nopadding			; 	so we ignore it and continue looking for more paddings
	cmp 	ebx, 9				; if the number is lower or equal to 9
	jle		.printsingledigit	; 	then it's a single digit number
	push 	ebx					; otherwise put it back in and go on to normal printing
	inc		ecx
	jmp		.printnode

.printsingledigit:
	pushad
	push	ebx
	push	decformat
	call	printf				; print a single digit number
	add		esp, 8
	popad
	cmp		ecx, 0				; if there are more numbers, go on to normal printing
	je		.finishprint
	
.printnode:
	pop 	ebx
	dec 	ecx
	pushad
	push	ebx
	push 	hexformat
	call 	printf		; print both nibbles
	add 	esp, 8
	popad
	cmp 	ecx, 0		; if there are more numbers, continue with normal printing
	jg 		.printnode
	
.finishprint:
	prtmsg	nl			; new line
	call 	freelink 	; the first link of the number is now on TOS, so we need to deallocate it
	add 	esp, 4
	inc_op
	xor 	eax, eax

.end_print:
	funcend
	
addition_op:
	funcstart
	mov 	ebx,[nums_on_stack]
	cmp 	ebx,1			;check for legal numbers on stack for op
	jg 		.start_addition
	mov 	eax, err_stack
	jmp 	.end_addition

.start_addition:
	malloclink
	calc_pop	ebx
	calc_pop	ecx
	push 	ebx
	push 	ecx
	mov 	edx,eax
	push 	eax
	clc					; clear carry flag
	pushfd
.addition_loop:
	xor 	eax, eax
	mov 	byte al,[ebx]
	popfd
	adc 	byte al,[ecx]
	daa
	pushfd
	mov 	byte [edx],al
	cmp 	dword [ecx+1],0
	je 		.only_first_num_left
	cmp 	dword [ebx+1],0
	je 		.only_second_num_left
	mov 	ebx,[ebx+1]
	mov 	ecx,[ecx+1]
	push 	ebx
	push 	ecx
	push 	edx
	malloclink
	pop  	edx
	pop 	ecx
	pop 	ebx
	mov 	dword[edx+1],eax
	mov 	edx,eax
	jmp 	.addition_loop	

.only_first_num_left:
	cmp 	dword [ebx+1],0
	je 		.finalize_addition
	mov 	ebx,[ebx+1]
	push 	ebx
	push 	edx
	malloclink
	pop 	edx
	pop 	ebx
	mov 	dword[edx+1],eax		
	mov 	edx,eax
	xor 	eax, eax
	mov 	byte al, [ebx]
	popfd
	adc 	byte al, 0
	daa
	pushfd
	mov 	byte [edx], al
	jmp 	.only_first_num_left 

.only_second_num_left:
	cmp 	dword [ecx+1],0
	je 		.finalize_addition
	mov 	ecx,[ecx+1]
	push 	ecx
	push 	edx
	malloclink
	pop 	edx
	pop 	ecx
	mov 	dword[edx+1],eax
	mov 	edx,eax
	xor 	eax, eax
	mov 	byte al, [ecx]
	popfd
	adc 	byte al, 0
	daa
	pushfd
	mov 	byte [edx], al
	jmp 	.only_second_num_left

.carrylink:
	push 	edx
	malloclink
	pop 	edx
	mov 	dword[edx+1],eax
	mov 	edx,eax
	mov 	byte[edx],1
	clc
	pushfd

.finalize_addition:
	popfd
	jc  	.carrylink
	mov 	dword[edx+1],0
	pop 	eax
	calc_push 	eax
	call 	freelink
	pop		eax
	call 	freelink
	add 	esp, 4
	xor 	eax, eax

	inc_op

.end_addition:	
	funcend
	
freelink:		;;;;;;;;;;;;;;;;;; recursive function to free the linkedlist
	funcstart
	pushad
	
	mov		dword eax, [ebp + 8]	; get arg1
	cmp 	dword [eax + 1], 0		; compare pointer to next link
	je 		.freeandfinish
	push	dword [eax + 1]
	call 	freelink				; recursive call to next link
	add 	esp, 4
	
.freeandfinish:			; once here, there is no son on the heap
	push	dword [ebp + 8]	
	call 	free		; free the current link
	add		esp, 4
	popad
	xor 	eax, eax
	funcend