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
		msg_server_started db "reverse proxy listening on port ", 0

		msg_failed_accept db "failed to accept connection", 10
		msg_failed_recv db "failed to receive data", 10
		msg_backend_connect_failed db "failed to connect to backend", 10

		;; utils
		newline db 10, 0

		;; constants
    AF_INET equ 2
    IP_ADDR_LEN equ 4


section .bss ; BLOCK STARTED BY SYMBOL -> used for uninitialized data
	;; Memory is allocated at runtime, not stored in the binary
	;; Reduces executable size by avoiding pre-filled zeros
  sockfd resq 1       ; Reserve space for socket file descriptor
  server_addr resb 16 ; Reserve space for sockaddr_in struct
	client_addr resb 16         ; Reserve space for client sockaddr_in struct
  client_addr_len resd 1      ; Reserve space for client address length
  client_fd resq 1            ; Reserve space for client file descriptor
  backend_fd resq 1           ; Reserve space for backend file descriptor
	buffer resb 4096  ; Reserve 4096 bytes for the buffer
	backend_addr resb 16  ; Reserve 16 bytes for the backend sockaddr_in structure

  hostent_struct resb 32       ; Hostent structure
  h_addr_list resq 2           ; Address list
  ip_addr resd 1              ; IP address storage
  temp_buffer resb 16         ; Temporary buffer for parsing


section .text
    global _start       ; entry point for the linker
		global htons
		extern gethostbyname

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

		test rax, rax ;; Performs a bitwise AND but only sets flags, doesn't store result. this is a common way to check if a value is 0
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
		lea rsi, [server_addr] ;; (Load Effective Address) - Calculates an address and puts it in the destination
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
    
		jmp server_loop

server_loop:
	;; accepting incoming connections 
	mov dword [client_addr_len], 16 ;; sizeof(struct sockaddr_in)
	mov rdi, [sockfd] 
	lea rsi, [client_addr]
	lea rdx, [client_addr_len]
	mov rax, 43 ;; accept() syscall
	syscall 

	test rax, rax
	js accept_failed

  mov [client_fd], rax  ; store the new client socket descriptor

	;; recieve data from the client
	lea rdi, [buffer]
	mov rsi, [client_fd]
	mov rdx, 4096
	mov rax, 45 ;; recv() syscall
	syscall

	test rax, rax
	js recv_failed

	;; connecting to the backend server
  lea rdi, [rcx]          ; Use the backend_host argument passed (backend_host is in rcx)
  call gethostbyname

  test rax, rax
  js backend_connect_failed

	xor rax, rax
  mov [backend_fd], rax  ; store the backend socket descriptor
  mov word [backend_addr], 2 ; sin_family = AF_INET
  mov dword [backend_addr+4], eax ; backend IP (this will come from gethostbyname)

  jmp server_loop       ; forever running


;; socket failed
socket_failed:
    mov rdi, 1
    mov rsi, msg_failed_socket
    call print_string
    jmp exit_error

recv_failed:
		mov rdi, 1
		mov rsi, msg_failed_recv
		call print_string
		jmp exit_error

backend_connect_failed:
		mov rdi, 1
		mov rsi, msg_backend_connect_failed
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

accept_failed:
		mov rdi, 1
		mov rsi, msg_failed_accept
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
    jz print_done				; Jumps to specified label if the zero flag is set
    
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

htons:
    mov ax, di        ; Load the 16-bit value from rdi into ax
    xchg al, ah       ; Swap the lower and upper bytes
    ret

gethostbyname:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    
    mov r12, rdi                ; Save input string
    xor r13, r13                ; Current number
    xor r14, r14                ; Byte count
    
.parse_ip:
    movzx rax, byte [r12]
    test al, al
    jz .finish_byte
    
    cmp al, '.'
    je .finish_byte
    
    sub al, '0'
    cmp al, 9
    ja .invalid
    
    imul r13, r13, 10
    add r13, rax
    
    cmp r13, 255
    ja .invalid
    
    inc r12
    jmp .parse_ip
    
.finish_byte:
    mov [ip_addr + r14], r13b
    inc r14
    
    cmp r14, 4
    je .build_hostent
    
    test al, al
    jz .invalid
    
    inc r12
    xor r13, r13
    jmp .parse_ip
    
.build_hostent:
    lea rax, [hostent_struct]
    
    mov dword [rax], 0
    mov qword [rax + 8], 0
    mov dword [rax + 16], AF_INET
    mov dword [rax + 20], IP_ADDR_LEN
    
    lea rbx, [h_addr_list]
    mov [rax + 24], rbx
    
    mov ebx, [ip_addr]
    mov [h_addr_list], rbx
    mov qword [h_addr_list + 8], 0
    
    jmp .done
    
.invalid:
    xor rax, rax
    
.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    mov rsp, rbp
    pop rbp
    ret