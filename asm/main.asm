; main.asm

section .data
    msg_three_arguments_rec db "there are 3 arguments, move on", 10 ; 10 is the newline
    msg_failed_to_get_three_arguments db "usage: ./main <listen_port> <backend_host> <backend_port>", 10

    len_success_three_args equ $ - msg_three_arguments_rec ; calculate length of msg_three_arguments_rec
    len_failed_to_get_three_arguments equ $ - msg_failed_to_get_three_arguments

		;; server messages
		msg_failed_socket db "failed to create socket", 10
		msg_failed_bind db "failed to bind socket", 10
		msg_failed_listen db "failed to listen", 10
		msg_server_started db "server started on port ", 0

		;; utils
		newline db 10, 0

section .text
    global _start       ; entry point for the linker

_start:
    mov rax, [rsp]      ; rax == argc ; rsp == argv
    cmp rax, 4          ; there should be 4 arguments (program name + 3 arguments)
    je process_args     ; if there are 4 arguments, jump to process_args

    ;; not enough arguments
    mov rdi, 1                          ; exit status: 1
    mov rsi, msg_failed_to_get_three_arguments ; pointer to error message
    mov rdx, len_failed_to_get_three_arguments   ; length of error message
    mov rax, 1                          ; syscall: write (stdout)
    syscall

    mov rdi, 1      ; exit status: 1
    mov rax, 60     ; syscall: exit
    syscall

process_args:
    ; at this point, we have exactly 3 arguments (excluding the program name).
    ; load pointers to each argument from the stack:
    ; [rsp+8]  -> argv[0] (program name)
    ; [rsp+16] -> argv[1] (first argument)
    ; [rsp+24] -> argv[2] (second argument)
    ; [rsp+32] -> argv[3] (third argument)

    mov rbx, [rsp+8]    ; rbx now points to argv[1] (first argument)
    mov rcx, [rsp+16]   ; rcx now points to argv[2] (second argument)
    mov rdx, [rsp+24]   ; rdx now points to argv[3] (third argument)

    mov rdi, rbx       ; Convert listen_port to int
    call atoi
    mov r8, rax        ; Store in r8

    mov rdi, rdx       ; Convert backend_port to int
    call atoi
    mov r10, rax       ; Store in r10


    mov rdi, 0         ; exit status 0
    mov rax, 60        ; syscall: exit
    syscall

;; ATOI 
atoi: 
	;; this is used to efficiently reset rax to 0 as using XOR with itself always returns 0
	;; mov rax, 0 is 7 bytes, while xor rax,rax is 2 bytes
	;; this is faster as well
	xor rax,rax
	movzx rcx, byte [rdi]  ; Load first character
	test  rcx, rcx
	je    atoi_done     ; If empty string, return 0


atoi_loop:
	movzx rcx, byte [rdi] ;; loading next byte into rcx and zero extend 
	test  rcx, rcx ;; if rcx is 0 (null terminator), we are done
	je atoi_done

	cmp   rcx, '0'
	jl atoi_done ;; if char is less than '0', we are done
	cmp   rcx, '9'
	jg atoi_done ;; if char is greater than '9', we are done

	sub   rcx, '0'     ; now rcx holds the numeric value (0-9)
  ; multiply the current result by 10 and add the new digit:
  imul  rax, rax, 10
  add   rax, rcx
  inc   rdi          ; move pointer to next character
  jmp   atoi_loop

atoi_done:
	ret