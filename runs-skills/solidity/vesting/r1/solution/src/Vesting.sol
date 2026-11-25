// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

/// @title Vesting
/// @notice Holds ether and releases it linearly to a beneficiary between `start` and `start + duration`.
/// @dev Ether sent after deployment (via `receive`) joins the vesting total and follows the same schedule.
contract Vesting {
    /// @notice Emitted when vested ether is sent to the beneficiary.
    event Released(uint256 amount);

    error ZeroBeneficiary();
    error ZeroDuration();
    error NothingToRelease();
    error TransferFailed();

    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable duration;

    /// @notice Total ether released to the beneficiary so far.
    uint256 public released;

    constructor(address beneficiary_, uint64 start_, uint64 duration_) payable {
        require(beneficiary_ != address(0), ZeroBeneficiary());
        require(duration_ != 0, ZeroDuration());
        beneficiary = beneficiary_;
        start = start_;
        duration = duration_;
    }

    receive() external payable {}

    /// @notice Amount of ether vested at `timestamp`, including what has already been released.
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        uint256 total = address(this).balance + released;
        if (timestamp < start) return 0;
        if (uint256(timestamp) >= uint256(start) + duration) return total;
        return (total * (timestamp - start)) / duration;
    }

    /// @notice Amount of ether that can be released right now.
    function releasable() public view returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    /// @notice Sends all currently releasable ether to the beneficiary. Callable by anyone.
    function release() external {
        uint256 amount = releasable();
        require(amount != 0, NothingToRelease());

        released += amount;
        emit Released(amount);

        (bool ok,) = beneficiary.call{value: amount}("");
        require(ok, TransferFailed());
    }
}
