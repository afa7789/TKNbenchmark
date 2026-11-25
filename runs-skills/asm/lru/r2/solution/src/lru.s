// lru — LRU cache simulator (AArch64, macOS).
//
// The whole of stdin is slurped into one buffer; keys and values are never
// copied, nodes just point into that buffer.  Data structures:
//
//   nodes  : array of 32-byte records, indexed by u32.  Index 0 is the list
//            sentinel (next = MRU, prev = LRU).  Free nodes are chained
//            through `hnext`.
//   table  : power-of-two array of u32 bucket heads (0 = empty), separate
//            chaining through `hnext`, hashed with CRC32C.
//
// Register map inside _main (callee-saved, so they survive libc calls):
//   x19 input cursor        x20 input end (a '\n' sentinel lives there)
//   x21 node array          x22 hash table          x23 table mask
//   x24 output cursor       x25 output flush mark   x26 key count
//   x27 capacity            x28 free-list head (node index)
//
// Internal helper Lfind is a leaf: inputs x10 = key ptr, x11 = key len;
// it clobbers x0-x8 only.

// Node layout
        .equ N_KEY,   0         // u64 pointer to key bytes
        .equ N_VAL,   8         // u64 pointer to value bytes
        .equ N_PREV,  16        // u32 LRU list links
        .equ N_NEXT,  20
        .equ N_HNEXT, 24        // u32 hash chain / free list link
        .equ N_KLEN,  28        // u8
        .equ N_VLEN,  29        // u8
        .equ N_SHIFT, 5         // sizeof(node) == 32

        .equ IN_INIT,  (1 << 20)
        .equ IN_SLACK, 64       // readable bytes kept past the input end
        .equ OUT_SIZE, (1 << 16)
        .equ OUT_SLACK, 256     // room for one record past the flush mark
        .equ EINTR, 4

// \dst = address of node \idx (a zero-extended x register)
.macro NODE dst, idx
        add     \dst, x21, \idx, lsl #N_SHIFT
.endm

// Unlink node (address \n) from the LRU list.  Clobbers x5-x7.
.macro LIST_UNLINK n
        ldp     w5, w6, [\n, #N_PREV]
        NODE    x7, x5
        str     w6, [x7, #N_NEXT]
        NODE    x7, x6
        str     w5, [x7, #N_PREV]
.endm

// Insert node (index \i, address \n) right after the sentinel.  Clobbers x5, x7.
.macro LIST_PUSH_FRONT i, n
        ldr     w5, [x21, #N_NEXT]
        stp     wzr, w5, [\n, #N_PREV]
        NODE    x7, x5
        str     \i, [x7, #N_PREV]
        str     \i, [x21, #N_NEXT]
.endm

// Advance x19 to the first byte <= ' ' (space, newline, or the sentinel).
.macro SCAN_TOKEN
1:      ldrb    w9, [x19], #1
        cmp     w9, #' '
        b.hi    1b
        sub     x19, x19, #1
.endm

// Given w0 = index, x1 = slot pointing at it, x4 = its address: remove the
// node from the hash chain and the list, and return it to the free list.
.macro REMOVE_NODE
        ldr     w5, [x4, #N_HNEXT]
        str     w5, [x1]
        LIST_UNLINK x4
        str     w28, [x4, #N_HNEXT]
        mov     w28, w0
        sub     x26, x26, #1
.endm

        .text
        .globl  _main
        .p2align 2
_main:
        .cfi_startproc
        sub     sp, sp, #96
        stp     x28, x27, [sp, #0]
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

// ---- slurp stdin: x19 = buffer, x20 = length, x21 = allocation size ----
        mov     x21, #IN_INIT
        mov     x0, x21
        bl      _malloc
        cbz     x0, Lfail
        mov     x19, x0
        mov     x20, #0
Lread:
        sub     x2, x21, x20
        sub     x2, x2, #IN_SLACK
        cmp     x2, #4096
        b.hs    Lread_call
        lsl     x21, x21, #1
        mov     x0, x19
        mov     x1, x21
        bl      _realloc
        cbz     x0, Lfail
        mov     x19, x0
        b       Lread
Lread_call:
        mov     w0, #0
        add     x1, x19, x20
        bl      _read
        cmp     x0, #0
        b.eq    Lread_done
        b.lt    Lread_err
        add     x20, x20, x0
        b       Lread
Lread_err:
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lread
        b       Lfail
Lread_done:
        add     x20, x19, x20           // x20 = end
        mov     w9, #'\n'
        strb    w9, [x20]               // sentinel terminates any scan

// ---- line 1: capacity ----
        mov     x27, #0
Lcap_loop:
        ldrb    w9, [x19]
        sub     w9, w9, #'0'
        cmp     w9, #9
        b.hi    Lcap_done
        add     x19, x19, #1
        mov     x10, #10
        madd    x27, x27, x10, x9
        b       Lcap_loop
Lcap_done:
        cmp     x27, #1
        csinc   x27, x27, xzr, hs       // clamp to >= 1
Lcap_eol:
        ldrb    w9, [x19], #1
        cmp     w9, #'\n'
        b.ne    Lcap_eol

// ---- hash table: power of two >= 2*C, at least 16 buckets ----
        lsl     x0, x27, #1
        sub     x0, x0, #1
        clz     x0, x0
        mov     x1, #1
        neg     x0, x0
        lsl     x0, x1, x0              // 1 << (64 - clz(2C-1))
        mov     x1, #16
        cmp     x0, x1
        csel    x0, x0, x1, hs
        sub     x23, x0, #1
        mov     x1, #4
        bl      _calloc
        cbz     x0, Lfail
        mov     x22, x0

// ---- node pool: sentinel + C + 1 nodes, all on the free list ----
        add     x0, x27, #2
        mov     x1, #(1 << N_SHIFT)
        bl      _calloc
        cbz     x0, Lfail
        mov     x21, x0
        add     x10, x27, #1            // last node index
        mov     x9, #1
Lfree_init:
        NODE    x4, x9
        add     w9, w9, #1
        str     w9, [x4, #N_HNEXT]
        cmp     x9, x10
        b.ls    Lfree_init
        NODE    x4, x10
        str     wzr, [x4, #N_HNEXT]
        mov     w28, #1
        mov     x26, #0

        adrp    x24, _outbuf@PAGE
        add     x24, x24, _outbuf@PAGEOFF
        add     x25, x24, #OUT_SIZE

// ---- command loop ----
Lloop:
        cmp     x19, x20
        b.hs    Lfinish
        ldrb    w9, [x19]
        cmp     w9, #'G'
        b.eq    Lget
        cmp     w9, #'S'
        b.eq    Ls
        cmp     w9, #'D'
        b.eq    Ldel
        b       Leol                    // blank or unknown line

Ls:     ldrb    w9, [x19, #1]
        cmp     w9, #'I'
        b.eq    Lsize

// SET <key> <value>
        add     x19, x19, #4
        mov     x10, x19
        SCAN_TOKEN
        sub     x11, x19, x10
        add     x19, x19, #1
        mov     x12, x19
        SCAN_TOKEN
        sub     x13, x19, x12
        bl      Lfind
        cbz     w0, Lset_new
        str     x12, [x4, #N_VAL]       // overwrite: new value, refresh
        strb    w13, [x4, #N_VLEN]
        ldr     w5, [x21, #N_NEXT]
        cmp     w5, w0
        b.eq    Leol
        LIST_UNLINK x4
        LIST_PUSH_FRONT w0, x4
        b       Leol
Lset_new:
        mov     w0, w28                 // pop a free node
        NODE    x4, x0
        ldr     w28, [x4, #N_HNEXT]
        str     w0, [x1]                // append at end of its chain
        stp     x10, x12, [x4, #N_KEY]
        str     wzr, [x4, #N_HNEXT]
        strb    w11, [x4, #N_KLEN]
        strb    w13, [x4, #N_VLEN]
        LIST_PUSH_FRONT w0, x4
        add     x26, x26, #1
        cmp     x26, x27
        b.ls    Leol
        ldr     w0, [x21, #N_PREV]      // evict the LRU node
        NODE    x4, x0
        ldr     x10, [x4, #N_KEY]
        ldrb    w11, [x4, #N_KLEN]
        bl      Lfind                   // locate the slot that links to it
        REMOVE_NODE
        b       Leol

// GET <key>
Lget:
        add     x19, x19, #4
        mov     x10, x19
        SCAN_TOKEN
        sub     x11, x19, x10
        bl      Lfind
        cbz     w0, Lget_null
        ldr     w5, [x21, #N_NEXT]
        cmp     w5, w0
        b.eq    Lget_out
        LIST_UNLINK x4
        LIST_PUSH_FRONT w0, x4
Lget_out:
        ldr     x5, [x4, #N_VAL]
        ldrb    w6, [x4, #N_VLEN]
        mov     x7, x24
        add     x24, x24, x6
1:      ldp     q0, q1, [x5], #32       // over-copy is covered by the slacks
        stp     q0, q1, [x7], #32
        subs    x6, x6, #32
        b.gt    1b
        mov     w9, #'\n'
        strb    w9, [x24], #1
        b       Leol
Lget_null:
        movz    w9, #0x554e             // "NULL"
        movk    w9, #0x4c4c, lsl #16
        str     w9, [x24]
        mov     w9, #'\n'
        strb    w9, [x24, #4]
        add     x24, x24, #5
        b       Leol

// DEL <key>
Ldel:
        add     x19, x19, #4
        mov     x10, x19
        SCAN_TOKEN
        sub     x11, x19, x10
        bl      Lfind
        mov     w9, #0x0a30             // "0\n"
        cbz     w0, Ldel_out
        REMOVE_NODE
        mov     w9, #0x0a31             // "1\n"
Ldel_out:
        strh    w9, [x24], #2
        b       Leol

// SIZE
Lsize:
        mov     x9, x26
        mov     x10, #10
        mov     x11, x24                // count the digits
1:      udiv    x9, x9, x10
        add     x11, x11, #1
        cbnz    x9, 1b
        mov     w12, #'\n'
        strb    w12, [x11]
        add     x24, x11, #1
        mov     x9, x26
2:      udiv    x12, x9, x10
        msub    x13, x12, x10, x9
        add     w13, w13, #'0'
        strb    w13, [x11, #-1]!
        mov     x9, x12
        cbnz    x9, 2b

// Consume the rest of the line, flush output if needed.
Leol:
        ldrb    w9, [x19], #1
        cmp     w9, #'\n'
        b.ne    Leol
        cmp     x24, x25
        b.lo    Lloop
        bl      Lflush
        b       Lloop

Lfinish:
        bl      Lflush
        mov     w0, #0
        b       Lreturn
Lfail:
        mov     w0, #1
Lreturn:
        ldp     x29, x30, [sp, #80]
        ldp     x20, x19, [sp, #64]
        ldp     x22, x21, [sp, #48]
        ldp     x24, x23, [sp, #32]
        ldp     x26, x25, [sp, #16]
        ldp     x28, x27, [sp, #0]
        add     sp, sp, #96
        ret
        .cfi_endproc

// Lfind: look up key (x10 ptr, x11 len).
// Returns w0 = node index (0 if absent), x4 = node address (if found),
// x1 = address of the u32 link holding w0 (the chain's terminating 0 link
// if absent, which is where a new node is appended).
        .p2align 2
Lfind:
        mov     w2, w11                 // CRC32C seeded with the length
        mov     x3, x10
        subs    x4, x11, #8
        b.lo    2f
1:      ldr     x5, [x3], #8
        crc32cx w2, w2, x5
        subs    x4, x4, #8
        b.hs    1b
2:      adds    x4, x4, #8
        b.eq    3f
        ldr     x5, [x3]                // tail: keep the low x4 bytes
        lsl     x6, x4, #3
        neg     x6, x6
        mov     x7, #-1
        lsr     x7, x7, x6
        and     x5, x5, x7
        crc32cx w2, w2, x5
3:      and     w2, w2, w23
        add     x1, x22, x2, lsl #2
Lfind_walk:
        ldr     w0, [x1]
        cbz     w0, Lfind_ret
        NODE    x4, x0
        ldrb    w5, [x4, #N_KLEN]
        cmp     w5, w11
        b.ne    Lfind_next
        ldr     x5, [x4, #N_KEY]
        mov     x6, x10
        mov     x7, x11
4:      cmp     x7, #8
        b.lo    5f
        ldr     x2, [x5], #8
        ldr     x3, [x6], #8
        cmp     x2, x3
        b.ne    Lfind_next
        sub     x7, x7, #8
        b       4b
5:      cbz     x7, Lfind_ret
        ldr     x2, [x5]
        ldr     x3, [x6]
        eor     x2, x2, x3
        lsl     x3, x7, #3
        neg     x3, x3
        mov     x8, #-1
        lsr     x8, x8, x3
        tst     x2, x8
        b.eq    Lfind_ret
Lfind_next:
        add     x1, x4, #N_HNEXT
        b       Lfind_walk
Lfind_ret:
        ret

// Lflush: write [_outbuf, x24) to stdout and reset x24.  Exits(1) on error.
        .p2align 2
Lflush:
        .cfi_startproc
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x20, x19, [sp, #16]
        .cfi_def_cfa w29, 32
        .cfi_offset w30, -24
        .cfi_offset w29, -32
        .cfi_offset w19, -8
        .cfi_offset w20, -16
        adrp    x19, _outbuf@PAGE
        add     x19, x19, _outbuf@PAGEOFF
        sub     x20, x24, x19
        mov     x24, x19
Lflush_loop:
        cbz     x20, Lflush_done
        mov     w0, #1
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.le    Lflush_err
        add     x19, x19, x0
        sub     x20, x20, x0
        b       Lflush_loop
Lflush_err:
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lflush_loop
        mov     w0, #1
        bl      __exit
Lflush_done:
        ldp     x20, x19, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret
        .cfi_endproc

        .zerofill __DATA,__bss,_outbuf,OUT_SIZE+OUT_SLACK,4

.subsections_via_symbols
