// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Bench Token
/// @notice Fixed-supply ERC-20 token; the entire supply is minted to the deployer.
contract Token is ERC20 {
    constructor(uint256 initialSupply) ERC20("Bench Token", "BTK") {
        _mint(msg.sender, initialSupply);
    }
}
