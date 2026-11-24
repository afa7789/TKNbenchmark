// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bench Token
/// @notice Fixed-supply ERC-20 token; the entire supply is minted to the deployer.
/// @dev Relies on OpenZeppelin's ERC20, which reverts on insufficient balance or
///      allowance, rejects the zero address as recipient/spender, treats an
///      allowance of `type(uint256).max` as infinite, and emits `Transfer` on
///      every transfer (including zero-value ones).
contract Token is ERC20 {
    constructor(uint256 initialSupply) ERC20("Bench Token", "BTK") {
        _mint(msg.sender, initialSupply);
    }
}
