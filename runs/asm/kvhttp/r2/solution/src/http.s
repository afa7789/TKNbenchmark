// kvhttp — per-connection HTTP/1.1 handling: read the request head and body,
// route it, write one response, close.

        .include "defs.inc"

        .section __TEXT,__text,regular,pure_instructions

// void *conn_thread(void *fd) — pthread entry point.
        .globl _conn_thread
        .p2align 2
_conn_thread:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        bl      _handle_conn
        mov     x0, #0
        ldp     x29, x30, [sp], #16
        ret

// Locals of _handle_conn (offsets from sp after the prologue).
        .equ L_EXPECT,   0      // nonzero if the client sent "Expect:"
        .equ L_NEXT,     8      // offset of the next header line
        .equ L_LINE,     16     // current header line pointer
        .equ L_LINELEN,  24     // current header line length
        .equ L_SIZE,     32

// handle_conn(fd w0)
//
// Register use:
//   w19 fd            x20 head buffer     x21 bytes in head buffer
//   x22 head end      x23 method len, then method code
//   x24 path offset, then path pointer    x25 path len
//   x26 content length                    x27 body buffer (owned, or 0)
//   x28 scratch (header cursor / bytes received / response buffer)
        .p2align 2
_handle_conn:
        stp     x29, x30, [sp, #-96]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]
        stp     x27, x28, [sp, #80]
        sub     sp, sp, #L_SIZE
        mov     w19, w0
        mov     x27, #0
        str     xzr, [sp, #L_EXPECT]

        mov     x0, #HDR_CAP
        bl      _malloc
        mov     x20, x0
        cbz     x20, Lhc_done
        mov     x21, #0

        // ---- read until the end of the request head ----
Lhc_read_head:
        mov     x2, #HDR_CAP
        subs    x2, x2, x21
        b.eq    Lhc_431
        mov     w0, w19
        add     x1, x20, x21
        bl      _read_some
        cmp     x0, #0
        b.le    Lhc_done
        subs    x1, x21, #3                     // rescan the last 3 old bytes
        csel    x1, xzr, x1, lt
        add     x21, x21, x0
        mov     x0, x20
        mov     x2, x21
        bl      _find_hdr_end
        tbnz    x0, #63, Lhc_read_head
        mov     x22, x0

        // ---- request line: METHOD SP PATH SP VERSION ----
        mov     x0, x20
        mov     x1, #0
        mov     x2, x22
        mov     w3, #' '
        bl      _find_byte
        tbnz    x0, #63, Lhc_400
        cbz     x0, Lhc_400
        mov     x23, x0
        add     x24, x0, #1
        mov     x0, x20
        mov     x1, x24
        mov     x2, x22
        mov     w3, #' '
        bl      _find_byte
        tbnz    x0, #63, Lhc_400
        subs    x25, x0, x24
        b.eq    Lhc_400

        mov     x0, x20
        mov     x1, x24
        mov     x2, x22
        mov     w3, #'\n'
        bl      _find_byte
        add     x28, x0, #1                     // first header line
        mov     x26, #0

        // ---- header lines ----
Lhc_hdr_loop:
        cmp     x28, x22
        b.hs    Lhc_body
        mov     x0, x20
        mov     x1, x28
        mov     x2, x22
        mov     w3, #'\n'
        bl      _find_byte
        add     x8, x0, #1
        str     x8, [sp, #L_NEXT]
        sub     x1, x0, x28                     // line length (excl. '\n')
        add     x0, x20, x28                    // line start
        stp     x0, x1, [sp, #L_LINE]

        LOADADDR x2, Lhdr_clen
        mov     x3, #(Lhdr_clen_end - Lhdr_clen)
        bl      _match_header
        cbz     x0, 1f
        bl      _parse_uint
        tbnz    x0, #63, Lhc_400
        mov     x26, x0
        b       2f
1:      ldp     x0, x1, [sp, #L_LINE]
        LOADADDR x2, Lhdr_expect
        mov     x3, #(Lhdr_expect_end - Lhdr_expect)
        bl      _match_header
        cbz     x0, 2f
        mov     x8, #1
        str     x8, [sp, #L_EXPECT]
2:      ldr     x28, [sp, #L_NEXT]
        b       Lhc_hdr_loop

        // ---- body: exactly Content-Length bytes ----
Lhc_body:
        mov     x8, #MAX_BODY
        cmp     x26, x8
        b.hi    Lhc_413
        add     x0, x26, #1
        bl      _malloc
        cbz     x0, Lhc_500
        mov     x27, x0
        sub     x2, x21, x22                    // body bytes already buffered
        cmp     x2, x26
        csel    x2, x2, x26, ls
        mov     x28, x2
        add     x1, x20, x22
        bl      _memcpy

        cmp     x28, x26
        b.hs    Lhc_route
        ldr     x8, [sp, #L_EXPECT]
        cbz     x8, Lhc_body_loop
        mov     w0, w19
        LOADADDR x1, Lresp_continue
        mov     x2, #(Lresp_continue_end - Lresp_continue)
        bl      _write_all
Lhc_body_loop:
        cmp     x28, x26
        b.hs    Lhc_route
        mov     w0, w19
        add     x1, x27, x28
        sub     x2, x26, x28
        bl      _read_some
        cmp     x0, #0
        b.le    Lhc_done
        add     x28, x28, x0
        b       Lhc_body_loop

        // ---- routing ----
Lhc_route:
        mov     x0, x20
        mov     x1, x23
        bl      _method_code
        mov     x23, x0
        add     x24, x20, x24                   // path pointer

        mov     x0, x24
        mov     x1, x25
        LOADADDR x2, Lpath_health
        mov     x3, #(Lpath_health_end - Lpath_health)
        bl      _bytes_eq
        cbz     w0, 1f
        cmp     x23, #M_GET
        b.ne    Lhc_405
        mov     w1, #ST_200
        LOADADDR x2, Lbody_ok
        mov     x3, #2
        b       Lhc_send

1:      mov     x0, x24
        mov     x1, x25
        LOADADDR x2, Lpath_kv
        mov     x3, #(Lpath_kv_end - Lpath_kv)
        bl      _bytes_eq
        cbnz    w0, Lhc_list

        cmp     x25, #4
        b.lo    Lhc_404
        mov     x0, x24
        mov     x1, #4
        LOADADDR x2, Lpath_kvslash
        mov     x3, #4
        bl      _bytes_eq
        cbz     w0, Lhc_404

        add     x24, x24, #4                    // key
        sub     x25, x25, #4                    // key length
        mov     x0, x24
        mov     x1, x25
        bl      _valid_key
        cbz     w0, Lhc_400

        cmp     x23, #M_GET
        b.eq    Lhc_get
        cmp     x23, #M_PUT
        b.eq    Lhc_put
        cmp     x23, #M_DELETE
        b.eq    Lhc_del
        b       Lhc_405

Lhc_list:
        cmp     x23, #M_GET
        b.ne    Lhc_405
        bl      _store_list
        cbz     x0, Lhc_500
        mov     x28, x0
        mov     x3, x1
        mov     x2, x0
        mov     w0, w19
        mov     w1, #ST_200
        mov     w4, #1
        bl      _send_response
        mov     x0, x28
        bl      _free
        b       Lhc_done

Lhc_get:
        mov     x0, x24
        mov     x1, x25
        bl      _store_get
        cbz     x0, Lhc_404
        tbnz    x0, #63, Lhc_500
        mov     x28, x1
        mov     x3, x2
        mov     x2, x1
        mov     w0, w19
        mov     w1, #ST_200
        mov     w4, #0
        bl      _send_response
        mov     x0, x28
        bl      _free
        b       Lhc_done

Lhc_put:
        mov     x0, x24
        mov     x1, x25
        mov     x2, x27
        mov     x3, x26
        bl      _store_put
        tbnz    x0, #63, Lhc_500
        mov     x27, #0                         // the store owns the body now
        cmp     x0, #1
        mov     w1, #ST_201
        mov     w8, #ST_200
        csel    w1, w1, w8, eq
        b       Lhc_send_empty

Lhc_del:
        mov     x0, x24
        mov     x1, x25
        bl      _store_del
        cbz     x0, Lhc_404
        mov     w1, #ST_204
        b       Lhc_send_empty

Lhc_400:
        mov     w1, #ST_400
        b       Lhc_send_empty
Lhc_404:
        mov     w1, #ST_404
        b       Lhc_send_empty
Lhc_405:
        mov     w1, #ST_405
        b       Lhc_send_empty
Lhc_413:
        mov     w1, #ST_413
        b       Lhc_send_empty
Lhc_431:
        mov     w1, #ST_431
        b       Lhc_send_empty
Lhc_500:
        mov     w1, #ST_500
Lhc_send_empty:
        mov     x2, #0
        mov     x3, #0
Lhc_send:
        mov     w0, w19
        mov     w4, #0
        bl      _send_response

Lhc_done:
        mov     x0, x27
        bl      _free
        mov     x0, x20
        bl      _free
        mov     w0, w19
        mov     w1, #SHUT_WR
        bl      _shutdown
        mov     w0, w19
        bl      _close

        add     sp, sp, #L_SIZE
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #96
        ret

// send_response(fd w0, status index w1, body x2, body len x3, json w4)
// Writes a complete response with Content-Length and Connection: close.
        .equ SR_INLINE, 4096                    // bodies up to this go in one write
        .equ SR_BUF,    (SR_INLINE + 512)

        .p2align 2
_send_response:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        mov     x9, #SR_BUF
        sub     sp, sp, x9
        mov     w19, w0
        mov     w24, w1
        mov     x20, x2
        mov     x21, x3
        mov     w22, w4

        mov     x0, sp
        LOADADDR x1, Lresp_version
        mov     x2, #(Lresp_version_end - Lresp_version)
        bl      _append
        LOADADDR x9, _status_tab
        add     x9, x9, x24, lsl #4
        ldp     x1, x2, [x9]
        bl      _append
        LOADADDR x1, Lresp_clen
        mov     x2, #(Lresp_clen_end - Lresp_clen)
        bl      _append
        mov     x1, x21
        bl      _append_uint
        LOADADDR x1, Lresp_crlf
        mov     x2, #2
        bl      _append
        cbz     w22, 1f
        LOADADDR x1, Lresp_json
        mov     x2, #(Lresp_json_end - Lresp_json)
        bl      _append
1:      LOADADDR x1, Lresp_tail
        mov     x2, #(Lresp_tail_end - Lresp_tail)
        bl      _append
        mov     x23, x0                         // end of head

        cmp     x21, #SR_INLINE
        b.hi    2f
        mov     x1, x20                         // small body: one write
        mov     x2, x21
        bl      _append
        mov     x2, x0
        mov     x1, sp
        sub     x2, x2, x1
        mov     w0, w19
        bl      _write_all
        b       3f

2:      mov     w0, w19
        mov     x1, sp
        sub     x2, x23, x1
        bl      _write_all
        tbnz    x0, #63, 3f
        mov     w0, w19
        mov     x1, x20
        mov     x2, x21
        bl      _write_all

3:      mov     x9, #SR_BUF
        add     sp, sp, x9
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ret

// method_code(ptr x0, len x1) -> x0 = M_GET / M_PUT / M_DELETE / M_OTHER. Leaf.
        .p2align 2
_method_code:
        cmp     x1, #3
        b.eq    1f
        cmp     x1, #6
        b.eq    2f
        b       9f
1:      ldrh    w2, [x0]
        ldrb    w3, [x0, #2]
        orr     w2, w2, w3, lsl #16
        mov     w4, #0x4547                     // "GE"
        movk    w4, #0x54, lsl #16              // "T"
        cmp     w2, w4
        b.eq    3f
        mov     w4, #0x5550                     // "PU"
        movk    w4, #0x54, lsl #16              // "T"
        cmp     w2, w4
        b.eq    4f
        b       9f
2:      ldr     w2, [x0]
        ldrh    w3, [x0, #4]
        mov     w4, #0x4544                     // "DE"
        movk    w4, #0x454c, lsl #16            // "LE"
        cmp     w2, w4
        b.ne    9f
        mov     w4, #0x4554                     // "TE"
        cmp     w3, w4
        b.ne    9f
        mov     x0, #M_DELETE
        ret
3:      mov     x0, #M_GET
        ret
4:      mov     x0, #M_PUT
        ret
9:      mov     x0, #M_OTHER
        ret

// valid_key(ptr x0, len x1) -> w0 = 1 if it matches [A-Za-z0-9_-]{1,64}. Leaf.
        .p2align 2
_valid_key:
        sub     x2, x1, #1
        cmp     x2, #63
        b.hi    9f                              // len 0 wraps to huge
        add     x1, x0, x1
1:      ldrb    w2, [x0], #1
        sub     w3, w2, #'0'
        cmp     w3, #9
        b.ls    2f
        orr     w3, w2, #0x20
        sub     w3, w3, #'a'
        cmp     w3, #25
        b.ls    2f
        cmp     w2, #'_'
        b.eq    2f
        cmp     w2, #'-'
        b.ne    9f
2:      cmp     x0, x1
        b.lo    1b
        mov     w0, #1
        ret
9:      mov     w0, #0
        ret

// match_header(line x0, len x1, name x2, namelen x3) -> x0 = pointer to the
// value (leading/trailing whitespace and CR trimmed), x1 = value length;
// x0 = 0 if the line is not that header. `name` is lowercase and includes
// the trailing ':'. Header names compare case-insensitively. Leaf.
        .p2align 2
_match_header:
        cmp     x1, x3
        b.lo    9f
        mov     x4, #0
1:      cmp     x4, x3
        b.hs    2f
        ldrb    w5, [x0, x4]
        ldrb    w6, [x2, x4]
        sub     w7, w5, #'A'
        cmp     w7, #25
        b.hi    11f
        orr     w5, w5, #0x20
11:     cmp     w5, w6
        b.ne    9f
        add     x4, x4, #1
        b       1b
2:      add     x1, x0, x1                      // end of line
        add     x0, x0, x3                      // start of value
3:      cmp     x0, x1                          // skip leading SP / HT
        b.hs    5f
        ldrb    w5, [x0]
        cmp     w5, #' '
        b.eq    31f
        cmp     w5, #'\t'
        b.ne    4f
31:     add     x0, x0, #1
        b       3b
4:      ldrb    w5, [x1, #-1]                   // trim trailing CR / SP / HT
        cmp     w5, #'\r'
        b.eq    41f
        cmp     w5, #' '
        b.eq    41f
        cmp     w5, #'\t'
        b.ne    5f
41:     sub     x1, x1, #1
        cmp     x0, x1
        b.lo    4b
5:      sub     x1, x1, x0
        ret
9:      mov     x0, #0
        ret

// parse_uint(ptr x0, len x1) -> x0 = value, or -1 if empty, not all digits,
// or larger than 2^48. Leaf.
        .p2align 2
_parse_uint:
        cbz     x1, 9f
        add     x1, x0, x1
        mov     x2, #0
        mov     x4, #10
        mov     x5, #(1 << 48)
1:      ldrb    w3, [x0], #1
        sub     w3, w3, #'0'
        cmp     w3, #9
        b.hi    9f
        madd    x2, x2, x4, x3
        cmp     x2, x5
        b.hi    9f
        cmp     x0, x1
        b.lo    1b
        mov     x0, x2
        ret
9:      mov     x0, #-1
        ret

// ---- constant data ----

        .section __TEXT,__const
Lhdr_clen:      .ascii "content-length:"
Lhdr_clen_end:
Lhdr_expect:    .ascii "expect:"
Lhdr_expect_end:
Lpath_health:   .ascii "/health"
Lpath_health_end:
Lpath_kv:       .ascii "/kv"
Lpath_kv_end:
Lpath_kvslash:  .ascii "/kv/"
Lbody_ok:       .ascii "ok"
Lresp_version:  .ascii "HTTP/1.1 "
Lresp_version_end:
Lresp_clen:     .ascii "\r\nContent-Length: "
Lresp_clen_end:
Lresp_crlf:     .ascii "\r\n"
Lresp_json:     .ascii "Content-Type: application/json\r\n"
Lresp_json_end:
Lresp_tail:     .ascii "Connection: close\r\n\r\n"
Lresp_tail_end:
Lresp_continue: .ascii "HTTP/1.1 100 Continue\r\n\r\n"
Lresp_continue_end:

St_200: .ascii "200 OK"
St_201: .ascii "201 Created"
St_204: .ascii "204 No Content"
St_400: .ascii "400 Bad Request"
St_404: .ascii "404 Not Found"
St_405: .ascii "405 Method Not Allowed"
St_413: .ascii "413 Content Too Large"
St_431: .ascii "431 Request Header Fields Too Large"
St_500: .ascii "500 Internal Server Error"
St_end:

// { const char *text; size_t len } indexed by ST_* (see defs.inc).
        .section __DATA,__const
        .p2align 3
_status_tab:
        .quad St_200, St_201 - St_200
        .quad St_201, St_204 - St_201
        .quad St_204, St_400 - St_204
        .quad St_400, St_404 - St_400
        .quad St_404, St_405 - St_404
        .quad St_405, St_413 - St_405
        .quad St_413, St_431 - St_413
        .quad St_431, St_500 - St_431
        .quad St_500, St_end - St_500
