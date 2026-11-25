---
name: odin
description: "Version-correct, idiomatic Odin for the installed toolchain (Odin dev-2026-11:9a6991685): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Odin code."
---

# Odin dev-2026-11

Verified on `dev-2026-11:9a6991685`. APIs change monthly, so trust this file over memory. Signatures live in `$(odin root)core/`.

## Commands
```sh
odin run . -debug -- a b                   # program args after --
odin build . -o:speed -out:build/app       # build/ must exist (mkdir -p)
odin check . -vet -strict-style -vet-tabs -disallow-do -warnings-as-errors  # lint gate
odin test tests -collection:app=src -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true
odin test . -- -tests:name                 # or -define:ODIN_TEST_NAMES=pkg.name
odin build lib -build-mode:dll -out:libx.dylib   # :lib :obj
odin build . -debug -sanitize:address
```
`-define:N=v` sets `N :: #config(N, default)`. `odinfmt`/`ols` are installed separately.

## Layout
```
src/main.odin        package main   (1 dir = 1 package)
src/calc/calc.odin   package calc → import "calc" (relative path)
tests/x_test.odin    package tests → import "app:calc" via -collection:app=src
```
Files ending `_darwin/_linux/_windows/_amd64.odin` are picked automatically. File tag: `#+build linux, darwin`. In code: `when ODIN_OS == .Darwin {}`. No package manager; vendor deps.

## core:os is the new API (since dev-2026-03)
`core:os/os2` and `core:os/old` are gone, and so are `os.Handle`, `os.Errno` and the `ok: bool` returns. Files are `^os.File`. `os.Error` is a union (`General_Error`, `io.Error`, `Allocator_Error`, `Platform_Error`) and `nil` means OK. **Allocating procs require an allocator.**
```odin
data, err := os.read_entire_file(path, context.allocator); defer delete(data)
werr := os.write_entire_file("out.txt", "string or []byte")
f, ferr := os.open("log.txt", {.Write, .Create, .Trunc})   // default {.Read}; .Append .Excl
if ferr != nil { fmt.eprintln(os.error_string(ferr)); os.exit(1) }
defer os.close(f)
fmt.fprintfln(f, "x=%d", 5); os.write_string(f, "hi\n")
if err == .Not_Exist {}
os.args   // []string, [0]=exe; os.stdout/os.stderr are ^os.File
infos, _ := os.read_all_directory_by_path(dir, context.allocator)
defer os.file_info_slice_delete(infos, context.allocator)
fi, _ := os.stat(p, context.allocator); defer os.file_info_delete(fi, context.allocator)
w := os.walker_create(root); defer os.walker_destroy(&w)
for info in os.walker_walk(&w) { if _, e := os.walker_error(&w); e != nil { continue } }
jp, _ := os.join_path({a, b}, context.temp_allocator)    // os.base/dir/ext/stem/exists/is_directory
st, out, eout, perr := os.process_exec({command = {"ls"}}, context.allocator) // delete out, eout
```

## Other breaking changes
- `using` as a statement or param modifier needs `#+feature using-stmt` at the top of the file (struct-field `using` is fine).
- `strconv.atoi/itoa/atof` are deprecated. Use `parse_int(s) -> (int, bool)`, `parse_f64`, `write_int(buf, i64(n), 10)`.
- `core:strings` procs are `@(require_results)`.
- fmt: `%5d` pads with spaces; only `%05d` pads with zeros.
- `core:compress`: `Image.pixels` is `[dynamic]byte`; zlib/gzip are deprecated in favor of `compress/deflate`.
- `mem.DEFAULT_PAGE_SIZE` → `mem.PAGE_SIZE`.
- New syntax: `[dynamic; N]T`; `for i := 0; x in xs {}`; `"""…"""` multi-line strings (indent stripped); `**x` = `expand_values(x)`.
- A warning fires for atomics on locals that are never shared.

## Memory
Free with the same allocator: `make`→`delete` (slice, dynamic array, map, string), `new`→`free`, `builder_make`→`builder_destroy`.
```odin
when ODIN_DEBUG {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	context.allocator = mem.tracking_allocator(&track)
	defer { for _, e in track.allocation_map { fmt.eprintfln("%v leaked %v", e.location, e.size) }
	        mem.tracking_allocator_destroy(&track) }
}
s := fmt.tprintf("%d", n)    // temp: free_all(context.temp_allocator) per frame/request
{ runtime.DEFAULT_TEMP_ALLOCATOR_TEMP_GUARD() }   // "base:runtime", scoped temp
arena: vmem.Arena            // vmem "core:mem/virtual"
_ = vmem.arena_init_growing(&arena); defer vmem.arena_destroy(&arena)
xs := make([]T, n, vmem.arena_allocator(&arena))
```
- `strings.to_string(b)` is a **view** of the builder. Don't `delete` it; clone it if it must outlive the builder.
- `strings.split/fields` allocate only the slice; the parts are views.
- `make([dynamic]T, n)` sets **len** n. For capacity only, use `make([dynamic]T, 0, n)` or `reserve`.
- A zero map or dynamic array allocates on first insert, but still needs `delete`.
- For speed: `reserve` up front, `for &v in xs` to mutate in place, `unordered_remove`, `#no_bounds_check` on tested hot procs.

## Errors
```odin
Parse_Error :: enum { None, Empty }
Error :: union #shared_nil { Parse_Error, os.Error }
parse :: proc(path: string) -> (sum: int, err: Error) {
	data := os.read_entire_file(path, context.allocator) or_return
	defer delete(data)
	s := string(data)
	if len(s) == 0 { return 0, Parse_Error.Empty }  // bare .Empty fails for a union
	for line in strings.split_lines_iterator(&s) {
		sum += strconv.parse_int(strings.trim_space(line)) or_continue
	}
	return
}
if pe, ok := err.(Parse_Error); ok {}    // bare u.(T) panics on mismatch
idx := find(xs, 3).? or_else -1          // Maybe(T)
```
`or_return` requires the enclosing proc to return results, and its last result must be able to hold the error.

## Gotchas
- None of these exist: `++`, implicit numeric conversion (write `int(x)`/`cast`/`transmute`), pointer arithmetic (use `[^]T`), methods, closures, exceptions.
- `switch` on an enum or union must be exhaustive, or written `#partial switch`.
- A composite literal in an `if`/`for` header needs parens: `for x in ([]int{1, 2}) {}`.
- `m[k].f = v` is illegal. Use `p := &m[k]; p.f = v`, or `for k, &v in m`.
- `proc "c"` callbacks have no context: start them with `context = runtime.default_context()`.
- `for r, i in s` yields runes and byte offsets; `len(s)` counts bytes. C strings: `strings.clone_to_cstring(s, alloc)`, then `string(cs)` back.
- Style: `Ada_Case` types and enum members, `snake_case` everything else, `SCREAMING_SNAKE` constants, tabs.

## Stdlib (verified)
```odin
b := strings.builder_make(); defer strings.builder_destroy(&b)
fmt.sbprintf(&b, "%v", x); str := strings.to_string(b)
slice.sort(xs[:]); slice.sort_by(ps, proc(a, b: P) -> bool { return a.x < b.x })
Opts :: struct { file: string `args:"pos=0,required" usage:"Input."`, n: int, v: bool }
o: Opts; flags.parse_or_exit(&o, os.args, .Odin)   // prog f.txt -n:3 -v
js, _ := json.marshal(cfg, {pretty = true}, context.temp_allocator)
uerr := json.unmarshal(js, &cfg, allocator = context.allocator)
context.logger = log.create_console_logger(); defer log.destroy_console_logger(context.logger)
thread.run_with_poly_data2(&st, &wg, proc(s: ^St, wg: ^sync.Wait_Group) { defer sync.wait_group_done(wg) })
sync.mutex_lock(&mu); defer sync.mutex_unlock(&mu)   // wait_group_add/_wait, atomic_add
t0 := time.tick_now(); el := time.tick_since(t0)
```
Tests: `@(test) t_x :: proc(t: ^testing.T) { testing.expect_value(t, got, want); testing.expectf(t, ok, "%v", v) }`. A leak is only a WARN unless `ODIN_TEST_FAIL_ON_BAD_MEMORY=true`. `log.error` fails the test.

## Error → fix
| Message | Fix |
|---|---|
| `'Handle' is not declared by 'os'`, no match for `os.read_entire_file` | new os API + allocator |
| `Path does not exist: core:os/os2` | `core:os` |
| `Postfix '++' … not supported` | `x += 1` |
| `requires that its results must be handled` | use the result |
| `'using' has been disallowed` | `#+feature using-stmt` |
| `Unhandled switch case` | add the case / `#partial` |
| `Cannot assign to struct field … in map` | `&m[k]` |
| `Expected 1 expression` in a header | parenthesize literal |
| `Invalid type … for implicit selector` | `Type.Value` |
| `'context' has not been defined` | `context = runtime.default_context()` |
| `Cannot assign end value … in 'or_return'` | match the caller's error type |
| `shadows declaration` (-vet) | rename (`x := x` is OK) |
| `ld: open() failed` | mkdir the -out dir |
