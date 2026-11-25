# Sources

## Official Solidity release notes and docs
- https://www.soliditylang.org/blog/2026/11/19/solidity-0.8.39-release-announcement/ — 0.8.39 is the latest and likely last 0.8.x release; default EVM stays osaka; fixes the recursive-struct storage copy bug; outlines 0.9.0 removals.
- https://www.soliditylang.org/blog/2026/10/22/solidity-0.8.38-release-announcement/ — Yul optimizer stale-knowledge miscompilation fix (0.8.19–0.8.37); `swapn`/`dupn`/`exchange` Yul identifier warnings.
- https://www.soliditylang.org/blog/2026/09/10/solidity-0.8.37-release-announcement/ — `pragma experimental ABIEncoderV2` and pre-Constantinople EVM versions deprecated; `--lsp` removed; `block.slotnum` (Amsterdam only).
- https://www.soliditylang.org/blog/2026/07/09/solidity-0.8.36-release-announcement/ — EOF backend removed; Amsterdam EVM support; SSA CFG spilling (experimental).
- https://www.soliditylang.org/blog/2026/04/29/solidity-0.8.35-release-announcement/ — `erc7201()` comptime builtin; `--experimental` gate; `at`/`error`/`layout`/`leave`/`super`/`this`/`transient` will become keywords.
- https://www.soliditylang.org/blog/2026/02/18/solidity-0.8.34-release-announcement/ — via-IR transient/persistent `delete` collision bug (0.8.28–0.8.33).
- https://www.soliditylang.org/blog/2025/12/18/solidity-0.8.32-0.8.33-release-announcement/ — storage array bugfix; skip 0.8.32 and use 0.8.33+.
- https://www.soliditylang.org/blog/2025/12/03/solidity-0.8.31-release-announcement/ — osaka default; `clz`; constants in `layout at`; deprecations of send/transfer, virtual modifiers, contract comparison and memory-safe-assembly NatSpec.
- https://www.soliditylang.org/blog/2025/03/12/solidity-0.8.29-release-announcement/ — custom storage layout `contract C layout at <expr>` and its restrictions.
- https://www.soliditylang.org/blog/category/releases/ — release timeline: 0.8.28 transient state vars, 0.8.30 prague default.
- https://docs.soliditylang.org/en/latest/style-guide.html — official style guide: file and contract ordering, function ordering, modifier order, naming conventions, NatSpec.

## Foundry
- https://newreleases.io/project/github/foundry-rs/foundry/release/v1.7.0 — Foundry 1.7 changes: osaka default, random fuzz seed, unresolved imports now fail, invariant assert reporting, new cheatcodes and config keys.
- https://newreleases.io/project/github/foundry-rs/foundry/release/v1.7.1 — 1.7.1 is a patch release with cherry-picked fixes.
- https://www.getfoundry.sh/guides/migrations/foundry-v1 — v1 breaking changes: optimizer off by default, `testFail` removed, expectRevert no longer covers internal calls, removed CLI commands.
- https://getfoundry.sh/best-practices — test naming (`test_`, `testFuzz_`, `test_RevertWhen_`), `bound` over `assume`, named imports, script and env conventions, keystores, `forge lint`/`fmt --check`.
- https://getfoundry.sh/llms.txt — index of Foundry docs pages (testing, cheatcodes, scripting, config).
- https://newreleases.io/project/github/foundry-rs/forge-std/release/v1.14.0 — forge-std requires `^0.8.13` from v1.14.

## OpenZeppelin
- https://www.openzeppelin.com/news/introducing-openzeppelin-contract-5-7 — OZ 5.7 features; `at` deprecated in favour of `pos` in EnumerableSet/Map, Checkpoints and DoubleEndedQueue; renamed ERC-4337 files.
- https://github.com/OpenZeppelin/openzeppelin-contracts/releases — confirmed v5.7.0 is the latest tag (checked with `git ls-remote`).

## Community agent rules and skills
- https://github.com/0xlayerghost/solidity-agent-kit — agent skill kit: custom errors, NatSpec, fuzz and invariant tests, pre-deploy checklists.
- https://www.skills.sh/whackur/solidity-agent-toolkit/solidity-foundry-development — Foundry skill: setUp/test naming, prefer expectRevert over testFail, remappings in foundry.toml.
- https://codex.danielvaughan.com/2026/05/23/codex-cli-solidity-smart-contract-development-foundry-mcp-security-audit-workflows/ — sample AGENTS.md: pinned pragma, named imports, custom errors, CEI, OZ v5 not v4, no SafeMath, human-gated deploys.
- https://github.com/defi-wonderland/solidity-foundry-boilerplate — reference Foundry project layout (unit, fuzz and fork tests, scripts).

## Local verification (installed toolchain)
- forge/cast/anvil 1.7.1 with solc 0.8.39 (downloaded by forge), forge-std v1.17.0 and OZ v5.7.0. I compiled and ran every snippet in SKILL.md, plus the error messages, lint behaviour, default `ignored_error_codes`, config keys, CLI flags and the anvil deploy, call and send flow.
