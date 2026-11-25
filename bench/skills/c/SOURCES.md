# Sources

## Standard and release notes
- https://cppreference.net/c/17.html — C17 = C11 + defect fixes; `__STDC_VERSION__` 201710L; deprecates `ATOMIC_VAR_INIT` and `realloc` with size zero.
- https://en.wikipedia.org/wiki/C17_(C_standard_revision) — C17/C18 naming; no new language features.
- https://www.open-std.org/jtc1/sc22/wg14/www/docs/n2244.htm — WG14 C11 defect summary: DR 400 (realloc zero), DR 470/480 (spurious mtx_trylock failure and cnd_wait wake-ups), DR 485 (ATOMIC_VAR_INIT), DR 412 (#elif).
- https://open-std.org/JTC1/SC22/WG14/issues/c11c17/log.html — WG14 issue log for defects fixed in C17.

## Style guides and coding standards
- https://www.kernel.org/doc/html/latest/process/coding-style.html — Linux kernel style: centralized `goto` cleanup with descriptive labels, `do { } while (0)` macros, `static inline` over macros.
- https://wiki.sei.cmu.edu/confluence/label/c/rule-list — SEI CERT C rules: error checking, errno handling, banned string functions, integer overflow and UB.
- https://cmu-sei.github.io/secure-coding-standards/sei-cert-c-coding-standard/rules — browsable CERT C rule list (ERR30-C errno, MEM rules).
- https://nullprogram.com/blog/2023/10/08 — Chris Wellons' C style: `countof` macro, sanitizer-driven asserts, signed sizes, length-carrying strings, `{0}` init.

## Agent rules published by C developers
- https://cdn.jsdelivr.net/npm/@deftai/directive-content@0.126.2/languages/c.md — deft C directive: C17, extensions off, ASan/UBSan in debug, goto cleanup, no malloc cast, realloc via temp, `_Static_assert`, no `volatile` for sync.
- https://eliteai.tools/agent-skills/c — C agent skill: `-Wall -Wextra -Werror -pedantic`, sanitizers, banned `gets/strcpy/sprintf`, check every allocation.
- https://clawhub.ai/iliaal/compound-eng-c-systems — C systems skill: follow repo conventions, `-Wconversion -Wshadow`, ASan+UBSan clean, bound loops over external input.
- https://dev.to/olivia_craft/claudemd-for-modern-c-12-rules-that-stop-ai-from-writing-1998-style-c-3hf2 — listed in search results as a CLAUDE.md rule set for C; used only to confirm that agents commonly drift to outdated idioms.

## Tooling, build and hardening
- https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++ — OpenSSF flags: `-Wformat=2 -Wconversion -Wimplicit-fallthrough`, `-D_FORTIFY_SOURCE=3`, `-fstack-protector-strong`, `-ftrivial-auto-var-init=zero`, `-Werror=implicit/incompatible-pointer-types/int-conversion`, GNU-ld-only `-z` flags, `-Werror` only in dev.
- https://blog.quarkslab.com/clang-hardening-cheat-sheet-ten-years-later.html — Clang hardening cheat sheet confirming the OpenSSF baseline.
- https://clang.llvm.org/docs/AddressSanitizer.html — ASan flags (`-O1 -g -fno-omit-frame-pointer`), link with clang, ASAN/UBSAN_OPTIONS usage.
- https://clang.llvm.org/docs/LeakSanitizer.html — LSan platform notes.
- https://discourse.llvm.org/t/does-leaksanitizer-not-work-on-macos-13-apple-silicon/73148 — LSan is unreliable on Apple Silicon.
- https://lists.llvm.org/pipermail/llvm-commits/Week-of-Mon-20250317/1589285.html — LLVM disables leak detection on non-Intel Darwin.
- https://forums.swift.org/t/leaksanitizer-on-macos/84545 — use the macOS `leaks` tool instead of LSan.
- https://cmake.org/cmake/help/latest/prop_tgt/C_STANDARD.html — `C_STANDARD 17` needs CMake 3.21; without `C_STANDARD_REQUIRED` the standard silently decays to an older one.
- https://www.labri.fr/perso/fleury/posts/programming/using-cmake-googletests-and-gcovr-in-a-c-project.html — common `src/` + `tests/` layout with CTest.
- https://cyril-grelier.github.io/vscode/c/2025/07/15/vscode_c_project.html — 2025 C project setup with clang tooling and sanitizers.

## Local verification (Apple clang 17.0.0, macOS SDK 26.2, CMake 4.4.3, GNU make 3.81)
All checks ran in a scratch directory that has since been deleted:
- Default `__STDC_VERSION__` is 201710L, in gnu17 mode; `-std=c17` defines `__STRICT_ANSI__`.
- `<threads.h>` and `<uchar.h>` are missing; `<stdatomic.h>`, `<stdalign.h>` and `<stdnoreturn.h>` are present.
- Under `-std=c17`, each C23 construct produced an error or a `-Wc23-extensions` warning. The exact diagnostic text in SKILL.md was captured from these runs.
- Rejected flags: `-fsanitize=memory`, `-fsanitize=leak` and `-fsanitize=fuzzer`. `detect_leaks` is unsupported. `-pie` is unused, and ld64 rejects `-z` and `--as-needed`. The other hardening and warning flags were accepted.
- ASan, UBSan and TSan caught the seeded bugs. `leaks --atExit` reported the leak and exited with status 1.
- `_POSIX_C_SOURCE` hides `strlcpy` and `arc4random`. `char` is signed on arm64 Darwin.
- The CMake project (Ninja, CTest, Debug+sanitizers, Release) and the Makefile with `-MMD -MP` both built and passed tests. CMake < 3.5 is rejected.
- The idiom snippets (vector growth, strtol parsing, comparator, snprintf truncation, memcpy punning, goto cleanup) ran clean under ASan+UBSan and `clang --analyze`.
