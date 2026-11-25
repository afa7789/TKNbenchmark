// format.s — signed 64-bit integer to decimal text.

        .text

// size_t fmt_i64(char *dst, int64_t v)
//   Writes the decimal form of v (no terminator) to dst; returns its length
//   (at most 20 bytes). Leaf; uses a 32-byte scratch area on the stack.
        .globl _fmt_i64
        .p2align 2
_fmt_i64:
        .cfi_startproc
        sub     sp, sp, #32
        .cfi_def_cfa_offset 32
        mov     x2, x0                          // write cursor
        cmp     x1, #0
        cneg    x3, x1, mi                      // |v| as unsigned (INT64_MIN stays 2^63)
        b.pl    1f
        mov     w4, #'-'
        strb    w4, [x2], #1
1:      add     x5, sp, #32                     // digits are produced backwards
        mov     x6, x5
        mov     x7, #10
2:      udiv    x8, x3, x7
        msub    x9, x8, x7, x3
        add     w9, w9, #'0'
        strb    w9, [x6, #-1]!
        mov     x3, x8
        cbnz    x3, 2b
3:      ldrb    w9, [x6], #1
        strb    w9, [x2], #1
        cmp     x6, x5
        b.lo    3b
        sub     x0, x2, x0
        add     sp, sp, #32
        ret
        .cfi_endproc

.subsections_via_symbols
