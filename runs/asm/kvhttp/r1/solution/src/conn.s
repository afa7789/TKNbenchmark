// conn.s — per-connection thread: socket setup, request handling, and a
// graceful close (half-close + drain) so unread request bytes never turn the
// close into a RST that could destroy the response in flight.

        .include "macros.inc"

        .text

// void set_opt_int(int fd w0, int level w1, int name w2, int value w3)
        .p2align 2
set_opt_int:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        sub     sp, sp, #16
        str     w3, [sp]
        mov     x3, sp
        mov     w4, #4
        bl      _setsockopt
        add     sp, sp, #16
        ldp     x29, x30, [sp], #16
        ret

// void set_opt_timeout(int fd w0, int name w1)
        .p2align 2
set_opt_timeout:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        sub     sp, sp, #16
        mov     x8, #IO_TIMEOUT_SEC
        stp     x8, xzr, [sp]               // struct timeval { tv_sec, tv_usec }
        mov     w2, w1
        mov     w1, #SOL_SOCKET
        mov     x3, sp
        mov     w4, #16
        bl      _setsockopt
        add     sp, sp, #16
        ldp     x29, x30, [sp], #16
        ret

// void *conn_main(void *arg) — arg carries the client fd.
        .globl  _conn_main
        .p2align 2
_conn_main:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        sub     sp, sp, #4096               // drain buffer
        mov     w19, w0

        mov     w0, w19
        mov     w1, #SOL_SOCKET
        mov     w2, #SO_NOSIGPIPE
        mov     w3, #1
        bl      set_opt_int
        mov     w0, w19
        mov     w1, #IPPROTO_TCP
        mov     w2, #TCP_NODELAY
        mov     w3, #1
        bl      set_opt_int
        mov     w0, w19
        mov     w1, #SO_RCVTIMEO
        bl      set_opt_timeout
        mov     w0, w19
        mov     w1, #SO_SNDTIMEO
        bl      set_opt_timeout

        mov     w0, w19
        bl      _http_handle

        mov     w0, w19
        mov     w1, #SHUT_WR
        bl      _shutdown
        mov     x20, #DRAIN_LIMIT
1:      mov     w0, w19
        mov     x1, sp
        mov     x2, #4096
        bl      _read
        cmp     x0, #0
        b.le    2f
        subs    x20, x20, x0
        b.gt    1b
2:      mov     w0, w19
        bl      _close

        mov     x0, #0
        add     sp, sp, #4096
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret
