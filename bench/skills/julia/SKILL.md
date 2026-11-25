---
name: julia
description: "Version-correct, idiomatic Julia for the installed toolchain (julia version 1.13.4): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Julia code."
---

# Julia 1.13 (checked against 1.13.4)

## Projects and commands
```sh
julia --project=. script.jl          # also: --project=@temp, --project=@script, -t auto, -t 4,0
julia -e 'using Pkg; Pkg.generate("MyPkg")'
julia --project -e 'using Pkg; Pkg.add("JSON"); Pkg.instantiate()'
julia --project -e 'using Pkg; Pkg.test()'   # JULIA_TEST_VERBOSE=true, JULIA_TEST_FAILFAST=true
julia --project -m MyPkg arg1        # runs MyPkg's (@main); its return value becomes the exit code
julia --trace-eval script.jl         # 1.13: print each top-level eval (find hangs)
```
- Change dependencies only through Pkg, and commit `[compat]` for every dependency plus `julia`. `pkg"compat --current"` fills in missing entries for `[deps]` but **skips `[weakdeps]`**. `Pkg.compat("WeakDep", ...)` errors, so add those compat lines to Project.toml by hand. `Aqua.test_all` flags any that are missing.
- Since 1.13, `Pkg.test` no longer forces bounds checks: `Pkg.test(; julia_args=["--check-bounds=yes"])`.
- Scripts do **not** load InteractiveUtils. Write `using InteractiveUtils` before `@code_warntype`, `@which` or `versioninfo()`.

Package layout (tests in a workspace, the recommended setup since 1.12):
```
MyPkg/Project.toml       # name, uuid, version, [deps], [compat], [workspace] projects = ["test"]
MyPkg/src/MyPkg.jl       # module MyPkg ... end; include("x.jl") for other files
MyPkg/ext/MyPkgFooExt.jl # [weakdeps] Foo = "uuid"; [extensions] MyPkgFooExt = "Foo"
MyPkg/test/Project.toml  # deps: MyPkg, Test, Aqua, JET...
MyPkg/test/runtests.jl
```
Set up the test env with `julia --project=test -e 'using Pkg; Pkg.develop(path="."); Pkg.add("Test")'`. The workspace shares a single root Manifest.toml. An extension module does `using MyPkg, Foo` and adds methods to a function that MyPkg already declared (`function summarize end`).

Quality gates in `runtests.jl`:
```julia
using MyPkg, Test, Aqua, JET
@testset "MyPkg" begin
    @test f(2) == 4
    @test_throws ArgumentError "bad" g(-1)   # 1.13: type + message pattern
    @testset "Aqua" Aqua.test_all(MyPkg)
    @testset "JET" JET.test_package(MyPkg; target_modules=(MyPkg,))
end
```
Format with Runic (no config): `julia -e 'using Pkg; Pkg.Apps.add("Runic")'`, then `runic --check --diff .` or `runic --inplace .`. Its rules: 4-space indent, an explicit `return` in long-form functions, `for x in xs`, and `;` before keyword arguments. CI: `julia-actions/setup-julia@v2`, `cache@v2`, `julia-buildpkg@v1`, `julia-runtest@v1`.

## Executables
- **Pkg apps** (experimental): put `[apps] mytool = {}` in Project.toml (or `{ submodule = "CLI", julia_flags = ["-t4"] }`), define `function (@main)(args) ... end` in the module, then run `Pkg.Apps.develop(path=".")` or `Pkg.Apps.add("Name")`. The shims go into `~/.julia/bin`, which must be on PATH.
- **JuliaC + trim**: `Pkg.Apps.add("JuliaC")`, then `juliac --output-exe app --trim=safe --experimental [--bundle build] path/to/pkg_or_file.jl`. Write `function (@main)(args::Vector{String})::Cint`. Under `--trim`, every call must be statically resolvable. Typical error: `unresolved call from statement println(...)`. Fixes: print to `Core.stdout` (plain `println(x)` goes through the global `stdout::IO`), avoid `Any` containers, and give fields and arguments concrete types. `--bundle` may fail with EEXIST symlink errors on Homebrew Julia. Use the juliaup or official binary in that case.

## Version-specific API (1.11 to 1.13)
```julia
module M
export run!            # exported names are public
public helper          # public but not exported; using `public` and `export` on one name is an error
end
b = IOBuffer(); print(b, "x", 1); s = takestring!(b)   # 1.13; empties the buffer
Iterators.nth(itr, 3); collect(Iterators.findeach(iseven, v))   # 1.13
ispositive(x); isnegative(x); fieldindex(T, :field)      # 1.13
fact = n -> n <= 1 ? 1 : n * (@__FUNCTION__)(n - 1)      # 1.13: self-recursive lambda
sort(keys(d))                     # works in 1.13 (it used to throw)
mergewith(+, d1, d2)              # merge(f, d...) is deprecated
chopprefix(s, 'a'); chopsuffix(s, ".jl")
const CFG = OncePerProcess{Dict{String,Int}}(() -> load_cfg())   # lazy init: CFG()
const BUF = OncePerTask{Vector{Float64}}(() -> zeros(64))         # per-task scratch: BUF()
l = Lockable(Int[]); @lock l push!(l[], 1)
using Base.ScopedValues: ScopedValue, with, @with
const LEVEL = ScopedValue(1); with(() -> LEVEL[], LEVEL => 5)
waitall(tasks); waitany(tasks); logrange(1, 1000; length=4)
Base.Fix{2}(-, 1)(10) == 9; insertdims(A; dims=1); stack(vecs)
mutable struct C; @atomic n::Int; end; @atomic c.n += 1
```
- **Custom hashes**: define only `Base.hash(x::T, h::UInt) = hash(x.a, hash(:T, h))` together with `==`. Never give `h` a default value. The seed and the string hash changed in 1.13, so stored hash values are not stable across versions.
- **Redefinition** (1.12+): you can redefine a `struct` or `const` in a live session (world-age semantics). Code that calls a method created by `@eval` inside the same running function gets `MethodError ... method too new to be called from this world context`. Fix it with `@invokelatest f()` or `Base.invokelatest(f)`.
- `x.nofield` now throws `FieldError`, not `ErrorException`. `@doc` returns the documented object.
- `@atomic v[i]` works only on `AtomicMemory`. On a `Vector` it gives a `MethodError`. On a plain `Memory` it gives a `ConcurrencyViolationError`.

## Threads
- By default you get 1 worker thread plus 1 interactive thread (`Threads.nthreads()==1`). Start with `-t auto` or `-t N`. Since 1.13, `Sys.CPU_THREADS` counts every core on Apple Silicon.
- Don't index buffers by `threadid()`, because tasks migrate between threads. Split the work into chunks instead:
```julia
function psum(xs; n = Threads.nthreads())
    tasks = [Threads.@spawn sum(c) for c in Iterators.partition(xs, cld(length(xs), n))]
    return sum(fetch, tasks)
end
```
Use `@threads :greedy` for uneven work and `Threads.@spawn :samepool` to stay in the caller's thread pool.

## Performance rules
- Code that uses non-`const` globals has type `Any`. Pass values as arguments, or use `const X = ...` or a typed global `x::Int = 0`.
- Struct fields need concrete types. Use type parameters (`struct P{T<:Real}; x::T; end`), not `x::Real` and not untyped fields.
- If a captured variable is reassigned, the closure boxes it (`Core.Box` in `@code_warntype`). Don't reassign it, or bind it with `let x = x`.
- `Vector{Float64}` is not a subtype of `Vector{Real}` (types are invariant). Write `AbstractVector{<:Real}`.
- Measure allocations inside a function. Top-level `@allocated` also counts global boxing. Benchmark with `@btime f($x)` (BenchmarkTools) or `@b f($x)` (Chairmarks). Find dispatch with `JET.@report_opt f(x)`, and wrap it in `display` when running in a script.
- Use in-place updates (`y .= a .* x .+ y`, `map!`, `mul!`), `@views` for slices, and `similar`/`eachindex`. Loop down columns: arrays are column-major.
- Cut package latency with PrecompileTools: `@setup_workload begin ... @compile_workload begin calls end end`.
- `Int` overflows silently (`2^64 == 0`). Use `big`, `Int128` or `Base.checked_mul`.

## Common errors and fixes
| Error | Fix |
|---|---|
| `UndefVarError: s not defined in local scope` + soft-scope warning in a script loop | Wrap the code in a function (or write `global s`) |
| `MethodError: no method matching f(::Vector{Float64})` | Signature too narrow or invariant. Use `AbstractVector{<:Real}` |
| `InexactError: Int64(1.5)` | Wrong element type (`push!(Int[], 1.5)`). Use `round(Int, x)` or a `Float64` container |
| `StringIndexError` | Strings are indexed by byte. Use `eachindex`, `nextind`, `collect(s)` or `first(s, n)` |
| `UndefVarError: @code_warntype` | Add `using InteractiveUtils` |
| Aqua "Compat bounds ... weakdeps" | Add `[compat]` entries for the weak deps by hand |
| `Package X not found in current path` | Run `Pkg.add` in the right project (`--project`), then `Pkg.instantiate()` |
