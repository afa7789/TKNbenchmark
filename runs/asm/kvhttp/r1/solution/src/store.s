// store.s — thread-safe in-memory key/value store.
//
// Keys live in a sorted array of entry pointers (binary search for lookup,
// memmove for insert/delete), which makes the sorted key listing trivial.
// Values are reference-counted blobs so a reader can stream a value to its
// client without holding the lock while a writer replaces or deletes it.

        .include "macros.inc"

        .zerofill __DATA,__bss,_g_lock,64,4         // pthread_mutex_t
        .zerofill __DATA,__bss,_g_entries,8,3       // entry **
        .zerofill __DATA,__bss,_g_count,8,3
        .zerofill __DATA,__bss,_g_cap,8,3

        .text

// int store_init(void) — returns 0 on success.
        .globl  _store_init
        .p2align 2
_store_init:
        LOADADDR x0, _g_lock
        mov     x1, #0
        b       _pthread_mutex_init

        .p2align 2
store_lock:
        LOADADDR x0, _g_lock
        b       _pthread_mutex_lock

        .p2align 2
store_unlock:
        LOADADDR x0, _g_lock
        b       _pthread_mutex_unlock

// long key_cmp(a x0, alen x1, b x2, blen x3) — leaf, bytewise ordering.
        .p2align 2
key_cmp:
        cmp     x1, x3
        csel    x4, x1, x3, lo              // min length
        mov     x5, #0
1:      cmp     x5, x4
        b.hs    2f
        ldrb    w6, [x0, x5]
        ldrb    w7, [x2, x5]
        add     x5, x5, #1
        subs    w6, w6, w7
        b.eq    1b
        sxtw    x0, w6
        ret
2:      sub     x0, x1, x3
        ret

// (index x0, found x1) store_find(key x0, klen x1) — caller holds the lock.
// When not found, index is the insertion point.
        .p2align 2
store_find:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        mov     x19, x0                     // key
        mov     x20, x1                     // klen
        mov     x21, #0                     // lo
        adrp    x8, _g_count@PAGE
        ldr     x22, [x8, _g_count@PAGEOFF] // hi
        adrp    x8, _g_entries@PAGE
        ldr     x23, [x8, _g_entries@PAGEOFF]
1:      cmp     x21, x22
        b.hs    3f
        add     x24, x21, x22
        lsr     x24, x24, #1                // mid
        ldr     x9, [x23, x24, lsl #3]
        mov     x0, x19
        mov     x1, x20
        add     x2, x9, #ENT_KEY
        ldr     x3, [x9, #ENT_KLEN]
        bl      key_cmp
        cmp     x0, #0
        b.eq    2f
        b.lt    4f
        add     x21, x24, #1                // key > mid
        b       1b
4:      mov     x22, x24                    // key < mid
        b       1b
2:      mov     x0, x24
        mov     x1, #1
        b       5f
3:      mov     x0, x21
        mov     x1, #0
5:      ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ret

// void blob_release(blob x0) — drop one reference, free on last.
        .globl  _blob_release
        .p2align 2
_blob_release:
        cbz     x0, 1f
        mov     x1, #-1
        ldaddal x1, x2, [x0]
        cmp     x2, #1
        b.ne    1f
        b       _free
1:      ret

// long store_put(key x0, klen x1, blob x2)
//   -> 1 created, 0 replaced, -1 out of memory (blob ownership not taken).
// On success the store owns the caller's reference to blob.
        .globl  _store_put
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

        // Build the entry outside the lock; discarded if the key exists.
        mov     x0, #ENT_SIZE
        bl      _malloc
        cbz     x0, Lput_oom
        mov     x22, x0
        stp     x20, x21, [x22, #ENT_KLEN]
        add     x0, x22, #ENT_KEY
        mov     x1, x19
        mov     x2, x20
        bl      _memcpy

        bl      store_lock
        mov     x0, x19
        mov     x1, x20
        bl      store_find
        mov     x23, x0                     // index
        cbnz    x1, Lput_replace

        adrp    x8, _g_count@PAGE
        ldr     x9, [x8, _g_count@PAGEOFF]
        adrp    x10, _g_cap@PAGE
        ldr     x11, [x10, _g_cap@PAGEOFF]
        cmp     x9, x11
        b.lo    Lput_room
        lsl     x24, x11, #1
        mov     x12, #64
        cmp     x11, #0
        csel    x24, x12, x24, eq           // new capacity
        adrp    x8, _g_entries@PAGE
        ldr     x0, [x8, _g_entries@PAGEOFF]
        lsl     x1, x24, #3
        bl      _realloc
        cbz     x0, Lput_oom_locked
        adrp    x8, _g_entries@PAGE
        str     x0, [x8, _g_entries@PAGEOFF]
        adrp    x8, _g_cap@PAGE
        str     x24, [x8, _g_cap@PAGEOFF]

Lput_room:
        adrp    x8, _g_entries@PAGE
        ldr     x24, [x8, _g_entries@PAGEOFF]
        adrp    x8, _g_count@PAGE
        ldr     x9, [x8, _g_count@PAGEOFF]
        add     x10, x9, #1
        str     x10, [x8, _g_count@PAGEOFF]
        add     x1, x24, x23, lsl #3        // &e[idx]
        add     x0, x1, #8                  // &e[idx+1]
        sub     x2, x9, x23
        lsl     x2, x2, #3
        bl      _memmove
        str     x22, [x24, x23, lsl #3]
        bl      store_unlock
        mov     x0, #1
        b       Lput_ret

Lput_replace:
        adrp    x8, _g_entries@PAGE
        ldr     x8, [x8, _g_entries@PAGEOFF]
        ldr     x9, [x8, x23, lsl #3]
        ldr     x24, [x9, #ENT_BLOB]        // old value
        str     x21, [x9, #ENT_BLOB]
        bl      store_unlock
        mov     x0, x24
        bl      _blob_release
        mov     x0, x22
        bl      _free
        mov     x0, #0
        b       Lput_ret

Lput_oom_locked:
        bl      store_unlock
        mov     x0, x22
        bl      _free
Lput_oom:
        mov     x0, #-1
Lput_ret:
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ret

// blob *store_get(key x0, klen x1) — returns a new reference, or NULL.
        .globl  _store_get
        .p2align 2
_store_get:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        mov     x19, x0
        mov     x20, x1
        bl      store_lock
        mov     x0, x19
        mov     x1, x20
        bl      store_find
        mov     x19, #0
        cbz     x1, 1f
        adrp    x8, _g_entries@PAGE
        ldr     x8, [x8, _g_entries@PAGEOFF]
        ldr     x9, [x8, x0, lsl #3]
        ldr     x19, [x9, #ENT_BLOB]
        mov     x10, #1
        stadd   x10, [x19]                  // ordered by the mutex release below
1:      bl      store_unlock
        mov     x0, x19
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// long store_delete(key x0, klen x1) — 1 if deleted, 0 if absent.
        .globl  _store_delete
        .p2align 2
_store_delete:
        stp     x29, x30, [sp, #-32]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        mov     x19, x0
        mov     x20, x1
        bl      store_lock
        mov     x0, x19
        mov     x1, x20
        bl      store_find
        cbz     x1, 1f
        adrp    x8, _g_entries@PAGE
        ldr     x10, [x8, _g_entries@PAGEOFF]
        ldr     x19, [x10, x0, lsl #3]      // victim entry
        adrp    x8, _g_count@PAGE
        ldr     x9, [x8, _g_count@PAGEOFF]
        sub     x9, x9, #1
        str     x9, [x8, _g_count@PAGEOFF]
        sub     x2, x9, x0
        lsl     x2, x2, #3
        add     x0, x10, x0, lsl #3         // &e[idx]
        add     x1, x0, #8                  // &e[idx+1]
        bl      _memmove
        bl      store_unlock
        ldr     x0, [x19, #ENT_BLOB]
        bl      _blob_release
        mov     x0, x19
        bl      _free
        mov     x0, #1
        b       2f
1:      bl      store_unlock
        mov     x0, #0
2:      ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #32
        ret

// (buf x0, len x1) store_list(void) — malloc'd JSON array of all keys in
// ascending order; buf is NULL on allocation failure. Keys never need JSON
// escaping because of the restricted key alphabet.
        .globl  _store_list
        .p2align 2
_store_list:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        bl      store_lock
        adrp    x8, _g_count@PAGE
        ldr     x19, [x8, _g_count@PAGEOFF]
        adrp    x8, _g_entries@PAGE
        ldr     x20, [x8, _g_entries@PAGEOFF]

        // size = "[" + "]" + sum(klen + 2 quotes) + (count - 1) commas
        mov     x21, #2
        mov     x9, #0
1:      cmp     x9, x19
        b.hs    2f
        ldr     x10, [x20, x9, lsl #3]
        ldr     x11, [x10, #ENT_KLEN]
        add     x21, x21, x11
        add     x21, x21, #3
        add     x9, x9, #1
        b       1b
2:      cmp     x19, #0
        cset    x9, ne
        sub     x21, x21, x9

        mov     x0, x21
        bl      _malloc
        mov     x22, x0
        cbz     x0, 7f

        mov     x0, x22                     // write cursor
        mov     w12, #'['
        strb    w12, [x0], #1
        mov     w13, #'"'
        mov     w14, #','
        mov     x9, #0
3:      cmp     x9, x19
        b.hs    6f
        cbz     x9, 4f
        strb    w14, [x0], #1
4:      strb    w13, [x0], #1
        ldr     x10, [x20, x9, lsl #3]
        ldr     x11, [x10, #ENT_KLEN]
        add     x10, x10, #ENT_KEY
5:      ldrb    w15, [x10], #1
        strb    w15, [x0], #1
        subs    x11, x11, #1
        b.ne    5b
        strb    w13, [x0], #1
        add     x9, x9, #1
        b       3b
6:      mov     w12, #']'
        strb    w12, [x0]
7:      bl      store_unlock
        mov     x0, x22
        mov     x1, x21
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret
