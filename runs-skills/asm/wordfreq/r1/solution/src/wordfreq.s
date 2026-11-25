// wordfreq: print the 10 most frequent ASCII words read from stdin.
//
// Design
//   1. Slurp stdin into one growable heap buffer.
//   2. Scan it once: fold letters to lowercase in place and count each word in
//      an open-addressing hash table (linear probing, load factor <= 1/2).
//      Words are referenced by offset into the input buffer; nothing is copied.
//   3. One pass over the table keeps a sorted top-10 by insertion.
//   4. Print "<count> <word>\n" lines.
//
// Hash table entry (16 bytes, empty when count == 0):
//   +0  u32 offset of word in input buffer
//   +4  u32 word length
//   +8  u32 hash (CRC32-C of the lowercased word)
//   +12 u32 count

        .equ    ENTRY_SHIFT, 4          // log2(sizeof entry)
        .equ    E_OFF,   0
        .equ    E_LEN,   4
        .equ    E_HASH,  8
        .equ    E_COUNT, 12

        .equ    INIT_BITS, 16           // initial table: 65536 slots
        .equ    INIT_BUF, (1 << 22)     // initial input buffer: 4 MiB
        .equ    BUF_PAD, 16             // slack kept free at end of buffer
        .equ    TOPN, 10
        .equ    EINTR, 4

// Fibonacci hashing multiplier (2^32 / phi) materialised into a w register.
.macro  LOAD_GOLDEN reg
        movz    \reg, #0x79b9
        movk    \reg, #0x9e37, lsl #16
.endm

        .text

// ---------------------------------------------------------------------------
// int main(void)
//   x19 input buffer      x20 bytes in buffer     x21 buffer capacity
//   x22 hash table        x23 slot mask           x24 occupied slots
//   x25 index shift (32 - bits)                    w26 golden multiplier
//   x27 scan cursor       x28 scan end
// ---------------------------------------------------------------------------
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

        // ---- 1. read all of stdin -----------------------------------------
        mov     x21, #INIT_BUF
        mov     x0, x21
        bl      _malloc
        cbz     x0, Loom
        mov     x19, x0
        mov     x20, #0
Lread:
        sub     x2, x21, x20
        sub     x2, x2, #BUF_PAD
        cbnz    x2, 1f
        lsl     x21, x21, #1                    // full: double capacity
        mov     x0, x19
        mov     x1, x21
        bl      _realloc
        cbz     x0, Loom
        mov     x19, x0
        b       Lread
1:      mov     w0, #0
        add     x1, x19, x20
        bl      _read
        cmp     x0, #0
        b.gt    2f
        b.eq    Lread_done
        bl      ___error                        // read failed: retry on EINTR
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lread
        b       Lread_done                      // other errors: treat as EOF
2:      add     x20, x20, x0
        b       Lread
Lread_done:

        // ---- 2. hash table --------------------------------------------------
        mov     x0, #(1 << INIT_BITS)
        mov     x1, #(1 << ENTRY_SHIFT)
        bl      _calloc
        cbz     x0, Loom
        mov     x22, x0
        mov     x23, #((1 << INIT_BITS) - 1)
        mov     x24, #0
        mov     x25, #(32 - INIT_BITS)
        LOAD_GOLDEN w26

        mov     x27, x19
        add     x28, x19, x20

        // ---- 3. scan words --------------------------------------------------
Lskip:                                          // find first letter of a word
        cmp     x27, x28
        b.hs    Lscan_done
        ldrb    w9, [x27], #1
        orr     w9, w9, #0x20
        sub     w10, w9, #'a'
        cmp     w10, #26
        b.hs    Lskip
        sub     x11, x27, #1                    // x11 = word start
        strb    w9, [x11]
        mov     w2, #0
        crc32cb w2, w2, w9                      // w2 = running hash
Lword:
        cmp     x27, x28
        b.hs    Lword_end
        ldrb    w9, [x27]
        orr     w9, w9, #0x20
        sub     w10, w9, #'a'
        cmp     w10, #26
        b.hs    Lword_end
        strb    w9, [x27], #1
        crc32cb w2, w2, w9
        b       Lword
Lword_end:
        sub     x12, x27, x11                   // x12 = word length

        // probe for (x11, x12, w2)
        mul     w3, w2, w26
        lsr     w3, w3, w25
Lprobe:
        add     x4, x22, x3, lsl #ENTRY_SHIFT
        ldr     w5, [x4, #E_COUNT]
        cbz     w5, Lnew_word
        ldp     w6, w7, [x4, #E_LEN]            // w6 = len, w7 = hash
        cmp     w7, w2
        ccmp    w6, w12, #0, eq
        b.ne    Lprobe_next
        ldr     w6, [x4, #E_OFF]
        add     x6, x19, x6                     // stored word
        mov     x7, x11
        mov     x8, x12
1:      ldrb    w9, [x6], #1
        ldrb    w10, [x7], #1
        cmp     w9, w10
        b.ne    Lprobe_next
        subs    x8, x8, #1
        b.ne    1b
        add     w5, w5, #1                      // hit: bump the count
        str     w5, [x4, #E_COUNT]
        b       Lskip
Lprobe_next:
        add     w3, w3, #1
        and     w3, w3, w23
        b       Lprobe
Lnew_word:
        sub     x6, x11, x19
        stp     w6, w12, [x4, #E_OFF]
        mov     w5, #1
        stp     w2, w5, [x4, #E_HASH]
        add     x24, x24, #1
        cmp     x23, x24, lsl #1                // grow once more than half full
        b.hs    Lskip
        mov     x0, x22
        add     x1, x23, #1
        sub     w2, w25, #1
        bl      _table_rehash
        cbz     x0, Loom
        mov     x22, x0
        lsl     x23, x23, #1
        orr     x23, x23, #1
        sub     x25, x25, #1
        b       Lskip
Lscan_done:

        // ---- 4. select top 10 (sorted entry pointers at [sp]) --------------
        sub     sp, sp, #(TOPN * 8 + 16)        // 96 bytes: 10 pointers + pad
        mov     x27, #0                         // x27 = entries in top list
        mov     x28, x22                        // x28 = cursor over table
        add     x24, x23, #1                    // x24 = slots remaining
Lsel_loop:
        cbz     x24, Lsel_done
        sub     x24, x24, #1
        mov     x20, x28
        add     x28, x28, #(1 << ENTRY_SHIFT)
        ldr     w9, [x20, #E_COUNT]
        cbz     w9, Lsel_loop
        mov     x21, x27                        // x21 = insertion position
        cmp     x27, #TOPN
        b.lo    1f
        mov     x0, x20
        ldr     x1, [sp, #((TOPN - 1) * 8)]
        mov     x2, x19
        bl      _entry_before
        cbz     w0, Lsel_loop                   // not better than current 10th
        mov     x21, #(TOPN - 1)
        b       2f
1:      add     x27, x27, #1
2:      cbz     x21, 3f                         // shift worse entries down
        sub     x9, x21, #1
        ldr     x1, [sp, x9, lsl #3]
        mov     x0, x20
        mov     x2, x19
        bl      _entry_before
        cbz     w0, 3f
        sub     x9, x21, #1
        ldr     x1, [sp, x9, lsl #3]
        str     x1, [sp, x21, lsl #3]
        mov     x21, x9
        b       2b
3:      str     x20, [sp, x21, lsl #3]
        b       Lsel_loop
Lsel_done:

        // ---- 5. print -------------------------------------------------------
        mov     x24, #0
Lprint:
        cmp     x24, x27
        b.hs    Lexit
        ldr     x20, [sp, x24, lsl #3]
        add     x24, x24, #1
        sub     sp, sp, #32                     // line prefix scratch
        add     x1, sp, #32                     // build "<count> " backwards
        mov     w9, #' '
        strb    w9, [x1, #-1]!
        ldr     w0, [x20, #E_COUNT]
        mov     w10, #10
1:      udiv    w11, w0, w10
        msub    w12, w11, w10, w0
        add     w12, w12, #'0'
        strb    w12, [x1, #-1]!
        mov     w0, w11
        cbnz    w0, 1b
        mov     x0, x1
        add     x1, sp, #32
        sub     x1, x1, x0
        bl      _write_all
        add     sp, sp, #32
        ldp     w0, w1, [x20, #E_OFF]
        add     x0, x19, x0
        bl      _write_all
        adrp    x0, Lnewline@PAGE
        add     x0, x0, Lnewline@PAGEOFF
        mov     x1, #1
        bl      _write_all
        b       Lprint

Lexit:
        mov     w0, #0
        sub     sp, x29, #80
        ldp     x29, x30, [sp, #80]
        ldp     x20, x19, [sp, #64]
        ldp     x22, x21, [sp, #48]
        ldp     x24, x23, [sp, #32]
        ldp     x26, x25, [sp, #16]
        ldp     x28, x27, [sp, #0]
        add     sp, sp, #96
        ret

Loom:
        mov     w0, #2                          // stderr
        adrp    x1, Loom_msg@PAGE
        add     x1, x1, Loom_msg@PAGEOFF
        mov     x2, #(Loom_msg_end - Loom_msg)
        bl      _write
        mov     w0, #1
        bl      _exit
        .cfi_endproc

// ---------------------------------------------------------------------------
// entry *table_rehash(entry *old, size_t oldcap, uint32_t newshift)
//   Allocates a table of 2*oldcap slots, reinserts every occupied entry using
//   its stored hash, frees the old table. Returns NULL on allocation failure.
// ---------------------------------------------------------------------------
        .p2align 2
_table_rehash:
        .cfi_startproc
        sub     sp, sp, #48
        stp     x22, x21, [sp, #0]
        stp     x20, x19, [sp, #16]
        stp     x29, x30, [sp, #32]
        add     x29, sp, #32
        .cfi_def_cfa w29, 16
        .cfi_offset w30, -8
        .cfi_offset w29, -16
        .cfi_offset w19, -24
        .cfi_offset w20, -32
        .cfi_offset w21, -40
        .cfi_offset w22, -48
        mov     x19, x0
        mov     x20, x1
        mov     w21, w2
        lsl     x0, x1, #1
        mov     x1, #(1 << ENTRY_SHIFT)
        bl      _calloc
        cbz     x0, Lrh_ret
        mov     x22, x0

        lsl     x9, x20, #1
        sub     x9, x9, #1                      // x9 = new mask
        LOAD_GOLDEN w10
        mov     x11, x19                        // x11 = old cursor
        mov     x12, x20                        // x12 = slots remaining
Lrh_loop:
        ldp     x13, x14, [x11], #(1 << ENTRY_SHIFT)
        lsr     x15, x14, #32                   // count
        cbz     w15, Lrh_next
        mul     w15, w14, w10                   // w14 = hash
        lsr     w15, w15, w21
1:      add     x16, x22, x15, lsl #ENTRY_SHIFT
        ldr     w17, [x16, #E_COUNT]
        cbz     w17, 2f
        add     w15, w15, #1
        and     w15, w15, w9
        b       1b
2:      stp     x13, x14, [x16]
Lrh_next:
        subs    x12, x12, #1
        b.ne    Lrh_loop

        mov     x0, x19
        bl      _free
        mov     x0, x22
Lrh_ret:
        ldp     x29, x30, [sp, #32]
        ldp     x20, x19, [sp, #16]
        ldp     x22, x21, [sp, #0]
        add     sp, sp, #48
        ret
        .cfi_endproc

// ---------------------------------------------------------------------------
// int entry_before(const entry *a, const entry *b, const char *base)
//   1 if a ranks ahead of b: higher count, then lexicographically smaller word.
//   Leaf function.
// ---------------------------------------------------------------------------
        .p2align 2
_entry_before:
        .cfi_startproc
        ldr     w3, [x0, #E_COUNT]
        ldr     w4, [x1, #E_COUNT]
        cmp     w3, w4
        b.ne    Lcmp_done                       // hi -> a first
        ldp     w3, w5, [x0, #E_OFF]
        ldp     w4, w6, [x1, #E_OFF]
        add     x3, x2, x3
        add     x4, x2, x4
        cmp     w5, w6
        csel    w7, w5, w6, lo                  // w7 = min length
1:      cbz     w7, Lcmp_len
        ldrb    w8, [x3], #1
        ldrb    w9, [x4], #1
        sub     w7, w7, #1
        cmp     w8, w9
        b.eq    1b
        cset    w0, lo
        ret
Lcmp_len:
        cmp     w5, w6
        cset    w0, lo                          // shorter prefix sorts first
        ret
Lcmp_done:
        cset    w0, hi
        ret
        .cfi_endproc

// ---------------------------------------------------------------------------
// void write_all(const void *p, size_t n) - write n bytes to stdout,
//   retrying on short writes and EINTR; gives up silently on other errors.
// ---------------------------------------------------------------------------
        .p2align 2
_write_all:
        .cfi_startproc
        sub     sp, sp, #32
        stp     x20, x19, [sp, #0]
        stp     x29, x30, [sp, #16]
        add     x29, sp, #16
        .cfi_def_cfa w29, 16
        .cfi_offset w30, -8
        .cfi_offset w29, -16
        .cfi_offset w19, -24
        .cfi_offset w20, -32
        mov     x19, x0
        mov     x20, x1
Lwa_loop:
        cbz     x20, Lwa_ret
        mov     w0, #1
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.lt    1f
        add     x19, x19, x0
        sub     x20, x20, x0
        b       Lwa_loop
1:      bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lwa_loop
Lwa_ret:
        ldp     x29, x30, [sp, #16]
        ldp     x20, x19, [sp, #0]
        add     sp, sp, #32
        ret
        .cfi_endproc

        .section __TEXT,__cstring,cstring_literals
Lnewline:
        .asciz  "\n"
Loom_msg:
        .ascii  "wordfreq: out of memory\n"
Loom_msg_end:

.subsections_via_symbols
