// eval.s — evaluate one calc expression line (64-bit signed integers).
//
// Operator-precedence parser driven by an explicit value stack and an
// operator stack, so arbitrarily deep nesting ("((((...", "----...") cannot
// overflow the machine stack. Grammar and semantics: see SPEC.md.
//
// Operator codes carry their precedence in the high nibble:
//   0x00 '('   0x10 '+'  0x11 '-'   0x20 '*'  0x21 '/'  0x22 '%'   0x30 unary '-'

        .equ OP_LPAREN, 0x00
        .equ OP_ADD,    0x10
        .equ OP_SUB,    0x11
        .equ OP_MUL,    0x20
        .equ OP_DIV,    0x21
        .equ OP_MOD,    0x22
        .equ OP_NEG,    0x30

        .equ ST_OK,     0
        .equ ST_ERROR,  1
        .equ ST_BLANK,  2

        .text

// int eval_line(const char *p, const char *end, int64_t *vals, uint8_t *ops)
//   vals / ops must each hold at least (end - p) entries.
//   Returns w0 = ST_OK (value in x1), ST_ERROR, or ST_BLANK (only spaces/tabs).
//
// Register map:
//   x0  cursor            x1  end              x2  vals base   x3  ops base
//   x4  vals top (next)   x5  ops top (next)   w6  state: 0 = expect operand,
//                                                         1 = expect operator
//   w7  current char      x10 INT64_MAX / 10   x14 &binop_tab
//   w11 pending op        w12 pending precedence  w13 op to apply  x8, x9, x15 scratch
        .globl _eval_line
        .p2align 2
_eval_line:
        .cfi_startproc
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        .cfi_def_cfa w29, 16
        .cfi_offset w30, -8
        .cfi_offset w29, -16

        mov     x4, x2
        mov     x5, x3
        mov     w6, #0
        mov     x10, #0xCCCCCCCCCCCCCCCC
        lsr     x10, x10, #4                    // 922337203685477580
        adrp    x14, Lbinop_tab@PAGE
        add     x14, x14, Lbinop_tab@PAGEOFF

Lnext:
        cmp     x0, x1
        b.hs    Lend
        ldrb    w7, [x0], #1
        cmp     w7, #' '
        b.eq    Lnext
        cmp     w7, #'\t'
        b.eq    Lnext
        cbnz    w6, Loperator

        // ---- expecting an operand: NUMBER, unary '-', or '(' ----
        sub     w8, w7, #'0'
        cmp     w8, #9
        b.ls    Lnumber
        cmp     w7, #'-'
        b.eq    Lpush_neg
        cmp     w7, #'('
        b.ne    Lerror
        mov     w8, #OP_LPAREN
        strb    w8, [x5], #1
        b       Lnext
Lpush_neg:
        mov     w8, #OP_NEG
        strb    w8, [x5], #1
        b       Lnext

Lnumber:
        mov     x9, x8                          // accumulator
Ldigit:
        cmp     x0, x1
        b.hs    Lnumber_done
        ldrb    w7, [x0]
        sub     w8, w7, #'0'
        cmp     w8, #9
        b.hi    Lnumber_done
        add     x0, x0, #1
        cmp     x9, x10
        b.hi    Lerror                          // acc * 10 would exceed INT64_MAX
        add     x9, x9, x9, lsl #2
        add     x9, x8, x9, lsl #1              // acc = acc * 10 + digit
        tbnz    x9, #63, Lerror                 // > INT64_MAX
        b       Ldigit
Lnumber_done:
        str     x9, [x4], #8
        mov     w6, #1
        b       Lnext

        // ---- expecting an operator: binary op or ')' ----
Loperator:
        cmp     w7, #')'
        b.eq    Lclose
        sub     w8, w7, #'%'
        cmp     w8, #('/' - '%')
        b.hi    Lerror
        ldrb    w11, [x14, w8, uxtw]
        cbz     w11, Lerror
        lsr     w12, w11, #4                    // precedence of the new op
Lreduce:                                        // left-assoc: pop while prec(top) >= prec(new)
        cmp     x5, x3
        b.eq    Lpush_op
        ldrb    w13, [x5, #-1]
        cmp     w12, w13, lsr #4
        b.hi    Lpush_op
        sub     x5, x5, #1
        bl      Lapply
        b       Lreduce
Lpush_op:
        strb    w11, [x5], #1
        mov     w6, #0
        b       Lnext

Lclose:
        cmp     x5, x3
        b.eq    Lerror                          // no matching '('
        ldrb    w13, [x5, #-1]!
        cbz     w13, Lnext                      // matched '(' (still expecting an operator)
        bl      Lapply
        b       Lclose

        // ---- end of line ----
Lend:
        cbnz    w6, Lfinish
        cmp     x4, x2                          // nothing parsed at all => blank line
        ccmp    x5, x3, #0, eq
        b.ne    Lerror                          // dangling operator / '('
        mov     w0, #ST_BLANK
        ldp     x29, x30, [sp], #16
        ret
Lfinish:
        cmp     x5, x3
        b.eq    Lresult
        ldrb    w13, [x5, #-1]!
        cbz     w13, Lerror                     // unclosed '('
        bl      Lapply
        b       Lfinish
Lresult:
        ldr     x1, [x2]
        mov     w0, #ST_OK
        ldp     x29, x30, [sp], #16
        ret

Lerror:
        mov     w0, #ST_ERROR
        ldp     x29, x30, [sp], #16
        ret

// Lapply: local subroutine. Applies operator w13 to the top of the value
// stack (x4). Clobbers x8, x9, x15, flags. Never touches sp, so on overflow or
// division by zero it branches straight to Lerror, which unwinds the frame.
Lapply:
        cmp     w13, #OP_NEG
        b.ne    Lbinary
        ldr     x8, [x4, #-8]
        negs    x8, x8
        b.vs    Lerror                          // -INT64_MIN
        str     x8, [x4, #-8]
        ret
Lbinary:
        ldp     x8, x9, [x4, #-16]!             // x8 = lhs, x9 = rhs
        cmp     w13, #OP_ADD
        b.eq    Ladd
        cmp     w13, #OP_SUB
        b.eq    Lsub
        cmp     w13, #OP_MUL
        b.eq    Lmul
        cbz     x9, Lerror                      // '/' or '%' by zero
        cmp     w13, #OP_DIV
        b.eq    Ldiv
        sdiv    x15, x8, x9                     // '%': INT64_MIN % -1 wraps to 0
        msub    x8, x15, x9, x8
        b       Lstore
Ldiv:
        cmn     x9, #1
        b.ne    1f
        negs    x8, x8                          // x / -1 == -x; overflows for INT64_MIN
        b.vs    Lerror
        b       Lstore
1:      sdiv    x8, x8, x9
        b       Lstore
Ladd:
        adds    x8, x8, x9
        b.vs    Lerror
        b       Lstore
Lsub:
        subs    x8, x8, x9
        b.vs    Lerror
        b       Lstore
Lmul:
        mul     x15, x8, x9
        smulh   x8, x8, x9
        cmp     x8, x15, asr #63                // high half must be sign of low half
        b.ne    Lerror
        mov     x8, x15
Lstore:
        str     x8, [x4], #8
        ret
        .cfi_endproc

        .section __TEXT,__const
// Binary operator codes indexed by (char - '%'); 0 = not an operator.
Lbinop_tab:
        .byte   OP_MOD                          // '%'
        .byte   0, 0, 0, 0                      // '&' '\'' '(' ')'
        .byte   OP_MUL                          // '*'
        .byte   OP_ADD                          // '+'
        .byte   0                               // ','
        .byte   OP_SUB                          // '-'
        .byte   0                               // '.'
        .byte   OP_DIV                          // '/'

.subsections_via_symbols
