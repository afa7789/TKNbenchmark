// SPDX-License-Identifier: MIT
pragma solidity 0.8.39;

/// @title Vesting
/// @notice Holds ether and releases it linearly to a fixed beneficiary between `start` and
/// `start + duration`. Ether sent to the contract after deployment joins the vesting schedule.
contract Vesting {
    /// @notice Emitted when `amount` wei is released to the beneficiary.
    event Released(uint256 amount);

    error ZeroBeneficiary();
    error ZeroDuration();
    error NothingToRelease();
    error TransferFailed();

    address public immutable beneficiary;
    uint64 public immutable start;
    uint64 public immutable duration;

    /// @notice Total wei released to the beneficiary so far.
    uint256 public released;

    constructor(address beneficiary_, uint64 start_, uint64 duration_) payable {
        require(beneficiary_ != address(0), ZeroBeneficiary());
        require(duration_ != 0, ZeroDuration());
        beneficiary = beneficiary_;
        start = start_;
        duration = duration_;
    }

    receive() external payable {}

    /// @notice Amount vested at `timestamp`, out of everything ever held by the contract.
    function vestedAmount(uint64 timestamp) public view returns (uint256) {
        uint256 total = address(this).balance + released;
        if (timestamp < start) return 0;
        uint256 elapsed = uint256(timestamp) - start;
        if (elapsed >= duration) return total;
        return (total * elapsed) / duration;
    }

    /// @notice Amount currently vested but not yet released.
    function releasable() public view returns (uint256) {
        // forge-lint: disable-next-line(unsafe-typecast)
        return vestedAmount(uint64(block.timestamp)) - released;
    }

    /// @notice Sends all releasable ether to the beneficiary. Callable by anyone.
    function release() external {
        uint256 amount = releasable();
        require(amount != 0, NothingToRelease());

        released += amount;
        emit Released(amount);

        (bool ok,) = beneficiary.call{value: amount}("");
        require(ok, TransferFailed());
    }
}
