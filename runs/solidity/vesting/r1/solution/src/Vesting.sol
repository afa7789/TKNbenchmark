// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Vesting
/// @notice Holds ether and releases it linearly to a fixed beneficiary between
///         `start` and `start + duration`.
contract Vesting {
    /// @notice Emitted when ether is released to the beneficiary.
    event Released(uint256 amount);

    error ZeroBeneficiary();
    error ZeroDuration();
    error NothingToRelease();
    error TransferFailed();

    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable duration;

    /// @notice Total ether released so far.
    uint256 public released;

    constructor(address beneficiary_, uint64 start_, uint64 duration_) payable {
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        if (duration_ == 0) revert ZeroDuration();
        beneficiary = beneficiary_;
        start = start_;
        duration = duration_;
    }

    receive() external payable {}

    /// @notice Amount of ether vested at `timestamp`, out of the total ever received.
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        return _vestingSchedule(address(this).balance + released, timestamp);
    }

    /// @notice Amount of ether currently vested but not yet released.
    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    /// @notice Sends all releasable ether to the beneficiary. Callable by anyone.
    function release() external {
        uint256 amount = releasable();
        if (amount == 0) revert NothingToRelease();

        released += amount;
        emit Released(amount);

        (bool ok,) = beneficiary.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function _vestingSchedule(uint256 total, uint64 timestamp) private view returns (uint256) {
        if (timestamp < start) return 0;
        // Widen to uint256 so `start + duration` cannot overflow.
        uint256 elapsed = uint256(timestamp) - start;
        if (elapsed >= duration) return total;
        return (total * elapsed) / duration;
    }
}
