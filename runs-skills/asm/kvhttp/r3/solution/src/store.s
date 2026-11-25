// store.s - thread-safe in-memory key/value store.
//
// A chained hash table (FNV-1a, power-of-two bucket count, doubled when the
// load factor reaches 1) guarded by a single pthread mutex.
//
// Public interface (C prototypes):
//   int    store_init(void);                                  0 ok, -1 error
//   int    store_put(const char *key, size_t klen,
//                    void *val, size_t vlen);                  1 new, 0 replaced, -1 OOM
//          On success the store takes ownership of `val` (a malloc'd block).
//   int    store_get(const char *key, size_t klen,
//                    void **out, size_t *outlen);              0 found, 1 absent, -1 OOM
//          On success *out is a malloc'd copy the caller must free.
//   int    store_delete(const char *key, size_t klen);       1 deleted, 0 absent
//   char  *store_list_json(size_t *outlen);                  malloc'd JSON array of the
//          keys sorted ascending, or NULL on OOM.

// Entry layout
    .equ E_NEXT,  0
    .equ E_HASH,  8
    .equ E_VAL,   16
    .equ E_VLEN,  24              // must follow E_VAL (stored as a pair)
    .equ E_KLEN,  32
    .equ E_KEY,   40              // up to 64 bytes + NUL
    .equ E_SIZE,  112

// Store layout
    .equ S_LOCK,     0            // pthread_mutex_t (64 bytes)
    .equ S_BUCKETS,  64
    .equ S_NBUCKETS, 72
    .equ S_COUNT,    80
    .equ S_SIZE,     88

    .equ INITIAL_BUCKETS, 1024
    .equ JSON_PER_KEY, 67         // 64 key bytes + 2 quotes + 1 comma

.macro STORE reg
    adrp    \reg, _kv_store@PAGE
    add     \reg, \reg, _kv_store@PAGEOFF
.endm

    .text

// ---------------------------------------------------------------------------
// int store_init(void)
    .globl  _store_init
    .private_extern _store_init
    .p2align 2
_store_init:
    .cfi_startproc
    sub     sp, sp, #32
    stp     x20, x19, [sp]
    stp     x29, x30, [sp, #16]
    add     x29, sp, #16
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    STORE   x19
    mov     x0, x19
    mov     x1, #0
    bl      _pthread_mutex_init
    cbnz    w0, Linit_fail
    mov     x0, #INITIAL_BUCKETS
    mov     x1, #8
    bl      _calloc
    cbz     x0, Linit_fail
    str     x0, [x19, #S_BUCKETS]
    mov     x0, #INITIAL_BUCKETS
    str     x0, [x19, #S_NBUCKETS]
    str     xzr, [x19, #S_COUNT]
    mov     w0, #0
    b       Linit_ret
Linit_fail:
    mov     w0, #-1
Linit_ret:
    ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp]
    add     sp, sp, #32
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// uint64_t kv_hash(const char *key, size_t klen)   FNV-1a, leaf
// Clobbers x0-x4.
    .p2align 2
_kv_hash:
    .cfi_startproc
    movz    x2, #0x2325
    movk    x2, #0x8422, lsl #16
    movk    x2, #0x9ce4, lsl #32
    movk    x2, #0xcbf2, lsl #48          // offset basis
    movz    x3, #0x01b3
    movk    x3, #0x0100, lsl #32          // prime
    cbz     x1, 2f
1:  ldrb    w4, [x0], #1
    eor     x2, x2, x4
    mul     x2, x2, x3
    subs    x1, x1, #1
    b.ne    1b
2:  mov     x0, x2
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// kv_find(key x0, klen x1, hash x2) -> x0 = link slot, x1 = entry or NULL
// The slot is the pointer that refers to the entry (or the terminating NULL).
// Caller holds the lock. Leaf; clobbers x0-x10.
    .p2align 2
_kv_find:
    .cfi_startproc
    STORE   x9
    ldr     x10, [x9, #S_NBUCKETS]
    ldr     x9, [x9, #S_BUCKETS]
    sub     x10, x10, #1
    and     x10, x2, x10
    add     x3, x9, x10, lsl #3
1:  ldr     x4, [x3]
    cbz     x4, 4f
    ldr     x5, [x4, #E_HASH]
    cmp     x5, x2
    b.ne    3f
    ldr     x5, [x4, #E_KLEN]
    cmp     x5, x1
    b.ne    3f
    add     x8, x4, #E_KEY
    mov     x6, #0
2:  cmp     x6, x1
    b.eq    4f
    ldrb    w7, [x0, x6]
    ldrb    w5, [x8, x6]
    add     x6, x6, #1
    cmp     w7, w5
    b.eq    2b
3:  add     x3, x4, #E_NEXT
    b       1b
4:  mov     x0, x3
    mov     x1, x4
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// void kv_grow(void)  Double the bucket array if the load factor reached 1.
// Best effort: on allocation failure the table keeps its current size.
// Caller holds the lock.
    .p2align 2
_kv_grow:
    .cfi_startproc
    sub     sp, sp, #48
    stp     x22, x21, [sp]
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
    STORE   x19
    ldr     x20, [x19, #S_NBUCKETS]
    ldr     x8, [x19, #S_COUNT]
    cmp     x8, x20
    b.lo    Lgrow_ret
    lsl     x21, x20, #1
    mov     x0, x21
    mov     x1, #8
    bl      _calloc
    cbz     x0, Lgrow_ret
    mov     x22, x0
    ldr     x8, [x19, #S_BUCKETS]
    sub     x9, x21, #1                   // new mask
    mov     x10, #0
1:  ldr     x11, [x8, x10, lsl #3]
2:  cbz     x11, 3f
    ldr     x12, [x11, #E_NEXT]
    ldr     x13, [x11, #E_HASH]
    and     x13, x13, x9
    ldr     x14, [x22, x13, lsl #3]
    str     x14, [x11, #E_NEXT]
    str     x11, [x22, x13, lsl #3]
    mov     x11, x12
    b       2b
3:  add     x10, x10, #1
    cmp     x10, x20
    b.lo    1b
    str     x22, [x19, #S_BUCKETS]
    str     x21, [x19, #S_NBUCKETS]
    mov     x0, x8
    bl      _free
Lgrow_ret:
    ldp     x29, x30, [sp, #32]
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp]
    add     sp, sp, #48
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// int store_put(const char *key, size_t klen, void *val, size_t vlen)
    .globl  _store_put
    .private_extern _store_put
    .p2align 2
_store_put:
    .cfi_startproc
    sub     sp, sp, #80
    stp     x26, x25, [sp]
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
    mov     x19, x0                       // key
    mov     x20, x1                       // klen
    mov     x21, x2                       // val
    mov     x22, x3                       // vlen
    bl      _kv_hash
    mov     x23, x0                       // hash
    STORE   x24
    mov     x0, x24
    bl      _pthread_mutex_lock
    mov     x0, x19
    mov     x1, x20
    mov     x2, x23
    bl      _kv_find
    cbz     x1, Lput_new
    ldr     x25, [x1, #E_VAL]             // old value: freed after unlocking
    stp     x21, x22, [x1, #E_VAL]
    mov     w26, #0
    b       Lput_unlock
Lput_new:
    mov     x0, #1
    mov     x1, #E_SIZE
    bl      _calloc
    cbz     x0, Lput_oom
    mov     x25, x0
    str     x23, [x25, #E_HASH]
    stp     x21, x22, [x25, #E_VAL]
    str     x20, [x25, #E_KLEN]
    add     x0, x25, #E_KEY
    mov     x1, x19
    mov     x2, x20
    bl      _memcpy                       // NUL terminator comes from calloc
    bl      _kv_grow
    ldr     x8, [x24, #S_BUCKETS]
    ldr     x9, [x24, #S_NBUCKETS]
    sub     x9, x9, #1
    and     x9, x23, x9
    ldr     x10, [x8, x9, lsl #3]
    str     x10, [x25, #E_NEXT]
    str     x25, [x8, x9, lsl #3]
    ldr     x10, [x24, #S_COUNT]
    add     x10, x10, #1
    str     x10, [x24, #S_COUNT]
    mov     x25, #0                       // nothing to free
    mov     w26, #1
Lput_unlock:
    mov     x0, x24
    bl      _pthread_mutex_unlock
    mov     x0, x25
    bl      _free
    mov     w0, w26
    b       Lput_ret
Lput_oom:
    mov     x0, x24
    bl      _pthread_mutex_unlock
    mov     w0, #-1
Lput_ret:
    ldp     x29, x30, [sp, #64]
    ldp     x20, x19, [sp, #48]
    ldp     x22, x21, [sp, #32]
    ldp     x24, x23, [sp, #16]
    ldp     x26, x25, [sp]
    add     sp, sp, #80
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// int store_get(const char *key, size_t klen, void **out, size_t *outlen)
    .globl  _store_get
    .private_extern _store_get
    .p2align 2
_store_get:
    .cfi_startproc
    sub     sp, sp, #64
    stp     x24, x23, [sp]
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
    mov     x21, x2
    mov     x22, x3
    bl      _kv_hash
    mov     x23, x0
    STORE   x24
    mov     x0, x24
    bl      _pthread_mutex_lock
    mov     x0, x19
    mov     x1, x20
    mov     x2, x23
    bl      _kv_find
    cbz     x1, Lget_absent
    mov     x19, x1                       // entry
    ldr     x20, [x19, #E_VLEN]
    cmp     x20, #0
    csinc   x0, x20, xzr, ne              // malloc(vlen ? vlen : 1)
    bl      _malloc
    cbz     x0, Lget_oom
    str     x0, [x21]
    str     x20, [x22]
    ldr     x1, [x19, #E_VAL]
    mov     x2, x20
    bl      _memcpy
    mov     w23, #0
    b       Lget_unlock
Lget_absent:
    mov     w23, #1
    b       Lget_unlock
Lget_oom:
    mov     w23, #-1
Lget_unlock:
    mov     x0, x24
    bl      _pthread_mutex_unlock
    mov     w0, w23
    ldp     x29, x30, [sp, #48]
    ldp     x20, x19, [sp, #32]
    ldp     x22, x21, [sp, #16]
    ldp     x24, x23, [sp]
    add     sp, sp, #64
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// int store_delete(const char *key, size_t klen)
    .globl  _store_delete
    .private_extern _store_delete
    .p2align 2
_store_delete:
    .cfi_startproc
    sub     sp, sp, #48
    stp     x22, x21, [sp]
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
    bl      _kv_hash
    mov     x21, x0
    STORE   x22
    mov     x0, x22
    bl      _pthread_mutex_lock
    mov     x0, x19
    mov     x1, x20
    mov     x2, x21
    bl      _kv_find
    cbz     x1, Ldel_absent
    ldr     x8, [x1, #E_NEXT]
    str     x8, [x0]                      // unlink
    ldr     x8, [x22, #S_COUNT]
    sub     x8, x8, #1
    str     x8, [x22, #S_COUNT]
    mov     x19, x1
    mov     x0, x22
    bl      _pthread_mutex_unlock
    ldr     x0, [x19, #E_VAL]
    bl      _free
    mov     x0, x19
    bl      _free
    mov     w0, #1
    b       Ldel_ret
Ldel_absent:
    mov     x0, x22
    bl      _pthread_mutex_unlock
    mov     w0, #0
Ldel_ret:
    ldp     x29, x30, [sp, #32]
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp]
    add     sp, sp, #48
    ret
    .cfi_endproc

// ---------------------------------------------------------------------------
// int kv_entry_cmp(const void *a, const void *b)   qsort comparator on Entry**
    .p2align 2
_kv_entry_cmp:
    .cfi_startproc
    ldr     x0, [x0]
    ldr     x1, [x1]
    add     x0, x0, #E_KEY
    add     x1, x1, #E_KEY
    b       _strcmp
    .cfi_endproc

// ---------------------------------------------------------------------------
// char *store_list_json(size_t *outlen)
    .globl  _store_list_json
    .private_extern _store_list_json
    .p2align 2
_store_list_json:
    .cfi_startproc
    sub     sp, sp, #80
    stp     x26, x25, [sp]
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
    mov     x19, x0                       // outlen
    STORE   x20
    mov     x0, x20
    bl      _pthread_mutex_lock
    ldr     x21, [x20, #S_COUNT]          // n
    cmp     x21, #0
    csinc   x0, x21, xzr, ne
    lsl     x0, x0, #3
    bl      _malloc
    cbz     x0, Llist_oom
    mov     x22, x0                       // Entry *arr[n]
    mov     x8, #JSON_PER_KEY
    mov     x9, #2
    madd    x0, x21, x8, x9
    bl      _malloc
    cbz     x0, Llist_oom_arr
    mov     x23, x0                       // JSON buffer

    ldr     x8, [x20, #S_BUCKETS]
    ldr     x9, [x20, #S_NBUCKETS]
    mov     x10, #0
    mov     x11, x22
1:  ldr     x12, [x8, x10, lsl #3]
2:  cbz     x12, 3f
    str     x12, [x11], #8
    ldr     x12, [x12, #E_NEXT]
    b       2b
3:  add     x10, x10, #1
    cmp     x10, x9
    b.lo    1b

    mov     x0, x22
    mov     x1, x21
    mov     x2, #8
    adrp    x3, _kv_entry_cmp@PAGE
    add     x3, x3, _kv_entry_cmp@PAGEOFF
    bl      _qsort

    mov     x24, x23                      // cursor
    mov     w8, #'['
    strb    w8, [x24], #1
    mov     x25, #0
4:  cmp     x25, x21
    b.hs    6f
    cbz     x25, 5f
    mov     w8, #','
    strb    w8, [x24], #1
5:  mov     w8, #'"'
    strb    w8, [x24], #1
    ldr     x9, [x22, x25, lsl #3]
    ldr     x2, [x9, #E_KLEN]
    add     x1, x9, #E_KEY
    mov     x0, x24
    add     x26, x24, x2
    bl      _memcpy                       // keys need no JSON escaping
    mov     x24, x26
    mov     w8, #'"'
    strb    w8, [x24], #1
    add     x25, x25, #1
    b       4b
6:  mov     w8, #']'
    strb    w8, [x24], #1
    sub     x8, x24, x23
    str     x8, [x19]
    mov     x0, x20
    bl      _pthread_mutex_unlock
    mov     x0, x22
    bl      _free
    mov     x0, x23
    b       Llist_ret
Llist_oom_arr:
    mov     x0, x22
    bl      _free
Llist_oom:
    mov     x0, x20
    bl      _pthread_mutex_unlock
    mov     x0, #0
Llist_ret:
    ldp     x29, x30, [sp, #64]
    ldp     x20, x19, [sp, #48]
    ldp     x22, x21, [sp, #32]
    ldp     x24, x23, [sp, #16]
    ldp     x26, x25, [sp]
    add     sp, sp, #80
    ret
    .cfi_endproc

    .bss
    .p2align 4
_kv_store:
    .space  S_SIZE

.subsections_via_symbols
