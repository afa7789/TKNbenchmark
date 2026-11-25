---
name: c
description: "Version-correct, idiomatic C for the installed toolchain (Apple clang version 17.0.0 (clang-1700.0.13.5)): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing C code."
---

# C17 (ISO/IEC 9899:2018)

C17 is C11 with defect fixes, no new syntax (`__STDC_VERSION__ == 201710L`). It deprecates `ATOMIC_VAR_INIT` and `realloc(p, 0)`. Use `-std=c17`, not the default `gnu17`.

## C23 features that do not exist in C17
Under `-std=c17` each is an error or a `-Wc23-extensions` warning:
- `bool/true/false` need `<stdbool.h>`. `static_assert`, `alignas/alignof` and `noreturn` need `<assert.h>`, `<stdalign.h>` and `<stdnoreturn.h>`. `_Static_assert(e, "msg")` **requires** the message.
- No `nullptr` (use `NULL`), `auto` type inference, `constexpr`, `typeof` (`__typeof__` is a GNU extension), `[[attributes]]`, `= {}` (use `= {0}`), `0b` literals, `1'000` separators, `<stdckdint.h>`/`ckd_add`, `memset_explicit` or `#embed`.
- `int f();` declares a function with **unspecified** parameters, not zero. Write `int f(void);`.
- Variadic macros need at least one variadic argument. Don't use `__VA_OPT__`.
- Overflow checks: `__builtin_add_overflow(a, b, &r)` (`_sub_`/`_mul_`; GCC+Clang) returns true on overflow.

## Build flags
Dev:
```
-std=c17 -Wall -Wextra -Wpedantic -Wshadow -Wconversion -Wstrict-prototypes \
-Wmissing-prototypes -Wwrite-strings -Wformat=2 -Wimplicit-fallthrough \
-Werror=implicit -Werror=incompatible-pointer-types -Werror=int-conversion -g -O0
```
Sanitizers: `-O1 -g -fno-omit-frame-pointer -fsanitize=address,undefined`, plus the same `-fsanitize` at link time. Threads: separate `-fsanitize=thread` build. UBSan only prints and continues by default; to fail tests, use `UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1` or `-fno-sanitize-recover=undefined`.
Release: `-O2 -DNDEBUG -fstack-protector-strong -D_FORTIFY_SOURCE=3 -ftrivial-auto-var-init=zero`. Linux adds `-fPIE -pie -Wl,-z,relro,-z,now -fstack-clash-protection`.
`-Werror` only in dev/CI, not shipped build files. Static analysis: `clang --analyze file.c`.

### macOS / Apple clang (arm64) facts (verified)
- No `<threads.h>` and no `<uchar.h>`. Use `<pthread.h>` (+ `-pthread`) and `<stdatomic.h>`.
- Not supported: `-fsanitize=memory`, `-fsanitize=leak`, `ASAN_OPTIONS=detect_leaks=1`, `-fsanitize=fuzzer`. No Valgrind. Check leaks with `leaks --atExit -- ./prog` (exit status 1 = leaks found). Run it on a binary built without ASan.
- PIE is the default, so `-pie` is "unused". ld64 rejects `-Wl,-z,*` and `--as-needed`. Use `-Wl,-dead_strip`.
- `char` is signed on Apple arm64 and unsigned on Linux arm64. Use `unsigned char`/`uint8_t` for bytes and cast to `unsigned char` before `isalpha()` etc.
- `#define _POSIX_C_SOURCE 200809L` hides `strlcpy`/`arc4random`; also define `_DARWIN_C_SOURCE` if you need them. On glibc, `-std=c17` hides `strdup`, `getline` and `fileno` unless `_POSIX_C_SOURCE 200809L` is defined **before any include**.
- Universal binary: `-arch arm64 -arch x86_64` (`lipo -archs`). Dylib: `cc -dynamiclib -install_name @rpath/libx.dylib` (`otool -L`).

## Project layout and CMake (4.x installed; `cmake_minimum_required` < 3.5 is an error)
```
include/mylib/mylib.h  src/mylib.c  src/main.c  tests/test_mylib.c
```
```cmake
cmake_minimum_required(VERSION 3.21)   # C_STANDARD 17 needs 3.21
project(mylib VERSION 0.1.0 LANGUAGES C)
set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)  # else silently decays to older -std
set(CMAKE_C_EXTENSIONS OFF)        # -std=c17, not gnu17
add_library(mylib src/mylib.c)
target_include_directories(mylib PUBLIC include)
target_compile_options(mylib PRIVATE -Wall -Wextra -Wpedantic -Wconversion -Wshadow)
add_executable(app src/main.c)
target_link_libraries(app PRIVATE mylib)
include(CTest)
if(BUILD_TESTING)
  add_executable(test_mylib tests/test_mylib.c)
  target_link_libraries(test_mylib PRIVATE mylib)
  add_test(NAME mylib COMMAND test_mylib)
endif()
```
```
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Debug && cmake --build build && ctest --test-dir build --output-on-failure
cmake -S . -B build-rel -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF && cmake --build build-rel
```
Makefile (macOS ships GNU make **3.81**): `CPPFLAGS += -Iinclude -MMD -MP` plus `-include $(wildcard $(BUILD)/*.d)` tracks header deps; compile with `$(CC) $(CPPFLAGS) $(CFLAGS) -c $< -o $@`.
Tests need no framework: `#define CHECK(c) do{ if(!(c)){ fprintf(stderr,"%s:%d: %s\n",__FILE__,__LINE__,#c); fails++; } }while(0)`; return `EXIT_FAILURE` if any failed.

## Headers
Include guard `#ifndef MYLIB_MYLIB_H`, prefixed public symbols (`mylib_`), `extern "C"` under `#ifdef __cplusplus`. Everything else `static` (`-Wmissing-prototypes` catches misses). Prefer `static inline` over function-like macros.

## Idioms (verified with ASan+UBSan)
```c
/* Growable array: overflow-checked, realloc into a temporary */
if (v->len == v->cap) {
    size_t ncap = v->cap ? v->cap * 2 : 8;
    if (ncap > SIZE_MAX / sizeof *v->data) return ENOMEM;
    int *p = realloc(v->data, ncap * sizeof *p);
    if (!p) return ENOMEM;            /* old block still owned */
    v->data = p; v->cap = ncap;
}
/* Integer parsing: never atoi */
char *end; errno = 0;
long val = strtol(s, &end, 10);
if (end == s || *end != '\0') return EINVAL;
if (errno == ERANGE || val < INT_MIN || val > INT_MAX) return ERANGE;
/* qsort comparator without overflow (not a - b) */
static int cmp_int(const void *a, const void *b) {
    int x = *(const int *)a, y = *(const int *)b; return (x > y) - (x < y); }
/* snprintf truncation check */
int w = snprintf(buf, sizeof buf, "%s-%d", name, id);
if (w < 0 || (size_t)w >= sizeof buf) { /* truncated */ }
/* strip newline after fgets */
line[strcspn(line, "\n")] = '\0';
/* type punning: memcpy, not pointer casts (strict aliasing) */
uint32_t bits; memcpy(&bits, &f, sizeof bits);
```
- `T *p = malloc(n * sizeof *p);` after an overflow check, no cast; `calloc` checks overflow itself.
- Cleanup: single `goto out;` path; init resources to `NULL` first (`free(NULL)` is a no-op; guard `fclose`).
- Return `0`/`errno`-style codes; results via out-params. On short `fread`, check `ferror`.
- Sizes/indices are `size_t` (`%zu`); fixed-width printf via `PRId64`/`PRIu32` (`<inttypes.h>`).
- Zero-init: `T x = {0};`. Designated initializers and compound literals are fine.
- Flexible array member: `struct S { size_t n; char data[]; };` with `malloc(sizeof *s + n)`.
- `#define countof(a) (sizeof(a) / sizeof((a)[0]))`.
- Atomics: `atomic_int c = 0;` (no `ATOMIC_VAR_INIT`) and `atomic_fetch_add_explicit(&c, 1, memory_order_relaxed)`. Never use `volatile` for threads. `cnd_wait`/`pthread_cond_wait` can wake spuriously, so always wait in a `while (!pred)` loop.
- Never `realloc(p, 0)` (deprecated; behavior differs between implementations). Use `free(p)`.
- No `strcpy/strcat/sprintf/gets/strtok`; use `snprintf`, `memcpy` with known lengths, `strtok_r`.
- Signed overflow, shifting by ≥ width or a negative amount, and `INT_MIN / -1` are UB. Do the math in `unsigned` or check first.

## Compiler diagnostics → fix
| Message | Fix |
|---|---|
| `call to undeclared function 'x'` (implicit declaration) | Include the header; for POSIX/BSD functions define the feature macro before all includes |
| `a function declaration without a prototype is deprecated` | `f()` → `f(void)` |
| `no previous prototype for function 'f'` | Make it `static` or declare it in a header |
| `format specifies type 'int' but the argument has type 'size_t'` | `%zu` |
| `implicit conversion loses integer precision` / `-Wshorten-64-to-32` | Fix the type (`size_t`), or explicitly cast after a range check |
| `comparison of integers of different signs` | `size_t` index, or cast after `>= 0` check |
| `'char *' with ... 'const char[N]' discards qualifiers` | `const char *s = "lit";` |
| `type specifier missing, defaults to 'int'` (on `auto x =`) | C23 syntax; write the type |
| `too many arguments provided to function-like macro invocation` | Parenthesize a braced or comma-containing argument |
| `AddressSanitizer: detect_leaks is not supported on this platform` | Use `leaks --atExit -- ./prog` on macOS |
