// kvhttp — entry point: argument parsing, listening socket, accept loop.
// Each accepted connection is served by its own detached pthread.

        .include "defs.inc"

        .section __TEXT,__text,regular,pure_instructions

// Stack frame layout for _main.
        .equ F_SADDR, 48        // struct sockaddr_in (16 bytes)
        .equ F_ONE,   64        // int 1, used for boolean socket options
        .equ F_TID,   72        // pthread_t
        .equ F_ATTR,  80        // pthread_attr_t (64 bytes)
        .equ F_TV,    144       // struct timeval (16 bytes)
        .equ F_SIZE,  160

        .globl _main
        .p2align 2
_main:
        sub     sp, sp, #F_SIZE
        stp     x29, x30, [sp]
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]

        cmp     w0, #2
        b.ne    Lusage
        ldr     x0, [x1, #8]
        bl      _parse_port
        tbnz    x0, #63, Lusage
        mov     x21, x0                         // x21 = port (host order)

        mov     w0, #SIGPIPE                    // peers may vanish mid-write
        mov     x1, #SIG_IGN
        bl      _signal

        bl      _store_init

        // Listening socket.
        mov     w0, #AF_INET
        mov     w1, #SOCK_STREAM
        mov     w2, #0
        bl      _socket
        tbnz    w0, #31, Lerr_socket
        mov     w19, w0                         // w19 = listen fd

        mov     w8, #1
        str     w8, [sp, #F_ONE]
        mov     w0, w19
        mov     w1, #SOL_SOCKET
        mov     w2, #SO_REUSEADDR
        add     x3, sp, #F_ONE
        mov     w4, #4
        bl      _setsockopt

        // sockaddr_in { len=16, family=AF_INET, port=htons(port), addr=127.0.0.1 }
        rev16   w8, w21
        lsl     w8, w8, #16
        mov     w9, #(16 | (AF_INET << 8))
        orr     w8, w8, w9
        str     w8, [sp, #F_SADDR]
        mov     w9, #0x007f
        movk    w9, #0x0100, lsl #16            // bytes 7f 00 00 01
        str     w9, [sp, #F_SADDR + 4]
        str     xzr, [sp, #F_SADDR + 8]

        mov     w0, w19
        add     x1, sp, #F_SADDR
        mov     w2, #16
        bl      _bind
        cbnz    w0, Lerr_bind

        mov     w0, w19
        mov     w1, #LISTEN_BACKLOG
        bl      _listen
        cbnz    w0, Lerr_listen

        // Detached thread attributes shared by every connection thread.
        add     x0, sp, #F_ATTR
        bl      _pthread_attr_init
        add     x0, sp, #F_ATTR
        mov     w1, #PTHREAD_CREATE_DETACHED
        bl      _pthread_attr_setdetachstate

        mov     x8, #IO_TIMEOUT_S
        str     x8, [sp, #F_TV]
        str     xzr, [sp, #F_TV + 8]

Laccept:
        mov     w0, w19
        mov     x1, #0
        mov     x2, #0
        bl      _accept
        tbnz    w0, #31, Laccept_err
        mov     w20, w0                         // w20 = client fd

        mov     w0, w20
        mov     w1, #IPPROTO_TCP
        mov     w2, #TCP_NODELAY
        add     x3, sp, #F_ONE
        mov     w4, #4
        bl      _setsockopt

        mov     w0, w20
        mov     w1, #SOL_SOCKET
        mov     w2, #SO_RCVTIMEO
        add     x3, sp, #F_TV
        mov     w4, #16
        bl      _setsockopt

        mov     w0, w20
        mov     w1, #SOL_SOCKET
        mov     w2, #SO_SNDTIMEO
        add     x3, sp, #F_TV
        mov     w4, #16
        bl      _setsockopt

        add     x0, sp, #F_TID
        add     x1, sp, #F_ATTR
        LOADADDR x2, _conn_thread
        mov     w3, w20                         // fd passed as the thread argument
        bl      _pthread_create
        cbz     w0, Laccept
        mov     w0, w20                         // could not spawn: drop the client
        bl      _close
        b       Laccept

Laccept_err:
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Laccept
        mov     w0, #1000                       // EMFILE & co: back off 1 ms
        bl      _usleep
        b       Laccept

Lusage:
        mov     w0, #2
        LOADADDR x1, Lmsg_usage
        mov     x2, #(Lmsg_usage_end - Lmsg_usage)
        bl      _write
        mov     w0, #2
        bl      _exit

Lerr_socket:
        LOADADDR x0, Lmsg_socket
        b       Lfatal
Lerr_bind:
        LOADADDR x0, Lmsg_bind
        b       Lfatal
Lerr_listen:
        LOADADDR x0, Lmsg_listen
Lfatal:
        bl      _perror
        mov     w0, #1
        bl      _exit

// _parse_port(const char *s) -> x0 = port in 1..65535, or -1 if invalid.
        .p2align 2
_parse_port:
        mov     x1, #0                          // value
        mov     x3, #0                          // digit count
        mov     x4, #10
        mov     x5, #65535
1:      ldrb    w2, [x0], #1
        cbz     w2, 2f
        sub     w2, w2, #'0'
        cmp     w2, #9
        b.hi    3f
        madd    x1, x1, x4, x2
        cmp     x1, x5
        b.hi    3f
        add     x3, x3, #1
        b       1b
2:      cbz     x3, 3f
        cbz     x1, 3f
        mov     x0, x1
        ret
3:      mov     x0, #-1
        ret

        .section __TEXT,__cstring,cstring_literals
Lmsg_usage:
        .ascii  "usage: app <port>\n"
Lmsg_usage_end:
        .byte   0
Lmsg_socket:
        .asciz  "socket"
Lmsg_bind:
        .asciz  "bind"
Lmsg_listen:
        .asciz  "listen"
