---
name: circom
description: "Version-correct, idiomatic Circom for the installed toolchain (circom compiler 2.2.3): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Circom code."
---

# Circom 2.2.3

- Start files with `pragma circom 2.2.3;` (it does not gate features; a newer version is error P1003).
- Since 2.2.0 the default is `--O1` (it was `--O2`), and buses exist.
- 2.2.3 removed `--constraint_assert_dissabled`. Use `--sanity_check 0` (levels 0–3, default 2).

## Build
Layout: `circuits/*.circom` (templates, no main), `circuits/main/*.circom` (one main each), `test/`, `inputs/`, `build/`.
```sh
npm i -D circomlib snarkjs circom_tester mocha  # or circomkit
mkdir -p build    # -o must exist, else "invalid output path", exit 1
circom circuits/main/c.circom --r1cs --wasm --sym -l node_modules -o build --inspect
node build/c_js/generate_witness.js build/c_js/c.wasm input.json build/c.wtns
npx snarkjs wtns check build/c.r1cs build/c.wtns
```
- Include libraries as `include "circomlib/circuits/bitify.circom";` with `-l node_modules`.
- Constraint counts print only with `--r1cs`. Use `--O2` for release Groth16 (one example went from 625 to 341 constraints) and `--O0` to debug.
- macOS arm64: `--c` builds (even with `--no_asm`) fail against Homebrew GMP (`no matching function for call to '__gmpn_add_n'`). Use WASM; build C++ on Linux x86_64.

**Input JSON** uses the main input names only:
- Values: numbers, decimal strings (required above 2^53), `"0x.."`, or `"-1"` (becomes p−1).
- Missing input: `Not all inputs have been set`. Extra key: `Too many values for input signal`.
- Bus inputs: snarkjs `wtns calculate`/`fullprove` reject nested `{"pt":{"x":..}}` (`Not enough values for input signal pt`); pass a flat array in declaration order (`"pt":["2","7"]`).

**Groth16.** `public.json` = outputs (declaration order), then public inputs. ptau: `storage.googleapis.com/zkevm/ptau/powersOfTau28_hez_final_NN.ptau`.
```sh
npx snarkjs groth16 setup build/c.r1cs ptau/p.ptau c0.zkey
npx snarkjs zkey contribute c0.zkey c.zkey --name=1 -e="entropy"
npx snarkjs zkey export verificationkey c.zkey vk.json
npx snarkjs groth16 fullprove input.json build/c_js/c.wasm c.zkey proof.json public.json
npx snarkjs groth16 verify vk.json public.json proof.json
npx snarkjs zkey export solidityverifier c.zkey Verifier.sol  # Groth16Verifier
```
- PLONK: `plonk setup` (no contribute step), then `plonk fullprove` and `plonk verify`.
- `circuit too big for this power of tau ceremony`: use a larger ptau.

## Syntax (verified)
```circom
pragma circom 2.2.3;
include "circomlib/circuits/comparators.circom";
include "circomlib/circuits/bitify.circom";
bus Point() { signal x; signal y; }
template Bin() { signal input x; signal output {binary} y; x*(x-1) === 0; y <== x; }
template Scale() { input Point() p; signal input k; output Point() q; signal output s;
    q.x <== p.x*k; q.y <== p.y*k; s <== p.x + p.y; }
template Main(n) {
    input signal a, b;                 // same as signal input a, b;
    input Point() pt;                  // `signal input Point() pt` = parse error
    signal input bits[2];
    output Point() o; signal output s, lt, w;
    _ <== Num2Bits(n)(a); _ <== Num2Bits(n)(b);  // range check, discard out
    lt <== LessThan(n)([a, b]);
    signal eq <== IsEqual()(in <== [a, b]);      // named inputs: all or none
    (o, s) <== Scale()(pt, a);                   // tuple for multi-output
    w <== Bits2Num(2)([Bin()(bits[0]), Bin()(bits[1])]); // 2.2.3: anon in arrays
    if (n > 8) { signal t <== a*b; _ <== t; }    // OK: known condition
}
component main {public [a]} = Main(32);
```
- **Anonymous components:** they allow only `<==`, `==>` or `=`; `<--` is TAC01. A bare `T()(x);` with outputs is TAC02, so write `_ <== T()(x);`.
- **Loops:** no `signal`/`component` declarations inside `for`/`while` (T2011). Declare `signal e[n]; component c[n];` before it, assign `c[i] = T();` inside. Anonymous components are fine.
- **`main`:** `public [...]` lists inputs only (T2008); main inputs cannot be tagged (T2051); outputs are always public.
- **Tags:** the compiler checks only that a tag is present; the issuer must enforce it. A valued tag is set with `out.maxbit = n;` before `out` is assigned.
- **`var` arrays** need a size: `var z[3] = [1,2,3];`.
- **Functions** can't touch signals; every path must `return` (T2015).

## Soundness rules
- **Pin every `<--` with constraints that make it unique.** Use `<==` when quadratic (`--inspect` warns T3002). Division by a constant is linear: `o <== a / 4;`.
  ```circom
  q <-- a \ k;  r <-- a % k;  a === q*k + r;
  _ <== Num2Bits(m)(q);  lt <== LessThan(m)([r, k]);  lt === 1;
  ```
- **`assert` on a signal adds no constraint.** Use it only for template parameters.
- **`LessThan(n)` family:** `n <= 252`; range-check both inputs with `Num2Bits(n)` first; consume `out` (`lt === 1;`). `<`/`>` on signals are witness-only and signed (values above p/2 are negative).
- **Aliasing:** `Num2Bits(254)` and `Bits2Num(254)` accept both x and x+p. Use `Num2Bits_strict()` or `Bits2Num_strict()`, which are BN254 only.
- **Boolean inputs:** `AND`, `OR`, `XOR`, `Mux*` and `Multiplexer.sel` assume 0/1 inputs without checking. Add `s*(s-1) === 0`.
- **No branching on signals:** an `if` on a signal is T2005 and a signal-valued index is T20462. Select with `out <== s*(a-b) + b;`, or for an unknown index:
  ```circom
  signal eq[n]; signal prod[n]; var acc = 0; var hits = 0;
  for (var i = 0; i < n; i++) {
      eq[i] <== IsEqual()([idx, i]); prod[i] <== eq[i]*arr[i];
      acc += prod[i]; hits += eq[i];
  }
  hits === 1; out <== acc;
  ```
- `a*b*c` needs `signal t <== a*b; o <== t*c;`.
- **Divide by a signal:** `inv <-- 1/x; inv*x === 1;` (forces x≠0; else `IsZero`).
- **Overflow:** sums wrap mod p; keep total width under ~250 bits and range-check every limb/byte.
- **Unused signals:** `--inspect` reports CA01 for a signal used in no constraint and CA02 for unused subcomponent outputs. Mark intentional cases with `_ <== c.out;`.
- **Hashing:** prefer `Poseidon(n)` (`inputs[n]`→`out`) over `Sha256` (~30k constraints/block).

## Errors → fix
- `Non quadratic constraints are not allowed!`: split with intermediate signals. `%`, `\`, `/signal`, `?:` need `<--` + constraints. Also caused by a `var` set under a signal-dependent `if`.
- T2054 `operator =` on a signal: use `<==`. T2005 unknown condition: branchless math or `Mux1`.
- T20461 `component instantiation must be resolved`: params must be compile-time.
- `not all its inputs initialized`: assign every input before reading `.out`.
- `Exception caused by invalid assignment`: signal or component assigned twice, or you assigned your own input.
- `missing tags`: route through a tag-issuing template. T2046: only subcomponent inputs/outputs are visible.
- Runtime `Assert Failed. Error in template X line: N`: a `===` or assert failed for these inputs.

## circomlib 2.0.5
`bitify`: `Num2Bits(n)` in→out[n], `Bits2Num(n)`. `comparators`: `IsZero()` in→out, `IsEqual()` and `LessThan`/`LessEqThan`/`GreaterThan`/`GreaterEqThan(n)` in[2]→out, `ForceEqualIfEnabled()` (enabled, in[2]). `gates`: `AND`/`OR`/`XOR` (a, b→out), `NOT`. `mux1`: `Mux1()` (c[2], s→out). `multiplexer`: `Multiplexer(wIn, nIn)` (inp[nIn][wIn], sel→out[wIn]). `switcher`: `Switcher()` (sel, L, R→outL, outR). `poseidon`: `Poseidon(n)`.

## Testing
```js
const { wasm: wasm_tester } = require("circom_tester");
const c = await wasm_tester("circuits/lib.circom", { include: ["node_modules"],
  templateName: "RangeMul", templateParams: [8], templatePublicSignals: ["a"] }); // no main
const w = await c.calculateWitness({ a: 3, b: 4 }, true);
await c.checkConstraints(w); await c.assertOut(w, { c: 12 });
await assert.rejects(c.calculateWitness({ a: 256, b: 4 }, true));
```
- **circomkit:** `await new Circomkit({include:["./node_modules"], version:"2.2.3"}).WitnessTester(name, {file, template, params})`, then `expectPass(in, out)`, `expectFail(in)` and `expectConstraintCount(n, true)`.
- **Test** 0, p−1, 2^n−1, 2^n and pin constraint counts. Run `circomspect circuits/` (`cargo install circomspect`) before release.
