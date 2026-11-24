// main.s — kvhttp entry point: `app <port>` serves on 127.0.0.1:<port>.
//
// The main thread accepts connections and hands each socket to a
// detached worker thread running conn_main (see http.s).

        .equ    AF_INET, 2
        .equ    SOCK_STREAM, 1
        .equ    SOL_SOCKET, 0xffff
        .equ    SO_REUSEADDR, 4
        .equ    SIGPIPE, 13
        .equ    SIG_IGN, 1
        .equ    PTHREAD_CREATE_DETACHED, 2
        .equ    LISTEN_BACKLOG, 1024
        .equ    EINTR, 4
        .equ    ACCEPT_BACKOFF_US, 1000

.macro  LOADADDR reg, sym
        adrp    \reg, \sym@PAGE
        add     \reg, \reg, \sym@PAGEOFF
.endm

        .zerofill __DATA,__bss,L_thread_attr,64,3

        .section __TEXT,__text,regular,pure_instructions

// Frame: [sp,#48] scratch (endptr / int option), [sp,#56] pthread_t,
//        [sp,#64] struct sockaddr_in (16 bytes)
        .globl  _main
        .p2align 2
_main:
        stp     x29, x30, [sp, #-80]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]

        cmp     w0, #2
        b.ne    Lusage
        ldr     x0, [x1, #8]
        ldrb    w8, [x0]
        cbz     w8, Lusage
        add     x1, sp, #48
        mov     w2, #10
        bl      _strtol
        ldr     x8, [sp, #48]
        ldrb    w8, [x8]
        cbnz    w8, Lusage              // trailing garbage
        cmp     x0, #1
        b.lt    Lusage
        mov     x8, #65535
        cmp     x0, x8
        b.gt    Lusage
        mov     x19, x0                 // port

        mov     w0, #SIGPIPE
        mov     x1, #SIG_IGN
        bl      _signal
        bl      _store_init

        mov     w0, #AF_INET
        mov     w1, #SOCK_STREAM
        mov     w2, #0
        bl      _socket
        LOADADDR x22, L_e_socket
        cmp     w0, #0
        b.lt    Lfatal
        mov     w20, w0

        mov     w8, #1
        str     w8, [sp, #48]
        mov     w0, w20
        mov     w1, #SOL_SOCKET
        mov     w2, #SO_REUSEADDR
        add     x3, sp, #48
        mov     w4, #4
        bl      _setsockopt

        // sockaddr_in { len 16, AF_INET, htons(port), 127.0.0.1, zero[8] }
        rev16   w9, w19
        mov     w10, #(AF_INET << 8) | 16
        orr     w10, w10, w9, lsl #16
        str     w10, [sp, #64]
        movz    w11, #0x007f
        movk    w11, #0x0100, lsl #16
        str     w11, [sp, #68]
        str     xzr, [sp, #72]
        mov     w0, w20
        add     x1, sp, #64
        mov     w2, #16
        bl      _bind
        LOADADDR x22, L_e_bind
        cmp     w0, #0
        b.lt    Lfatal
        mov     w0, w20
        mov     w1, #LISTEN_BACKLOG
        bl      _listen
        LOADADDR x22, L_e_listen
        cmp     w0, #0
        b.lt    Lfatal

        LOADADDR x21, L_thread_attr
        mov     x0, x21
        bl      _pthread_attr_init
        mov     x0, x21
        mov     w1, #PTHREAD_CREATE_DETACHED
        bl      _pthread_attr_setdetachstate

Laccept:
        mov     w0, w20
        mov     x1, #0
        mov     x2, #0
        bl      _accept
        cmp     w0, #0
        b.lt    Laccept_err
        mov     w22, w0
        add     x0, sp, #56
        mov     x1, x21
        LOADADDR x2, _conn_main
        mov     w3, w22                 // fd passed as the thread argument
        bl      _pthread_create
        cbz     w0, Laccept
        mov     w0, w22                 // no thread: drop the connection
        bl      _close
        b       Laccept
Laccept_err:
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    Laccept
        mov     w0, #ACCEPT_BACKOFF_US  // e.g. EMFILE: back off briefly
        bl      _usleep
        b       Laccept

Lusage:
        LOADADDR x22, L_usage
        mov     x0, x22
        bl      _strlen
        mov     x2, x0
        mov     w0, #2
        mov     x1, x22
        bl      _write
        mov     w0, #2
        bl      _exit

Lfatal:                                 // x22 = name of the failed call
        mov     x0, x22
        bl      _perror
        mov     w0, #1
        bl      _exit

        .section __TEXT,__cstring,cstring_literals
L_usage:    .asciz "usage: app <port>\n"
L_e_socket: .asciz "socket"
L_e_bind:   .asciz "bind"
L_e_listen: .asciz "listen"
