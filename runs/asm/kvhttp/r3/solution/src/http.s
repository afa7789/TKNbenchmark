// http.s — per-connection HTTP/1.1 request handling for kvhttp.
//
// conn_main(fd) runs on its own detached thread: it reads one request,
// dispatches it to the store, writes one response and closes the socket.

        .equ    HBUF_SIZE, 65536        // max request line + headers
        .equ    MAX_BODY, 1048576       // 1 MiB value limit
        .equ    DRAIN_MAX, 0x4000000    // discard at most 64 MiB after an early error
        .equ    RESP_BUF, 4096
        .equ    INLINE_MAX, 3584        // bodies up to this size share the header write

        .equ    SOL_SOCKET, 0xffff
        .equ    SO_SNDTIMEO, 0x1005
        .equ    SO_RCVTIMEO, 0x1006
        .equ    IPPROTO_TCP, 6
        .equ    TCP_NODELAY, 1
        .equ    SHUT_WR, 1
        .equ    EINTR, 4

        .equ    KV_PATH_LEN, 3          // "/kv"
        .equ    KV_PREFIX_LEN, 4        // "/kv/"

        .equ    M_OTHER, 0
        .equ    M_GET, 1
        .equ    M_PUT, 2
        .equ    M_DELETE, 3

        // Indices into L_status_tab
        .equ    ST_200, 0
        .equ    ST_201, 1
        .equ    ST_204, 2
        .equ    ST_400, 3
        .equ    ST_404, 4
        .equ    ST_405, 5
        .equ    ST_413, 6
        .equ    ST_431, 7
        .equ    ST_500, 8

.macro  LOADADDR reg, sym
        adrp    \reg, \sym@PAGE
        add     \reg, \reg, \sym@PAGEOFF
.endm

        .section __TEXT,__text,regular,pure_instructions

// void *conn_main(void *fd)
//
// Register plan:
//   x19 fd            x20 header buffer   x21 bytes buffered / body bytes read
//   x22 header end    x23 body buffer     x24 Content-Length
//   x25 method code   x26 path / key ptr  x27 path / key len
//   x28 nonzero => drain unread input before closing
//   [sp,#96], [sp,#104]: out-params for store_get / store_list
        .globl  _conn_main
        .p2align 2
_conn_main:
        stp     x29, x30, [sp, #-112]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]
        stp     x27, x28, [sp, #80]
        mov     x19, x0
        mov     x20, #0
        mov     x23, #0
        mov     x28, #0

        mov     w0, w19
        mov     w1, #SOL_SOCKET
        mov     w2, #SO_RCVTIMEO
        LOADADDR x3, L_io_timeout
        mov     w4, #16
        bl      _setsockopt
        mov     w0, w19
        mov     w1, #SOL_SOCKET
        mov     w2, #SO_SNDTIMEO
        LOADADDR x3, L_io_timeout
        mov     w4, #16
        bl      _setsockopt
        mov     w8, #1
        str     w8, [sp, #104]
        mov     w0, w19
        mov     w1, #IPPROTO_TCP
        mov     w2, #TCP_NODELAY
        add     x3, sp, #104
        mov     w4, #4
        bl      _setsockopt

        mov     x0, #HBUF_SIZE
        bl      _malloc
        cbz     x0, Lc_close
        mov     x20, x0
        mov     x21, #0

        // ---- read until the blank line that ends the header block ----
Lc_read_hdr:
        mov     x8, #HBUF_SIZE
        cmp     x21, x8
        b.hs    Lc_hdr_too_big
        mov     w0, w19
        add     x1, x20, x21
        sub     x2, x8, x21
        bl      _read
        cmp     x0, #0
        b.gt    Lc_scan
        b.eq    Lc_close
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    Lc_read_hdr
        b       Lc_close
Lc_scan:
        subs    x9, x21, #3             // terminator may straddle reads
        csel    x9, xzr, x9, lo
        add     x21, x21, x0
        movz    w12, #0x0a0d
        movk    w12, #0x0a0d, lsl #16   // "\r\n\r\n"
1:      add     x10, x9, #4
        cmp     x10, x21
        b.hi    Lc_read_hdr
        ldr     w11, [x20, x9]
        cmp     w11, w12
        b.eq    2f
        add     x9, x9, #1
        b       1b
2:      add     x22, x9, #4

        // ---- request line: METHOD SP PATH SP VERSION CRLF ----
        mov     x9, #0
1:      ldrb    w10, [x20, x9]
        cmp     w10, #' '
        b.eq    2f
        cmp     w10, #'\r'
        b.eq    Lc_bad_request
        add     x9, x9, #1
        b       1b
2:      cbz     x9, Lc_bad_request
        mov     x27, x9
        mov     x0, x20
        mov     x1, x9
        bl      L_method
        mov     w25, w0
        add     x10, x27, #1            // path start
        mov     x11, x10
3:      ldrb    w12, [x20, x11]
        cmp     w12, #' '
        b.eq    4f
        cmp     w12, #'\r'
        b.eq    Lc_bad_request
        add     x11, x11, #1
        b       3b
4:      subs    x27, x11, x10
        b.eq    Lc_bad_request
        add     x26, x20, x10
5:      ldrb    w12, [x20, x11]         // skip to the first header line
        cmp     w12, #'\n'
        add     x11, x11, #1
        b.ne    5b

        // ---- header lines: only Content-Length matters ----
        mov     x24, #0
        sub     x13, x22, #2            // the final CRLF
Lc_hdr_line:
        cmp     x11, x13
        b.hs    Lc_hdrs_done
        mov     x12, x11
6:      ldrb    w14, [x20, x12]
        cmp     w14, #'\r'
        b.eq    7f
        add     x12, x12, #1
        b       6b
7:      sub     x14, x12, x11           // line = [x11, x12)
        cmp     x14, #15
        b.lo    Lc_next_line
        LOADADDR x15, L_cl_name
        add     x16, x20, x11
        mov     x17, #0
8:      ldrb    w0, [x16, x17]
        sub     w1, w0, #'A'
        cmp     w1, #26
        b.hs    9f
        orr     w0, w0, #0x20           // ASCII lower-case
9:      ldrb    w1, [x15, x17]
        cmp     w0, w1
        b.ne    Lc_next_line
        add     x17, x17, #1
        cmp     x17, #15
        b.lo    8b

        add     x16, x16, #15           // value
        add     x17, x20, x12           // end of line
10:     cmp     x16, x17                // leading whitespace
        b.hs    Lc_bad_request
        ldrb    w0, [x16]
        cmp     w0, #' '
        b.eq    11f
        cmp     w0, #'\t'
        b.ne    12f
11:     add     x16, x16, #1
        b       10b
12:     mov     x24, #0
        mov     x1, #0                  // digit count
        mov     x2, #10
        mov     x3, #MAX_BODY
13:     cmp     x16, x17
        b.hs    15f
        ldrb    w0, [x16]
        sub     w0, w0, #'0'
        cmp     w0, #9
        b.hi    14f
        madd    x24, x24, x2, x0
        cmp     x24, x3
        b.hi    Lc_too_large
        add     x1, x1, #1
        add     x16, x16, #1
        b       13b
14:     ldrb    w0, [x16]               // trailing whitespace only
        cmp     w0, #' '
        b.eq    16f
        cmp     w0, #'\t'
        b.ne    Lc_bad_request
16:     add     x16, x16, #1
        cmp     x16, x17
        b.lo    14b
15:     cbz     x1, Lc_bad_request
Lc_next_line:
        add     x11, x12, #2
        b       Lc_hdr_line

        // ---- body: exactly Content-Length bytes ----
Lc_hdrs_done:
        cmp     x24, #0
        csinc   x0, x24, xzr, ne        // malloc(max(cl, 1))
        bl      _malloc
        cbz     x0, Lc_server_error
        mov     x23, x0
        sub     x2, x21, x22            // body bytes already buffered
        cmp     x2, x24
        csel    x2, x2, x24, lo
        mov     x21, x2
        add     x1, x20, x22
        bl      _memcpy
Lc_read_body:
        cmp     x21, x24
        b.hs    Lc_route
        mov     w0, w19
        add     x1, x23, x21
        sub     x2, x24, x21
        bl      _read
        cmp     x0, #0
        b.gt    1f
        b.eq    Lc_close
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    Lc_read_body
        b       Lc_close
1:      add     x21, x21, x0
        b       Lc_read_body

        // ---- routing ----
Lc_route:
        mov     x0, x26
        mov     x1, x27
        LOADADDR x2, L_p_health
        mov     x3, #L_p_health_len
        bl      L_memeq
        cbnz    w0, Lc_health
        mov     x0, x26
        mov     x1, x27
        LOADADDR x2, L_p_kv
        mov     x3, #KV_PATH_LEN
        bl      L_memeq
        cbnz    w0, Lc_list
        cmp     x27, #KV_PREFIX_LEN
        b.lo    Lc_not_found
        mov     x0, x26
        mov     x1, #KV_PREFIX_LEN     // "/kv/"
        LOADADDR x2, L_p_kv
        mov     x3, #KV_PREFIX_LEN
        bl      L_memeq
        cbz     w0, Lc_not_found
        add     x26, x26, #KV_PREFIX_LEN
        sub     x27, x27, #KV_PREFIX_LEN
        mov     x0, x26
        mov     x1, x27
        bl      L_valid_key
        cbz     w0, Lc_invalid_key
        cmp     w25, #M_GET
        b.eq    Lc_get
        cmp     w25, #M_PUT
        b.eq    Lc_put
        cmp     w25, #M_DELETE
        b.eq    Lc_delete
        b       Lc_method_not_allowed

Lc_health:
        cmp     w25, #M_GET
        b.ne    Lc_method_not_allowed
        mov     w1, #ST_200
        LOADADDR x2, L_ok
        mov     x3, #2
        mov     w4, #0
        b       Lc_respond

Lc_list:
        cmp     w25, #M_GET
        b.ne    Lc_method_not_allowed
        add     x0, sp, #96
        add     x1, sp, #104
        bl      _store_list
        cbnz    x0, Lc_internal_error
        mov     w4, #1
        b       Lc_respond_owned

Lc_get:
        mov     x0, x26
        mov     x1, x27
        add     x2, sp, #96
        add     x3, sp, #104
        bl      _store_get
        cmp     x0, #0
        b.eq    Lc_not_found
        b.lt    Lc_internal_error
        mov     w4, #0
Lc_respond_owned:                       // 200 with malloc'd body at [sp,#96]
        mov     w0, w19
        mov     w1, #ST_200
        ldp     x2, x3, [sp, #96]
        bl      L_respond
        ldr     x0, [sp, #96]
        bl      _free
        b       Lc_close

Lc_put:
        mov     x0, x26
        mov     x1, x27
        mov     x2, x23
        mov     x3, x24
        bl      _store_put
        cmp     x0, #0
        b.lt    Lc_internal_error
        mov     x23, #0                 // the store owns the body now
        mov     w1, #ST_200
        mov     w2, #ST_201
        csel    w1, w2, w1, gt
        b       Lc_respond_empty

Lc_delete:
        mov     x0, x26
        mov     x1, x27
        bl      _store_delete
        cbz     x0, Lc_not_found
        mov     w1, #ST_204
        b       Lc_respond_empty

Lc_not_found:
        mov     w1, #ST_404
        b       Lc_respond_empty
Lc_invalid_key:
        mov     w1, #ST_400
        b       Lc_respond_empty
Lc_method_not_allowed:
        mov     w1, #ST_405
        b       Lc_respond_empty
Lc_internal_error:
        mov     w1, #ST_500
        b       Lc_respond_empty

        // Errors detected before the body was consumed: drain afterwards so
        // the client sees the response instead of a connection reset.
Lc_bad_request:
        mov     w1, #ST_400
        b       Lc_respond_early
Lc_too_large:
        mov     w1, #ST_413
        b       Lc_respond_early
Lc_hdr_too_big:
        mov     w1, #ST_431
        b       Lc_respond_early
Lc_server_error:
        mov     w1, #ST_500
Lc_respond_early:
        mov     x28, #1
Lc_respond_empty:
        mov     x2, #0
        mov     x3, #0
        mov     w4, #0
Lc_respond:
        mov     w0, w19
        bl      L_respond

Lc_close:
        cbz     x28, 2f
        cbz     x20, 2f
        mov     w0, w19
        mov     w1, #SHUT_WR
        bl      _shutdown
        mov     x21, #0
1:      mov     w0, w19
        mov     x1, x20
        mov     x2, #HBUF_SIZE
        bl      _read
        cmp     x0, #0
        b.le    2f
        add     x21, x21, x0
        mov     x8, #DRAIN_MAX
        cmp     x21, x8
        b.lo    1b
2:      mov     x0, x23
        bl      _free
        mov     x0, x20
        bl      _free
        mov     w0, w19
        bl      _close
        mov     x0, #0
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #112
        ret

// Send a complete response.
// In: w0 fd, w1 status index, x2 body, x3 body length, w4 nonzero => JSON.
        .p2align 2
L_respond:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        sub     sp, sp, #RESP_BUF
        mov     w19, w0
        mov     x20, x2
        mov     x21, x3
        mov     w22, w4
        LOADADDR x8, L_status_tab
        add     x8, x8, w1, uxtw #4
        ldp     x9, x10, [x8]           // status text, length

        mov     x0, sp
        LOADADDR x1, L_h_proto
        mov     x2, #L_h_proto_len
        bl      L_copy
        mov     x1, x9
        mov     x2, x10
        bl      L_copy
        LOADADDR x1, L_h_clen
        mov     x2, #L_h_clen_len
        bl      L_copy
        mov     x1, x21
        bl      L_utoa
        cbz     w22, 1f
        LOADADDR x1, L_h_json
        mov     x2, #L_h_json_len
        bl      L_copy
1:      LOADADDR x1, L_h_end
        mov     x2, #L_h_end_len
        bl      L_copy

        cmp     x21, #INLINE_MAX
        b.hi    2f
        mov     x1, x20                 // small body: one write
        mov     x2, x21
        bl      L_copy
        mov     x1, sp
        sub     x2, x0, x1
        mov     w0, w19
        bl      L_write_all
        b       3f
2:      mov     x1, sp
        sub     x2, x0, x1
        mov     w0, w19
        bl      L_write_all
        cbnz    x0, 3f
        mov     w0, w19
        mov     x1, x20
        mov     x2, x21
        bl      L_write_all
3:      add     sp, sp, #RESP_BUF
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// Write the whole buffer. In: w0 fd, x1 buf, x2 len. Out: x0 0 ok, -1 error.
        .p2align 2
L_write_all:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        str     x21, [sp, #32]
        mov     w19, w0
        mov     x20, x1
        mov     x21, x2
1:      cbz     x21, 3f
        mov     w0, w19
        mov     x1, x20
        mov     x2, x21
        bl      _write
        cmp     x0, #0
        b.le    2f
        add     x20, x20, x0
        sub     x21, x21, x0
        b       1b
2:      b.eq    4f
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    1b
4:      mov     x0, #-1
        b       5f
3:      mov     x0, #0
5:      ldr     x21, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// Leaf. Copy x2 bytes from x1 to x0; returns x0 advanced past the copy.
// Clobbers x0-x3 only.
        .p2align 2
L_copy:
        cbz     x2, 2f
1:      ldrb    w3, [x1], #1
        strb    w3, [x0], #1
        subs    x2, x2, #1
        b.ne    1b
2:      ret

// Leaf. Write x1 in decimal at x0; returns x0 advanced. Clobbers x0-x6.
        .p2align 2
L_utoa:
        mov     x5, #10
        mov     x2, x1
        mov     x3, #0
1:      udiv    x2, x2, x5              // count digits
        add     x3, x3, #1
        cbnz    x2, 1b
        add     x4, x0, x3
        mov     x0, x4
2:      udiv    x2, x1, x5
        msub    x6, x2, x5, x1
        add     w6, w6, #'0'
        strb    w6, [x4, #-1]!
        mov     x1, x2
        cbnz    x1, 2b
        ret

// Leaf. w0 = (x1 == x3 && memcmp(x0, x2, x1) == 0).
        .p2align 2
L_memeq:
        cmp     x1, x3
        b.ne    3f
        cbz     x1, 2f
1:      ldrb    w4, [x0], #1
        ldrb    w5, [x2], #1
        cmp     w4, w5
        b.ne    3f
        subs    x1, x1, #1
        b.ne    1b
2:      mov     w0, #1
        ret
3:      mov     w0, #0
        ret

// Leaf. w0 = key (x0, x1) matches [A-Za-z0-9_-]{1,64}.
        .p2align 2
L_valid_key:
        sub     x2, x1, #1
        cmp     x2, #64                 // unsigned: rejects 0 and > 64
        b.hs    3f
1:      ldrb    w2, [x0], #1
        sub     w3, w2, #'0'
        cmp     w3, #10
        b.lo    2f
        orr     w3, w2, #0x20           // fold case
        sub     w3, w3, #'a'
        cmp     w3, #26
        b.lo    2f
        cmp     w2, #'_'
        b.eq    2f
        cmp     w2, #'-'
        b.ne    3f
2:      subs    x1, x1, #1
        b.ne    1b
        mov     w0, #1
        ret
3:      mov     w0, #0
        ret

// Leaf. Map method token (x0, x1) to an M_* code.
        .p2align 2
L_method:
        cmp     x1, #3
        b.eq    1f
        cmp     x1, #6
        b.eq    2f
        b       9f
1:      ldrh    w2, [x0]
        ldrb    w3, [x0, #2]
        orr     w2, w2, w3, lsl #16
        movz    w4, #0x4547             // "GET"
        movk    w4, #0x54, lsl #16
        cmp     w2, w4
        b.eq    3f
        movz    w4, #0x5550             // "PUT"
        movk    w4, #0x54, lsl #16
        cmp     w2, w4
        b.eq    4f
        b       9f
2:      ldr     w2, [x0]
        ldrh    w3, [x0, #4]
        movz    w4, #0x4544             // "DELE"
        movk    w4, #0x454c, lsl #16
        cmp     w2, w4
        b.ne    9f
        mov     w4, #0x4554             // "TE"
        cmp     w3, w4
        b.ne    9f
        mov     w0, #M_DELETE
        ret
3:      mov     w0, #M_GET
        ret
4:      mov     w0, #M_PUT
        ret
9:      mov     w0, #M_OTHER
        ret

// ---------------------------------------------------------------------------

        .section __TEXT,__const
        .p2align 3
L_io_timeout:                           // struct timeval { 30 s }
        .quad   30
        .long   0, 0

L_cl_name:      .ascii "content-length:"
L_p_health:     .ascii "/health"
        .equ    L_p_health_len, . - L_p_health
L_p_kv:         .ascii "/kv/"                   // "/kv" route and "/kv/" key prefix
L_ok:           .ascii "ok"
L_h_proto:      .ascii "HTTP/1.1 "
        .equ    L_h_proto_len, . - L_h_proto
L_h_clen:       .ascii "\r\nContent-Length: "
        .equ    L_h_clen_len, . - L_h_clen
L_h_json:       .ascii "\r\nContent-Type: application/json"
        .equ    L_h_json_len, . - L_h_json
L_h_end:        .ascii "\r\nConnection: close\r\n\r\n"
        .equ    L_h_end_len, . - L_h_end

L_s200: .ascii "200 OK"
L_s201: .ascii "201 Created"
L_s204: .ascii "204 No Content"
L_s400: .ascii "400 Bad Request"
L_s404: .ascii "404 Not Found"
L_s405: .ascii "405 Method Not Allowed"
L_s413: .ascii "413 Content Too Large"
L_s431: .ascii "431 Request Header Fields Too Large"
L_s500: .ascii "500 Internal Server Error"
L_s_end:

        .section __DATA,__const
        .p2align 3
L_status_tab:                           // { const char *text; size_t len; }
        .quad   L_s200, L_s201 - L_s200
        .quad   L_s201, L_s204 - L_s201
        .quad   L_s204, L_s400 - L_s204
        .quad   L_s400, L_s404 - L_s400
        .quad   L_s404, L_s405 - L_s404
        .quad   L_s405, L_s413 - L_s405
        .quad   L_s413, L_s431 - L_s413
        .quad   L_s431, L_s500 - L_s431
        .quad   L_s500, L_s_end - L_s500
