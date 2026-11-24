# vesting — linear vesting of ether

Write a contract named **`Vesting`**. `build.sh` must write `out/Vesting.json` with its ABI and
creation bytecode.

Constructor: `constructor(address beneficiary, uint64 start, uint64 duration)`, payable. It holds
ether and releases it to `beneficiary` linearly between `start` and `start + duration` (timestamps in
seconds). `beneficiary` must not be the zero address and `duration` must be positive, otherwise the
deployment reverts.

| Function | Behaviour |
|---|---|
| `beneficiary() returns (address)`, `start() returns (uint64)`, `duration() returns (uint64)` | the constructor values |
| `released() returns (uint256)` | ether released so far |
| `vestedAmount(uint64 timestamp) returns (uint256)` | with `total = address(this).balance + released()`: `0` before `start`; `total` at or after `start + duration`; otherwise `total * (timestamp - start) / duration`, rounded down |
| `releasable() returns (uint256)` | `vestedAmount(block.timestamp) - released()` |
| `release()` | sends `releasable()` to the beneficiary and emits `Released(uint256 amount)`; reverts if nothing is releasable. Anyone may call it. |

The contract also accepts plain ether transfers (`receive`), which add to the vesting total.

Event: `Released(uint256 amount)`.
