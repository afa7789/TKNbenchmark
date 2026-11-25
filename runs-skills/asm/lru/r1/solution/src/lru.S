// lru: LRU cache simulator (see SPEC.md).
//
// Design
//   * stdin is slurped into one buffer; keys and values are referenced in
//     place (pointer + length), never copied.  The buffer is terminated by a
//     '\n' sentinel and over-allocated so 8/16-byte loads past a token's end
//     stay inside the allocation.
//   * Nodes live in a flat array indexed by u32; index 0 is the sentinel of
//     the circular doubly linked recency list (next = MRU, prev = LRU).
//   * A power-of-two bucket array of u32 heads (0 = empty) with chaining
//     through node.hnext provides O(1) expected lookup.
//   * Output is accumulated in a static buffer and flushed with write(2).

#define NODE_SHIFT  5           // sizeof(node) == 32
#define N_KEY       0           // u64 key pointer
#define N_VAL       8           // u64 value pointer
#define N_PREV      16          // u32 recency list: towards MRU
#define N_NEXT      20          // u32 recency list: towards LRU
#define N_HNEXT     24          // u32 hash chain / free list link
#define N_KLEN      28          // u8
#define N_VLEN      29          // u8

#define IN_INIT     (1 << 20)
#define IN_PAD      256         // slack after the input for wide loads
#define OUT_SIZE    (1 << 20)
#define OUT_SLACK   128         // one command never emits more than this

#define EINTR       4

// Global register assignment inside _main:
//   x19 parse cursor          x20 end of input (points at sentinel '\n')
//   x21 node array            x22 bucket array
//   x23 bucket mask           x24 live key count
//   x25 capacity              x26 output cursor
//   x27 output flush limit    x28 free-list head (node index, 0 = none)

// Remove node at address \a from the recency list.
.macro LIST_UNLINK a              // clobbers x4-x6
    ldp     w4, w5, [\a, #N_PREV]
    add     x6, x21, x4, lsl #NODE_SHIFT
    str     w5, [x6, #N_NEXT]
    add     x6, x21, x5, lsl #NODE_SHIFT
    str     w4, [x6, #N_PREV]
.endm

// Insert node (index \i, address \a) at the MRU end.
.macro LIST_PUSH i, a               // clobbers x4, x5
    ldr     w4, [x21, #N_NEXT]
    stp     wzr, w4, [\a, #N_PREV]
    add     x5, x21, x4, lsl #NODE_SHIFT
    str     \i, [x5, #N_PREV]
    str     \i, [x21, #N_NEXT]
.endm

// Advance x19 past a token (bytes > ' '); \s = start, \n = length.
// x19 is left one past the terminating byte, whose value is in \c.
.macro SCAN_TOKEN s, n, c
    mov     \s, x19
1:  ldrb    \c, [x19], #1
    cmp     \c, #' '
    b.hi    1b
    sub     \n, x19, \s
    sub     \n, \n, #1
.endm

// Ensure room for one command's output.
.macro OUT_RESERVE
    cmp     x26, x27
    b.lo    1f
    bl      Lflush
1:
.endm

    .text

// ---------------------------------------------------------------------------
// Lfind: look up a key.
//   in : x0 = key pointer, x1 = key length (1..64)
//   out: x0 = node index (0 if absent), x3 = node address (if found),
//        x1 = address of the u32 link holding x0 (bucket or predecessor's
//        hnext), x2 = bucket address
//   clobbers x0-x11, flags; preserves x12-x15 and all callee-saved regs.
    .p2align 4
Lfind:
    mov     x9, x0
    mov     x10, x1
    // hash: 64-bit multiplicative mix over 8-byte chunks, seeded with length
    movz    x7, #0x7c15
    movk    x7, #0x7f4a, lsl #16
    movk    x7, #0x79b9, lsl #32
    movk    x7, #0x9e37, lsl #48
    mov     x4, x1
    mov     x2, x1
1:  cmp     x2, #8
    b.ls    2f
    ldr     x5, [x0], #8
    eor     x4, x4, x5
    mul     x4, x4, x7
    eor     x4, x4, x4, lsr #29
    sub     x2, x2, #8
    b       1b
2:  ldr     x5, [x0]
    lsl     x6, x2, #3
    neg     x6, x6
    lsl     x5, x5, x6              // keep the low r bytes (shift is mod 64)
    eor     x4, x4, x5
    mul     x4, x4, x7
    eor     x4, x4, x4, lsr #32
    mul     x4, x4, x7
    eor     x4, x4, x4, lsr #29
    and     x4, x4, x23
    add     x2, x22, x4, lsl #2
    mov     x1, x2
    // walk the chain
3:  ldr     w0, [x1]
    cbz     w0, 9f
    add     x3, x21, x0, lsl #NODE_SHIFT
    ldrb    w4, [x3, #N_KLEN]
    cmp     x4, x10
    b.ne    6f
    ldr     x5, [x3, #N_KEY]
    mov     x6, x9
    mov     x7, x10
4:  cmp     x7, #8
    b.ls    5f
    ldr     x8, [x5], #8
    ldr     x11, [x6], #8
    cmp     x8, x11
    b.ne    6f
    sub     x7, x7, #8
    b       4b
5:  ldr     x8, [x5]
    ldr     x11, [x6]
    eor     x8, x8, x11
    lsl     x7, x7, #3
    neg     x7, x7
    lsl     x8, x8, x7
    cbz     x8, 9f
6:  add     x1, x3, #N_HNEXT
    b       3b
9:  ret

// ---------------------------------------------------------------------------
// Lflush: write out [_g_out, x26) and reset x26.  Preserves x19-x28.
    .p2align 4
Lflush:
    .cfi_startproc
    stp     x20, x19, [sp, #-32]!
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    adrp    x19, _g_out@PAGE
    add     x19, x19, _g_out@PAGEOFF
    mov     x20, x19
1:  subs    x2, x26, x20
    b.ls    3f
    mov     w0, #1
    mov     x1, x20
    bl      _write
    cmp     x0, #0
    b.gt    2f
    b.eq    3f
    bl      ___error
    ldr     w0, [x0]
    cmp     w0, #EINTR
    b.eq    1b
    b       3f                      // unrecoverable: drop output
2:  add     x20, x20, x0
    b       1b
3:  mov     x26, x19
    ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp], #32
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
    .globl  _main
    .p2align 4
_main:
    .cfi_startproc
    stp     x28, x27, [sp, #-96]!
    stp     x26, x25, [sp, #16]
    stp     x24, x23, [sp, #32]
    stp     x22, x21, [sp, #48]
    stp     x20, x19, [sp, #64]
    stp     x29, x30, [sp, #80]
    add     x29, sp, #80
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

    // ---- slurp stdin: x21 = buffer, x22 = allocated size, x20 = length
    mov     x22, #IN_INIT
    mov     x0, x22
    bl      _malloc
    cbz     x0, Lfail
    mov     x21, x0
    mov     x20, #0
Lread:
    sub     x2, x22, x20
    sub     x2, x2, #IN_PAD
    cmp     x2, #(1 << 16)
    b.hs    1f
    lsl     x22, x22, #1
    mov     x0, x21
    mov     x1, x22
    bl      _realloc
    cbz     x0, Lfail
    mov     x21, x0
    b       Lread
1:  mov     w0, #0
    add     x1, x21, x20
    bl      _read
    cmp     x0, #0
    b.gt    2f
    b.eq    Lread_done
    bl      ___error
    ldr     w0, [x0]
    cmp     w0, #EINTR
    b.eq    Lread
    b       Lread_done
2:  add     x20, x20, x0
    b       Lread
Lread_done:
    mov     x19, x21
    add     x20, x21, x20
    mov     w0, #'\n'
    strb    w0, [x20]               // sentinel

    // ---- capacity (line 1)
    mov     x25, #0
    mov     x1, #10
1:  ldrb    w0, [x19]
    sub     w0, w0, #'0'
    cmp     w0, #9
    b.hi    2f
    madd    x25, x25, x1, x0
    add     x19, x19, #1
    b       1b
2:  cmp     x25, #1
    csinc   x25, x25, xzr, hs       // clamp to >= 1
3:  ldrb    w0, [x19], #1           // skip rest of line 1
    cmp     w0, #'\n'
    b.ne    3b

    // ---- nodes: (C + 1) * 32 bytes; free list 1 -> 2 -> ... -> C -> 0
    add     x0, x25, #1
    lsl     x0, x0, #NODE_SHIFT
    bl      _malloc
    cbz     x0, Lfail
    mov     x21, x0
    stp     wzr, wzr, [x21, #N_PREV]
    add     x3, x21, #(1 << NODE_SHIFT)
    mov     x1, #1
1:  add     x2, x1, #1
    cmp     x1, x25
    csel    x2, x2, xzr, lo
    str     w2, [x3, #N_HNEXT]
    add     x3, x3, #(1 << NODE_SHIFT)
    add     x1, x1, #1
    cmp     x1, x25
    b.ls    1b
    mov     x28, #1

    // ---- buckets: smallest power of two >= 2C (at least 16)
    mov     x23, #16
    lsl     x1, x25, #1
1:  cmp     x23, x1
    b.hs    2f
    lsl     x23, x23, #1
    b       1b
2:  mov     x0, x23
    mov     x1, #4
    bl      _calloc
    cbz     x0, Lfail
    mov     x22, x0
    sub     x23, x23, #1

    mov     x24, #0
    adrp    x26, _g_out@PAGE
    add     x26, x26, _g_out@PAGEOFF
    mov     x27, #(OUT_SIZE - OUT_SLACK)
    add     x27, x26, x27

    // command words, little-endian
    movz    w13, #0x4553            // "SET "
    movk    w13, #0x2054, lsl #16
    movz    w14, #0x4547            // "GET "
    movk    w14, #0x2054, lsl #16
    movz    w15, #0x4544            // "DEL "
    movk    w15, #0x204c, lsl #16
    movz    w12, #0x4953            // "SIZE"
    movk    w12, #0x455a, lsl #16
    stp     w13, w14, [sp, #-16]!
    stp     w15, w12, [sp, #8]

    // ---- command loop
Lloop:
    cmp     x19, x20
    b.hs    Ldone
    OUT_RESERVE
    ldr     w0, [x19]
    ldp     w13, w14, [sp]
    ldp     w15, w12, [sp, #8]
    cmp     w0, w14
    b.eq    Lget
    cmp     w0, w13
    b.eq    Lset
    cmp     w0, w15
    b.eq    Ldel
    cmp     w0, w12
    b.eq    Lsize
    // unrecognised or blank line: fall through to skip it
Lskip_line:
    ldrb    w0, [x19], #1
    cmp     w0, #'\n'
    b.ne    Lskip_line
    b       Lloop

// Finish a line whose last token ended at byte w0.
.macro END_LINE c
    cmp     \c, #'\n'
    b.ne    Lskip_line
    b       Lloop
.endm

Lget:
    add     x19, x19, #4
    SCAN_TOKEN x13, x14, w12
    mov     x0, x13
    mov     x1, x14
    bl      Lfind
    cbz     w0, Lget_miss
    ldr     w4, [x21, #N_NEXT]
    cmp     w4, w0
    b.eq    1f
    LIST_UNLINK x3
    LIST_PUSH w0, x3
1:  ldr     x1, [x3, #N_VAL]
    ldrb    w2, [x3, #N_VLEN]
    ldp     q0, q1, [x1]
    ldp     q2, q3, [x1, #32]
    stp     q0, q1, [x26]
    stp     q2, q3, [x26, #32]
    add     x26, x26, x2
    mov     w4, #'\n'
    strb    w4, [x26], #1
    END_LINE w12
Lget_miss:
    movz    w4, #0x554e             // "NULL"
    movk    w4, #0x4c4c, lsl #16
    str     w4, [x26]
    mov     w4, #'\n'
    strb    w4, [x26, #4]
    add     x26, x26, #5
    END_LINE w12

Lset:
    add     x19, x19, #4
    SCAN_TOKEN x13, x14, w12
    mov     x0, x13
    mov     x1, x14
    bl      Lfind
    cbz     w0, Lset_new
    ldr     w4, [x21, #N_NEXT]
    cmp     w4, w0
    b.eq    Lset_value
    LIST_UNLINK x3
    LIST_PUSH w0, x3
    b       Lset_value
Lset_new:
    mov     x12, x2                 // bucket for the new key
    cmp     x24, x25
    b.lo    Lset_alloc
    // full: evict the LRU node and reuse it
    ldr     w0, [x21, #N_PREV]
    add     x3, x21, x0, lsl #NODE_SHIFT
    LIST_UNLINK x3
    ldr     x0, [x3, #N_KEY]
    ldrb    w1, [x3, #N_KLEN]
    bl      Lfind                   // x1 = link to the victim, x3 = victim
    ldr     w4, [x3, #N_HNEXT]
    str     w4, [x1]
    b       Lset_link
Lset_alloc:
    mov     x0, x28
    add     x3, x21, x0, lsl #NODE_SHIFT
    ldr     w28, [x3, #N_HNEXT]
    add     x24, x24, #1
Lset_link:
    str     x13, [x3, #N_KEY]
    strb    w14, [x3, #N_KLEN]
    ldr     w4, [x12]
    str     w4, [x3, #N_HNEXT]
    str     w0, [x12]
    LIST_PUSH w0, x3
Lset_value:
    SCAN_TOKEN x15, x14, w12
    str     x15, [x3, #N_VAL]
    strb    w14, [x3, #N_VLEN]
    END_LINE w12

Ldel:
    add     x19, x19, #4
    SCAN_TOKEN x13, x14, w12
    mov     x0, x13
    mov     x1, x14
    bl      Lfind
    mov     w4, #'0'
    cbz     w0, 1f
    ldr     w4, [x3, #N_HNEXT]      // unlink from hash chain
    str     w4, [x1]
    LIST_UNLINK x3
    str     w28, [x3, #N_HNEXT]     // push on the free list
    mov     x28, x0
    sub     x24, x24, #1
    mov     w4, #'1'
1:  mov     w5, #'\n'
    strb    w4, [x26]
    strb    w5, [x26, #1]
    add     x26, x26, #2
    END_LINE w12

Lsize:
    add     x19, x19, #4
    // number of digits of x24
    mov     x1, #1
    mov     x2, #10
    mov     x3, #10
1:  cmp     x24, x2
    b.lo    2f
    add     x1, x1, #1
    mul     x2, x2, x3
    b       1b
2:  add     x26, x26, x1
    mov     x4, x26
    mov     x0, x24
3:  udiv    x5, x0, x3
    msub    x6, x5, x3, x0
    add     w6, w6, #'0'
    strb    w6, [x4, #-1]!
    mov     x0, x5
    cbnz    x0, 3b
    mov     w6, #'\n'
    strb    w6, [x26], #1
    ldrb    w12, [x19], #1
    END_LINE w12

Ldone:
    add     sp, sp, #16
    bl      Lflush
    mov     w0, #0
    ldp     x29, x30, [sp, #80]
    ldp     x20, x19, [sp, #64]
    ldp     x22, x21, [sp, #48]
    ldp     x24, x23, [sp, #32]
    ldp     x26, x25, [sp, #16]
    ldp     x28, x27, [sp], #96
    ret
Lfail:
    mov     w0, #1
    bl      _exit
    .cfi_endproc

    .zerofill __DATA,__bss,_g_out,OUT_SIZE,6
.subsections_via_symbols
