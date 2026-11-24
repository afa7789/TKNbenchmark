// lru.s — LRU cache simulator (AArch64, macOS / Mach-O).
//
// Reads the whole of stdin into one buffer, then executes commands in place.
// Keys and values are never copied: cache nodes point straight into the input
// buffer, which stays alive (and unmoved) for the lifetime of the program.
//
// Data structures
//   * Node pool: (C + 1) nodes of 32 bytes. Node 0 is the sentinel of a
//     circular doubly linked recency list (sentinel.next = MRU, .prev = LRU).
//     Released nodes go on a singly linked free list threaded through `next`.
//   * Hash index: open addressing, linear probing, power-of-two size >= 2C.
//     Each 8-byte slot holds (hash << 32) | node_index; 0 means empty.
//     Deletion uses backward-shift, so there are no tombstones and every
//     operation stays O(1) expected.
//
// The input buffer is followed by PAD bytes of '\n'. That makes every token
// and line scan terminate without bounds checks, and allows the 8/16-byte
// over-reads used by hashing, key comparison and value copying.

        .set    NODE_SHIFT, 5           // sizeof(node) == 32
        .set    N_KEY,  0               // u64  key pointer
        .set    N_VAL,  8               // u64  value pointer
        .set    N_HASH, 16              // u32  key hash
        .set    N_KLEN, 20              // u16  key length
        .set    N_VLEN, 22              // u16  value length
        .set    N_PREV, 24              // u32  previous node index
        .set    N_NEXT, 28              // u32  next node index

        .set    PAD,        64          // '\n' padding after the input
        .set    IN_INIT,    1 << 24     // initial input buffer size
        .set    IN_MINREAD, 1 << 16     // grow when less room than this
        .set    OUT_SIZE,   1 << 20     // output buffer size
        .set    MAX_CAP,    1 << 26     // sanity clamp for the capacity
        .set    EINTR,      4

        .set    S_OOM_LEN,    19        // lengths of the diagnostics below
        .set    S_EREAD_LEN,  16
        .set    S_EWRITE_LEN, 17

// Register assignment inside _main (all callee-saved):
//   x19  input cursor            x20  input end (start of '\n' padding)
//   x21  node pool base          x22  hash table base
//   x23  hash table mask         x24  output cursor
//   x25  output buffer end       x26  number of keys held
//   x27  capacity C              x28  free-list head (0 = empty)
//
// Leaf helpers below use only caller-saved registers and document exactly
// which ones they clobber, so _main can keep scratch values in x14/x15.

        .section __TEXT,__text,regular,pure_instructions
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

        bl      read_all                // x0 = buffer, x1 = length
        mov     x19, x0
        add     x20, x0, x1

        // ---- line 1: capacity ------------------------------------------
        mov     x27, #0
        mov     x9, #10
1:      ldrb    w10, [x19]
        sub     w10, w10, #'0'
        cmp     w10, #9
        b.hi    2f
        madd    x27, x27, x9, x10
        add     x19, x19, #1
        mov     x11, #MAX_CAP
        cmp     x27, x11
        csel    x27, x27, x11, ls
        b       1b
2:      ldrb    w10, [x19], #1          // skip rest of the line
        cmp     w10, #'\n'
        b.ne    2b
        cmp     x27, #0
        csinc   x27, x27, xzr, ne       // C = max(C, 1)

        // ---- allocations -----------------------------------------------
        add     x0, x27, #1             // node pool: C + 1 nodes
        lsl     x0, x0, #NODE_SHIFT
        bl      xmalloc
        mov     x21, x0
        str     xzr, [x21, #N_PREV]     // sentinel: prev = next = 0

        lsl     x9, x27, #1             // table size: pow2 >= max(2C, 16)
        sub     x9, x9, #1
        clz     x9, x9
        mov     x10, #64
        sub     x9, x10, x9
        mov     x10, #1
        lsl     x0, x10, x9
        cmp     x0, #16
        mov     x10, #16
        csel    x0, x0, x10, hs
        sub     x23, x0, #1
        mov     x1, #8
        bl      _calloc
        cbz     x0, oom
        mov     x22, x0

        mov     x0, #OUT_SIZE
        bl      xmalloc
        mov     x24, x0
        add     x25, x0, #OUT_SIZE

        mov     x26, #0
        mov     x28, #0

        // ---- command loop ----------------------------------------------
Lloop:
        cmp     x19, x20
        b.hs    Ldone
        ldrb    w9, [x19]
        cmp     w9, #'G'
        b.eq    Lget
        cmp     w9, #'S'
        b.eq    Lset_or_size
        cmp     w9, #'D'
        b.eq    Ldel
Lskip:                                  // advance past the next '\n'
        ldrb    w9, [x19], #1
        cmp     w9, #'\n'
        b.ne    Lskip
        b       Lloop

// Scan a token starting at \start; leaves \end at its terminator (<= ' ').
        .macro  SCAN_TOKEN start, end
        mov     \end, \start
0:      ldrb    w9, [\end], #1
        cmp     w9, #' '
        b.hi    0b
        sub     \end, \end, #1
        .endm

// ---- GET <key> ---------------------------------------------------------
Lget:
        add     x0, x19, #4
        SCAN_TOKEN x0, x19
        sub     x1, x19, x0
        bl      hash_key
        bl      find
        cbz     x4, 1f
        bl      touch
        add     x5, x21, x4, lsl #NODE_SHIFT
        ldr     x0, [x5, #N_VAL]
        ldrh    w1, [x5, #N_VLEN]
        bl      out_line
        b       Lskip
1:      adrp    x0, s_null@PAGE
        add     x0, x0, s_null@PAGEOFF
        mov     x1, #4
        bl      out_line
        b       Lskip

// ---- SET <key> <value> / SIZE --------------------------------------------
Lset_or_size:
        ldrb    w9, [x19, #1]
        cmp     w9, #'I'
        b.eq    Lsize

        add     x0, x19, #4
        SCAN_TOKEN x0, x19
        ldrb    w9, [x19]
        cmp     w9, #' '
        b.ne    Lskip                   // malformed: no value
        add     x14, x19, #1            // x14 = value pointer
        SCAN_TOKEN x14, x19
        sub     x15, x19, x14           // x15 = value length
        sub     x1, x14, x0
        sub     x1, x1, #1              // x1 = key length
        bl      hash_key
        bl      find
        cbnz    x4, Lset_update

        cmp     x26, x27
        b.lo    Lset_alloc

        // Full: recycle the least recently used node for the new key.
        ldr     w4, [x21, #N_PREV]
        bl      tbl_remove_node
        bl      unlink
        and     x3, x2, x23             // re-probe: removal may shift slots
1:      ldr     x5, [x22, x3, lsl #3]
        cbz     x5, Lset_fill
        add     x3, x3, #1
        and     x3, x3, x23
        b       1b

Lset_alloc:
        add     x26, x26, #1
        cbz     x28, 1f
        mov     x4, x28                 // pop the free list
        add     x5, x21, x4, lsl #NODE_SHIFT
        ldr     w28, [x5, #N_NEXT]
        b       Lset_fill
1:      adrp    x5, g_bump@PAGE         // fresh node from the pool
        ldr     x4, [x5, g_bump@PAGEOFF]
        add     x6, x4, #1
        str     x6, [x5, g_bump@PAGEOFF]

Lset_fill:                              // x3 = empty slot, x4 = node
        add     x5, x21, x4, lsl #NODE_SHIFT
        stp     x0, x14, [x5, #N_KEY]
        str     w2, [x5, #N_HASH]
        strh    w1, [x5, #N_KLEN]
        strh    w15, [x5, #N_VLEN]
        orr     x6, x4, x2, lsl #32
        str     x6, [x22, x3, lsl #3]
        bl      push_front
        b       Lskip

Lset_update:
        add     x5, x21, x4, lsl #NODE_SHIFT
        str     x14, [x5, #N_VAL]
        strh    w15, [x5, #N_VLEN]
        bl      touch
        b       Lskip

Lsize:
        mov     x0, x26
        bl      out_uint
        b       Lskip

// ---- DEL <key> ---------------------------------------------------------
Ldel:
        add     x0, x19, #4
        SCAN_TOKEN x0, x19
        sub     x1, x19, x0
        bl      hash_key
        bl      find
        adrp    x0, s_zero@PAGE
        add     x0, x0, s_zero@PAGEOFF
        cbz     x4, 1f
        mov     x7, x3
        bl      tbl_delete_slot
        bl      unlink
        add     x5, x21, x4, lsl #NODE_SHIFT
        str     w28, [x5, #N_NEXT]      // push onto the free list
        mov     x28, x4
        sub     x26, x26, #1
        adrp    x0, s_one@PAGE
        add     x0, x0, s_one@PAGEOFF
1:      mov     x1, #1
        bl      out_line
        b       Lskip

Ldone:
        bl      flush
        mov     w0, #0
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #96
        ret

// ---------------------------------------------------------------------------
// hash_key: x0 = key, x1 = length  ->  x2 = 32-bit hash (upper bits zero).
// Processes 8 bytes per round; the final partial word is masked.
// Preserves x0, x1. Clobbers x3-x7.
        .p2align 4
hash_key:
        mov     x3, x0
        mov     x4, x1
        movz    x5, #0x7c15
        movk    x5, #0x7f4a, lsl #16
        movk    x5, #0x79b9, lsl #32
        movk    x5, #0x9e37, lsl #48
        eor     x2, x1, x5
        cbz     x4, 3f
1:      ldr     x6, [x3], #8
        cmp     x4, #8
        b.hs    2f
        lsl     x7, x4, #3
        neg     x7, x7                  // 64 - 8*len (mod 64)
        lsl     x6, x6, x7
        lsr     x6, x6, x7
        mov     x4, #8
2:      eor     x2, x2, x6
        mul     x2, x2, x5
        eor     x2, x2, x2, lsr #29
        subs    x4, x4, #8
        b.hi    1b
3:      eor     x2, x2, x2, lsr #32
        mul     x2, x2, x5
        eor     x2, x2, x2, lsr #29
        mov     w2, w2
        ret

// find: x0 = key, x1 = length, x2 = hash
//   -> x4 = node index (0 if absent), x3 = slot index (match or first empty).
// Preserves x0-x2, x14, x15. Clobbers x5-x12.
        .p2align 4
find:
        and     x3, x2, x23
1:      ldr     x5, [x22, x3, lsl #3]
        cbz     x5, 5f
        cmp     x2, x5, lsr #32
        b.ne    4f
        mov     w4, w5
        add     x6, x21, x4, lsl #NODE_SHIFT
        ldrh    w7, [x6, #N_KLEN]
        cmp     x7, x1
        b.ne    4f
        ldr     x8, [x6, #N_KEY]
        mov     x9, x0
        mov     x10, x1
2:      ldr     x11, [x9], #8
        ldr     x12, [x8], #8
        eor     x11, x11, x12
        cmp     x10, #8
        b.lo    3f
        cbnz    x11, 4f
        subs    x10, x10, #8
        b.hi    2b
        ret
3:      lsl     x12, x10, #3            // discard bytes past the key
        neg     x12, x12
        lsl     x11, x11, x12
        cbnz    x11, 4f
        ret
4:      add     x3, x3, #1
        and     x3, x3, x23
        b       1b
5:      mov     x4, #0
        ret

// tbl_remove_node: remove the slot referencing node w4.  Clobbers x5-x11.
// tbl_delete_slot: empty slot x7 with backward-shift. Clobbers x7-x11.
        .p2align 4
tbl_remove_node:
        add     x5, x21, x4, lsl #NODE_SHIFT
        ldr     w7, [x5, #N_HASH]
        and     x7, x7, x23
1:      ldr     x8, [x22, x7, lsl #3]
        cmp     w8, w4
        b.eq    tbl_delete_slot
        add     x7, x7, #1
        and     x7, x7, x23
        b       1b
tbl_delete_slot:
        mov     x8, x7                  // x7 = hole i, x8 = scan j
1:      add     x8, x8, #1
        and     x8, x8, x23
        ldr     x9, [x22, x8, lsl #3]
        cbz     x9, 2f
        sub     x10, x8, x9, lsr #32    // displacement of entry at j
        and     x10, x10, x23
        sub     x11, x8, x7             // distance from hole to j
        and     x11, x11, x23
        cmp     x10, x11
        b.lo    1b                      // its home lies after the hole
        str     x9, [x22, x7, lsl #3]
        mov     x7, x8
        b       1b
2:      str     xzr, [x22, x7, lsl #3]
        ret

// Recency list operations on node w4. Clobber x5-x8.
        .p2align 4
unlink:
        add     x5, x21, x4, lsl #NODE_SHIFT
        ldp     w6, w7, [x5, #N_PREV]
        add     x8, x21, x6, lsl #NODE_SHIFT
        str     w7, [x8, #N_NEXT]
        add     x8, x21, x7, lsl #NODE_SHIFT
        str     w6, [x8, #N_PREV]
        ret

touch:                                  // move to the MRU position
        ldr     w6, [x21, #N_NEXT]
        cmp     w6, w4
        b.eq    1f
        add     x5, x21, x4, lsl #NODE_SHIFT
        ldp     w6, w7, [x5, #N_PREV]
        add     x8, x21, x6, lsl #NODE_SHIFT
        str     w7, [x8, #N_NEXT]
        add     x8, x21, x7, lsl #NODE_SHIFT
        str     w6, [x8, #N_PREV]
push_front:
        ldr     w6, [x21, #N_NEXT]
        add     x5, x21, x4, lsl #NODE_SHIFT
        stp     wzr, w6, [x5, #N_PREV]
        add     x8, x21, x6, lsl #NODE_SHIFT
        str     w4, [x8, #N_PREV]
        str     w4, [x21, #N_NEXT]
1:      ret

// ---------------------------------------------------------------------------
// out_line: append x1 bytes at x0 plus '\n'. Source must be readable up to
// 15 bytes past its end. Clobbers caller-saved registers.
        .p2align 4
out_line:
        sub     x2, x25, x24
        add     x3, x1, #32
        cmp     x2, x3
        b.hs    1f
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x0, x1, [sp, #16]
        bl      flush
        ldp     x0, x1, [sp, #16]
        ldp     x29, x30, [sp], #32
1:      mov     x2, x24
        mov     x3, x1
2:      ldr     q0, [x0], #16
        str     q0, [x2], #16
        subs    x3, x3, #16
        b.hi    2b
        add     x24, x24, x1
        mov     w2, #'\n'
        strb    w2, [x24], #1
        ret

// out_uint: append decimal x0 plus '\n'.
out_uint:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        add     x1, sp, #40             // digits end; 24 bytes of slack above
        mov     x2, x1
        mov     x3, #10
1:      udiv    x4, x0, x3
        msub    x5, x4, x3, x0
        add     w5, w5, #'0'
        strb    w5, [x2, #-1]!
        mov     x0, x4
        cbnz    x0, 1b
        mov     x0, x2
        sub     x1, x1, x2
        bl      out_line
        ldp     x29, x30, [sp], #64
        ret

// flush: write the output buffer to stdout, retrying on short writes/EINTR.
flush:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        sub     x19, x25, #OUT_SIZE     // buffer base
        mov     x20, x19
1:      sub     x2, x24, x20
        cbz     x2, 3f
        mov     w0, #1
        mov     x1, x20
        bl      _write
        cmp     x0, #0
        b.gt    2f
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    1b
        adrp    x0, s_ewrite@PAGE
        add     x0, x0, s_ewrite@PAGEOFF
        mov     x1, #S_EWRITE_LEN
        b       fatal
2:      add     x20, x20, x0
        b       1b
3:      mov     x24, x19
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// read_all: slurp stdin. Returns x0 = buffer, x1 = length; the buffer is
// followed by PAD bytes of '\n'.
read_all:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        mov     x21, #IN_INIT           // capacity
        add     x0, x21, #PAD
        bl      xmalloc
        mov     x19, x0                 // buffer
        mov     x20, #0                 // length
1:      sub     x2, x21, x20
        cmp     x2, #IN_MINREAD
        b.hs    2f
        lsl     x21, x21, #1
        mov     x0, x19
        add     x1, x21, #PAD
        bl      _realloc
        cbz     x0, oom
        mov     x19, x0
2:      mov     w0, #0
        add     x1, x19, x20
        sub     x2, x21, x20
        bl      _read
        cmp     x0, #0
        b.gt    3f
        b.eq    4f
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    1b
        adrp    x0, s_eread@PAGE
        add     x0, x0, s_eread@PAGEOFF
        mov     x1, #S_EREAD_LEN
        b       fatal
3:      add     x20, x20, x0
        b       1b
4:      add     x0, x19, x20
        mov     w1, #'\n'
        mov     x2, #PAD
        bl      _memset
        mov     x0, x19
        mov     x1, x20
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// xmalloc: malloc that never returns NULL.
xmalloc:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        bl      _malloc
        cbz     x0, oom
        ldp     x29, x30, [sp], #16
        ret

oom:
        adrp    x0, s_oom@PAGE
        add     x0, x0, s_oom@PAGEOFF
        mov     x1, #S_OOM_LEN
// fatal: print message x0/x1 to stderr and exit(1). Does not return.
fatal:
        mov     x2, x1
        mov     x1, x0
        mov     w0, #2
        bl      _write
        mov     w0, #1
        bl      _exit

// ---------------------------------------------------------------------------
        .section __TEXT,__const
        .p2align 4
// Each literal is followed by enough bytes for out_line's 16-byte copies.
s_null: .ascii  "NULL"
        .space  12
s_zero: .ascii  "0"
        .space  15
s_one:  .ascii  "1"
        .space  15

        .section __TEXT,__const
s_oom:      .ascii "app: out of memory\n"
s_eread:    .ascii "app: read error\n"
s_ewrite:   .ascii "app: write error\n"

        .section __DATA,__data
        .p2align 3
g_bump: .quad   1                       // next never-used pool node
