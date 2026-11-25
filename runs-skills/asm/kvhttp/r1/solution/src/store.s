// store.s — the in-memory key/value table.
//
// Entries live in one array kept sorted by key (bytewise, a proper prefix
// sorts first), so lookups are binary searches and listing is a linear walk.
// One mutex serialises every operation. Values are copied out under the lock,
// so callers never hold pointers into the table.
//
// Entry layout (32 bytes): { key_ptr, key_len, val_ptr, val_len }

    .equ ENTRY_SHIFT, 5
    .equ ENTRY_SIZE,  32
    .equ E_KEY,  0
    .equ E_KLEN, 8
    .equ E_VAL,  16
    .equ E_VLEN, 24

    // Global table state, one block so a single adrp/add reaches all of it.
    .equ KV_LOCK,    0              // pthread_mutex_t (64 bytes)
    .equ KV_ENTRIES, 64
    .equ KV_COUNT,   72
    .equ KV_CAP,     80

    .equ INITIAL_CAP, 64

    .zerofill __DATA,__bss,_kv,96,4

.macro KV_BASE reg
    adrp    \reg, _kv@PAGE
    add     \reg, \reg, _kv@PAGEOFF
.endm

    .text

// void kv_init(void)
    .globl  _kv_init
    .p2align 2
_kv_init:
    .cfi_startproc
    stp     x29, x30, [sp, #-16]!
    mov     x29, sp
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    KV_BASE x0
    mov     x1, #0
    bl      _pthread_mutex_init
    ldp     x29, x30, [sp], #16
    ret
    .cfi_endproc

// kv_find(key x0, klen x1) -> x0 = index of match or insertion point,
//                             x1 = 1 if found else 0.
// Leaf; caller holds the lock. Clobbers x2-x13.
    .p2align 2
_kv_find:
    KV_BASE x8
    ldr     x9, [x8, #KV_ENTRIES]
    mov     x10, #0                         // lo
    ldr     x11, [x8, #KV_COUNT]            // hi
Lfind_loop:
    cmp     x10, x11
    b.hs    Lfind_miss
    add     x12, x10, x11
    lsr     x12, x12, #1                    // mid
    add     x13, x9, x12, lsl #ENTRY_SHIFT
    ldp     x2, x3, [x13, #E_KEY]           // entry key, entry len
    cmp     x3, x1
    csel    x4, x3, x1, lo                  // common prefix length
    mov     x5, #0
Lfind_cmp:
    cmp     x5, x4
    b.eq    Lfind_prefix
    ldrb    w6, [x2, x5]
    ldrb    w7, [x0, x5]
    add     x5, x5, #1
    cmp     w6, w7
    b.eq    Lfind_cmp
    b.lo    Lfind_right                     // entry < key
    mov     x11, x12                        // entry > key: hi = mid
    b       Lfind_loop
Lfind_prefix:
    cmp     x3, x1
    b.lo    Lfind_right
    b.hi    Lfind_left
    mov     x0, x12
    mov     x1, #1
    ret
Lfind_right:
    add     x10, x12, #1
    b       Lfind_loop
Lfind_left:
    mov     x11, x12
    b       Lfind_loop
Lfind_miss:
    mov     x0, x10
    mov     x1, #0
    ret

// int kv_put(key x0, klen x1, val x2, vlen x3) -> 201 new, 200 replaced, 500.
// Takes ownership of the malloc'd value buffer in every case.
    .globl  _kv_put
    .p2align 2
_kv_put:
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
    mov     x21, x2
    mov     x22, x3

    // Copy the key before taking the lock; dropped again on replace.
    mov     x0, x20
    bl      _malloc
    cbz     x0, Lput_oom
    mov     x23, x0
    mov     x1, x19
    mov     x2, x20
    bl      _memcpy

    KV_BASE x0
    bl      _pthread_mutex_lock
    mov     x0, x19
    mov     x1, x20
    bl      _kv_find
    mov     x24, x0
    cbz     x1, Lput_insert

    // Replace the value of an existing key.
    KV_BASE x8
    ldr     x9, [x8, #KV_ENTRIES]
    add     x9, x9, x24, lsl #ENTRY_SHIFT
    ldr     x19, [x9, #E_VAL]               // old value
    stp     x21, x22, [x9, #E_VAL]
    KV_BASE x0
    bl      _pthread_mutex_unlock
    mov     x0, x19
    bl      _free
    mov     x0, x23
    bl      _free
    mov     w0, #200
    b       Lput_ret

Lput_insert:
    KV_BASE x8
    ldr     x10, [x8, #KV_COUNT]
    ldr     x11, [x8, #KV_CAP]
    cmp     x10, x11
    b.lo    Lput_room
    lsl     x11, x11, #1
    mov     x12, #INITIAL_CAP
    cmp     x11, #0
    csel    x19, x12, x11, eq               // new capacity
    ldr     x0, [x8, #KV_ENTRIES]
    lsl     x1, x19, #ENTRY_SHIFT
    bl      _realloc
    cbz     x0, Lput_oom_locked
    KV_BASE x8
    str     x0, [x8, #KV_ENTRIES]
    str     x19, [x8, #KV_CAP]
Lput_room:
    KV_BASE x8
    ldr     x9, [x8, #KV_ENTRIES]
    ldr     x10, [x8, #KV_COUNT]
    add     x1, x9, x24, lsl #ENTRY_SHIFT   // shift [idx, count) up one slot
    add     x0, x1, #ENTRY_SIZE
    sub     x2, x10, x24
    lsl     x2, x2, #ENTRY_SHIFT
    bl      _memmove
    KV_BASE x8
    ldr     x9, [x8, #KV_ENTRIES]
    add     x9, x9, x24, lsl #ENTRY_SHIFT
    stp     x23, x20, [x9, #E_KEY]
    stp     x21, x22, [x9, #E_VAL]
    ldr     x10, [x8, #KV_COUNT]
    add     x10, x10, #1
    str     x10, [x8, #KV_COUNT]
    KV_BASE x0
    bl      _pthread_mutex_unlock
    mov     w0, #201
    b       Lput_ret

Lput_oom_locked:
    KV_BASE x0
    bl      _pthread_mutex_unlock
    mov     x0, x23
    bl      _free
Lput_oom:
    mov     x0, x21
    bl      _free
    mov     w0, #500
Lput_ret:
    ldp     x29, x30, [sp, #48]
    ldp     x20, x19, [sp, #32]
    ldp     x22, x21, [sp, #16]
    ldp     x24, x23, [sp], #64
    ret
    .cfi_endproc

// kv_get(key x0, klen x1) -> w0 = 200/404/500, x1 = malloc'd copy, x2 = len.
// The caller frees x1 (NULL unless 200).
    .globl  _kv_get
    .p2align 2
_kv_get:
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
    KV_BASE x0
    bl      _pthread_mutex_lock
    mov     x0, x19
    mov     x1, x20
    bl      _kv_find
    mov     w19, #404
    mov     x20, #0
    mov     x22, #0
    cbz     x1, Lget_unlock
    KV_BASE x8
    ldr     x9, [x8, #KV_ENTRIES]
    add     x9, x9, x0, lsl #ENTRY_SHIFT
    ldp     x21, x22, [x9, #E_VAL]
    cmp     x22, #1
    csinc   x0, x22, xzr, hs                // malloc(max(len, 1))
    bl      _malloc
    mov     w19, #500
    mov     x20, x0
    cbz     x0, Lget_empty
    mov     x1, x21
    mov     x2, x22
    bl      _memcpy
    mov     w19, #200
    b       Lget_unlock
Lget_empty:
    mov     x22, #0
Lget_unlock:
    KV_BASE x0
    bl      _pthread_mutex_unlock
    mov     w0, w19
    mov     x1, x20
    mov     x2, x22
    ldp     x29, x30, [sp, #32]
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #48
    ret
    .cfi_endproc

// int kv_delete(key x0, klen x1) -> 204 deleted, 404 absent.
    .globl  _kv_delete
    .p2align 2
_kv_delete:
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
    KV_BASE x0
    bl      _pthread_mutex_lock
    mov     x0, x19
    mov     x1, x20
    bl      _kv_find
    cbz     x1, Ldel_absent
    KV_BASE x8
    ldr     x9, [x8, #KV_ENTRIES]
    ldr     x10, [x8, #KV_COUNT]
    sub     x10, x10, #1
    str     x10, [x8, #KV_COUNT]
    add     x9, x9, x0, lsl #ENTRY_SHIFT
    ldr     x19, [x9, #E_KEY]
    ldr     x20, [x9, #E_VAL]
    sub     x2, x10, x0                     // entries after the victim
    lsl     x2, x2, #ENTRY_SHIFT
    mov     x0, x9
    add     x1, x9, #ENTRY_SIZE
    bl      _memmove
    KV_BASE x0
    bl      _pthread_mutex_unlock
    mov     x0, x19
    bl      _free
    mov     x0, x20
    bl      _free
    mov     w0, #204
    b       Ldel_ret
Ldel_absent:
    KV_BASE x0
    bl      _pthread_mutex_unlock
    mov     w0, #404
Ldel_ret:
    ldp     x29, x30, [sp, #16]
    ldp     x20, x19, [sp], #32
    ret
    .cfi_endproc

// kv_list_json() -> w0 = 200/500, x1 = malloc'd JSON array of keys, x2 = len.
// Keys are restricted to [A-Za-z0-9_-], so no escaping is needed.
    .globl  _kv_list_json
    .p2align 2
_kv_list_json:
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
    KV_BASE x0
    bl      _pthread_mutex_lock

    // Size: "[" + "]" + per key (len + 2 quotes + 1 comma) - 1 comma.
    KV_BASE x8
    ldr     x9, [x8, #KV_ENTRIES]
    ldr     x10, [x8, #KV_COUNT]
    mov     x20, #2
    mov     x11, x10
    add     x12, x9, #E_KLEN
Llist_size:
    cbz     x11, Llist_sized
    ldr     x13, [x12], #ENTRY_SIZE
    add     x20, x20, x13
    add     x20, x20, #3
    sub     x11, x11, #1
    b       Llist_size
Llist_sized:
    cmp     x10, #0
    cset    x11, ne
    sub     x20, x20, x11                   // no trailing comma
    mov     x0, x20
    bl      _malloc
    mov     x19, x0
    mov     w21, #500
    cbz     x0, Llist_fail

    KV_BASE x8
    ldr     x9, [x8, #KV_ENTRIES]
    ldr     x10, [x8, #KV_COUNT]
    mov     x11, x19                        // write cursor
    mov     w12, #'['
    strb    w12, [x11], #1
    mov     x22, #0                         // index
Llist_key:
    cmp     x22, x10
    b.hs    Llist_close
    cbz     x22, Llist_quote
    mov     w12, #','
    strb    w12, [x11], #1
Llist_quote:
    mov     w12, #'"'
    strb    w12, [x11], #1
    ldp     x13, x14, [x9, #E_KEY]
Llist_copy:
    ldrb    w12, [x13], #1
    strb    w12, [x11], #1
    subs    x14, x14, #1
    b.ne    Llist_copy
    mov     w12, #'"'
    strb    w12, [x11], #1
    add     x9, x9, #ENTRY_SIZE
    add     x22, x22, #1
    b       Llist_key
Llist_close:
    mov     w12, #']'
    strb    w12, [x11]
    mov     w21, #200
    b       Llist_unlock
Llist_fail:
    mov     x20, #0
Llist_unlock:
    KV_BASE x0
    bl      _pthread_mutex_unlock
    mov     w0, w21
    mov     x1, x19
    mov     x2, x20
    ldp     x29, x30, [sp, #32]
    ldp     x20, x19, [sp, #16]
    ldp     x22, x21, [sp], #48
    ret
    .cfi_endproc

.subsections_via_symbols
