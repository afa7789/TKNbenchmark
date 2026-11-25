# pragma version ~=0.4.3
"""
@title Bench Token
@notice Minimal ERC-20 token with a fixed supply minted to the deployer.
"""

from ethereum.ercs import IERC20
from ethereum.ercs import IERC20Detailed

implements: IERC20
implements: IERC20Detailed


NAME: constant(String[11]) = "Bench Token"
SYMBOL: constant(String[3]) = "BTK"
DECIMALS: constant(uint8) = 18

name: public(constant(String[11])) = NAME
symbol: public(constant(String[3])) = SYMBOL
decimals: public(constant(uint8)) = DECIMALS

totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])


@deploy
def __init__(initial_supply: uint256):
    self.totalSupply = initial_supply
    self.balanceOf[msg.sender] = initial_supply
    log IERC20.Transfer(sender=empty(address), receiver=msg.sender, value=initial_supply)


@external
def transfer(to: address, amount: uint256) -> bool:
    self._transfer(msg.sender, to, amount)
    return True


@external
def approve(spender: address, amount: uint256) -> bool:
    assert spender != empty(address), "approve to zero address"
    self.allowance[msg.sender][spender] = amount
    log IERC20.Approval(owner=msg.sender, spender=spender, value=amount)
    return True


@external
def transferFrom(owner: address, to: address, amount: uint256) -> bool:
    current: uint256 = self.allowance[owner][msg.sender]
    if current != max_value(uint256):
        assert current >= amount, "insufficient allowance"
        self.allowance[owner][msg.sender] = unsafe_sub(current, amount)
    self._transfer(owner, to, amount)
    return True


def _transfer(owner: address, to: address, amount: uint256):
    assert to != empty(address), "transfer to zero address"
    owner_balance: uint256 = self.balanceOf[owner]
    assert owner_balance >= amount, "insufficient balance"
    self.balanceOf[owner] = unsafe_sub(owner_balance, amount)
    # Cannot overflow: the sum of all balances is bounded by totalSupply.
    self.balanceOf[to] = unsafe_add(self.balanceOf[to], amount)
    log IERC20.Transfer(sender=owner, receiver=to, value=amount)
