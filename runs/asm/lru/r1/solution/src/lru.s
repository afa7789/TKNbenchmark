// lru.s — LRU cache simulator for macOS / AArch64.
//
// Reads a capacity line followed by SET/GET/DEL/SIZE commands from stdin and
// writes the results to stdout. See SPEC.md.
//
// Design
//   * All of stdin is read into one heap buffer that is guaranteed to end in
//     '\n'. Keys and values are never copied: cache nodes refer to them by
//     32-bit offset into that buffer.
//   * Nodes live in a flat pool of (C + 1) 32-byte records addressed by index.
//     Index 0 is the sentinel of the circular doubly linked recency list
//     (sentinel.next = MRU, sentinel.prev = LRU) and doubles as the "null"
//     index for hash chains and the free list.
//   * The hash table is a power-of-two array of 32-bit chain heads (>= 2C
//     buckets) with separate chaining through node.hnext. Keys are hashed with
//     the CRC32C instructions followed by a multiplicative finaliser.
//   * Output is staged in a 64 KiB static buffer.
//
// Register conventions inside main's command loop (callee-saved, so they
// survive libc calls):
//   x19  cursor: start of the next unparsed line
//   x20  end of input
//   x21  input base (keys/values are stored as offsets from here)
//   x22  node pool base
//   x23  bucket array base
//   x24  bucket mask (number of buckets - 1)
//   x25  capacity C
//   x26  current number of keys
//   x27  output write pointer
//   x28  output soft limit (OUT_SIZE - OUT_SLACK past the buffer start)
// Internal leaf helpers read these globals and clobber only x0-x8 and
// x16-x17, so main may keep short-lived values in x9-x15 across them.

        .arch_extension crc

// Node record layout (32 bytes).
        .equ    NODE_SHIFT, 5
        .equ    N_PREV,     0           // u32 recency list: towards MRU
        .equ    N_NEXT,     4           // u32 recency list: towards LRU
        .equ    N_HNEXT,    8           // u32 hash chain / free list link
        .equ    N_HASH,     12          // u32 full hash of the key
        .equ    N_KOFF,     16          // u32 key offset in the input buffer
        .equ    N_KLEN,     20          // u32 key length
        .equ    N_VOFF,     24          // u32 value offset in the input buffer
        .equ    N_VLEN,     28          // u32 value length

        .equ    OUT_SIZE,   65536
        .equ    OUT_SLACK,  32          // room for the short fixed replies
        .equ    READ_INIT,  1 << 20
        .equ    READ_MIN,   4096        // minimum free space before read()
        .equ    MAX_CAP,    1 << 26
        .equ    EINTR,      4

// Four-byte command tags as little-endian words.
        .equ    TAG_GET,    0x20544547  // "GET "
        .equ    TAG_SET,    0x20544553  // "SET "
        .equ    TAG_DEL,    0x204C4544  // "DEL "
        .equ    TAG_SIZE,   0x455A4953  // "SIZE"
        .equ    TAG_NULL,   0x4C4C554E  // "NULL"

// Load a 32-bit constant into a W register.
.macro  MOVW32  reg, value
        movz    \reg, #((\value) & 0xFFFF)
        movk    \reg, #(((\value) >> 16) & 0xFFFF), lsl #16
.endm

        .section __TEXT,__text,regular,pure_instructions

// ---------------------------------------------------------------------------
// int main(void)
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

        bl      read_all                // x0 = buffer, x1 = length
        mov     x21, x0
        mov     x19, x0
        add     x20, x0, x1

        // ---- capacity: leading decimal digits of line 1, clamped ----------
        mov     x25, #0
        mov     x9, #MAX_CAP
        mov     x10, #10
Lcap_digit:
        ldrb    w0, [x19]
        sub     w0, w0, #'0'
        cmp     w0, #9
        b.hi    Lcap_skip
        madd    x25, x25, x10, x0
        cmp     x25, x9
        csel    x25, x9, x25, hi
        add     x19, x19, #1
        b       Lcap_digit
Lcap_skip:                              // advance past the first '\n'
        ldrb    w0, [x19], #1
        cmp     w0, #'\n'
        b.ne    Lcap_skip
        cmp     x25, #1
        csinc   x25, x25, xzr, hs       // C = max(C, 1)

        // ---- hash table: smallest power of two >= 2C (at least 16) --------
        lsl     x0, x25, #1
        mov     x1, #16
Lbucket_size:
        cmp     x1, x0
        b.hs    Lbucket_alloc
        lsl     x1, x1, #1
        b       Lbucket_size
Lbucket_alloc:
        sub     x24, x1, #1
        mov     x0, x1
        mov     x1, #4
        bl      _calloc
        cbz     x0, Lout_of_memory
        mov     x23, x0

        // ---- node pool: sentinel + C nodes, zeroed (empty list) -----------
        add     x0, x25, #1
        mov     x1, #(1 << NODE_SHIFT)
        bl      _calloc
        cbz     x0, Lout_of_memory
        mov     x22, x0

        mov     x26, #0
        adrp    x27, _outbuf@PAGE
        add     x27, x27, _outbuf@PAGEOFF
        mov     x0, #(OUT_SIZE - OUT_SLACK)
        add     x28, x27, x0

// ---------------------------------------------------------------------------
// Command loop. Per line: x9 = line start, x10 = line end (exclusive, '\r'
// stripped), x11 = line length.
// ---------------------------------------------------------------------------
Lloop:
        cmp     x19, x20
        b.hs    Ldone
        cmp     x27, x28
        b.lo    1f
        bl      flush_out
1:
        mov     x0, x19                 // locate end of line; the buffer is
        mov     w1, #'\n'               // '\n'-terminated, so this never fails
        sub     x2, x20, x19
        bl      _memchr
        mov     x9, x19
        mov     x10, x0
        add     x19, x0, #1
        cmp     x10, x9
        b.eq    Lloop                   // empty line
        ldurb   w0, [x10, #-1]
        cmp     w0, #'\r'
        b.ne    2f
        sub     x10, x10, #1
2:
        sub     x11, x10, x9
        cmp     x11, #4
        b.lo    Lloop                   // too short to be a command

        ldr     w0, [x9]
        MOVW32  w1, TAG_GET
        cmp     w0, w1
        b.eq    Lcmd_get
        MOVW32  w1, TAG_SET
        cmp     w0, w1
        b.eq    Lcmd_set
        MOVW32  w1, TAG_DEL
        cmp     w0, w1
        b.eq    Lcmd_del
        MOVW32  w1, TAG_SIZE
        cmp     w0, w1
        ccmp    x11, #4, #0, eq
        b.eq    Lcmd_size
        b       Lloop                   // unknown command: ignore

// ---- GET <key> -------------------------------------------------------------
Lcmd_get:
        add     x12, x9, #4             // x12 = key, x13 = key length
        mov     x0, x12
        mov     x1, x10
        bl      token_end
        subs    x13, x0, x12
        b.eq    Lloop
        mov     x0, x12
        mov     x1, x13
        bl      lookup                  // w1 = node index or 0
        cbz     w1, Lget_miss
        mov     w9, w1
        bl      touch
        add     x3, x22, x9, lsl #NODE_SHIFT
        ldp     w0, w1, [x3, #N_VOFF]
        add     x0, x21, x0
        bl      emit_line
        b       Lloop
Lget_miss:
        MOVW32  w0, TAG_NULL
        str     w0, [x27]
        mov     w0, #'\n'
        strb    w0, [x27, #4]
        add     x27, x27, #5
        b       Lloop

// ---- SET <key> <value> -----------------------------------------------------
Lcmd_set:
        add     x12, x9, #4             // x12/x13 = key, x14/x15 = value
        mov     x0, x12
        mov     x1, x10
        bl      token_end
        subs    x13, x0, x12
        b.eq    Lloop
        cmp     x0, x10
        b.hs    Lloop                   // no value token
        add     x14, x0, #1
        mov     x0, x14
        mov     x1, x10
        bl      token_end
        subs    x15, x0, x14
        b.eq    Lloop

        mov     x0, x12
        mov     x1, x13
        bl      lookup                  // w1 = index, w2 = hash
        cbz     w1, Lset_insert

        // Existing key: overwrite the value and make it the MRU.
        mov     w9, w1
        add     x3, x22, x9, lsl #NODE_SHIFT
        sub     x4, x14, x21
        stp     w4, w15, [x3, #N_VOFF]
        bl      touch
        b       Lloop

Lset_insert:
        mov     w11, w2                 // keep the hash across helper calls
        cmp     x26, x25
        b.lo    Lset_alloc

        // Full: recycle the LRU node for the new key (size is unchanged).
        ldr     w9, [x22, #N_PREV]
        mov     w0, w9
        bl      list_unlink
        mov     w0, w9
        bl      hash_remove
        b       Lset_fill

Lset_alloc:
        adrp    x0, _pool_state@PAGE
        add     x0, x0, _pool_state@PAGEOFF
        ldp     w9, w1, [x0]            // w9 = free head, w1 = next unused
        cbz     w9, 1f
        add     x2, x22, x9, lsl #NODE_SHIFT
        ldr     w2, [x2, #N_HNEXT]
        str     w2, [x0]                // pop the free list
        b       2f
1:      mov     w9, w1                  // carve a fresh node
        add     w1, w1, #1
        str     w1, [x0, #4]
2:      add     x26, x26, #1

Lset_fill:
        add     x3, x22, x9, lsl #NODE_SHIFT
        str     w11, [x3, #N_HASH]
        sub     x4, x12, x21
        stp     w4, w13, [x3, #N_KOFF]
        sub     x4, x14, x21
        stp     w4, w15, [x3, #N_VOFF]
        and     w4, w11, w24            // push onto the bucket chain
        add     x4, x23, x4, lsl #2
        ldr     w5, [x4]
        str     w5, [x3, #N_HNEXT]
        str     w9, [x4]
        mov     w0, w9
        bl      list_push_front
        b       Lloop

// ---- DEL <key> -------------------------------------------------------------
Lcmd_del:
        add     x12, x9, #4
        mov     x0, x12
        mov     x1, x10
        bl      token_end
        subs    x13, x0, x12
        b.eq    Lloop
        mov     x0, x12
        mov     x1, x13
        bl      lookup                  // x0 = link to node, w1 = index
        cbz     w1, Ldel_miss
        mov     w9, w1
        add     x3, x22, x9, lsl #NODE_SHIFT
        ldr     w4, [x3, #N_HNEXT]
        str     w4, [x0]                // drop from the hash chain
        mov     w0, w9
        bl      list_unlink
        adrp    x0, _pool_state@PAGE    // return node to the free list
        add     x0, x0, _pool_state@PAGEOFF
        ldr     w1, [x0]
        add     x3, x22, x9, lsl #NODE_SHIFT
        str     w1, [x3, #N_HNEXT]
        str     w9, [x0]
        sub     x26, x26, #1
        mov     w0, #('1' | ('\n' << 8))
        strh    w0, [x27], #2
        b       Lloop
Ldel_miss:
        mov     w0, #('0' | ('\n' << 8))
        strh    w0, [x27], #2
        b       Lloop

// ---- SIZE ------------------------------------------------------------------
Lcmd_size:
        mov     x0, x26
        bl      emit_uint
        b       Lloop

Ldone:
        bl      flush_out
        mov     w0, #0
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #96
        ret

Lout_of_memory:
        bl      die_oom

// ---------------------------------------------------------------------------
// read_all: slurp stdin. Returns x0 = buffer, x1 = length; the data always
// ends with '\n' (one is appended if missing or if stdin is empty).
// ---------------------------------------------------------------------------
        .p2align 2
read_all:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]     // x19 = buffer, x20 = length
        str     x21, [sp, #32]          // x21 = capacity
        mov     x21, #READ_INIT
        mov     x0, x21
        bl      _malloc
        cbz     x0, Lread_oom
        mov     x19, x0
        mov     x20, #0
Lread_loop:
        sub     x2, x21, x20
        cmp     x2, #READ_MIN
        b.hi    1f
        lsl     x21, x21, #1
        mov     x0, x19
        mov     x1, x21
        bl      _realloc
        cbz     x0, Lread_oom
        mov     x19, x0
1:      sub     x2, x21, x20
        sub     x2, x2, #1              // reserve a byte for the final '\n'
        mov     w0, #0
        add     x1, x19, x20
        bl      _read
        cmp     x0, #0
        b.gt    2f
        b.eq    Lread_eof
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lread_loop
        b       Lread_eof               // other errors: treat as end of input
2:      add     x20, x20, x0
        b       Lread_loop
Lread_eof:
        cbz     x20, 3f
        add     x1, x19, x20
        ldurb   w0, [x1, #-1]
        cmp     w0, #'\n'
        b.eq    4f
3:      mov     w0, #'\n'
        strb    w0, [x19, x20]
        add     x20, x20, #1
4:      mov     x0, x19
        mov     x1, x20
        ldr     x21, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret
Lread_oom:
        bl      die_oom

// ---------------------------------------------------------------------------
// flush_out: write the staged output to stdout and reset x27.
// Retries on EINTR / short writes; silently drops output on other errors.
// ---------------------------------------------------------------------------
        .p2align 2
flush_out:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        adrp    x19, _outbuf@PAGE
        add     x19, x19, _outbuf@PAGEOFF
        mov     x20, x19
Lflush_loop:
        subs    x2, x27, x20
        b.ls    Lflush_done
        mov     w0, #1
        mov     x1, x20
        bl      _write
        cmp     x0, #0
        b.gt    1f
        b.eq    Lflush_done
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lflush_loop
        b       Lflush_done
1:      add     x20, x20, x0
        b       Lflush_loop
Lflush_done:
        mov     x27, x19
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// ---------------------------------------------------------------------------
// emit_line(x0 = src, x1 = len): append bytes plus '\n' to the output,
// flushing as needed so any length is accepted.
// ---------------------------------------------------------------------------
        .p2align 2
emit_line:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        mov     x19, x0
        mov     x20, x1
Lemit_chunk:
        add     x3, x28, #OUT_SLACK     // hard end of the buffer
        subs    x2, x3, x27             // x2 = free bytes
        b.hi    1f
        bl      flush_out
        b       Lemit_chunk
1:      cmp     x2, x20
        csel    x2, x2, x20, lo         // x2 = bytes to copy now
        sub     x20, x20, x2
        cmp     x2, #8
        b.lo    3f
2:      ldr     x4, [x19], #8           // 8-byte blocks
        str     x4, [x27], #8
        sub     x2, x2, #8
        cmp     x2, #8
        b.hs    2b
3:      cbz     x2, 4f
        ldrb    w4, [x19], #1
        strb    w4, [x27], #1
        sub     x2, x2, #1
        b       3b
4:      cbnz    x20, Lemit_chunk
        add     x3, x28, #OUT_SLACK
        cmp     x27, x3
        b.lo    5f
        bl      flush_out
5:      mov     w4, #'\n'
        strb    w4, [x27], #1
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// ---------------------------------------------------------------------------
// emit_uint(x0 = value): append the decimal value plus '\n'. The caller
// guarantees OUT_SLACK bytes of room. Leaf; clobbers x0-x5.
// ---------------------------------------------------------------------------
        .p2align 2
emit_uint:
        sub     sp, sp, #32
        add     x1, sp, #32             // digits are built backwards
        mov     x2, x1
        mov     x3, #10
1:      udiv    x4, x0, x3
        msub    x5, x4, x3, x0
        add     w5, w5, #'0'
        strb    w5, [x2, #-1]!
        mov     x0, x4
        cbnz    x0, 1b
2:      ldrb    w5, [x2], #1
        strb    w5, [x27], #1
        cmp     x2, x1
        b.ne    2b
        mov     w5, #'\n'
        strb    w5, [x27], #1
        add     sp, sp, #32
        ret

// ---------------------------------------------------------------------------
// token_end(x0 = p, x1 = end): first ' ' at or after p, or end. Leaf.
// ---------------------------------------------------------------------------
        .p2align 2
token_end:
        cmp     x0, x1
        b.hs    1f
        ldrb    w2, [x0]
        cmp     w2, #' '
        b.eq    1f
        add     x0, x0, #1
        b       token_end
1:      ret

// ---------------------------------------------------------------------------
// lookup(x0 = key, x1 = len)
//   -> w1 = node index (0 if absent)
//      x0 = address of the u32 link that holds it (bucket head or a
//           predecessor's hnext); when absent, the terminating link
//      w2 = hash of the key
// Leaf; clobbers x0-x8, x16, x17.
// ---------------------------------------------------------------------------
        .p2align 2
lookup:
        mov     x7, x0                  // x7 = key, x6 = len
        mov     x6, x1
        mov     w2, #-1                 // CRC32C over 8-byte blocks + tail
        mov     x3, x0
        lsr     x4, x1, #3
        cbz     x4, 2f
1:      ldr     x5, [x3], #8
        crc32cx w2, w2, x5
        subs    x4, x4, #1
        b.ne    1b
2:      ands    x4, x1, #7
        b.eq    4f
3:      ldrb    w5, [x3], #1
        crc32cb w2, w2, w5
        subs    x4, x4, #1
        b.ne    3b
4:      eor     w2, w2, w2, lsr #16     // finaliser spreads bits downwards
        MOVW32  w5, 0x85EBCA6B
        mul     w2, w2, w5
        eor     w2, w2, w2, lsr #13

        and     w3, w2, w24
        add     x3, x23, x3, lsl #2     // x3 = current link
Lchain:
        ldr     w1, [x3]
        cbz     w1, Lfound
        add     x4, x22, x1, lsl #NODE_SHIFT
        ldr     w5, [x4, #N_HASH]
        cmp     w5, w2
        b.ne    Lnext
        ldp     w5, w8, [x4, #N_KOFF]   // w5 = key offset, w8 = key length
        cmp     x8, x6
        b.ne    Lnext
        add     x5, x21, x5
        mov     x0, x7
5:      subs    x8, x8, #8              // compare 8-byte blocks
        b.lo    6f
        ldr     x16, [x0], #8
        ldr     x17, [x5], #8
        cmp     x16, x17
        b.ne    Lnext
        b       5b
6:      adds    x8, x8, #8              // then the tail
        b.eq    Lfound
7:      ldrb    w16, [x0], #1
        ldrb    w17, [x5], #1
        cmp     w16, w17
        b.ne    Lnext
        subs    x8, x8, #1
        b.ne    7b
Lfound:
        mov     x0, x3
        ret
Lnext:
        add     x3, x4, #N_HNEXT
        b       Lchain

// ---------------------------------------------------------------------------
// hash_remove(w0 = index): unlink a node known to be in the table. Leaf.
// ---------------------------------------------------------------------------
        .p2align 2
hash_remove:
        add     x1, x22, x0, lsl #NODE_SHIFT
        ldr     w2, [x1, #N_HASH]
        and     w2, w2, w24
        add     x2, x23, x2, lsl #2
1:      ldr     w3, [x2]
        cmp     w3, w0
        b.eq    2f
        add     x2, x22, x3, lsl #NODE_SHIFT
        add     x2, x2, #N_HNEXT
        b       1b
2:      ldr     w3, [x1, #N_HNEXT]
        str     w3, [x2]
        ret

// ---------------------------------------------------------------------------
// Recency list primitives. w0 = node index (upper half of x0 is zero).
// Leaf; clobber x1-x4.
// ---------------------------------------------------------------------------
        .p2align 2
list_unlink:
        add     x1, x22, x0, lsl #NODE_SHIFT
        ldp     w2, w3, [x1, #N_PREV]
        add     x4, x22, x2, lsl #NODE_SHIFT
        str     w3, [x4, #N_NEXT]
        add     x4, x22, x3, lsl #NODE_SHIFT
        str     w2, [x4, #N_PREV]
        ret

        .p2align 2
list_push_front:
        add     x1, x22, x0, lsl #NODE_SHIFT
        ldr     w3, [x22, #N_NEXT]      // current MRU
        stp     wzr, w3, [x1, #N_PREV]
        add     x4, x22, x3, lsl #NODE_SHIFT
        str     w0, [x4, #N_PREV]
        str     w0, [x22, #N_NEXT]
        ret

// touch(w9 = index): make a node the MRU. Leaf; clobbers x0-x4.
        .p2align 2
touch:
        ldr     w0, [x22, #N_NEXT]
        cmp     w0, w9
        b.eq    1f                      // already most recent
        add     x1, x22, x9, lsl #NODE_SHIFT
        ldp     w2, w3, [x1, #N_PREV]
        add     x4, x22, x2, lsl #NODE_SHIFT
        str     w3, [x4, #N_NEXT]
        add     x4, x22, x3, lsl #NODE_SHIFT
        str     w2, [x4, #N_PREV]
        stp     wzr, w0, [x1, #N_PREV]
        add     x4, x22, x0, lsl #NODE_SHIFT
        str     w9, [x4, #N_PREV]
        str     w9, [x22, #N_NEXT]
1:      ret

// ---------------------------------------------------------------------------
// die_oom: report allocation failure and exit(1).
// ---------------------------------------------------------------------------
        .p2align 2
die_oom:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        mov     w0, #2
        adrp    x1, Loom_msg@PAGE
        add     x1, x1, Loom_msg@PAGEOFF
        mov     x2, #(Loom_msg_end - Loom_msg)
        bl      _write
        mov     w0, #1
        bl      _exit

        .section __TEXT,__const
Loom_msg:
        .ascii  "lru: out of memory\n"
Loom_msg_end:

        .section __DATA,__data
        .p2align 3
// [0] free-list head (0 = empty), [4] next never-used node index.
_pool_state:
        .long   0, 1

        .zerofill __DATA,__bss,_outbuf,OUT_SIZE,4
