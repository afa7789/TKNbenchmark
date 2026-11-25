# pragma version ~=0.4.3
"""
@title Vesting
@notice Linearly vests the ether it holds to a beneficiary between
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
    assert _beneficiary != empty(address), "Vesting: zero beneficiary"
    assert _duration != 0, "Vesting: zero duration"
    beneficiary = _beneficiary
    start = _start
    duration = _duration


@external
@payable
def __default__():
    """
    @notice Accept plain ether transfers; they add to the vesting total.
    """
    pass


@external
@view
def vestedAmount(timestamp: uint64) -> uint256:
    """
    @notice Amount of ether vested at `timestamp`.
    """
    return self._vested_amount(timestamp)


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
    @notice Send the releasable ether to the beneficiary. Callable by anyone.
    """
    amount: uint256 = self._releasable()
    assert amount != 0, "Vesting: nothing to release"
    self.released += amount
    log Released(amount=amount)
    raw_call(beneficiary, b"", value=amount)


@internal
@view
def _releasable() -> uint256:
    return self._vested_amount(convert(block.timestamp, uint64)) - self.released


@internal
@view
def _vested_amount(timestamp: uint64) -> uint256:
    total: uint256 = self.balance + self.released
    if timestamp < start:
        return 0
    # Widen to uint256 so `start + duration` cannot overflow.
    elapsed: uint256 = convert(timestamp - start, uint256)
    length: uint256 = convert(duration, uint256)
    if elapsed >= length:
        return total
    return total * elapsed // length
