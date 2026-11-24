# pragma version ~=0.4.3
"""
@title Vesting
@notice Holds ether and releases it linearly to a beneficiary between
        `start` and `start + duration`.
"""

event Released:
    amount: uint256


beneficiary: public(immutable(address))
start: public(immutable(uint64))
duration: public(immutable(uint64))

released: public(uint256)


@deploy
@payable
def __init__(_beneficiary: address, _start: uint64, _duration: uint64):
    """
    @param _beneficiary Recipient of vested ether; must be non-zero.
    @param _start Vesting start timestamp (seconds).
    @param _duration Vesting duration (seconds); must be positive.
    """
    assert _beneficiary != empty(address), "Vesting: zero beneficiary"
    assert _duration > 0, "Vesting: zero duration"
    beneficiary = _beneficiary
    start = _start
    duration = _duration


@external
@payable
def __default__():
    """
    @notice Accepts plain ether transfers, adding them to the vesting total.
    """
    pass


@internal
@view
def _vested_amount(timestamp: uint256) -> uint256:
    total: uint256 = self.balance + self.released
    begin: uint256 = convert(start, uint256)
    length: uint256 = convert(duration, uint256)
    if timestamp < begin:
        return 0
    if timestamp >= begin + length:
        return total
    return total * (timestamp - begin) // length


@internal
@view
def _releasable() -> uint256:
    return self._vested_amount(block.timestamp) - self.released


@external
@view
def vestedAmount(timestamp: uint64) -> uint256:
    """
    @notice Amount of ether vested at `timestamp`.
    """
    return self._vested_amount(convert(timestamp, uint256))


@external
@view
def releasable() -> uint256:
    """
    @notice Amount of ether vested but not yet released.
    """
    return self._releasable()


@external
@nonreentrant
def release():
    """
    @notice Sends all releasable ether to the beneficiary. Callable by anyone.
    """
    amount: uint256 = self._releasable()
    assert amount > 0, "Vesting: nothing to release"
    self.released += amount
    log Released(amount=amount)
    raw_call(beneficiary, b"", value=amount)
