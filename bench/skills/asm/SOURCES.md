# Sources

- https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms — Apple's ABI rules: x18 reserved, x29 frame records, red zone, variadic args on the stack, caller extends sub-32-bit args, `char` signed, `long double` = double, DIT and `timingsafe_*` APIs.
- https://developer.apple.com/documentation/xcode/application-binary-interfaces — index of Apple's platform ABI documents (where the arm64 page lives).
- https://developer.apple.com/documentation/xcode-release-notes/xcode-16_3-release-notes — the toolchain release that ships Apple clang 17. Clang now defines `TARGET_OS_*` macros from the triple; no assembler or linker breaking changes are listed.
- https://developer.apple.com/forums/thread/781538 — Apple DTS: `-ld_classic` (ld64) is deprecated with no removal date, and ld_prime is the linker to target.
- https://developer.apple.com/forums/thread/777412 — confirms Xcode 16.3 ships Clang 17.0.0 and that assembly-file processing performance changed across versions.
- https://github.com/ARM-software/abi-aa/blob/main/aapcs64/aapcs64.rst — AAPCS64: callee-saved x19–x29 and the low 64 bits of v8–v15, x16/x17 clobbered by veneers, x8 indirect result, SP mod 16 = 0.
- https://github.com/below/HelloSilicon — the most-followed macOS port of a Linux ARM64 book. Source of the Darwin-vs-Linux list: svc 0x80/x16, carry-flag errors, `@PAGE`/`@PAGEOFF`, no `ldr =`, the ld `-lSystem -syslibroot -e` command line, varargs on the stack, the `add …, w0, sxtb` and `lsl` syntax rules, L-prefixed labels. Its lowercase-directive claim and its `sys/syscalls.h` header name are outdated or wrong (verified: `.QUAD` assembles, the header is `sys/syscall.h`).
- https://ariadne.space/2023/04/12/writing-portable-arm-assembly.html — portable ARM64 asm across ELF and Mach-O: underscore prefix, no `.type` on Mach-O, Apple NEON shorthand (`eor.16b`) versus the standard form, x18.
- https://skills.sh/mohitmishra786/low-level-dev-skills/assembly-arm (and raw SKILL.md on GitHub) — a published agent skill for ARM asm. Agreed points: 16 KB pages on Apple Silicon, no SVE on M1–M3, SP alignment at calls, callee-saved v8–v15 low halves, `w` writes zero-extend. It contradicts itself on the red zone, which was resolved by Apple's doc.
- https://github.com/oddur/asm — a lesson-per-directory macOS ARM64 course built with `make run` and Xcode CLT. Informed the project layout.
- https://github.com/atcold/asm-apple-aarch64-playground — workflow of `clang -S` to learn idioms and `clang -o x x.s` to build, plus `-arch` selection.
- https://developer.apple.com/forums/thread/668654 — HFA/alignment surprise caused by Apple ABI divergence (motivated checking the ABI against compiler output).

All version-specific claims in SKILL.md were checked against the installed toolchain (Apple clang 17.0.0 clang-1700.0.13.5, ld-1167.5, MacOSX26.2 SDK, macOS 15.7, M4 Pro) by assembling, linking and running snippets. Those checks found the `;`-is-a-comment pitfall, `.s` being preprocessed by Apple clang, the silent misaligned `@PAGEOFF` truncation, and the exact linker error texts.
