// format.s — signed 64-bit integer to decimal text.
//
//   char *fmt_i64(int64 value, char *dst)
//     Writes the decimal form of x0 (no terminator) at x1 and returns the
//     pointer one past the last byte written. At most 20 bytes are written.
//
// Leaf routine: builds the digits in the red zone below sp.

    .text
    .private_extern _fmt_i64
    .globl  _fmt_i64
    .p2align 2
_fmt_i64:
    .cfi_startproc
    tbz     x0, #63, 1f
    mov     w3, #'-'
    strb    w3, [x1], #1
    neg     x0, x0                      // magnitude as unsigned (INT64_MIN ok)
1:  mov     x4, sp                      // digits grow downward from sp
    mov     x8, x4
    mov     x5, #10
2:  udiv    x6, x0, x5
    msub    x7, x6, x5, x0
    add     w7, w7, #'0'
    strb    w7, [x4, #-1]!
    mov     x0, x6
    cbnz    x0, 2b
3:  ldrb    w7, [x4], #1
    strb    w7, [x1], #1
    cmp     x4, x8
    b.ne    3b
    mov     x0, x1
    ret
    .cfi_endproc

.subsections_via_symbols
