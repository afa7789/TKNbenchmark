# Sources

- https://github.com/isocpp/CppCoreGuidelines — the baseline most C++ rule sets follow: RAII, Rule of Zero, value semantics, named locks, concepts.
- https://google.github.io/styleguide/cppguide.html — Google style targets C++20 (no C++23); self-contained headers, include order, `unique_ptr` ownership, `explicit`/`override`, return values over out-params.
- https://libcxx.llvm.org/Status/Cxx20.html — libc++ C++20 status: tz/chrono partial, osyncstream experimental, jthread un-gated in LLVM 20, format/ranges/source_location complete.
- https://libcxx.llvm.org/Hardening.html — `_LIBCPP_HARDENING_MODE` names and what each mode checks; FAST recommended for production, DEBUG for tests.
- https://libcxx.llvm.org/ReleaseNotes/20.html — jthread/stop_token no longer behind `-fexperimental-library` in libc++ 20.
- https://www.llvm.org/releases/17.0.1/projects/libcxx/docs/ReleaseNotes/17.html — `std::format` declared stable; chrono time zones still missing.
- https://libcxx.llvm.org/Status/Format.html — std::format paper status in libc++.
- https://en.cppreference.com/w/cpp/compiler_support/20 — Apple Clang column: modules partial, jthread/execution policies/osyncstream not listed as supported.
- https://google.github.io/googletest/quickstart-cmake.html — FetchContent + `GTest::gtest_main` + `gtest_discover_tests` + ctest workflow.
- https://github.com/cpp-best-practices/cmake_template — the commonly used project template: warnings-as-errors, ASan/UBSan, clang-tidy, Catch2, CMakePresets, include/src/test layout.
- https://lessup.github.io/cpp-high-performance-guide/examples/01-cmake-modern — target-based CMake, `target_compile_features`, presets, FetchContent patterns.
- https://raw.githubusercontent.com/affaan-m/ECC/main/.kiro/skills/cpp-coding-standards/SKILL.md — published agent skill based on the Core Guidelines; checklist (no naked new, `explicit`, `enum class`, `'\n'`, constrained templates).
- https://raw.githubusercontent.com/mindrally/skills/HEAD/cpp/SKILL.md — published agent skill: smart pointers, sanitizers in CI, CMake, warnings as errors.
- https://dev.to/olivia_craft/claudemd-for-c-13-rules-that-make-ai-write-safe-modern-idiomatic-c-3dna — CLAUDE.md rules: span/string_view over pointer+size, jthread, strict warnings + sanitizers, no `using namespace` in headers.
- https://cursor.directory/rules/cpp — Cursor rules for C++; points to the ISO Core Guidelines and prefers STL algorithms.
- https://github.com/google/googletest and https://github.com/catchorg/Catch2 (tags via `git ls-remote`) — current releases (GoogleTest v1.17.0 used in the verified FetchContent build, v1.18.0 also out; Catch2 v3.16.1).
- Local toolchain (Apple clang 17.0.0, MacOSX26.2.sdk libc++ headers `__config`, `__config_site`, `__configuration/availability.h`) — verified libc++ 20.1, hardening default NONE, `_LIBCPP_HAS_TIME_ZONE_DATABASE 0`, libdispatch PSTL backend, and the availability gates (float from_chars needs macOS 26, to_chars/format need 13.3, sync primitives need 11.0). All examples and commands in SKILL.md were compiled and run on it (CMake 4.4.3, Ninja).
