// calc — 64-bit signed integer expression evaluator (AArch64, macOS).
//
// Reads all of stdin, evaluates one expression per line and prints the value
// or "error". Blank lines (only spaces/tabs) print nothing.
//
// Parsing is an iterative operator-precedence (shunting-yard) evaluator with
// heap-allocated value/operator stacks, so nesting depth is bounded only by
// memory, never by the machine stack.

        .equ    STDIN, 0
        .equ    STDOUT, 1
        .equ    EINTR, 4
        .equ    IN_INITIAL, 1 << 20
        .equ    OUT_CAP, 1 << 16
        .equ    OUT_SLACK, 32           // > longest record ("-9223372036854775808\n")
        .equ    ERROR_LEN, 6            // strlen("error\n")

        // Operator codes (index into prec_table).
        .equ    OP_LPAREN, 0
        .equ    OP_ADD, 1
        .equ    OP_SUB, 2
        .equ    OP_MUL, 3
        .equ    OP_DIV, 4
        .equ    OP_MOD, 5
        .equ    OP_NEG, 6

        // eval() status codes.
        .equ    ST_OK, 0
        .equ    ST_ERROR, 1
        .equ    ST_BLANK, 2

        .section __TEXT,__const
prec_table:
        .byte   0, 1, 1, 2, 2, 2, 3
error_msg:
        .ascii  "error\n"

        .text

// ---------------------------------------------------------------------------
// int main(void)
//   x19 input buffer, then current line end / saved result
//   x20 input capacity, then saved eval status   x21 input length
//   x22 cursor           x23 input end        x24 stack capacity (entries)
//   x25 value stack      x26 operator stack   x27 output buffer
//   x28 output length
// ---------------------------------------------------------------------------
        .globl  _main
        .p2align 2
_main:
        stp     x29, x30, [sp, #-96]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]
        stp     x27, x28, [sp, #80]

        // ---- slurp stdin -------------------------------------------------
        mov     x20, #IN_INITIAL
        mov     x0, x20
        bl      _malloc
        cbz     x0, .Lexit
        mov     x19, x0
        mov     x21, #0
.Lread:
        cmp     x21, x20
        b.lo    .Lread_call
        lsl     x20, x20, #1
        mov     x0, x19
        mov     x1, x20
        bl      _realloc
        cbz     x0, .Lexit
        mov     x19, x0
.Lread_call:
        mov     w0, #STDIN
        add     x1, x19, x21
        sub     x2, x20, x21
        bl      _read
        cmp     x0, #0
        b.gt    .Lread_more
        b.eq    .Lread_done
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    .Lread_call
        b       .Lread_done             // unrecoverable: use what we have
.Lread_more:
        add     x21, x21, x0
        b       .Lread

.Lread_done:
        mov     x22, x19
        add     x23, x19, x21
        mov     x24, #0
        mov     x25, #0
        mov     x26, #0

        mov     x0, #OUT_CAP
        bl      _malloc
        cbz     x0, .Lexit
        mov     x27, x0
        mov     x28, #0

        // ---- per-line loop ----------------------------------------------
.Lline:
        cmp     x22, x23
        b.hs    .Lfinish
        mov     x0, x22
        mov     w1, #'\n'
        sub     x2, x23, x22
        bl      _memchr
        cmp     x0, #0
        csel    x19, x23, x0, eq        // x19 = line end (input base no longer needed)

        // Stacks need at most (line length + 1) entries.
        sub     x9, x19, x22
        add     x9, x9, #2
        cmp     x9, x24
        b.ls    .Leval
        lsl     x24, x9, #1
        mov     x0, x25
        bl      _free
        mov     x0, x26
        bl      _free
        lsl     x0, x24, #3
        bl      _malloc
        mov     x25, x0
        mov     x0, x24
        bl      _malloc
        mov     x26, x0
        cbz     x25, .Lexit
        cbz     x26, .Lexit

.Leval:
        mov     x0, x22
        mov     x1, x19
        mov     x2, x25
        mov     x3, x26
        bl      eval
        add     x22, x19, #1            // next line

        cmp     x1, #ST_BLANK
        b.eq    .Lline

        // Make room for one record.
        mov     x9, #(OUT_CAP - OUT_SLACK)
        cmp     x28, x9
        b.ls    .Lemit
        mov     x19, x0                 // line end is consumed; keep result
        mov     x20, x1                 // input capacity is dead; keep status
        mov     x0, x27
        mov     x1, x28
        bl      write_all
        mov     x28, #0
        mov     x0, x19
        mov     x1, x20
.Lemit:
        add     x2, x27, x28
        cbnz    x1, .Lemit_error
        mov     x1, x2
        bl      format_i64
        sub     x28, x0, x27
        b       .Lline
.Lemit_error:
        adrp    x9, error_msg@PAGE
        add     x9, x9, error_msg@PAGEOFF
        ldr     w10, [x9]               // "erro"
        ldrh    w11, [x9, #4]           // "r\n"
        str     w10, [x2]
        strh    w11, [x2, #4]
        add     x28, x28, #ERROR_LEN
        b       .Lline

.Lfinish:
        mov     x0, x27
        mov     x1, x28
        bl      write_all
.Lexit:
        mov     w0, #0
        ldp     x19, x20, [sp, #16]
        ldp     x21, x22, [sp, #32]
        ldp     x23, x24, [sp, #48]
        ldp     x25, x26, [sp, #64]
        ldp     x27, x28, [sp, #80]
        ldp     x29, x30, [sp], #96
        ret

// ---------------------------------------------------------------------------
// write_all(x0 = buf, x1 = len): write everything to stdout, retrying on
// short writes and EINTR. Gives up silently on any other error.
// ---------------------------------------------------------------------------
        .p2align 2
write_all:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        mov     x19, x0
        mov     x20, x1
1:      cbz     x20, 3f
        mov     w0, #STDOUT
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.le    2f
        add     x19, x19, x0
        sub     x20, x20, x0
        b       1b
2:      b.eq    3f                      // wrote 0 bytes: give up
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    1b
3:      ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// ---------------------------------------------------------------------------
// format_i64(x0 = value, x1 = dst) -> x0 = dst past the trailing '\n'.
// Leaf; handles INT64_MIN via unsigned magnitude.
// ---------------------------------------------------------------------------
        .p2align 2
format_i64:
        sub     sp, sp, #32
        add     x2, sp, #32             // build digits backwards in scratch
        mov     w3, #'\n'
        strb    w3, [x2, #-1]!
        cmp     x0, #0
        cneg    x4, x0, lt              // |value| as unsigned
        mov     x5, #10
1:      udiv    x6, x4, x5
        msub    x7, x6, x5, x4
        add     w7, w7, #'0'
        strb    w7, [x2, #-1]!
        mov     x4, x6
        cbnz    x4, 1b
        b.ge    2f                      // flags still from cmp x0, #0
        mov     w3, #'-'
        strb    w3, [x2, #-1]!
2:      add     x3, sp, #32
3:      ldrb    w4, [x2], #1
        strb    w4, [x1], #1
        cmp     x2, x3
        b.lo    3b
        mov     x0, x1
        add     sp, sp, #32
        ret

// ---------------------------------------------------------------------------
// eval(x0 = line start, x1 = line end, x2 = value stack, x3 = op stack)
//   -> x0 = value, x1 = ST_OK | ST_ERROR | ST_BLANK
//
// Two-state machine: "expect operand" and "expect operator".
//   x4 value-stack top (one past last)   x5 op-stack top (one past last)
//   x12 prec_table                       w13 incoming binary op
// apply_top pops one operator and reduces the value stack (leaf helper).
// ---------------------------------------------------------------------------
        .p2align 2
eval:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        mov     x4, x2
        mov     x5, x3
        adrp    x12, prec_table@PAGE
        add     x12, x12, prec_table@PAGEOFF

        // Leading whitespace; a line with nothing else is blank.
1:      cmp     x0, x1
        b.hs    .Lblank
        ldrb    w6, [x0]
        cmp     w6, #' '
        ccmp    w6, #'\t', #4, ne       // Z set if space or tab
        b.ne    .Lexpect_operand
        add     x0, x0, #1
        b       1b

.Lexpect_operand:
        cmp     x0, x1
        b.hs    .Lerror
        ldrb    w6, [x0], #1
        cmp     w6, #' '
        ccmp    w6, #'\t', #4, ne
        b.eq    .Lexpect_operand
        cmp     w6, #'-'
        b.eq    .Lpush_neg
        cmp     w6, #'('
        b.eq    .Lpush_lparen
        sub     w7, w6, #'0'
        cmp     w7, #9
        b.hi    .Lerror

        // NUMBER: accumulate with overflow check against INT64_MAX.
        movz    x8, #0xCCCC                     // x8 = INT64_MAX / 10
        movk    x8, #0xCCCC, lsl #16
        movk    x8, #0xCCCC, lsl #32
        movk    x8, #0x0CCC, lsl #48
        mov     x10, #10
2:      cmp     x0, x1
        b.hs    3f
        ldrb    w6, [x0]
        sub     w6, w6, #'0'
        cmp     w6, #9
        b.hi    3f
        add     x0, x0, #1
        cmp     x7, x8
        b.hi    .Lerror
        b.lo    4f
        cmp     w6, #7                          // INT64_MAX ends in ...807
        b.hi    .Lerror
4:      madd    x7, x7, x10, x6
        b       2b
3:      str     x7, [x4], #8
        b       .Lexpect_operator

.Lpush_neg:
        mov     w7, #OP_NEG
        strb    w7, [x5], #1
        b       .Lexpect_operand
.Lpush_lparen:
        strb    wzr, [x5], #1                   // OP_LPAREN == 0
        b       .Lexpect_operand

.Lexpect_operator:
        cmp     x0, x1
        b.hs    .Lend
        ldrb    w6, [x0], #1
        cmp     w6, #' '
        ccmp    w6, #'\t', #4, ne
        b.eq    .Lexpect_operator
        cmp     w6, #')'
        b.eq    .Lclose
        mov     w13, #OP_ADD
        cmp     w6, #'+'
        b.eq    .Lbinary
        mov     w13, #OP_SUB
        cmp     w6, #'-'
        b.eq    .Lbinary
        mov     w13, #OP_MUL
        cmp     w6, #'*'
        b.eq    .Lbinary
        mov     w13, #OP_DIV
        cmp     w6, #'/'
        b.eq    .Lbinary
        mov     w13, #OP_MOD
        cmp     w6, #'%'
        b.ne    .Lerror

        // Left-associative: reduce while prec(top) >= prec(incoming).
.Lbinary:
        ldrb    w14, [x12, w13, uxtw]
5:      cmp     x5, x3
        b.eq    6f
        ldrb    w7, [x5, #-1]
        ldrb    w9, [x12, w7, uxtw]
        cmp     w9, w14
        b.lo    6f
        sub     x5, x5, #1
        bl      apply_op
        cbnz    w15, .Lerror
        b       5b
6:      strb    w13, [x5], #1
        b       .Lexpect_operand

        // ')' : reduce down to the matching '('.
.Lclose:
        cmp     x5, x3
        b.eq    .Lerror
        ldrb    w7, [x5, #-1]!
        cbz     w7, .Lexpect_operator
        bl      apply_op
        cbnz    w15, .Lerror
        b       .Lclose

        // End of line: reduce everything; any '(' left is unbalanced.
.Lend:
        cmp     x5, x3
        b.eq    7f
        ldrb    w7, [x5, #-1]!
        cbz     w7, .Lerror
        bl      apply_op
        cbnz    w15, .Lerror
        b       .Lend
7:      ldr     x0, [x2]
        mov     x1, #ST_OK
        ldp     x29, x30, [sp], #16
        ret

.Lerror:
        mov     x1, #ST_ERROR
        ldp     x29, x30, [sp], #16
        ret
.Lblank:
        mov     x1, #ST_BLANK
        ldp     x29, x30, [sp], #16
        ret

// ---------------------------------------------------------------------------
// apply_op(w7 = operator, x4 = value-stack top) -> x4 updated, w15 = 0 ok / 1
// error. Clobbers x9-x11. Overflow in + - * / and unary - is an error;
// INT64_MIN % -1 is 0 (sdiv does not trap, msub then yields 0).
// ---------------------------------------------------------------------------
        .p2align 2
apply_op:
        mov     w15, #1
        cmp     w7, #OP_NEG
        b.ne    1f
        ldr     x9, [x4, #-8]
        negs    x9, x9
        b.vs    9f
        str     x9, [x4, #-8]
        mov     w15, #0
        ret

1:      ldp     x9, x10, [x4, #-16]!            // x9 = lhs, x10 = rhs
        cmp     w7, #OP_SUB
        b.eq    .Lsub
        b.hi    .Lmuldiv
        adds    x9, x9, x10
        b.vs    9f
        b       8f
.Lsub:
        subs    x9, x9, x10
        b.vs    9f
        b       8f
.Lmuldiv:
        cmp     w7, #OP_DIV
        b.eq    .Ldiv
        b.hi    .Lmod
        mul     x11, x9, x10
        smulh   x9, x9, x10
        cmp     x9, x11, asr #63                // high half must be sign of low
        b.ne    9f
        mov     x9, x11
        b       8f
.Ldiv:
        cbz     x10, 9f
        cmn     x10, #1
        b.ne    2f
        negs    x9, x9                          // x / -1 == -x
        b.vs    9f
        b       8f
2:      sdiv    x9, x9, x10
        b       8f
.Lmod:
        cbz     x10, 9f
        sdiv    x11, x9, x10
        msub    x9, x11, x10, x9
8:      str     x9, [x4], #8
        mov     w15, #0
9:      ret
