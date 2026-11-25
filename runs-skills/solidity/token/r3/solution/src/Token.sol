// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bench Token
/// @notice Fixed-supply ERC-20 token; the entire supply is minted to the deployer.
/// @dev Relies on OpenZeppelin's ERC20 for the spec'd semantics: transfers to and approvals of
///      the zero address revert, a `type(uint256).max` allowance is treated as infinite, and
///      zero-value transfers emit `Transfer`.
contract Token is ERC20 {
    constructor(uint256 initialSupply) ERC20("Bench Token", "BTK") {
        _mint(msg.sender, initialSupply);
    }
}
