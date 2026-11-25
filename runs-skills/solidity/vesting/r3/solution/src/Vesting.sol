// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

/// @title Vesting
/// @notice Holds ether and releases it linearly to a fixed beneficiary between `start` and
///         `start + duration`. Ether received after deployment joins the vesting total.
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
        require(beneficiary_ != address(0), ZeroBeneficiary());
        require(duration_ != 0, ZeroDuration());
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

    /// @notice Amount of ether vested at `timestamp`, out of the historical total.
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        uint256 total = address(this).balance + _released;
        if (timestamp < _start) return 0;
        uint256 elapsed = uint256(timestamp) - _start;
        if (elapsed >= _duration) return total;
        return total * elapsed / _duration;
    }

    /// @notice Amount of ether vested but not yet released.
    function releasable() public view returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return vestedAmount(uint64(block.timestamp)) - _released;
    }

    /// @notice Sends all releasable ether to the beneficiary. Callable by anyone.
    function release() external {
        uint256 amount = releasable();
        require(amount != 0, NothingToRelease());

        _released += amount;
        emit Released(amount);

        (bool ok,) = payable(_beneficiary).call{value: amount}("");
        require(ok, TransferFailed());
    }
}
