# pragma version ~=0.4.3
"""
@title Token
@license MIT
@notice Minimal ERC-20 token with allowances. The full initial supply is
        minted to the deployer; an allowance of `max_value(uint256)` is
        treated as infinite.
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed

implements: IERC20
implements: IERC20Detailed


event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256


event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256


NAME: constant(String[25]) = "Bench Token"
SYMBOL: constant(String[5]) = "BTK"
DECIMALS: constant(uint8) = 18

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])


@deploy
def __init__(initial_supply: uint256):
    self.totalSupply = initial_supply
    self.balanceOf[msg.sender] = initial_supply
    log Transfer(sender=empty(address), receiver=msg.sender, value=initial_supply)


@external
@view
def name() -> String[25]:
    return NAME


@external
@view
def symbol() -> String[5]:
    return SYMBOL


@external
@view
def decimals() -> uint8:
    return DECIMALS


@external
def transfer(receiver: address, amount: uint256) -> bool:
    self._transfer(msg.sender, receiver, amount)
    return True


@external
def approve(spender: address, amount: uint256) -> bool:
    assert spender != empty(address), "Token: approve to the zero address"
    self.allowance[msg.sender][spender] = amount
    log Approval(owner=msg.sender, spender=spender, value=amount)
    return True


@external
def transferFrom(owner: address, receiver: address, amount: uint256) -> bool:
    current: uint256 = self.allowance[owner][msg.sender]
    if current != max_value(uint256):
        assert current >= amount, "Token: insufficient allowance"
        self.allowance[owner][msg.sender] = unsafe_sub(current, amount)
    self._transfer(owner, receiver, amount)
    return True


@internal
def _transfer(owner: address, receiver: address, amount: uint256):
    assert receiver != empty(address), "Token: transfer to the zero address"
    balance: uint256 = self.balanceOf[owner]
    assert balance >= amount, "Token: transfer amount exceeds balance"
    self.balanceOf[owner] = unsafe_sub(balance, amount)
    # Cannot overflow: the sum of all balances equals `totalSupply`.
    self.balanceOf[receiver] = unsafe_add(self.balanceOf[receiver], amount)
    log Transfer(sender=owner, receiver=receiver, value=amount)
