---
name: rust
description: "Version-correct, idiomatic Rust for the installed toolchain (rustc 1.96.0 (ac68faa20 2026-05-25)): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Rust code."
---

# Rust 1.96 (edition 2024)

rustc/cargo 1.96. `cargo new` writes `edition = "2024"`, which implies resolver 3 (it picks dependency versions compatible with `rust-version`). All checked on 1.96.

## Project workflow
```sh
cargo new app            # --lib for a library; --vcs none to skip git
cargo add serde --features derive; cargo add --dev tempfile
cargo check --all-targets                       # fastest loop
cargo clippy --all-targets --all-features -- -D warnings
cargo fmt                                       # NOT bare `rustfmt file.rs` (defaults to edition 2015)
cargo test name_substr -- --no-capture          # `--nocapture` is deprecated
cargo test tests::exact_name -- --exact; cargo test --doc
cargo build --release; cargo doc --no-deps --open
cargo tree -d; cargo info <crate>; cargo publish --dry-run
```
`cargo update --breaking` works on nightly only. Layout: thin `src/main.rs`, logic in `src/lib.rs` so you can test it, `tests/*.rs` for integration tests, `benches/` with criterion or divan (`#[bench]` is unstable). Commit `Cargo.lock` for binaries.

```toml
[package]
edition = "2024"
rust-version = "1.96"   # clippy::incompatible_msrv flags APIs newer than this
[lints.rust]
unsafe_code = "forbid"
[lints.clippy]
pedantic = { level = "warn", priority = -1 }   # groups need priority -1
unwrap_used = "warn"
[profile.release]
lto = "fat"          # or "thin"
codegen-units = 1
panic = "abort"      # only if nothing relies on catch_unwind
strip = "symbols"
```
Workspaces: share `[workspace.package]`, `[workspace.dependencies]` and `[workspace.lints]`; members use `x.workspace = true`. A virtual workspace needs `resolver = "3"`.

## Edition 2024 rules (common compile errors)
- `extern "C" {}` gives "extern blocks must be unsafe". Write `unsafe extern "C" { pub safe fn abs(x: i32) -> i32; pub unsafe fn strlen(p: *const c_char) -> usize; }`.
- `#[no_mangle]` gives "unsafe attribute used without unsafe". Use `#[unsafe(no_mangle)]`, and likewise `#[unsafe(export_name = "..")]` and `#[unsafe(link_section = "..")]`.
- `std::env::set_var` and `remove_var` are `unsafe` (E0133).
- `&STATIC_MUT` is a deny-by-default error (`static_mut_refs`). Use atomics, `Mutex`, `LazyLock`/`OnceLock`, or `&raw const X`/`&raw mut X` (safe to take).
- An `unsafe fn` body is no longer an unsafe block. Wrap ops in `unsafe { }` with a `// SAFETY:` comment.
- `gen` is a keyword. Write `r#gen`.
- RPIT captures all in-scope lifetimes. If `fn f(x: &u32) -> impl Fn()` keeps `x` borrowed ("cannot assign … because it is borrowed"), add `+ use<>` (or `use<'a, T>`).
- "cannot explicitly borrow within an implicitly-borrowing pattern": `match &opt { Some(ref x) => …}` must become `Some(x)`.
- Temporaries in an `if let` scrutinee and in block tail expressions drop earlier. Guards no longer live into `else` or past the block.
- The `mismatched_lifetime_syntaxes` lint fires on `fn iter(&self) -> Iter<u8>`. Write `Iter<'_, u8>`.

## Language features you can use (stable)
```rust
if let Some((k, v)) = s.split_once('=') && let Ok(n) = v.parse::<i32>() && n > 0 { } // let chains
match x { Some(t) if let Ok(n) = t.parse::<i32>() => n, _ => 0 }  // if-let guard (1.95)
let Some(x) = opt else { return Err(..) };                       // let-else
async fn run<F: AsyncFn(u32) -> u32>(f: F) -> u32 { f(1).await } // async closures: async |x| ..
let d: &dyn Debug = &*boxed_sub;                                 // trait upcasting
#[expect(clippy::cast_possible_truncation, reason = "checked < 256")]  // instead of allow
const { assert!(N > 0) };  cfg_select! { unix => { .. } _ => { .. } }
```
`async fn` in a trait is not dyn-compatible (E0038) and its future is not `Send` (`tokio::spawn` fails). Declare `fn get(&self) -> impl Future<Output = T> + Send;` and implement it with `async fn`. Need `dyn`: use the `async-trait` crate.

## Recent std APIs
- Globals: `static C: LazyLock<T> = LazyLock::new(|| ..)` and `OnceLock::get_or_init` replace `lazy_static` and `once_cell`.
- `use std::assert_matches;` then `assert_matches!(r, Err(E::Port(_)))` (1.96, not in prelude).
- `std::range::Range::from(1..3)` is `Copy` (1.96). Accept `impl RangeBounds<usize>` in APIs.
- Vec: `v.extract_if(.., |x| pred)` (takes a range), `pop_if(|x: &mut T| ..)`, and `push_mut(x)` which returns `&mut T` (1.95). `HashMap`/`HashSet::extract_if(|k, v| ..)`.
- Slices: `get_disjoint_mut([i, j])` returns `Result<[&mut T; 2], _>`, while `HashMap::get_disjoint_mut([&k1, &k2])` returns `[Option<&mut V>; 2]` and panics on duplicate keys. Also `as_chunks::<N>()` returning `(&[[T; N]], &[T])`, `array_windows::<N>()` (1.94), `chunk_by`, `sort_by(f64::total_cmp)`.
- Integers: `is_multiple_of`, `div_ceil`, `midpoint`, `isqrt`, `ilog2`, `abs_diff`, `strict_add` (panics on overflow), `checked_`/`wrapping_`/`saturating_`, `cast_signed`/`cast_unsigned`, `bool::try_from(1u8)`, `NonZero<u32>`.
- Atomics: `a.update(Ordering::Relaxed, Ordering::Relaxed, |x| x + 1)` returns the previous value; `try_update` takes a closure returning `Option`. `Cell::update`.
- Misc: `Option::is_none_or`/`is_some_and`, `Result::inspect_err`/`flatten`, `Arc::unwrap_or_clone`, `iter::repeat_n`, `iter::chain(a, b)`, `array::from_fn`, `Peekable::next_if_map`, `str::floor_char_boundary(i)` (safe slicing), `io::pipe()`, `File::lock`/`try_lock`, `fmt::from_fn(|f| ..)` for ad-hoc `Display`, `thread::scope`, `hint::black_box`.

## Crate API drift
- rand 0.10: `let mut rng = rand::rng(); use rand::RngExt; rng.random_range(1..=6); rng.random::<f64>()`. `thread_rng`, `gen` and `gen_range` are gone; methods need `RngExt` in scope (else E0599). Seeded: `StdRng::seed_from_u64` (`SeedableRng`). Use `seq::SliceRandom::shuffle` and `seq::IndexedRandom::choose`.
- thiserror 2, anyhow 1, clap 4 (`#[derive(Parser)] #[command(version, about)]`, `#[arg(short, long, default_value_t = 3)]`), tokio 1 (`features = ["full"]` or e.g. `rt-multi-thread,macros`).

## Errors and idioms
- Libraries: `#[derive(Debug, thiserror::Error)]` enum, `#[error("failed to read {path}")] Io { path: PathBuf, #[source] source: io::Error }`, `#[from]` for `?` conversion. Binaries: `anyhow::Result` with `.context()` or `.with_context(|| format!(..))`. `Err` from `main` prints `Debug` (anyhow formats it well).
- No `unwrap` outside tests or proven invariants; `lock().unwrap()` is accepted, or `unwrap_or_else(PoisonError::into_inner)` to ignore poisoning.
- Take `&str`, `&[T]`, `&Path` and `impl AsRef<Path>` as parameters, and return owned values. Use `Cow` when a value is sometimes borrowed.
- Fast I/O: `io::read_to_string(io::stdin())?` plus `BufWriter::new(io::stdout().lock())`. `println!` locks and flushes per line, which is slow in loops.
- Use `with_capacity`, reuse buffers with `clear()`, and prefer iterators to indexing. Benchmark with `--release`. Overflow panics in debug and wraps in release.
- Async: never hold a `std::sync::MutexGuard` across `.await` ("future cannot be sent between threads safely"). Drop it in an inner block or use `tokio::sync::Mutex`. Move CPU or blocking work to `spawn_blocking`. Prefer bounded channels.
- Doctests: end with `# Ok::<(), MyErr>(())` so you can use `?`. Doctests run only for library crates.

## Error quick-fixes
- E0382 use after move: borrow (`&x`), `.clone()` deliberately, or restructure. Loops: iterate `&v`.
- E0499/E0502 conflicting borrows: shorten the borrow (bind the result first), split struct fields, use `get_disjoint_mut`, `split_at_mut` or indices, or `mem::take`.
- E0507 move out of borrow or index: `mem::take`, `Option::take`, `.clone()`, `swap_remove`, or iterate with `into_iter()`.
- E0716 temporary dropped while borrowed: bind it with `let`.
- E0373 closure may outlive: use `move`, or `thread::scope`.
- E0277 `?` couldn't convert the error: add `#[from]`, `map_err`, or use `anyhow`.
- E0599 method not found: import the trait (`io::Write`, `fmt::Write`, `RngExt`, `FromStr`).
- Panic "RefCell already borrowed": overlapping `RefCell` borrows; scope them tighter.
