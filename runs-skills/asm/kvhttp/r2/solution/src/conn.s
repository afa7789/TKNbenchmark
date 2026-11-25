// conn.s — one HTTP/1.1 request per connection.
//
//   void *conn_main(void *fd)     pthread entry; owns and closes the socket.
//
// Flow: read until the header terminator, parse the request line and
// Content-Length, read the whole body, route, write one response
// (always with Content-Length and `Connection: close`), close.

    .equ HDR_CAP,   65536           // max bytes of request line + headers
    .equ MAX_BODY,  1048576         // 1 MiB value limit
    .equ IO_TIMEOUT, 30             // seconds, SO_RCVTIMEO / SO_SNDTIMEO

    .equ SOL_SOCKET,  0xffff
    .equ SO_SNDTIMEO, 0x1005
    .equ SO_RCVTIMEO, 0x1006
    .equ EINTR, 4

    .equ CH_TAB, 9
    .equ CH_LF, 10
    .equ CH_CR, 13
    .equ CH_SP, 32

    // method ids
    .equ M_OTHER, 0
    .equ M_GET, 1
    .equ M_PUT, 2
    .equ M_DELETE, 3

    // conn_main frame (sp-relative)
    .equ F_HDR,     0               // char[256] response header
    .equ F_IOV,     256             // struct iovec[2]
    .equ F_RBODY,   288             // response body ptr
    .equ F_RLEN,    296             // response body len
    .equ F_RFREE,   304             // buffer to free after responding
    .equ F_JSON,    312             // nonzero: add Content-Type: application/json
    .equ F_TV,      320             // struct timeval
    .equ F_REGS,    384
    .equ F_SIZE,    480

    .text
    .globl  _conn_main
    .p2align 2
_conn_main:
    .cfi_startproc
    sub     sp, sp, #F_SIZE
    stp     x28, x27, [sp, #F_REGS]
    stp     x26, x25, [sp, #F_REGS + 16]
    stp     x24, x23, [sp, #F_REGS + 32]
    stp     x22, x21, [sp, #F_REGS + 48]
    stp     x20, x19, [sp, #F_REGS + 64]
    stp     x29, x30, [sp, #F_REGS + 80]
    add     x29, sp, #F_REGS + 80
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

    // Register roles:
    //   w19 fd           x20 header buffer    x21 bytes read / method id
    //   x22 header end   x23 method length    x24 path        x25 path length
    //   x26 Content-Length                     x27 request body x28 status
    mov     w19, w0
    mov     x20, #0
    mov     x27, #0
    stp     xzr, xzr, [sp, #F_RBODY]
    stp     xzr, xzr, [sp, #F_RFREE]

    mov     x8, #IO_TIMEOUT
    stp     x8, xzr, [sp, #F_TV]
    mov     w0, w19
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_RCVTIMEO
    add     x3, sp, #F_TV
    mov     w4, #16
    bl      _setsockopt
    mov     w0, w19
    mov     w1, #SOL_SOCKET
    mov     w2, #SO_SNDTIMEO
    add     x3, sp, #F_TV
    mov     w4, #16
    bl      _setsockopt

    mov     x0, #HDR_CAP
    bl      _malloc
    cbz     x0, Lclose
    mov     x20, x0
    mov     x21, #0

    // ---- read until "\r\n\r\n" -------------------------------------------
Lread_more:
    mov     x8, #HDR_CAP
    cmp     x21, x8
    b.hs    Lbad_request
    mov     w0, w19
    add     x1, x20, x21
    sub     x2, x8, x21
    bl      _read
    cmp     x0, #0
    b.gt    Lgot_bytes
    b.eq    Lclose
    bl      ___error
    ldr     w8, [x0]
    cmp     w8, #EINTR
    b.eq    Lread_more
    b       Lclose
Lgot_bytes:
    subs    x9, x21, #3                 // rescan the last 3 old bytes
    csel    x9, x9, xzr, hs
    add     x21, x21, x0
    movz    w10, #0x0a0d
    movk    w10, #0x0a0d, lsl #16       // "\r\n\r\n" as a little-endian word
Lscan:
    add     x11, x9, #4
    cmp     x11, x21
    b.hi    Lread_more
    ldr     w12, [x20, x9]
    cmp     w12, w10
    b.eq    Lhdr_done
    add     x9, x9, #1
    b       Lscan
Lhdr_done:
    add     x22, x9, #4

    // ---- request line: METHOD SP PATH SP VERSION CRLF ----------------------
    mov     x9, #0
1:  ldrb    w10, [x20, x9]
    cmp     w10, #CH_SP
    b.eq    2f
    cmp     w10, #CH_CR
    b.eq    Lbad_request
    add     x9, x9, #1
    b       1b
2:  cbz     x9, Lbad_request
    mov     x23, x9
    add     x9, x9, #1
    add     x24, x20, x9
    mov     x10, x9
3:  ldrb    w11, [x20, x10]
    cmp     w11, #CH_SP
    b.eq    4f
    cmp     w11, #CH_CR
    b.eq    Lbad_request
    add     x10, x10, #1
    b       3b
4:  sub     x25, x10, x9
    cbz     x25, Lbad_request
5:  ldrb    w11, [x20, x10]             // skip to the first header line
    add     x10, x10, #1
    cmp     w11, #CH_LF
    b.ne    5b

    add     x0, x20, x10
    add     x1, x20, x22
    bl      Lcontent_length
    tbnz    x0, #63, Lbad_request
    mov     x26, x0
    mov     x8, #MAX_BODY
    cmp     x26, x8
    b.hi    Ltoo_large

    // ---- body -------------------------------------------------------------
    cbz     x26, Lroute
    mov     x0, x26
    bl      _malloc
    cbz     x0, Linternal
    mov     x27, x0
    sub     x2, x21, x22                // bytes already buffered past headers
    cmp     x2, x26
    csel    x2, x2, x26, lo
    mov     x28, x2
    add     x1, x20, x22
    bl      _memcpy
Lbody_more:
    cmp     x28, x26
    b.hs    Lroute
    mov     w0, w19
    add     x1, x27, x28
    sub     x2, x26, x28
    bl      _read
    cmp     x0, #0
    b.gt    1f
    b.eq    Lclose
    bl      ___error
    ldr     w8, [x0]
    cmp     w8, #EINTR
    b.eq    Lbody_more
    b       Lclose
1:  add     x28, x28, x0
    b       Lbody_more

    // ---- routing ----------------------------------------------------------
Lroute:
    // classify the method (the buffer is HDR_CAP bytes, so 8-byte loads are safe)
    mov     x21, #M_OTHER
    ldr     x9, [x20]
    cmp     x23, #3
    b.ne    1f
    and     w10, w9, #0xffffff
    movz    w11, #0x4547
    movk    w11, #0x54, lsl #16         // "GET"
    mov     x12, #M_GET
    cmp     w10, w11
    csel    x21, x12, x21, eq
    movz    w11, #0x5550
    movk    w11, #0x54, lsl #16         // "PUT"
    mov     x12, #M_PUT
    cmp     w10, w11
    csel    x21, x12, x21, eq
    b       2f
1:  cmp     x23, #6
    b.ne    2f
    and     x10, x9, #0xffffffffffff
    movz    x11, #0x4544
    movk    x11, #0x454c, lsl #16
    movk    x11, #0x4554, lsl #32       // "DELETE"
    mov     x12, #M_DELETE
    cmp     x10, x11
    csel    x21, x12, x21, eq
2:
    // "/health"
    cmp     x25, #7
    b.ne    Lroute_kv
    ldr     x10, [x24]
    and     x10, x10, #0x00ffffffffffffff
    movz    x11, #0x682f
    movk    x11, #0x6165, lsl #16
    movk    x11, #0x746c, lsl #32
    movk    x11, #0x0068, lsl #48
    cmp     x10, x11
    b.ne    Lroute_kv
    cmp     x21, #M_GET
    b.ne    Lnot_allowed
    adrp    x8, Lok_body@PAGE
    add     x8, x8, Lok_body@PAGEOFF
    mov     x9, #2
    stp     x8, x9, [sp, #F_RBODY]
    mov     w28, #200
    b       Lrespond

Lroute_kv:
    // "/kv" or "/kv/<key>"
    cmp     x25, #3
    b.lo    Lnot_found
    ldr     w10, [x24]
    and     w11, w10, #0xffffff
    movz    w12, #0x6b2f
    movk    w12, #0x76, lsl #16         // "/kv"
    cmp     w11, w12
    b.ne    Lnot_found
    cmp     x25, #3
    b.eq    Lkv_root
    lsr     w11, w10, #24
    cmp     w11, #'/'
    b.ne    Lnot_found

    add     x0, x24, #4
    sub     x1, x25, #4
    bl      Lvalid_key
    cbz     w0, Lbad_request
    add     x0, x24, #4
    sub     x1, x25, #4
    cmp     x21, #M_GET
    b.eq    Lkv_get
    cmp     x21, #M_PUT
    b.eq    Lkv_put
    cmp     x21, #M_DELETE
    b.eq    Lkv_delete
    b       Lnot_allowed

Lkv_get:
    add     x2, sp, #F_RBODY
    add     x3, sp, #F_RLEN
    bl      _kv_get
    mov     w28, w0
    ldr     x8, [sp, #F_RBODY]
    str     x8, [sp, #F_RFREE]
    b       Lrespond

Lkv_put:
    mov     x2, x27                     // ownership moves to the store
    mov     x3, x26
    mov     x27, #0
    bl      _kv_put
    mov     w28, w0
    b       Lrespond

Lkv_delete:
    bl      _kv_delete
    mov     w28, w0
    b       Lrespond

Lkv_root:
    cmp     x21, #M_GET
    b.ne    Lnot_allowed
    add     x0, sp, #F_RBODY
    add     x1, sp, #F_RLEN
    bl      _kv_list
    mov     w28, w0
    ldr     x8, [sp, #F_RBODY]
    str     x8, [sp, #F_RFREE]
    cmp     w28, #200
    cset    w8, eq
    str     w8, [sp, #F_JSON]
    b       Lrespond

Lbad_request:
    mov     w28, #400
    b       Lrespond
Lnot_found:
    mov     w28, #404
    b       Lrespond
Lnot_allowed:
    mov     w28, #405
    b       Lrespond
Ltoo_large:
    mov     w28, #413
    b       Lrespond
Linternal:
    mov     w28, #500

    // ---- response ---------------------------------------------------------
Lrespond:
    mov     w0, w28
    bl      Lstatus_line                // x1 = "HTTP/1.1 NNN Reason\r\n"
    add     x0, sp, #F_HDR
    bl      Lappend
    ldr     w8, [sp, #F_JSON]
    cbz     w8, 1f
    adrp    x1, Lhdr_json@PAGE
    add     x1, x1, Lhdr_json@PAGEOFF
    bl      Lappend
1:  adrp    x1, Lhdr_length@PAGE
    add     x1, x1, Lhdr_length@PAGEOFF
    bl      Lappend
    ldr     x1, [sp, #F_RLEN]
    bl      Lappend_u64
    adrp    x1, Lhdr_tail@PAGE
    add     x1, x1, Lhdr_tail@PAGEOFF
    bl      Lappend

    add     x8, sp, #F_HDR
    sub     x9, x0, x8
    stp     x8, x9, [sp, #F_IOV]
    ldp     x10, x11, [sp, #F_RBODY]
    stp     x10, x11, [sp, #F_IOV + 16]
    mov     w0, w19
    add     x1, sp, #F_IOV
    mov     w2, #2
    bl      Lwritev_all

Lclose:
    ldr     x0, [sp, #F_RFREE]
    bl      _free
    mov     x0, x27
    bl      _free
    mov     x0, x20
    bl      _free
    mov     w0, w19
    bl      _close
    mov     x0, #0
    ldp     x29, x30, [sp, #F_REGS + 80]
    ldp     x20, x19, [sp, #F_REGS + 64]
    ldp     x22, x21, [sp, #F_REGS + 48]
    ldp     x24, x23, [sp, #F_REGS + 32]
    ldp     x26, x25, [sp, #F_REGS + 16]
    ldp     x28, x27, [sp, #F_REGS]
    add     sp, sp, #F_SIZE
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// Lcontent_length — leaf.  x0 = first header line, x1 = end of headers
// (just past "\r\n\r\n").  Returns x0 = Content-Length (0 if absent) or -1
// if the value is malformed.  The region always ends in CRLF CRLF, which
// bounds every scan below.
    .p2align 2
Lcontent_length:
    .cfi_startproc
    mov     x9, #0
    adrp    x10, Lcl_name@PAGE
    add     x10, x10, Lcl_name@PAGEOFF
Lcl_line:
    cmp     x0, x1
    b.hs    Lcl_done
    mov     x2, #0
Lcl_cmp:                                // case-insensitive "content-length:"
    ldrb    w3, [x10, x2]
    cbz     w3, Lcl_match
    ldrb    w4, [x0, x2]
    sub     w5, w4, #'A'
    cmp     w5, #25
    b.hi    1f
    orr     w4, w4, #0x20
1:  cmp     w4, w3
    b.ne    Lcl_skip
    add     x2, x2, #1
    b       Lcl_cmp
Lcl_match:
    add     x0, x0, x2
2:  ldrb    w4, [x0]                    // leading OWS
    cmp     w4, #CH_SP
    b.eq    3f
    cmp     w4, #CH_TAB
    b.ne    4f
3:  add     x0, x0, #1
    b       2b
4:  mov     x9, #0
    mov     x6, #0                      // digit count
    mov     x7, #10
5:  ldrb    w4, [x0]
    sub     w5, w4, #'0'
    cmp     w5, #9
    b.hi    6f
    madd    x9, x9, x7, x5
    add     x6, x6, #1
    cmp     x6, #18                     // keeps the value well inside int64
    b.hi    Lcl_bad
    add     x0, x0, #1
    b       5b
6:  cbz     x6, Lcl_bad
7:  cmp     w4, #CH_SP                  // trailing OWS, then CR
    b.eq    8f
    cmp     w4, #CH_TAB
    b.ne    9f
8:  add     x0, x0, #1
    ldrb    w4, [x0]
    b       7b
9:  cmp     w4, #CH_CR
    b.ne    Lcl_bad
Lcl_skip:
    ldrb    w4, [x0], #1
    cmp     w4, #CH_LF
    b.ne    Lcl_skip
    b       Lcl_line
Lcl_done:
    mov     x0, x9
    ret
Lcl_bad:
    mov     x0, #-1
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// Lvalid_key — leaf.  x0 = ptr, x1 = len.  w0 = 1 if [A-Za-z0-9_-]{1,64}.
    .p2align 2
Lvalid_key:
    .cfi_startproc
    sub     x2, x1, #1
    cmp     x2, #63
    b.hi    Lkey_bad
1:  ldrb    w3, [x0], #1
    sub     w4, w3, #'0'
    cmp     w4, #9
    b.ls    2f
    orr     w4, w3, #0x20
    sub     w4, w4, #'a'
    cmp     w4, #25
    b.ls    2f
    cmp     w3, #'_'
    b.eq    2f
    cmp     w3, #'-'
    b.ne    Lkey_bad
2:  subs    x1, x1, #1
    b.ne    1b
    mov     w0, #1
    ret
Lkey_bad:
    mov     w0, #0
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// Lstatus_line — leaf.  w0 = status code.  x1 = full status line string.
    .macro STATUS code, label
    cmp     w0, #\code
    b.ne    1f
    adrp    x1, \label@PAGE
    add     x1, x1, \label@PAGEOFF
    ret
1:
    .endm

    .p2align 2
Lstatus_line:
    .cfi_startproc
    STATUS  200, Ls200
    STATUS  201, Ls201
    STATUS  204, Ls204
    STATUS  400, Ls400
    STATUS  404, Ls404
    STATUS  405, Ls405
    STATUS  413, Ls413
    adrp    x1, Ls500@PAGE
    add     x1, x1, Ls500@PAGEOFF
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// Lappend — leaf.  Copy NUL-terminated x1 to x0; return x0 = end of copy.
    .p2align 2
Lappend:
    .cfi_startproc
1:  ldrb    w2, [x1], #1
    cbz     w2, 2f
    strb    w2, [x0], #1
    b       1b
2:  ret
    .cfi_endproc

// Lappend_u64 — leaf.  Write x1 in decimal at x0; return x0 = end.
    .p2align 2
Lappend_u64:
    .cfi_startproc
    mov     x4, #10
    mov     x2, x1
    mov     x3, #0
1:  udiv    x2, x2, x4                  // count digits
    add     x3, x3, #1
    cbnz    x2, 1b
    add     x0, x0, x3
    mov     x5, x0
2:  udiv    x2, x1, x4                  // emit back to front
    msub    x6, x2, x4, x1
    add     w6, w6, #'0'
    strb    w6, [x5, #-1]!
    mov     x1, x2
    cbnz    x1, 2b
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// Lwritev_all — w0 = fd, x1 = iovec array (modified), w2 = count.
// Writes everything, retrying on EINTR and short writes.  w0 = 0 / -1.
    .p2align 2
Lwritev_all:
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
Lwv_skip:                               // drop exhausted leading iovecs
    cbz     w21, Lwv_ok
    ldr     x8, [x20, #8]
    cbnz    x8, Lwv_write
    add     x20, x20, #16
    sub     w21, w21, #1
    b       Lwv_skip
Lwv_write:
    mov     w0, w19
    mov     x1, x20
    mov     w2, w21
    bl      _writev
    tbz     x0, #63, Lwv_advance
    bl      ___error
    ldr     w8, [x0]
    cmp     w8, #EINTR
    b.eq    Lwv_write
    mov     w0, #-1
    b       Lwv_ret
Lwv_advance:                            // consume x0 bytes from the iovecs
    cbz     x0, Lwv_skip
    ldp     x9, x8, [x20]
    cmp     x0, x8
    b.lo    1f
    sub     x0, x0, x8
    str     xzr, [x20, #8]
    add     x20, x20, #16
    sub     w21, w21, #1
    cbz     w21, Lwv_ok
    b       Lwv_advance
1:  add     x9, x9, x0
    sub     x8, x8, x0
    stp     x9, x8, [x20]
    b       Lwv_skip
Lwv_ok:
    mov     w0, #0
Lwv_ret:
    ldp     x29, x30, [sp, #32]
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #48
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
    .section __TEXT,__cstring,cstring_literals
Lok_body:       .asciz "ok"
Lcl_name:       .asciz "content-length:"
Lhdr_json:      .asciz "Content-Type: application/json\r\n"
Lhdr_length:    .asciz "Content-Length: "
Lhdr_tail:      .asciz "\r\nConnection: close\r\n\r\n"
Ls200:          .asciz "HTTP/1.1 200 OK\r\n"
Ls201:          .asciz "HTTP/1.1 201 Created\r\n"
Ls204:          .asciz "HTTP/1.1 204 No Content\r\n"
Ls400:          .asciz "HTTP/1.1 400 Bad Request\r\n"
Ls404:          .asciz "HTTP/1.1 404 Not Found\r\n"
Ls405:          .asciz "HTTP/1.1 405 Method Not Allowed\r\n"
Ls413:          .asciz "HTTP/1.1 413 Content Too Large\r\n"
Ls500:          .asciz "HTTP/1.1 500 Internal Server Error\r\n"

.subsections_via_symbols
