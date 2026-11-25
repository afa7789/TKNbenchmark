---
name: nim
description: "Version-correct, idiomatic Nim for the installed toolchain (Nim Compiler Version 2.4.2 [MacOSX: arm64]): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Nim code."
---

# Nim 2.4 (2.4.2)

Defaults: `--mm:orc`, `--threads:on`. Defects: `IndexDefect`, `RangeDefect`,
`OverflowDefect`, `FieldDefect`, nil deref = SIGSEGV.

## Project, build, test
```
nimble init app -y        # lib layout: app.nimble, src/app.nim, tests/test1.nim, tests/config.nims
nimble build | test | run -- args   # test runs tests/t*.nim; NOT `run app -- x` (passes "--")
nimble add results        # adds `requires "results >= x"` to .nimble
nimble c -r src/f.nim     # compile with package deps on path; `nimble tasks` lists tasks
nim c -r --hints:off f.nim args     # or `nim r f.nim`
nim check src/app.nim     # fast typecheck, no codegen
nim c -d:release --outdir:bin src/app.nim       # ship: checks still ON, -O3
nim c -d:danger -d:lto --opt:speed -o:bin/app src/app.nim  # all checks off
nim doc --outdir:docs src/app.nim; nimpretty f.nim; --styleCheck:error
```
`.nimble`: `srcDir = "src"`, `bin = @["app"]`, `requires "nim >= 2.2.0"`,
`task lint, "desc": exec "nim check src/app.nim"`. Use `when isMainModule: main()`.
Put flags in `config.nims` (`switch("define", "ssl")`). Imports: `std/[os, strutils]`, deps: `pkg/x` or `x`.

## 2.2→2.4 changes that bite
- Bare `except:` no longer catches `Defect` (panics). Write `except CatchableError:`;
  `except Defect:` only in tests.
- `tables.getOrDefault(t, k, def = v)`: the param is now `def`, not `default`.
- Deprecated, moved to nimble packages: `std/sha1`, `std/md5` →
  `checksums/sha1|md5`; `std/parsesql` → `parsesql`; `std/threadpool` → `malebolgia`/`taskpools`.
- `std/re`, `std/nre` deprecated. `std/nre2` (same API as nre) needs `nimble add regex`.
- `unsafeAddr` deprecated alias → `addr`. `newSeqUninitialized` → `newSeqUninit[T](n)`.
- New: `setLenUninit` (seq and string), `multiReplace(s, ({'-','_'}, ' '))` charset form,
  `min/max(arr, cmpProc)`, `x ^ 0.5` floats, `std/files`+`std/dirs` (Path: `copyFile`,
  `tryRemoveFile`, `copyDir`), `--mm:yrc` (ORC with cross-thread cycles), `--strings:sso`.
- `{.cyclic.}` imports and `--ic:on` need nimony tools: don't use.

Sum types (new; classic `case kind: K` objects still fine):
```nim
type Shape = object
  case
  of Circle: r: float
  of Rect: w, h: float
proc area(s: Shape): float =
  case s
  of Circle(r): 3.14 * r * r
  of Rect(w, h): w * h
echo area(Rect(w: 2, h: 3)), Circle(r: 1.0)   # 6.0Circle(r: 1.0)
```
Fields are only reachable via such `case` (or `{.cast(uncheckedAccess).}`).

## Daily stdlib (verified)
```nim
import std/[strformat, strutils, sequtils, tables, sets, json, jsonutils, options,
            algorithm, sugar, os, osproc, times, monotimes, parseopt]
echo fmt"{name:>6}|{x:.2f}|{n:08b}|{name=}|{{lit}}"     # & "…" also works
"a,b".split(','); s.strip; s.splitWhitespace; parseInt(s)  # ValueError on bad input
xs.mapIt(it*2).filterIt(it > 4); xs.foldl(a + b); collect(for x in xs: x)
xs.sorted(SortOrder.Descending); us.sortedByIt(it.age); us.sort((a, b) => cmp(a.n, b.n))
var t = initTable[string, seq[int]](); t.mgetOrPut("k", @[]).add 1
t["missing"]  # KeyError; use getOrDefault / `in` / withValue
var c = initCountTable[string](); c.inc w; c.largest
let j = parseJson(str); j["a"].getStr; j{"x"}.getInt(-1); j.to(User)  # missing field: KeyError
%*{"a": 1, "b": [x]}; u.toJson; j.jsonTo(User)   # jsonutils; Option fields ↔ null
let (output, code) = execCmdEx("git rev-parse HEAD")
for kind, key, val in getopt(): ...   # cmdArgument / cmdLongOption / cmdShortOption / cmdEnd
(getMonoTime() - t0).inMilliseconds; now().format("yyyy-MM-dd")
readFile/writeFile/lines(path); paramStr(1), commandLineParams(), getEnv("X")
```
Custom key in `Table`/`HashSet`: `proc hash(p: P): Hash = hash((p.x, p.y))` (import `std/hashes`) plus `==` (auto for objects).
Importing `std/os` and `std/paths` together: `getCurrentDir()` is ambiguous → `os.getCurrentDir()`.

## Errors and effects
```nim
type ParseError* = object of CatchableError        # never inherit Exception directly
proc parse*(s: string): int {.raises: [ParseError].} =
  try: parseInt(s)
  except ValueError as e: raise newException(ParseError, "bad: " & s, e)  # e = parent
```
`{.push raises: [].}` at module top makes the compiler enforce effect lists.
`Option[T]`: `some(x)`, `none(int)`, `.isSome`, `.get`, `.get(default)`.
For `Result[T, E]` use package `results`: `ok(x)`, `err("m")`, `r.isOk`, `r.error`, `r.valueOr(0)`.

## Memory, ownership, speed
- Hooks (2.x signatures): `proc `=destroy`(x: T)` (non-var), `=wasMoved(x: var T)`,
  `=copy(dst: var T; src: T)`, `=dup(src: T): T`, `=sink`. Mark `{.error.}` for move-only.
- `sink` params take ownership; `move x` forces it; `lent T` returns a borrow.
  Implicit last-use moves happen only for locals: top-level globals are copied. Put code in
  `proc main()` (faster too: globals block many optimizations).
- `newSeqOfCap[T](n)`, `newStringOfCap(n)`, `for x in s.mitems: x *= 2`, `openArray[T]`
  params, `toOpenArray(s, a, b)` for zero-copy slices (`s[a..b]` copies).
- `{.inline.}`, `func` (no side effects), `const x = static: ...` for compile-time tables.
- `ref object` has no `$`: print `r[]` or `repr(r)`. Value objects/tuples get `$` automatically.
- `uint8(300) == 44` (unsigned conversions are NOT range-checked); `int8(300)` → RangeDefect.
- Signed int overflow → `OverflowDefect`; use `uint`/`+%` for wraparound.

## Concurrency
```nim
import std/[asyncdispatch, typedthreads, locks]
proc fetch(i: int): Future[int] {.async.} = await sleepAsync(10); return i*2
echo waitFor all(@[fetch(1), fetch(2)])
var ch: Channel[string]; ch.open()       # in system; send/recv/close
proc worker(n: int) {.thread.} = ch.send($n)
var th: Thread[int]; createThread(th, worker, 3); echo ch.recv(); joinThread(th)
var L: Lock; initLock(L); var total {.guard: L.} = 0
withLock L: total += 1
```
Thread procs can't touch GC'd globals (seq/string/ref): pass data via params/channels.
Thread pool (package `malebolgia`):
```nim
var m = createMaster()
m.awaitAll:
  for i in 0..3: m.spawn sq(i) -> res[i]   # res: seq preallocated
```

## Compiler errors → fix
- `expression 'f()' is of type 'int' and has to be used (or discarded)` → `discard f()`.
- `type mismatch … expression 'x' is immutable, not 'var'` → arg must be a `var` variable (seq `add` on a `let`).
- `type mismatch: got 'int' … expected 'uint8'` / `a + b` int+float → explicit `T(x)` / `x.float`.
- `undeclared identifier` → missing import, or proc used before its declaration (Nim is
  order-dependent: reorder or forward-declare `proc f(x: int): int`).
- `ambiguous call; both A.f and B.f match` → qualify `A.f(...)` or `from B import nil`.
- `can raise an unlisted exception: ValueError` → catch it or add to `raises`.
- `'worker' is not GC-safe as it accesses 'names'` → stop sharing globals across threads.
- `'=dup' is not available … not the last read` → move-only type used twice: `move` or restructure.
- `invalid indentation` → 2 spaces, no tabs; continuation lines after an operator or `(`.
- `undeclared field: 'y' for type A` → typo, or field not exported (`*`) from its module.
- Runtime `field 's' is not accessible … using 'kind = kInt'` → check discriminator first.

## Style (NEP1)
camelCase procs/vars, PascalCase types and constants; `parseUrl` not `parseURL`. Identifiers match
ignoring case except first letter and `_` (`some_Thing == someThing`). Pure-enum values PascalCase,
others prefixed (`pcDir`). Errors `XxxError`, panics `XxxDefect`. Constructors `initX` (value) /
`newX` (ref); build objects with `T(field: v)`. Prefer `result`/expression value over `return`;
`let` over `var`. Export with `*`. Tests: `std/unittest` `suite`/`test`/`check`/`expect E:`.
