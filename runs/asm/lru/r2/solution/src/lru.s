// lru.s — LRU cache simulator (see SPEC.md).
//
// Design
//   * All of stdin is slurped into one heap buffer. Keys and values are
//     never copied: nodes hold pointers into that buffer.
//   * Nodes live in a flat pool indexed by 32-bit indices. Index 0 is the
//     sentinel of a circular doubly linked recency list (sentinel.next is the
//     most recently used node, sentinel.prev the least recently used one).
//     The sentinel's CHAIN field doubles as the head of the free-node list.
//   * A power-of-two bucket array of 32-bit node indices with separate
//     chaining (through CHAIN) maps keys to nodes; load factor <= 0.5.
//   * Output is accumulated in a 64 KiB buffer and flushed with write(2).
//
// Global registers inside _main (callee-saved, live for the whole run):
//   x19  input cursor            x20  input end (a '\n' sentinel sits here)
//   x21  node pool base          x22  bucket array base
//   x23  bucket mask (w23)       x24  number of keys held
//   x25  capacity                x26  output buffer base
//   x27  output cursor           x28  next never-used node index
//
// Internal helpers (hash_key, lookup, list_*, hash_*) are leaf routines with
// a private convention: they only clobber x9-x15 and the registers they
// document as results, so callers may keep state in x0-x8 across them.

        .set    NODE_KEY,   0           // u64  key pointer
        .set    NODE_VAL,   8           // u64  value pointer
        .set    NODE_PREV,  16          // u32  recency list
        .set    NODE_NEXT,  20          // u32  recency list / free list link
        .set    NODE_CHAIN, 24          // u32  hash chain link
        .set    NODE_HASH,  28          // u32  full key hash
        .set    NODE_KLEN,  32          // u32  key length
        .set    NODE_VLEN,  36          // u32  value length
        .set    NODE_SIZE,  40

        .set    IN_INITIAL, 0x100000    // initial input buffer size
        .set    IN_PAD,     64          // slack kept after the input data
        .set    OUT_SIZE,   0x10000     // output buffer size
        .set    OUT_LIMIT,  0xF000      // flush when this much is pending
        .set    EINTR,      4

// dst = address of node \idx  (base + idx * 40)
        .macro  node_addr dst, idx
        add     \dst, \idx, \idx, lsl #2
        add     \dst, x21, \dst, lsl #3
        .endm

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

// ---- read all of stdin: x19 = buffer, x20 = length, x21 = capacity ----
        mov     x21, #IN_INITIAL
        mov     x0, x21
        bl      _malloc
        cbz     x0, Lfail
        mov     x19, x0
        mov     x20, #0
Lread_loop:
        sub     x2, x21, x20
        subs    x2, x2, #IN_PAD
        b.hi    Lread_some
        lsl     x21, x21, #1                // grow geometrically
        mov     x0, x19
        mov     x1, x21
        bl      _realloc
        cbz     x0, Lfail
        mov     x19, x0
        b       Lread_loop
Lread_some:
        mov     w0, #0
        add     x1, x19, x20
        bl      _read
        cmp     x0, #0
        b.gt    Lread_got
        b.eq    Lread_done
        bl      ___error                    // read failed: retry on EINTR
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lread_loop
        b       Lread_done
Lread_got:
        add     x20, x20, x0
        b       Lread_loop
Lread_done:
        add     x20, x19, x20               // x20 = end of data
        mov     w9, #'\n'
        strb    w9, [x20]                   // terminate a final unterminated line

// ---- line 1: capacity ----
        bl      skip_sp
        mov     x25, #0
        mov     x10, #10
Lcap_digit:
        ldrb    w9, [x19]
        sub     w9, w9, #'0'
        cmp     w9, #9
        b.hi    Lcap_done
        madd    x25, x25, x10, x9
        add     x19, x19, #1
        b       Lcap_digit
Lcap_done:
        cmp     x25, #1                     // spec guarantees C >= 1; be safe
        csinc   x25, x25, xzr, hs
1:      ldrb    w9, [x19], #1               // skip the rest of line 1
        cmp     w9, #'\n'
        b.ne    1b

// ---- allocate node pool (sentinel + C nodes), buckets, output buffer ----
        add     x0, x25, #1
        mov     x9, #NODE_SIZE
        mul     x0, x0, x9
        bl      _malloc
        cbz     x0, Lfail
        mov     x21, x0
        str     xzr, [x21, #NODE_PREV]      // PREV = NEXT = 0: empty list
        str     wzr, [x21, #NODE_CHAIN]     // free list empty

        mov     x9, #16                     // buckets: pow2 >= 2*C
        lsl     x10, x25, #1
1:      cmp     x9, x10
        b.hs    2f
        lsl     x9, x9, #1
        b       1b
2:      sub     w23, w9, #1
        mov     x0, x9
        mov     x1, #4
        bl      _calloc
        cbz     x0, Lfail
        mov     x22, x0

        mov     x0, #OUT_SIZE
        bl      _malloc
        cbz     x0, Lfail
        mov     x26, x0
        mov     x27, x0

        mov     x24, #0
        mov     x28, #1

// ---- command loop ----
Lcmd_loop:
        cmp     x19, x20
        b.hs    Lfinish
        sub     x9, x27, x26                // keep room for one command's output
        cmp     x9, #OUT_LIMIT
        b.lo    1f
        bl      flush
1:      ldrb    w9, [x19]
        cmp     w9, #'G'
        b.eq    Lget
        cmp     w9, #'D'
        b.eq    Ldel
        cmp     w9, #'S'
        b.ne    Lskip_line
        ldrb    w9, [x19, #1]
        cmp     w9, #'E'
        b.eq    Lset
        cmp     w9, #'I'
        b.eq    Lsize
Lskip_line:
        ldrb    w9, [x19], #1
        cmp     w9, #'\n'
        b.ne    Lskip_line
        b       Lcmd_loop

// GET <key>
Lget:
        add     x19, x19, #3
        bl      skip_sp
        bl      scan_token
        bl      hash_key
        bl      lookup
        cbz     w3, Lget_miss
        bl      list_unlink
        bl      list_push_front
        ldr     x9, [x4, #NODE_VAL]
        ldr     w10, [x4, #NODE_VLEN]
        mov     x11, x27
        add     x27, x27, x10
1:      ldr     q0, [x9], #16               // over-copy in 16-byte chunks; the
        str     q0, [x11], #16              // input pad and output slack cover it
        subs    x10, x10, #16
        b.gt    1b
        mov     w9, #'\n'
        strb    w9, [x27], #1
        b       Lskip_line
Lget_miss:
        mov     w9, #0x554e
        movk    w9, #0x4c4c, lsl #16        // "NULL" little-endian
        str     w9, [x27]
        mov     w9, #'\n'
        strb    w9, [x27, #4]
        add     x27, x27, #5
        b       Lskip_line

// SET <key> <value>
Lset:
        add     x19, x19, #3
        bl      skip_sp
        bl      scan_token
        mov     x5, x0
        mov     x6, x1
        bl      skip_sp
        bl      scan_token
        mov     x7, x0                      // x7/x8 = value ptr/len
        mov     x8, x1
        mov     x0, x5                      // x0/x1 = key ptr/len
        mov     x1, x6
        bl      hash_key
        bl      lookup
        cbz     w3, Lset_new
        str     x7, [x4, #NODE_VAL]         // overwrite existing key
        str     w8, [x4, #NODE_VLEN]
        bl      list_unlink
        bl      list_push_front
        b       Lskip_line
Lset_new:
        cmp     x24, x25
        b.lo    Lset_alloc
        ldr     w3, [x21, #NODE_PREV]       // full: recycle the LRU node
        node_addr x4, x3
        bl      list_unlink
        bl      hash_remove
        b       Lset_fill
Lset_alloc:
        add     x24, x24, #1
        ldr     w3, [x21, #NODE_CHAIN]      // free list head
        cbz     w3, 1f
        node_addr x4, x3
        ldr     w9, [x4, #NODE_NEXT]
        str     w9, [x21, #NODE_CHAIN]
        b       Lset_fill
1:      mov     x3, x28                     // fresh node
        add     x28, x28, #1
        node_addr x4, x3
Lset_fill:
        str     x0, [x4, #NODE_KEY]
        str     x7, [x4, #NODE_VAL]
        str     w2, [x4, #NODE_HASH]
        str     w1, [x4, #NODE_KLEN]
        str     w8, [x4, #NODE_VLEN]
        bl      hash_insert
        bl      list_push_front
        b       Lskip_line

// DEL <key>
Ldel:
        add     x19, x19, #3
        bl      skip_sp
        bl      scan_token
        bl      hash_key
        bl      lookup
        mov     w9, #'0'
        cbz     w3, 1f
        bl      list_unlink
        bl      hash_remove
        ldr     w9, [x21, #NODE_CHAIN]      // push onto free list
        str     w9, [x4, #NODE_NEXT]
        str     w3, [x21, #NODE_CHAIN]
        sub     x24, x24, #1
        mov     w9, #'1'
1:      strb    w9, [x27]
        mov     w9, #'\n'
        strb    w9, [x27, #1]
        add     x27, x27, #2
        b       Lskip_line

// SIZE
Lsize:
        mov     x11, #10
        mov     x9, x24
        mov     x12, x27
1:      udiv    x9, x9, x11                 // x12 = end of the digits
        add     x12, x12, #1
        cbnz    x9, 1b
        mov     w9, #'\n'
        strb    w9, [x12]
        add     x27, x12, #1
        mov     x9, x24
2:      udiv    x13, x9, x11
        msub    x14, x13, x11, x9
        add     w14, w14, #'0'
        strb    w14, [x12, #-1]!
        mov     x9, x13
        cbnz    x9, 2b
        b       Lskip_line

Lfinish:
        bl      flush
        mov     w0, #0
Lreturn:
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #96
        ret
Lfail:
        mov     w0, #1
        b       Lreturn

// ---------------------------------------------------------------------------
// skip_sp: advance x19 past spaces.  Clobbers w9.
        .p2align 2
skip_sp:
        ldrb    w9, [x19]
        cmp     w9, #' '
        b.ne    1f
        add     x19, x19, #1
        b       skip_sp
1:      ret

// scan_token: token at x19 ends at the first byte <= ' '.
// Out: x0 = start, x1 = length, x19 = terminator.  Clobbers w9.
        .p2align 2
scan_token:
        mov     x0, x19
1:      ldrb    w9, [x19], #1
        cmp     w9, #' '
        b.hi    1b
        sub     x19, x19, #1
        sub     x1, x19, x0
        ret

// hash_key: FNV-1a over x0[0..x1), folded to 32 bits.
// Out: w2 = hash.  Clobbers x9-x12.
        .p2align 2
hash_key:
        mov     x9, #0x2325
        movk    x9, #0x8422, lsl #16
        movk    x9, #0x9ce4, lsl #32
        movk    x9, #0xcbf2, lsl #48
        mov     x10, #0x01b3
        movk    x10, #0x100, lsl #32
        mov     x11, #0
        cbz     x1, 2f
1:      ldrb    w12, [x0, x11]
        eor     x9, x9, x12
        mul     x9, x9, x10
        add     x11, x11, #1
        cmp     x11, x1
        b.lo    1b
2:      eor     x9, x9, x9, lsr #32
        mov     w2, w9
        ret

// lookup: find key (x0 ptr, x1 len, w2 hash).
// Out: w3 = node index (0 if absent), x4 = node address.  Clobbers x9-x14.
        .p2align 2
lookup:
        and     w9, w2, w23
        ldr     w3, [x22, x9, lsl #2]
1:      cbz     w3, 9f
        node_addr x4, x3
        ldr     w10, [x4, #NODE_HASH]
        cmp     w10, w2
        b.ne    3f
        ldr     w10, [x4, #NODE_KLEN]
        cmp     x10, x1
        b.ne    3f
        ldr     x11, [x4, #NODE_KEY]
        mov     x12, #0
2:      cmp     x12, x1
        b.eq    9f                          // all bytes equal: found
        ldrb    w13, [x0, x12]
        ldrb    w14, [x11, x12]
        add     x12, x12, #1
        cmp     w13, w14
        b.eq    2b
3:      ldr     w3, [x4, #NODE_CHAIN]
        b       1b
9:      ret

// list_unlink: remove node (x4) from the recency list.  Clobbers x9-x11.
        .p2align 2
list_unlink:
        ldr     w9, [x4, #NODE_PREV]
        ldr     w10, [x4, #NODE_NEXT]
        node_addr x11, x9
        str     w10, [x11, #NODE_NEXT]
        node_addr x11, x10
        str     w9, [x11, #NODE_PREV]
        ret

// list_push_front: make node (w3, x4) the most recently used.  Clobbers x9-x10.
        .p2align 2
list_push_front:
        ldr     w9, [x21, #NODE_NEXT]
        str     wzr, [x4, #NODE_PREV]
        str     w9, [x4, #NODE_NEXT]
        node_addr x10, x9
        str     w3, [x10, #NODE_PREV]
        str     w3, [x21, #NODE_NEXT]
        ret

// hash_insert: link node (w3, x4) into its bucket.  Clobbers x9-x10.
        .p2align 2
hash_insert:
        ldr     w9, [x4, #NODE_HASH]
        and     w9, w9, w23
        ldr     w10, [x22, x9, lsl #2]
        str     w10, [x4, #NODE_CHAIN]
        str     w3, [x22, x9, lsl #2]
        ret

// hash_remove: unlink node (w3, x4) from its bucket chain.  Clobbers x9-x12.
        .p2align 2
hash_remove:
        ldr     w9, [x4, #NODE_HASH]
        and     w9, w9, w23
        add     x9, x22, x9, lsl #2         // x9 = address of the link to patch
1:      ldr     w11, [x9]
        cmp     w11, w3
        b.eq    2f
        node_addr x12, x11
        add     x9, x12, #NODE_CHAIN
        b       1b
2:      ldr     w10, [x4, #NODE_CHAIN]
        str     w10, [x9]
        ret

// flush: write the pending output [x26, x27) to stdout, then reset x27.
// Standard AAPCS64 call: clobbers caller-saved registers.
        .p2align 2
flush:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        str     x19, [sp, #16]
        mov     x19, x26
1:      subs    x2, x27, x19
        b.ls    3f
        mov     w0, #1
        mov     x1, x19
        bl      _write
        cmp     x0, #0
        b.le    2f
        add     x19, x19, x0
        b       1b
2:      b.eq    3f
        bl      ___error                    // retry on EINTR, give up otherwise
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    1b
3:      mov     x27, x26
        ldr     x19, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

.subsections_via_symbols
