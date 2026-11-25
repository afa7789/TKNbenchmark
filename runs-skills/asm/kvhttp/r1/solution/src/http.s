// http.s — one HTTP/1.1 request per connection: read, route, respond, close.

    .equ INITIAL_BUF,   16384
    .equ MAX_HEADER,    65536
    .equ MAX_VALUE,     1048576
    .equ IO_TIMEOUT_S,  10

    .equ SOL_SOCKET,    0xffff
    .equ SO_SNDTIMEO,   0x1005
    .equ SO_RCVTIMEO,   0x1006
    .equ SO_NOSIGPIPE,  0x1022
    .equ IPPROTO_TCP,   6
    .equ TCP_NODELAY,   1
    .equ SHUT_WR,       1
    .equ EINTR,         4

    .equ M_OTHER,  0
    .equ M_GET,    1
    .equ M_PUT,    2
    .equ M_DELETE, 3

    .equ F_JSON, 1                          // response flags
    .equ F_FREE, 2

    .section __TEXT,__cstring,cstring_literals
Lcrlfcrlf:  .asciz "\r\n\r\n"
Lcl_name:   .asciz "content-length:"
Lm_get:     .asciz "GET"
Lm_put:     .asciz "PUT"
Lm_delete:  .asciz "DELETE"
Lp_health:  .asciz "/health"
Lp_kv:      .asciz "/kv"
Lbody_ok:   .asciz "ok"

    // Header fragments (unterminated; lengths come from the end labels).
    .const
Lh_len:     .ascii "Content-Length: "
Lh_len_end:
Lh_json:    .ascii "\r\nContent-Type: application/json"
Lh_json_end:
Lh_close:   .ascii "\r\nConnection: close\r\n\r\n"
Lh_close_end:

    // Status lines: 64-byte records { u16 code, u8 len, text }. 500 is last
    // and doubles as the fallback for unknown codes.
    .p2align 6
Lstatus_tab:
    .short 200
    .byte  2f - 1f
1:  .ascii "HTTP/1.1 200 OK\r\n"
2:  .p2align 6
    .short 201
    .byte  2f - 1f
1:  .ascii "HTTP/1.1 201 Created\r\n"
2:  .p2align 6
    .short 204
    .byte  2f - 1f
1:  .ascii "HTTP/1.1 204 No Content\r\n"
2:  .p2align 6
    .short 400
    .byte  2f - 1f
1:  .ascii "HTTP/1.1 400 Bad Request\r\n"
2:  .p2align 6
    .short 404
    .byte  2f - 1f
1:  .ascii "HTTP/1.1 404 Not Found\r\n"
2:  .p2align 6
    .short 405
    .byte  2f - 1f
1:  .ascii "HTTP/1.1 405 Method Not Allowed\r\n"
2:  .p2align 6
    .short 413
    .byte  2f - 1f
1:  .ascii "HTTP/1.1 413 Content Too Large\r\n"
2:  .p2align 6
    .short 431
    .byte  2f - 1f
1:  .ascii "HTTP/1.1 431 Request Header Fields Too Large\r\n"
2:  .p2align 6
    .short 500
    .byte  2f - 1f
1:  .ascii "HTTP/1.1 500 Internal Server Error\r\n"
2:  .p2align 6

// Byte copy for short strings: dst/src advance, len is consumed.
.macro COPYB dst, src, len, tmp
1:  cbz     \len, 2f
    ldrb    \tmp, [\src], #1
    strb    \tmp, [\dst], #1
    sub     \len, \len, #1
    b       1b
2:
.endm

.macro LOADSTR reg, sym
    adrp    \reg, \sym@PAGE
    add     \reg, \reg, \sym@PAGEOFF
.endm

    .text

// bool bytes_eq(p x0, n x1, q x2, m x3): leaf.
    .p2align 2
_bytes_eq:
    cmp     x1, x3
    b.ne    Leq_no
Leq_loop:
    cbz     x1, Leq_yes
    ldrb    w4, [x0], #1
    ldrb    w5, [x2], #1
    sub     x1, x1, #1
    cmp     w4, w5
    b.eq    Leq_loop
Leq_no:
    mov     w0, #0
    ret
Leq_yes:
    mov     w0, #1
    ret

// bool valid_key(p x0, n x1): [A-Za-z0-9_-]{1,64}. Leaf.
    .p2align 2
_valid_key:
    sub     x9, x1, #1
    cmp     x9, #63
    b.hi    Lkey_bad
Lkey_loop:
    ldrb    w9, [x0], #1
    sub     w10, w9, #'0'
    cmp     w10, #10
    b.lo    Lkey_next
    orr     w10, w9, #0x20                  // fold case
    sub     w10, w10, #'a'
    cmp     w10, #26
    b.lo    Lkey_next
    cmp     w9, #'_'
    b.eq    Lkey_next
    cmp     w9, #'-'
    b.ne    Lkey_bad
Lkey_next:
    subs    x1, x1, #1
    b.ne    Lkey_loop
    mov     w0, #1
    ret
Lkey_bad:
    mov     w0, #0
    ret

// int write_all_iov(fd w0, iov x1, cnt w2) -> 0, or -1 on error.
// Consumes (modifies) the iovec array.
    .p2align 2
_write_all_iov:
    .cfi_startproc
    stp     x22, x21, [sp, #-48]!
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
    mov     w19, w0
    mov     x20, x1
    mov     w21, w2
Lwv_loop:
    mov     w0, w19
    mov     x1, x20
    mov     w2, w21
    bl      _writev
    tbz     x0, #63, Lwv_advance
    bl      ___error
    ldr     w8, [x0]
    cmp     w8, #EINTR
    b.eq    Lwv_loop
    mov     w0, #-1
    b       Lwv_ret
Lwv_advance:
    cbz     w21, Lwv_done
    ldr     x9, [x20, #8]
    cmp     x0, x9
    b.lo    Lwv_partial
    sub     x0, x0, x9
    add     x20, x20, #16
    sub     w21, w21, #1
    b       Lwv_advance
Lwv_partial:
    ldr     x10, [x20]
    add     x10, x10, x0
    sub     x9, x9, x0
    stp     x10, x9, [x20]
    b       Lwv_loop
Lwv_done:
    mov     w0, #0
Lwv_ret:
    ldp     x29, x30, [sp, #32]
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #48
    ret
    .cfi_endproc

// void send_response(fd w0, status w1, body x2, len x3, json w4)
// Frame: [sp,#0] iov[2], [sp,#32..288) header + digit scratch at the top.
    .equ SR_IOV, 0
    .equ SR_HDR, 32
    .equ SR_HDR_END, 288
    .p2align 2
_send_response:
    .cfi_startproc
    sub     sp, sp, #336
    stp     x22, x21, [sp, #288]
    stp     x20, x19, [sp, #304]
    stp     x29, x30, [sp, #320]
    add     x29, sp, #320
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    .cfi_offset w21, -40
    .cfi_offset w22, -48
    mov     w19, w0
    mov     x20, x2
    mov     x21, x3
    mov     w22, w4

    // Status line.
    LOADSTR x9, Lstatus_tab
Lsr_find:
    ldrh    w10, [x9]
    cmp     w10, w1
    b.eq    Lsr_found
    cmp     w10, #500
    b.eq    Lsr_found
    add     x9, x9, #64
    b       Lsr_find
Lsr_found:
    ldrb    w11, [x9, #2]
    add     x12, x9, #3
    add     x13, sp, #SR_HDR                // write cursor
    COPYB   x13, x12, x11, w14

    LOADSTR x12, Lh_len
    mov     x11, #(Lh_len_end - Lh_len)
    COPYB   x13, x12, x11, w14

    // Content-Length digits, generated backwards at the top of the buffer.
    add     x12, sp, #SR_HDR_END
    mov     x14, x21
    mov     x15, #10
Lsr_digit:
    udiv    x10, x14, x15
    msub    x11, x10, x15, x14
    add     w11, w11, #'0'
    strb    w11, [x12, #-1]!
    mov     x14, x10
    cbnz    x14, Lsr_digit
    add     x11, sp, #SR_HDR_END
    sub     x11, x11, x12
    COPYB   x13, x12, x11, w14

    cbz     w22, Lsr_tail
    LOADSTR x12, Lh_json
    mov     x11, #(Lh_json_end - Lh_json)
    COPYB   x13, x12, x11, w14
Lsr_tail:
    LOADSTR x12, Lh_close
    mov     x11, #(Lh_close_end - Lh_close)
    COPYB   x13, x12, x11, w14

    add     x9, sp, #SR_HDR
    sub     x10, x13, x9
    stp     x9, x10, [sp, #SR_IOV]
    stp     x20, x21, [sp, #SR_IOV + 16]
    cmp     x21, #0
    cinc    w2, wzr, ne
    add     w2, w2, #1                      // 1 or 2 iovecs
    mov     w0, w19
    add     x1, sp, #SR_IOV
    bl      _write_all_iov

    ldp     x29, x30, [sp, #320]
    ldp     x20, x19, [sp, #304]
    ldp     x22, x21, [sp, #288]
    add     sp, sp, #336
    ret
    .cfi_endproc

// void *conn_thread(void *fd)
//
// Registers:
//   x19 fd          x20 buf         x21 buf capacity   x22 bytes in buf
//   x23 header end  x24 content-length
//   x25 method len  x26 path offset x27 path len       x28 scratch / method
// At Lrespond: w25 status, x26 body, x27 body len, x28 flags.
    .equ CT_TV,      0                      // struct timeval (16 bytes)
    .equ CT_ONE,     16                     // int 1 for setsockopt
    .equ CT_LINEEND, 24                     // current header line '\n'
    .globl  _conn_thread
    .p2align 2
_conn_thread:
    .cfi_startproc
    sub     sp, sp, #128
    stp     x28, x27, [sp, #32]
    stp     x26, x25, [sp, #48]
    stp     x24, x23, [sp, #64]
    stp     x22, x21, [sp, #80]
    stp     x20, x19, [sp, #96]
    stp     x29, x30, [sp, #112]
    add     x29, sp, #112
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    .cfi_offset w21, -40
    .cfi_offset w22, -48
    .cfi_offset w23, -56
    .cfi_offset w24, -64
    .cfi_offset w25, -72
    .cfi_offset w26, -80
    .cfi_offset w27, -88
    .cfi_offset w28, -96
    mov     x19, x0
    mov     x20, #0

    // Socket options: bounded I/O time, no SIGPIPE, no Nagle delay.
    mov     x9, #IO_TIMEOUT_S
    stp     x9, xzr, [sp, #CT_TV]
    mov     w9, #1
    str     w9, [sp, #CT_ONE]
    mov     w0, w19
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_RCVTIMEO
    add     x3, sp, #CT_TV
    mov     w4, #16
    bl      _setsockopt
    mov     w0, w19
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_SNDTIMEO
    add     x3, sp, #CT_TV
    mov     w4, #16
    bl      _setsockopt
    mov     w0, w19
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_NOSIGPIPE
    add     x3, sp, #CT_ONE
    mov     w4, #4
    bl      _setsockopt
    mov     w0, w19
    mov     w1, #IPPROTO_TCP
    mov     w2, #TCP_NODELAY
    add     x3, sp, #CT_ONE
    mov     w4, #4
    bl      _setsockopt

    mov     x21, #INITIAL_BUF
    mov     x0, x21
    bl      _malloc
    cbz     x0, Lct_500
    mov     x20, x0
    mov     x22, #0

    // ---- read until the end of the header block ----
Lct_hdr:
    cmp     x22, x21
    b.lo    Lct_hdr_read
    mov     x9, #MAX_HEADER
    cmp     x21, x9
    b.hs    Lct_431
    lsl     x1, x21, #1
    mov     x0, x20
    bl      _realloc
    cbz     x0, Lct_500
    mov     x20, x0
    lsl     x21, x21, #1
Lct_hdr_read:
    mov     w0, w19
    add     x1, x20, x22
    sub     x2, x21, x22
    bl      _read
    cmp     x0, #0
    b.le    Lct_close
    add     x22, x22, x0
    mov     x0, x20
    mov     x1, x22
    LOADSTR x2, Lcrlfcrlf
    mov     x3, #4
    bl      _memmem
    cbz     x0, Lct_hdr
    sub     x23, x0, x20
    add     x23, x23, #4

    // ---- request line: METHOD SP PATH SP VERSION ----
    mov     x0, x20
    mov     w1, #'\n'
    mov     x2, x23
    bl      _memchr
    mov     x28, x0                         // end of request line
    mov     x0, x20
    mov     w1, #' '
    sub     x2, x28, x20
    bl      _memchr
    cbz     x0, Lct_400
    sub     x25, x0, x20
    cbz     x25, Lct_400
    add     x26, x25, #1
    add     x0, x20, x26
    mov     w1, #' '
    sub     x2, x28, x0
    bl      _memchr
    cbz     x0, Lct_400
    sub     x27, x0, x20
    sub     x27, x27, x26
    add     x28, x28, #1                    // first header line

    // ---- headers: only Content-Length matters ----
    mov     x24, #0
Lct_line:
    add     x9, x20, x23
    subs    x2, x9, x28
    b.ls    Lct_headers_done
    mov     x0, x28
    mov     w1, #'\n'
    bl      _memchr
    cbz     x0, Lct_headers_done
    str     x0, [sp, #CT_LINEEND]
    sub     x9, x0, x28
    cmp     x9, #15
    b.lo    Lct_line_next
    mov     x0, x28
    LOADSTR x1, Lcl_name
    mov     x2, #15
    bl      _strncasecmp
    cbnz    w0, Lct_line_next

    add     x9, x28, #15                    // value cursor
    ldr     x10, [sp, #CT_LINEEND]
Lct_cl_ws:
    cmp     x9, x10
    b.hs    Lct_400
    ldrb    w12, [x9]
    cmp     w12, #' '
    ccmp    w12, #'\t', #4, ne
    b.ne    Lct_cl_digits
    add     x9, x9, #1
    b       Lct_cl_ws
Lct_cl_digits:
    mov     x24, #0
    mov     x11, #0                         // digit count
    mov     x13, #10
    mov     x14, #0x10000000000             // saturation bound (> MAX_VALUE)
Lct_cl_digit:
    cmp     x9, x10
    b.hs    Lct_cl_end
    ldrb    w12, [x9]
    sub     w12, w12, #'0'
    cmp     w12, #9
    b.hi    Lct_cl_end
    madd    x24, x24, x13, x12
    cmp     x24, x14
    csel    x24, x14, x24, hi
    add     x11, x11, #1
    add     x9, x9, #1
    b       Lct_cl_digit
Lct_cl_end:
    cbz     x11, Lct_400
Lct_cl_trail:
    cmp     x9, x10
    b.hs    Lct_line_next
    ldrb    w12, [x9], #1
    cmp     w12, #' '
    ccmp    w12, #'\t', #4, ne
    ccmp    w12, #'\r', #4, ne
    b.ne    Lct_400
    b       Lct_cl_trail
Lct_line_next:
    ldr     x28, [sp, #CT_LINEEND]
    add     x28, x28, #1
    b       Lct_line
Lct_headers_done:

    // ---- body ----
    mov     x9, #MAX_VALUE
    cmp     x24, x9
    b.hi    Lct_413
    add     x28, x23, x24                   // total request size
    cmp     x28, x21
    b.ls    Lct_body
    mov     x0, x20
    mov     x1, x28
    bl      _realloc
    cbz     x0, Lct_500
    mov     x20, x0
    mov     x21, x28
Lct_body:
    cmp     x22, x28
    b.hs    Lct_route
    mov     w0, w19
    add     x1, x20, x22
    sub     x2, x21, x22
    bl      _read
    cmp     x0, #0
    b.le    Lct_close
    add     x22, x22, x0
    b       Lct_body

    // ---- routing ----
Lct_route:
    mov     x28, #M_GET
    mov     x0, x20
    mov     x1, x25
    LOADSTR x2, Lm_get
    mov     x3, #3
    bl      _bytes_eq
    cbnz    w0, Lct_path
    mov     x28, #M_PUT
    mov     x0, x20
    mov     x1, x25
    LOADSTR x2, Lm_put
    mov     x3, #3
    bl      _bytes_eq
    cbnz    w0, Lct_path
    mov     x28, #M_DELETE
    mov     x0, x20
    mov     x1, x25
    LOADSTR x2, Lm_delete
    mov     x3, #6
    bl      _bytes_eq
    cbnz    w0, Lct_path
    mov     x28, #M_OTHER
Lct_path:
    add     x26, x20, x26                   // path pointer from here on
    mov     x0, x26
    mov     x1, x27
    LOADSTR x2, Lp_health
    mov     x3, #7
    bl      _bytes_eq
    cbnz    w0, Lct_health
    mov     x0, x26
    mov     x1, x27
    LOADSTR x2, Lp_kv
    mov     x3, #3
    bl      _bytes_eq
    cbnz    w0, Lct_list
    cmp     x27, #4
    b.lo    Lct_404
    ldr     w9, [x26]
    movz    w10, #0x6b2f                    // "/kv/" little-endian
    movk    w10, #0x2f76, lsl #16
    cmp     w9, w10
    b.ne    Lct_404
    add     x26, x26, #4                    // key
    sub     x27, x27, #4
    mov     x0, x26
    mov     x1, x27
    bl      _valid_key
    cbz     w0, Lct_400
    cmp     x28, #M_GET
    b.eq    Lct_get
    cmp     x28, #M_PUT
    b.eq    Lct_put
    cmp     x28, #M_DELETE
    b.eq    Lct_delete
    b       Lct_405

Lct_health:
    cmp     x28, #M_GET
    b.ne    Lct_405
    mov     w25, #200
    LOADSTR x26, Lbody_ok
    mov     x27, #2
    mov     x28, #0
    b       Lct_respond

Lct_list:
    cmp     x28, #M_GET
    b.ne    Lct_405
    bl      _kv_list_json
    b       Lct_owned_json

Lct_get:
    mov     x0, x26
    mov     x1, x27
    bl      _kv_get
    mov     w25, w0
    mov     x26, x1
    mov     x27, x2
    mov     x28, #F_FREE
    b       Lct_respond

Lct_put:
    cmp     x24, #1
    csinc   x0, x24, xzr, hs                // malloc(max(len, 1))
    bl      _malloc
    cbz     x0, Lct_500
    mov     x25, x0
    add     x1, x20, x23
    mov     x2, x24
    bl      _memcpy
    mov     x0, x26
    mov     x1, x27
    mov     x2, x25
    mov     x3, x24
    bl      _kv_put                         // takes ownership of x25
    b       Lct_status_only

Lct_delete:
    mov     x0, x26
    mov     x1, x27
    bl      _kv_delete
    b       Lct_status_only

Lct_owned_json:
    mov     w25, w0
    mov     x26, x1
    mov     x27, x2
    mov     x28, #(F_JSON | F_FREE)
    b       Lct_respond

Lct_400:
    mov     w0, #400
    b       Lct_status_only
Lct_404:
    mov     w0, #404
    b       Lct_status_only
Lct_405:
    mov     w0, #405
    b       Lct_status_only
Lct_413:
    mov     w0, #413
    b       Lct_status_only
Lct_431:
    mov     w0, #431
    b       Lct_status_only
Lct_500:
    mov     w0, #500
Lct_status_only:
    mov     w25, w0
    mov     x26, #0
    mov     x27, #0
    mov     x28, #0

Lct_respond:
    mov     w0, w19
    mov     w1, w25
    mov     x2, x26
    mov     x3, x27
    and     w4, w28, #F_JSON
    bl      _send_response
    tbz     x28, #1, Lct_shutdown           // F_FREE
    mov     x0, x26
    bl      _free

    // Half-close, then drain until the peer closes so unread request bytes
    // cannot turn our close into a RST that clobbers the response.
Lct_shutdown:
    mov     w0, w19
    mov     w1, #SHUT_WR
    bl      _shutdown
    cbz     x20, Lct_close
Lct_drain:
    mov     w0, w19
    mov     x1, x20
    mov     x2, x21
    bl      _read
    cmp     x0, #0
    b.gt    Lct_drain

Lct_close:
    mov     w0, w19
    bl      _close
    mov     x0, x20
    bl      _free
    mov     x0, #0
    ldp     x29, x30, [sp, #112]
    ldp     x20, x19, [sp, #96]
    ldp     x22, x21, [sp, #80]
    ldp     x24, x23, [sp, #64]
    ldp     x26, x25, [sp, #48]
    ldp     x28, x27, [sp, #32]
    add     sp, sp, #128
    ret
    .cfi_endproc

.subsections_via_symbols
