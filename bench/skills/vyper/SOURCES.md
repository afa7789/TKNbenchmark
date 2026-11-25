# Sources

## Web
- https://docs.vyperlang.org/en/v0.4.3/release-notes.html — Breaking changes in 0.4.0 through 0.4.3: `@deploy`, extcall/staticcall, `//`, `flag`, `ethereum.ercs`, the `math.sqrt` move, the nonreentrancy pragma, `raw_create`, `@raw_return`, prague as the default EVM, and `-W` flags.
- https://docs.vyperlang.org/en/v0.4.3/using-modules.html — Module system: `uses`, `initializes`, `exports`, `__interface__`, `__at__`, `:=` dependency wiring, and the `__init__` ordering rules.
- https://docs.vyperlang.org/en/v0.4.3/interfaces.html — extcall/staticcall rules, the `default_return_value`, `skip_contract_check`, `value` and `gas` kwargs, `.vyi` files, built-in ERC interfaces, and `-f interface`/`external_interface`.
- https://docs.vyperlang.org/en/v0.4.3/control-structures.html — Decorators, `@raw_return`, `__default__`, the nonreentrancy pragma with `@reentrant`, and `range(..., bound=N)`. Its `raw_return` example turned out not to compile.
- https://docs.vyperlang.org/en/v0.4.3/built-in-functions.html — Builtin signatures for `raw_call`, `abi_encode`/`abi_decode`, the create builtins, `method_id`, `isqrt`, `pow_mod256` and the `unsafe_*` family.
- https://docs.vyperlang.org/en/stable/style-guide.html — Confirmed that the official style guide covers only the compiler's Python code, so contract conventions came from snekmate, Curve and natrix.
- https://docs.vyperlang.org/en/stable/natspec.html — NatSpec rules: `@param` names must match real arguments, and internal docstrings are not parsed.
- https://curve.readthedocs.io/guide-code-style.html — Curve's naming conventions: snake_case storage, CapWords events, structs and interfaces, and `# dev:` revert comments.
- https://docs.curve.finance/developer/resources/curve-practices — Ownership patterns, and the recommendation to use snekmate's ownable modules.
- https://raw.githubusercontent.com/pcaversaccio/snekmate/main/src/snekmate/tokens/erc20.vy — Production module style: `uses` and `initializes`, explicit `exports`, `unsafe_sub` after a balance check, keyword-argument `log`, and natspec.
- https://etherscan.io/token/0x01791F726B4103694969820be083196cC7c045fF — A deployed contract that wires snekmate's ownable and erc20 modules together.
- https://pypi.org/pypi/snekmate/json — Showed that snekmate 0.1.2 is the latest PyPI release and pins `~=0.4.3`.
- https://raw.githubusercontent.com/vyperlang/titanoboa/master/README.md — Titanoboa API: `load`, `load_partial`, `reverts`, `env.prank`, `fork` and `eval`.
- https://docs.vyperlang.org/en/latest/testing-contracts.html — Titanoboa and Moccasin are the recommended testing tools.
- https://cyfrin.github.io/moccasin/ and https://cyfrin.github.io/moccasin/quickstart.html — Moccasin commands (`mox init/compile/test/run/install`) and its project layout.
- https://raw.githubusercontent.com/Cyfrin/moccasin/main/README.md — Install with `uv tool install moccasin`.
- https://cyfrin.github.io/moccasin/core_concepts/testing/titanoboa_testing.html — Moccasin tests are plain Titanoboa and pytest.
- https://raw.githubusercontent.com/AlbertoCentonze/natrix/main/README.md and https://albertocentonze.github.io/natrix/rules/constant-naming — The natrix linter's install, usage and rules.
- https://clawhub.ai/skills/vyper — The only published Vyper agent skill I found. It is generic and has no usable version-specific content.

## Verified locally (vyper 0.4.3+commit.bff19ea2, titanoboa 0.2.8, moccasin 0.4.4, natrix, snekmate 0.1.2)
- Installed compiler source (`vyper/ast/pre_parser.py`, `vyper/builtins/stdlib/math.vy`, `vyper/builtins/interfaces/*.vyi`, `vyper --help`) — Pragma names, the `math` stdlib, built-in interfaces, and the CLI flags and output formats.
- Scratch contracts compiled with `vyper` — Every snippet and every error message in SKILL.md, plus the deprecation warnings that `-W error` turns into failures.
- Scratch pytest suites under Titanoboa — `boa.load/loads/load_partial/deploy_as_blueprint/at`, `prank`, `reverts(reason|dev=)`, `get_logs`, `time_travel`, `boa.test.strategy`, and the runtime revert from the reentrancy lock.
- `mox init`, `mox install snekmate==0.1.2`, `mox compile`, `mox test` and `mox lint`, plus the source of natrix's ModifiersOrdering rule (decorator order is visibility, then mutability, then security).
