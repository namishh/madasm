; main.asm

section .data
    msg_three_arguments_rec db "there are 3 arguments, move on", 10 ; 10 is the newline
    msg_failed_to_get_three_arguments db "usage: ./main <listen_port> <backend_host> <backend_port>", 10

    len_success_three_args equ $ - msg_three_arguments_rec ; calculate length of msg_three_arguments_rec
    len_failed_to_get_three_arguments equ $ - msg_failed_to_get_three_arguments

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

    mov rbx, [rsp+16]    ; rbx now points to argv[1]
    mov rcx, [rsp+24]    ; rcx now points to argv[2]
    mov rdx, [rsp+32]    ; rdx now points to argv[3]

    mov rdi, 0         ; exit status 0
    mov rax, 60        ; syscall: exit
    syscall

;; ATOI 
atoi: 
	;; this is used to efficiently reset rax to 0 as using XOR with itself always returns 0
	;; mov rax, 0 is 7 bytes, while xor rax,rax is 2 bytes
	;; this is faster as well
	xor rax,rax
atoi_done:
	ret