---
name: asm
description: "Version-correct, idiomatic Assembly for the installed toolchain (Apple clang version 17.0.0 (clang-1700.0.13.5)): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Assembly code."
---

# AArch64 assembly on macOS (Apple clang 17, ld-prime, Mach-O)

Target `arm64-apple-macosx`, default CPU `apple-m1` (v8.5: NEON, LSE, CRC, dotprod, SHA3). The assembler is LLVM's integrated one, **not GNU as**, so Linux/ELF examples fail here.

## Build commands (verified)
```sh
clang -g -c src/foo.S -o build/foo.o                   # assemble (.S = preprocessed)
clang -g build/foo.o tests/t.c -o build/t              # link with libc via clang, never bare ld
clang -mmacosx-version-min=13.0 ...                    # or -target arm64-apple-macos13 / MACOSX_DEPLOYMENT_TARGET
libtool -static -o build/libfoo.a build/*.o            # static lib (ar rcs also works)
clang -dynamiclib -install_name @rpath/libfoo.dylib build/*.o -o build/libfoo.dylib
clang -mcpu=apple-m4 ...                               # or `.arch_extension sme`, needed for SME/bf16/i8mm
```
- Without libc: `clang -nostartfiles -e _start foo.s -o foo`. With bare ld: `ld foo.o -o foo -lSystem -syslibroot "$(xcrun --show-sdk-path)" -e _start -arch arm64`. libSystem is mandatory. `-static` fails (`library 'crt0.o' not found`), `-no_pie` is ignored, and `-ld_classic` is deprecated.
- Apple clang also runs the preprocessor on `.s`, but `as` and Linux clang do not. Name any file that uses `#include`/`#define` `.S`.
- Universal: guard the source with `#if defined(__arm64__)` / `#elif defined(__x86_64__)` and build with `clang -arch arm64 -arch x86_64`.
- Inspect: `otool -tvV x.o`, `objdump -d x.o`, `nm -m x.o`, `otool -L bin`. For the idiomatic form of a construct, run `clang -O2 -S -o - f.c`.
- Debug: `lldb ./t` → `b sum_u8` (no underscore), `run`, `si`, `register read x0 v1`, `dis -p -c 8`, `bt`.

## Layout
```
src/*.S      one public function (or small family) per file
include/*.h  C prototypes: the contract
tests/*.c    compare against a C reference at sizes 0,1,15,16,17,big
Makefile     build/%.o: src/%.S; tests built with -fsanitize=address,undefined
```

## File skeleton
```asm
#define FUNC(n) .globl _##n %% .p2align 2 %% _##n:
    .text
FUNC(add3)                                  // int64_t add3(int64_t,int64_t,int64_t)
    add  x0, x0, x1
    add  x0, x0, x2
    ret
    .section __TEXT,__cstring,cstring_literals
Lmsg: .asciz "hi\n"
    .const                                  // read-only data (__TEXT,__const)
    .p2align 4
Ltab: .quad 1, 2
    .data
    .p2align 3
_counter: .quad 0
    .zerofill __DATA,__bss,_buf,4096,4      // or `.bss` then label + .space
.subsections_via_symbols
```
- **`;` starts a comment on Darwin.** `a; b` silently drops `b`, so a macro using `;` exports nothing (`Undefined symbols`). Use `%%` as the statement separator.
- C symbols carry a leading `_`. A hidden global is `.private_extern _f`.
- Labels inside functions must be `L`-prefixed (`Lloop:`) or numeric (`1:` / `b.ne 1b`). With `.subsections_via_symbols`, a plain label starts an atom the linker may split off or dead-strip.
- `.align N` means 2^N here (`.align 4` = 16 bytes). Prefer `.p2align`/`.balign`.
- ELF-only syntax is rejected: `.type`, `.size`, `.section .rodata`, and `:lo12:` (`ADR/ADRP relocations must be GOT relative`). `.macro` (`\arg`), `.irp`, `.rept`, `.equ` and `.if` work.

## Addressing (the #1 source of errors)
```asm
adrp x0, Lmsg@PAGE            // local/own symbol: PC-relative
add  x0, x0, Lmsg@PAGEOFF
adrp x8, _counter@PAGE
ldr  x9, [x8, _counter@PAGEOFF]
adrp x8, ___stdoutp@GOTPAGE   // data in ANOTHER image (libSystem/dylib): via GOT
ldr  x8, [x8, ___stdoutp@GOTPAGEOFF]
ldr  x1, [x8]                 // FILE *stdout
adrp x0, _tv@TLVPPAGE         // _Thread_local: call the TLV thunk
ldr  x0, [x0, _tv@TLVPPAGEOFF]
ldr  x8, [x0]
blr  x8                       // x0 = &tv (non-leaf: needs a frame)
```
- `ldr x0, =sym` and `.quad sym` in `__text` fail: `ld: Found illegal text-relocations`. Keep pointer tables in `__DATA`/`__DATA_CONST`.
- Using `@PAGE` on an external data symbol fails: `fixup error ... does not have address`. Use `@GOTPAGE`/`@GOTPAGEOFF`.
- `adr` to another section fails (`unknown AArch64 fixup kind!`). Use adrp+add.
- **Silent bug:** the `@PAGEOFF` in `ldr xN, [xM, sym@PAGEOFF]` is scaled by the access size. If `sym` is not aligned to that size, ld truncates the offset with no warning and you load the wrong bytes. Always `.p2align` data to its access width.
- Wide constants: `mov x0, #0x12345678` fails (`expected compatible register or logical immediate`). Use `movz x0,#0x5678` + `movk x0,#0x1234,lsl #16`, or load from `__const`.

## Apple ABI (differs from Linux/AAPCS64)
- **x18 is reserved.** Never touch it; the assembler gives no warning.
- x29 must always point to a valid frame record. Non-leaf functions build one; leaf functions may skip it.
- **Variadic arguments always go on the stack**, each in its own 8-byte slot (doubles too). The fixed arguments still go in registers. `printf(fmt, 42)`: fmt in x0, `42` at `[sp]`. Putting it in x1 prints garbage.
- **The caller sign- or zero-extends arguments narrower than 32 bits** (`sxtb w0, w0` before `bl`). The callee may assume this. Callers likewise assume `char`/`short`/`bool` return values come back extended to 32 bits, so the callee extends them before `ret`.
- `char` is signed and `long double` == `double`. `__int128` may start in an odd register (x1:x2). Small stack arguments are packed at natural alignment.
- Callee-saved: x19–x28, x29, x30, sp, and the **low 64 bits** of v8–v15 (`stp d8, d9, ...`). x16/x17 may be clobbered by stubs at any `bl`. x8 holds the pointer for indirect results larger than 16 bytes.
- SP must be 16-aligned at every access and call. A misaligned `str xzr, [sp]` raises SIGBUS (exit 138).
- Only leaf functions may use the 128-byte red zone below sp.
- Pages are 16 KB. Use `sysconf(_SC_PAGESIZE)` and never hardcode 4096.

## Frames: canonical non-leaf prologue (what clang emits)
```asm
FUNC(f)
    .cfi_startproc
    sub  sp, sp, #48
    stp  x20, x19, [sp, #16]
    stp  x29, x30, [sp, #32]     // frame record ABOVE the outgoing-arg area
    add  x29, sp, #32
    .cfi_def_cfa w29, 16
    .cfi_offset w30, -8
    .cfi_offset w29, -16
    .cfi_offset w19, -24
    .cfi_offset w20, -32
    str  x9, [sp]                // outgoing stack/vararg slot at [sp]
    bl   _printf
    ldp  x29, x30, [sp, #32]
    ldp  x20, x19, [sp, #16]
    add  sp, sp, #48
    ret
    .cfi_endproc
```
Do not `stp x29, x30, [sp, #-16]!` and then write varargs to `[sp]`: that overwrites the saved fp/lr and crashes on return. Add CFI so C++ exceptions and profilers can unwind. arm64e also needs `pacibsp`/`retab`.

## Syscalls (prefer libc; numbers are private and may change)
`mov x16, #SYS_write` (from `<sys/syscall.h>`, in `.S`), arguments in x0–x5, `svc #0x80`. On error the **carry flag is set and x0 holds a positive errno**, so test `b.cs Lerr`. Linux's x8 / `svc #0` / negative return do not apply.

## Syntax the LLVM assembler rejects
| Wrong | Right |
|---|---|
| `mov x1, x2, lsl #1` | `lsl x1, x2, #1` |
| `add x2, x1, x0, sxtb` | `add x2, x1, w0, sxtb` (32-bit source for b/h/w extends) |
| `mov v3.4h[0], w0` | `mov v3.h[0], w0` |
| SVE `z0.d` | M1–M4 have no SVE (`requires: sve or sme`). Use NEON |

`otool`, `objdump` and `clang -S` print Apple NEON shorthand (`movi.2d v0, #0`). Write the portable form instead: `movi v0.2d, #0`.

## Fast idioms
- In loops use post-indexed `ldr q1, [x0], #16`, `ldp q0, q1` for 32-byte steps, `subs`+`b.ne` to count down, and `cbz`/`tbz` for zero and bit tests.
- Writing `wN` zeroes the upper half of `xN` (a free zero-extension), e.g. `ldrb w3, [x0], #1`.
- Prefer branchless `csel`, `csinc`, `cset` and `ccmp`. Widen with `uaddlp`/`uadalp` and reduce with `addv`. The M1 baseline has `udot`, `eor3`, `crc32cx` and LSE `ldadd`/`cas*`. bf16 and i8mm need `-mcpu=apple-m2`; SME needs apple-m4.
- Handle the `n % 16` tail with a scalar loop or an overlapping final vector load.
- Constant-time crypto: enable DIT (`msr dit, #1`) or call `timingsafe_enable_if_supported()` (macOS 15.2+).
