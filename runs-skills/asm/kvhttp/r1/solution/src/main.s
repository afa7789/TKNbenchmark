// main.s — kvhttp entry point: ./app <port>
// Listens on 127.0.0.1:<port> and hands each accepted connection to a
// detached thread running conn_thread.

    .equ AF_INET,        2
    .equ SOCK_STREAM,    1
    .equ SOL_SOCKET,     0xffff
    .equ SO_REUSEADDR,   4
    .equ SIGPIPE,        13
    .equ SIG_IGN,        1
    .equ BACKLOG,        1024
    .equ PTHREAD_CREATE_DETACHED, 2
    .equ EINTR,          4
    .equ ECONNABORTED,   53

    .section __TEXT,__cstring,cstring_literals
Lusage:     .asciz "usage: app <port>\n"
Lerr_sock:  .asciz "socket"
Lerr_bind:  .asciz "bind"
Lerr_listen:.asciz "listen"

    .text

// Frame: [sp,#0] pthread_attr_t (64), [sp,#64] sockaddr_in (16),
//        [sp,#80] pthread_t, [sp,#88] int one.
    .equ M_ATTR, 0
    .equ M_ADDR, 64
    .equ M_TID,  80
    .equ M_ONE,  88
    .globl  _main
    .p2align 2
_main:
    .cfi_startproc
    sub     sp, sp, #144
    stp     x22, x21, [sp, #96]
    stp     x20, x19, [sp, #112]
    stp     x29, x30, [sp, #128]
    add     x29, sp, #128
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    .cfi_offset w21, -40
    .cfi_offset w22, -48

    cmp     w0, #2
    b.lt    Lmain_usage
    ldr     x0, [x1, #8]
    bl      _atoi
    sub     w9, w0, #1
    mov     w10, #65534
    cmp     w9, w10
    b.hi    Lmain_usage
    mov     w19, w0                         // port

    mov     w0, #SIGPIPE
    mov     x1, #SIG_IGN
    bl      _signal
    bl      _kv_init

    mov     w0, #AF_INET
    mov     w1, #SOCK_STREAM
    mov     w2, #0
    bl      _socket
    adrp    x21, Lerr_sock@PAGE
    add     x21, x21, Lerr_sock@PAGEOFF
    tbnz    w0, #31, Lmain_die
    mov     w20, w0

    mov     w9, #1
    str     w9, [sp, #M_ONE]
    mov     w0, w20
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_REUSEADDR
    add     x3, sp, #M_ONE
    mov     w4, #4
    bl      _setsockopt

    // struct sockaddr_in { u8 len, u8 family, be16 port, be32 addr, zero[8] }
    mov     w9, #16
    strb    w9, [sp, #M_ADDR]
    mov     w9, #AF_INET
    strb    w9, [sp, #M_ADDR + 1]
    rev16   w9, w19
    strh    w9, [sp, #M_ADDR + 2]
    movz    w9, #0x007f                     // 127.0.0.1 in network order
    movk    w9, #0x0100, lsl #16
    str     w9, [sp, #M_ADDR + 4]
    str     xzr, [sp, #M_ADDR + 8]
    mov     w0, w20
    add     x1, sp, #M_ADDR
    mov     w2, #16
    bl      _bind
    adrp    x21, Lerr_bind@PAGE
    add     x21, x21, Lerr_bind@PAGEOFF
    tbnz    w0, #31, Lmain_die

    mov     w0, w20
    mov     w1, #BACKLOG
    bl      _listen
    adrp    x21, Lerr_listen@PAGE
    add     x21, x21, Lerr_listen@PAGEOFF
    tbnz    w0, #31, Lmain_die

    add     x0, sp, #M_ATTR
    bl      _pthread_attr_init
    add     x0, sp, #M_ATTR
    mov     w1, #PTHREAD_CREATE_DETACHED
    bl      _pthread_attr_setdetachstate

Lmain_accept:
    mov     w0, w20
    mov     x1, #0
    mov     x2, #0
    bl      _accept
    tbnz    w0, #31, Lmain_accept_err
    mov     w21, w0
    add     x0, sp, #M_TID
    add     x1, sp, #M_ATTR
    adrp    x2, _conn_thread@PAGE
    add     x2, x2, _conn_thread@PAGEOFF
    mov     w3, w21                         // fd as the thread argument
    bl      _pthread_create
    cbz     w0, Lmain_accept
    mov     w0, w21                         // could not spawn: drop it
    bl      _close
    b       Lmain_accept

Lmain_accept_err:
    bl      ___error
    ldr     w8, [x0]
    cmp     w8, #EINTR
    b.eq    Lmain_accept
    cmp     w8, #ECONNABORTED
    b.eq    Lmain_accept
    mov     w0, #10000                      // e.g. EMFILE: back off briefly
    bl      _usleep
    b       Lmain_accept

Lmain_usage:
    adrp    x0, Lusage@PAGE
    add     x0, x0, Lusage@PAGEOFF
    adrp    x1, ___stderrp@GOTPAGE
    ldr     x1, [x1, ___stderrp@GOTPAGEOFF]
    ldr     x1, [x1]
    bl      _fputs
    mov     w0, #2
    bl      _exit

Lmain_die:
    mov     x0, x21
    bl      _perror
    mov     w0, #1
    bl      _exit
    .cfi_endproc

.subsections_via_symbols
