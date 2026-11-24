// main.s — process entry, listening socket and the accept loop.
// One detached thread per connection; each connection serves one request.

        .include "macros.inc"

        .section __TEXT,__cstring,cstring_literals
Lmsg_usage:     .asciz "usage: app <port>\n"
Lmsg_init:      .asciz "store init"
Lmsg_socket:    .asciz "socket"
Lmsg_bind:      .asciz "bind"
Lmsg_listen:    .asciz "listen"

        .text

// long parse_port(const char *s x0) — 1..65535, or -1 when invalid.
        .p2align 2
parse_port:
        mov     x1, #0                      // value
        mov     x2, #0                      // digits
        mov     x4, #10
1:      ldrb    w3, [x0], #1
        cbz     w3, 2f
        sub     w3, w3, #'0'
        cmp     w3, #9
        b.hi    3f
        madd    x1, x1, x4, x3
        add     x2, x2, #1
        cmp     x2, #5
        b.hi    3f
        b       1b
2:      cbz     x2, 3f
        cbz     x1, 3f
        mov     x5, #65535
        cmp     x1, x5
        b.hi    3f
        mov     x0, x1
        ret
3:      mov     x0, #-1
        ret

        .globl  _main
        .p2align 2
_main:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        // [sp,#40] int scratch, [sp,#48..63] struct sockaddr_in
        cmp     w0, #2
        b.ne    Lusage
        ldr     x0, [x1, #8]
        bl      parse_port
        cmp     x0, #0
        b.le    Lusage
        mov     x19, x0

        mov     w0, #SIGPIPE
        mov     x1, #SIG_IGN
        bl      _signal

        bl      _store_init
        LOADADDR x1, Lmsg_init
        cbnz    w0, Lfatal

        mov     w0, #AF_INET
        mov     w1, #SOCK_STREAM
        mov     w2, #0
        bl      _socket
        LOADADDR x1, Lmsg_socket
        tbnz    w0, #31, Lfatal
        mov     w20, w0

        mov     w8, #1
        str     w8, [sp, #40]
        mov     w0, w20
        mov     w1, #SOL_SOCKET
        mov     w2, #SO_REUSEADDR
        add     x3, sp, #40
        mov     w4, #4
        bl      _setsockopt

        // sockaddr_in { len=16, family=AF_INET, port (BE), 127.0.0.1, zero[8] }
        movz    x8, #0x0210
        movk    x8, #0x007f, lsl #32
        movk    x8, #0x0100, lsl #48
        rev16   w9, w19
        orr     x8, x8, x9, lsl #16
        stp     x8, xzr, [sp, #48]
        mov     w0, w20
        add     x1, sp, #48
        mov     w2, #16
        bl      _bind
        LOADADDR x1, Lmsg_bind
        tbnz    w0, #31, Lfatal

        mov     w0, w20
        mov     w1, #LISTEN_BACKLOG
        bl      _listen
        LOADADDR x1, Lmsg_listen
        tbnz    w0, #31, Lfatal

Laccept:
        mov     w0, w20
        mov     x1, #0
        mov     x2, #0
        bl      _accept
        tbz     w0, #31, Lspawn
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    Laccept
        cmp     w8, #ECONNABORTED
        b.eq    Laccept
        mov     w0, #10000                  // fd/memory exhaustion: back off 10 ms
        bl      _usleep
        b       Laccept
Lspawn:
        bl      conn_spawn
        b       Laccept

Lusage:
        mov     w0, #2
        LOADADDR x1, Lmsg_usage
        mov     x2, #18
        bl      _write
        mov     w0, #2
        bl      _exit

Lfatal:                                     // x1 = message for perror
        mov     x0, x1
        bl      _perror
        mov     w0, #1
        bl      _exit

// void conn_spawn(int fd w0) — hand the connection to a detached thread.
        .p2align 2
conn_spawn:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x19, [sp, #16]
        mov     w19, w0
        add     x0, sp, #24                 // pthread_t
        mov     x1, #0
        LOADADDR x2, _conn_main
        mov     w3, w19                     // fd passed as the thread argument
        bl      _pthread_create
        cbnz    w0, 1f
        ldr     x0, [sp, #24]
        bl      _pthread_detach
        b       2f
1:      mov     w0, w19
        bl      _close
2:      ldr     x19, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret
