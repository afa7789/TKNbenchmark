---
name: zig
description: "Version-correct, idiomatic Zig for the installed toolchain (0.16.0): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Zig code."
---

# Zig 0.16.0

Most Zig code online is pre-0.15 and no longer compiles. In 0.16 **all I/O goes through a `std.Io` value**, containers are **unmanaged**, and readers/writers are **non-generic, caller-buffered** `*std.Io.Reader`/`*std.Io.Writer`. `has no member named` on a std API means you used an old API. Grep the std sources (`zig env` → `std_dir`) instead of guessing.

## Core rules
- Anything that touches the OS (files, stdout, sleep, clocks, randomness, sockets, processes, mutexes) takes `io: std.Io`. Get it from `init.io` in `main` or `std.testing.io` in tests. Libraries take `io` as a parameter, never a global.
- Allocators are explicit: `var l: std.ArrayList(T) = .empty;`, `l.append(gpa, x)`, `l.deinit(gpa)`.
- Writers need a buffer and `flush()`. **Never copy `.interface`** (`var w = fw.interface;` segfaults). Use `&fw.interface`.
- Functions that write take `w: *std.Io.Writer`. A `format` method is `pub fn format(self: T, w: *std.Io.Writer) std.Io.Writer.Error!void`, and only `{f}` calls it (`{}` silently prints raw fields).

## main ("juicy main")
```zig
const std = @import("std");
const Io = std.Io;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const gpa = init.gpa; // leak-checked in Debug
    const arena = init.arena.allocator(); // lives until exit
    const args = try init.minimal.args.toSlice(arena); // or .iterate()
    const home = init.environ_map.get("HOME") orelse "";

    var out_buf: [4096]u8 = undefined;
    var out: Io.File.Writer = .init(.stdout(), io, &out_buf);
    const stdout = &out.interface;
    try stdout.print("{d} {s}\n", .{ args.len, home });
    try stdout.flush();
    _ = gpa;
}
```
With no `Init` parameter, build your own: `var dbg: std.heap.DebugAllocator(.{}) = .init; defer _ = dbg.deinit();`, then `var th: std.Io.Threaded = .init(gpa, .{}); defer th.deinit(); const io = th.io();`. `std.process.fatal(fmt, args)` prints and exits with code 1.

## Old → 0.16
| Old | 0.16 |
|---|---|
| `std.fs.cwd()`, `std.fs.File` | `std.Io.Dir.cwd()`, `std.Io.File` |
| `std.io.getStdOut().writer()` | `std.Io.File.stdout().writer(io, &buf)` → `&w.interface` |
| `std.io.fixedBufferStream` | `var w: std.Io.Writer = .fixed(&buf)` / `std.Io.Reader.fixed(bytes)` |
| `ArrayList(u8).writer()` | `list.print(gpa, fmt, args)` or `var aw: std.Io.Writer.Allocating = .init(gpa)` → `&aw.writer`, `aw.written()` |
| `GeneralPurposeAllocator` | `heap.DebugAllocator(.{})` / `init.gpa` |
| `std.process.argsAlloc`, `std.posix.getenv` | `init.minimal.args`, `init.environ_map.get` |
| `std.time.sleep`/`Thread.sleep` | `try io.sleep(.fromMilliseconds(10), .awake)` |
| `std.time.milliTimestamp`/`Timer` | `Io.Timestamp.now(io, .awake)`, `t0.untilNow(io, .awake).toMilliseconds()`, wall clock `Io.Clock.real.now(io).toSeconds()` |
| `std.crypto.random` | `io.random(&buf)` (`randomSecure` for keys) |
| `Thread.Mutex`/`Condition`/`ResetEvent`/`WaitGroup`/`Pool` | `Io.Mutex`/`Io.Condition`/`Io.Event`/`Io.Group` |
| `std.net` | `std.Io.net`: `IpAddress.parse("127.0.0.1", port)`, `.listen(io, .{})`, `.connect(io, .{ .mode = .stream })` |
| `Child.init`+`spawn`, `Child.run` | `std.process.spawn(io, .{ .argv = a, .stdout = .pipe })`, `std.process.run(gpa, io, .{ .argv = a })` |
| `AutoArrayHashMap(K,V).init(a)` | `std.array_hash_map.Auto(K,V) = .empty` (also `.String`, `.Custom`) |
| `BoundedArray` | `ArrayList(T).initBuffer(&buf)` + `appendBounded`/`appendSliceBounded` |
| `@Type(.{ .int = ... })` | `@Int(.unsigned, n)`, `@Struct`, `@Enum`, `@Union`, `@Pointer`, `@Fn`, `@Tuple`, `@EnumLiteral` |
| `@cImport` | `b.addTranslateC(...)` in build.zig, then `@import("c")` |
| `fs.Dir.makePath` / `makeDir` | `dir.createDirPath(io, p)` / `dir.createDir(io, p, .default_dir)` |

## Files
```zig
const cwd = std.Io.Dir.cwd();
const data = try cwd.readFileAlloc(io, "in.txt", gpa, .limited(16 << 20)); // error.StreamTooLong past limit
defer gpa.free(data);
try cwd.writeFile(io, .{ .sub_path = "out.txt", .data = data });

const f = try cwd.openFile(io, "in.txt", .{}); // createFile(io, p, .{}) to write
defer f.close(io);
var rbuf: [64 * 1024]u8 = undefined; // longer line → error.StreamTooLong
var fr = f.reader(io, &rbuf);
while (try fr.interface.takeDelimiter('\n')) |line| { _ = line; } // null at EOF

var dir = try cwd.openDir(io, "src", .{ .iterate = true });
defer dir.close(io);
var it = dir.iterate();
while (try it.next(io)) |e| if (e.kind == .file) {};
```
Also: `dir.statFile(io, p, .{})`, `file.length(io)`, `deleteFile(io, p)`, `deleteTree(io, p)`, `rename(old, new_dir, new, io)`, `std.Io.Dir.path.join(gpa, &.{a, b})`. `error.ReadFailed`/`WriteFailed` hide the cause, which is in `fr.err`/`fw.err`. Reader: `takeByte`, `takeInt(u32, .little)`, `take(n)`, `peek(n)`, `allocRemaining(gpa, .limited(n))`.

## Concurrency
```zig
var fut = io.async(work, .{arg}); // may run inline; io.concurrent forces parallelism
defer _ = fut.cancel(io); // idempotent, safe after await
const r = fut.await(io);

var g: Io.Group = .init;
errdefer g.cancel(io);
for (items) |it| g.async(io, process, .{ io, it });
try g.await(io);

var m: Io.Mutex = .init;
m.lockUncancelable(io); defer m.unlock(io); // or `try m.lock(io)`
```
Propagate `error.Canceled`; don't swallow it.

## Formatting
`{s}` string, `{d}` number, `{x}` hex, `{t}` enum tag or error name, `{f}` format method, `{any}` debug, `{B}`/`{Bi}` byte sizes, `{d:.2}`, `{s:>8}`. `{}` on a slice is a compile error. `{D}` is gone; use `{f}` on an `Io.Duration`. Helpers: `std.fmt.allocPrint(gpa, ...)`, `std.fmt.bufPrint(&buf, ...)`, `std.fmt.parseInt(T, s, 10)`, `std.fmt.parseFloat`. JSON: `std.json.parseFromSlice(T, gpa, s, .{ .ignore_unknown_fields = true })` → `.value`, then `deinit()`. Write with `std.json.Stringify.value(v, .{}, w)` or `{f}` with `std.json.fmt(v, .{})`.

## Project & build
`zig init` makes `build.zig`, `build.zig.zon`, `src/{main,root}.zig`. The zon needs `.name = .my_pkg` (an enum literal) and a generated `.fingerprint` (`invalid fingerprint` errors print a valid one). Executables need `root_module`:
```zig
const exe = b.addExecutable(.{ .name = "app", .root_module = b.createModule(.{
    .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize,
    .imports = &.{.{ .name = "dep", .module = b.dependency("dep", .{ .target = target, .optimize = optimize }).module("dep") }},
}) });
// library: b.addLibrary(.{ .name = "x", .linkage = .static, .root_module = mod });
// tests:   b.addRunArtifact(b.addTest(.{ .root_module = mod }))
// C:       mod.addCSourceFiles(.{ .files = &.{"c/a.c"} }); .link_libc = true; mod.linkSystemLibrary("z", .{})
// C hdr:   b.addTranslateC(.{ .root_source_file = b.path("c/a.h"), .target = target, .optimize = optimize }).createModule()
```
Commands: `zig build run -- args`, `zig build test --summary all`, `zig build --release=fast` (or `-Doptimize=ReleaseSafe`), `-Dtarget=x86_64-linux-musl`, `--watch`, `--test-timeout 10s`, `zig test f.zig --test-filter name`, `zig fmt --check .`, `zig fetch --save <url>` (deps go into `zig-pkg/`). Analysis is lazy, so unreferenced code isn't type-checked: run both `zig build` and `zig build test`.

## Tests
`std.testing.allocator` fails on leaks. Use `std.testing.io` and `var tmp = std.testing.tmpDir(.{}); defer tmp.cleanup();` (`tmp.dir`). Argument order is `expectEqual(expected, actual)`.

## Errors → fix
- `member function expected N argument(s)` → it now needs `io` or `gpa` (`openFile(io, …)`, `append(gpa, …)`, `writer(io, &buf)`).
- `expected type '*Io.Writer', found '*const Io.Writer'` → pass `&w` (a `var`).
- `returning address of expired local variable` → return by value or allocate.
- `vector index not comptime known` → `const a: [N]T = vec;` then index the array.
- Float to int: `const i: i32 = @floor(f);` (`@intFromFloat` is deprecated). `u24` and narrower coerce to `f32` implicitly.
- Packed types can't hold pointers (use `usize`). Extern enums need a tag type (`enum(u8)`).
