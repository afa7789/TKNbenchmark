// eval.s — evaluate one calc expression (see SPEC.md).
//
// The parser is an iterative operator-precedence (shunting-yard style)
// evaluator with explicit stacks, so arbitrarily deep nesting such as
// "((((...))))" cannot overflow the machine stack.  It alternates between two
// states:
//
//   expect_operand:  NUMBER | '-' (unary, pushed as OP_NEG) | '('
//   expect_operator: '+' '-' '*' '/' '%' | ')' | end of line
//
// Before an operator of precedence P is pushed, every stacked operator with
// precedence >= P is applied (left associativity; unary minus binds tightest).
// '(' has precedence 0, so it acts as a barrier for every reduction.
//
// C prototype:
//   uint64_t eval_line(const char *p, const char *end,
//                      int64_t *vstack, uint8_t *ostack);
//   returns x0 = EVAL_OK / EVAL_ERROR / EVAL_BLANK, x1 = value when EVAL_OK
//
// Both stacks must hold at least (end - p + 1) entries.
// Leaf function: touches only x0-x15 and the flags.

        .equ    EVAL_OK,        0
        .equ    EVAL_ERROR,     1
        .equ    EVAL_BLANK,     2

        // Operator codes stored on the operator stack (index into prec_table).
        .equ    OP_LPAREN,      0
        .equ    OP_ADD,         1
        .equ    OP_SUB,         2
        .equ    OP_MUL,         3
        .equ    OP_DIV,         4
        .equ    OP_MOD,         5
        .equ    OP_NEG,         6

        // What to do once a reduction loop finishes.
        .equ    K_BINARY,       0       // push the pending binary operator
        .equ    K_RPAREN,       1       // pop the matching '('
        .equ    K_EOL,          2       // finish the line

        .section __TEXT,__const
prec_table:
        .byte   0, 1, 1, 2, 2, 2, 3     // ( + - * / % neg

        .text
        .globl  _eval_line
        .p2align 2
// Register map:
//   x0  cursor            x1  line end
//   x2  value stack base  x3  operator stack base
//   x4  value stack top   x5  operator stack top   (both: next free slot)
//   x6  current byte      x7/x8 operands (a, b)    x9 result
//   x10 pending opcode    x11 minimum precedence   x12 continuation kind
//   x13 stacked opcode    x14 its precedence       x15 &prec_table
//   x16 literal limit (INT64_MAX / 10)
_eval_line:
        mov     x4, x2
        mov     x5, x3
        adrp    x15, prec_table@PAGE
        add     x15, x15, prec_table@PAGEOFF
        mov     x16, #0xCCCCCCCCCCCCCCCC
        lsr     x16, x16, #4            // 0x0CCC...C = 922337203685477580

// ---------------------------------------------------------------- operand
expect_operand:
        cmp     x0, x1
        b.hs    operand_eol
        ldrb    w6, [x0], #1
        cmp     w6, #' '
        b.eq    expect_operand
        cmp     w6, #'\t'
        b.eq    expect_operand
        sub     w7, w6, #'0'
        cmp     w7, #9
        b.ls    number
        cmp     w6, #'-'
        b.eq    push_neg
        cmp     w6, #'('
        b.ne    fail
        mov     w9, #OP_LPAREN
        strb    w9, [x5], #1
        b       expect_operand

push_neg:
        mov     w9, #OP_NEG
        strb    w9, [x5], #1
        b       expect_operand

operand_eol:
        // Nothing at all on the line means blank; otherwise an operand is missing.
        cmp     x4, x2
        ccmp    x5, x3, #0, eq
        b.ne    fail
        mov     x0, #EVAL_BLANK
        ret

// x7 holds the first digit; accumulate the rest with overflow detection.
number:
        cmp     x0, x1
        b.hs    number_done
        ldrb    w6, [x0]
        sub     w9, w6, #'0'
        cmp     w9, #9
        b.hi    number_done
        add     x0, x0, #1
        cmp     x7, x16
        b.hi    fail                    // x7 * 10 would exceed INT64_MAX
        add     x7, x7, x7, lsl #2      // x7 *= 5
        add     x7, x9, x7, lsl #1      // x7 = x7 * 2 + digit
        tbnz    x7, #63, fail           // > INT64_MAX
        b       number
number_done:
        str     x7, [x4], #8

// ---------------------------------------------------------------- operator
expect_operator:
        cmp     x0, x1
        b.hs    operator_eol
        ldrb    w6, [x0], #1
        cmp     w6, #' '
        b.eq    expect_operator
        cmp     w6, #'\t'
        b.eq    expect_operator
        cmp     w6, #')'
        b.eq    close_paren
        mov     w10, #OP_ADD
        cmp     w6, #'+'
        b.eq    binary
        mov     w10, #OP_SUB
        cmp     w6, #'-'
        b.eq    binary
        mov     w10, #OP_MUL
        cmp     w6, #'*'
        b.eq    binary
        mov     w10, #OP_DIV
        cmp     w6, #'/'
        b.eq    binary
        mov     w10, #OP_MOD
        cmp     w6, #'%'
        b.ne    fail
binary:
        ldrb    w11, [x15, w10, uxtw]
        mov     w12, #K_BINARY
        b       reduce
close_paren:
        mov     w11, #1                 // everything except '('
        mov     w12, #K_RPAREN
        b       reduce
operator_eol:
        mov     w11, #1
        mov     w12, #K_EOL

// ---------------------------------------------------------------- reduce
// Apply stacked operators while their precedence is >= w11.
reduce:
        cmp     x5, x3
        b.eq    reduce_done
        ldrb    w13, [x5, #-1]
        ldrb    w14, [x15, w13, uxtw]
        cmp     w14, w11
        b.lo    reduce_done
        sub     x5, x5, #1
        ldr     x8, [x4, #-8]!          // pop right operand (or the negand)
        cmp     w13, #OP_NEG
        b.eq    apply_neg
        ldr     x7, [x4, #-8]           // left operand; result replaces it
        cmp     w13, #OP_SUB
        b.lo    apply_add
        b.eq    apply_sub
        cmp     w13, #OP_DIV
        b.lo    apply_mul
        b.eq    apply_div

apply_mod:
        cbz     x8, fail
        sdiv    x9, x7, x8              // INT64_MIN / -1 yields INT64_MIN ...
        msub    x9, x9, x8, x7          // ... so the remainder is correctly 0
        b       store_result
apply_add:
        adds    x9, x7, x8
        b.vs    fail
        b       store_result
apply_sub:
        subs    x9, x7, x8
        b.vs    fail
        b       store_result
apply_mul:
        mul     x9, x7, x8
        smulh   x6, x7, x8
        cmp     x6, x9, asr #63         // high half must be the sign extension
        b.ne    fail
        b       store_result
apply_div:
        cbz     x8, fail
        cmn     x8, #1
        b.eq    apply_div_neg1
        sdiv    x9, x7, x8
        b       store_result
apply_div_neg1:
        negs    x9, x7                  // overflows only for INT64_MIN
        b.vs    fail
store_result:
        str     x9, [x4, #-8]
        b       reduce

apply_neg:
        negs    x9, x8
        b.vs    fail
        str     x9, [x4], #8
        b       reduce

reduce_done:
        cmp     w12, #K_RPAREN
        b.lo    push_binary
        b.eq    pop_paren
        // K_EOL: only an unmatched '(' can remain.
        cmp     x5, x3
        b.ne    fail
        ldr     x1, [x2]
        mov     x0, #EVAL_OK
        ret

push_binary:
        strb    w10, [x5], #1
        b       expect_operand

pop_paren:
        cmp     x5, x3                  // no '(' to match
        b.eq    fail
        sub     x5, x5, #1
        b       expect_operator

fail:
        mov     x0, #EVAL_ERROR
        ret
