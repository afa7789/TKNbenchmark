// wordfreq — print the 10 most frequent ASCII words read from stdin.
//
// AArch64 / macOS (Mach-O, Apple arm64 ABI).
//
// Strategy
//   1. Slurp all of stdin into one growable heap buffer.
//   2. Scan it once: every letter is folded to lowercase *in place*, and an
//      FNV-1a hash is accumulated per word. Words are interned in an
//      open-addressing hash table whose entries point back into the input
//      buffer, so no word is ever copied.
//   3. Walk the table keeping a sorted top-10 array (insertion step).
//   4. Print "<count> <word>\n" for each selected entry.
//
// Hash table entry layout (32 bytes, ptr == 0 marks an empty slot):
//     +0  ptr    word start (inside the input buffer)
//     +8  hash   full 64-bit FNV-1a hash
//     +16 len    word length in bytes
//     +24 count  occurrences

        .set    ENT_PTR,     0
        .set    ENT_HASH,    8
        .set    ENT_LEN,     16
        .set    ENT_COUNT,   24
        .set    ENT_SHIFT,   5                  // log2(entry size)
        .set    ENT_SIZE,    1 << ENT_SHIFT

        .set    TABLE_INIT,  1 << 16            // initial slots (power of two)
        .set    READ_INIT,   1 << 20            // initial input buffer size
        .set    TOP_N,       10
        .set    EINTR,       4

// main's stack frame below the saved registers:
//   sp + 0          top[TOP_N] entry pointers
//   sp + TOP_N*8..  scratch for formatting a count (20 digits + ' ')
        .set    NUM_SCRATCH, 32
        .set    LOCALS,      TOP_N * 8 + NUM_SCRATCH   // 112, 16-aligned

        .text

// ---------------------------------------------------------------------------
// int main(void)
//
// Callee-saved register roles during the scan:
//   x19 cursor in input        x20 end of input
//   x21 hash table base        x22 table mask (slots - 1)
//   x23 occupied slots         x24 byte-class table
//   x25 FNV prime              x26 FNV offset basis
//   x27 start of current word
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
        sub     sp, sp, #LOCALS

        bl      read_input                      // x0 = buf, x1 = len
        mov     x19, x0
        add     x20, x0, x1

        mov     x0, #TABLE_INIT
        mov     x1, #ENT_SIZE
        bl      _calloc
        cbz     x0, fatal_oom
        mov     x21, x0
        mov     x22, #(TABLE_INIT - 1)
        mov     x23, #0

        adrp    x24, byte_class@PAGE
        add     x24, x24, byte_class@PAGEOFF
        mov     x25, #0x01b3                    // FNV-1a 64 prime 0x100000001b3
        movk    x25, #0x0100, lsl #32
        mov     x26, #0x2325                    // offset basis 0xcbf29ce484222325
        movk    x26, #0x8422, lsl #16
        movk    x26, #0x9ce4, lsl #32
        movk    x26, #0xcbf2, lsl #48

// ---- skip separators -------------------------------------------------------
scan:
        cmp     x19, x20
        b.hs    scan_done
        ldrb    w0, [x19], #1
        ldrb    w1, [x24, x0]                   // lowercase letter, or 0
        cbz     w1, scan

        sub     x27, x19, #1                    // word starts here
        strb    w1, [x27]
        eor     x2, x26, x1
        mul     x2, x2, x25

// ---- consume the rest of the word, folding + hashing ----------------------
word:
        cmp     x19, x20
        b.hs    word_end
        ldrb    w0, [x19]
        ldrb    w1, [x24, x0]
        cbz     w1, word_end
        strb    w1, [x19], #1
        eor     x2, x2, x1
        mul     x2, x2, x25
        b       word

// ---- look the word up: x27 = ptr, x3 = len, x2 = hash ---------------------
word_end:
        sub     x3, x19, x27
        and     x4, x2, x22
probe:
        add     x5, x21, x4, lsl #ENT_SHIFT
        ldr     x6, [x5, #ENT_PTR]
        cbz     x6, insert_new
        ldp     x7, x8, [x5, #ENT_HASH]         // x7 = hash, x8 = len
        cmp     x7, x2
        ccmp    x8, x3, #0, eq
        b.ne    probe_next

        mov     x8, #0                          // byte offset
cmp8:   sub     x9, x3, x8
        cmp     x9, #8
        b.lo    cmp1
        ldr     x10, [x6, x8]
        ldr     x11, [x27, x8]
        cmp     x10, x11
        b.ne    probe_next
        add     x8, x8, #8
        b       cmp8
cmp1:   cmp     x8, x3
        b.hs    hit
        ldrb    w10, [x6, x8]
        ldrb    w11, [x27, x8]
        cmp     w10, w11
        b.ne    probe_next
        add     x8, x8, #1
        b       cmp1

hit:
        ldr     x7, [x5, #ENT_COUNT]
        add     x7, x7, #1
        str     x7, [x5, #ENT_COUNT]
        b       scan

probe_next:
        add     x4, x4, #1
        and     x4, x4, x22
        b       probe

insert_new:
        stp     x27, x2, [x5, #ENT_PTR]
        mov     x7, #1
        stp     x3, x7, [x5, #ENT_LEN]
        add     x23, x23, #1
        cmp     x22, x23, lsl #1                // keep load factor <= 1/2
        b.hs    scan
        mov     x0, x21
        mov     x1, x22
        bl      table_grow
        mov     x21, x0
        mov     x22, x1
        b       scan

// ---- select the top N entries ---------------------------------------------
// x19 cursor over slots, x20 end of table, x23 entries in top[], x24 insert
// position, x28 top[] base.
scan_done:
        mov     x28, sp
        mov     x19, x21
        add     x20, x22, #1
        add     x20, x21, x20, lsl #ENT_SHIFT
        mov     x23, #0

select:
        cmp     x19, x20
        b.hs    emit
        ldr     x0, [x19, #ENT_PTR]
        cbz     x0, select_next

        cmp     x23, #TOP_N
        b.lo    select_room
        mov     x0, x19                         // full: must beat the last one
        ldr     x1, [x28, #((TOP_N - 1) * 8)]
        bl      ranks_before
        cbz     w0, select_next
        mov     x24, #(TOP_N - 1)
        b       select_shift
select_room:
        mov     x24, x23
        add     x23, x23, #1

select_shift:                                   // insertion step
        cbz     x24, select_place
        sub     x9, x24, #1
        ldr     x1, [x28, x9, lsl #3]
        mov     x0, x19
        bl      ranks_before
        cbz     w0, select_place
        sub     x9, x24, #1
        ldr     x1, [x28, x9, lsl #3]
        str     x1, [x28, x24, lsl #3]
        mov     x24, x9
        b       select_shift
select_place:
        str     x19, [x28, x24, lsl #3]
select_next:
        add     x19, x19, #ENT_SIZE
        b       select

// ---- print -----------------------------------------------------------------
// x19 index, x23 count of entries, x28 top[], x21 current entry.
emit:
        mov     x19, #0
emit_loop:
        cmp     x19, x23
        b.hs    done
        ldr     x21, [x28, x19, lsl #3]

        ldr     x0, [x21, #ENT_COUNT]
        add     x1, x28, #LOCALS                // end of number scratch
        sub     x1, x1, #1
        mov     w2, #' '
        strb    w2, [x1]                        // digits are built backwards
        mov     x3, #10
1:      udiv    x4, x0, x3
        msub    x5, x4, x3, x0
        add     w5, w5, #'0'
        strb    w5, [x1, #-1]!
        mov     x0, x4
        cbnz    x0, 1b
        add     x2, x28, #LOCALS
        mov     x0, x1
        sub     x1, x2, x1
        bl      write_all

        ldr     x0, [x21, #ENT_PTR]
        ldr     x1, [x21, #ENT_LEN]
        bl      write_all

        adrp    x0, newline@PAGE
        add     x0, x0, newline@PAGEOFF
        mov     x1, #1
        bl      write_all

        add     x19, x19, #1
        b       emit_loop

done:
        mov     w0, #0
        add     sp, sp, #LOCALS
        ldp     x27, x28, [sp, #80]
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #96
        ret

// ---------------------------------------------------------------------------
// read_input -> x0 = buffer, x1 = length
// Reads stdin to EOF into a doubling heap buffer.
// ---------------------------------------------------------------------------
        .p2align 2
read_input:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        str     x21, [sp, #32]

        mov     x21, #READ_INIT                 // capacity
        mov     x20, #0                         // length
        mov     x0, x21
        bl      _malloc
        cbz     x0, fatal_oom
        mov     x19, x0

read_more:
        sub     x2, x21, x20
        cbnz    x2, 1f
        lsl     x21, x21, #1
        mov     x0, x19
        mov     x1, x21
        bl      _realloc
        cbz     x0, fatal_oom
        mov     x19, x0
        sub     x2, x21, x20
1:      mov     w0, #0                          // STDIN_FILENO
        add     x1, x19, x20
        bl      _read
        cmp     x0, #0
        b.gt    2f
        b.eq    read_done
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    read_more
        b       read_done                       // treat other errors as EOF
2:      add     x20, x20, x0
        b       read_more

read_done:
        mov     x0, x19
        mov     x1, x20
        ldr     x21, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// ---------------------------------------------------------------------------
// table_grow(x0 = old table, x1 = old mask) -> x0 = new table, x1 = new mask
// Doubles the table, rehashes every entry from its stored hash, frees old.
// ---------------------------------------------------------------------------
        .p2align 2
table_grow:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        mov     x19, x0
        mov     x20, x1

        add     x0, x1, #1
        lsl     x0, x0, #1                      // new slot count
        sub     x22, x0, #1
        mov     x1, #ENT_SIZE
        bl      _calloc
        cbz     x0, fatal_oom
        mov     x21, x0

        mov     x2, x19                         // cursor
        add     x3, x20, #1
        add     x3, x19, x3, lsl #ENT_SHIFT     // end
1:      cmp     x2, x3
        b.hs    3f
        ldp     x4, x5, [x2, #ENT_PTR]
        ldp     x6, x7, [x2, #ENT_LEN]
        add     x2, x2, #ENT_SIZE
        cbz     x4, 1b
        and     x8, x5, x22
2:      add     x9, x21, x8, lsl #ENT_SHIFT
        ldr     x10, [x9, #ENT_PTR]
        cbz     x10, 4f
        add     x8, x8, #1
        and     x8, x8, x22
        b       2b
4:      stp     x4, x5, [x9, #ENT_PTR]
        stp     x6, x7, [x9, #ENT_LEN]
        b       1b

3:      mov     x0, x19
        bl      _free
        mov     x0, x21
        mov     x1, x22
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// ---------------------------------------------------------------------------
// ranks_before(x0 = entry a, x1 = entry b) -> w0 = 1 if a sorts before b
// Order: count descending, then word ascending (bytewise; prefix first).
// Leaf; clobbers x0-x7 only.
// ---------------------------------------------------------------------------
        .p2align 2
ranks_before:
        ldr     x2, [x0, #ENT_COUNT]
        ldr     x3, [x1, #ENT_COUNT]
        cmp     x2, x3
        b.ne    1f
        ldr     x4, [x0, #ENT_PTR]
        ldr     x5, [x1, #ENT_PTR]
        ldr     x2, [x0, #ENT_LEN]
        ldr     x3, [x1, #ENT_LEN]
        cmp     x2, x3
        csel    x6, x2, x3, lo                  // shorter length
2:      cbz     x6, 3f
        ldrb    w0, [x4], #1
        ldrb    w1, [x5], #1
        sub     x6, x6, #1
        cmp     w0, w1
        b.eq    2b
        cset    w0, lo
        ret
3:      cmp     x2, x3                          // common prefix: shorter first
        cset    w0, lo
        ret
1:      cset    w0, hi
        ret

// ---------------------------------------------------------------------------
// write_all(x0 = ptr, x1 = len) — write everything to stdout, retry on EINTR.
// Gives up silently on other errors (e.g. EPIPE).
// ---------------------------------------------------------------------------
        .p2align 2
write_all:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        mov     x19, x0
        mov     x20, x1
1:      cbz     x20, 3f
        mov     w0, #1                          // STDOUT_FILENO
        mov     x1, x19
        mov     x2, x20
        bl      _write
        cmp     x0, #0
        b.gt    2f
        b.eq    3f
        bl      ___error
        ldr     w0, [x0]
        cmp     w0, #EINTR
        b.eq    1b
        b       3f
2:      add     x19, x19, x0
        sub     x20, x20, x0
        b       1b
3:      ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// ---------------------------------------------------------------------------
// fatal_oom — report allocation failure and exit(1).
// ---------------------------------------------------------------------------
        .p2align 2
fatal_oom:
        mov     w0, #2                          // STDERR_FILENO
        adrp    x1, oom_msg@PAGE
        add     x1, x1, oom_msg@PAGEOFF
        mov     x2, #OOM_LEN
        bl      _write
        mov     w0, #1
        bl      _exit

        .section __TEXT,__const
// byte -> lowercase ASCII letter, or 0 for any separator byte.
byte_class:
        .space  'A'
        .ascii  "abcdefghijklmnopqrstuvwxyz"
        .space  'a' - 'Z' - 1
        .ascii  "abcdefghijklmnopqrstuvwxyz"
        .space  256 - 'z' - 1

newline:
        .ascii  "\n"
oom_msg:
        .ascii  "wordfreq: out of memory\n"
        .set    OOM_LEN, . - oom_msg
