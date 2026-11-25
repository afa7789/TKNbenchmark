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
def __init__(beneficiary_: address, start_: uint64, duration_: uint64):
    assert beneficiary_ != empty(address), "Vesting: zero beneficiary"
    assert duration_ != 0, "Vesting: zero duration"
    beneficiary = beneficiary_
    start = start_
    duration = duration_


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
    return self._vested_amount(timestamp)


@external
@view
def releasable() -> uint256:
    return self._releasable()


@external
@nonreentrant
def release():
    """
    @notice Send all currently releasable ether to the beneficiary.
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
    if timestamp < start:
        return 0
    total: uint256 = self.balance + self.released
    elapsed: uint64 = unsafe_sub(timestamp, start)
    if elapsed >= duration:
        return total
    return total * convert(elapsed, uint256) // convert(duration, uint256)
