// calc — 64-bit signed integer expression evaluator (AArch64, macOS).
//
// Reads all of stdin, evaluates each '\n'-terminated line and prints its
// value or "error".  Parsing is an iterative operator-precedence (shunting
// yard) parser driven by a two-state machine, so arbitrarily deep nesting
// of parentheses or unary minus never touches the machine stack.

        .equ    OUT_CAP,   65536          // output buffer size
        .equ    OUT_SLACK, 32             // room needed for one result line
        .equ    IN_INIT,   65536          // initial input buffer size

        // Operator codes stored on the operator stack.
        .equ    OP_LPAREN, 0
        .equ    OP_ADD,    1
        .equ    OP_SUB,    2
        .equ    OP_MUL,    3
        .equ    OP_DIV,    4
        .equ    OP_REM,    5
        .equ    OP_NEG,    6

        // eval_line status codes.
        .equ    ST_OK,     0
        .equ    ST_ERROR,  1
        .equ    ST_BLANK,  2

        .text

// ---------------------------------------------------------------------------
// int main(void)
//
// x19 input buffer      x20 input capacity, then output buffer base
// x21 input length      x22 current line start
// x23 input end         x24 current line end
// x25 stack capacity    x26 value stack (int64[])
// x27 operator stack    x28 output length
// [sp, #0..31]          scratch for number formatting
// ---------------------------------------------------------------------------
        .globl  _main
        .p2align 2
_main:
        .cfi_startproc
        sub     sp, sp, #128
        stp     x28, x27, [sp, #32]
        stp     x26, x25, [sp, #48]
        stp     x24, x23, [sp, #64]
        stp     x22, x21, [sp, #80]
        stp     x20, x19, [sp, #96]
        stp     x29, x30, [sp, #112]
        add     x29, sp, #112
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

        // ---- slurp stdin ----------------------------------------------------
        mov     x20, #IN_INIT
        mov     x0, x20
        bl      _malloc
        cbz     x0, Lmain_oom
        mov     x19, x0
        mov     x21, #0
Lread:
        cmp     x21, x20
        b.lo    1f
        lsl     x20, x20, #1
        mov     x0, x19
        mov     x1, x20
        bl      _realloc
        cbz     x0, Lmain_oom
        mov     x19, x0
1:      mov     w0, #0
        add     x1, x19, x21
        sub     x2, x20, x21
        bl      _read
        cmp     x0, #0
        b.eq    Lread_done
        b.lt    Lread_err
        add     x21, x21, x0
        b       Lread
Lread_err:
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #4                      // EINTR: retry
        b.eq    Lread
Lread_done:
        adrp    x20, _outbuf@PAGE
        add     x20, x20, _outbuf@PAGEOFF
        mov     x28, #0
        mov     x25, #0
        mov     x26, #0
        mov     x27, #0
        mov     x22, x19
        add     x23, x19, x21

        // ---- per-line loop --------------------------------------------------
Lline:
        cmp     x22, x23
        b.hs    Lfinish
        mov     x0, x22
        mov     w1, #'\n'
        sub     x2, x23, x22
        bl      _memchr
        cmp     x0, #0
        csel    x24, x0, x23, ne            // unterminated last line ends at EOF

        // Ensure the stacks can hold one entry per byte of the line.
        sub     x9, x24, x22
        cmp     x9, x25
        b.lo    Lstacks_ok
        add     x9, x9, #1
        lsl     x10, x25, #1
        cmp     x9, x10
        csel    x25, x9, x10, hi
        mov     x0, x26
        bl      _free
        mov     x0, x27
        bl      _free
        lsl     x0, x25, #3
        bl      _malloc
        cbz     x0, Lmain_oom
        mov     x26, x0
        mov     x0, x25
        bl      _malloc
        cbz     x0, Lmain_oom
        mov     x27, x0
Lstacks_ok:
        mov     x0, x22
        mov     x1, x24
        mov     x2, x26
        mov     x3, x27
        bl      _eval_line
        add     x22, x24, #1
        cmp     w0, #ST_BLANK
        b.eq    Lline

        // Make room for one result line.
        mov     x9, #(OUT_CAP - OUT_SLACK)
        cmp     x28, x9
        b.ls    1f
        stp     w0, wzr, [sp]
        str     x1, [sp, #8]
        mov     x0, x20
        mov     x1, x28
        bl      _out_write
        mov     x28, #0
        ldr     w0, [sp]
        ldr     x1, [sp, #8]
1:      add     x9, x20, x28
        cbnz    w0, Lemit_error

        // Format x1 as decimal, backwards into the scratch area.
        cmp     x1, #0
        cneg    x2, x1, lt                  // |x1| as unsigned (INT64_MIN ok)
        add     x3, sp, #32
        mov     w4, #'\n'
        strb    w4, [x3, #-1]!
        mov     x5, #10
2:      udiv    x6, x2, x5
        msub    x7, x6, x5, x2
        add     w7, w7, #'0'
        strb    w7, [x3, #-1]!
        mov     x2, x6
        cbnz    x2, 2b
        tbz     x1, #63, 3f
        mov     w4, #'-'
        strb    w4, [x3, #-1]!
3:      add     x4, sp, #32
4:      ldrb    w5, [x3], #1
        strb    w5, [x9], #1
        cmp     x3, x4
        b.lo    4b
        sub     x28, x9, x20
        b       Lline

Lemit_error:
        movz    w4, #0x7265                 // "erro"
        movk    w4, #0x6f72, lsl #16
        mov     w5, #0x0a72                 // "r\n"
        str     w4, [x9]
        strh    w5, [x9, #4]
        add     x28, x28, #6
        b       Lline

Lfinish:
        mov     x0, x20
        mov     x1, x28
        bl      _out_write
        mov     x0, x26
        bl      _free
        mov     x0, x27
        bl      _free
        mov     x0, x19
        bl      _free
        mov     w0, #0
        b       Lmain_ret
Lmain_oom:
        mov     w0, #1
Lmain_ret:
        ldp     x29, x30, [sp, #112]
        ldp     x20, x19, [sp, #96]
        ldp     x22, x21, [sp, #80]
        ldp     x24, x23, [sp, #64]
        ldp     x26, x25, [sp, #48]
        ldp     x28, x27, [sp, #32]
        add     sp, sp, #128
        ret
        .cfi_endproc

// ---------------------------------------------------------------------------
// void out_write(const char *buf, size_t len)
// Writes the whole buffer to stdout, retrying on short writes and EINTR.
// ---------------------------------------------------------------------------
        .private_extern _out_write
        .p2align 2
_out_write:
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
Lw_loop:
        cbz     x20, Lw_done
        mov     w0, #1
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.lt    Lw_err
        add     x19, x19, x0
        sub     x20, x20, x0
        b       Lw_loop
Lw_err:
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #4                      // EINTR: retry, otherwise give up
        b.eq    Lw_loop
Lw_done:
        ldp     x29, x30, [sp, #16]
        ldp     x20, x19, [sp], #32
        ret
        .cfi_endproc

// ---------------------------------------------------------------------------
// int eval_line(const char *p, const char *end, int64_t *vstack, uint8_t *ostack)
// Returns w0 = ST_OK (value in x1), ST_ERROR or ST_BLANK.
//
// x9  cursor            x10 line end
// x11 value stack top   x12 INT64_MAX / 10
// x13 op stack top      x14 op stack base
// w6/w7 precedence / opcode handed to Lreduce (which clobbers x0-x5, x8)
// ---------------------------------------------------------------------------
        .private_extern _eval_line
        .p2align 2
_eval_line:
        .cfi_startproc
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        .cfi_def_cfa w29, 16
        .cfi_offset w30, -8
        .cfi_offset w29, -16
        mov     x9, x0
        mov     x10, x1
        mov     x11, x2
        mov     x13, x3
        mov     x14, x3
        movz    x12, #0xcccc                // 922337203685477580
        movk    x12, #0xcccc, lsl #16
        movk    x12, #0xcccc, lsl #32
        movk    x12, #0x0ccc, lsl #48

        // A line holding only spaces/tabs is blank.
Lblank:
        cmp     x9, x10
        b.hs    Lret_blank
        ldrb    w4, [x9]
        cmp     w4, #' '
        ccmp    w4, #'\t', #4, ne
        b.ne    Loperand
        add     x9, x9, #1
        b       Lblank

        // State 1: expecting an operand ('-', '(' or a number).
Loperand:
        cmp     x9, x10
        b.hs    Lfail
        ldrb    w4, [x9], #1
        cmp     w4, #' '
        ccmp    w4, #'\t', #4, ne
        b.eq    Loperand
        cmp     w4, #'-'
        b.ne    1f
        mov     w5, #OP_NEG
        strb    w5, [x13], #1
        b       Loperand
1:      cmp     w4, #'('
        b.ne    2f
        mov     w5, #OP_LPAREN
        strb    w5, [x13], #1
        b       Loperand
2:      sub     w5, w4, #'0'
        cmp     w5, #9
        b.hi    Lfail
Ldigit:
        cmp     x9, x10
        b.hs    Lnum_done
        ldrb    w4, [x9]
        sub     w4, w4, #'0'
        cmp     w4, #9
        b.hi    Lnum_done
        add     x9, x9, #1
        cmp     x5, x12
        b.hi    Lfail                       // v*10 would exceed INT64_MAX
        add     x5, x5, x5, lsl #2
        adds    x5, x4, x5, lsl #1          // v = v*10 + d
        b.vs    Lfail
        b       Ldigit
Lnum_done:
        str     x5, [x11], #8

        // State 2: expecting a binary operator, ')' or end of line.
Loperator:
        cmp     x9, x10
        b.hs    Lend
        ldrb    w4, [x9], #1
        cmp     w4, #' '
        ccmp    w4, #'\t', #4, ne
        b.eq    Loperator
        cmp     w4, #')'
        b.eq    Lrparen
        mov     w6, #1
        mov     w7, #OP_ADD
        cmp     w4, #'+'
        b.eq    Lbinop
        mov     w7, #OP_SUB
        cmp     w4, #'-'
        b.eq    Lbinop
        mov     w6, #2
        mov     w7, #OP_MUL
        cmp     w4, #'*'
        b.eq    Lbinop
        mov     w7, #OP_DIV
        cmp     w4, #'/'
        b.eq    Lbinop
        mov     w7, #OP_REM
        cmp     w4, #'%'
        b.ne    Lfail
Lbinop:
        bl      Lreduce
        cbnz    w0, Lfail
        strb    w7, [x13], #1
        b       Loperand

Lrparen:
        mov     w6, #1
        bl      Lreduce
        cbnz    w0, Lfail
        cmp     x13, x14
        b.ls    Lfail                       // no matching '('
        ldrb    w4, [x13, #-1]!
        cbnz    w4, Lfail
        b       Loperator

Lend:
        mov     w6, #1
        bl      Lreduce
        cbnz    w0, Lfail
        cmp     x13, x14
        b.ne    Lfail                       // unclosed '('
        ldr     x1, [x11, #-8]
        mov     w0, #ST_OK
        b       Lret
Lret_blank:
        mov     w0, #ST_BLANK
        b       Lret
Lfail:
        mov     w0, #ST_ERROR
Lret:
        ldp     x29, x30, [sp], #16
        ret

// Lreduce: apply stacked operators while their precedence is >= w6.
// Returns w0 = 0, or 1 on division by zero / overflow.
Lreduce:
        adrp    x8, Lprec@PAGE
        add     x8, x8, Lprec@PAGEOFF
Lr_loop:
        cmp     x13, x14
        b.ls    Lr_ok
        ldrb    w0, [x13, #-1]
        ldrb    w1, [x8, w0, uxtw]
        cmp     w1, w6
        b.lo    Lr_ok
        sub     x13, x13, #1
        cmp     w0, #OP_NEG
        b.eq    Lr_neg
        ldp     x2, x3, [x11, #-16]!        // x2 = lhs, x3 = rhs
        cmp     w0, #OP_SUB
        b.lo    Lr_add
        b.eq    Lr_sub
        cmp     w0, #OP_DIV
        b.lo    Lr_mul
        b.eq    Lr_div
        // remainder: sign follows the dividend; x % -1 == 0 (no overflow)
        cbz     x3, Lr_err
        cmn     x3, #1
        b.eq    1f
        sdiv    x4, x2, x3
        msub    x2, x4, x3, x2
        b       Lr_push
1:      mov     x2, #0
        b       Lr_push
Lr_div:
        cbz     x3, Lr_err
        cmn     x3, #1
        b.ne    1f
        negs    x2, x2                      // INT64_MIN / -1 overflows
        b.vs    Lr_err
        b       Lr_push
1:      sdiv    x2, x2, x3
        b       Lr_push
Lr_mul:
        mul     x4, x2, x3
        smulh   x5, x2, x3
        cmp     x5, x4, asr #63
        b.ne    Lr_err
        mov     x2, x4
        b       Lr_push
Lr_sub:
        subs    x2, x2, x3
        b.vs    Lr_err
        b       Lr_push
Lr_add:
        adds    x2, x2, x3
        b.vs    Lr_err
Lr_push:
        str     x2, [x11], #8
        b       Lr_loop
Lr_neg:
        ldr     x2, [x11, #-8]
        negs    x2, x2
        b.vs    Lr_err
        str     x2, [x11, #-8]
        b       Lr_loop
Lr_ok:
        mov     w0, #0
        ret
Lr_err:
        mov     w0, #1
        ret
        .cfi_endproc

        .const
// Precedence indexed by opcode: '(' + - * / % neg
Lprec:  .byte   0, 1, 1, 2, 2, 2, 3

        .zerofill __DATA,__bss,_outbuf,OUT_CAP,4

.subsections_via_symbols
