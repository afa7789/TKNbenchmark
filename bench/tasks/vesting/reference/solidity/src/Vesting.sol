// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Vesting {
    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable duration;
    uint256 public released;

    event Released(uint256 amount);

    constructor(address beneficiary_, uint64 start_, uint64 duration_) payable {
        require(beneficiary_ != address(0), "zero beneficiary");
        require(duration_ > 0, "zero duration");
        beneficiary = beneficiary_;
        start = start_;
        duration = duration_;
    }

    receive() external payable {}

    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        uint256 total = address(this).balance + released;
        if (timestamp < start) return 0;
        if (timestamp >= start + duration) return total;
        return (total * (timestamp - start)) / duration;
    }

    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    function release() external {
        uint256 amount = releasable();
        require(amount > 0, "nothing to release");
        released += amount;
        emit Released(amount);
        (bool ok, ) = beneficiary.call{value: amount}("");
        require(ok, "transfer failed");
    }
}
