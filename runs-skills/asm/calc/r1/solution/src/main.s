// main.s — calc driver: read stdin, evaluate each line, write results.
//
// The whole input is read into one growable heap buffer, then split on
// '\n'. Results are collected in a static output buffer that is flushed
// with write(2) whenever it nears capacity and once at exit.

    .set OUTBUF_SIZE, 65536
    .set OUT_RESERVE, 32                // max bytes emitted per line ("-" + 19 digits + "\n")
    .set INBUF_INIT,  65536
    .set SCRATCH_MIN, 256
    .set EINTR,       4

    .text
    .globl  _main
    .p2align 2
_main:
    .cfi_startproc
    sub     sp, sp, #96
    stp     x28, x27, [sp, #0]
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

    // ---- slurp stdin: x19 = buffer, x21 = length, x22 = capacity ----
    mov     x22, #INBUF_INIT
    mov     x0, x22
    bl      _malloc
    cbz     x0, Lfail
    mov     x19, x0
    mov     x21, #0
Lread:
    subs    x2, x22, x21
    b.ne    1f
    lsl     x22, x22, #1
    mov     x0, x19
    mov     x1, x22
    bl      _realloc
    cbz     x0, Lfail
    mov     x19, x0
    sub     x2, x22, x21
1:  mov     w0, #0                      // STDIN_FILENO
    add     x1, x19, x21
    bl      _read
    cmp     x0, #0
    b.gt    2f
    b.eq    Lread_done
    bl      ___error
    ldr     w0, [x0]
    cmp     w0, #EINTR
    b.eq    Lread
    b       Lread_done                  // treat other read errors as EOF
2:  add     x21, x21, x0
    b       Lread
Lread_done:
    add     x20, x19, x21               // x20 = end of input
    mov     x21, x19                    // x21 = start of current line

    // x23 = evaluator scratch (values, then ops), x25 = entries it holds
    mov     x23, #0
    mov     x25, #0
    adrp    x26, _outbuf@PAGE
    add     x26, x26, _outbuf@PAGEOFF
    mov     x27, #0                     // x27 = bytes pending in _outbuf

Lline:
    cmp     x21, x20
    b.hs    Lexit
    mov     x0, x21
    mov     w1, #'\n'
    sub     x2, x20, x21
    bl      _memchr
    cmp     x0, #0
    csel    x22, x0, x20, ne            // x22 = end of line (exclusive)

    mov     x28, x21                    // skip leading blanks
1:  cmp     x28, x22
    b.hs    Lnext                       // blank line: no output
    ldrb    w1, [x28]
    cmp     w1, #' '
    ccmp    w1, #'\t', #4, ne
    b.ne    2f
    add     x28, x28, #1
    b       1b

2:  sub     x1, x22, x28                // need (len + 1) scratch entries
    add     x24, x1, #1
    cmp     x24, x25
    b.ls    3f
    lsl     x1, x25, #1
    cmp     x24, x1
    csel    x24, x24, x1, hi
    cmp     x24, #SCRATCH_MIN
    mov     x1, #SCRATCH_MIN
    csel    x25, x24, x1, hi            // x25 = max(len + 1, 2 * cap, MIN)
    add     x1, x25, x25, lsl #3        // 8 bytes per value + 1 per op
    mov     x0, x23
    bl      _realloc
    cbz     x0, Lfail
    mov     x23, x0

3:  mov     x1, #(OUTBUF_SIZE - OUT_RESERVE)
    cmp     x27, x1
    b.ls    4f
    mov     x0, x26
    mov     x1, x27
    bl      _write_all
    mov     x27, #0

4:  mov     x0, x28
    mov     x1, x22
    mov     x2, x23
    add     x3, x23, x25, lsl #3
    bl      _eval_expr
    cbnz    w1, Lprint_error
    add     x1, x26, x27
    bl      _fmt_i64
    mov     w1, #'\n'
    strb    w1, [x0], #1
    sub     x27, x0, x26
    b       Lnext
Lprint_error:
    add     x0, x26, x27
    movz    w1, #0x7265                 // "erro"
    movk    w1, #0x6f72, lsl #16
    str     w1, [x0]
    mov     w1, #0x0a72                 // "r\n"
    strh    w1, [x0, #4]
    add     x27, x27, #6

Lnext:
    add     x21, x22, #1
    b       Lline

Lexit:
    mov     x0, x26
    mov     x1, x27
    bl      _write_all
    mov     x0, x23
    bl      _free
    mov     x0, x19
    bl      _free
    mov     w0, #0
Lreturn:
    ldp     x29, x30, [sp, #80]
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp, #0]
    add     sp, sp, #96
    ret
Lfail:                                  // out of memory
    mov     w0, #1
    b       Lreturn
    .cfi_endproc

// void write_all(const void *buf, size_t len) — write(1, ...) until done,
// retrying on EINTR; gives up silently on any other error.
    .private_extern _write_all
    .globl  _write_all
    .p2align 2
_write_all:
    .cfi_startproc
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    mov     x19, x0
    mov     x20, x1
1:  cbz     x20, 3f
    mov     w0, #1                      // STDOUT_FILENO
    mov     x1, x19
    mov     x2, x20
    bl      _write
    cmp     x0, #0
    b.le    2f
    add     x19, x19, x0
    sub     x20, x20, x0
    b       1b
2:  b.eq    3f
    bl      ___error
    ldr     w0, [x0]
    cmp     w0, #EINTR
    b.eq    1b
3:  ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp], #32
    ret
    .cfi_endproc

    .zerofill __DATA,__bss,_outbuf,OUTBUF_SIZE,4

.subsections_via_symbols
