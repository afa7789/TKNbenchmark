// main.s — calc driver: read stdin, evaluate each line, print results.
//
// All of standard input is slurped into one heap buffer, then split on '\n'
// with memchr.  Each line is handed to eval_line (eval.s) together with a pair
// of scratch stacks sized to the line.  Output is accumulated in a static
// buffer and flushed with write(2).

        .equ    EVAL_OK,        0
        .equ    EVAL_ERROR,     1

        .equ    STDIN,          0
        .equ    STDOUT,         1
        .equ    STDERR,         2
        .equ    EINTR,          4

        .equ    READ_CHUNK,     65536           // initial input capacity
        .equ    OUT_SIZE,       65536
        .equ    OUT_SLACK,      32              // >= longest record ("-9223372036854775808\n")
        .equ    MIN_STACK,      256             // minimum stack capacity (entries)
        .equ    ENTRY_BYTES,    9               // 8-byte value + 1-byte operator

        .zerofill __DATA, __bss, outbuf, OUT_SIZE, 4

        .section __TEXT,__cstring
msg_nomem:
        .asciz  "calc: out of memory\n"
        .equ    MSG_NOMEM_LEN, 20

        .section __TEXT,__const
        .p2align 3
str_error:
        .ascii  "error\n\0\0"               // padded to 8 bytes for a single load

        .text
        .globl  _main
        .p2align 2
// Register map:
//   x19 input cursor        x20 input end          x21 value stack
//   x22 operator stack      x23 stack capacity     x24 output buffer base
//   x25 output cursor       x26 current line end   x27 input buffer
//   x28 output flush threshold
//   [sp, #0..31]            integer formatting scratch
_main:
        stp     x29, x30, [sp, #-96]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]
        stp     x27, x28, [sp, #80]
        sub     sp, sp, #32

        bl      read_all
        mov     x27, x0
        mov     x19, x0
        add     x20, x0, x1
        mov     x21, xzr
        mov     x22, xzr
        mov     x23, xzr
        adrp    x24, outbuf@PAGE
        add     x24, x24, outbuf@PAGEOFF
        mov     x25, x24
        mov     x28, #(OUT_SIZE - OUT_SLACK)
        add     x28, x24, x28

line_loop:
        cmp     x19, x20
        b.hs    finish

        // Locate the end of this line (or of the input).
        mov     x0, x19
        mov     w1, #'\n'
        sub     x2, x20, x19
        bl      _memchr
        cmp     x0, #0
        csel    x26, x20, x0, eq

        // Ensure the scratch stacks hold (line length + 1) entries.
        sub     x0, x26, x19
        add     x0, x0, #1
        cmp     x23, x0
        b.hs    stacks_ready
        lsl     x1, x23, #1
        cmp     x1, x0
        csel    x0, x1, x0, hi
        mov     x1, #MIN_STACK
        cmp     x0, x1
        csel    x23, x0, x1, hi
        mov     x0, x21
        bl      _free
        mov     x0, #ENTRY_BYTES
        mul     x0, x23, x0
        bl      _malloc
        cbz     x0, out_of_memory
        mov     x21, x0
        add     x22, x0, x23, lsl #3

stacks_ready:
        // Keep room for one full record in the output buffer.
        cmp     x25, x28
        b.ls    1f
        mov     x0, x24
        sub     x1, x25, x24
        bl      write_all
        mov     x25, x24
1:
        mov     x0, x19
        mov     x1, x26
        mov     x2, x21
        mov     x3, x22
        bl      _eval_line
        add     x19, x26, #1
        cmp     x0, #EVAL_ERROR
        b.lo    emit_value
        b.hi    line_loop                   // blank line: no output

        adrp    x9, str_error@PAGE
        add     x9, x9, str_error@PAGEOFF
        ldr     x9, [x9]
        str     x9, [x25]
        add     x25, x25, #6
        b       line_loop

// x1 = value.  Digits are produced backwards into the scratch area, then copied.
emit_value:
        tbz     x1, #63, 1f
        mov     w9, #'-'
        strb    w9, [x25], #1
        neg     x1, x1                      // as unsigned, exact even for INT64_MIN
1:
        add     x11, sp, #32                // end of scratch
        mov     x10, x11
        mov     x12, #10
2:
        udiv    x13, x1, x12
        msub    x14, x13, x12, x1
        add     w14, w14, #'0'
        strb    w14, [x10, #-1]!
        mov     x1, x13
        cbnz    x1, 2b
3:
        ldrb    w14, [x10], #1
        strb    w14, [x25], #1
        cmp     x10, x11
        b.lo    3b
        mov     w9, #'\n'
        strb    w9, [x25], #1
        b       line_loop

finish:
        mov     x0, x24
        sub     x1, x25, x24
        bl      write_all
        mov     x0, x21
        bl      _free
        mov     x0, x27
        bl      _free
        mov     w0, #0

        add     sp, sp, #32
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #96
        ret

// Fatal allocation failure: report on stderr and exit(1).
out_of_memory:
        mov     x0, #STDERR
        adrp    x1, msg_nomem@PAGE
        add     x1, x1, msg_nomem@PAGEOFF
        mov     x2, #MSG_NOMEM_LEN
        bl      _write
        mov     w0, #1
        bl      _exit

// ---------------------------------------------------------------------------
// read_all() -> x0 = buffer, x1 = length
// Reads standard input to EOF into a growing heap buffer.
        .p2align 2
read_all:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]

        mov     x20, xzr                    // length
        mov     x21, #READ_CHUNK            // capacity
        mov     x0, x21
        bl      _malloc
        cbz     x0, out_of_memory
        mov     x19, x0

read_loop:
        cmp     x20, x21
        b.lo    1f
        lsl     x21, x21, #1
        mov     x0, x19
        mov     x1, x21
        bl      _realloc
        cbz     x0, out_of_memory
        mov     x19, x0
1:
        mov     x0, #STDIN
        add     x1, x19, x20
        sub     x2, x21, x20
        bl      _read
        cmp     x0, #0
        b.gt    read_more
        b.eq    read_done
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    read_loop
        b       read_done                   // treat other errors as EOF
read_more:
        add     x20, x20, x0
        b       read_loop

read_done:
        mov     x0, x19
        mov     x1, x20
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// ---------------------------------------------------------------------------
// write_all(x0 = buffer, x1 = length)
// Writes the whole buffer to stdout, retrying short writes and EINTR.
        .p2align 2
write_all:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        mov     x19, x0
        mov     x20, x1

write_loop:
        cbz     x20, write_done
        mov     x0, #STDOUT
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.lt    write_failed
        add     x19, x19, x0
        sub     x20, x20, x0
        b       write_loop
write_failed:
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    write_loop
write_done:
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret
