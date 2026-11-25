# Sources

Official (Noir v1.0.0 tag, matches installed `noirc 1.0.0+275d3ab1`)
- https://github.com/noir-lang/noir/blob/v1.0.0/CHANGELOG.md — breaking changes from beta.0 to 1.0.0: slices renamed to vectors, `as_slice` removed, removed std hashes/Vec/U128/HashMap, u1/i1 removed, `pub` and visibility now hard errors, signed-to-Field cast banned, u32 indexing required.
- https://github.com/noir-lang/noir/releases/tag/v1.0.0 — confirms 1.0.0 is the final release after rc.7.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/migrating_from_rc0.md — stricter trait solver errors (overlapping impls, ambiguous inherent methods, exact numeric-generic division), noirup bundle change, `nargo fmt` changes.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/getting_started_manually.md — new/check/execute workflow and the `bb prove` / `bb verify` commands.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/language/data_types/vectors.mdx — `[T]` vector type, `@[..]` literal, vector methods.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/language/data_types/integers.md — literal defaulting rules (Field vs u32), suffixes, overflow errors, Wrapping traits.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/language/unconstrained.md — `unsafe` + `// Safety:` requirement, under-constrained and Brillig-constraint checks.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/tooling/tests.md — `#[test]`, `should_fail_with` substring match, fuzz tests with parameters, `--coverage`, `OracleMock`.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/project_structure/workspaces.md and dependencies.md — workspace `members`/`default-member`, git/path deps, `nargo add`.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/libraries/standard_library/cryptographic_primitives/hashes.mdx — which hashes stay in std and which moved to external libraries.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/libraries/standard_library/containers/uhashmap.md — UHashMap is unconstrained-only and takes the Poseidon2Hasher from the external poseidon lib.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/libraries/standard_library/recursion.mdx — `verify_proof_with_type` signature; recommends Barretenberg's `bb_proof_verification` library.
- https://github.com/noir-lang/noir/blob/v1.0.0/docs/docs/guides/thinking_in_circuits.md — Rust-to-Noir differences (no `&&`, `global` not `const`, no early return) and Field-to-int truncation.
- https://github.com/noir-lang/noir/tree/v1.0.0/noir_stdlib/src — exact stdlib signatures (BoundedVec `&self` methods, Field byte/bit methods, ecdsa, hash module, `FunctionParameter`).
- https://github.com/noir-lang/noir/blob/v1.0.0/scripts/install_bb.sh — bb 6.0.0 is the version pinned for Noir 1.0.0.
- https://github.com/noir-lang/noir/blob/v1.0.0/EXTERNAL_NOIR_LIBRARIES.yml — the official external libraries (poseidon, sha256, keccak256, bignum, ...).

Agent rules and skills published by Noir developers
- https://github.com/noir-lang/noir/blob/v1.0.0/.claude/skills/noir-idioms/SKILL.md — official idioms: hint-and-verify, ACIR vs Brillig costs, if/else selects, hoisting asserts, `assert_eq`, `is_unconstrained()`.
- https://github.com/noir-lang/noir/blob/v1.0.0/.claude/skills/noir-optimize-acir/SKILL.md — measurement loop with `bb gates`, `#[export]` + `nargo export` for libraries, what not to optimize.
- https://github.com/critesjosh/noir-claude-plugin — community Claude Code plugin (CLAUDE.md, noir-developer, review-circuit, noir-testing): soundness checklist and external Poseidon2 usage. Its `pub y: Field` param syntax is wrong in 1.0 (checked).
- https://docs.aztec.network/developers/ai_tooling — Aztec's AI tooling page: links the Noir skills/MCP, recommends Poseidon2 over Pedersen.

Libraries and ecosystem
- https://github.com/noir-lang/poseidon (tag v0.4.0) — `Poseidon2::hash(input, message_size)`, `Poseidon2Hasher`.
- https://github.com/noir-lang/sha256 (tag v0.3.0) — `digest`, `sha256_var` API.
- https://github.com/noir-lang/keccak256 (tag v0.1.3) — `keccak256(input, message_size)`; README still shows legacy `dep::`, which fails on 1.0.0.
- https://github.com/oak-security/noir-ctf-challenges/pull/4 — real-world 1.0 port: beta.22 to 1.0.0, bb 6.0.0, `FunctionDefinition::parameters()` now returns `FunctionParameter`.
- https://raw.githubusercontent.com/AztecProtocol/aztec-packages/refs/heads/next/barretenberg/bbup/install — bbup installer; bb 6.0.0 CLI (`prove`, `verify`, `gates`, `write_vk`, `write_solidity_verifier`, `-t` targets) checked from its `--help`.

Verification: the commands, flags, APIs and error messages in SKILL.md were run against nargo 1.0.0 and bb 6.0.0 in scratch projects, deleted afterwards. The one exception is the `bb_proof_verification` recommendation, which comes from the recursion docs and was not run.
