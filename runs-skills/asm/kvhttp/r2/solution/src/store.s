// store.s — thread-safe in-memory key/value store.
//
// Representation: a dense array of entry pointers kept sorted by key
// (byte-wise, shorter-prefix first).  Lookup is a binary search; insert and
// delete shift the pointer array with memmove.  Sorted order makes the
// `GET /kv` listing a straight walk.  One global mutex guards everything.
//
// Public interface (all return an HTTP status code in w0):
//   int kv_put(const char *key, size_t klen, void *val, size_t vlen)
//         201 new, 200 replaced, 500 OOM.  Takes ownership of `val`
//         (malloc'd or NULL when vlen == 0) in every case.
//   int kv_get(const char *key, size_t klen, void **out, size_t *outlen)
//         200 with a malloc'd copy in *out, 404 absent, 500 OOM.
//   int kv_delete(const char *key, size_t klen)
//         204 deleted, 404 absent.
//   int kv_list(void **out, size_t *outlen)
//         200 with a malloc'd JSON array of all keys, 500 OOM.

    // entry layout (malloc'd, E_SIZE bytes)
    .equ E_KLEN,   0            // size_t key length (1..64)
    .equ E_VAL,    8            // void * value bytes (may be NULL if empty)
    .equ E_VLEN,  16            // size_t value length
    .equ E_KEY,   24            // char key[64]
    .equ E_SIZE,  88

    // store layout
    .equ S_LOCK,     0          // pthread_mutex_t (64 bytes)
    .equ S_ENTRIES, 64          // entry **, sorted
    .equ S_COUNT,   72          // size_t
    .equ S_CAP,     80          // size_t (capacity of S_ENTRIES)

    .equ INITIAL_CAP, 64

    .data
    .p2align 3
Lstore:
    .quad 0x32AAABA7            // PTHREAD_MUTEX_INITIALIZER signature
    .space 56
    .quad 0                     // entries
    .quad 0                     // count
    .quad 0                     // cap

    .text

// ---------------------------------------------------------------------------
// kv_find_locked — binary search (leaf, caller holds the lock).
//   in:  x0 = key, x1 = klen, x2 = store base
//   out: x0 = index (match or insertion point), x1 = 1 if found else 0
// Clobbers x3-x15.
    .private_extern _kv_find_locked
    .p2align 2
_kv_find_locked:
    ldr     x8, [x2, #S_ENTRIES]
    ldr     x9, [x2, #S_COUNT]          // hi
    mov     x10, #0                     // lo
Lfind_loop:
    cmp     x10, x9
    b.hs    Lfind_miss
    add     x11, x10, x9
    lsr     x11, x11, #1                // mid
    ldr     x12, [x8, x11, lsl #3]
    ldr     x13, [x12, #E_KLEN]
    add     x14, x12, #E_KEY
    cmp     x1, x13
    csel    x15, x1, x13, lo            // common prefix length
    mov     x3, #0
Lfind_cmp:
    cmp     x3, x15
    b.hs    Lfind_prefix
    ldrb    w4, [x0, x3]
    ldrb    w5, [x14, x3]
    add     x3, x3, #1
    cmp     w4, w5
    b.eq    Lfind_cmp
    b.lo    Lfind_less
    b       Lfind_greater
Lfind_prefix:
    cmp     x1, x13
    b.eq    Lfind_hit
    b.lo    Lfind_less
Lfind_greater:                          // key > entries[mid]
    add     x10, x11, #1
    b       Lfind_loop
Lfind_less:                             // key < entries[mid]
    mov     x9, x11
    b       Lfind_loop
Lfind_hit:
    mov     x0, x11
    mov     x1, #1
    ret
Lfind_miss:
    mov     x0, x10
    mov     x1, #0
    ret

// ---------------------------------------------------------------------------
    .globl  _kv_put
    .p2align 2
_kv_put:
    .cfi_startproc
    stp     x26, x25, [sp, #-80]!
    stp     x24, x23, [sp, #16]
    stp     x22, x21, [sp, #32]
    stp     x20, x19, [sp, #48]
    stp     x29, x30, [sp, #64]
    add     x29, sp, #64
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
    mov     x19, x0                     // key
    mov     x20, x1                     // klen
    mov     x21, x2                     // value
    mov     x22, x3                     // vlen
    adrp    x25, Lstore@PAGE
    add     x25, x25, Lstore@PAGEOFF
    mov     x0, x25
    bl      _pthread_mutex_lock

    mov     x0, x19
    mov     x1, x20
    mov     x2, x25
    bl      _kv_find_locked
    mov     x23, x0                     // index
    cbz     x1, Lput_new

    // replace in place; the old value is freed after unlocking
    ldr     x8, [x25, #S_ENTRIES]
    ldr     x8, [x8, x23, lsl #3]
    ldr     x24, [x8, #E_VAL]
    stp     x21, x22, [x8, #E_VAL]
    mov     w26, #200
    b       Lput_unlock

Lput_new:
    ldp     x8, x9, [x25, #S_COUNT]     // count, cap
    cmp     x8, x9
    b.lo    Lput_alloc
    lsl     x9, x9, #1
    mov     x10, #INITIAL_CAP
    cmp     x9, x10
    csel    x26, x9, x10, hs            // new cap = max(2*cap, INITIAL_CAP)
    ldr     x0, [x25, #S_ENTRIES]
    lsl     x1, x26, #3
    bl      _realloc
    cbz     x0, Lput_fail
    str     x0, [x25, #S_ENTRIES]
    str     x26, [x25, #S_CAP]
Lput_alloc:
    mov     x0, #E_SIZE
    bl      _malloc
    cbz     x0, Lput_fail
    mov     x24, x0
    str     x20, [x24, #E_KLEN]
    stp     x21, x22, [x24, #E_VAL]
    add     x0, x24, #E_KEY
    mov     x1, x19
    mov     x2, x20
    bl      _memcpy
    // open a slot: memmove(&e[idx+1], &e[idx], (count-idx)*8)
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
    mov     x24, #0                     // nothing to free
    mov     w26, #201

Lput_unlock:
    mov     x0, x25
    bl      _pthread_mutex_unlock
    mov     x0, x24
    bl      _free
    mov     w0, w26
    ldp     x29, x30, [sp, #64]
    ldp     x20, x19, [sp, #48]
    ldp     x22, x21, [sp, #32]
    ldp     x24, x23, [sp, #16]
    ldp     x26, x25, [sp], #80
    ret

Lput_fail:
    mov     x24, x21                    // drop the value we were handed
    mov     w26, #500
    b       Lput_unlock
    .cfi_endproc

// ---------------------------------------------------------------------------
    .globl  _kv_get
    .p2align 2
_kv_get:
    .cfi_startproc
    stp     x24, x23, [sp, #-64]!
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
    mov     x19, x0
    mov     x20, x1
    mov     x21, x2                     // out
    mov     x22, x3                     // outlen
    str     xzr, [x21]
    str     xzr, [x22]
    adrp    x23, Lstore@PAGE
    add     x23, x23, Lstore@PAGEOFF
    mov     x0, x23
    bl      _pthread_mutex_lock

    mov     x0, x19
    mov     x1, x20
    mov     x2, x23
    bl      _kv_find_locked
    mov     w24, #404
    cbz     x1, Lget_unlock

    ldr     x8, [x23, #S_ENTRIES]
    ldr     x8, [x8, x0, lsl #3]
    ldp     x19, x20, [x8, #E_VAL]      // value, vlen
    cmp     x20, #0
    csinc   x0, x20, xzr, ne            // malloc(vlen ? vlen : 1)
    bl      _malloc
    mov     w24, #500
    cbz     x0, Lget_unlock
    str     x0, [x21]
    str     x20, [x22]
    mov     w24, #200
    cbz     x20, Lget_unlock
    mov     x1, x19
    mov     x2, x20
    bl      _memcpy

Lget_unlock:
    mov     x0, x23
    bl      _pthread_mutex_unlock
    mov     w0, w24
    ldp     x29, x30, [sp, #48]
    ldp     x20, x19, [sp, #32]
    ldp     x22, x21, [sp, #16]
    ldp     x24, x23, [sp], #64
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
    .globl  _kv_delete
    .p2align 2
_kv_delete:
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
    adrp    x21, Lstore@PAGE
    add     x21, x21, Lstore@PAGEOFF
    mov     x0, x21
    bl      _pthread_mutex_lock

    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    bl      _kv_find_locked
    mov     x20, #0                     // entry to free
    mov     w22, #404
    cbz     x1, Ldel_unlock

    // close the gap: memmove(&e[idx], &e[idx+1], (count-idx-1)*8)
    ldr     x8, [x21, #S_ENTRIES]
    ldr     x9, [x21, #S_COUNT]
    ldr     x20, [x8, x0, lsl #3]
    sub     x2, x9, x0
    sub     x2, x2, #1
    lsl     x2, x2, #3
    sub     x9, x9, #1
    str     x9, [x21, #S_COUNT]
    add     x0, x8, x0, lsl #3
    add     x1, x0, #8
    bl      _memmove
    mov     w22, #204

Ldel_unlock:
    mov     x0, x21
    bl      _pthread_mutex_unlock
    cbz     x20, Ldel_ret
    ldr     x0, [x20, #E_VAL]
    bl      _free
    mov     x0, x20
    bl      _free
Ldel_ret:
    mov     w0, w22
    ldp     x29, x30, [sp, #32]
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #48
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
    .globl  _kv_list
    .p2align 2
_kv_list:
    .cfi_startproc
    stp     x24, x23, [sp, #-64]!
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
    mov     x19, x0                     // out
    mov     x20, x1                     // outlen
    str     xzr, [x19]
    str     xzr, [x20]
    adrp    x21, Lstore@PAGE
    add     x21, x21, Lstore@PAGEOFF
    mov     x0, x21
    bl      _pthread_mutex_lock

    ldr     x22, [x21, #S_COUNT]
    ldr     x23, [x21, #S_ENTRIES]

    // size = 2 + sum(klen + 3)   ('[' ']' plus quotes and a comma per key)
    mov     x0, #2
    mov     x8, #0
Llist_size:
    cmp     x8, x22
    b.hs    Llist_alloc
    ldr     x9, [x23, x8, lsl #3]
    ldr     x9, [x9, #E_KLEN]
    add     x0, x0, x9
    add     x0, x0, #3
    add     x8, x8, #1
    b       Llist_size
Llist_alloc:
    bl      _malloc
    mov     w24, #500
    cbz     x0, Llist_unlock
    str     x0, [x19]

    mov     x1, x0                      // write cursor
    mov     w10, #'['
    strb    w10, [x1], #1
    mov     x8, #0
Llist_key:
    cmp     x8, x22
    b.hs    Llist_close
    cbz     x8, 1f
    mov     w10, #','
    strb    w10, [x1], #1
1:  mov     w10, #'"'
    strb    w10, [x1], #1
    ldr     x9, [x23, x8, lsl #3]
    ldr     x11, [x9, #E_KLEN]
    add     x9, x9, #E_KEY
2:  ldrb    w12, [x9], #1               // klen >= 1 by invariant
    strb    w12, [x1], #1
    subs    x11, x11, #1
    b.ne    2b
    strb    w10, [x1], #1               // closing quote
    add     x8, x8, #1
    b       Llist_key
Llist_close:
    mov     w10, #']'
    strb    w10, [x1], #1
    sub     x1, x1, x0
    str     x1, [x20]
    mov     w24, #200

Llist_unlock:
    mov     x0, x21
    bl      _pthread_mutex_unlock
    mov     w0, w24
    ldp     x29, x30, [sp, #48]
    ldp     x20, x19, [sp, #32]
    ldp     x22, x21, [sp, #16]
    ldp     x24, x23, [sp], #64
    ret
    .cfi_endproc

.subsections_via_symbols
