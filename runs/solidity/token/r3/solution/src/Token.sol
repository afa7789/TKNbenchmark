// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bench Token
/// @notice Fixed-supply ERC-20 token; the entire supply is minted to the deployer.
/// @dev An allowance of `type(uint256).max` is treated as infinite by OpenZeppelin's ERC20.
contract Token is ERC20 {
    /// @param initialSupply Amount of tokens (in base units) minted to the deployer.
    constructor(uint256 initialSupply) ERC20("Bench Token", "BTK") {
        _mint(msg.sender, initialSupply);
    }
}
