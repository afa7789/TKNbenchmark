# Sources

## Official
- https://raw.githubusercontent.com/rust-lang/rust/master/RELEASES.md — release notes for 1.85–1.96: stabilized APIs (assert_matches, core::range, push_mut, extract_if, get_disjoint_mut, as_chunks, array_windows, atomic update, cfg_select, if-let guards, let chains), compatibility notes, and Cargo changes (host-tuple, `clean --workspace`, `--nocapture` deprecation).
- https://blog.rust-lang.org/2026/05/28/Rust-1.96.0/ — 1.96 highlights: `use core::assert_matches`, Copy `core::range::Range`, `impl RangeBounds` advice, wasm `--allow-undefined` change.
- https://doc.rust-lang.org/edition-guide/rust-2024/index.html — list of edition 2024 changes: unsafe extern, unsafe attributes, static_mut_refs, RPIT capture, temporary scopes, `gen` keyword, unsafe set_var, match ergonomics, resolver 3.
- https://doc.rust-lang.org/style-guide/index.html — default formatting (4 spaces, 100 columns, block indent, version sorting) that rustfmt implements.
- https://rust-lang.github.io/api-guidelines/checklist.html — API naming and conversion conventions, common traits, error types, and why examples use `?`.
- https://doc.rust-lang.org/cargo/reference/profiles.html — default dev/release profile values and the valid values of lto, strip and panic.
- https://doc.rust-lang.org/cargo/guide/build-performance.html — build-speed guidance (debug info levels, linkers).
- https://doc.rust-lang.org/cargo/reference/workspaces.html — workspace.package, workspace.dependencies and workspace.lints inheritance; virtual workspaces need an explicit resolver.

## Community agent rules and practice
- https://cdn.jsdelivr.net/gh/leonardomso/rust-skills@master/SKILL.md — widely shared Rust agent skill: no unwrap in prod, thiserror for libraries and anyhow for apps, borrowing over cloning, no lock held across await, workspace lints, MSRV.
- https://awesome-copilot.github.com/instruction/rust/ — GitHub Copilot Rust instructions: lib/main split, `&str` parameters, no premature collect, clippy and fmt gates.
- https://raw.githubusercontent.com/Taiizor/agents-md-cookbook/790e0ba0d9c7fc9b96992bd68f08e9bfcb4c217e/templates/rust/AGENTS.md — AGENTS.md template: fmt, clippy `-D warnings` and tests as the definition of done; `// SAFETY:` comments; no `allow` just to pass CI.
- https://cdn.jsdelivr.net/npm/@tansuasici/claude-code-kit@1.21.0/examples/rust/CLAUDE.md — CLAUDE.md for Rust: verification order (fmt, clippy, check, test, release build) and async rules (no blocking, no non-Send guards across await).
- https://dev.to/d-oit/github-rust-2026-template-my-rust-starter-in-2026-20b5 and https://skills.sh/existential-birds/beagle/rust-project-setup — how people set up projects today: `[lints]` in Cargo.toml with group priority, release profile with LTO, one codegen unit and strip, committing Cargo.lock for binaries.

## Verified locally (rustc/cargo 1.96.0, aarch64-apple-darwin)
Each API, error message and command in SKILL.md was compiled or run in a scratch crate, which has since been deleted. Findings that corrected the web sources or my memory:
- `HashMap::get_disjoint_mut` returns `[Option<&mut V>; N]`, not a `Result`.
- `Vec::extract_if` takes a range argument.
- rand 0.10.4 needs `RngExt` in scope and has no `thread_rng`, `gen` or `gen_range`.
- Bare `rustfmt` defaults to edition 2015.
- `cargo update --breaking` is nightly-only.
- The RefCell panic text is "RefCell already borrowed".
- `&raw const` on a `static mut` needs no `unsafe`.
- clippy `incompatible_msrv` fires against `rust-version`.
- `async fn` in a trait used with `tokio::spawn` fails with "future cannot be sent between threads safely".
