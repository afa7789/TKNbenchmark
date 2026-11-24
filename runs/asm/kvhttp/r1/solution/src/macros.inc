// macros.inc — shared constants and helper macros for kvhttp (AArch64, Mach-O)

// Load the address of a symbol (PC-relative, position independent).
.macro LOADADDR reg, sym
        adrp    \reg, \sym@PAGE
        add     \reg, \reg, \sym@PAGEOFF
.endm

// --- libc / Darwin constants -------------------------------------------------
        .equ    AF_INET,        2
        .equ    SOCK_STREAM,    1
        .equ    SOL_SOCKET,     0xffff
        .equ    SO_REUSEADDR,   0x0004
        .equ    SO_SNDTIMEO,    0x1005
        .equ    SO_RCVTIMEO,    0x1006
        .equ    SO_NOSIGPIPE,   0x1022
        .equ    IPPROTO_TCP,    6
        .equ    TCP_NODELAY,    1
        .equ    SHUT_WR,        1
        .equ    SIGPIPE,        13
        .equ    SIG_IGN,        1

        .equ    EINTR,          4
        .equ    ECONNABORTED,   53

// --- application constants ---------------------------------------------------
        .equ    LISTEN_BACKLOG, 1024
        .equ    IO_TIMEOUT_SEC, 10          // per-connection socket read/write timeout
        .equ    HDR_CAP,        16384       // maximum size of request line + headers
        .equ    MAX_VALUE,      1048576     // 1 MiB value limit
        .equ    DRAIN_LIMIT,    4194304     // bytes we discard before giving up on a client

// Value blob: one malloc'd block, shared between store and in-flight readers.
//   [0]  refcount (atomic)
//   [8]  length
//   [16] bytes...
        .equ    BLOB_REFS,      0
        .equ    BLOB_LEN,       8
        .equ    BLOB_DATA,      16

// Store entry (keys are at most 64 bytes, stored inline).
        .equ    ENT_KLEN,       0
        .equ    ENT_BLOB,       8
        .equ    ENT_KEY,        16
        .equ    ENT_SIZE,       80
        .equ    KEY_MAX,        64
