// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bench Token
/// @notice Fixed-supply ERC-20 token; the entire supply is minted to the deployer.
/// @dev Relies on OpenZeppelin's ERC20, which already provides:
///      - reverts on insufficient balance / allowance (ERC-6093 errors),
///      - reverts on transfers to, and approvals for, the zero address,
///      - infinite allowance semantics for `type(uint256).max`,
///      - `Transfer` events for every transfer, including zero-value ones.
contract Token is ERC20 {
    /// @param initialSupply Amount of tokens (in base units) minted to the deployer.
    constructor(uint256 initialSupply) ERC20("Bench Token", "BTK") {
        _mint(msg.sender, initialSupply);
    }
}
