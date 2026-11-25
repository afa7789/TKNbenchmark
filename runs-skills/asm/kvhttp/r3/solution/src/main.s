// main.s - kvhttp entry point: `./app <port>`.
// Listens on 127.0.0.1:<port> and serves each connection on a detached thread.

    .equ AF_INET,          2
    .equ SOCK_STREAM,      1
    .equ SOL_SOCKET,       0xffff
    .equ SO_REUSEADDR,     0x0004
    .equ SO_SNDTIMEO,      0x1005
    .equ SO_RCVTIMEO,      0x1006
    .equ IPPROTO_TCP,      6
    .equ TCP_NODELAY,      0x01
    .equ SIGPIPE,          13
    .equ SIG_IGN,          1
    .equ PTHREAD_CREATE_DETACHED, 2
    .equ BACKLOG,          1024
    .equ IO_TIMEOUT_SEC,   30
    .equ STDERR_FILENO,    2

// Locals
    .equ L_ATTR,  0                   // pthread_attr_t (64 bytes)
    .equ L_ADDR,  64                  // struct sockaddr_in (16 bytes)
    .equ L_TV,    80                  // struct timeval (16 bytes)
    .equ L_TID,   96                  // pthread_t
    .equ L_ONE,   104                 // int 1, for boolean socket options
    .equ L_SIZE,  112

.macro ADDR reg, sym
    adrp    \reg, \sym@PAGE
    add     \reg, \reg, \sym@PAGEOFF
.endm

    .text
    .globl  _main
    .p2align 2
_main:
    .cfi_startproc
    sub     sp, sp, #48
    stp     x22, x21, [sp]
    stp     x20, x19, [sp, #16]
    stp     x29, x30, [sp, #32]
    add     x29, sp, #32
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    .cfi_offset w21, -40
    .cfi_offset w22, -48
    sub     sp, sp, #L_SIZE

    cmp     w0, #2
    b.lt    Lusage
    ldr     x0, [x1, #8]
    bl      _atoi
    sub     w8, w0, #1                    // valid ports: 1..65535
    mov     w9, #65534
    cmp     w8, w9
    b.hi    Lusage
    mov     w20, w0

    mov     w0, #SIGPIPE                  // peers may close early; use EPIPE instead
    mov     x1, #SIG_IGN
    bl      _signal

    bl      _store_init
    cbnz    w0, Lfatal_init

    mov     w0, #AF_INET
    mov     w1, #SOCK_STREAM
    mov     w2, #0
    bl      _socket
    tbnz    w0, #31, Lfatal_socket
    mov     w19, w0

    mov     w8, #1
    str     w8, [sp, #L_ONE]
    mov     w0, w19
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_REUSEADDR
    add     x3, sp, #L_ONE
    mov     w4, #4
    bl      _setsockopt

    mov     w8, #0x0210                   // sin_len = 16, sin_family = AF_INET
    rev16   w9, w20                       // htons(port)
    orr     w8, w8, w9, lsl #16
    str     w8, [sp, #L_ADDR]
    movz    w8, #0x007f
    movk    w8, #0x0100, lsl #16          // 127.0.0.1, network order
    str     w8, [sp, #L_ADDR + 4]
    str     xzr, [sp, #L_ADDR + 8]
    mov     w0, w19
    add     x1, sp, #L_ADDR
    mov     w2, #16
    bl      _bind
    cbnz    w0, Lfatal_bind
    mov     w0, w19
    mov     w1, #BACKLOG
    bl      _listen
    cbnz    w0, Lfatal_listen

    add     x0, sp, #L_ATTR
    bl      _pthread_attr_init
    add     x0, sp, #L_ATTR
    mov     w1, #PTHREAD_CREATE_DETACHED
    bl      _pthread_attr_setdetachstate

    mov     x8, #IO_TIMEOUT_SEC           // bound how long a stalled peer holds a thread
    stp     x8, xzr, [sp, #L_TV]

Laccept:
    mov     w0, w19
    mov     x1, #0
    mov     x2, #0
    bl      _accept
    tbnz    w0, #31, Laccept_error
    mov     w21, w0

    mov     w0, w21
    mov     w1, #IPPROTO_TCP
    mov     w2, #TCP_NODELAY
    add     x3, sp, #L_ONE
    mov     w4, #4
    bl      _setsockopt
    mov     w0, w21
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_RCVTIMEO
    add     x3, sp, #L_TV
    mov     w4, #16
    bl      _setsockopt
    mov     w0, w21
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_SNDTIMEO
    add     x3, sp, #L_TV
    mov     w4, #16
    bl      _setsockopt

    add     x0, sp, #L_TID
    add     x1, sp, #L_ATTR
    ADDR    x2, _conn_main
    mov     w3, w21                       // fd passed as the thread argument
    bl      _pthread_create
    cbz     w0, Laccept
    mov     w0, w21                       // could not spawn: drop the connection
    bl      _close
    b       Laccept

Laccept_error:
    // Transient (EINTR, ECONNABORTED, EMFILE...): back off briefly and retry.
    mov     w0, #1000
    bl      _usleep
    b       Laccept

Lusage:
    mov     w0, #STDERR_FILENO
    ADDR    x1, Lmsg_usage
    mov     x2, #(Lmsg_usage_end - Lmsg_usage)
    bl      _write
    mov     w0, #2
    b       Lmain_ret
Lfatal_init:
    ADDR    x0, Lmsg_init
    b       Lfatal
Lfatal_socket:
    ADDR    x0, Lmsg_socket
    b       Lfatal
Lfatal_bind:
    ADDR    x0, Lmsg_bind
    b       Lfatal
Lfatal_listen:
    ADDR    x0, Lmsg_listen
Lfatal:
    bl      _perror
    mov     w0, #1
Lmain_ret:
    sub     sp, x29, #32
    ldp     x29, x30, [sp, #32]
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp]
    add     sp, sp, #48
    ret
    .cfi_endproc

    .section __TEXT,__cstring,cstring_literals
Lmsg_init:    .asciz "kvhttp: store init"
Lmsg_socket:  .asciz "kvhttp: socket"
Lmsg_bind:    .asciz "kvhttp: bind"
Lmsg_listen:  .asciz "kvhttp: listen"

    .const
Lmsg_usage:   .ascii "usage: app <port>\n"
Lmsg_usage_end:

.subsections_via_symbols
