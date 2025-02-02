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
		msg_backend_connect_failed_cleanup db "failed to connect to backend", 10
    msg_client_connected db "Client connected", 10
    msg_data_received db "Received data from client. Bytes: ", 0

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
	backend_buffer resb 4096 ; Reserve 4096 bytes for the backend buffer

  hostent_struct resb 32       ; Hostent structure
  h_addr_list resq 2           ; Address list
  ip_addr resd 1              ; IP address storage
  temp_buffer resb 16         ; Temporary buffer for parsing

	;; declaring constants
	AF_INET equ 2
	SOCK_STREAM equ 1
	IP_ADDR_LEN equ 4

section .text
    global _start       ; entry point for the linker
		global htons

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

		mov r10, [rsp+24]   ; Store backend_host pointer in r10

		;; SOCKET CREATION
		mov rdi, AF_INET ;; AF_INET (IPv4)
		mov rsi, SOCK_STREAM ;; SOCK_STREAM
		xor rdx, rdx ;; protocol
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

server_loop:
	;; accepting incoming connections 
	mov dword [client_addr_len], 16
	mov rdi, [sockfd] 
	lea rsi, [client_addr]
	lea rdx, [client_addr_len]
	mov rax, 43        ; accept() syscall
	syscall 

	test rax, rax
	js accept_failed

	mov [client_fd], rax

	;; print confirmation of client connection
  mov rdi, 1
  mov rsi, msg_client_connected
  call print_string

	; Receive data from client
	mov rdi, [client_fd]
	lea rsi, [buffer]
	mov rdx, 4096
	xor r10, r10       ; flags = 0
	mov rax, 45        ; recv() syscall
	syscall

	test rax, rax
	jle recv_failed    ; Changed to jle to catch both 0 and negative

	push rax           ; Save bytes received for later
	mov rdi, 1
	mov rsi, msg_data_received
	call print_string
	pop rax
	push rax            ; Save it again
	mov rdi, rax
	call print_number
	mov rdi, 1
	mov rsi, newline
	call print_string

	; Parse backend IP (127.0.0.1)
	mov rdi, r10        ; backend_host from stored pointer
	call parse_ip
	test rax, rax
	js backend_connect_failed

	; Create backend socket
	mov rdi, AF_INET
	mov rsi, SOCK_STREAM
	xor rdx, rdx
	mov rax, 41
	syscall

	test rax, rax
	js backend_connect_failed

	mov [backend_fd], rax

	; Setup backend address
	mov word [backend_addr], AF_INET
	mov rdi, r9         ; backend_port
	call htons
	mov [backend_addr+2], ax
	mov eax, [ip_addr]
	mov [backend_addr+4], eax

	; Connect to backend
	mov rdi, [backend_fd]
	lea rsi, [backend_addr]
	mov edx, 16
	mov rax, 42
	syscall

	test rax, rax
	js backend_connect_failed_cleanup

	; Send data to backend
	pop rdx             ; Restore received bytes
	mov rdi, [backend_fd]
	lea rsi, [buffer]
	xor r10, r10        ; flags = 0
	mov rax, 44         ; send syscall
	syscall

	jmp relay_loop

relay_loop:
    mov rdi, [backend_fd]   ; Backend socket
    lea rsi, [buffer]       ; Receive into buffer
    mov rdx, 4096           ; Buffer size
		xor r10, r10            ; Flags
    mov rax, 45             ; recv() syscall
    syscall

    test rax, rax
    jle close_connections   ; If <= 0, close sockets

    mov rdx, rax        ; bytes to send
    mov rdi, [client_fd]
    lea rsi, [buffer]
    xor r10, r10
    mov rax, 44
    syscall

    jmp relay_loop

close_connections:
    mov rdi, [backend_fd]
    mov rax, 3
    syscall
    mov rdi, [client_fd]
    mov rax, 3
    syscall
    jmp server_loop

;; socket failed
socket_failed:
    mov rdi, 1
    mov rsi, msg_failed_socket
    call print_string
    jmp exit_error

backend_connect_failed_cleanup:
    mov rdi, [backend_fd]
    mov rax, 3          ; close() syscall
    syscall
    mov rdi, [client_fd]
    mov rax, 3
    syscall
    jmp server_loop


backend_connect_failed:
		mov rdi, 1
		mov rsi, msg_backend_connect_failed
		call print_string
		jmp exit_error

recv_failed:
		mov rdi, 1
		mov rsi, msg_failed_recv
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


parse_ip:
    push rbp
    mov rbp, rsp
    push r12
    push r13
    push r14

    mov r12, rdi        ; Save input string
    xor r13, r13        ; Current octet
    xor r14, r14        ; Octet counter

parse_ip_loop:
    movzx rax, byte [r12]
    test al, al
    jz parse_ip_end

    cmp al, '.'
    je finish_octet

    sub al, '0'
    cmp al, 9
    ja parse_ip_invalid

    imul r13, r13, 10
    movzx rax, al
    add r13, rax

    cmp r13, 255
    ja parse_ip_invalid

    inc r12
    jmp parse_ip_loop

finish_octet:
    mov [ip_addr + r14], r13b
    inc r14
    xor r13, r13
    inc r12
    jmp parse_ip_loop

parse_ip_end:
    mov [ip_addr + r14], r13b
    inc r14
    cmp r14, 4
    jne parse_ip_invalid

    mov eax, [ip_addr]
    jmp parse_ip_done

parse_ip_invalid:
    mov rax, -1

parse_ip_done:
    pop r14
    pop r13
    pop r12
    mov rsp, rbp
    pop rbp
    ret