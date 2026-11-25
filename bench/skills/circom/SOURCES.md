# Sources

## Official documentation and release notes
- https://github.com/iden3/circom/blob/master/RELEASES.md — release notes for 2.1.0 through 2.2.3. Used for the `--O1` default (2.2.0), buses (2.2.0), the removal of `--constraint_assert_dissabled` and the new `--sanity_check` (2.2.3), and inline arrays of buses and anonymous components (2.2.3).
- https://docs.circom.io/ (the mkdocs sources in the local circom checkout, `mkdocs/docs/`) — signals, tags, buses, anonymous components and tuples, templates, control flow, unknowns, scoping, data types, pragma, include, functions, main component, and the `--inspect`, assert, log and compilation-options pages. Used for the language rules, the CA01/CA02 fixes and the sanity_check levels.
- https://docs.circom.io/getting-started/proving-circuits/ — the snarkjs Groth16 ceremony and prove/verify commands, plus Solidity verifier export.
- `circom --help` (installed 2.2.3) — the exact flag names and their defaults.

## Libraries and tooling
- https://github.com/iden3/circomlib (npm 2.0.5; source read in `node_modules/circomlib/circuits`) — template names, signatures and IO signal names, and the `LessThan` `assert(n <= 252)`.
- https://github.com/iden3/circomlib/commits/master — confirms that the npm 2.0.5 package lags the repo (commits from 2024 to 2026).
- https://github.com/iden3/snarkjs (README for 0.7.6) — CLI commands, PLONK flow and the Hermez ptau download table.
- https://github.com/iden3/circom_tester (0.0.24 source) — `wasm_tester` options (`include`, `templateName`, `templateParams`, `templatePublicSignals`, `O`, `recompile`) and the `calculateWitness`, `checkConstraints` and `assertOut` methods.
- https://github.com/erhant/circomkit (0.4.0 README) — `circomkit.json` and `circuits.json` format, the CLI, the WitnessTester and ProofTester APIs, and the conventional project layout.
- https://github.com/trailofbits/circomspect and https://github.com/trailofbits/circomspect/blob/main/doc/analysis_passes.md — the static analyzer, its install command, and its list of analysis passes.

## Security and style guidance
- https://blog.zksecurity.xyz/posts/circom-pitfalls-1.md — `assert` adds no constraints, `<--` hints must be constrained, the IsZero subtlety, and `Num2Bits(254)` aliasing with its `_strict` fix.
- https://blog.zksecurity.xyz/posts/circom-pitfalls-2.md — unconstrained component outputs and inputs (circomlib `AND` booleanity), and signed comparison semantics.
- https://blog.zksecurity.xyz/posts/circom-auditor.md and https://github.com/zksecurity/zk-skills (circom-auditor SKILL.md, attack-vectors/*.md) — a published agent skill. Used for its checklist: comparator inputs need range checks, comparator outputs must be consumed, divisors must be nonzero, accumulators overflow, and byte packing needs range checks.
- https://hacken.io/discover/circom-security-pitfalls/ — underconstrained circuits and division-by-zero bugs found in audits.
- https://www.rareskills.io/post/circom-tutorial — practitioner workflow: compile and inspect, witness layout, splitting non-quadratic products, and the IsZero, Num2Bits and LessThan idioms.
- https://blog.trailofbits.com/2024/01/02/tag-youre-it-signal-tagging-in-circom/ — tags are promises that the issuing template must enforce.
- https://claudskills.com/skills/circom-dev/SKILL.md — a community circom-dev agent skill. It agrees on defaulting to `<==`, constraining every `<--`, range checks, wasm_tester tests, and running circomspect.
- https://skills.sh/hairyf/blockchain-skills/circom — a community circom skill (topic coverage only). It confirmed the same core topics: signals, constraints, main, pragma and `-l`.

## Verified locally (scratch builds, since deleted)
- Every SKILL.md code block was compiled with circom 2.2.3. The witnesses were generated and checked with `snarkjs wtns check`.
- The Groth16 and PLONK setup/prove/verify flows were run end to end.
- The circom_tester and circomkit tests passed.
- Each listed error code was reproduced.
- Also confirmed:
  - `-o` requires an existing directory.
  - snarkjs `wtns calculate`/`fullprove` reject nested bus JSON.
  - The `--c`/`--no_asm` C++ build fails on macOS arm64 with Homebrew GMP.
