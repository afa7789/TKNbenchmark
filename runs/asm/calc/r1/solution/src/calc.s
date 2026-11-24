// calc — 64-bit signed integer expression evaluator (AArch64, macOS)
//
// Reads all of stdin, evaluates one expression per line and prints its value
// or "error".  Blank lines (only spaces/tabs) print nothing.
//
// Parsing is an iterative operator-precedence (shunting-yard) evaluator with
// heap-allocated operand/operator stacks, so arbitrarily deep nesting such as
// "((((...))))" or "------5" cannot overflow the machine stack.

        .equ    STDIN, 0
        .equ    STDOUT, 1
        .equ    EINTR, 4

        .equ    IN_INIT_CAP, 1 << 20       // initial input buffer size
        .equ    OUT_CAP, 1 << 16           // output buffer size
        .equ    OUT_SLACK, 32              // max bytes one result can emit
        .equ    STK_INIT_CAP, 256          // initial evaluator stack entries

        // Operator codes stored on the operator stack.
        .equ    OP_LPAREN, 0
        .equ    OP_ADD, 1
        .equ    OP_SUB, 2
        .equ    OP_MUL, 3
        .equ    OP_DIV, 4
        .equ    OP_MOD, 5
        .equ    OP_NEG, 6

        // eval_line status codes.
        .equ    ST_OK, 0
        .equ    ST_ERROR, 1
        .equ    ST_EMPTY, 2

        .section __TEXT,__const
// Binding power per operator code.  '(' has 0 so reductions stop at it.
Lprec:
        .byte   0, 1, 1, 2, 2, 2, 3
Lerror_msg:
        .ascii  "error\n"
        .equ    ERROR_MSG_LEN, 6

        .text

// ---------------------------------------------------------------------------
// int main(void)
//
// Register use:
//   x19  input buffer          x20  input end pointer
//   x21  current line start    x22  output buffer
//   x23  output fill length    x24  operand stack (int64[cap])
//   x25  operator stack (u8[cap])  x26  stack capacity (entries)
//   x27  current line end      x28  input capacity (during read)
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

        // ---- slurp stdin ----
        mov     x28, #IN_INIT_CAP
        mov     x0, x28
        bl      _malloc
        cbz     x0, Lout_of_memory
        mov     x19, x0
        mov     x20, #0                     // bytes read so far
Lread_loop:
        cmp     x20, x28
        b.lo    Lread_some
        lsl     x28, x28, #1
        mov     x0, x19
        mov     x1, x28
        bl      _realloc
        cbz     x0, Lout_of_memory
        mov     x19, x0
Lread_some:
        mov     w0, #STDIN
        add     x1, x19, x20
        sub     x2, x28, x20
        bl      _read
        cmp     x0, #0
        b.gt    Lread_got
        b.eq    Lread_done
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lread_some
        b       Lread_done                  // treat read errors as EOF
Lread_got:
        add     x20, x20, x0
        b       Lread_loop
Lread_done:
        add     x20, x19, x20               // x20 = end of input
        mov     x21, x19

        // ---- output buffer and evaluator stacks ----
        mov     x0, #OUT_CAP
        bl      _malloc
        cbz     x0, Lout_of_memory
        mov     x22, x0
        mov     x23, #0

        mov     x26, #STK_INIT_CAP
        lsl     x0, x26, #3
        bl      _malloc
        cbz     x0, Lout_of_memory
        mov     x24, x0
        mov     x0, x26
        bl      _malloc
        cbz     x0, Lout_of_memory
        mov     x25, x0

        // ---- per-line loop ----
Lline_loop:
        cmp     x21, x20
        b.hs    Lfinish
        mov     x0, x21
        mov     w1, #'\n'
        sub     x2, x20, x21
        bl      _memchr
        cmp     x0, #0
        csel    x27, x0, x20, ne            // line end (newline or EOF)

        // Every byte pushes at most one stack entry; ensure cap > line length.
        sub     x9, x27, x21
        cmp     x9, x26
        b.lo    Lcap_ok
        add     x9, x9, #1
        lsl     x26, x26, #1
        cmp     x26, x9
        csel    x26, x26, x9, hs
        mov     x0, x24
        lsl     x1, x26, #3
        bl      _realloc
        cbz     x0, Lout_of_memory
        mov     x24, x0
        mov     x0, x25
        mov     x1, x26
        bl      _realloc
        cbz     x0, Lout_of_memory
        mov     x25, x0
Lcap_ok:
        mov     x0, x21
        mov     x1, x27
        mov     x2, x24
        mov     x3, x25
        bl      _eval_line
        add     x21, x27, #1                // advance past the newline
        cmp     w1, #ST_EMPTY
        b.eq    Lline_loop

        // Make room for the longest possible result line.
        mov     x9, #(OUT_CAP - OUT_SLACK)
        cmp     x23, x9
        b.ls    Lemit
        mov     x27, x0                     // preserve value / status
        mov     w28, w1
        mov     x0, x22
        mov     x1, x23
        bl      _write_all
        mov     x23, #0
        mov     x0, x27
        mov     w1, w28
Lemit:
        add     x9, x22, x23
        cbnz    w1, Lemit_error
        mov     x1, x9
        bl      _format_i64
        add     x23, x23, x0
        b       Lline_loop
Lemit_error:
        adrp    x10, Lerror_msg@PAGE
        add     x10, x10, Lerror_msg@PAGEOFF
        ldr     w11, [x10]                  // "erro"
        ldrh    w12, [x10, #4]              // "r\n"
        str     w11, [x9]
        strh    w12, [x9, #4]
        add     x23, x23, #ERROR_MSG_LEN
        b       Lline_loop

Lfinish:
        mov     x0, x22
        mov     x1, x23
        bl      _write_all
        mov     w0, #0
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #96
        ret

Lout_of_memory:
        mov     w0, #1
        bl      __exit

// ---------------------------------------------------------------------------
// eval_line(x0 = start, x1 = end, x2 = operand stack, x3 = operator stack)
//   -> x0 = value, w1 = ST_OK | ST_ERROR | ST_EMPTY
//
// Two-state machine: Lexpect_operand / Lexpect_operator.
//   x4  operand stack top (next free slot)
//   x5  operator stack top (next free slot)
//   x14 precedence table
//   x9  current byte / pending operator code
//   x15 pending operator precedence
// ---------------------------------------------------------------------------
        .p2align 2
_eval_line:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        mov     x4, x2
        mov     x5, x3
        adrp    x14, Lprec@PAGE
        add     x14, x14, Lprec@PAGEOFF

Lexpect_operand:
        cmp     x0, x1
        b.hs    Lend_in_operand
        ldrb    w9, [x0], #1
        cmp     w9, #' '
        b.eq    Lexpect_operand
        cmp     w9, #'\t'
        b.eq    Lexpect_operand
        sub     w10, w9, #'0'
        cmp     w10, #9
        b.ls    Lnumber
        cmp     w9, #'-'
        b.eq    Lpush_neg
        cmp     w9, #'('
        b.ne    Leval_error
        mov     w9, #OP_LPAREN
        strb    w9, [x5], #1
        b       Lexpect_operand
Lpush_neg:
        mov     w9, #OP_NEG
        strb    w9, [x5], #1
        b       Lexpect_operand

Lend_in_operand:
        // Nothing pushed at all means the line was blank.
        cmp     x5, x3
        b.ne    Leval_error
        mov     x0, #0
        mov     w1, #ST_EMPTY
        ldp     x29, x30, [sp], #16
        ret

        // NUMBER: w10 holds the first digit.  Reject anything > INT64_MAX.
Lnumber:
        mov     w11, w10
        mov     x12, #0xcccccccccccccccc
        lsr     x12, x12, #4                // 922337203685477580 = INT64_MAX / 10
        mov     x13, #10
Lnumber_loop:
        cmp     x0, x1
        b.hs    Lnumber_done
        ldrb    w9, [x0]
        sub     w10, w9, #'0'
        cmp     w10, #9
        b.hi    Lnumber_done
        add     x0, x0, #1
        cmp     x11, x12
        b.hi    Leval_error
        madd    x11, x11, x13, x10          // <= 9223372036854775809, no wrap
        tbnz    x11, #63, Leval_error
        b       Lnumber_loop
Lnumber_done:
        str     x11, [x4], #8

Lexpect_operator:
        cmp     x0, x1
        b.hs    Lend_in_operator
        ldrb    w9, [x0], #1
        cmp     w9, #' '
        b.eq    Lexpect_operator
        cmp     w9, #'\t'
        b.eq    Lexpect_operator
        cmp     w9, #')'
        b.eq    Lrparen
        cmp     w9, #'+'
        b.eq    Lop_add
        cmp     w9, #'-'
        b.eq    Lop_sub
        cmp     w9, #'*'
        b.eq    Lop_mul
        cmp     w9, #'/'
        b.eq    Lop_div
        cmp     w9, #'%'
        b.ne    Leval_error
        mov     w9, #OP_MOD
        b       Lbinop
Lop_add:
        mov     w9, #OP_ADD
        b       Lbinop
Lop_sub:
        mov     w9, #OP_SUB
        b       Lbinop
Lop_mul:
        mov     w9, #OP_MUL
        b       Lbinop
Lop_div:
        mov     w9, #OP_DIV

        // Reduce while the stacked operator binds at least as tightly
        // (left associativity), then push the new one.
Lbinop:
        ldrb    w15, [x14, w9, uxtw]
Lbinop_reduce:
        cmp     x5, x3
        b.ls    Lbinop_push
        ldrb    w10, [x5, #-1]
        ldrb    w10, [x14, w10, uxtw]
        cmp     w10, w15
        b.lo    Lbinop_push
        bl      Lreduce
        b       Lbinop_reduce
Lbinop_push:
        strb    w9, [x5], #1
        b       Lexpect_operand

Lrparen:
        cmp     x5, x3
        b.ls    Leval_error                 // ')' without matching '('
        ldrb    w10, [x5, #-1]
        cbz     w10, Lrparen_match          // OP_LPAREN
        bl      Lreduce
        b       Lrparen
Lrparen_match:
        sub     x5, x5, #1
        b       Lexpect_operator

Lend_in_operator:
        cmp     x5, x3
        b.ls    Lend_done
        ldrb    w10, [x5, #-1]
        cbz     w10, Leval_error            // unclosed '('
        bl      Lreduce
        b       Lend_in_operator
Lend_done:
        ldr     x0, [x2]
        mov     w1, #ST_OK
        ldp     x29, x30, [sp], #16
        ret

Leval_error:
        mov     x0, #0
        mov     w1, #ST_ERROR
        ldp     x29, x30, [sp], #16
        ret

// Pop one operator and apply it to the operand stack.  Local subroutine of
// eval_line: it does not touch sp, so on failure it branches straight to
// Leval_error, which unwinds eval_line's frame.  Clobbers x10-x13, x16.
//   x11 = right operand (or sole operand of NEG), x12 = left operand.
Lreduce:
        ldrb    w10, [x5, #-1]!
        ldr     x11, [x4, #-8]
        cmp     w10, #OP_NEG
        b.ne    Lreduce_binary
        negs    x11, x11
        b.vs    Leval_error
        str     x11, [x4, #-8]
        ret
Lreduce_binary:
        ldr     x12, [x4, #-16]!
        cmp     w10, #OP_ADD
        b.eq    Lapply_add
        cmp     w10, #OP_SUB
        b.eq    Lapply_sub
        cmp     w10, #OP_MUL
        b.eq    Lapply_mul
        cbz     x11, Leval_error            // '/' or '%' by zero
        cmp     w10, #OP_DIV
        b.eq    Lapply_div
        // OP_MOD.  AArch64 sdiv does not trap: INT64_MIN / -1 yields
        // INT64_MIN, and the msub then gives the correct remainder 0.
        sdiv    x13, x12, x11
        msub    x12, x13, x11, x12
        b       Lreduce_store
Lapply_add:
        adds    x12, x12, x11
        b.vs    Leval_error
        b       Lreduce_store
Lapply_sub:
        subs    x12, x12, x11
        b.vs    Leval_error
        b       Lreduce_store
Lapply_mul:
        mul     x13, x12, x11
        smulh   x16, x12, x11
        cmp     x16, x13, asr #63           // high half must be sign of low
        b.ne    Leval_error
        mov     x12, x13
        b       Lreduce_store
Lapply_div:
        cmn     x11, #1
        b.ne    Lapply_sdiv
        negs    x12, x12                    // x / -1 == -x; INT64_MIN overflows
        b.vs    Leval_error
        b       Lreduce_store
Lapply_sdiv:
        sdiv    x12, x12, x11
Lreduce_store:
        str     x12, [x4], #8
        ret

// ---------------------------------------------------------------------------
// format_i64(x0 = value, x1 = dst) -> x0 = bytes written
// Writes the decimal value followed by '\n' (at most 21 bytes).
// ---------------------------------------------------------------------------
        .p2align 2
_format_i64:
        sub     sp, sp, #32
        mov     x2, x1                      // write cursor
        cmp     x0, #0
        b.ge    Lfmt_digits
        mov     w9, #'-'
        strb    w9, [x2], #1
        neg     x0, x0                      // as unsigned, also fine for INT64_MIN
Lfmt_digits:
        add     x3, sp, #32                 // build digits backwards
        mov     x4, #10
Lfmt_loop:
        udiv    x5, x0, x4
        msub    x6, x5, x4, x0
        add     w6, w6, #'0'
        strb    w6, [x3, #-1]!
        mov     x0, x5
        cbnz    x0, Lfmt_loop
        add     x5, sp, #32
Lfmt_copy:
        ldrb    w6, [x3], #1
        strb    w6, [x2], #1
        cmp     x3, x5
        b.lo    Lfmt_copy
        mov     w6, #'\n'
        strb    w6, [x2], #1
        sub     x0, x2, x1
        add     sp, sp, #32
        ret

// ---------------------------------------------------------------------------
// write_all(x0 = buf, x1 = len): write the whole buffer to stdout,
// retrying on short writes and EINTR.  Gives up silently on other errors.
// ---------------------------------------------------------------------------
        .p2align 2
_write_all:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        mov     x19, x0
        mov     x20, x1
Lwrite_loop:
        cbz     x20, Lwrite_done
        mov     w0, #STDOUT
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.lt    Lwrite_failed
        b.eq    Lwrite_done                 // no progress possible
        add     x19, x19, x0
        sub     x20, x20, x0
        b       Lwrite_loop
Lwrite_failed:
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lwrite_loop
Lwrite_done:
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret
