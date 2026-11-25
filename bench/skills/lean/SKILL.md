---
name: lean
description: "Version-correct, idiomatic Lean 4 for the installed toolchain (Lean (version 4.36.0, arm64-apple-darwin24.6.0, commit 611c117bfaf7b7ae1cfcf246ce6fba31e8f509e9, Release)): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Lean 4 code."
---

# Lean 4.36 (Lake 5): write correct code first try

Everything here was checked on `leanprover/lean4:v4.36.0`. The core library changed heavily in 4.2x–4.36, so names from older code may be gone. Check with `#check @Name` before relying on one.

## Project and commands
```
lake new app [exe|lib|math]  # lib App/ + Main.lean + lakefile.toml + lean-toolchain + CI
lake build [target]          # binary in .lake/build/bin/; flags --fail-fast, -q, -R
lake exe app a b             # build, then run with args
lake test                    # runs testDriver
lake env lean F.lean         # check a scratch file against project deps
lean --run F.lean args       # run `main` from a single file
lake update                  # re-resolve deps into lake-manifest.json (commit it)
```
In `lakefile.toml`, package keys **must come before the first `[[table]]`**. Otherwise TOML attaches them to that table and `lake test` says "no test driver configured".
```toml
name = "app"
defaultTargets = ["app"]
testDriver = "tests"
[leanOptions]
autoImplicit = false   # default true: typos silently become implicit args
[[require]]
name = "batteries"
scope = "leanprover-community"
rev = "v4.36.0"        # tag matches lean-toolchain (same for Mathlib)
[[lean_lib]]
name = "App"
[[lean_exe]]
name = "app"
root = "Main"
[[lean_exe]]
name = "tests"
root = "Tests.Main"    # main : IO UInt32; nonzero exit fails `lake test`
```
For Mathlib, run `lake exe cache get` before building. For CI, use `leanprover/lean-action@v1`.

## Module system
Templates don't use the `module` header. If a file starts with `module`:
- Declarations are **private by default**. Use `public def` or `public section … end`; `main` must be `public def main`.
- A `public def` exports only its type. Add `@[expose]` so other modules can unfold it with `rfl` or `decide`.
- `import X` is private. Re-export with `public import X`, which library roots need.
- `cannot import non-module X from module` means every file a module imports must also be a module.

## Strings: most results are now `String.Slice`
| Old / wrong | 4.36 |
|---|---|
| `s.trim` (removed) | `s.trimAscii`, `trimAsciiStart`/`End` → Slice |
| `s.dropRight n` (removed) | `s.dropEnd n`. `takeEnd`, `drop`, `take`, `dropWhile` → Slice |
| `String.mk l` (deprecated) | `String.ofList l` |
| `s.get i`, `s.iter`, `s.data` | `s.front`, `s.toList`, `s.chars` |
Turn a Slice back into a String with `.copy` (or `toString`). Slices support `toNat?`, `isEmpty`, `startsWith` and `split`.
```lean
"  42 ".trimAscii.toNat?                         -- some 42
("hello".drop 2).copy ++ "!"                     -- "llo!"
"a,b,,c".splitOn ","                             -- List String
("1 2 3".split ' ').toList.filterMap (·.toNat?)  -- split gives an iterator
("a b".split ' ').toStringList                   -- List String
```
A `Prop` inside `s!"…"` fails with `ToString Prop`; write `{decide (a < b)}`. `String` `<` compares UTF-8 bytes.

## Collections
- `import Std.Data.HashMap` (or `HashSet`, `TreeMap`) and `open Std`.
  - `HashMap.empty` and `find?` don't exist. Use `{}` or `HashMap.emptyWithCapacity n`, and `m[k]?`, `m.getD k d`, `m[k]!`.
  - Also available: `m.alter k (fun | none => some 1 | some n => some (n+1))`, `m.modify k f`, `m.fold (fun acc k v => …) x`, `for (k, v) in m do`, `HashMap.ofList`.
- `Lean.RBMap` is deprecated. Use `Std.TreeMap` (sorted, `minKey?`, `toList`) or `Std.TreeSet`.
- Removed: `List.iota`, `List.enum`, `Array.mkArray`, `Array.indexOf?`, `List.groupBy`, `Array.maximum?`. Use `List.range'`, `zipIdx` (gives `(x, i)`), `Array.replicate n v`, `idxOf?`, `splitBy`, `max?`.
- Sorting: `qsort (· < ·)`, or `mergeSort` (stable). For structs, use `qsort (fun p q => p.a < q.a)`. `deriving Ord` gives no `<`; add `instance : LT P := ltOfOrd`.
- `a[i]` needs a proof of `i < a.size`, else "failed to prove index is valid". Use `if h : i < a.size then a[i] else …`, `a[i]?`, `a[i]!`, or `for h : i in 0...a.size`.
- `Nat.toDigits base n` takes the base first: `(255).toDigits 16` uses base 255.

## Ranges, loops, `do` (new elaborator since 4.32)
`0...n` is half-open, `1...=n` is closed, and `0...<n` also exists. Ranges support `.toList`, `.toArray`, `.size`, and work on `Int` and `Char`. The legacy `[0:n:step]` still works in `for` but has no `.toList`.
```lean
def sumSq (a : Array Nat) : Nat := Id.run do
  let mut s := 0
  for h : i in 0...a.size do s := s + a[i] * a[i]
  return s
```
- `for x in xs, i in 0...n` zips. `while`, `repeat`, `break`, `continue` and early `return` work.
- `return e` inside `(← do …)` **returns from the whole function**; use `pure e` to produce the inner value.
- `do`-`match` is non-dependent; write `match (dependent := true)` when you need it. Use `let some v := o | return 0` for early exits.
- `IO.asTask act : BaseIO (Task (Except IO.Error α))`. Write `Task.spawn fun _ => …` and block with `.get`.

## IO (verified)
```lean
def main (args : List String) : IO UInt32 := do
  let all ← (← IO.getStdin).readToEnd  -- or getLine loop; "" = EOF
  let ls ← IO.FS.lines "in.txt"        -- Array String
  IO.FS.writeFile "out.txt" all
  IO.eprintln "log"
  let out ← IO.Process.output { cmd := "echo", args := #["hi"] }  -- .exitCode .stdout
  if ← System.FilePath.pathExists "x" then IO.FS.removeFile "x"
  let r ← IO.mkRef 0; r.modify (· + 1)
  return 0
```
Also: `IO.Process.exit : UInt8 → IO α`, `IO.monoMsNow`, `IO.getEnv`, `IO.FS.createDirAll`, `dir.readDir`, `IO.FS.withFile p .read (·.readToEnd)`, `"a" / "b.txt"`, `p.extension`. A failed read throws `IO.Error`; catch it with `try … catch e => … finally …`.

JSON: `import Lean.Data.Json` and `open Lean`, then `deriving ToJson, FromJson`. Serialize with `(toJson c).compress` and parse with `(Json.parse s >>= fromJson? : Except String Cfg)`. Duplicate keys are now an error.

## Termination and proofs
- The decreasing fact must be in scope: `if b = 0 then … else f b (a % b)` fails termination, but `if h : b = 0` works. Add `termination_by` or `decreasing_by` when needed.
- Use `partial def` for loops and possibly non-terminating code; it needs an `Inhabited` or `Nonempty` result type.
- `#eval` refuses code that depends on `sorry`; `#eval!` overrides that.
- Tactics: `omega` (linear Nat/Int), `decide`, `simp`, `grind`.
- Renamed: `if_pos`/`if_neg` → `ite_eq_left`/`ite_eq_right`, `dif_pos` → `dite_eq_left`, `letFun` → `have`, `mvcgen` → `vcgen`.
- `rwa … at h` must close the goal with `h`. `constructor` warns when it is ambiguous; use `left` or `right`.
- `Decidable` is a structure; build instances with `decidable_of_iff p ⟨…, …⟩`.
- `#print axioms t` lists axioms. `#guard b` checks at compile time. `/-- info: 3 -/ #guard_msgs in #eval …` pins output.

## Numerics
- `Nat` subtraction truncates: `3 - 5 = 0`.
- `Int` `/` and `%` are Euclidean: `-7 % 2 = 1`.
- `UIntN` wraps, and `(5 : Fin 3) = 2`.
- `Float.lt` returns `Bool`. `min` and `max` on `Float` propagate NaN; use `Float.minimumNumber`/`Float.maximumNumber` to ignore it.
- `Nat` is bignum; use `UInt64` in hot loops.

## Performance
- Array, String and HashMap update **in place only when unshared**. Rebind with `a := a.push x`, `set!`, `modify` or `swap`, and never keep the old value alive. `dbgTraceIfShared "msg" a` reports copies.
- Preallocate with `Array.emptyWithCapacity n`. Prefer `Array` to `List` for indexed data.
- Use `@[inline]` on small helpers and `@[specialize]` on higher-order ones. Builds are `release` by default, and the stack is 1 GB (`LEAN_STACK_SIZE_KB`).

## Style (core and Mathlib)
- Types `UpperCamelCase`, data `lowerCamelCase`, theorems `snake_case`.
- Suffix `?` for `Option` results and `!` for functions that can panic.
- Put functions in the type's namespace (`def Shape.area`) so dot notation works.
- Use `fun` (not `λ`) and `<|` (not `$`). Put `by` at the end of the line.
- Indent 2 spaces, keep lines ≤ 100 chars, write `/-- … -/` docstrings.
