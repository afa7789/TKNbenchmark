# pragma version ~=0.4.3
"""
@title Vesting
@license MIT
@notice Holds ether and releases it linearly to a beneficiary between
        `start` and `start + duration`. Ether received after deployment is
        added to the vesting total.
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
    @param _beneficiary Recipient of the vested ether; must be non-zero.
    @param _start Vesting start timestamp (seconds).
    @param _duration Vesting duration in seconds; must be positive.
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
    @notice Accept plain ether transfers; they join the vesting total.
    """
    pass


@internal
@view
def _vested_amount(timestamp: uint64) -> uint256:
    total: uint256 = self.balance + self.released
    begin: uint256 = convert(start, uint256)
    length: uint256 = convert(duration, uint256)
    t: uint256 = convert(timestamp, uint256)
    if t < begin:
        return 0
    if t >= begin + length:
        return total
    return total * (t - begin) // length


@internal
@view
def _releasable() -> uint256:
    return self._vested_amount(convert(block.timestamp, uint64)) - self.released


@external
@view
def vestedAmount(timestamp: uint64) -> uint256:
    """
    @notice Amount of ether vested at `timestamp` (including already released).
    """
    return self._vested_amount(timestamp)


@external
@view
def releasable() -> uint256:
    """
    @notice Amount of ether that can currently be released.
    """
    return self._releasable()


@external
@nonreentrant
def release():
    """
    @notice Send the currently releasable ether to the beneficiary.
    @dev Callable by anyone. Reverts if nothing is releasable.
    """
    amount: uint256 = self._releasable()
    assert amount > 0, "Vesting: nothing to release"
    self.released += amount
    log Released(amount=amount)
    raw_call(beneficiary, b"", value=amount)
