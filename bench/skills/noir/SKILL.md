---
name: noir
description: "Version-correct, idiomatic Noir for the installed toolchain (nargo version = 1.0.0): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Noir code."
---

# Noir 1.0.0 (nargo 1.0.0, bb 6.0.0)

Constrained code -> ACIR circuit; `unconstrained` code -> Brillig VM. All below verified on nargo 1.0.0.

## Workflow
```sh
nargo new app            # bin (default); --lib, --contract
nargo check              # type-check; writes Prover.toml stub
nargo execute [wit]      # compile + solve -> target/app.json, target/app.gz; -p Other => Other.toml
nargo test [substr] [--exact] [--show-output]
nargo info               # ACIR/Brillig opcode counts per function
nargo fmt [--check]      # canonical style; run before committing
nargo add --git https://github.com/noir-lang/sha256 --tag v0.3.0   # or --path ../lib
nargo export             # libs: #[export] fns -> export/<fn>.json
```
- `nargo check` skips backend passes: loop-bound errors and Brillig-constraint `bug:` reports only appear in `compile`/`execute`/`test`. Run those before claiming success.
- `nargo compile` on a lib emits nothing; use `#[export]` + `nargo export`.
- CI: `nargo fmt --check && nargo test --deny-warnings`. Never ship with `--skip-underconstrained-check` / `--skip-brillig-constraints-check`.

Prove with Barretenberg (`bbup -v 6.0.0`):
```sh
bb prove -b target/app.json -w target/app.gz --write_vk -o target  # proof, vk, public_inputs
bb verify -p target/proof -k target/vk
bb gates -b target/app.json            # circuit_size = real proving cost
# EVM: same -t on every step
bb write_vk -b target/app.json -o evm -t evm
bb prove -b target/app.json -w target/app.gz -k evm/vk -o evm -t evm
bb write_solidity_verifier -k evm/vk -o evm/Verifier.sol -t evm
```
Other `-t`: `evm-no-zk`, `noir-recursive`, `noir-rollup`, `starknet`.

## Layout / manifest
```
Nargo.toml  Prover.toml  src/main.nr (bin) | src/lib.nr (lib)  src/foo.nr  src/foo/bar.nr
```
```toml
[package]
name = "app"
type = "bin"            # "lib" | "contract"
[dependencies]
poseidon = { git = "https://github.com/noir-lang/poseidon", tag = "v0.4.0" }
mylib = { path = "../mylib" }
```
Workspace: `[workspace] members = ["a","b"]`, `default-member = "a"`; `--workspace`/`--package`. `mod foo;` loads `src/foo.nr`. Import deps by name: `use sha256::digest;`. `dep::` no longer resolves (some READMEs still show it).

Prover.toml: `x = 1` or `"0x02"`; `a = [1, 2]`; struct = `[p]` table; struct array = `[[ps]]`.

## 1.0 changes agents get wrong
- **Slices are now "vectors"**: type `[T]`, literal `@[1, 2]`, `arr.as_vector()`. `as_slice` is gone. Vectors can't be circuit inputs/outputs; prefer `[T; N]` or `BoundedVec<T, N>`.
- **Removed from std** (`Could not resolve ... in path`): `std::hash::{sha256, keccak256, poseidon, poseidon2, mimc, hash_to_field}`, `Vec`, constrained `HashMap` (`collections::map`), `U128` (use `u128`), schnorr, eddsa, `ec`, `merkle`, `bytes32_to_field`, `to_le_radix`, `verify_proof` (use Barretenberg's `bb_proof_verification` lib, which wraps `std::verify_proof_with_type`).
- External libs verified on 1.0.0: `poseidon` v0.4.0, `sha256` v0.3.0, `keccak256` v0.1.3.
```rust
use poseidon::poseidon2::Poseidon2;
let h = Poseidon2::hash([secret, salt], 2);          // (input, message_size)
let d: [u8; 32] = sha256::digest(bytes);              // fixed length
let d2 = sha256::sha256_var(padded, len);            // runtime length <= N
let k = keccak256::keccak256(bytes, bytes.len());    // (input, message_size)
```
- Still in std: `std::hash::{pedersen_hash, pedersen_commitment, blake2s, blake3, poseidon2_permutation, sha256_compression, keccakf1600}`, `std::ecdsa_secp256k1::verify_signature(pk_x: [u8;32], pk_y: [u8;32], sig: [u8;64], msg_hash: [u8;32]) -> bool` (same for `ecdsa_secp256r1`), `std::embedded_curve_ops`, `std::aes128::aes128_encrypt`.
- `UHashMap<K, V, BuildHasherDefault<Poseidon2Hasher>>` (`std::collections::umap`, hasher from `poseidon::poseidon2`) is for unconstrained/comptime only; `insert` returns a value, so write `let _ = m.insert(k, v);`.
- `BoundedVec` (prelude) methods take `&self`/`&mut self`: `new, push, pop, get, get_unchecked, set, len, max_len, storage, from_array, extend_from_array, any, map, for_each`.
- No `u1`/`i1`/`i128`. Only unsigned ints can be cast to `Field`. `enum`/`match` need `-Zenums` (unstable).
- Stricter trait solver: overlapping blanket impls and ambiguous inherent methods (`S<_>` with `impl S<u8>` + `impl S<u16>`) are errors; annotate the receiver type.
- Comptime: `FunctionDefinition::parameters()` returns `[FunctionParameter]`; use `.name()` / `.typ()`, not tuple `.1`.

## Compiler errors -> fix
| Error | Fix |
|---|---|
| `Expected a pattern but found 'pub'` | `fn main(x: pub Field)`; visibility goes on the type |
| `unnecessary pub keyword on parameter` | `pub` only on `main` params/return |
| `Indexing arrays and vectors must be done with u32` | index with `u32` (`i as u32`) |
| `Fields cannot be compared` | cast to an int, or `x.lt(y)` |
| `Integers must have the same bit width` | explicit `as` cast; no implicit widening |
| `Early 'return' is unsupported` (even unconstrained) | single tail expression; `if/else` values |
| `break is only allowed in unconstrained functions` | constrained: loop full bound with a `done` flag |
| `Could not determine loop bound at compile-time` | bound must be a constant/generic `N`; loop `0..N` + `if i < len` |
| `no logical-and (&&)` | `&` / `\|` on `bool` (both sides evaluate) |
| `Expected an item but found 'const'` | `global K: u32 = 3;` (type required) |
| `Mutable variable c captured in lambda must be a mutable reference` | `let r = &mut c; let f = \|v\| { *r += v; };` |
| `Call to unconstrained function ... unsafe` / `Unsafe block must have a safety comment` | `// Safety: <what constrains it>` then `unsafe { f(x) }` |
| `bug: Brillig function call isn't properly covered by a manual constraint` | assert hint outputs against inputs (below) |
| `x is private and not visible` | `pub` on struct fields, fns, methods, and `pub mod` |

Runtime `attempt to add with overflow`: for intended wrapping, `use std::ops::WrappingAdd;` + `x.wrapping_add(y)`. `Field as u8` silently truncates (300 -> 44); range-check with `x.assert_max_bit_size::<8>()` first if needed.

## Idioms
Hint and verify: compute in `unconstrained`, constrain the result in circuit.
```rust
unconstrained fn sqrt_hint(x: u64) -> u64 {
    let mut r: u64 = 0;
    while (r + 1) * (r + 1) <= x { r += 1; }   // dynamic loops fine in Brillig
    r
}
pub fn isqrt(x: u64) -> u64 {
    // Safety: r*r <= x < (r+1)^2 pins r uniquely
    let r = unsafe { sqrt_hint(x) };
    assert(r * r <= x);
    assert(x < (r + 1) * (r + 1));
    r
}
```
- Hint only final results; never hint division/modulo (compiler does).
- ACIR evaluates both `if` branches (predicated). Prefer `let v = if c { a } else { b }; assert_eq(out, v);` over asserts in each branch.
- `Field` is cheapest; ints add range checks; `<` > `==` in cost. Measure with `bb gates`.
- Prefer `assert_eq(a, b, "msg")`; messages can be `f"bad {v}"`.
- Variable length: `BoundedVec<T, MAX>` or `[T; N]` + `len`. Per-target code: `std::runtime::is_unconstrained()`.
- Generics: `struct Buf<let N: u32> { data: [u8; N] }`, `impl<let N: u32> Buf<N>`; call `f::<4>()`.
- Unsuffixed literals default to `Field`, except indices, loop vars, bitwise, comparison, `%`, numeric generics (`u32`). Suffix: `1_u8`, `3u64`.
- Field bytes: `x.to_le_bytes::<32>()`, `Field::from_le_bytes(b)`, `to_be_bits::<N>()`. Arrays: `map, fold, reduce, all, any, sort, sort_via, concat, as_vector`; `"abc".as_bytes()`.
- Compile-time: `global G: u32 = comptime { f(21) };`, `std::static_assert(cond, "msg")`, `#[derive(Eq, Default, Hash)]`.
- `fn inc(x: &mut Field) { *x += 1; }` called as `inc(&mut a)`.

## Tests
```rust
#[test] fn ok() { assert_eq(main(1, 2), 3); }
#[test(should_fail_with = "overflow")]                // substring match
fn bad() { let a: u8 = 255; let _ = a + 1; }
#[test] unconstrained fn fast() { /* Brillig, faster */ }
#[test] fn fuzz(a: u32, b: u32) { /* params => fuzzed */ }
```
Mock oracles with `std::test::OracleMock`.
