// store.s — thread-safe in-memory key/value store for kvhttp.
//
// Entries are kept in a pointer array sorted by key (bytewise, then by
// length), which gives O(log n) lookup and makes the sorted key listing
// for `GET /kv` a linear walk. A single mutex guards the whole store.
//
// Public API (all functions take/return per AAPCS64):
//   store_init()                                   -> void
//   store_put(key, klen, val, vlen)                -> 1 new, 0 replaced, -1 OOM
//        On success the store takes ownership of `val` (malloc'd).
//   store_get(key, klen, out_ptr*, out_len*)       -> 1 found, 0 absent, -1 OOM
//        On success *out_ptr is a malloc'd copy the caller must free.
//   store_delete(key, klen)                        -> 1 deleted, 0 absent
//   store_list(out_ptr*, out_len*)                 -> 0 ok, -1 OOM
//        Produces a JSON array of all keys; caller frees *out_ptr.

        // Entry record (malloc'd, one per key)
        .equ    E_KLEN, 0
        .equ    E_VAL, 8
        .equ    E_VLEN, 16
        .equ    E_KEY, 24
        .equ    E_SIZE, 88              // 24 + 64-byte key

        // Store state record
        .equ    S_LOCK, 0               // pthread_mutex_t (64 bytes)
        .equ    S_ENTRIES, 64           // Entry** sorted array
        .equ    S_COUNT, 72
        .equ    S_CAP, 80
        .equ    S_SIZE, 88

        .equ    INITIAL_CAP, 64

        .zerofill __DATA,__bss,L_store,S_SIZE,4

// Load the address of the store state into \reg.
.macro  STORE_ADDR reg
        adrp    \reg, L_store@PAGE
        add     \reg, \reg, L_store@PAGEOFF
.endm

        .section __TEXT,__text,regular,pure_instructions

// void store_init(void)
        .globl  _store_init
        .p2align 2
_store_init:
        STORE_ADDR x0
        mov     x1, #0
        b       _pthread_mutex_init

// Leaf. Compare key (x0, x1) with Entry* x2.
// Returns x0 <0, 0, >0. Clobbers x0-x7 only.
        .p2align 2
L_keycmp:
        ldr     x3, [x2, #E_KLEN]
        add     x2, x2, #E_KEY
        cmp     x1, x3
        csel    x4, x1, x3, lo          // common prefix length
        mov     x5, #0
1:      cmp     x5, x4
        b.hs    2f
        ldrb    w6, [x0, x5]
        ldrb    w7, [x2, x5]
        add     x5, x5, #1
        cmp     w6, w7
        b.eq    1b
        sub     x0, x6, x7
        ret
2:      sub     x0, x1, x3
        ret

// Binary search; caller holds the lock.
// In: x0 key, x1 klen. Out: x0 index (match or insertion point), x1 found.
        .p2align 2
L_find:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        mov     x19, x0
        mov     x20, x1
        STORE_ADDR x8
        mov     x21, #0                 // lo
        ldr     x22, [x8, #S_COUNT]     // hi
        ldr     x23, [x8, #S_ENTRIES]
1:      cmp     x21, x22
        b.hs    3f
        add     x24, x21, x22
        lsr     x24, x24, #1            // mid
        ldr     x2, [x23, x24, lsl #3]
        mov     x0, x19
        mov     x1, x20
        bl      L_keycmp
        cmp     x0, #0
        b.eq    2f
        b.lt    4f
        add     x21, x24, #1
        b       1b
4:      mov     x22, x24
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

// long store_put(const char *key, size_t klen, void *val, size_t vlen)
        .globl  _store_put
        .p2align 2
_store_put:
        stp     x29, x30, [sp, #-80]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        stp     x25, x26, [sp, #64]
        mov     x19, x0                 // key
        mov     x20, x1                 // klen
        mov     x21, x2                 // val
        mov     x22, x3                 // vlen
        STORE_ADDR x25
        mov     x0, x25
        bl      _pthread_mutex_lock
        mov     x0, x19
        mov     x1, x20
        bl      L_find
        mov     x23, x0                 // index
        cbz     x1, Lput_new

        // Replace the value of an existing entry.
        ldr     x8, [x25, #S_ENTRIES]
        ldr     x9, [x8, x23, lsl #3]
        ldr     x24, [x9, #E_VAL]       // old value, freed outside the lock
        str     x21, [x9, #E_VAL]
        str     x22, [x9, #E_VLEN]
        mov     x0, x25
        bl      _pthread_mutex_unlock
        mov     x0, x24
        bl      _free
        mov     x0, #0
        b       Lput_ret

Lput_new:
        ldr     x9, [x25, #S_COUNT]
        ldr     x10, [x25, #S_CAP]
        cmp     x9, x10
        b.lo    Lput_have_cap
        lsl     x26, x10, #1
        mov     x11, #INITIAL_CAP
        cmp     x10, #0
        csel    x26, x11, x26, eq       // new capacity
        ldr     x0, [x25, #S_ENTRIES]
        lsl     x1, x26, #3
        bl      _realloc
        cbz     x0, Lput_oom
        str     x0, [x25, #S_ENTRIES]
        str     x26, [x25, #S_CAP]
Lput_have_cap:
        mov     x0, #E_SIZE
        bl      _malloc
        cbz     x0, Lput_oom
        mov     x24, x0
        str     x20, [x24, #E_KLEN]
        str     x21, [x24, #E_VAL]
        str     x22, [x24, #E_VLEN]
        add     x0, x24, #E_KEY
        mov     x1, x19
        mov     x2, x20
        bl      _memcpy
        // Open a slot at `index`.
        ldr     x8, [x25, #S_ENTRIES]
        ldr     x9, [x25, #S_COUNT]
        add     x1, x8, x23, lsl #3
        add     x0, x1, #8
        sub     x2, x9, x23
        lsl     x2, x2, #3
        bl      _memmove
        ldr     x8, [x25, #S_ENTRIES]
        str     x24, [x8, x23, lsl #3]
        ldr     x9, [x25, #S_COUNT]
        add     x9, x9, #1
        str     x9, [x25, #S_COUNT]
        mov     x0, x25
        bl      _pthread_mutex_unlock
        mov     x0, #1
        b       Lput_ret

Lput_oom:
        mov     x0, x25
        bl      _pthread_mutex_unlock
        mov     x0, #-1
Lput_ret:
        ldp     x25, x26, [sp, #64]
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #80
        ret

// long store_get(const char *key, size_t klen, void **out, size_t *outlen)
        .globl  _store_get
        .p2align 2
_store_get:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        mov     x19, x0
        mov     x20, x1
        mov     x21, x2
        mov     x22, x3
        STORE_ADDR x23
        mov     x0, x23
        bl      _pthread_mutex_lock
        mov     x0, x19
        mov     x1, x20
        bl      L_find
        cbz     x1, Lget_absent
        ldr     x8, [x23, #S_ENTRIES]
        ldr     x24, [x8, x0, lsl #3]   // entry
        ldr     x0, [x24, #E_VLEN]
        cmp     x0, #0
        csinc   x0, x0, xzr, ne         // malloc(max(vlen, 1))
        bl      _malloc
        cbz     x0, Lget_oom
        mov     x19, x0
        ldr     x1, [x24, #E_VAL]
        ldr     x2, [x24, #E_VLEN]
        bl      _memcpy
        str     x19, [x21]
        ldr     x9, [x24, #E_VLEN]
        str     x9, [x22]
        mov     x19, #1
        b       Lget_unlock
Lget_absent:
        mov     x19, #0
        b       Lget_unlock
Lget_oom:
        mov     x19, #-1
Lget_unlock:
        mov     x0, x23
        bl      _pthread_mutex_unlock
        mov     x0, x19
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ret

// long store_delete(const char *key, size_t klen)
        .globl  _store_delete
        .p2align 2
_store_delete:
        stp     x29, x30, [sp, #-48]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        mov     x19, x0
        mov     x20, x1
        STORE_ADDR x21
        mov     x0, x21
        bl      _pthread_mutex_lock
        mov     x0, x19
        mov     x1, x20
        bl      L_find
        cbz     x1, Ldel_absent
        ldr     x8, [x21, #S_ENTRIES]
        ldr     x22, [x8, x0, lsl #3]   // entry being removed
        ldr     x9, [x21, #S_COUNT]
        sub     x9, x9, #1
        str     x9, [x21, #S_COUNT]
        // Close the gap: memmove(&a[i], &a[i+1], (count-1-i)*8)
        sub     x2, x9, x0
        lsl     x2, x2, #3
        add     x0, x8, x0, lsl #3
        add     x1, x0, #8
        bl      _memmove
        mov     x0, x21
        bl      _pthread_mutex_unlock
        ldr     x0, [x22, #E_VAL]
        bl      _free
        mov     x0, x22
        bl      _free
        mov     x0, #1
        b       Ldel_ret
Ldel_absent:
        mov     x0, x21
        bl      _pthread_mutex_unlock
        mov     x0, #0
Ldel_ret:
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #48
        ret

// long store_list(char **out, size_t *outlen)
        .globl  _store_list
        .p2align 2
_store_list:
        stp     x29, x30, [sp, #-64]!
        mov     x29, sp
        stp     x19, x20, [sp, #16]
        stp     x21, x22, [sp, #32]
        stp     x23, x24, [sp, #48]
        mov     x19, x0
        mov     x20, x1
        STORE_ADDR x21
        mov     x0, x21
        bl      _pthread_mutex_lock
        ldr     x22, [x21, #S_COUNT]
        ldr     x23, [x21, #S_ENTRIES]
        // Size: "[" + "]" + per key: quotes, comma, key bytes.
        mov     x0, #2
        mov     x9, #0
1:      cmp     x9, x22
        b.hs    2f
        ldr     x10, [x23, x9, lsl #3]
        ldr     x10, [x10, #E_KLEN]
        add     x0, x0, x10
        add     x0, x0, #3
        add     x9, x9, #1
        b       1b
2:      bl      _malloc
        cbz     x0, Llist_oom
        mov     x24, x0
        mov     x0, x24                 // write cursor
        mov     w11, #'['
        strb    w11, [x0], #1
        mov     x9, #0
3:      cmp     x9, x22
        b.hs    6f
        cbz     x9, 4f
        mov     w11, #','
        strb    w11, [x0], #1
4:      mov     w11, #'"'
        strb    w11, [x0], #1
        ldr     x10, [x23, x9, lsl #3]
        ldr     x12, [x10, #E_KLEN]
        add     x10, x10, #E_KEY
5:      ldrb    w13, [x10], #1
        strb    w13, [x0], #1
        subs    x12, x12, #1
        b.ne    5b
        strb    w11, [x0], #1
        add     x9, x9, #1
        b       3b
6:      mov     w11, #']'
        strb    w11, [x0], #1
        sub     x0, x0, x24
        str     x24, [x19]
        str     x0, [x20]
        mov     x22, #0
        b       Llist_unlock
Llist_oom:
        mov     x22, #-1
Llist_unlock:
        mov     x0, x21
        bl      _pthread_mutex_unlock
        mov     x0, x22
        ldp     x23, x24, [sp, #48]
        ldp     x21, x22, [sp, #32]
        ldp     x19, x20, [sp, #16]
        ldp     x29, x30, [sp], #64
        ret
