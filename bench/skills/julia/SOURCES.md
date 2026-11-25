# Sources

## Official (installed toolchain, Julia 1.13.4 via Homebrew)
- /opt/homebrew/Cellar/julia/1.13.4/NEWS.md: the 1.13 changes (takestring!, Iterators.nth/findeach, ispositive, fieldindex, @__FUNCTION__, sort(keys(d)), mergewith deprecation, @test_throws 3-arg form, JULIA_TEST_VERBOSE, --trace-eval, hash changes, Apple Silicon CPU_THREADS).
- /opt/homebrew/Cellar/julia/1.13.4/HISTORY.md: the 1.12 and 1.11 notes (struct/const redefinition and world age, FieldError, `public` and `public`+`export` error, @main and -m, --project=@temp/@script, default interactive thread, OncePerProcess/Task, Lockable, ScopedValue, waitall, logrange, Fix, insertdims, @atomic indexing, --trim).
- share/julia/stdlib/v1.13/Pkg/CHANGELOG.md: Pkg 1.13/1.12/1.11 changes (workspaces, apps, [sources], compat --current, Pkg.test no longer forcing check-bounds).
- share/julia/stdlib/v1.13/Pkg/docs/src/creating-packages.md: workspaces with test/Project.toml as the recommended test layout, plus extensions and weakdeps.
- share/julia/stdlib/v1.13/Pkg/docs/src/apps.md: the [apps] section, submodule and julia_flags, the ~/.julia/bin PATH note.
- share/julia/stdlib/v1.13/Test/src/Test.jl: the JULIA_TEST_VERBOSE and JULIA_TEST_FAILFAST environment variables.
- share/julia/base/hashing.jl: the default HASH_SEED; why custom `hash` must take the seed with no default.
- share/doc/julia/html/en/manual/{style-guide,performance-tips,workflow-tips}.html: baseline style and performance rules (const globals, concrete fields, function barriers, column-major order, @views).
- https://julialang.org/blog/2026/09/julia-1.13-highlights/: 1.13 highlights (hash seed warning, JuliaC package, trim improvements, Pkg zstd and registry-in-manifest, Pkg.test check-bounds change).
- https://docs.julialang.org/en/v1/NEWS: online copy of the release notes, cross-checked against the local file.
- https://raw.githubusercontent.com/JuliaLang/julia/HEAD/AGENTS.md: the Julia repo's own agent rules (check docstrings before use, use Revise, avoid needless module prefixes).

## Style and tooling
- https://github.com/JuliaDiff/BlueStyle: the most widely followed style guide (4 spaces, 92 columns, explicit `return`, `for x in xs`, `;` before keyword arguments, compat without caret).
- https://github.com/fredrikekre/Runic.jl: the config-free formatter; install via Pkg.Apps and the --check/--diff/--inplace flags (checked locally).
- https://github.com/JuliaLang/JuliaC.jl: juliac CLI flags, --trim=safe, --bundle, @main entry point (checked locally by building a 1.6 MB trimmed executable).
- https://github.com/julia-actions/julia-runtest: the standard GitHub Actions steps (setup-julia@v2, cache@v2, julia-buildpkg@v1, julia-runtest@v1).
- https://modernjuliaworkflows.org/writing/: environments, Revise, logging practices.
- https://modernjuliaworkflows.org/sharing/: PkgTemplates, Aqua.test_all, JET.test_package, Documenter, CompatHelper/TagBot/Registrator workflow.
- https://modernjuliaworkflows.org/optimizing/: BenchmarkTools `$` interpolation, Chairmarks, JET @report_opt, PrecompileTools, AllocCheck.

## Published agent guidance for Julia
- https://discourse.julialang.org/t/julia-agent-tools-agent-directives-ast-grep-rules-and-a-ctags-optlib-for-julia/142735: agent directives (type stability, concrete fields, measure @allocated inside functions not at top level, precompile hygiene).
- https://tessl.io/registry/skills/github/popey/claude-code-skills/julia-pro: a common skill consensus (change dependencies through Pkg, BlueStyle, JET + Aqua, avoid type piracy, extensions).
- https://skills.sh/seabbs/skills/julia-development: keep a warm session or use Revise to avoid TTFX, and check edits as you go.
- https://skills.sh/hanafsky/julia-skills/julia-vibe-coding: project layout and TTFX-avoidance workflow (looked at only for points of agreement).

## Local verification (scratch, deleted afterwards)
- Ran snippets on julia 1.13.4 for every API in SKILL.md. Corrections that came from this: `nth` is `Iterators.nth`, not exported. InteractiveUtils is not loaded in scripts. `@atomic v[i]` needs AtomicMemory. `compat --current` and `Pkg.compat` do not handle weakdeps. Trimmed `println` through `stdout` fails, so use `Core.stdout`. `--bundle` fails on Homebrew's symlinked libs. Also ran a full Pkg.generate, workspace test, extension, PrecompileTools, Aqua and JET package test, plus Pkg app install and `julia -m` exit code.
