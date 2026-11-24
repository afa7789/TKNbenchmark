// http.s — HTTP/1.1 request parsing, routing and response writing.

        .include "macros.inc"

        .equ    M_OTHER,        0
        .equ    M_GET,          1
        .equ    M_PUT,          2
        .equ    M_DELETE,       3

        .equ    RESP_BUF,       1024        // header + small inline body
        .equ    INLINE_BODY,    512         // bodies up to this size share the header write

        .section __TEXT,__const
// Status line records: 32 bytes each, terminated by a zero code whose text
// is used as the fallback.
.macro STATUS code, text
        .p2align 5
        .word   \code
        .asciz  "\text"
.endm
Lstatus_table:
        STATUS  200, "200 OK"
        STATUS  201, "201 Created"
        STATUS  204, "204 No Content"
        STATUS  400, "400 Bad Request"
        STATUS  404, "404 Not Found"
        STATUS  405, "405 Method Not Allowed"
        STATUS  413, "413 Content Too Large"
        STATUS  0,   "500 Internal Server Error"

Lcl_name:       .ascii "content-length:"        // compared case-insensitively

        .section __TEXT,__cstring,cstring_literals
Ls_http:        .asciz "HTTP/1.1 "
Ls_clen:        .asciz "\r\nContent-Length: "
Ls_ctype:       .asciz "Content-Type: "
Ls_crlf:        .asciz "\r\n"
Ls_close:       .asciz "Connection: close\r\n\r\n"
Ls_json:        .asciz "application/json"
Ls_ok:          .asciz "ok"
Ls_get:         .asciz "GET"
Ls_put:         .asciz "PUT"
Ls_delete:      .asciz "DELETE"
Ls_health:      .asciz "/health"
Ls_kv:          .asciz "/kv"

        .text

// ---------------------------------------------------------------------------
// Small leaf helpers
// ---------------------------------------------------------------------------

// bool mem_eq(a x0, alen x1, b x2, blen x3)
        .p2align 2
mem_eq:
        cmp     x1, x3
        b.ne    2f
1:      cbz     x1, 3f
        ldrb    w4, [x0], #1
        ldrb    w5, [x2], #1
        sub     x1, x1, #1
        cmp     w4, w5
        b.eq    1b
2:      mov     w0, #0
        ret
3:      mov     w0, #1
        ret

// char *str_append(dst x0, const char *src x1) — returns the new end of dst.
        .p2align 2
str_append:
1:      ldrb    w2, [x1], #1
        cbz     w2, 2f
        strb    w2, [x0], #1
        b       1b
2:      ret

// char *u64_to_dec(dst x0, value x1) — returns the new end of dst.
        .p2align 2
u64_to_dec:
        mov     x4, #10
        mov     x2, x1
1:      udiv    x2, x2, x4                  // count digits
        add     x0, x0, #1
        cbnz    x2, 1b
        mov     x5, x0
2:      udiv    x2, x1, x4
        msub    x6, x2, x4, x1
        add     w6, w6, #'0'
        strb    w6, [x5, #-1]!
        mov     x1, x2
        cbnz    x1, 2b
        ret

// const char *status_text(int code w0)
        .p2align 2
status_text:
        LOADADDR x1, Lstatus_table
1:      ldr     w2, [x1]
        cbz     w2, 2f
        cmp     w2, w0
        b.eq    2f
        add     x1, x1, #32
        b       1b
2:      add     x0, x1, #4
        ret

// int write_all(int fd w0, const void *buf x1, size_t len x2) — 0 or -1.
        .p2align 2
write_all:
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
        b.gt    2f
        b.eq    4f
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    1b
        b       4f
2:      add     x20, x20, x0
        sub     x21, x21, x0
        b       1b
3:      mov     w0, #0
        b       5f
4:      mov     w0, #-1
5:      ldr     x21, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// void send_response(int fd w0, int status w1, const void *body x2,
//                    size_t len x3, const char *content_type x4 /* or NULL */)
        .p2align 2
send_response:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        sub     sp, sp, #RESP_BUF
        mov     w19, w0
        mov     w20, w1
        mov     x21, x2
        mov     x22, x3
        mov     x23, x4

        mov     x0, sp
        LOADADDR x1, Ls_http
        bl      str_append
        mov     x24, x0
        mov     w0, w20
        bl      status_text
        mov     x1, x0
        mov     x0, x24
        bl      str_append
        LOADADDR x1, Ls_clen
        bl      str_append
        mov     x1, x22
        bl      u64_to_dec
        LOADADDR x1, Ls_crlf
        bl      str_append
        cbz     x23, 1f
        LOADADDR x1, Ls_ctype
        bl      str_append
        mov     x1, x23
        bl      str_append
        LOADADDR x1, Ls_crlf
        bl      str_append
1:      LOADADDR x1, Ls_close
        bl      str_append
        mov     x24, x0                     // end of header

        cbz     x22, 2f
        cmp     x22, #INLINE_BODY
        b.hi    2f
        mov     x1, x21
        mov     x2, x22
        bl      _memcpy
        add     x24, x24, x22
        mov     x22, #0
2:      mov     w0, w19
        mov     x1, sp
        sub     x2, x24, x1
        bl      write_all
        cbnz    w0, 3f
        cbz     x22, 3f
        mov     w0, w19
        mov     x1, x21
        mov     x2, x22
        bl      write_all
3:      add     sp, sp, #RESP_BUF
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ret

// ---------------------------------------------------------------------------
// void http_handle(int fd w0) — read one request, dispatch, respond.
//
//   x19 fd            x20 header buffer      x21 bytes buffered / body bytes
//   x22 header end    x23 method / key ptr   x24 method / key length
//   x25 path ptr      x26 path length        x27 Content-Length
//   x28 request body blob (owned until handed to the store)
// ---------------------------------------------------------------------------
        .globl  _http_handle
        .p2align 2
_http_handle:
        stp     x29, x30, [sp, #-96]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]
        stp     x27, x28, [sp, #80]
        sub     sp, sp, #HDR_CAP
        mov     w19, w0
        mov     x20, sp
        mov     x21, #0
        mov     x28, #0

        // --- read until the blank line that ends the header block ---
Lread_more:
        mov     x2, #HDR_CAP
        subs    x2, x2, x21
        b.eq    L400                        // header block too large
        mov     w0, w19
        add     x1, x20, x21
        bl      _read
        cmp     x0, #0
        b.gt    1f
        b.eq    Ldone
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    Lread_more
        b       Ldone
1:      subs    x9, x21, #3                 // rescan the last 3 old bytes
        csel    x9, xzr, x9, lo
        add     x21, x21, x0
        movz    w12, #0x0a0d
        movk    w12, #0x0a0d, lsl #16       // "\r\n\r\n"
2:      add     x10, x9, #4
        cmp     x10, x21
        b.hi    Lread_more
        ldr     w11, [x20, x9]
        cmp     w11, w12
        b.eq    3f
        add     x9, x9, #1
        b       2b
3:      add     x22, x9, #4

        // --- request line: METHOD SP PATH SP VERSION CRLF ---
        mov     x9, #0
1:      ldrb    w10, [x20, x9]
        cmp     w10, #' '
        b.eq    2f
        cmp     w10, #'\r'
        b.eq    L400
        add     x9, x9, #1
        b       1b
2:      cbz     x9, L400
        mov     x23, x20
        mov     x24, x9
        add     x9, x9, #1
        add     x25, x20, x9
        mov     x10, x9
3:      ldrb    w11, [x20, x10]
        cmp     w11, #' '
        b.eq    4f
        cmp     w11, #'\r'
        b.eq    L400
        add     x10, x10, #1
        b       3b
4:      subs    x26, x10, x9
        b.eq    L400
5:      ldrb    w11, [x20, x10]             // skip the version to end of line
        cmp     w11, #'\r'
        b.eq    6f
        add     x10, x10, #1
        b       5b
6:      add     x10, x10, #2

        // --- header fields: only Content-Length matters ---
        mov     x27, #0
        LOADADDR x14, Lcl_name
Lhdr_loop:
        sub     x11, x22, #2
        cmp     x10, x11
        b.hs    Lhdr_done
        mov     x12, x10
1:      ldrb    w13, [x20, x12]
        cmp     w13, #'\r'
        b.eq    2f
        add     x12, x12, #1
        b       1b
2:      sub     x13, x12, x10               // line is [x10, x12)
        cmp     x13, #15
        b.lo    Lhdr_next
        mov     x15, #0
3:      add     x16, x10, x15
        ldrb    w16, [x20, x16]
        orr     w16, w16, #0x20
        ldrb    w17, [x14, x15]
        cmp     w16, w17
        b.ne    Lhdr_next
        add     x15, x15, #1
        cmp     x15, #15
        b.lo    3b

        add     x15, x10, #15               // value: OWS 1*DIGIT OWS
        bl      Lskip_ows
        mov     x27, #0
        mov     x16, #0
        mov     x17, #10
        movz    x9, #1, lsl #32             // saturation bound (well above MAX_VALUE)
4:      cmp     x15, x12
        b.hs    5f
        ldrb    w13, [x20, x15]
        sub     w13, w13, #'0'
        cmp     w13, #9
        b.hi    5f
        madd    x27, x27, x17, x13
        cmp     x27, x9
        csel    x27, x9, x27, hi
        add     x16, x16, #1
        add     x15, x15, #1
        b       4b
5:      cbz     x16, L400
        bl      Lskip_ows
        cmp     x15, x12
        b.ne    L400
Lhdr_next:
        add     x10, x12, #2
        b       Lhdr_loop

        // Local leaf: advance x15 over spaces/tabs while x15 < x12.
Lskip_ows:
        cmp     x15, x12
        b.hs    2f
        ldrb    w13, [x20, x15]
        cmp     w13, #' '
        b.eq    1f
        cmp     w13, #'\t'
        b.ne    2f
1:      add     x15, x15, #1
        b       Lskip_ows
2:      ret

        // --- body: read exactly Content-Length bytes into a value blob ---
Lhdr_done:
        mov     x8, #MAX_VALUE
        cmp     x27, x8
        b.hi    L413
        add     x0, x27, #BLOB_DATA
        bl      _malloc
        cbz     x0, L500
        mov     x28, x0
        mov     x8, #1
        stp     x8, x27, [x28, #BLOB_REFS]
        sub     x2, x21, x22                // body bytes already buffered
        cmp     x2, x27
        csel    x2, x27, x2, hi
        mov     x21, x2
        add     x0, x28, #BLOB_DATA
        add     x1, x20, x22
        bl      _memcpy
Lbody_loop:
        cmp     x21, x27
        b.hs    Lroute
        mov     w0, w19
        add     x1, x28, #BLOB_DATA
        add     x1, x1, x21
        sub     x2, x27, x21
        bl      _read
        cmp     x0, #0
        b.gt    1f
        b.eq    Ldone
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    Lbody_loop
        b       Ldone
1:      add     x21, x21, x0
        b       Lbody_loop

        // --- routing ---
Lroute:
        mov     x22, #M_GET
        mov     x0, x23
        mov     x1, x24
        LOADADDR x2, Ls_get
        mov     x3, #3
        bl      mem_eq
        cbnz    w0, 1f
        mov     x22, #M_PUT
        mov     x0, x23
        mov     x1, x24
        LOADADDR x2, Ls_put
        mov     x3, #3
        bl      mem_eq
        cbnz    w0, 1f
        mov     x22, #M_DELETE
        mov     x0, x23
        mov     x1, x24
        LOADADDR x2, Ls_delete
        mov     x3, #6
        bl      mem_eq
        cbnz    w0, 1f
        mov     x22, #M_OTHER
1:
        mov     x0, x25
        mov     x1, x26
        LOADADDR x2, Ls_health
        mov     x3, #7
        bl      mem_eq
        cbnz    w0, Lr_health
        mov     x0, x25
        mov     x1, x26
        LOADADDR x2, Ls_kv
        mov     x3, #3
        bl      mem_eq
        cbnz    w0, Lr_list
        cmp     x26, #4
        b.lo    L404
        ldr     w8, [x25]
        movz    w9, #0x6b2f
        movk    w9, #0x2f76, lsl #16        // "/kv/"
        cmp     w8, w9
        b.ne    L404

        // /kv/<key>: validate [A-Za-z0-9_-]{1,64}
        add     x23, x25, #4
        sub     x24, x26, #4
        cbz     x24, L400
        cmp     x24, #KEY_MAX
        b.hi    L400
        mov     x9, #0
2:      ldrb    w10, [x23, x9]
        sub     w11, w10, #'0'
        cmp     w11, #10
        b.lo    3f
        orr     w11, w10, #0x20
        sub     w11, w11, #'a'
        cmp     w11, #26
        b.lo    3f
        cmp     w10, #'_'
        b.eq    3f
        cmp     w10, #'-'
        b.ne    L400
3:      add     x9, x9, #1
        cmp     x9, x24
        b.lo    2b

        cmp     x22, #M_GET
        b.eq    Lr_get
        cmp     x22, #M_PUT
        b.eq    Lr_put
        cmp     x22, #M_DELETE
        b.eq    Lr_delete
        b       L405

Lr_health:
        cmp     x22, #M_GET
        b.ne    L405
        mov     w1, #200
        LOADADDR x2, Ls_ok
        mov     x3, #2
        mov     x4, #0
        b       Lrespond

Lr_list:
        cmp     x22, #M_GET
        b.ne    L405
        bl      _store_list
        cbz     x0, L500
        mov     x21, x0
        mov     x2, x0
        mov     x3, x1
        mov     w0, w19
        mov     w1, #200
        LOADADDR x4, Ls_json
        bl      send_response
        mov     x0, x21
        bl      _free
        b       Ldone

Lr_get:
        mov     x0, x23
        mov     x1, x24
        bl      _store_get
        cbz     x0, L404
        mov     x21, x0
        mov     w0, w19
        mov     w1, #200
        add     x2, x21, #BLOB_DATA
        ldr     x3, [x21, #BLOB_LEN]
        mov     x4, #0
        bl      send_response
        mov     x0, x21
        bl      _blob_release
        b       Ldone

Lr_put:
        mov     x0, x23
        mov     x1, x24
        mov     x2, x28
        bl      _store_put
        tbnz    x0, #63, L500
        mov     x28, #0                     // the store owns the blob now
        mov     w1, #200
        mov     w8, #201
        cmp     x0, #0
        csel    w1, w8, w1, ne
        b       Lrespond_empty

Lr_delete:
        mov     x0, x23
        mov     x1, x24
        bl      _store_delete
        cbz     x0, L404
        mov     w1, #204
        b       Lrespond_empty

L400:   mov     w1, #400
        b       Lrespond_empty
L404:   mov     w1, #404
        b       Lrespond_empty
L405:   mov     w1, #405
        b       Lrespond_empty
L413:   mov     w1, #413
        b       Lrespond_empty
L500:   mov     w1, #500
Lrespond_empty:
        mov     x2, #0
        mov     x3, #0
        mov     x4, #0
Lrespond:
        mov     w0, w19
        bl      send_response

Ldone:
        mov     x0, x28
        bl      _blob_release
        add     sp, sp, #HDR_CAP
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #96
        ret
