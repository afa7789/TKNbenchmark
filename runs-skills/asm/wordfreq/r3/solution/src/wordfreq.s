// wordfreq — print the 10 most frequent ASCII words read from stdin.
//
// Algorithm
//   1. Slurp stdin into one growable heap buffer.
//   2. Scan it once: every maximal run of [A-Za-z] is lowercased in place and
//      hashed (FNV-1a/64 + multiplicative finaliser) on the fly, then counted in
//      an open-addressing hash table (linear probing, load factor <= 3/4).
//   3. One pass over the table keeps a sorted top-10 (count desc, word asc).
//   4. Format the result into one buffer and write(2) it.
//
// Hash table entry (16 bytes, little-endian):
//   +0  u32 offset of the word in the input buffer
//   +4  u32 word length
//   +8  u32 hash
//   +12 u32 count            (0 = empty slot)

        .equ    INIT_CAP,   1 << 20          // initial input buffer size
        .equ    SLACK,      16               // spare bytes past the buffer end
        .equ    INIT_SLOTS, 1 << 16          // initial table size (power of 2)
        .equ    TOPN,       10
        .equ    ENTRY_SZ,   16
        .equ    EINTR,      4

        // main's frame: [sp, #0..79] top-N pointer array, then saved registers
        .equ    TOP,        0
        .equ    FRAME,      176

        .text

// ---------------------------------------------------------------------------
// int main(void)
//
// Register use during the scan:
//   x19 input buffer          x20 FNV offset basis
//   x21 hash table            x22 finaliser multiplier
//   x23 table mask            x24 used slots
//   x25 grow threshold        x26 scan cursor
//   x27 scan end              x28 FNV prime
// ---------------------------------------------------------------------------
        .globl  _main
        .p2align 2
_main:
        .cfi_startproc
        sub     sp, sp, #FRAME
        stp     x28, x27, [sp, #80]
        stp     x26, x25, [sp, #96]
        stp     x24, x23, [sp, #112]
        stp     x22, x21, [sp, #128]
        stp     x20, x19, [sp, #144]
        stp     x29, x30, [sp, #160]
        add     x29, sp, #160
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

// ---- 1. read all of stdin: x19 = buffer, x20 = length, x22 = capacity ----
        mov     x22, #INIT_CAP
        add     x0, x22, #SLACK
        bl      _malloc
        cbz     x0, Lfail
        mov     x19, x0
        mov     x20, #0
Lread:
        cmp     x20, x22
        b.lo    1f
        lsl     x22, x22, #1                // buffer full: double it
        mov     x0, x19
        add     x1, x22, #SLACK
        bl      _realloc
        cbz     x0, Lfail
        mov     x19, x0
1:      mov     w0, #0                      // fd 0
        add     x1, x19, x20
        sub     x2, x22, x20
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
        b.eq    Lread                       // interrupted: retry
Lread_done:                                 // EOF (or unrecoverable error)
        add     x27, x19, x20               // scan end
        mov     x26, x19                    // scan cursor

// ---- hash table ----
        mov     x0, #INIT_SLOTS
        mov     x1, #ENTRY_SZ
        bl      _calloc
        cbz     x0, Lfail
        mov     x21, x0
        mov     x23, #(INIT_SLOTS - 1)
        mov     x24, #0
        mov     x25, #(INIT_SLOTS - INIT_SLOTS / 4)

        // hashing constants
        movz    x20, #0x2325                // FNV-1a/64 offset basis 0xcbf29ce484222325
        movk    x20, #0x8422, lsl #16
        movk    x20, #0x9ce4, lsl #32
        movk    x20, #0xcbf2, lsl #48
        movz    x28, #0x01b3                // FNV-1a/64 prime 0x100000001b3
        movk    x28, #0x0100, lsl #32
        movz    x22, #0x7c15                // golden ratio 0x9e3779b97f4a7c15
        movk    x22, #0x7f4a, lsl #16
        movk    x22, #0x79b9, lsl #32
        movk    x22, #0x9e37, lsl #48

// ---- 2. scan: skip separators ----
Lskip:
        cmp     x26, x27
        b.hs    Lscan_done
        ldrb    w2, [x26], #1
        orr     w3, w2, #0x20               // fold case
        sub     w3, w3, #'a'
        cmp     w3, #26
        b.hs    Lskip
        // first letter of a word
        sub     x4, x26, #1                 // x4 = word start
        add     w3, w3, #'a'
        strb    w3, [x4]
        eor     x5, x20, x3
        mul     x5, x5, x28                 // x5 = running hash
Lword:
        cmp     x26, x27
        b.hs    Lword_end
        ldrb    w2, [x26]
        orr     w3, w2, #0x20
        sub     w3, w3, #'a'
        cmp     w3, #26
        b.hs    Lword_end
        add     w3, w3, #'a'
        strb    w3, [x26], #1               // store lowercased letter
        eor     x5, x5, x3
        mul     x5, x5, x28
        b       Lword
Lword_end:
        sub     x6, x26, x4                 // x6 = word length
        mul     x5, x5, x22
        lsr     x5, x5, #32                 // w5 = 32-bit hash (high bits mix best)
        and     w7, w5, w23                 // w7 = slot index

// ---- lookup / insert ----
Lprobe:
        add     x8, x21, x7, lsl #4
        ldp     w9, w10, [x8]               // offset, length
        ldp     w11, w12, [x8, #8]          // hash, count
        cbz     w12, Lnew
        cmp     w11, w5
        ccmp    w10, w6, #0, eq
        b.ne    Lnext
        add     x15, x19, x9                // stored word
        mov     x16, x4                     // current word
        mov     x14, x6
Lcmp8:
        subs    x14, x14, #8
        b.lo    Lcmp_tail
        ldr     x0, [x15], #8
        ldr     x1, [x16], #8
        cmp     x0, x1
        b.ne    Lnext
        b       Lcmp8
Lcmp_tail:
        adds    x14, x14, #8
        b.eq    Lhit
Lcmp1:
        ldrb    w0, [x15], #1
        ldrb    w1, [x16], #1
        cmp     w0, w1
        b.ne    Lnext
        subs    x14, x14, #1
        b.ne    Lcmp1
Lhit:
        add     w12, w12, #1
        str     w12, [x8, #12]
        b       Lskip
Lnext:
        add     w7, w7, #1
        and     w7, w7, w23
        b       Lprobe
Lnew:
        sub     x9, x4, x19
        stp     w9, w6, [x8]
        mov     w12, #1
        stp     w5, w12, [x8, #8]
        add     x24, x24, #1
        cmp     x24, x25
        b.lo    Lskip
        mov     x0, x21                     // too full: double the table
        mov     x1, x23
        bl      grow_table
        cbz     x0, Lfail
        mov     x21, x0
        lsl     x23, x23, #1
        orr     x23, x23, #1
        add     x0, x23, #1                 // new slot count
        sub     x25, x0, x0, lsr #2         // threshold = 3/4 of it
        b       Lskip

// ---- 3. select the top N: x26 = entry, x27 = table end, x28 = n ----
Lscan_done:
        mov     x26, x21
        add     x27, x23, #1
        add     x27, x21, x27, lsl #4
        mov     x28, #0
Lsel:
        cmp     x26, x27
        b.hs    Lsel_done
        ldr     w0, [x26, #12]
        cbz     w0, Lsel_next
        cmp     x28, #TOPN
        b.lo    Lsel_insert
        mov     x0, x26                     // full: must beat the current last
        ldr     x1, [sp, #(TOP + (TOPN - 1) * 8)]
        mov     x2, x19
        bl      entry_before
        cbz     w0, Lsel_next
        mov     x28, #(TOPN - 1)            // drop the last one
Lsel_insert:
        mov     x25, x28                    // x25 = insertion position
1:      cbz     x25, 2f
        sub     x24, x25, #1
        ldr     x1, [sp, x24, lsl #3]
        mov     x0, x26
        mov     x2, x19
        bl      entry_before
        cbz     w0, 2f
        ldr     x1, [sp, x24, lsl #3]       // shift top[i-1] down to top[i]
        str     x1, [sp, x25, lsl #3]
        mov     x25, x24
        b       1b
2:      str     x26, [sp, x25, lsl #3]
        add     x28, x28, #1
Lsel_next:
        add     x26, x26, #ENTRY_SZ
        b       Lsel
Lsel_done:
        cbz     x28, Lexit

// ---- 4. format "<count> <word>\n" lines into one buffer ----
        mov     x0, #0                      // size = sum(len + 12)
        mov     x1, #0
1:      ldr     x2, [sp, x1, lsl #3]
        ldr     w3, [x2, #4]
        add     x0, x0, x3
        add     x0, x0, #12                 // 10 digits + space + newline
        add     x1, x1, #1
        cmp     x1, x28
        b.lo    1b
        bl      _malloc
        cbz     x0, Lfail
        mov     x20, x0                     // x20 = output buffer
        mov     x21, x0                     // x21 = output cursor
        mov     x24, #0                     // x24 = line index
        mov     w10, #10
Lfmt:
        ldr     x22, [sp, x24, lsl #3]      // x22 = entry
        ldr     w0, [x22, #12]
        // count digits, then emit them right-to-left
        mov     w1, w0
        mov     x2, #0
1:      udiv    w1, w1, w10
        add     x2, x2, #1
        cbnz    w1, 1b
        add     x21, x21, x2
        mov     x3, x21
2:      udiv    w1, w0, w10
        msub    w4, w1, w10, w0
        add     w4, w4, #'0'
        strb    w4, [x3, #-1]!
        mov     w0, w1
        cbnz    w0, 2b
        mov     w4, #' '
        strb    w4, [x21], #1
        ldp     w1, w2, [x22]               // offset, length
        mov     x23, x2
        mov     x0, x21
        add     x1, x19, x1
        bl      _memcpy
        add     x21, x21, x23
        mov     w4, #'\n'
        strb    w4, [x21], #1
        mov     w10, #10
        add     x24, x24, #1
        cmp     x24, x28
        b.lo    Lfmt

        mov     x0, x20
        sub     x1, x21, x20
        bl      write_all

Lexit:
        mov     w0, #0
Lret:
        ldp     x29, x30, [sp, #160]
        ldp     x20, x19, [sp, #144]
        ldp     x22, x21, [sp, #128]
        ldp     x24, x23, [sp, #112]
        ldp     x26, x25, [sp, #96]
        ldp     x28, x27, [sp, #80]
        add     sp, sp, #FRAME
        ret
Lfail:                                      // out of memory
        mov     w0, #1
        b       Lret
        .cfi_endproc

// ---------------------------------------------------------------------------
// entry *grow_table(entry *old, size_t old_mask)
// Returns a table of twice the size holding every entry of `old` (which is
// freed), or NULL if allocation fails.
// ---------------------------------------------------------------------------
        .p2align 2
grow_table:
        .cfi_startproc
        stp     x22, x21, [sp, #-48]!
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
        lsl     x21, x1, #1
        orr     x21, x21, #1                // new mask
        add     x0, x21, #1
        mov     x1, #ENTRY_SZ
        bl      _calloc
        cbz     x0, 9f
        mov     x22, x0
        mov     x2, x19                     // old cursor
        add     x3, x20, #1
        add     x3, x19, x3, lsl #4         // old end
1:      ldp     x4, x5, [x2], #16           // x4 = off|len, x5 = hash|count<<32
        lsr     x6, x5, #32
        cbz     x6, 3f
        and     w7, w5, w21
2:      add     x8, x22, x7, lsl #4
        ldr     w9, [x8, #12]
        cbz     w9, 4f
        add     w7, w7, #1
        and     w7, w7, w21
        b       2b
4:      stp     x4, x5, [x8]
3:      cmp     x2, x3
        b.lo    1b
        mov     x0, x19
        bl      _free
        mov     x0, x22
9:      ldp     x29, x30, [sp, #32]
        ldp     x20, x19, [sp, #16]
        ldp     x22, x21, [sp], #48
        ret
        .cfi_endproc

// ---------------------------------------------------------------------------
// int entry_before(entry *a, entry *b, const char *buf)
// 1 if `a` sorts before `b`: higher count, or equal count and smaller word.
// Leaf.
// ---------------------------------------------------------------------------
        .p2align 2
entry_before:
        ldr     w3, [x0, #12]
        ldr     w4, [x1, #12]
        cmp     w3, w4
        b.ne    2f
        ldp     w3, w5, [x0]                // a: offset, length
        ldp     w4, w6, [x1]                // b: offset, length
        add     x3, x2, x3
        add     x4, x2, x4
        cmp     w5, w6
        csel    w7, w5, w6, lo              // shorter length
1:      cbz     w7, 3f
        ldrb    w8, [x3], #1
        ldrb    w9, [x4], #1
        sub     w7, w7, #1
        cmp     w8, w9
        b.eq    1b
        cset    w0, lo
        ret
2:      cset    w0, hi
        ret
3:      cmp     w5, w6                      // common prefix: shorter first
        cset    w0, lo
        ret

// ---------------------------------------------------------------------------
// void write_all(const void *p, size_t n) — write to stdout, retrying on
// short writes and EINTR.
// ---------------------------------------------------------------------------
        .p2align 2
write_all:
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
1:      cbz     x20, 9f
        mov     w0, #1
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.lt    2f
        add     x19, x19, x0
        sub     x20, x20, x0
        b       1b
2:      bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    1b
9:      ldp     x29, x30, [sp, #16]
        ldp     x20, x19, [sp], #32
        ret
        .cfi_endproc

.subsections_via_symbols
