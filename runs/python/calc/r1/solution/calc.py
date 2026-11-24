"""64-bit signed integer expression evaluator.

Reads one expression per line from standard input and prints its value,
or ``error`` for syntax errors, division by zero, and 64-bit overflow.
"""

from __future__ import annotations

import re
import sys
from collections.abc import Iterable, Iterator

INT_MIN = -(1 << 63)
INT_MAX = (1 << 63) - 1

_TOKEN_RE = re.compile(rb"[ \t]*(?:([0-9]+)|([-+*/%()])|(.))", re.DOTALL)
_BLANK = b" \t"

# Binary operator precedence; unary minus binds tighter than all of them.
_PRECEDENCE = {b"+": 1, b"-": 1, b"*": 2, b"/": 2, b"%": 2}
_UNARY = b"neg"
_UNARY_PRECEDENCE = 3
_LPAREN = b"("


class CalcError(Exception):
    """Raised for any syntax, domain, or overflow error in an expression."""


def _check(value: int) -> int:
    if not INT_MIN <= value <= INT_MAX:
        raise CalcError("overflow")
    return value


def _truncated_divmod(a: int, b: int) -> tuple[int, int]:
    if b == 0:
        raise CalcError("division by zero")
    q = abs(a) // abs(b)
    if (a < 0) != (b < 0):
        q = -q
    return q, a - b * q


def _apply_binary(op: bytes, a: int, b: int) -> int:
    match op:
        case b"+":
            return _check(a + b)
        case b"-":
            return _check(a - b)
        case b"*":
            return _check(a * b)
        case b"/":
            return _check(_truncated_divmod(a, b)[0])
        case b"%":
            # The remainder always fits, e.g. INT_MIN % -1 == 0.
            return _truncated_divmod(a, b)[1]
    raise AssertionError(f"unknown operator {op!r}")


def _precedence(op: bytes) -> int:
    return _UNARY_PRECEDENCE if op is _UNARY else _PRECEDENCE.get(op, 0)


def _tokens(line: bytes) -> Iterator[tuple[bytes | None, bytes | None]]:
    """Yield (number, operator) pairs; invalid characters raise CalcError."""
    end = len(line.rstrip(_BLANK))
    pos = 0
    while pos < end:
        m = _TOKEN_RE.match(line, pos, end)
        if m is None or m.group(3) is not None:
            raise CalcError("invalid character")
        pos = m.end()
        yield m.group(1), m.group(2)


def evaluate(line: bytes) -> int:
    """Evaluate one expression and return its value.

    Uses an operator-precedence (shunting-yard) evaluator so that deeply
    nested input cannot exhaust the interpreter's recursion limit.
    """
    values: list[int] = []
    ops: list[bytes] = []

    def reduce_top() -> None:
        op = ops.pop()
        if op is _UNARY:
            values.append(_check(-values.pop()))
        else:
            b = values.pop()
            a = values.pop()
            values.append(_apply_binary(op, a, b))

    expect_operand = True
    for number, op in _tokens(line):
        if expect_operand:
            if number is not None:
                value = int(number)
                if value > INT_MAX:
                    raise CalcError("literal out of range")
                values.append(value)
                expect_operand = False
            elif op == b"-":
                ops.append(_UNARY)
            elif op == _LPAREN:
                ops.append(_LPAREN)
            else:
                raise CalcError("expected operand")
        elif op == b")":
            while ops and ops[-1] != _LPAREN:
                reduce_top()
            if not ops:
                raise CalcError("unbalanced ')'")
            ops.pop()
        elif op in _PRECEDENCE:
            prec = _PRECEDENCE[op]
            # Left-associative: reduce operators of equal or higher precedence.
            while ops and _precedence(ops[-1]) >= prec:
                reduce_top()
            ops.append(op)
            expect_operand = True
        else:
            raise CalcError("expected operator")

    if expect_operand:
        raise CalcError("missing operand")
    while ops:
        if ops[-1] == _LPAREN:
            raise CalcError("unbalanced '('")
        reduce_top()
    return values[0]


def process(lines: Iterable[bytes]) -> Iterator[str]:
    """Yield one output line per non-blank input line."""
    for raw in lines:
        line = raw.removesuffix(b"\n")
        if not line.strip(_BLANK):
            continue
        try:
            yield str(evaluate(line))
        except CalcError:
            yield "error"


def main() -> int:
    out = sys.stdout
    out.writelines(f"{result}\n" for result in process(sys.stdin.buffer))
    out.flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
