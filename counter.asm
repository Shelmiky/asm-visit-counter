bits 64
default rel
global _start

SYS_READ      equ 0
SYS_WRITE     equ 1
SYS_OPEN      equ 2
SYS_CLOSE     equ 3
SYS_LSEEK     equ 8
SYS_EXIT      equ 60
SYS_FLOCK     equ 73
SYS_FSYNC     equ 74
SYS_FTRUNCATE equ 77
O_RDWR_CREAT  equ 66
LOCK_EX       equ 2
EINTR         equ 4

section .rodata
    filename db 'count.txt', 0
    prefix db 'Visits: '
    prefix_len equ $ - prefix
    invalid_msg db 'Error: count.txt must contain an unsigned decimal number.', 10
    invalid_len equ $ - invalid_msg
    overflow_msg db 'Error: counter cannot exceed 18446744073709551615.', 10
    overflow_len equ $ - overflow_msg
    io_msg db 'Error: could not access, save or display the counter.', 10
    io_len equ $ - io_msg

section .bss
    input_buffer resb 32
    output_buffer resb 21

section .text
_start:
    mov r13, -1
    mov eax, SYS_OPEN
    lea rdi, [filename]
    mov esi, O_RDWR_CREAT
    mov edx, 0o644
    syscall
    test rax, rax
    js io_error
    mov r13, rax

.lock:
    mov eax, SYS_FLOCK
    mov rdi, r13
    mov esi, LOCK_EX
    syscall
    cmp rax, -EINTR
    je .lock
    test rax, rax
    js io_error

    xor r12d, r12d
.read:
    mov eax, SYS_READ
    mov rdi, r13
    lea rsi, [input_buffer]
    add rsi, r12
    mov edx, 32
    sub rdx, r12
    syscall
    cmp rax, -EINTR
    je .read
    test rax, rax
    js io_error
    jz .parse
    add r12, rax
    cmp r12, 32
    jae invalid_input
    jmp .read

.parse:
    xor ebx, ebx
    test r12, r12
    jz .increment
    lea rsi, [input_buffer]
    cmp byte [rsi + r12 - 1], 10
    jne .check_length
    dec r12
.check_length:
    test r12, r12
    jz invalid_input
    cmp r12, 20
    ja invalid_input
    mov r10d, 10
.digit:
    movzx edi, byte [rsi]
    sub edi, '0'
    cmp edi, 9
    ja invalid_input
    mov rax, rbx
    mul r10
    test rdx, rdx
    jnz overflow
    add rax, rdi
    jc overflow
    mov rbx, rax
    inc rsi
    dec r12
    jnz .digit

.increment:
    add rbx, 1
    jc overflow
    lea r14, [output_buffer + 20]
    mov byte [r14], 10
    mov r15d, 1
    mov rax, rbx
    mov r10d, 10
.format:
    xor edx, edx
    div r10
    add dl, '0'
    dec r14
    mov [r14], dl
    inc r15
    test rax, rax
    jnz .format

    mov eax, SYS_LSEEK
    mov rdi, r13
    xor esi, esi
    xor edx, edx
    syscall
    test rax, rax
    js io_error

    mov rdi, r13
    mov rsi, r14
    mov rdx, r15
    call write_all

    ; shortcut: in-place save is not crash-atomic; use a journal for durable shared storage.
    mov eax, SYS_FTRUNCATE
    mov rdi, r13
    mov rsi, r15
    syscall
    test rax, rax
    js io_error

    mov eax, SYS_FSYNC
    mov rdi, r13
    syscall
    test rax, rax
    js io_error

    mov eax, SYS_CLOSE
    mov rdi, r13
    syscall
    mov r13, -1
    test rax, rax
    js io_error

    mov edi, 1
    lea rsi, [prefix]
    mov edx, prefix_len
    call write_all
    mov edi, 1
    mov rsi, r14
    mov rdx, r15
    call write_all

    xor edi, edi
    jmp exit

write_all:
    mov eax, SYS_WRITE
    syscall
    cmp rax, -EINTR
    je write_all
    test rax, rax
    jle io_error
    add rsi, rax
    sub rdx, rax
    jnz write_all
    ret

invalid_input:
    lea r14, [invalid_msg]
    mov r15d, invalid_len
    jmp error
overflow:
    lea r14, [overflow_msg]
    mov r15d, overflow_len
    jmp error
io_error:
    lea r14, [io_msg]
    mov r15d, io_len
error:
    cmp r13, 0
    jl .message
    mov eax, SYS_CLOSE
    mov rdi, r13
    syscall
.message:
    mov eax, SYS_WRITE
    mov edi, 2
    mov rsi, r14
    mov rdx, r15
    syscall
    mov edi, 1
exit:
    mov eax, SYS_EXIT
    syscall

section .note.GNU-stack noalloc noexec nowrite progbits
