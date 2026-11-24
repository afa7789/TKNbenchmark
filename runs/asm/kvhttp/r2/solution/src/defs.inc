// Shared constants and macros for kvhttp (AArch64, macOS / Mach-O).

// Load the address of a symbol into a register (PC-relative, PIE-safe).
.macro LOADADDR reg, sym
        adrp    \reg, \sym@PAGE
        add     \reg, \reg, \sym@PAGEOFF
.endm

// Response status indices into _status_tab (see http.s).
        .equ ST_200, 0
        .equ ST_201, 1
        .equ ST_204, 2
        .equ ST_400, 3
        .equ ST_404, 4
        .equ ST_405, 5
        .equ ST_413, 6
        .equ ST_431, 7
        .equ ST_500, 8

// Request method codes returned by _method_code.
        .equ M_OTHER,  0
        .equ M_GET,    1
        .equ M_PUT,    2
        .equ M_DELETE, 3

// libc / kernel constants (Darwin).
        .equ EINTR,        4
        .equ AF_INET,      2
        .equ SOCK_STREAM,  1
        .equ SOL_SOCKET,   0xffff
        .equ SO_REUSEADDR, 0x0004
        .equ SO_SNDTIMEO,  0x1005
        .equ SO_RCVTIMEO,  0x1006
        .equ IPPROTO_TCP,  6
        .equ TCP_NODELAY,  1
        .equ SHUT_WR,      1
        .equ SIGPIPE,      13
        .equ SIG_IGN,      1
        .equ PTHREAD_CREATE_DETACHED, 2

// Limits.
        .equ HDR_CAP,      65536            // max request head (line + headers)
        .equ MAX_BODY,     (64 << 20)       // reject bodies above 64 MiB with 413
        .equ IO_TIMEOUT_S, 30               // per-socket send/recv timeout
        .equ LISTEN_BACKLOG, 1024
