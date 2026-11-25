// eval.s — evaluate one calc expression (see SPEC.md).
//
// Iterative operator-precedence (shunting-yard) evaluator, so arbitrarily
// deep nesting or long unary chains cannot overflow the machine stack.
//
//   int64 eval_expr(const char *cur, const char *end, int64 *vals, uint8 *ops)
//     in:  x0 = first byte of the line, x1 = one past the last byte
//          x2 = value stack, x3 = operator stack; each must hold at least
//               (end - cur + 1) entries
//     out: x0 = value, w1 = 0 on success, 1 on any error
//
// Leaf routine: no stack frame; uses only caller-saved x0-x15.
//
// Operator ids stored on the op stack (precedence in Lprec):
//   0 '('   1 '+'   2 '-'   3 '*'   4 '/'   5 '%'   6 unary '-'

    .set OP_LPAREN, 0
    .set OP_SUB,    2
    .set OP_MUL,    3
    .set OP_DIV,    4
    .set OP_NEG,    6

    .text
    .private_extern _eval_expr
    .globl  _eval_expr
    .p2align 2
_eval_expr:
    .cfi_startproc
    mov     x15, x30                    // return address (Lapply uses bl)
    mov     x4, x2                      // x4 = value stack top (next free)
    mov     x5, x3                      // x5 = op stack top (next free)
    adrp    x12, Lopid@PAGE
    add     x12, x12, Lopid@PAGEOFF
    adrp    x13, Lprec@PAGE
    add     x13, x13, Lprec@PAGEOFF
    mov     x10, #0xcccccccccccccccc
    lsr     x10, x10, #4                // INT64_MAX / 10

// ---- expecting an operand: NUMBER, '(' or unary '-' ----
Loperand:
    cmp     x0, x1
    b.hs    Lerr
    ldrb    w6, [x0], #1
    cmp     w6, #' '
    ccmp    w6, #'\t', #4, ne
    b.eq    Loperand
    cmp     w6, #'-'
    b.eq    Lpush_neg
    cmp     w6, #'('
    b.eq    Lpush_lparen
    sub     w9, w6, #'0'
    cmp     w9, #9
    b.hi    Lerr

Ldigit:                                 // x9 = accumulated literal
    cmp     x0, x1
    b.hs    Lnumber_done
    ldrb    w6, [x0]
    sub     w7, w6, #'0'
    cmp     w7, #9
    b.hi    Lnumber_done
    add     x0, x0, #1
    cmp     x9, x10
    b.hi    Lerr                        // x9 * 10 would exceed INT64_MAX
    add     x9, x9, x9, lsl #2
    add     x9, x7, x9, lsl #1          // x9 = x9 * 10 + digit
    tbnz    x9, #63, Lerr
    b       Ldigit
Lnumber_done:
    str     x9, [x4], #8

// ---- expecting a binary operator, ')' or end of line ----
Loperator:
    cmp     x0, x1
    b.hs    Lfinish
    ldrb    w6, [x0], #1
    cmp     w6, #' '
    ccmp    w6, #'\t', #4, ne
    b.eq    Loperator
    cmp     w6, #')'
    b.eq    Lclose
    sub     w6, w6, #'%'
    cmp     w6, #('/' - '%')
    b.hi    Lerr
    ldrb    w14, [x12, w6, uxtw]        // w14 = operator id
    cbz     w14, Lerr
    ldrb    w8, [x13, x14]              // w8 = its precedence
Lreduce:                                // pop while prec(top) >= prec(new)
    cmp     x5, x3
    b.eq    Lpush_op
    ldrb    w9, [x5, #-1]
    ldrb    w11, [x13, x9]
    cmp     w11, w8
    b.lo    Lpush_op
    sub     x5, x5, #1
    bl      Lapply
    b       Lreduce
Lpush_op:
    strb    w14, [x5], #1
    b       Loperand

Lpush_neg:
    mov     w6, #OP_NEG
    strb    w6, [x5], #1
    b       Loperand
Lpush_lparen:
    strb    wzr, [x5], #1
    b       Loperand

Lclose:                                 // reduce back to the matching '('
    cmp     x5, x3
    b.eq    Lerr
    ldrb    w9, [x5, #-1]!
    cbz     w9, Loperator
    bl      Lapply
    b       Lclose

Lfinish:                                // reduce everything; no '(' may remain
    cmp     x5, x3
    b.eq    Lresult
    ldrb    w9, [x5, #-1]!
    cbz     w9, Lerr
    bl      Lapply
    b       Lfinish
Lresult:
    ldr     x0, [x2]
    mov     w1, #0
    ret     x15

Lerr:
    mov     w1, #1
    ret     x15

// Apply operator w9 (1..6) to the top of the value stack. Branches to Lerr
// on overflow or division by zero (x15 still holds the caller's lr).
// Clobbers only x4, x6, x7, x11 (x8 holds the pending operator's precedence).
Lapply:
    cmp     w9, #OP_NEG
    b.ne    Lbinary
    ldr     x6, [x4, #-8]
    negs    x6, x6
    b.vs    Lerr
    str     x6, [x4, #-8]
    ret
Lbinary:
    ldp     x6, x7, [x4, #-16]!         // x6 = lhs, x7 = rhs
    cmp     w9, #OP_SUB
    b.hi    Lmuldiv
    b.eq    Lsub
    adds    x6, x6, x7
    b.vs    Lerr
    b       Lstore
Lsub:
    subs    x6, x6, x7
    b.vs    Lerr
    b       Lstore
Lmuldiv:
    cmp     w9, #OP_DIV
    b.hi    Lmod
    b.eq    Ldiv
    smulh   x11, x6, x7
    mul     x6, x6, x7
    cmp     x11, x6, asr #63            // high half must be the sign of low
    b.ne    Lerr
    b       Lstore
Ldiv:
    cbz     x7, Lerr
    cmn     x7, #1
    b.ne    1f
    negs    x6, x6                      // x / -1 == -x; overflows for INT64_MIN
    b.vs    Lerr
    b       Lstore
1:  sdiv    x6, x6, x7
    b       Lstore
Lmod:                                   // INT64_MIN % -1: sdiv wraps, msub gives 0
    cbz     x7, Lerr
    sdiv    x11, x6, x7
    msub    x6, x11, x7, x6
Lstore:
    str     x6, [x4], #8
    ret
    .cfi_endproc

    .const
Lopid:                                  // operator id for chars '%' .. '/'
    .byte   5, 0, 0, 0, 0, 3, 1, 0, 2, 0, 4
Lprec:                                  // precedence by operator id
    .byte   0, 1, 1, 2, 2, 2, 3

.subsections_via_symbols
