// main.s — `app <port>`: listen on 127.0.0.1:<port>, one detached thread
// per accepted connection (see conn.s), serve until killed.

    .equ AF_INET, 2
    .equ SOCK_STREAM, 1
    .equ SOL_SOCKET, 0xffff
    .equ SO_REUSEADDR, 4
    .equ SIGPIPE, 13
    .equ SIG_IGN, 1
    .equ PTHREAD_CREATE_DETACHED, 2
    .equ BACKLOG, 1024
    .equ ENFILE, 23
    .equ EMFILE, 24
    .equ EINTR, 4

    // frame (sp-relative)
    .equ F_ATTR, 0                  // pthread_attr_t (64 bytes)
    .equ F_ADDR, 64                 // struct sockaddr_in (16 bytes)
    .equ F_TID,  80                 // pthread_t
    .equ F_END,  88                 // strtol end pointer
    .equ F_ONE,  96                 // int 1 for setsockopt
    .equ F_REGS, 112
    .equ F_SIZE, 144

    .text
    .globl  _main
    .p2align 2
_main:
    .cfi_startproc
    sub     sp, sp, #F_SIZE
    stp     x20, x19, [sp, #F_REGS]
    stp     x29, x30, [sp, #F_REGS + 16]
    add     x29, sp, #F_REGS + 16
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32

    // port = strtol(argv[1]); must be a full decimal in 1..65535
    cmp     w0, #2
    b.ne    Lusage
    ldr     x0, [x1, #8]
    add     x1, sp, #F_END
    mov     w2, #10
    bl      _strtol
    ldr     x8, [sp, #F_END]
    ldrb    w8, [x8]
    cbnz    w8, Lusage
    sub     x8, x0, #1
    mov     x9, #65534
    cmp     x8, x9
    b.hi    Lusage
    mov     w19, w0

    // a client hanging up mid-write must not kill the process
    mov     w0, #SIGPIPE
    mov     x1, #SIG_IGN
    bl      _signal

    mov     w0, #AF_INET
    mov     w1, #SOCK_STREAM
    mov     w2, #0
    bl      _socket
    tbnz    w0, #31, Lfail_socket
    mov     w20, w0

    mov     w8, #1
    str     w8, [sp, #F_ONE]
    mov     w0, w20
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_REUSEADDR
    add     x3, sp, #F_ONE
    mov     w4, #4
    bl      _setsockopt

    // sockaddr_in { sin_len = 16, sin_family = AF_INET, sin_port, 127.0.0.1 }
    rev16   w9, w19
    mov     w8, #(AF_INET << 8) | 16
    orr     w8, w8, w9, lsl #16
    str     w8, [sp, #F_ADDR]
    movz    w9, #0x007f
    movk    w9, #0x0100, lsl #16
    str     w9, [sp, #F_ADDR + 4]
    str     xzr, [sp, #F_ADDR + 8]
    mov     w0, w20
    add     x1, sp, #F_ADDR
    mov     w2, #16
    bl      _bind
    cbnz    w0, Lfail_bind
    mov     w0, w20
    mov     w1, #BACKLOG
    bl      _listen
    cbnz    w0, Lfail_listen

    add     x0, sp, #F_ATTR
    bl      _pthread_attr_init
    add     x0, sp, #F_ATTR
    mov     w1, #PTHREAD_CREATE_DETACHED
    bl      _pthread_attr_setdetachstate

Laccept:
    mov     w0, w20
    mov     x1, #0
    mov     x2, #0
    bl      _accept
    tbnz    w0, #31, Laccept_error
    mov     w19, w0
    add     x0, sp, #F_TID
    add     x1, sp, #F_ATTR
    adrp    x2, _conn_main@PAGE
    add     x2, x2, _conn_main@PAGEOFF
    mov     w3, w19                     // fd travels as the thread argument
    bl      _pthread_create
    cbz     w0, Laccept
    mov     w0, w19                     // no thread: shed the connection
    bl      _close
    b       Laccept

Laccept_error:
    bl      ___error
    ldr     w8, [x0]
    cmp     w8, #EMFILE
    ccmp    w8, #ENFILE, #4, ne         // Z set if EMFILE or ENFILE
    b.ne    Laccept
    mov     w0, #10000                  // out of descriptors: back off 10 ms
    bl      _usleep
    b       Laccept

Lusage:
    adrp    x0, Lmsg_usage@PAGE
    add     x0, x0, Lmsg_usage@PAGEOFF
    adrp    x1, ___stderrp@GOTPAGE
    ldr     x1, [x1, ___stderrp@GOTPAGEOFF]
    ldr     x1, [x1]
    bl      _fputs
    mov     w0, #2
    b       Lexit
Lfail_socket:
    adrp    x0, Lmsg_socket@PAGE
    add     x0, x0, Lmsg_socket@PAGEOFF
    b       Lfail
Lfail_bind:
    adrp    x0, Lmsg_bind@PAGE
    add     x0, x0, Lmsg_bind@PAGEOFF
    b       Lfail
Lfail_listen:
    adrp    x0, Lmsg_listen@PAGE
    add     x0, x0, Lmsg_listen@PAGEOFF
Lfail:
    bl      _perror
    mov     w0, #1
Lexit:
    ldp     x29, x30, [sp, #F_REGS + 16]
    ldp     x20, x19, [sp, #F_REGS]
    add     sp, sp, #F_SIZE
    ret
    .cfi_endproc

    .section __TEXT,__cstring,cstring_literals
Lmsg_usage:     .asciz "usage: app <port>\n"
Lmsg_socket:    .asciz "socket"
Lmsg_bind:      .asciz "bind"
Lmsg_listen:    .asciz "listen"

.subsections_via_symbols
