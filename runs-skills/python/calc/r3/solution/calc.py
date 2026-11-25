"""Evaluate signed 64-bit integer expressions, one per line of standard input."""

import re
import sys
from collections.abc import Callable, Iterable

INT_MIN = -(1 << 63)
INT_MAX = (1 << 63) - 1

_LINE = re.compile(rb"(?:[ \t]*(?:[0-9]+|[-+*/%()]))*[ \t]*")
_TOKEN = re.compile(rb"[0-9]+|[-+*/%()]")


class CalcError(Exception):
    """Raised for syntax errors, division by zero and overflow."""


def _checked(value: int) -> int:
    if not INT_MIN <= value <= INT_MAX:
        raise CalcError("overflow")
    return value


def _quotient(a: int, b: int) -> int:
    if b == 0:
        raise CalcError("division by zero")
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def _div(a: int, b: int) -> int:
    return _checked(_quotient(a, b))


def _mod(a: int, b: int) -> int:
    return a - b * _quotient(a, b)


_BINARY: dict[bytes, tuple[int, Callable[[int, int], int]]] = {
    b"+": (1, lambda a, b: _checked(a + b)),
    b"-": (1, lambda a, b: _checked(a - b)),
    b"*": (2, lambda a, b: _checked(a * b)),
    b"/": (2, _div),
    b"%": (2, _mod),
}
_UNARY = b"neg"
_UNARY_PRECEDENCE = 3
_LPAREN = b"("


def _apply(op: bytes, values: list[int]) -> None:
    if op == _UNARY:
        values.append(_checked(-values.pop()))
    else:
        right = values.pop()
        left = values.pop()
        values.append(_BINARY[op][1](left, right))


def _precedence(op: bytes) -> int:
    return _UNARY_PRECEDENCE if op == _UNARY else _BINARY[op][0]


def evaluate(line: bytes) -> int:
    """Evaluate one expression; raise CalcError if it is invalid.

    Uses an iterative shunting-yard parser so deeply nested input cannot
    exhaust the interpreter's recursion limit.
    """
    if not _LINE.fullmatch(line):
        raise CalcError("invalid character")

    values: list[int] = []
    ops: list[bytes] = []
    expect_operand = True

    for token in _TOKEN.findall(line):
        if expect_operand:
            if token.isdigit():
                values.append(_checked(int(token)))
                expect_operand = False
            elif token == b"-":
                ops.append(_UNARY)
            elif token == _LPAREN:
                ops.append(_LPAREN)
            else:
                raise CalcError("missing operand")
        elif token in _BINARY:
            precedence = _BINARY[token][0]
            while ops and ops[-1] != _LPAREN and _precedence(ops[-1]) >= precedence:
                _apply(ops.pop(), values)
            ops.append(token)
            expect_operand = True
        elif token == b")":
            while ops and ops[-1] != _LPAREN:
                _apply(ops.pop(), values)
            if not ops:
                raise CalcError("unbalanced parenthesis")
            ops.pop()
        else:
            raise CalcError("missing operator")

    if expect_operand:
        raise CalcError("missing operand")
    while ops:
        op = ops.pop()
        if op == _LPAREN:
            raise CalcError("unbalanced parenthesis")
        _apply(op, values)
    return values[0]


def run(lines: Iterable[bytes]) -> Iterable[str]:
    """Yield the output line for every non-blank input line."""
    for raw in lines:
        line = raw.removesuffix(b"\n")
        if not line.strip(b" \t"):
            continue
        try:
            yield str(evaluate(line))
        except CalcError:
            yield "error"


def main() -> int:
    out = list(run(sys.stdin.buffer))
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
