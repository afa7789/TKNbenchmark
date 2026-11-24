// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Vesting
/// @notice Holds ether and releases it linearly to a beneficiary between `start` and `start + duration`.
/// @dev Ether received at any time (constructor or `receive`) is added to the vesting total and follows
///      the same schedule. Release is permissionless; funds always go to the beneficiary.
contract Vesting {
    /// @notice Emitted when `amount` wei is released to the beneficiary.
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

    /// @notice Total ether released so far.
    function released() external view returns (uint256) {
        return _released;
    }

    /// @notice Ether currently vested but not yet released.
    function releasable() public view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - _released;
    }

    /// @notice Amount of ether vested at `timestamp`, out of the total ever held.
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        uint256 total = address(this).balance + _released;
        if (timestamp < _start) return 0;
        // Widen to uint256 so `start + duration` cannot overflow uint64.
        uint256 elapsed = uint256(timestamp) - _start;
        if (elapsed >= _duration) return total;
        return (total * elapsed) / _duration;
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
