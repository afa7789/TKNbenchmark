# Sources

- https://lean-lang.org/doc/reference/latest/releases/ — release index; confirmed 4.36.0 (2026-11-16) is the current stable.
- https://lean-lang.org/doc/reference/4.36.0/releases/v4.36.0/ — Float min/max semantics, String byte-order `<`, Json duplicate-key rejection, `withPtrEq` removal, `vcgen` deprecations.
- https://lean-lang.org/doc/reference/4.36.0/releases/v4.35.0/ — `Decidable` as structure, `rwa`/`constructor` changes, range-notation parsing, `lake check`, `--fail-fast`.
- https://lean-lang.org/doc/reference/4.36.0/releases/v4.34.0/ — `if_pos`→`ite_eq_left`, `letFun` deprecation, `lake update` strictness.
- https://lean-lang.org/doc/reference/4.36.0/releases/v4.33.0/ — `Float.lt` returns Bool, `requiresModuleSystem`, exe template change.
- https://lean-lang.org/doc/reference/4.36.0/releases/v4.32.0/ — new `do` elaborator semantics (`return` in `(← do …)`, non-dependent match), `Lean.RBMap` deprecated for `Std.TreeMap`.
- https://lean-lang.org/doc/reference/4.36.0/releases/v4.31.0/ — `while let`, structure-instance pattern change, `instance` checks.
- https://lean-lang.org/doc/reference/4.36.0/releases/v4.30.0/ — String.Slice API changes, `Array.mergeSort`, 1 GB default stack, Lake config moves.
- https://mathlib.org/contribute/style.html — Mathlib style: 100-char lines, `fun` not `λ`, `<|` not `$`, `by` at line end, indentation.
- https://github.com/leanprover/lean4/blob/master/doc/std/naming.md — core naming: UpperCamelCase types, lowerCamelCase data, snake_case theorems, `?`/`!` suffixes, namespace placement.
- https://github.com/leanprover/lean4/blob/master/doc/std/style.md — core library whitespace and line-splitting rules.
- https://github.com/leanprover/skills — official Lean agent skills (lean-proof, lean-mwe, lean-setup): incremental checking, error priority, `#guard_msgs`, `lake env lean`.
- https://github.com/cameronfreer/lean4-skills — community Lean 4 agent skill pack: build/axiom-check loop (`#print axioms`), checkpoint with full project build.
- Installed toolchain `~/.elan/toolchains/leanprover--lean4---v4.36.0/src/lean/lake/README.md` — `lake new` templates, lakefile.toml options, `testDriver`, `[[require]]` TOML syntax.
- Installed toolchain sources (`src/lean/Init`, `Std`) plus scratch builds with `lean`/`lake` 4.36.0 — verified every API name, signature and command in SKILL.md.
- https://github.com/leanprover-community/batteries (git tags) — confirmed `v4.36.0` tag exists and resolves via `lake update`.
