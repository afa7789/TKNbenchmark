// wordfreq — print the 10 most frequent ASCII words read from stdin.
//
// AArch64 / macOS (Mach-O, Apple ABI).
//
// Design
//   1. Slurp all of stdin into one growable heap buffer (plus 16 bytes of
//      zeroed padding so 8-byte word compares may safely over-read).
//   2. Scan the buffer once.  Each word is lowercased in place while its
//      FNV-1a hash is computed, so stored keys are simply (offset, length)
//      references into the buffer — no per-word allocation or copying.
//   3. Words are counted in an open-addressing hash table with linear
//      probing (power-of-two capacity, grown at 3/4 load).
//   4. One pass over the table keeps a sorted top-10 by insertion.
//   5. The result is formatted into a single buffer and written out.
//
// Hash table entry (16 bytes):
//   +0  u32 offset of the word in the input buffer
//   +4  u32 length (0 marks an empty slot; real words have length >= 1)
//   +8  u32 hash
//   +12 u32 occurrence count

        .equ    ENT_OFF,   0
        .equ    ENT_LEN,   4
        .equ    ENT_HASH,  8
        .equ    ENT_CNT,   12
        .equ    ENT_SHIFT, 4            // log2(entry size)

        .equ    TOP_N,        10
        .equ    INIT_BUFCAP,  (1 << 24) // 16 MiB input buffer to start
        .equ    BUF_PAD,      16        // over-read slack after the data
        .equ    MIN_READ,     65536     // grow the buffer below this room
        .equ    INIT_SLOTS,   (1 << 16)
        .equ    EINTR,        4
        .equ    TOP_BYTES,    (TOP_N * 8)
        .equ    FRAME_LOCALS, (TOP_BYTES + 16)  // top[] + digit scratch

        .section __TEXT,__text,regular,pure_instructions

// ---------------------------------------------------------------------------
// int main(void)
//
// Callee-saved register roles:
//   x19 input buffer base         x20 input end (base + length)
//   x21 cursor / scratch          x22 hash table base
//   x23 table mask (slots - 1)    x24 number of distinct words
//   x25 grow threshold / top-N    x26 FNV prime / top array
//   x27 buffer capacity / index   x28 FNV offset basis
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

// ---- 1. read all of stdin -------------------------------------------------
        mov     x27, #INIT_BUFCAP
        mov     x0, x27
        bl      _malloc
        cbz     x0, Lout_of_memory
        mov     x19, x0
        mov     x21, #0                 // bytes read so far

Lread_loop:
        sub     x2, x27, x21
        sub     x2, x2, #BUF_PAD        // room available for read()
        cmp     x2, #MIN_READ
        b.hs    Lread_some
        lsl     x27, x27, #1
        mov     x0, x19
        mov     x1, x27
        bl      _realloc
        cbz     x0, Lout_of_memory
        mov     x19, x0
        b       Lread_loop
Lread_some:
        mov     w0, #0                  // STDIN_FILENO
        add     x1, x19, x21
        bl      _read
        cmp     x0, #0
        b.le    Lread_short
        add     x21, x21, x0
        b       Lread_loop
Lread_short:
        b.eq    Lread_done              // EOF
        bl      ___error                // read error: retry on EINTR,
        ldr     w0, [x0]                // otherwise treat as end of input
        cmp     w0, #EINTR
        b.eq    Lread_loop
Lread_done:
        add     x20, x19, x21
        stp     xzr, xzr, [x20]         // zero the over-read padding

// ---- 2. hash table --------------------------------------------------------
        mov     x0, #INIT_SLOTS
        mov     x1, #(1 << ENT_SHIFT)
        bl      _calloc
        cbz     x0, Lout_of_memory
        mov     x22, x0
        mov     x23, #(INIT_SLOTS - 1)
        mov     x24, #0
        mov     x25, #(INIT_SLOTS / 4 * 3)

        movz    x26, #0x01b3            // FNV-1a 64-bit prime 0x100000001b3
        movk    x26, #0x0100, lsl #32
        movz    x28, #0x2325            // offset basis 0xcbf29ce484222325
        movk    x28, #0x8422, lsl #16
        movk    x28, #0x9ce4, lsl #32
        movk    x28, #0xcbf2, lsl #48

// ---- 3. scan and count ----------------------------------------------------
        mov     x21, x19
Lscan:                                  // skip separators
        cmp     x21, x20
        b.hs    Lscan_done
        ldrb    w10, [x21]
        orr     w10, w10, #0x20         // fold case
        sub     w10, w10, #'a'
        cmp     w10, #26                // letter iff (c|0x20)-'a' < 26
        b.lo    Lword_start
        add     x21, x21, #1
        b       Lscan

Lword_start:
        mov     x11, x21                // word start
        mov     x9, x28                 // hash state
Lword_loop:                             // w10 = letter index 0..25
        add     w10, w10, #'a'
        strb    w10, [x21], #1          // store lowercase in place
        eor     x9, x9, x10
        mul     x9, x9, x26
        cmp     x21, x20
        b.hs    Lword_end
        ldrb    w10, [x21]
        orr     w10, w10, #0x20
        sub     w10, w10, #'a'
        cmp     w10, #26
        b.lo    Lword_loop
Lword_end:
        eor     x9, x9, x9, lsr #32     // fold to 32 bits (w9)
        sub     x12, x21, x11           // w12 = length
        sub     x13, x11, x19           // w13 = offset
        and     w14, w9, w23            // w14 = slot index

Lprobe:
        add     x15, x22, x14, lsl #ENT_SHIFT
        ldp     w0, w1, [x15, #ENT_OFF] // w0 = offset, w1 = length
        cbz     w1, Linsert_new
        ldr     w2, [x15, #ENT_HASH]
        cmp     w2, w9
        ccmp    w1, w12, #0, eq         // hash and length must both match
        b.ne    Lprobe_next

        add     x3, x19, x0             // stored key
        mov     x4, x11                 // current word
        mov     w5, w12
Lkey_cmp:                               // compare 8 bytes at a time
        ldr     x6, [x3], #8
        ldr     x7, [x4], #8
        eor     x6, x6, x7
        subs    w5, w5, #8
        b.le    Lkey_tail
        cbnz    x6, Lprobe_next
        b       Lkey_cmp
Lkey_tail:                              // w5 = -(bytes past the key) in -7..0
        neg     w5, w5
        lsl     w5, w5, #3
        lsl     x6, x6, x5              // discard bytes beyond the key
        cbnz    x6, Lprobe_next

        ldr     w2, [x15, #ENT_CNT]     // existing word: bump its count
        add     w2, w2, #1
        str     w2, [x15, #ENT_CNT]
        b       Lscan

Lprobe_next:
        add     w14, w14, #1
        and     w14, w14, w23
        b       Lprobe

Linsert_new:
        stp     w13, w12, [x15, #ENT_OFF]
        mov     w2, #1
        stp     w9, w2, [x15, #ENT_HASH]
        add     x24, x24, #1
        cmp     x24, x25
        b.lo    Lscan

        mov     x0, x22                 // load factor reached: double
        add     x1, x23, #1
        bl      ht_grow
        mov     x22, x0
        add     x23, x23, #1
        lsl     x23, x23, #1            // new slot count
        add     x25, x23, x23, lsl #1
        lsr     x25, x25, #2            // threshold = 3/4 of slots
        sub     x23, x23, #1
        b       Lscan

Lscan_done:
// ---- 4. select the top 10 -------------------------------------------------
        sub     sp, sp, #FRAME_LOCALS   // top[] of entry pointers, sorted
        mov     x26, sp
        mov     x25, #0                 // entries in top[]
        mov     x20, x22                // table cursor
        add     x21, x23, #1
        add     x21, x22, x21, lsl #ENT_SHIFT   // table end

Lsel_loop:
        cmp     x20, x21
        b.hs    Lsel_done
        ldr     w0, [x20, #ENT_LEN]
        cbz     w0, Lsel_next
        cmp     x25, #TOP_N
        b.lo    Lsel_append
        mov     x0, x20                 // full: must beat the current last
        ldr     x1, [x26, #((TOP_N - 1) * 8)]
        mov     x2, x19
        bl      rank_before
        cbz     w0, Lsel_next
        mov     x27, #(TOP_N - 1)
        b       Lsel_shift
Lsel_append:
        mov     x27, x25
        add     x25, x25, #1
Lsel_shift:                             // insertion sort step, hole at x27
        cbz     x27, Lsel_place
        sub     x9, x27, #1
        ldr     x1, [x26, x9, lsl #3]
        mov     x0, x20
        mov     x2, x19
        bl      rank_before
        cbz     w0, Lsel_place
        sub     x9, x27, #1
        ldr     x1, [x26, x9, lsl #3]
        str     x1, [x26, x27, lsl #3]
        mov     x27, x9
        b       Lsel_shift
Lsel_place:
        str     x20, [x26, x27, lsl #3]
Lsel_next:
        add     x20, x20, #16
        b       Lsel_loop

Lsel_done:
        cbz     x25, Lexit

// ---- 5. format and write the result --------------------------------------
        mov     x0, #0                  // size: per line, len + 10 digits +
        mov     x9, #0                  // space + newline (<= 12 extra)
Lsize_loop:
        ldr     x1, [x26, x9, lsl #3]
        ldr     w1, [x1, #ENT_LEN]
        add     x0, x0, x1
        add     x0, x0, #12
        add     x9, x9, #1
        cmp     x9, x25
        b.lo    Lsize_loop
        bl      _malloc
        cbz     x0, Lout_of_memory
        mov     x24, x0                 // output buffer
        mov     x21, x0                 // output cursor
        mov     x27, #0                 // line index
        mov     w10, #10

Lfmt_loop:
        ldr     x20, [x26, x27, lsl #3]
        ldr     w1, [x20, #ENT_CNT]
        add     x2, sp, #FRAME_LOCALS   // end of the digit scratch
        sub     x3, x2, #1              // emit digits backwards
Lutoa:
        udiv    w4, w1, w10
        msub    w5, w4, w10, w1
        add     w5, w5, #'0'
        strb    w5, [x3], #-1
        mov     w1, w4
        cbnz    w1, Lutoa
        add     x3, x3, #1              // first digit
Lcopy_digits:
        ldrb    w5, [x3], #1
        strb    w5, [x21], #1
        cmp     x3, x2
        b.lo    Lcopy_digits
        mov     w5, #' '
        strb    w5, [x21], #1

        ldp     w1, w2, [x20, #ENT_OFF] // word offset, length
        mov     x0, x21
        add     x1, x19, x1
        add     x21, x21, x2
        bl      _memcpy
        mov     w5, #'\n'
        strb    w5, [x21], #1
        mov     w10, #10
        add     x27, x27, #1
        cmp     x27, x25
        b.lo    Lfmt_loop

        mov     x0, x24
        sub     x1, x21, x24
        bl      write_all

Lexit:
        add     sp, sp, #FRAME_LOCALS
        mov     w0, #0
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #96
        ret

Lout_of_memory:
        mov     w0, #2                  // STDERR_FILENO
        adrp    x1, Lmsg_oom@PAGE
        add     x1, x1, Lmsg_oom@PAGEOFF
        mov     x2, #(Lmsg_oom_end - Lmsg_oom)
        bl      _write
        mov     w0, #1
        bl      _exit

// ---------------------------------------------------------------------------
// void *ht_grow(void *old, size_t old_slots)
// Allocate a table with twice the slots, rehash every entry into it using
// the stored hash, free the old table and return the new one.
// ---------------------------------------------------------------------------
        .p2align 2
ht_grow:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        mov     x19, x0
        mov     x20, x1
        lsl     x0, x1, #1
        mov     x1, #(1 << ENT_SHIFT)
        bl      _calloc
        cbz     x0, Lout_of_memory
        mov     x21, x0
        lsl     x9, x20, #1
        sub     x9, x9, #1              // new mask
        mov     x10, x19
        add     x11, x19, x20, lsl #ENT_SHIFT
Lgrow_loop:
        cmp     x10, x11
        b.hs    Lgrow_done
        ldr     w12, [x10, #ENT_LEN]
        cbz     w12, Lgrow_next
        ldr     w13, [x10, #ENT_HASH]
        and     w13, w13, w9
Lgrow_probe:
        add     x14, x21, x13, lsl #ENT_SHIFT
        ldr     w15, [x14, #ENT_LEN]
        cbz     w15, Lgrow_store
        add     w13, w13, #1
        and     w13, w13, w9
        b       Lgrow_probe
Lgrow_store:
        ldp     x6, x7, [x10]
        stp     x6, x7, [x14]
Lgrow_next:
        add     x10, x10, #(1 << ENT_SHIFT)
        b       Lgrow_loop
Lgrow_done:
        mov     x0, x19
        bl      _free
        mov     x0, x21
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// ---------------------------------------------------------------------------
// int rank_before(entry *a, entry *b, const char *base)
// Returns 1 if a sorts before b: higher count first, then word ascending
// (byte order, a proper prefix sorts first).  Keys are distinct.
// ---------------------------------------------------------------------------
        .p2align 2
rank_before:
        ldr     w3, [x0, #ENT_CNT]
        ldr     w4, [x1, #ENT_CNT]
        cmp     w3, w4
        b.hi    Lrank_yes
        b.lo    Lrank_no
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        ldp     w5, w19, [x0, #ENT_OFF] // a: offset, length
        ldp     w6, w20, [x1, #ENT_OFF] // b: offset, length
        add     x0, x2, x5
        add     x1, x2, x6
        cmp     w19, w20
        csel    w2, w19, w20, lo        // min length
        bl      _memcmp
        cbnz    w0, Lrank_cmp
        cmp     w19, w20
        cset    w0, lo
        b       Lrank_ret
Lrank_cmp:
        lsr     w0, w0, #31             // negative => a < b
Lrank_ret:
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret
Lrank_yes:
        mov     w0, #1
        ret
Lrank_no:
        mov     w0, #0
        ret

// ---------------------------------------------------------------------------
// void write_all(const void *buf, size_t len)
// Write the whole buffer to stdout, retrying on short writes and EINTR.
// ---------------------------------------------------------------------------
        .p2align 2
write_all:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        mov     x19, x0
        mov     x20, x1
Lwa_loop:
        cbz     x20, Lwa_done
        mov     w0, #1                  // STDOUT_FILENO
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.le    Lwa_err
        add     x19, x19, x0
        sub     x20, x20, x0
        b       Lwa_loop
Lwa_err:
        b.eq    Lwa_done
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lwa_loop
Lwa_done:
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

        .section __TEXT,__cstring,cstring_literals
Lmsg_oom:
        .ascii  "wordfreq: out of memory\n"
Lmsg_oom_end:
