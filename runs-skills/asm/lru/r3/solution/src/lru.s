// lru.s — LRU cache simulator (see SPEC.md).
//
// The whole of stdin is read into one buffer; keys and values are kept as
// (pointer, length) slices into that buffer, so no string is ever copied
// until it is written out.  The cache is a chained hash table of node
// pointers plus a circular doubly-linked recency list with a sentinel
// (sentinel.next = most recent, sentinel.prev = least recent).
// Nodes come from a pool sized for exactly C entries, recycled through a
// free list on DEL and reused in place on eviction.

// ---- node layout (64 bytes) -------------------------------------------
    .equ N_HNEXT, 0             // next node in hash chain (must be 0)
    .equ N_KEY,   8             // key pointer
    .equ N_VAL,   16            // value pointer
    .equ N_HASH,  24            // full 64-bit key hash
    .equ N_PREV,  32            // recency list
    .equ N_NEXT,  40
    .equ N_KLEN,  48            // u32
    .equ N_VLEN,  52            // u32
    .equ N_SIZE,  64
    .equ N_SHIFT, 6

    .equ OBUF_SIZE, 65536       // output buffer; flushed once past 60 KiB
    .equ IN_INIT,   1 << 20     // initial input buffer size
    .equ IN_PAD,    64          // slack after input for sentinels / over-read
    .equ EINTR,     4

// Register map inside _main (all callee-saved):
//   x19 cursor in input      x20 end of input
//   x21 bucket array         x22 bucket mask
//   x23 &sentinel            x24 key count
//   x25 capacity C           x26 free-list head
//   x27 pool bump pointer    x28 output cursor
//   x14 FNV prime, x15 FNV offset basis (reloaded after any libc call)

// Scan a key starting at x0: stops at the first byte <= ' '.
// Out: x1 = length, x2 = FNV-1a hash, x9 = one past terminator, w10 = terminator.
.macro SCAN_KEY
    mov     x2, x15
    mov     x9, x0
1:  ldrb    w10, [x9], #1
    cmp     w10, #' '
    b.ls    2f
    eor     x2, x2, x10
    mul     x2, x2, x14
    b       1b
2:  sub     x1, x9, x0
    sub     x1, x1, #1
.endm

// Finish the current line: x9 = one past last scanned byte (w10).
// Sets x19 to the start of the next line.
.macro END_LINE
    cmp     w10, #'\n'
    b.eq    4f
3:  ldrb    w10, [x9], #1
    cmp     w10, #'\n'
    b.ne    3b
4:  mov     x19, x9
.endm

// x5 = &bucket for hash x2.
.macro BUCKET hash
    eor     x5, \hash, \hash, lsr #32
    and     x5, x5, x22
    add     x4, x21, x5, lsl #3
.endm

// Detach node x3 from the recency list. Clobbers x6, x7.
.macro LIST_UNLINK
    ldp     x6, x7, [x3, #N_PREV]
    str     x7, [x6, #N_NEXT]
    str     x6, [x7, #N_PREV]
.endm

// Insert node x3 at the front of the recency list. Clobbers x5.
.macro LIST_PUSH_FRONT
    ldr     x5, [x23, #N_NEXT]
    stp     x23, x5, [x3, #N_PREV]
    str     x3, [x5, #N_PREV]
    str     x3, [x23, #N_NEXT]
.endm

.macro LOAD_FNV
    movz    x15, #0x2325
    movk    x15, #0x8422, lsl #16
    movk    x15, #0x9ce4, lsl #32
    movk    x15, #0xcbf2, lsl #48
    movz    x14, #0x01b3
    movk    x14, #0x0100, lsl #32
.endm

    .text

// ------------------------------------------------------------------------
// int main(void)
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
    // [sp, #0 .. #32) is scratch for number formatting.

    // ---- slurp stdin: x19 = buffer, x20 = length, x21 = capacity ----
    mov     x21, #IN_INIT
    mov     x0, x21
    bl      _malloc
    cbz     x0, Lfail
    mov     x19, x0
    mov     x20, #0
Lread:
    sub     x2, x21, x20
    cmp     x2, #2, lsl #12         // keep at least 8 KiB free per read
    b.hs    1f
    lsl     x21, x21, #1
    mov     x0, x19
    mov     x1, x21
    bl      _realloc
    cbz     x0, Lfail
    mov     x19, x0
    sub     x2, x21, x20
1:  sub     x2, x2, #IN_PAD
    add     x1, x19, x20
    mov     w0, #0
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
    add     x20, x19, x20           // x20 = end of input
    movi    v0.16b, #'\n'           // newline sentinels stop every scan
    stp     q0, q0, [x20]

    // ---- line 1: capacity ----
    mov     x25, #0
    mov     x11, #10
    mov     x9, x19
1:  ldrb    w10, [x9], #1
    sub     w12, w10, #'0'
    cmp     w12, #9
    b.hi    2f
    madd    x25, x25, x11, x12
    b       1b
2:  END_LINE
    cmp     x25, #1
    csinc   x25, x25, xzr, hs       // defensive: C >= 1

    // ---- hash table: power of two >= 2C buckets ----
    lsl     x9, x25, #1
    mov     x22, #16
1:  cmp     x22, x9
    b.hs    2f
    lsl     x22, x22, #1
    b       1b
2:  mov     x0, x22
    mov     x1, #8
    bl      _calloc
    cbz     x0, Lfail
    mov     x21, x0
    sub     x22, x22, #1

    // ---- node pool for C entries ----
    lsl     x0, x25, #N_SHIFT
    bl      _malloc
    cbz     x0, Lfail
    mov     x27, x0

    adrp    x23, _sentinel@PAGE
    add     x23, x23, _sentinel@PAGEOFF
    stp     x23, x23, [x23, #N_PREV]
    mov     x24, #0
    mov     x26, #0
    adrp    x28, _obuf@PAGE
    add     x28, x28, _obuf@PAGEOFF
    LOAD_FNV

// ---- command loop ----
Lloop:
    cmp     x19, x20
    b.hs    Ldone
    adrp    x9, _obuf@PAGE
    add     x9, x9, _obuf@PAGEOFF
    sub     x10, x28, x9
    cmp     x10, #15, lsl #12       // 60 KiB: room for any single reply
    b.lo    1f
    mov     x0, x9
    mov     x1, x10
    bl      _write_all
    adrp    x28, _obuf@PAGE
    add     x28, x28, _obuf@PAGEOFF
    LOAD_FNV
1:  ldrb    w9, [x19]
    cmp     w9, #'G'
    b.eq    Lget
    cmp     w9, #'S'
    b.eq    Lset_or_size
    cmp     w9, #'D'
    b.eq    Ldel
Lskip_line:                         // blank or unknown line
    mov     x9, x19
    mov     w10, #0
    END_LINE
    b       Lloop

// GET <key>
Lget:
    add     x0, x19, #4
    SCAN_KEY
    bl      _find
    END_LINE
    cbz     x3, Lget_miss
    ldr     x5, [x23, #N_NEXT]
    cmp     x5, x3
    b.eq    1f
    LIST_UNLINK
    LIST_PUSH_FRONT
1:  ldr     x0, [x3, #N_VAL]
    ldr     w1, [x3, #N_VLEN]
    mov     x5, x28
    add     x28, x28, x1
2:  ldr     q0, [x0], #16           // 16-byte chunks; both buffers have slack
    str     q0, [x5], #16
    subs    x1, x1, #16
    b.gt    2b
    mov     w5, #'\n'
    strb    w5, [x28], #1
    b       Lloop
Lget_miss:
    movz    x5, #0x554e             // "NULL\n"
    movk    x5, #0x4c4c, lsl #16
    movk    x5, #0x000a, lsl #32
    str     x5, [x28]
    add     x28, x28, #5
    b       Lloop

Lset_or_size:
    ldrb    w9, [x19, #1]
    cmp     w9, #'I'
    b.eq    Lsize

// SET <key> <value>
    add     x0, x19, #4
    SCAN_KEY
    cmp     w10, #' '
    b.ne    Lset_bad
    mov     x11, x9                 // x11 = value start
1:  ldrb    w10, [x9], #1
    cmp     w10, #' '
    b.hi    1b
    sub     x12, x9, x11
    sub     x12, x12, #1            // x12 = value length
    bl      _find
    END_LINE
    cbz     x3, Lset_new
    str     x11, [x3, #N_VAL]
    str     w12, [x3, #N_VLEN]
    ldr     x5, [x23, #N_NEXT]
    cmp     x5, x3
    b.eq    Lloop
    LIST_UNLINK
    LIST_PUSH_FRONT
    b       Lloop
Lset_bad:
    END_LINE
    b       Lloop
Lset_new:
    cmp     x24, x25
    b.lo    Lset_alloc
    // Full: evict the least recently used node and reuse it.
    ldr     x3, [x23, #N_PREV]
    LIST_UNLINK
    ldr     x6, [x3, #N_HASH]
    BUCKET  x6
1:  ldr     x5, [x4]
    cmp     x5, x3
    b.eq    2f
    mov     x4, x5                  // &node->hnext == node
    b       1b
2:  ldr     x5, [x3, #N_HNEXT]
    str     x5, [x4]
    sub     x24, x24, #1
    b       Lset_fill
Lset_alloc:
    cbz     x26, 1f
    mov     x3, x26
    ldr     x26, [x26, #N_HNEXT]
    b       Lset_fill
1:  mov     x3, x27
    add     x27, x27, #N_SIZE
Lset_fill:
    BUCKET  x2
    ldr     x5, [x4]
    str     x5, [x3, #N_HNEXT]
    str     x3, [x4]
    stp     x0, x11, [x3, #N_KEY]
    str     x2, [x3, #N_HASH]
    stp     w1, w12, [x3, #N_KLEN]
    LIST_PUSH_FRONT
    add     x24, x24, #1
    b       Lloop

// SIZE
Lsize:
    mov     x9, x19
    mov     w10, #0
    END_LINE
    add     x5, sp, #32
    mov     w6, #'\n'
    strb    w6, [x5, #-1]!
    mov     x6, x24
    mov     x7, #10
1:  udiv    x8, x6, x7
    msub    x9, x8, x7, x6
    add     w9, w9, #'0'
    strb    w9, [x5, #-1]!
    mov     x6, x8
    cbnz    x6, 1b
    add     x6, sp, #32
2:  ldrb    w9, [x5], #1
    strb    w9, [x28], #1
    cmp     x5, x6
    b.lo    2b
    b       Lloop

// DEL <key>
Ldel:
    add     x0, x19, #4
    SCAN_KEY
    bl      _find
    END_LINE
    cbz     x3, Ldel_miss
    ldr     x5, [x3, #N_HNEXT]
    str     x5, [x4]
    LIST_UNLINK
    str     x26, [x3, #N_HNEXT]
    mov     x26, x3
    sub     x24, x24, #1
    mov     w5, #0x0a31             // "1\n"
    strh    w5, [x28], #2
    b       Lloop
Ldel_miss:
    mov     w5, #0x0a30             // "0\n"
    strh    w5, [x28], #2
    b       Lloop

Ldone:
    adrp    x0, _obuf@PAGE
    add     x0, x0, _obuf@PAGEOFF
    sub     x1, x28, x0
    bl      _write_all
    mov     w0, #0
    b       Lret
Lfail:
    mov     w0, #1
Lret:
    ldp     x29, x30, [sp, #112]
    ldp     x20, x19, [sp, #96]
    ldp     x22, x21, [sp, #80]
    ldp     x24, x23, [sp, #64]
    ldp     x26, x25, [sp, #48]
    ldp     x28, x27, [sp, #32]
    add     sp, sp, #128
    ret
    .cfi_endproc

// ------------------------------------------------------------------------
// Private leaf helper with a custom convention.
// In:  x0 = key, x1 = key length, x2 = hash; x21/x22 = buckets/mask.
// Out: x3 = matching node or 0; x4 = address of the link that points to it
//      (or of the terminating null link).  Clobbers x5-x8 only.
    .p2align 2
_find:
    .cfi_startproc
    BUCKET  x2
Lf_loop:
    ldr     x3, [x4]
    cbz     x3, Lf_ret
    ldr     x5, [x3, #N_HASH]
    cmp     x5, x2
    b.ne    Lf_next
    ldr     w5, [x3, #N_KLEN]
    cmp     x5, x1
    b.ne    Lf_next
    ldr     x6, [x3, #N_KEY]
    mov     x7, #0
Lf_cmp:
    cmp     x7, x1
    b.hs    Lf_ret
    ldrb    w5, [x6, x7]
    ldrb    w8, [x0, x7]
    add     x7, x7, #1
    cmp     w5, w8
    b.eq    Lf_cmp
Lf_next:
    mov     x4, x3                  // &node->hnext == node
    b       Lf_loop
Lf_ret:
    ret
    .cfi_endproc

// ------------------------------------------------------------------------
// void write_all(const void *buf, size_t len): write(1) until done.
    .p2align 2
_write_all:
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
1:  cbz     x20, 3f
    mov     w0, #1
    mov     x1, x19
    mov     x2, x20
    bl      _write
    cmp     x0, #0
    b.le    2f
    add     x19, x19, x0
    sub     x20, x20, x0
    b       1b
2:  b.eq    3f
    bl      ___error
    ldr     w0, [x0]
    cmp     w0, #EINTR
    b.eq    1b
3:  ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp], #32
    ret
    .cfi_endproc

    .zerofill __DATA,__bss,_sentinel,N_SIZE,6
    .zerofill __DATA,__bss,_obuf,OBUF_SIZE,14

.subsections_via_symbols
