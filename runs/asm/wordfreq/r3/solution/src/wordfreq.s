// wordfreq — print the 10 most frequent ASCII words read from stdin.
//
// Strategy
//   1. Slurp all of stdin into one growable heap buffer.
//   2. Scan it once; letters are folded to lowercase in place, so every
//      word is a (ptr, len) slice of the buffer — no per-word allocation.
//   3. Count words in an open-addressed, linear-probing hash table
//      (power-of-two capacity, kept at most half full).
//   4. Select the top 10 with a bounded insertion sort over the table.
//   5. Print "<count> <word>\n" lines.
//
// Hash table entry layout (32 bytes):
//   +0  ptr   pointer to the word bytes (0 = empty slot)
//   +8  len   word length
//   +16 hash  full 64-bit FNV-1a hash
//   +24 count occurrences

        .set    ENT_PTR,   0
        .set    ENT_LEN,   8
        .set    ENT_HASH,  16
        .set    ENT_COUNT, 24
        .set    ENT_SHIFT, 5            // log2(entry size)

        .set    INIT_BUF,  (1 << 20)    // initial input buffer, bytes
        .set    INIT_TAB,  (1 << 14)    // initial table capacity, entries
        .set    TOP_N,     10
        .set    EINTR,     4

        .set    FNV_OFFSET_LO, 0x2325   // 0xcbf29ce484222325
        .set    FNV_OFFSET_M1, 0x8422
        .set    FNV_OFFSET_M2, 0x9ce4
        .set    FNV_OFFSET_HI, 0xcbf2
        .set    FNV_PRIME_LO,  0x01b3   // 0x00000100000001b3
        .set    FNV_PRIME_HI,  0x0100   // bits 32..47

// ---------------------------------------------------------------------------
        .section __DATA,__bss
        .p2align 3
table:  .space  8                       // entry array
mask:   .space  8                       // capacity - 1
used:   .space  8                       // occupied slots

// ---------------------------------------------------------------------------
        .section __TEXT,__text,regular,pure_instructions

// int main(void)
        .globl  _main
        .p2align 2
_main:
        stp     x29, x30, [sp, #-176]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]
        stp     x27, x28, [sp, #80]
        // [sp, #96 .. #176): top-10 array of entry pointers

        // ---- 1. read all of stdin -----------------------------------------
        mov     x21, #INIT_BUF          // x21 = capacity
        mov     x0, x21
        bl      _malloc
        cbz     x0, Lfatal
        mov     x19, x0                 // x19 = buffer
        mov     x20, #0                 // x20 = bytes read
Lread:
        subs    x2, x21, x20
        b.ne    1f
        lsl     x21, x21, #1
        mov     x0, x19
        mov     x1, x21
        bl      _realloc
        cbz     x0, Lfatal
        mov     x19, x0
        sub     x2, x21, x20
1:      mov     w0, #0                  // STDIN_FILENO
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
        // Any other error: treat what we have as the whole input.
Lread_done:

        // ---- 2. hash table ------------------------------------------------
        mov     x0, #INIT_TAB
        mov     x1, #(1 << ENT_SHIFT)
        bl      _calloc
        cbz     x0, Lfatal
        adrp    x8, table@PAGE
        add     x8, x8, table@PAGEOFF
        mov     x9, #(INIT_TAB - 1)
        stp     x0, x9, [x8]            // table, mask (used is already 0)

        // ---- 3. scan ------------------------------------------------------
        mov     x25, x19                // x25 = cursor
        add     x26, x19, x20           // x26 = end
        mov     x20, #FNV_PRIME_LO      // x20 = FNV prime (buffer len no longer needed)
        movk    x20, #FNV_PRIME_HI, lsl #32
        mov     x21, #FNV_OFFSET_LO     // x21 = FNV offset basis
        movk    x21, #FNV_OFFSET_M1, lsl #16
        movk    x21, #FNV_OFFSET_M2, lsl #32
        movk    x21, #FNV_OFFSET_HI, lsl #48
Lskip:
        cmp     x25, x26
        b.hs    Lscan_done
        ldrb    w0, [x25]
        orr     w1, w0, #0x20           // fold; a letter iff result is 'a'..'z'
        sub     w2, w1, #'a'
        cmp     w2, #25
        b.ls    Lword_start
        add     x25, x25, #1
        b       Lskip
Lword_start:
        mov     x27, x25                // x27 = word start
        mov     x28, x21                // x28 = running hash
Lword:
        strb    w1, [x25], #1           // store lowercase byte in place
        eor     x28, x28, x1
        mul     x28, x28, x20
        cmp     x25, x26
        b.hs    Lword_end
        ldrb    w0, [x25]
        orr     w1, w0, #0x20
        sub     w2, w1, #'a'
        cmp     w2, #25
        b.ls    Lword
Lword_end:
        mov     x0, x27                 // word is [x27, x25)
        sub     x1, x25, x27
        mov     x2, x28
        bl      count_word
        b       Lskip                   // cursor is on a separator or at end
Lscan_done:

        // ---- 4. select top 10 ---------------------------------------------
        adrp    x8, table@PAGE
        add     x8, x8, table@PAGEOFF
        ldp     x22, x23, [x8]          // x22 = table, x23 = mask
        add     x23, x22, x23, lsl #ENT_SHIFT
        add     x23, x23, #(1 << ENT_SHIFT) // x23 = table end
        add     x24, sp, #96            // x24 = top array
        mov     x25, #0                 // x25 = number selected
Lsel:
        cmp     x22, x23
        b.hs    Lsel_done
        ldr     x9, [x22, #ENT_PTR]
        cbz     x9, Lsel_next
        mov     x26, x25                // x26 = insertion slot
        cmp     x25, #TOP_N
        b.lo    1f
        mov     x0, x22                 // full: must beat the current 10th
        ldr     x1, [x24, #(8 * (TOP_N - 1))]
        bl      ranks_before
        cbz     w0, Lsel_next
        mov     x26, #(TOP_N - 1)
        b       Lshift
1:      add     x25, x25, #1
Lshift:
        cbz     x26, Lplace
        sub     x9, x26, #1
        ldr     x27, [x24, x9, lsl #3]
        mov     x0, x22
        mov     x1, x27
        bl      ranks_before
        cbz     w0, Lplace
        str     x27, [x24, x26, lsl #3]
        sub     x26, x26, #1
        b       Lshift
Lplace:
        str     x22, [x24, x26, lsl #3]
Lsel_next:
        add     x22, x22, #(1 << ENT_SHIFT)
        b       Lsel
Lsel_done:

        // ---- 5. print -----------------------------------------------------
        mov     x22, #0
Lprint:
        cmp     x22, x25
        b.hs    Lexit
        ldr     x23, [x24, x22, lsl #3]
        ldr     x0, [x23, #ENT_COUNT]
        bl      print_count
        ldp     x0, x1, [x23, #ENT_PTR] // ptr, len
        bl      write_all
        adrp    x0, Lnewline@PAGE
        add     x0, x0, Lnewline@PAGEOFF
        mov     x1, #1
        bl      write_all
        add     x22, x22, #1
        b       Lprint

Lexit:
        mov     w0, #0
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #176
        ret

Lfatal:
        mov     w0, #2                  // STDERR_FILENO
        adrp    x1, Loom@PAGE
        add     x1, x1, Loom@PAGEOFF
        mov     x2, #(Loom_end - Loom)
        bl      _write
        mov     w0, #1
        bl      _exit

// ---------------------------------------------------------------------------
// void count_word(const char *ptr, size_t len, uint64_t hash)
// Increment the count for the word, inserting it if new.
        .p2align 2
count_word:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        mov     x19, x0                 // ptr
        mov     x20, x1                 // len
        mov     x21, x2                 // hash
        adrp    x8, table@PAGE
        add     x8, x8, table@PAGEOFF
        ldp     x22, x23, [x8]          // table, mask
        eor     x24, x21, x21, lsr #32  // mix high bits into the index
        and     x24, x24, x23           // x24 = slot index
Lprobe:
        add     x9, x22, x24, lsl #ENT_SHIFT
        ldr     x0, [x9, #ENT_PTR]
        cbz     x0, Lnew
        ldp     x10, x11, [x9, #ENT_LEN] // len, hash
        cmp     x10, x20
        ccmp    x11, x21, #0, eq
        b.ne    Lprobe_next
        mov     x1, x19
        mov     x2, x20
        bl      _memcmp
        cbnz    w0, Lprobe_next
        add     x9, x22, x24, lsl #ENT_SHIFT
        ldr     x10, [x9, #ENT_COUNT]
        add     x10, x10, #1
        str     x10, [x9, #ENT_COUNT]
        b       Lcw_ret
Lprobe_next:
        add     x24, x24, #1
        and     x24, x24, x23
        b       Lprobe
Lnew:
        stp     x19, x20, [x9, #ENT_PTR]
        mov     x10, #1
        stp     x21, x10, [x9, #ENT_HASH]
        adrp    x8, table@PAGE
        add     x8, x8, table@PAGEOFF
        ldr     x10, [x8, #16]
        add     x10, x10, #1
        str     x10, [x8, #16]
        cmp     x23, x10, lsl #1        // grow once more than half full
        b.hs    Lcw_ret
        bl      grow_table
Lcw_ret:
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ret

// ---------------------------------------------------------------------------
// void grow_table(void) — double the capacity and rehash every entry.
        .p2align 2
grow_table:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        adrp    x8, table@PAGE
        add     x8, x8, table@PAGEOFF
        ldp     x19, x20, [x8]          // old table, old mask
        add     x0, x20, #1
        lsl     x0, x0, #1              // new capacity
        mov     x1, #(1 << ENT_SHIFT)
        bl      _calloc
        cbz     x0, Lfatal
        mov     x21, x0                 // new table
        lsl     x22, x20, #1
        add     x22, x22, #1            // new mask
        mov     x9, x19                 // cursor over old table
        add     x10, x19, x20, lsl #ENT_SHIFT
        add     x10, x10, #(1 << ENT_SHIFT) // old end
Lrehash:
        cmp     x9, x10
        b.hs    Lrehash_done
        ldp     x12, x13, [x9, #ENT_PTR]
        cbz     x12, Lrehash_next
        ldp     x14, x15, [x9, #ENT_HASH]
        eor     x11, x14, x14, lsr #32
        and     x11, x11, x22
1:      add     x16, x21, x11, lsl #ENT_SHIFT
        ldr     x17, [x16, #ENT_PTR]
        cbz     x17, 2f
        add     x11, x11, #1
        and     x11, x11, x22
        b       1b
2:      stp     x12, x13, [x16, #ENT_PTR]
        stp     x14, x15, [x16, #ENT_HASH]
Lrehash_next:
        add     x9, x9, #(1 << ENT_SHIFT)
        b       Lrehash
Lrehash_done:
        mov     x0, x19
        bl      _free
        adrp    x8, table@PAGE
        add     x8, x8, table@PAGEOFF
        stp     x21, x22, [x8]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// ---------------------------------------------------------------------------
// bool ranks_before(const entry *a, const entry *b)
// True if a sorts before b: higher count first, then word ascending by bytes.
        .p2align 2
ranks_before:
        ldr     x9, [x0, #ENT_COUNT]
        ldr     x10, [x1, #ENT_COUNT]
        cmp     x9, x10
        b.ne    Lrb_count
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        ldr     x19, [x0, #ENT_LEN]
        ldr     x20, [x1, #ENT_LEN]
        ldr     x0, [x0, #ENT_PTR]
        ldr     x1, [x1, #ENT_PTR]
        cmp     x19, x20
        csel    x2, x19, x20, lo        // min length
        bl      _memcmp
        cmp     w0, #0
        b.ne    1f
        cmp     x19, x20                // common prefix: shorter first
1:      cset    w0, lt
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret
Lrb_count:
        cset    w0, hi
        ret

// ---------------------------------------------------------------------------
// void print_count(uint64_t n) — write "<n> " to stdout.
        .p2align 2
print_count:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        add     x1, sp, #48             // build digits backwards in [sp+16, sp+48)
        mov     w9, #' '
        strb    w9, [x1, #-1]!
        mov     x10, #10
1:      udiv    x11, x0, x10
        msub    x12, x11, x10, x0
        add     w12, w12, #'0'
        strb    w12, [x1, #-1]!
        mov     x0, x11
        cbnz    x0, 1b
        add     x2, sp, #48
        sub     x2, x2, x1
        mov     x0, x1
        mov     x1, x2
        bl      write_all
        ldp     x29, x30, [sp], #48
        ret

// ---------------------------------------------------------------------------
// void write_all(const void *buf, size_t len) — write fully to stdout.
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
        b.gt    1f
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lwa_loop
        b       Lwa_done                // unrecoverable (e.g. EPIPE): give up
1:      add     x19, x19, x0
        sub     x20, x20, x0
        b       Lwa_loop
Lwa_done:
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// ---------------------------------------------------------------------------
        .section __TEXT,__cstring,cstring_literals
Lnewline:
        .asciz  "\n"
Loom:
        .ascii  "wordfreq: out of memory\n"
Loom_end:

        .subsections_via_symbols
