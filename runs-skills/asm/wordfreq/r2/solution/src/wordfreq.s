// wordfreq — print the 10 most frequent words read from standard input.
//
// A word is a maximal run of ASCII letters, folded to lowercase. Output is
// "<count> <word>\n", ordered by count descending, then word ascending.
//
// Design:
//   1. slurp:      read all of stdin into one heap buffer, NUL-terminated.
//   2. tally:      single pass over the buffer; words are lowercased in place
//                  and counted in an open-addressing (linear probe) hash table
//                  keyed by CRC32C. Entries reference the first occurrence of
//                  the word inside the buffer, so no key bytes are copied.
//   3. select_top: one pass over the table keeping a sorted top-10 array.
//   4. main:       format and write the result.
//
// Hash table entry (16 bytes, 16-byte aligned):
//   +0  u32 offset of the word in the buffer
//   +4  u32 count (0 = empty slot)
//   +8  u32 length
//   +12 u32 hash
// The (length, hash) pair is compared as a single 64-bit key.

        .equ    ENTRY_SHIFT, 4
        .equ    INIT_SLOTS, 1 << 16             // initial table size (power of 2)
        .equ    INIT_BUF, 1 << 20               // initial input buffer size
        .equ    TOP_N, 10
        .equ    EINTR, 4

        .section __TEXT,__cstring,cstring_literals
Loom_msg:
        .ascii  "wordfreq: out of memory\n"
Loom_end:
        .equ    OOM_LEN, Loom_end - Loom_msg

        .text

// ---------------------------------------------------------------------------
// int main(void)
// ---------------------------------------------------------------------------
        .globl  _main
        .p2align 2
_main:
        .cfi_startproc
        sub     sp, sp, #176
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
        // Frame: [sp, #0..79] top-N entry pointers, [sp, #80..111] number text.

        bl      _slurp                          // x0 = buf, x1 = len
        mov     x19, x0
        bl      _tally                          // x0 = table, x1 = slots
        mov     x2, x1
        mov     x1, x0
        mov     x0, x19
        mov     x3, sp
        bl      _select_top                     // x0 = number of entries
        mov     x20, x0
        mov     x21, #0                         // i

Lmain_line:
        cmp     x21, x20
        b.hs    Lmain_exit
        ldr     x22, [sp, x21, lsl #3]          // entry

        // "<count> " built right-to-left at the end of the number buffer.
        add     x23, sp, #112
        mov     w9, #' '
        strb    w9, [x23, #-1]!
        ldr     w9, [x22, #4]                   // count (>= 1)
        mov     w10, #10
Lmain_digit:
        udiv    w11, w9, w10
        msub    w12, w11, w10, w9
        add     w12, w12, #'0'
        strb    w12, [x23, #-1]!
        mov     w9, w11
        cbnz    w9, Lmain_digit
        mov     x0, x23
        add     x1, sp, #112
        sub     x1, x1, x23
        bl      _write_all

        // The word itself, followed by '\n'. The byte after a word is always a
        // separator (or the trailing NUL), and counting is finished, so it can
        // be overwritten with the newline.
        ldr     w9, [x22]                       // offset
        ldr     w10, [x22, #8]                  // length
        add     x0, x19, x9
        mov     w11, #'\n'
        strb    w11, [x0, x10]
        add     x1, x10, #1
        bl      _write_all

        add     x21, x21, #1
        b       Lmain_line

Lmain_exit:
        mov     w0, #0
        ldp     x29, x30, [sp, #160]
        ldp     x20, x19, [sp, #144]
        ldp     x22, x21, [sp, #128]
        ldp     x24, x23, [sp, #112]
        add     sp, sp, #176
        ret
        .cfi_endproc

// ---------------------------------------------------------------------------
// slurp: read all of stdin.
// out: x0 = malloc'd buffer, x1 = length; buffer[length] = 0.
// ---------------------------------------------------------------------------
        .p2align 2
_slurp:
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

        mov     x21, #INIT_BUF                  // capacity
        mov     x0, x21
        bl      _malloc
        cbz     x0, Lslurp_oom
        mov     x19, x0                         // buffer
        mov     x20, #0                         // length

Lslurp_loop:
        sub     x2, x21, x20
        sub     x2, x2, #1                      // reserve one byte for the NUL
        cbnz    x2, Lslurp_read
        lsl     x21, x21, #1
        mov     x0, x19
        mov     x1, x21
        bl      _realloc
        cbz     x0, Lslurp_oom
        mov     x19, x0
        b       Lslurp_loop

Lslurp_read:
        mov     w0, #0                          // STDIN_FILENO
        add     x1, x19, x20
        bl      _read
        cmp     x0, #0
        b.gt    Lslurp_got
        b.eq    Lslurp_eof
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lslurp_loop
        b       Lslurp_eof                      // treat read errors as EOF
Lslurp_got:
        add     x20, x20, x0
        b       Lslurp_loop

Lslurp_eof:
        strb    wzr, [x19, x20]
        mov     x0, x19
        mov     x1, x20
        ldp     x29, x30, [sp, #32]
        ldp     x20, x19, [sp, #16]
        ldp     x22, x21, [sp], #48
        ret
Lslurp_oom:
        bl      _die_oom
        .cfi_endproc

// ---------------------------------------------------------------------------
// tally: count words.
// in:  x0 = buffer, x1 = length (buffer[length] must be a non-letter)
// out: x0 = hash table, x1 = number of slots
// Letters in the buffer are lowercased in place.
// ---------------------------------------------------------------------------
        .p2align 2
_tally:
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

        mov     x19, x0                         // buffer base
        mov     x20, x0                         // cursor
        add     x21, x0, x1                     // end (points at the NUL)
        mov     x23, #INIT_SLOTS                // slots
        mov     x0, x23
        mov     x1, #(1 << ENTRY_SHIFT)
        bl      _calloc
        cbz     x0, Ltally_oom
        mov     x22, x0                         // table
        mov     x24, #0                         // occupied slots
        sub     w28, w23, #1                    // slot mask

        // Skip separators. A byte c is a letter iff (c | 0x20) - 'a' < 26.
Ltally_skip:
        cmp     x20, x21
        b.hs    Ltally_done
        ldrb    w9, [x20], #1
        orr     w10, w9, #0x20
        sub     w11, w10, #'a'
        cmp     w11, #26
        b.hs    Ltally_skip

        // Inside a word: lowercase in place and hash. The NUL at the end of the
        // buffer guarantees termination without a bounds check.
        sub     x25, x20, #1                    // word start
        mov     w26, #-1                        // CRC32C seed
Ltally_word:
        strb    w10, [x20, #-1]
        crc32cb w26, w26, w10
        ldrb    w9, [x20], #1
        orr     w10, w9, #0x20
        sub     w11, w10, #'a'
        cmp     w11, #26
        b.lo    Ltally_word

        sub     x27, x20, x25
        sub     x27, x27, #1                    // word length
        orr     x15, x27, x26, lsl #32          // 64-bit key: hash:length
        and     w12, w26, w28                   // slot index

Ltally_probe:
        add     x13, x22, x12, lsl #ENTRY_SHIFT
        ldp     w14, w9, [x13]                  // offset, count
        cbz     w9, Ltally_insert
        ldr     x10, [x13, #8]
        cmp     x10, x15
        b.ne    Ltally_next

        // Same hash and length: compare the bytes.
        add     x14, x19, x14                   // stored word
        mov     x11, x25                        // current word
        mov     x10, x27                        // bytes left
Ltally_cmp8:
        cmp     x10, #8
        b.lo    Ltally_cmp1
        ldr     x3, [x14], #8
        ldr     x4, [x11], #8
        cmp     x3, x4
        b.ne    Ltally_next
        sub     x10, x10, #8
        b       Ltally_cmp8
Ltally_cmp1:
        cbz     x10, Ltally_hit
        ldrb    w3, [x14], #1
        ldrb    w4, [x11], #1
        cmp     w3, w4
        b.ne    Ltally_next
        sub     x10, x10, #1
        b       Ltally_cmp1

Ltally_hit:
        add     w9, w9, #1
        str     w9, [x13, #4]
        b       Ltally_skip

Ltally_next:
        add     w12, w12, #1
        and     w12, w12, w28
        b       Ltally_probe

Ltally_insert:
        sub     x14, x25, x19
        mov     w9, #1
        stp     w14, w9, [x13]
        str     x15, [x13, #8]
        add     x24, x24, #1
        // Keep the load factor at or below 3/4.
        add     x9, x23, x23, lsl #1
        cmp     x9, x24, lsl #2
        b.hs    Ltally_skip
        mov     x0, x22
        mov     x1, x23
        bl      _rehash
        mov     x22, x0
        lsl     x23, x23, #1
        sub     w28, w23, #1
        b       Ltally_skip

Ltally_done:
        mov     x0, x22
        mov     x1, x23
        ldp     x29, x30, [sp, #80]
        ldp     x20, x19, [sp, #64]
        ldp     x22, x21, [sp, #48]
        ldp     x24, x23, [sp, #32]
        ldp     x26, x25, [sp, #16]
        ldp     x28, x27, [sp, #0]
        add     sp, sp, #96
        ret
Ltally_oom:
        bl      _die_oom
        .cfi_endproc

// ---------------------------------------------------------------------------
// rehash: move every entry into a table twice the size and free the old one.
// in:  x0 = old table, x1 = old slot count
// out: x0 = new table (2 * old slot count slots)
// ---------------------------------------------------------------------------
        .p2align 2
_rehash:
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
        mov     x0, x21
        mov     x1, #(1 << ENTRY_SHIFT)
        bl      _calloc
        cbz     x0, Lrehash_oom
        mov     x22, x0

        sub     w9, w21, #1                     // new mask
        mov     x10, x19                        // cursor
        add     x11, x19, x20, lsl #ENTRY_SHIFT // end
Lrehash_loop:
        cmp     x10, x11
        b.hs    Lrehash_done
        ldp     x12, x13, [x10], #16            // offset:count, length:hash
        lsr     x14, x12, #32
        cbz     x14, Lrehash_loop               // empty slot
        lsr     x14, x13, #32
        and     w14, w14, w9
Lrehash_probe:
        add     x15, x22, x14, lsl #ENTRY_SHIFT
        ldr     w3, [x15, #4]
        cbz     w3, Lrehash_put
        add     w14, w14, #1
        and     w14, w14, w9
        b       Lrehash_probe
Lrehash_put:
        stp     x12, x13, [x15]
        b       Lrehash_loop

Lrehash_done:
        mov     x0, x19
        bl      _free
        mov     x0, x22
        ldp     x29, x30, [sp, #32]
        ldp     x20, x19, [sp, #16]
        ldp     x22, x21, [sp], #48
        ret
Lrehash_oom:
        bl      _die_oom
        .cfi_endproc

// ---------------------------------------------------------------------------
// select_top: collect the TOP_N best entries in rank order.
// in:  x0 = buffer, x1 = table, x2 = slots, x3 = out array of TOP_N pointers
// out: x0 = number of entries stored (<= TOP_N)
// ---------------------------------------------------------------------------
        .p2align 2
_select_top:
        .cfi_startproc
        sub     sp, sp, #64
        stp     x24, x23, [sp, #0]
        stp     x22, x21, [sp, #16]
        stp     x20, x19, [sp, #32]
        stp     x29, x30, [sp, #48]
        add     x29, sp, #48
        .cfi_def_cfa w29, 16
        .cfi_offset w30, -8
        .cfi_offset w29, -16
        .cfi_offset w19, -24
        .cfi_offset w20, -32
        .cfi_offset w21, -40
        .cfi_offset w22, -48
        .cfi_offset w23, -56
        .cfi_offset w24, -64

        mov     x19, x0                         // buffer
        mov     x20, x1                         // cursor
        add     x21, x1, x2, lsl #ENTRY_SHIFT   // end
        mov     x22, x3                         // out array
        mov     x23, #0                         // filled
        // x24 = insertion position. The candidate entry is always x20 - 16.

Lsel_loop:
        cmp     x20, x21
        b.hs    Lsel_done
        add     x20, x20, #16
        ldr     w9, [x20, #-12]                 // count
        cbz     w9, Lsel_loop
        cmp     x23, #TOP_N
        b.hs    Lsel_full
        mov     x24, x23
        add     x23, x23, #1
        b       Lsel_shift

Lsel_full:
        // Cheap reject on count before the full comparison.
        ldr     x1, [x22, #(TOP_N - 1) * 8]
        ldr     w10, [x1, #4]
        cmp     w9, w10
        b.lo    Lsel_loop
        sub     x0, x20, #16
        mov     x2, x19
        bl      _ranks_before
        cbz     w0, Lsel_loop
        mov     x24, #(TOP_N - 1)

        // Insertion: shift worse entries down until the slot is found.
Lsel_shift:
        cbz     x24, Lsel_place
        sub     x9, x24, #1
        ldr     x1, [x22, x9, lsl #3]
        sub     x0, x20, #16
        mov     x2, x19
        bl      _ranks_before
        cbz     w0, Lsel_place
        sub     x24, x24, #1
        ldr     x9, [x22, x24, lsl #3]
        add     x10, x24, #1
        str     x9, [x22, x10, lsl #3]
        b       Lsel_shift
Lsel_place:
        sub     x9, x20, #16
        str     x9, [x22, x24, lsl #3]
        b       Lsel_loop

Lsel_done:
        mov     x0, x23
        ldp     x29, x30, [sp, #48]
        ldp     x20, x19, [sp, #32]
        ldp     x22, x21, [sp, #16]
        ldp     x24, x23, [sp, #0]
        add     sp, sp, #64
        ret
        .cfi_endproc

// ---------------------------------------------------------------------------
// ranks_before: does entry a rank strictly before entry b?
// (higher count first; equal counts by byte-wise word order, shorter prefix
// first). Leaf.
// in:  x0 = a, x1 = b, x2 = buffer
// out: w0 = 1 if a precedes b, else 0
// ---------------------------------------------------------------------------
        .p2align 2
_ranks_before:
        .cfi_startproc
        ldr     w3, [x0, #4]
        ldr     w4, [x1, #4]
        cmp     w3, w4
        b.ne    Lrb_count
        ldr     w3, [x0]                        // a offset
        ldr     w5, [x0, #8]                    // a length
        ldr     w4, [x1]                        // b offset
        ldr     w6, [x1, #8]                    // b length
        add     x3, x2, x3
        add     x4, x2, x4
        cmp     w5, w6
        csel    w7, w5, w6, lo                  // common length
Lrb_loop:
        cbz     w7, Lrb_len
        ldrb    w8, [x3], #1
        ldrb    w9, [x4], #1
        cmp     w8, w9
        b.ne    Lrb_byte
        sub     w7, w7, #1
        b       Lrb_loop
Lrb_count:
        cset    w0, hi
        ret
Lrb_byte:
        cset    w0, lo
        ret
Lrb_len:
        cmp     w5, w6
        cset    w0, lo
        ret
        .cfi_endproc

// ---------------------------------------------------------------------------
// write_all: write x1 bytes at x0 to stdout, retrying on short writes and
// EINTR. Other errors abandon the write.
// ---------------------------------------------------------------------------
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
Lwa_loop:
        cbz     x20, Lwa_done
        mov     w0, #1                          // STDOUT_FILENO
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.gt    Lwa_advance
        b.eq    Lwa_done
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    Lwa_loop
        b       Lwa_done
Lwa_advance:
        add     x19, x19, x0
        sub     x20, x20, x0
        b       Lwa_loop
Lwa_done:
        ldp     x29, x30, [sp, #16]
        ldp     x20, x19, [sp], #32
        ret
        .cfi_endproc

// ---------------------------------------------------------------------------
// die_oom: report allocation failure on stderr and exit(1). Does not return.
// ---------------------------------------------------------------------------
        .p2align 2
_die_oom:
        .cfi_startproc
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        .cfi_def_cfa w29, 16
        .cfi_offset w30, -8
        .cfi_offset w29, -16
        mov     w0, #2                          // STDERR_FILENO
        adrp    x1, Loom_msg@PAGE
        add     x1, x1, Loom_msg@PAGEOFF
        mov     x2, #OOM_LEN
        bl      _write
        mov     w0, #1
        bl      _exit
        .cfi_endproc

.subsections_via_symbols
