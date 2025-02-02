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

section .bss ; BLOCK STARTED BY SYMBOL -> used for uninitialized data
	;; Memory is allocated at runtime, not stored in the binary
	;; Reduces executable size by avoiding pre-filled zeros
  sockfd resq 1       ; Reserve space for socket file descriptor
  server_addr resb 16 ; Reserve space for sockaddr_in struct


section .text
    global _start       ; entry point for the linker
		extern htons

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

    mov rdi, [rsp+16]   ; Get pointer to first argument (listen_port)
    call atoi
    mov r8, rax         ; Store listen_port in r8

    mov rdi, [rsp+32]   ; Get pointer to third argument (backend_port)
    call atoi
    mov r9, rax         ; Store backend_port in r9

		;; SOCKET CREATION
		mov rdi, 2 ;; AF_INET (IPv4)
		mov rsi, 1 ;; SOCK_STREAM
		mov rdx, 0 ;; protocol
		mov rax, 41 ;; socket() syscall

		syscall

		test rax, rax
		js socket_failed 

		mov [sockfd], rax   ; Save socket file descriptor

		;; prepare sockaddr_in struct
		xor rax, rax
		mov [server_addr], rax
		mov [server_addr+8], rax

		mov word [server_addr], 2 ; sin_family = AF_INET
		mov dword [server_addr+4], 0 ; sin_addr.sin_addr = INADDR_ANY

    mov rdi, r8         ; listen_port
    call htons
    mov [server_addr+2], ax  ; store converted port

		;; bind socket
		mov rdi, [sockfd]
		lea rsi, [server_addr]
		mov edx, 16 ;; sizeof(struct sockaddr_in)
		mov rax, 49 ;; bind() syscall

		syscall
		test rax,rax
		js bind_failed

		;; listening to connections
    mov rdi, [sockfd]   ; sockfd
    mov rsi, 10         ; backlog = 10
    mov rax, 50         ; syscall: listen
    syscall
    test rax, rax
    js listen_failed

    mov rdi, 1          ; stdout
    mov rsi, msg_server_started
    call print_string

    mov rdi, r8         ; listen_port
    call print_number

    mov rdi, 1
    mov rsi, newline
    call print_string

    mov rdi, 0         ; exit status 0
    mov rax, 60        ; syscall: exit
    syscall

;; socket failed
socket_failed:
    mov rdi, 1
    mov rsi, msg_failed_socket
    call print_string
    jmp exit_error

bind_failed:
		mov rdi, 1
		mov rsi, msg_failed_bind
		call print_string
		jmp exit_error

listen_failed:
		mov rdi, 1
		mov rsi, msg_failed_listen
		call print_string
		jmp exit_error

exit_error:
    mov rdi, 1
    mov rax, 60
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

;; printing helper functions
print_string:
    mov rdx, -1
    xor al, al
find_len:
    inc rdx
    cmp byte [rsi+rdx], al
    jne find_len

    mov rax, 1
    syscall
    ret

print_number:
    push rbp
    mov rbp, rsp
    sub rsp, 32         ; Allocate stack space for local variables
    
    mov rax, rdi        ; Number to print is in rdi
    mov rbx, 10         ; Divisor
    xor rcx, rcx        ; Counter for number of digits
    
convert_loop:
    xor rdx, rdx        ; Clear rdx before division
    div rbx             ; Divide rax by 10
    add dl, '0'         ; Convert remainder to ASCII
    push rdx            ; Save digit
    inc rcx             ; Increment digit counter
    test rax, rax       ; Check if quotient is 0
    jnz convert_loop
    
print_digits:
    test rcx, rcx       ; Check if we have digits to print
    jz print_done
    
    pop rdi             ; Get digit
    push rcx            ; Save counter
    
    mov [rsp-8], rdi    ; Store digit in stack
    mov rdi, 1          ; stdout
    lea rsi, [rsp-8]    ; Address of digit
    mov rdx, 1          ; Length
    mov rax, 1          ; sys_write
    syscall
    
    pop rcx             ; Restore counter
    dec rcx             ; Decrement counter
    jmp print_digits
    
print_done:
    mov rsp, rbp
    pop rbp
    ret