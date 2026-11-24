#!/usr/bin/env python3
"""Line-oriented 64-bit signed integer expression evaluator.

Reads one expression per line from stdin and prints its value or ``error``.
Parsing uses an explicit operator stack (shunting-yard) so that deeply nested
input cannot exhaust Python's recursion limit.
"""

from __future__ import annotations

import re
import sys
from collections.abc import Iterable, Iterator

INT_MIN = -(1 << 63)
INT_MAX = (1 << 63) - 1

# Operator stack markers.
_NEG = "neg"
_LPAREN = "("

_PRECEDENCE = {"+": 1, "-": 1, "*": 2, "/": 2, "%": 2, _NEG: 3}

_TOKEN = re.compile(rb"[ \t]*+(?:([0-9]+)|([-+*/%()])|(.))", re.DOTALL)
_BLANK = re.compile(rb"[ \t]*")


class CalcError(Exception):
    """Raised for any syntax, domain, or overflow error in an expression."""


def _checked(value: int) -> int:
    if value < INT_MIN or value > INT_MAX:
        raise CalcError("overflow")
    return value


def _divide(a: int, b: int) -> int:
    """Integer division truncating toward zero."""
    if b == 0:
        raise CalcError("division by zero")
    q = abs(a) // abs(b)
    return -q if (a < 0) != (b < 0) else q


def _apply(op: str, values: list[int]) -> None:
    if op == _NEG:
        values[-1] = _checked(-values[-1])
        return
    b = values.pop()
    a = values[-1]
    if op == "+":
        result = a + b
    elif op == "-":
        result = a - b
    elif op == "*":
        result = a * b
    elif op == "/":
        result = _divide(a, b)
    else:  # "%": sign follows the dividend; never overflows.
        result = a - b * _divide(a, b)
    values[-1] = _checked(result)


def _tokens(line: bytes) -> Iterator[bytes]:
    pos = 0
    end = len(line)
    while pos < end:
        m = _TOKEN.match(line, pos)
        if m is None:  # only trailing blanks remain
            return
        number, op, junk = m.groups()
        if junk is not None:
            raise CalcError("invalid character")
        yield number if number is not None else op
        pos = m.end()


def evaluate(line: bytes) -> int:
    """Evaluate a single expression, raising CalcError on any failure."""
    values: list[int] = []
    ops: list[str] = []
    expect_operand = True

    for token in _tokens(line):
        if token[0] in b"0123456789":
            if not expect_operand:
                raise CalcError("unexpected number")
            values.append(_checked(int(token)))
            expect_operand = False
            continue

        tok = token.decode("ascii")
        if expect_operand:
            if tok == "-":
                ops.append(_NEG)
            elif tok == _LPAREN:
                ops.append(_LPAREN)
            else:
                raise CalcError(f"unexpected {tok!r}")
        elif tok == ")":
            while ops and ops[-1] != _LPAREN:
                _apply(ops.pop(), values)
            if not ops:
                raise CalcError("unbalanced ')'")
            ops.pop()
        elif tok == _LPAREN:
            raise CalcError("unexpected '('")
        else:
            prec = _PRECEDENCE[tok]
            while ops and ops[-1] != _LPAREN and _PRECEDENCE[ops[-1]] >= prec:
                _apply(ops.pop(), values)
            ops.append(tok)
            expect_operand = True

    if expect_operand:
        raise CalcError("missing operand")
    while ops:
        op = ops.pop()
        if op == _LPAREN:
            raise CalcError("unbalanced '('")
        _apply(op, values)
    return values[0]


def run(lines: Iterable[bytes]) -> Iterator[str]:
    for line in lines:
        if _BLANK.fullmatch(line):
            continue
        try:
            yield str(evaluate(line))
        except CalcError:
            yield "error"


def main() -> int:
    sys.set_int_max_str_digits(0)
    data = sys.stdin.buffer.read()
    out = "\n".join(run(data.split(b"\n")))
    if out:
        sys.stdout.write(out + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
