---
name: solidity
description: "Version-correct, idiomatic Solidity for the installed toolchain (forge Version: 1.7.1): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Solidity code."
---

# Solidity 0.8.39 + Foundry 1.7.1

Verified: forge 1.7.1, solc 0.8.39, forge-std v1.17.0, OZ v5.7.0. Default EVM `osaka`; set `evm_version` for lagging chains.

## Setup
```sh
forge init app && cd app        # adds forge-std, CI, foundry.lock
forge install OpenZeppelin/openzeppelin-contracts@v5.7.0 # not --shallow (tag lookup fails)
forge remappings                # @openzeppelin/contracts/ is auto-detected
```
`foundry.toml`:
```toml
[profile.default]
solc = "0.8.39"
optimizer = true          # OFF by default since Foundry 1.0
optimizer_runs = 200
deny = "warnings"         # was deny_warnings; never|warnings|notes
ignored_warnings_from = ["lib"]   # OZ 5.7 itself warns ("at" keyword)
[fuzz]
runs = 1000
seed = "0x1"              # random by default since 1.7
[rpc_endpoints]
mainnet = "${MAINNET_RPC_URL}"
[etherscan]
mainnet = { key = "${ETHERSCAN_API_KEY}" }
[profile.ci.fuzz]
runs = 10000   # FOUNDRY_PROFILE=ci forge test
```
Layout: `src/X.sol`, `test/X.t.sol`, `script/X.s.sol`. Pin `pragma solidity 0.8.39;` in apps (`^0.8.24` in libraries). Use named imports only: `import {ERC20} from "...";`.

## Toolchain traps
- forge **hides** solc's `send`/`transfer` deprecation and 24 KiB code-size warnings by default. Check sizes with `forge build --sizes`.
- `forge build` also lints. The 1.7.1 linter fails (`unresolved symbol erc7201`) on `erc7201(...)` in a `constant`, though solc accepts it. Use it inline in `layout at`, or hardcode the slot from `cast index-erc7201 ns`.
- `testFail*` was removed; use `test_RevertWhen_*` with `vm.expectRevert`.
- `vm.expectRevert` only matches the next **external** call. An internal or library revert fails with `call didn't revert at a lower depth than cheatcode call depth`. Go through a contract, or annotate the test with `/// forge-config: default.allow_internal_expect_revert = true`.
- `forge create` only dry-runs without `--broadcast`. `forge coverage` disables the optimizer and via-IR (`--ir-minimum` on stack-too-deep).
- Truncating casts (`uint128(x)`, `bytes4(data)`) trigger the `unsafe-typecast` lint; use `SafeCast`, or suppress with `// forge-lint: disable-next-line(unsafe-typecast)`.

## Language (0.8.24–0.8.39)
```solidity
contract Vault layout at erc7201("example.storage.Vault") { // 0.8.29+; erc7201 builtin 0.8.35+
    error InsufficientBalance(uint256 available, uint256 required);
    event Withdrawn(address indexed account, uint256 amount);
    mapping(address account => uint256) public balanceOf;     // named mapping params
    bool transient locked;                                    // value types only (EIP-1153)
    error Reentrancy();
    error TransferFailed();

    modifier nonReentrant() {
        require(!locked, Reentrancy());
        locked = true; _; locked = false;
    }
    function deposit() external payable { balanceOf[msg.sender] += msg.value; }

    function withdraw(uint256 amount) external nonReentrant {
        uint256 bal = balanceOf[msg.sender];
        require(bal >= amount, InsufficientBalance(bal, amount)); // custom error in require
        unchecked { balanceOf[msg.sender] = bal - amount; }
        emit Withdrawn(msg.sender, amount);
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
```
- Only the most-derived concrete contract may use `layout at`; on an abstract contract or a base it is error 7587/8894.
- Use the type-checked `abi.encodeCall(IERC20.transfer, (to, amt))`. `abi.encodeError` does not exist; use `abi.encodeWithSelector(E.selector, ...)`.
- Value types with operators: `type Shares is uint128; using {add as +} for Shares global;` (free functions in the same file).
- `emit Other.Ev(...)`, `Err.selector` and `Ev.selector` work. Since 0.8.22 a `for` header's `++i` is unchecked automatically.
- Write `assembly ("memory-safe") {}`; the `/// @solidity memory-safe-assembly` comment is deprecated. Yul on osaka has `clz`, `mcopy`, `tload` and `tstore`.
- **Deprecated, removed in 0.9:** `send`/`transfer` (use `call{value:}` plus a guard or CEI), `virtual` modifiers, `<`/`>` on contract types (cast to `address`), `pragma experimental ABIEncoderV2`, and ABI coder v1. Future keywords, so don't use them as identifiers: `at`, `error`, `layout`, `leave`, `super`, `this`, `transient`.

## OpenZeppelin 5.x (not 4.x)
Pass `Ownable(initialOwner)` in the constructor. Override `_update(from,to,value)` (`_beforeTokenTransfer` is gone). Use `ReentrancyGuardTransient`, `SafeERC20.safeTransfer`/`forceApprove` (no `safeApprove`), `Math.mulDiv(a,b,c,Math.Rounding.Ceil)`, and `ECDSA.recover(MessageHashUtils.toEthSignedMessageHash(h), sig)`. Errors: `Ownable.OwnableUnauthorizedAccount(a)`, and `IERC20Errors.ERC20InsufficientBalance(from,bal,need)` in `interfaces/draft-IERC6093.sol`. In 5.7, `EnumerableSet.pos(i)` replaces `at(i)`. Drop SafeMath.

## Tests
```solidity
import {Test, console} from "forge-std/Test.sol";
contract VaultTest is Test {
    Vault vault; address alice = makeAddr("alice");
    function setUp() public { vault = new Vault(); vm.deal(alice, 100 ether); }
    function test_RevertWhen_Overdraw() public {
        vm.expectRevert(abi.encodeWithSelector(Vault.InsufficientBalance.selector, 0, 1));
        vm.prank(alice);
        vault.withdraw(1);
    }
    function testFuzz_Roundtrip(uint256 amt) public {
        amt = bound(amt, 1, 100 ether);              // bound, not vm.assume
        vm.startPrank(alice);
        vault.deposit{value: amt}(); vault.withdraw(amt);
        vm.stopPrank();
        assertEq(alice.balance, 100 ether);
    }
}
```
Put `vm.expectEmit(address(c)); emit C.Ev(...);` before the call. `vm.expectPartialRevert(E.selector)` matches the selector only. Use `vm.snapshotState`/`revertToState` (`snapshot`/`revertTo` are deprecated). Others: `vm.startSnapshotGas("x")`/`stopSnapshotGas()`, `makeAddrAndKey` with `vm.sign(pk, digest)`, `deal(token, to, amt, true)`, `vm.mockCall`, `vm.expectCall`, `vm.createSelectFork("mainnet")`, `skip`/`vm.warp`/`vm.roll`, `/// forge-config: default.fuzz.runs = 50`. For invariants: call `targetContract(address(handler))` in setUp, write `function invariant_X() public view`, and keep ghost variables in the handler.

`forge test --mt <re> --mc <re> -vvvv`, `--rerun`, `--fuzz-seed`, `--gas-report`; `forge snapshot [--check]`; `forge coverage --report summary|lcov`.

## Deploy
```solidity
contract DeployVault is Script {
    function run() external returns (Vault v) {
        bytes32 salt = vm.envOr("SALT", bytes32(0));
        vm.startBroadcast(); v = new Vault{salt: salt}(); vm.stopBroadcast();
    }
}
```
```sh
cast wallet import deployer --interactive           # keep keys out of .env
forge script script/Deploy.s.sol:DeployVault --rpc-url mainnet --account deployer --sender 0x.. --broadcast --verify
forge verify-contract <addr> src/Vault.sol:Vault --chain mainnet --guess-constructor-args --watch
```
Results land in `broadcast/<script>/<chainid>/run-latest.json`. Cast: `cast call A "f(address)(uint256)" x`, `cast send A "f()" --value 1ether`, `cast sig`, `cast calldata`, `cast decode-error 0x.. --sig "E(uint256)"`, `cast storage`, `forge inspect C storageLayout|errors|methodIdentifiers`.

## Errors → fixes
- `Stack too deep` → use structs or `{}` scopes first; as a last resort, `via_ir = true` with the optimizer on.
- 4327 `needs to specify overridden contracts "A" and "B"` → write `override(A, B)`. Implementing an interface function needs no `override`.
- 6359 `not implicitly convertible` (uint256→uint8, address→address payable) → use `SafeCast`, or `payable(a)`.
- 9429 bad address checksum → use the suggested form.
- 4061 `struct ... only valid in storage` (struct holds a mapping) → use a `storage` reference.
- 6182 calldata is read-only → copy to `memory`.
- 1834 `transient` only works on value types.
- 9302 → check `(bool ok,)` of low-level calls.

Before shipping: run `forge fmt --check && forge build --sizes && forge lint && forge test`.
