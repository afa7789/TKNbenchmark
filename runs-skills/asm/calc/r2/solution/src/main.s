// main.s — calc driver: read stdin, evaluate each line, print results.

        .equ STDIN,       0
        .equ STDOUT,      1
        .equ EINTR,       4
        .equ READ_CHUNK0, 0x100000              // initial input buffer (1 MiB)
        .equ OUT_CAP,     0x10000               // output buffer size
        .equ OUT_SLACK,   32                    // >= longest single result line

        .text

// int main(void)
//   x19 input buffer   x20 input length / end   x21 line cursor
//   x22 input capacity, then eval stack block  x23 eval stack capacity (entries)
//   x24 end of current line   x25 output buffer   x26 output length
        .globl _main
        .p2align 2
_main:
        .cfi_startproc
        sub     sp, sp, #80
        stp     x26, x25, [sp, #0]
        stp     x24, x23, [sp, #16]
        stp     x22, x21, [sp, #32]
        stp     x20, x19, [sp, #48]
        stp     x29, x30, [sp, #64]
        add     x29, sp, #64
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

        // ---- slurp all of stdin ----
        mov     x22, #READ_CHUNK0
        mov     x0, x22
        bl      _malloc
        cbz     x0, Lfail
        mov     x19, x0
        mov     x20, #0
Lread:
        subs    x2, x22, x20
        b.ne    1f
        lsl     x22, x22, #1                    // full: double the buffer
        mov     x0, x19
        mov     x1, x22
        bl      _realloc
        cbz     x0, Lfail
        mov     x19, x0
        sub     x2, x22, x20
1:      mov     w0, #STDIN
        add     x1, x19, x20
        bl      _read
        cmp     x0, #0
        b.gt    2f
        b.eq    Lread_done
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    Lread
        b       Lread_done                      // treat other read errors as EOF
2:      add     x20, x20, x0
        b       Lread
Lread_done:
        add     x20, x19, x20                   // x20 = end of input
        mov     x21, x19
        mov     x22, #0                         // eval stack block (none yet)
        mov     x23, #0
        adrp    x25, _g_outbuf@PAGE
        add     x25, x25, _g_outbuf@PAGEOFF
        mov     x26, #0

        // ---- one expression per line ----
Lline:
        cmp     x21, x20
        b.hs    Ldone
        mov     x0, x21
        mov     w1, #'\n'
        sub     x2, x20, x21
        bl      _memchr
        cmp     x0, #0
        csel    x24, x20, x0, eq                // last line may lack '\n'

        sub     x8, x24, x21                    // stacks need one slot per byte
        cmp     x8, x23
        b.ls    Lhave_stack
        lsl     x9, x23, #1
        cmp     x8, x9
        csel    x23, x8, x9, hi                 // cap = max(len, 2 * cap)
        mov     x0, x22
        bl      _free
        add     x0, x23, x23, lsl #3            // cap * (8 value bytes + 1 op byte)
        bl      _malloc
        cbz     x0, Lfail
        mov     x22, x0
Lhave_stack:
        mov     x9, #(OUT_CAP - OUT_SLACK)
        cmp     x26, x9
        b.ls    1f
        mov     x0, x25
        mov     x1, x26
        bl      _flush_out
        mov     x26, #0
1:      mov     x0, x21
        mov     x1, x24
        mov     x2, x22
        add     x3, x22, x23, lsl #3
        bl      _eval_line
        cbz     w0, Lprint_value
        cmp     w0, #1
        b.ne    Lnext_line                      // blank line: no output
        adrp    x8, Lerror_text@PAGE
        ldr     x8, [x8, Lerror_text@PAGEOFF]
        str     x8, [x25, x26]                  // 8-byte store, 6 bytes kept
        add     x26, x26, #6
        b       Lnext_line
Lprint_value:
        add     x0, x25, x26
        bl      _fmt_i64
        add     x26, x26, x0
        mov     w8, #'\n'
        strb    w8, [x25, x26]
        add     x26, x26, #1
Lnext_line:
        add     x21, x24, #1
        b       Lline

Ldone:
        mov     x0, x25
        mov     x1, x26
        bl      _flush_out
        mov     x0, x22
        bl      _free
        mov     x0, x19
        bl      _free
        mov     w0, #0
        b       Lreturn
Lfail:
        mov     w0, #1
Lreturn:
        ldp     x29, x30, [sp, #64]
        ldp     x20, x19, [sp, #48]
        ldp     x22, x21, [sp, #32]
        ldp     x24, x23, [sp, #16]
        ldp     x26, x25, [sp, #0]
        add     sp, sp, #80
        ret
        .cfi_endproc

// void flush_out(const char *buf, size_t len)
//   Writes the whole buffer to stdout, retrying short writes and EINTR.
        .p2align 2
_flush_out:
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
1:      cbz     x20, 3f
        mov     w0, #STDOUT
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.lt    2f
        add     x19, x19, x0
        sub     x20, x20, x0
        b       1b
2:      bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    1b
3:      ldp     x29, x30, [sp, #16]
        ldp     x20, x19, [sp], #32
        ret
        .cfi_endproc

        .section __TEXT,__const
        .p2align 3
Lerror_text:
        .ascii  "error\n\0\0"

        .zerofill __DATA,__bss,_g_outbuf,OUT_CAP,4

.subsections_via_symbols
