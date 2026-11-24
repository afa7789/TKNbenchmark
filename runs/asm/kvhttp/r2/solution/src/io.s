// kvhttp — small I/O and byte-string helpers.

        .include "defs.inc"

        .section __TEXT,__text,regular,pure_instructions

// read_some(fd w0, buf x1, n x2) -> x0 = bytes read (0 on EOF, -1 on error).
// Retries on EINTR.
        .globl _read_some
        .p2align 2
_read_some:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        str     x21, [sp, #32]
        mov     w19, w0
        mov     x20, x1
        mov     x21, x2
1:      mov     w0, w19
        mov     x1, x20
        mov     x2, x21
        bl      _read
        tbz     x0, #63, 2f
        bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    1b
        mov     x0, #-1
2:      ldr     x21, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// write_all(fd w0, buf x1, n x2) -> x0 = 0 on success, -1 on error.
        .globl _write_all
        .p2align 2
_write_all:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        str     x21, [sp, #32]
        mov     w19, w0
        mov     x20, x1
        mov     x21, x2
1:      cbz     x21, 3f
        mov     w0, w19
        mov     x1, x20
        mov     x2, x21
        bl      _write
        tbnz    x0, #63, 2f
        add     x20, x20, x0
        sub     x21, x21, x0
        b       1b
2:      bl      ___error
        ldr     w8, [x0]
        cmp     w8, #EINTR
        b.eq    1b
        mov     x0, #-1
        b       4f
3:      mov     x0, #0
4:      ldr     x21, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// append(dst x0, src x1, n x2) -> x0 = dst + n.
        .globl _append
        .p2align 2
_append:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x19, [sp, #16]
        add     x19, x0, x2
        bl      _memcpy
        mov     x0, x19
        ldr     x19, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// append_uint(dst x0, v x1) -> x0 = dst + number of decimal digits written.
        .globl _append_uint
        .p2align 2
_append_uint:
        sub     sp, sp, #32
        add     x9, sp, #32                     // end of scratch
        mov     x10, x9
        mov     x11, #10
1:      udiv    x12, x1, x11
        msub    x13, x12, x11, x1
        add     w13, w13, #'0'
        strb    w13, [x10, #-1]!
        mov     x1, x12
        cbnz    x1, 1b
2:      ldrb    w13, [x10], #1
        strb    w13, [x0], #1
        cmp     x10, x9
        b.lo    2b
        add     sp, sp, #32
        ret

// find_byte(buf x0, start x1, end x2, byte w3) -> x0 = index or -1. Leaf.
        .globl _find_byte
        .p2align 2
_find_byte:
1:      cmp     x1, x2
        b.hs    2f
        ldrb    w4, [x0, x1]
        cmp     w4, w3
        b.eq    3f
        add     x1, x1, #1
        b       1b
2:      mov     x0, #-1
        ret
3:      mov     x0, x1
        ret

// find_hdr_end(buf x0, start x1, len x2) -> x0 = index just past the first
// "\r\n\r\n" at or after start, or -1. Leaf.
        .globl _find_hdr_end
        .p2align 2
_find_hdr_end:
        mov     w5, #0x0a0d
        movk    w5, #0x0a0d, lsl #16            // "\r\n\r\n" little-endian
        sub     x2, x2, #4                      // last valid start
1:      cmp     x1, x2
        b.gt    2f
        ldr     w4, [x0, x1]
        cmp     w4, w5
        b.eq    3f
        add     x1, x1, #1
        b       1b
2:      mov     x0, #-1
        ret
3:      add     x0, x1, #4
        ret

// bytes_eq(a x0, alen x1, b x2, blen x3) -> w0 = 1 if equal else 0. Leaf.
        .globl _bytes_eq
        .p2align 2
_bytes_eq:
        cmp     x1, x3
        b.ne    2f
1:      cbz     x1, 3f
        ldrb    w4, [x0], #1
        ldrb    w5, [x2], #1
        cmp     w4, w5
        b.ne    2f
        sub     x1, x1, #1
        b       1b
2:      mov     w0, #0
        ret
3:      mov     w0, #1
        ret
