// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Vesting
/// @notice Holds ether and releases it linearly to a beneficiary between `start` and `start + duration`.
/// @dev Ether received after deployment (via `receive`) is added to the vesting total and follows the same schedule.
contract Vesting {
    /// @notice Emitted when ether is released to the beneficiary.
    event Released(uint256 amount);

    error ZeroBeneficiary();
    error ZeroDuration();
    error NothingToRelease();
    error TransferFailed();

    address private immutable _beneficiary;
    uint64 private immutable _start;
    uint64 private immutable _duration;

    uint256 private _released;

    constructor(address beneficiary_, uint64 start_, uint64 duration_) payable {
        if (beneficiary_ == address(0)) revert ZeroBeneficiary();
        if (duration_ == 0) revert ZeroDuration();
        _beneficiary = beneficiary_;
        _start = start_;
        _duration = duration_;
    }

    receive() external payable {}

    function beneficiary() external view returns (address) {
        return _beneficiary;
    }

    function start() external view returns (uint64) {
        return _start;
    }

    function duration() external view returns (uint64) {
        return _duration;
    }

    function released() external view returns (uint256) {
        return _released;
    }

    /// @notice Amount of ether vested at `timestamp`, out of the total ever held by the contract.
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        uint256 total = address(this).balance + _released;
        if (timestamp < _start) return 0;
        // Compute the end in uint256 so `start + duration` cannot overflow uint64.
        uint256 elapsed = uint256(timestamp) - _start;
        if (elapsed >= _duration) return total;
        return (total * elapsed) / _duration;
    }

    /// @notice Amount of ether currently vested but not yet released.
    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - _released;
    }

    /// @notice Sends all releasable ether to the beneficiary. Callable by anyone.
    function release() external {
        uint256 amount = releasable();
        if (amount == 0) revert NothingToRelease();

        _released += amount;
        emit Released(amount);

        (bool ok,) = _beneficiary.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
