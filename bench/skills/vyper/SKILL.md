---
name: vyper
description: "Version-correct, idiomatic Vyper for the installed toolchain (Vyper 0.4.3+commit.bff19ea2): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Vyper code."
---

# Vyper 0.4.3

0.3.x syntax fails on 0.4.x. Defaults: EVM `prague`, `-O gas`, decimals off.

## Header and layout
```python
# pragma version ~=0.4.3
# pragma nonreentrancy on
from ethereum.ercs import IERC20   # + IERC20Detailed IERC721 IERC4626 IERC165
implements: IERC20
from lib import ownable            # any .vy is a module; interfaces are .vyi/.json
initializes: ownable
exports: ownable.owner
```
Order: imports/exports, then types/events/interfaces, constants, immutables, storage, `__init__`, external, internal. Constants are `UPPER_SNAKE`, types and events `CapWords`, everything else `snake_case`, internal names start with `_`. Decorators go visibility, then mutability, then `@nonreentrant`.

## 0.3 habits that fail (→ 0.4.3)
- `@external def __init__` → `@deploy`
- `Foo(a).bar()` → `extcall` (nonpayable/payable) or `staticcall` (view/pure)
- `for i in range(n)` → `for i: uint256 in range(n, bound=N)`. A non-literal end needs `bound` and reverts if it is exceeded.
- `a / b` on ints → `a // b`
- `ZERO_ADDRESS`, `MAX_UINT256` → `empty(address)`, `max_value(uint256)`
- `vyper.interfaces.ERC20` → `ethereum.ercs.IERC20`
- `@nonreentrant("k")` → `@nonreentrant` (one global lock, held in transient storage)
- `sqrt` → `import math` then `math.sqrt` (decimal). Use `isqrt` for uint256.
- `bitwise_and` → `&`, and `shift` → `<<`/`>>`
- Warnings only (`-W error` makes them fail): `_abi_encode`→`abi_encode`, `enum`→`flag`, `P({x: 1})`→`P(x=1)`, `log E(1)`→`log E(a=1)`

## Core (verified)
```python
flag Role:
    MINTER
    PAUSER
struct Point:
    x: uint256
    y: uint256
event Minted:
    to: indexed(address)
    amount: uint256
interface Pair:
    def get_reserves() -> (uint256, uint256): view
    def swap(a: uint256, to: address): payable

OWNER: public(immutable(address))  # read as OWNER, never self.OWNER
roles: public(HashMap[address, Role])
pts: DynArray[Point, 10]
_flag: transient(uint256)          # cancun+

@deploy
def __init__():
    OWNER = msg.sender
    self.roles[msg.sender] = Role.MINTER | Role.PAUSER

@external
@payable
def go(p: Pair) -> uint256:
    assert Role.MINTER in self.roles[msg.sender], "!minter"
    a: uint256 = 0                 # locals must be initialised
    b: uint256 = 0
    a, b = staticcall p.get_reserves()
    extcall p.swap(a, msg.sender, value=msg.value)
    self.pts.append(Point(x=a, y=b))
    log Minted(to=msg.sender, amount=a)
    return a if a > b else b
```
- Internal functions are the default. Call them as `self._f()`, because calling an external function through `self` is not allowed.
- Calldata args are read-only, and a `DynArray` can't be changed while you iterate over it. `HashMap` exists only in storage.
- Size bounds are enforced. `concat(String[10], "-", String[10])` is a `String[21]`.
- Mixed int types fail, so `convert(x, uint256)` first. `x ** y` with both at runtime fails; use `pow_mod256` or make one side constant.
- Revert with `assert c, "msg"`, `raise "msg"` or `raw_revert(b)`. `assert c  # dev: msg` gives a dev reason tests can match.

## Calls
```python
assert extcall token.transferFrom(msg.sender, self, amt, default_return_value=True)
bal: uint256 = staticcall IERC20(t).balanceOf(self)
r: Bytes[32] = raw_call(to, abi_encode(x, method_id=method_id("f(uint256)")), max_outsize=32)
ok: bool = False
out: Bytes[32] = b""
ok, out = raw_call(to, b"", max_outsize=32, value=v, revert_on_failure=False)
y: uint256 = abi_decode(r, uint256)
```
- `value=` cannot be combined with `is_delegate_call`/`is_static_call`. (the official `@raw_return` doc example does, and fails).
- `@raw_return` (0.4.3) makes an external function returning `Bytes[N]` return the bytes without ABI-encoding. Use it for proxies: `return raw_call(impl, msg.data, max_outsize=1024, is_delegate_call=True)`.
- Factories: `create_from_blueprint(bp, *ctor_args, salt=s)`, `create_minimal_proxy_to(impl)`, `create_copy_of(a)`, `raw_create(initcode, *args)` (0.4.2). Get blueprints with `vyper -f blueprint_bytecode`.
- `init` is reserved, so name a proxy initialiser `initialize`.

## Modules (composition, not inheritance)
```python
# lib/pausable.vy
from . import ownable
uses: ownable          # reads ownable state without owning it
# Main.vy
from lib import ownable
from lib import pausable
initializes: ownable
initializes: pausable[ownable := ownable]
exports: (ownable.owner, pausable.__interface__)
@deploy
def __init__():
    ownable.__init__()  # once per initialised module, in dependency order
```
- Unexported external functions are silently left out of the ABI, so check with `vyper -f abi`.
- Use `mod._fn()`, `mod.CONST` and `mod.Struct(...)`. A stateless module needs no `initializes`.
- `exports: m.__interface__` already includes `m`'s exports, so exporting one again gives "already exported!".
- `m.__at__(addr)` returns an `m.__interface__` for a deployed copy.
- In `.vyi` files the bodies are `...` and `@external` is optional. They can hold events, structs and flags, used as `I.Info` and `log I.Ev(...)`.
- Write `from a import b`, not `import a.b`.

## Reentrancy
- Calling a `@nonreentrant` function from another `@nonreentrant` one is a compile error, so share logic through unlocked internals.
- `# pragma nonreentrancy on` locks all external functions and `public` getters, except constant and immutable ones. Opt out with `@reentrant` or `public(reentrant(T))`. Under the pragma, `@nonreentrant` on an external function is an error. Without the pragma, `@reentrant` is an error.

## Gas
Load a storage value into a local once, then use `unsafe_add/sub` after an explicit bounds check. Use `constant`/`immutable` for deploy-time values (no SLOAD) and `transient` for per-transaction state. Keep `DynArray`/`Bytes` bounds small, because memory is sized to the bound.

## Build
```
vyper -f abi,bytecode,layout -o out.txt C.vy
vyper -f interface C.vy           # .vyi; -f external_interface for an inline one
vyper -p lib/pypi C.vy            # import search path
vyper -f solc_json C.vy           # Etherscan standard-json input
vyper --evm-version cancun -O codesize -W error --enable-decimals C.vy
```
Pragmas: `evm-version cancun`, `optimize codesize`, `enable-decimals`.

## Moccasin + Titanoboa
```
uv tool install moccasin
mox init proj --pyproject        # src/ tests/ script/deploy.py moccasin.toml
mox install snekmate==0.1.2      # -> lib/pypi; newer snekmate requires 0.5
mox compile; mox test -k x --gas-profile --coverage; mox lint   # natrix
mox wallet import key; mox run deploy --network sepolia --account key
```
snekmate: `from snekmate.tokens import erc20`, `initializes: erc20[ownable := ownable]`, then `erc20.__init__(name, sym, 18, eip712_name, eip712_ver)`.
```python
import boa
from boa.test import strategy
c = boa.load("src/Bank.vy", 100)  # ctor args after path; boa.loads(src)
d = boa.load_partial("src/Child.vy"); bp = d.deploy_as_blueprint(); d.at(addr)
alice = boa.env.generate_address(); boa.env.set_balance(alice, 10**18)
with boa.env.prank(alice):
    c.deposit(value=1000)
assert c.get_logs()[0].amount == 1000
with boa.reverts("locked"): c.withdraw(1)
with boa.reverts(dev="zero deposit"): c.deposit()
boa.env.time_travel(seconds=101); c.eval("self.x"); boa.env.eoa
# @given(x=strategy("uint256", max_value=10**30))  (hypothesis)
```

## Error → fix
- `must use the extcall/staticcall keyword` → add the keyword its hint suggests
- `Value must be a literal integer, unless a bound is specified` → add `bound=`
- `missing type annotation` → `for x: T in`
- `'x' is a storage variable, access it as self.x` (internal calls too)
- `not initialized!` → call `mod.__init__()`
- `Cannot access 'mod' state!` → add `uses:` or `initializes:`
- `'a' uses 'b', but it is not initialized with 'b'` → `a[b := b]`
- `Given reference has type String[21], expected String[20]` → widen the type
- `decimals are not allowed unless --enable-decimals is set`
- `transient is not available pre-cancun`
