// conn.s - per-connection HTTP/1.1 handling: parse one request, route it to
// the key/value store, write one response, close.
//
//   void *conn_main(void *fd)          pthread entry point; closes the socket
//   void  handle_connection(int fd)

    .equ HBUF_SIZE,  16384            // request line + headers limit
    .equ LOCALS,     64
    .equ MAX_VALUE,  1048576          // 1 MiB
    .equ MAX_DRAIN,  8388608          // oversized bodies beyond this are not drained

// Indices into Lstatus_table
    .equ ST_200, 0
    .equ ST_201, 1
    .equ ST_204, 2
    .equ ST_400, 3
    .equ ST_404, 4
    .equ ST_405, 5
    .equ ST_413, 6
    .equ ST_431, 7
    .equ ST_500, 8

// Request methods
    .equ M_OTHER,  0
    .equ M_GET,    1
    .equ M_PUT,    2
    .equ M_DELETE, 3

.macro ADDR reg, sym
    adrp    \reg, \sym@PAGE
    add     \reg, \reg, \sym@PAGEOFF
.endm

    .text

// ---------------------------------------------------------------------------
// void *conn_main(void *arg)   arg = socket descriptor
    .globl  _conn_main
    .private_extern _conn_main
    .p2align 2
_conn_main:
    .cfi_startproc
    sub     sp, sp, #32
    stp     x20, x19, [sp]
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    mov     w19, w0
    bl      _handle_connection
    mov     w0, w19
    bl      _close
    mov     x0, #0
    ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp]
    add     sp, sp, #32
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// void handle_connection(int fd)
//
// Register use:
//   x19 fd            x20 request buffer   x21 bytes buffered   x22 header end
//   x23 content len   x24 body (owned)     x25 method           x26 path / key
//   x27 path / key length                  x28 cursor
// Locals: [sp] out pointer, [sp+8] out length, [sp+16] current line end.
    .globl  _handle_connection
    .private_extern _handle_connection
    .p2align 2
_handle_connection:
    .cfi_startproc
    sub     sp, sp, #96
    stp     x28, x27, [sp]
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #80]
    add     x29, sp, #80
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
    sub     sp, sp, #(HBUF_SIZE >> 12), lsl #12
    sub     sp, sp, #LOCALS

    mov     w19, w0
    add     x20, sp, #LOCALS
    mov     x21, #0
    mov     x24, #0

    // --- read until the end of the header block -------------------------
Lhc_read:
    mov     x8, #HBUF_SIZE
    subs    x2, x8, x21
    b.eq    Lhc_431
    mov     w0, w19
    add     x1, x20, x21
    bl      _read
    cmp     x0, #0
    b.le    Lhc_done
    subs    x1, x21, #3                   // resume the search 3 bytes back
    csel    x1, xzr, x1, lo
    add     x21, x21, x0
    mov     x0, x20
    mov     x2, x21
    bl      _find_header_end
    tbnz    x0, #63, Lhc_read
    mov     x22, x0

    // --- request line: METHOD SP PATH [SP VERSION] CRLF -----------------
    mov     x0, x20
    mov     w1, #'\r'
    mov     x2, x22
    bl      _memchr                       // always found
    mov     x28, x0                       // end of request line
    mov     x0, x20
    mov     w1, #' '
    sub     x2, x28, x20
    bl      _memchr
    cbz     x0, Lhc_400
    sub     x9, x0, x20                   // method length
    add     x26, x0, #1                   // path

    mov     w25, #M_OTHER
    ldr     w8, [x20]
    cmp     x9, #3
    b.ne    1f
    movz    w10, #0x4547
    movk    w10, #0x2054, lsl #16         // "GET "
    mov     w11, #M_GET
    cmp     w8, w10
    csel    w25, w11, w25, eq
    movz    w10, #0x5550
    movk    w10, #0x2054, lsl #16         // "PUT "
    mov     w11, #M_PUT
    cmp     w8, w10
    csel    w25, w11, w25, eq
    b       2f
1:  cmp     x9, #6
    b.ne    2f
    movz    w10, #0x4544
    movk    w10, #0x454c, lsl #16         // "DELE"
    ldrh    w11, [x20, #4]
    mov     w12, #0x4554                  // "TE"
    cmp     w8, w10
    ccmp    w11, w12, #0, eq
    mov     w11, #M_DELETE
    csel    w25, w11, w25, eq
2:
    mov     x0, x26
    mov     w1, #' '
    sub     x2, x28, x26
    bl      _memchr
    cmp     x0, #0
    csel    x0, x28, x0, eq
    sub     x27, x0, x26                  // path length

    // --- header fields: only Content-Length matters ---------------------
    mov     x23, #0
    add     x28, x28, #2
Lhc_hdr:
    mov     x0, x28
    mov     w1, #'\r'
    add     x2, x20, x22
    sub     x2, x2, x28
    bl      _memchr
    cbz     x0, Lhc_body_start
    cmp     x0, x28
    b.eq    Lhc_body_start                // empty line ends the headers
    str     x0, [sp, #16]
    sub     x8, x0, x28
    cmp     x8, #15
    b.lo    Lhc_hdr_next
    mov     x0, x28
    ADDR    x1, Lstr_content_length
    mov     x2, #15
    bl      _strncasecmp
    cbnz    w0, Lhc_hdr_next
    add     x0, x28, #15
    ldr     x1, [sp, #16]
    bl      _parse_content_length
    tbnz    x0, #63, Lhc_400
    mov     x23, x0
Lhc_hdr_next:
    ldr     x28, [sp, #16]
    add     x28, x28, #2
    b       Lhc_hdr

    // --- body --------------------------------------------------------------
Lhc_body_start:
    mov     x8, #MAX_VALUE
    cmp     x23, x8
    b.hi    Lhc_413
    cmp     x23, #0
    csinc   x0, x23, xzr, ne              // malloc(len ? len : 1)
    bl      _malloc
    cbz     x0, Lhc_500
    mov     x24, x0
    sub     x2, x21, x22                  // body bytes already buffered
    cmp     x2, x23
    csel    x2, x2, x23, lo
    mov     x28, x2
    add     x1, x20, x22
    bl      _memcpy
Lhc_body:
    cmp     x28, x23
    b.hs    Lhc_route
    mov     w0, w19
    add     x1, x24, x28
    sub     x2, x23, x28
    bl      _read
    cmp     x0, #0
    b.le    Lhc_done                      // client went away mid-body
    add     x28, x28, x0
    b       Lhc_body

    // --- routing -----------------------------------------------------------
Lhc_route:
    cmp     x27, #3
    b.lo    Lhc_404
    ldr     w8, [x26]
    b.eq    Lhc_list
    cmp     x27, #7
    b.ne    Lhc_key
    movz    w9, #0x682f
    movk    w9, #0x6165, lsl #16          // "/hea"
    ldr     w10, [x26, #3]
    movz    w11, #0x6c61
    movk    w11, #0x6874, lsl #16         // "alth"
    cmp     w8, w9
    ccmp    w10, w11, #0, eq
    b.eq    Lhc_health
Lhc_key:
    movz    w9, #0x6b2f
    movk    w9, #0x2f76, lsl #16          // "/kv/"
    cmp     w8, w9
    b.ne    Lhc_404
    add     x26, x26, #4
    sub     x27, x27, #4
    mov     x0, x26
    mov     x1, x27
    bl      _valid_key
    cbz     w0, Lhc_400
    cmp     w25, #M_GET
    b.eq    Lhc_get
    cmp     w25, #M_PUT
    b.eq    Lhc_put
    cmp     w25, #M_DELETE
    b.eq    Lhc_delete
    b       Lhc_405

Lhc_list:
    and     w8, w8, #0xffffff
    movz    w9, #0x6b2f
    movk    w9, #0x0076, lsl #16          // "/kv"
    cmp     w8, w9
    b.ne    Lhc_404
    cmp     w25, #M_GET
    b.ne    Lhc_405
    add     x0, sp, #8
    bl      _store_list_json
    cbz     x0, Lhc_500
    mov     x21, x0
    mov     w0, w19
    mov     w1, #ST_200
    mov     x2, x21
    ldr     x3, [sp, #8]
    ADDR    x4, Lhdr_json
    bl      _send_response
    mov     x0, x21
    bl      _free
    b       Lhc_done

Lhc_health:
    cmp     w25, #M_GET
    b.ne    Lhc_405
    mov     w0, w19
    mov     w1, #ST_200
    ADDR    x2, Lstr_ok
    mov     x3, #2
    ADDR    x4, Lhdr_text
    bl      _send_response
    b       Lhc_done

Lhc_get:
    mov     x0, x26
    mov     x1, x27
    mov     x2, sp
    add     x3, sp, #8
    bl      _store_get
    cmp     w0, #1
    b.eq    Lhc_404
    cbnz    w0, Lhc_500
    ldr     x21, [sp]
    mov     w0, w19
    mov     w1, #ST_200
    mov     x2, x21
    ldr     x3, [sp, #8]
    ADDR    x4, Lhdr_octet
    bl      _send_response
    mov     x0, x21
    bl      _free
    b       Lhc_done

Lhc_put:
    mov     x0, x26
    mov     x1, x27
    mov     x2, x24
    mov     x3, x23
    bl      _store_put
    tbnz    w0, #31, Lhc_500
    mov     x24, #0                       // the store owns the body now
    mov     w8, #ST_200
    mov     w9, #ST_201
    cmp     w0, #0
    csel    w1, w9, w8, ne
    b       Lhc_empty

Lhc_delete:
    mov     x0, x26
    mov     x1, x27
    bl      _store_delete
    cbz     w0, Lhc_404
    mov     w1, #ST_204
    b       Lhc_empty

Lhc_413:
    // Drain a moderately oversized body so the client reads the response
    // instead of a connection reset.
    mov     x8, #MAX_DRAIN
    cmp     x23, x8
    b.hi    2f
    sub     x8, x21, x22
    sub     x28, x23, x8
1:  cbz     x28, 2f
    mov     x2, #HBUF_SIZE
    cmp     x28, x2
    csel    x2, x28, x2, lo
    mov     w0, w19
    mov     x1, x20
    bl      _read
    cmp     x0, #0
    b.le    2f
    sub     x28, x28, x0
    b       1b
2:  mov     w1, #ST_413
    b       Lhc_empty

Lhc_400:
    mov     w1, #ST_400
    b       Lhc_empty
Lhc_404:
    mov     w1, #ST_404
    b       Lhc_empty
Lhc_405:
    mov     w1, #ST_405
    b       Lhc_empty
Lhc_431:
    mov     w1, #ST_431
    b       Lhc_empty
Lhc_500:
    mov     w1, #ST_500
Lhc_empty:
    mov     w0, w19
    mov     x2, #0
    mov     x3, #0
    mov     x4, #0
    bl      _send_response
Lhc_done:
    mov     x0, x24
    bl      _free
    sub     sp, x29, #80
    ldp     x29, x30, [sp, #80]
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp]
    add     sp, sp, #96
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// void send_response(int fd, int status, const void *body, size_t len,
//                    const char *content_type_line /* or NULL */)
    .p2align 2
_send_response:
    .cfi_startproc
    sub     sp, sp, #64
    stp     x24, x23, [sp]
    stp     x22, x21, [sp, #16]
    stp     x20, x19, [sp, #32]
    stp     x29, x30, [sp, #48]
    add     x29, sp, #48
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    .cfi_offset w21, -40
    .cfi_offset w22, -48
    .cfi_offset w23, -56
    .cfi_offset w24, -64
    sub     sp, sp, #288                  // [sp] iovec[2], [sp+32] header text
    mov     w19, w0
    mov     x20, x2
    mov     x21, x3
    mov     x23, x4
    mov     w8, w1
    ADDR    x22, Lstatus_table
    add     x22, x22, x8, lsl #6

    add     x24, sp, #32
    mov     x0, x24
    ADDR    x1, Lstr_http
    bl      _str_append
    mov     x1, x22
    bl      _str_append
    ADDR    x1, Lstr_clen
    bl      _str_append
    mov     x1, x21
    bl      _utoa
    ADDR    x1, Lstr_crlf
    bl      _str_append
    cbz     x23, 1f
    mov     x1, x23
    bl      _str_append
1:  ADDR    x1, Lstr_close
    bl      _str_append

    sub     x8, x0, x24                   // header length
    stp     x24, x8, [sp]
    stp     x20, x21, [sp, #16]
    add     x22, x8, x21                  // total
    mov     w0, w19
    mov     x1, sp
    mov     w2, #2
    bl      _writev
    cmp     x0, x22
    b.eq    Lsr_ret
    tbnz    x0, #63, Lsr_ret
    // Short write: finish the header (if needed), then the body.
    ldr     x9, [sp, #8]
    subs    x22, x0, x9                   // body bytes already sent
    b.hs    2f
    add     x1, x24, x0
    neg     x2, x22
    mov     w0, w19
    bl      _write_all
    cbnz    w0, Lsr_ret
    mov     x22, #0
2:  add     x1, x20, x22
    sub     x2, x21, x22
    mov     w0, w19
    bl      _write_all
Lsr_ret:
    sub     sp, x29, #48
    ldp     x29, x30, [sp, #48]
    ldp     x20, x19, [sp, #32]
    ldp     x22, x21, [sp, #16]
    ldp     x24, x23, [sp]
    add     sp, sp, #64
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// int write_all(int fd, const void *buf, size_t len)   0 ok, -1 error
    .p2align 2
_write_all:
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
    mov     w19, w0
    mov     x20, x1
    mov     x21, x2
1:  cbz     x21, 2f
    mov     w0, w19
    mov     x1, x20
    mov     x2, x21
    bl      _write
    cmp     x0, #0
    b.le    3f
    add     x20, x20, x0
    sub     x21, x21, x0
    b       1b
2:  mov     w0, #0
    b       4f
3:  mov     w0, #-1
4:  ldp     x29, x30, [sp, #32]
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp]
    add     sp, sp, #48
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// ssize_t find_header_end(const char *buf, size_t from, size_t len)
// Index just past the first CRLFCRLF at or after `from`, or -1. Leaf.
    .p2align 2
_find_header_end:
    .cfi_startproc
    sub     x2, x2, #4
    movz    w4, #0x0a0d
    movk    w4, #0x0a0d, lsl #16          // "\r\n\r\n"
1:  cmp     x1, x2
    b.gt    2f
    ldr     w3, [x0, x1]
    cmp     w3, w4
    b.eq    3f
    add     x1, x1, #1
    b       1b
2:  mov     x0, #-1
    ret
3:  add     x0, x1, #4
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// int64_t parse_content_length(const char *p, const char *end)
// Field value: OWS 1*DIGIT OWS. Saturates at 2^40. -1 if malformed. Leaf.
    .p2align 2
_parse_content_length:
    .cfi_startproc
1:  cmp     x0, x1
    b.hs    Lpcl_bad
    ldrb    w2, [x0]
    cmp     w2, #' '
    ccmp    w2, #'\t', #4, ne
    b.ne    2f
    add     x0, x0, #1
    b       1b
2:  mov     x3, #0                        // value
    mov     x4, #0                        // digits seen
    mov     x6, #10
    movz    x7, #0x100, lsl #32           // 2^40
3:  cmp     x0, x1
    b.hs    5f
    ldrb    w2, [x0]
    sub     w5, w2, #'0'
    cmp     w5, #9
    b.hi    4f
    madd    x3, x3, x6, x5
    cmp     x3, x7
    csel    x3, x7, x3, hi
    add     x4, x4, #1
    add     x0, x0, #1
    b       3b
4:  cmp     w2, #' '                      // only trailing whitespace allowed
    ccmp    w2, #'\t', #4, ne
    b.ne    Lpcl_bad
    add     x0, x0, #1
    cmp     x0, x1
    b.hs    5f
    ldrb    w2, [x0]
    b       4b
5:  cbz     x4, Lpcl_bad
    mov     x0, x3
    ret
Lpcl_bad:
    mov     x0, #-1
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// int valid_key(const char *p, size_t n)   [A-Za-z0-9_-]{1,64}. Leaf.
    .p2align 2
_valid_key:
    .cfi_startproc
    cbz     x1, 3f
    cmp     x1, #64
    b.hi    3f
1:  ldrb    w2, [x0], #1
    sub     w3, w2, #'0'
    cmp     w3, #10
    b.lo    2f
    orr     w3, w2, #0x20                 // fold case
    sub     w3, w3, #'a'
    cmp     w3, #26
    b.lo    2f
    cmp     w2, #'_'
    b.eq    2f
    cmp     w2, #'-'
    b.ne    3f
2:  subs    x1, x1, #1
    b.ne    1b
    mov     w0, #1
    ret
3:  mov     w0, #0
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// char *str_append(char *dst, const char *src)   returns the new end. Leaf.
    .p2align 2
_str_append:
    .cfi_startproc
1:  ldrb    w2, [x1], #1
    cbz     w2, 2f
    strb    w2, [x0], #1
    b       1b
2:  ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// char *utoa(char *dst, uint64_t v)   decimal, returns the new end. Leaf.
    .p2align 2
_utoa:
    .cfi_startproc
    mov     x2, x0
    mov     x3, #10
1:  udiv    x4, x1, x3
    msub    x5, x4, x3, x1
    add     w5, w5, #'0'
    strb    w5, [x0], #1
    mov     x1, x4
    cbnz    x1, 1b
    sub     x3, x0, #1                    // reverse the digits in place
2:  cmp     x2, x3
    b.hs    3f
    ldrb    w4, [x2]
    ldrb    w5, [x3]
    strb    w5, [x2], #1
    strb    w4, [x3], #-1
    b       2b
3:  ret
    .cfi_endproc

// ---------------------------------------------------------------------------
    .const
    .p2align 6
Lstatus_table:                            // 64-byte slots, indexed by ST_*
    .asciz  "200 OK"
    .p2align 6
    .asciz  "201 Created"
    .p2align 6
    .asciz  "204 No Content"
    .p2align 6
    .asciz  "400 Bad Request"
    .p2align 6
    .asciz  "404 Not Found"
    .p2align 6
    .asciz  "405 Method Not Allowed"
    .p2align 6
    .asciz  "413 Content Too Large"
    .p2align 6
    .asciz  "431 Request Header Fields Too Large"
    .p2align 6
    .asciz  "500 Internal Server Error"

    .section __TEXT,__cstring,cstring_literals
Lstr_http:            .asciz "HTTP/1.1 "
Lstr_clen:            .asciz "\r\nContent-Length: "
Lstr_crlf:            .asciz "\r\n"
Lstr_close:           .asciz "Connection: close\r\n\r\n"
Lhdr_json:            .asciz "Content-Type: application/json\r\n"
Lhdr_text:            .asciz "Content-Type: text/plain\r\n"
Lhdr_octet:           .asciz "Content-Type: application/octet-stream\r\n"
Lstr_content_length:  .asciz "content-length:"
Lstr_ok:              .asciz "ok"

.subsections_via_symbols
