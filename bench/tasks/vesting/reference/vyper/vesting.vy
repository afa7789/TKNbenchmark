# pragma version ~=0.4.0

event Released:
    amount: uint256

beneficiary: public(immutable(address))
start: public(immutable(uint64))
duration: public(immutable(uint64))
released: public(uint256)


@deploy
@payable
def __init__(beneficiary_: address, start_: uint64, duration_: uint64):
    assert beneficiary_ != empty(address), "zero beneficiary"
    assert duration_ > 0, "zero duration"
    beneficiary = beneficiary_
    start = start_
    duration = duration_


@external
@payable
def __default__():
    pass


@view
@internal
def _vested(timestamp: uint64) -> uint256:
    total: uint256 = self.balance + self.released
    if timestamp < start:
        return 0
    if timestamp >= start + duration:
        return total
    return total * convert(timestamp - start, uint256) // convert(duration, uint256)


@view
@external
def vestedAmount(timestamp: uint64) -> uint256:
    return self._vested(timestamp)


@view
@internal
def _releasable() -> uint256:
    return self._vested(convert(block.timestamp, uint64)) - self.released


@view
@external
def releasable() -> uint256:
    return self._releasable()


@external
def release():
    amount: uint256 = self._releasable()
    assert amount > 0, "nothing to release"
    self.released += amount
    log Released(amount=amount)
    send(beneficiary, amount)
