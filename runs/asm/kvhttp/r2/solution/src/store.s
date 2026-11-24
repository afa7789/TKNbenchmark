// kvhttp — in-memory key/value store.
//
// Entries live in a single array of pointers kept sorted by key (bytewise,
// shorter-prefix first), so lookups are a binary search and listing is a
// linear walk. One global mutex guards the whole store; every critical
// section is short (pointer moves and at most one value copy).

        .include "defs.inc"

// struct entry
        .equ E_VLEN, 0          // u64 value length
        .equ E_VAL,  8          // u8* value bytes (malloc'd, owned)
        .equ E_KLEN, 16         // u64 key length (1..64)
        .equ E_KEY,  24         // u8[64] key bytes
        .equ E_SIZE, 88

// struct store (_g_store)
        .equ S_TAB, 0           // entry** sorted array
        .equ S_CNT, 8           // number of entries
        .equ S_CAP, 16          // capacity of S_TAB

        .equ INITIAL_CAP, 64

        .zerofill __DATA,__bss,_g_store,24,3
        .zerofill __DATA,__bss,_g_lock,64,4

        .section __TEXT,__text,regular,pure_instructions

// void store_init(void)
        .globl _store_init
        .p2align 2
_store_init:
        stp     x29, x30, [sp, #-16]!
        mov     x29, sp
        LOADADDR x0, _g_lock
        mov     x1, #0
        bl      _pthread_mutex_init
        ldp     x29, x30, [sp], #16
        ret

        .p2align 2
_store_lock:
        LOADADDR x0, _g_lock
        b       _pthread_mutex_lock

        .p2align 2
_store_unlock:
        LOADADDR x0, _g_lock
        b       _pthread_mutex_unlock

// store_find(key x0, klen x1) -> x0 = index, x1 = 1 if found else 0.
// When not found, x0 is the insertion point. Lock must be held. Leaf.
        .p2align 2
_store_find:
        LOADADDR x8, _g_store
        ldp     x9, x12, [x8, #S_TAB]           // x9 = tab, x12 = hi = cnt
        mov     x11, #0                         // lo
Lf_loop:
        cmp     x11, x12
        b.hs    Lf_miss
        add     x13, x11, x12
        lsr     x13, x13, #1                    // mid
        ldr     x14, [x9, x13, lsl #3]
        ldr     x15, [x14, #E_KLEN]
        add     x14, x14, #E_KEY
        cmp     x15, x1
        csel    x2, x15, x1, lo                 // n = min(elen, klen)
        mov     x3, #0
Lf_cmp:
        cmp     x3, x2
        b.hs    Lf_lens
        ldrb    w4, [x14, x3]
        ldrb    w5, [x0, x3]
        add     x3, x3, #1
        cmp     w4, w5
        b.eq    Lf_cmp
        b.lo    Lf_right                        // entry < key
        b       Lf_left
Lf_lens:
        cmp     x15, x1
        b.eq    Lf_hit
        b.lo    Lf_right
Lf_left:
        mov     x12, x13
        b       Lf_loop
Lf_right:
        add     x11, x13, #1
        b       Lf_loop
Lf_hit:
        mov     x0, x13
        mov     x1, #1
        ret
Lf_miss:
        mov     x0, x11
        mov     x1, #0
        ret

// store_put(key x0, klen x1, val x2, vlen x3) -> x0 = 1 created, 0 replaced,
// -1 out of memory. On success the store takes ownership of val.
        .globl _store_put
        .p2align 2
_store_put:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        mov     x19, x0
        mov     x20, x1
        mov     x21, x2
        mov     x22, x3

        bl      _store_lock
        mov     x0, x19
        mov     x1, x20
        bl      _store_find
        mov     x23, x0                         // index
        cbz     x1, Lp_insert

        // Replace the value of an existing entry; free the old one unlocked.
        LOADADDR x8, _g_store
        ldr     x9, [x8, #S_TAB]
        ldr     x10, [x9, x23, lsl #3]
        ldr     x24, [x10, #E_VAL]
        stp     x22, x21, [x10, #E_VLEN]
        bl      _store_unlock
        mov     x0, x24
        bl      _free
        mov     x0, #0
        b       Lp_ret

Lp_insert:
        LOADADDR x8, _g_store
        ldr     x10, [x8, #S_CNT]
        ldr     x11, [x8, #S_CAP]
        cmp     x10, x11
        b.lo    Lp_alloc
        lsl     x24, x11, #1
        mov     x12, #INITIAL_CAP
        cmp     x24, #0
        csel    x24, x12, x24, eq               // new capacity
        ldr     x0, [x8, #S_TAB]
        lsl     x1, x24, #3
        bl      _realloc
        cbz     x0, Lp_oom
        LOADADDR x8, _g_store
        str     x0, [x8, #S_TAB]
        str     x24, [x8, #S_CAP]

Lp_alloc:
        mov     x0, #E_SIZE
        bl      _malloc
        cbz     x0, Lp_oom
        mov     x24, x0
        stp     x22, x21, [x24, #E_VLEN]
        str     x20, [x24, #E_KLEN]
        add     x0, x24, #E_KEY
        mov     x1, x19
        mov     x2, x20
        bl      _memcpy

        // Shift tab[idx..cnt) up by one slot.
        LOADADDR x8, _g_store
        ldp     x9, x10, [x8, #S_TAB]
        add     x1, x9, x23, lsl #3
        add     x0, x1, #8
        sub     x2, x10, x23
        lsl     x2, x2, #3
        bl      _memmove

        LOADADDR x8, _g_store
        ldp     x9, x10, [x8, #S_TAB]
        str     x24, [x9, x23, lsl #3]
        add     x10, x10, #1
        str     x10, [x8, #S_CNT]
        bl      _store_unlock
        mov     x0, #1
        b       Lp_ret

Lp_oom:
        bl      _store_unlock
        mov     x0, #-1
Lp_ret:
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ret

// store_get(key x0, klen x1) -> x0 = 1 found / 0 absent / -1 out of memory,
// x1 = malloc'd copy of the value (caller frees), x2 = value length.
        .globl _store_get
        .p2align 2
_store_get:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        mov     x19, x0
        mov     x20, x1

        bl      _store_lock
        mov     x0, x19
        mov     x1, x20
        bl      _store_find
        cbz     x1, Lg_absent

        LOADADDR x8, _g_store
        ldr     x9, [x8, #S_TAB]
        ldr     x10, [x9, x0, lsl #3]
        ldp     x20, x19, [x10, #E_VLEN]        // x20 = vlen, x19 = val
        add     x0, x20, #1
        bl      _malloc
        cbz     x0, Lg_oom
        mov     x21, x0
        mov     x1, x19
        mov     x2, x20
        bl      _memcpy
        bl      _store_unlock
        mov     x0, #1
        mov     x1, x21
        mov     x2, x20
        b       Lg_ret

Lg_absent:
        bl      _store_unlock
        mov     x0, #0
        b       Lg_ret
Lg_oom:
        bl      _store_unlock
        mov     x0, #-1
Lg_ret:
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// store_del(key x0, klen x1) -> x0 = 1 deleted, 0 absent.
        .globl _store_del
        .p2align 2
_store_del:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        mov     x19, x0
        mov     x20, x1

        bl      _store_lock
        mov     x0, x19
        mov     x1, x20
        bl      _store_find
        cbz     x1, Ld_absent

        LOADADDR x8, _g_store
        ldp     x9, x10, [x8, #S_TAB]
        ldr     x21, [x9, x0, lsl #3]           // entry being removed
        sub     x10, x10, #1
        str     x10, [x8, #S_CNT]
        // Shift tab[idx+1..cnt_old) down by one slot.
        sub     x2, x10, x0
        lsl     x2, x2, #3
        add     x0, x9, x0, lsl #3
        add     x1, x0, #8
        bl      _memmove
        bl      _store_unlock

        ldr     x0, [x21, #E_VAL]
        bl      _free
        mov     x0, x21
        bl      _free
        mov     x0, #1
        b       Ld_ret

Ld_absent:
        bl      _store_unlock
        mov     x0, #0
Ld_ret:
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// store_list() -> x0 = malloc'd JSON array of all keys in ascending order
// (caller frees), x1 = its length. x0 = 0 if out of memory.
// Keys only contain [A-Za-z0-9_-], so no JSON escaping is needed.
        .globl _store_list
        .p2align 2
_store_list:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]

        bl      _store_lock
        LOADADDR x8, _g_store
        ldp     x19, x20, [x8, #S_TAB]          // x19 = tab, x20 = cnt

        // Upper bound: "[" + "]" + per key (quote, key, quote, comma).
        mov     x0, #2
        mov     x9, #0
1:      cmp     x9, x20
        b.hs    2f
        ldr     x10, [x19, x9, lsl #3]
        ldr     x11, [x10, #E_KLEN]
        add     x0, x0, x11
        add     x0, x0, #3
        add     x9, x9, #1
        b       1b
2:      bl      _malloc
        cbz     x0, Ll_oom
        mov     x21, x0                         // buffer
        mov     x22, x0                         // cursor

        mov     w12, #'['
        strb    w12, [x22], #1
        mov     x9, #0
Ll_key:
        cmp     x9, x20
        b.hs    Ll_close
        cbz     x9, 3f
        mov     w12, #','
        strb    w12, [x22], #1
3:      mov     w12, #'"'
        strb    w12, [x22], #1
        ldr     x10, [x19, x9, lsl #3]
        ldr     x11, [x10, #E_KLEN]
        add     x10, x10, #E_KEY
4:      ldrb    w13, [x10], #1
        strb    w13, [x22], #1
        subs    x11, x11, #1
        b.ne    4b
        strb    w12, [x22], #1
        add     x9, x9, #1
        b       Ll_key
Ll_close:
        mov     w12, #']'
        strb    w12, [x22], #1
        bl      _store_unlock
        mov     x0, x21
        sub     x1, x22, x21
        b       Ll_ret

Ll_oom:
        bl      _store_unlock
        mov     x0, #0
        mov     x1, #0
Ll_ret:
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret
