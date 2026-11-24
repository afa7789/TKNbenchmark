# token — a fungible token with allowances

Write a contract named **`Token`**. `build.sh` must write `out/Token.json` with its ABI and creation
bytecode.

Constructor: `constructor(uint256 initialSupply)` mints `initialSupply` to the deployer and emits
`Transfer(address(0), deployer, initialSupply)`.

| Function | Behaviour |
|---|---|
| `name() returns (string)` | `"Bench Token"` |
| `symbol() returns (string)` | `"BTK"` |
| `decimals() returns (uint8)` | `18` |
| `totalSupply() returns (uint256)` | total minted |
| `balanceOf(address) returns (uint256)` | balance |
| `transfer(address to, uint256 amount) returns (bool)` | moves `amount` from the caller to `to`; returns `true` |
| `approve(address spender, uint256 amount) returns (bool)` | sets the allowance (overwrites); returns `true` |
| `allowance(address owner, address spender) returns (uint256)` | current allowance |
| `transferFrom(address from, address to, uint256 amount) returns (bool)` | moves `amount` from `from` to `to` using the caller's allowance, which decreases by `amount`; returns `true` |

Events, with exactly these signatures:

- `Transfer(address indexed from, address indexed to, uint256 value)` on every transfer (also on
  zero-value transfers);
- `Approval(address indexed owner, address indexed spender, uint256 value)` on every `approve`.

Rules:

- A transfer of more than the sender's balance reverts. A `transferFrom` above the allowance reverts.
- Transfers to the zero address revert; `approve` to the zero address reverts.
- An allowance of `type(uint256).max` is infinite: `transferFrom` does not decrease it.
- Reverted calls change nothing.
