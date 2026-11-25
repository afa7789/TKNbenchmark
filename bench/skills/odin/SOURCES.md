# Sources

All version-specific claims in SKILL.md were rechecked against the installed toolchain (`odin version` → `dev-2026-11:9a6991685`, sources under `/opt/homebrew/Cellar/odin/2026-11a/libexec/{base,core}`). Each claim was checked by grepping the stdlib or by compiling and running snippets in a scratch directory, which has since been deleted.

## Official docs and release notes
- https://github.com/odin-lang/Odin/releases: dev-2026-05 through dev-2026-11a notes. Used for: fmt space padding (2026-11); the compress/deflate overhaul and `Image.pixels` → `[dynamic]byte`; `mem.PAGE_SIZE` rename; `make_aligned` as a builtin; `**` expand_values; multi-line `"""` strings; the `os.Error == 0` hack removal; atomic analysis warnings.
- https://newreleases.io/project/github/odin-lang/Odin/release/dev-2026-01: release notes for 2026-01 (`core:container/xar`, json custom marshalling, no labelled breaking changes).
- https://newreleases.io/project/github/odin-lang/Odin/release/dev-2026-02: `using` statement opt-in (`#+feature using-stmt`), `#must_tail`, `-lto:thin`, `vendor:libc` → `libc-shim`, `loc := #caller_location` on strings allocators.
- https://newreleases.io/project/github/odin-lang/Odin/release/dev-2026-03: `core:os/os2` → `core:os` (breaking), `for init; x in y` loops, `process_close` removed / `process_terminate` added, `-tests:` runner option.
- https://newreleases.io/project/github/odin-lang/Odin/release/dev-2026-04: fixed-capacity `[dynamic; N]T`, Tilde backend removal.
- https://odin-lang.org/news/moving-towards-a-new-core-os: the old→new os migration (`os.Handle` → `^os.File`, `Errno` → `Error` union, explicit allocator on `read_entire_file`, removed procs).
- https://odin-lang.org/news/newsletter-2026-q1/: Q1 2026 changes (`core:os/old` timeline, `using` opt-in, `#all_or_none`, `#simple`, `core:nbio`, `handle_map`, chacha8rand default RNG).
- https://odin-lang.org/docs/testing/: `@(test)`, `testing.expect*`, `ODIN_TEST_*` defines, per-test memory tracking.
- https://odin-lang.org/docs/faq/: make/new vs delete/free, no `++`/methods/closures/exceptions, exhaustive switch, package rules. Its `strconv.atoi/itoa` advice is outdated: both are deprecated in this version.
- https://odin-lang.org/docs/overview: language reference for syntax and builtins.

## Style guide
- https://github.com/odin-lang/examples/wiki/Naming-and-style-convention: Karl Zylinski's guide, linked from the official examples repo. Provides the Ada_Case/snake_case/SCREAMING_SNAKE naming, tabs, and the `-vet -strict-style -vet-tabs -disallow-do -warnings-as-errors` gate.
- https://github.com/odin-lang/Odin/wiki/Naming-Convention: the same casing rules in the official wiki.
- https://forum.odin-lang.org/t/checking-i-get-the-correct-official-style-guide/1395: confirms the Zylinski guide is treated as the "official" one.

## Agent rules / community practice
- https://github.com/rjallais/ubrew/blob/main/AGENTS.md: gotchas. Allocator mismatch on `delete`; `strings.to_string` being a builder view; `make([dynamic]T, n)` setting len; `read_directory_by_path` + `file_info_slice_delete`; literals in for headers. The last one was verified: such literals need parentheses.
- https://github.com/boxxxie/odin-xitdb/blob/main/AGENTS.md: check/test command matrix, `-define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true`, `-sanitize:address` in tests, `free_all(context.temp_allocator)`.
- https://github.com/jackharrhy/arctic-char/blob/main/AGENTS.md: scoping temp allocations with `runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD()`, preallocating instead of allocating per frame.
- https://github.com/nic-vdwalt/ingot/blob/main/AGENTS.md: pinning Odin versions, `-collection:` for consumers, `-vet -strict-style -vet-shadowing` lint gate, `odinfmt -w`, `ODIN_TEST_THREADS=1`.
- https://skills.lc/TrevorS/gba-odin/trevors-gba-odin-claude-skills-odin-dev-skill-md: a published Odin agent skill. Taken from it: project layout (`src/main.odin` plus sub-packages, `build/` output), `defer` after acquire, `#partial switch`, ols/odinfmt setup.
- https://skills.lc/ln167/odin_master/ln167-odin-master-claude-skills-odin-skill-md: another Odin skill. Its main point is that agents misexplain `context`/allocator swapping.
- https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template: a widely used project template (build scripts, debug/release builds, `build/` dir layout).
