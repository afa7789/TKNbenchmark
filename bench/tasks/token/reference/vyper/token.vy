# pragma version ~=0.4.0

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

name: public(constant(String[16])) = "Bench Token"
symbol: public(constant(String[8])) = "BTK"
decimals: public(constant(uint8)) = 18
totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])


@deploy
def __init__(initialSupply: uint256):
    self.totalSupply = initialSupply
    self.balanceOf[msg.sender] = initialSupply
    log Transfer(sender=empty(address), receiver=msg.sender, value=initialSupply)


@internal
def _move(sender: address, receiver: address, amount: uint256):
    assert receiver != empty(address), "zero to"
    assert self.balanceOf[sender] >= amount, "balance"
    self.balanceOf[sender] -= amount
    self.balanceOf[receiver] += amount
    log Transfer(sender=sender, receiver=receiver, value=amount)


@external
def transfer(receiver: address, amount: uint256) -> bool:
    self._move(msg.sender, receiver, amount)
    return True


@external
def approve(spender: address, amount: uint256) -> bool:
    assert spender != empty(address), "zero spender"
    self.allowance[msg.sender][spender] = amount
    log Approval(owner=msg.sender, spender=spender, value=amount)
    return True


@external
def transferFrom(sender: address, receiver: address, amount: uint256) -> bool:
    allowed: uint256 = self.allowance[sender][msg.sender]
    if allowed != max_value(uint256):
        assert allowed >= amount, "allowance"
        self.allowance[sender][msg.sender] = allowed - amount
    self._move(sender, receiver, amount)
    return True
