# pragma version ~=0.4.3
"""
@title Bench Token
@license MIT
@notice Minimal ERC-20 token with allowances. An allowance of
        `max_value(uint256)` is treated as infinite.
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed

implements: IERC20
implements: IERC20Detailed


NAME: constant(String[25]) = "Bench Token"
SYMBOL: constant(String[5]) = "BTK"
DECIMALS: constant(uint8) = 18


event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256


event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256


balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
totalSupply: public(uint256)


@deploy
def __init__(initial_supply: uint256):
    self.balanceOf[msg.sender] = initial_supply
    self.totalSupply = initial_supply
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
def transfer(to: address, amount: uint256) -> bool:
    self._transfer(msg.sender, to, amount)
    return True


@external
def approve(spender: address, amount: uint256) -> bool:
    assert spender != empty(address), "Token: approve to the zero address"
    self.allowance[msg.sender][spender] = amount
    log Approval(owner=msg.sender, spender=spender, value=amount)
    return True


@external
def transferFrom(owner: address, to: address, amount: uint256) -> bool:
    current: uint256 = self.allowance[owner][msg.sender]
    if current != max_value(uint256):
        assert current >= amount, "Token: insufficient allowance"
        self.allowance[owner][msg.sender] = unsafe_sub(current, amount)
    self._transfer(owner, to, amount)
    return True


@internal
def _transfer(owner: address, to: address, amount: uint256):
    assert to != empty(address), "Token: transfer to the zero address"
    owner_balance: uint256 = self.balanceOf[owner]
    assert owner_balance >= amount, "Token: transfer amount exceeds balance"
    self.balanceOf[owner] = unsafe_sub(owner_balance, amount)
    # Cannot overflow: the sum of all balances is bounded by `totalSupply`.
    self.balanceOf[to] = unsafe_add(self.balanceOf[to], amount)
    log Transfer(sender=owner, receiver=to, value=amount)
