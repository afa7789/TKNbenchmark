"""calc: evaluate 64-bit signed integer expressions, one per input line.

Each non-blank line of standard input is parsed and evaluated; its value,
or ``error``, is written to standard output.
"""

from __future__ import annotations

import re
import sys
from collections.abc import Iterable, Iterator

INT64_MIN = -(1 << 63)
INT64_MAX = (1 << 63) - 1

# Whitespace runs produce an empty group and are skipped; every other
# character (or digit run) becomes a token. DOTALL makes '.' catch anything,
# so unknown characters surface as tokens and are rejected by the parser.
_TOKEN_RE = re.compile(r"[ \t]+|([0-9]+|.)", re.DOTALL)

# Binary operator precedence. Unary minus binds tighter than all of these.
_BINARY_PRECEDENCE = {"+": 1, "-": 1, "*": 2, "/": 2, "%": 2}
_UNARY_MINUS = "neg"
_LPAREN = "("


class CalcError(Exception):
    """Raised for any syntax, range, or arithmetic error in an expression."""


def _checked(value: int) -> int:
    if not INT64_MIN <= value <= INT64_MAX:
        raise CalcError("overflow")
    return value


def _truncated_quotient(a: int, b: int) -> int:
    if b == 0:
        raise CalcError("division by zero")
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def _apply_binary(op: str, a: int, b: int) -> int:
    match op:
        case "+":
            return _checked(a + b)
        case "-":
            return _checked(a - b)
        case "*":
            return _checked(a * b)
        case "/":
            return _checked(_truncated_quotient(a, b))
        case "%":
            # Remainder of truncating division; always representable.
            return a - b * _truncated_quotient(a, b)
    raise AssertionError(f"unknown operator {op!r}")


def _tokenize(line: str) -> Iterator[str]:
    for match in _TOKEN_RE.finditer(line):
        token = match.group(1)
        if token is not None:
            yield token


def evaluate(line: str) -> int:
    """Evaluate one expression, raising CalcError if it is invalid.

    Uses an iterative operator-precedence (shunting-yard) parser so deeply
    nested input cannot exhaust the interpreter's recursion limit.
    """
    values: list[int] = []
    ops: list[str] = []

    def reduce_top() -> None:
        op = ops.pop()
        if op == _UNARY_MINUS:
            values.append(_checked(-values.pop()))
        else:
            b = values.pop()
            a = values.pop()
            values.append(_apply_binary(op, a, b))

    expect_operand = True
    for token in _tokenize(line):
        if expect_operand:
            if token.isdigit():
                values.append(_checked(int(token)))
                expect_operand = False
            elif token == "-":
                ops.append(_UNARY_MINUS)
            elif token == _LPAREN:
                ops.append(_LPAREN)
            else:
                raise CalcError(f"unexpected token {token!r}")
        elif (precedence := _BINARY_PRECEDENCE.get(token)) is not None:
            # Left-associative: reduce everything of equal or higher binding
            # (unary minus always qualifies) before pushing this operator.
            while ops and ops[-1] != _LPAREN and (
                ops[-1] == _UNARY_MINUS or _BINARY_PRECEDENCE[ops[-1]] >= precedence
            ):
                reduce_top()
            ops.append(token)
            expect_operand = True
        elif token == ")":
            while ops and ops[-1] != _LPAREN:
                reduce_top()
            if not ops:
                raise CalcError("unbalanced ')'")
            ops.pop()
        else:
            raise CalcError(f"unexpected token {token!r}")

    if expect_operand:
        raise CalcError("missing operand")
    while ops:
        if ops[-1] == _LPAREN:
            raise CalcError("unbalanced '('")
        reduce_top()
    return values.pop()


def process(lines: Iterable[str]) -> Iterator[str]:
    """Yield the output line for each input expression, skipping blanks."""
    for line in lines:
        if not line.strip(" \t"):
            continue
        try:
            yield str(evaluate(line))
        except CalcError:
            yield "error"


def main() -> int:
    data = sys.stdin.buffer.read()
    # latin-1 maps every byte to one character, so arbitrary bytes are
    # accepted and simply rejected as invalid tokens.
    lines = data.decode("latin-1").split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    out = "\n".join(process(lines))
    if out:
        sys.stdout.write(out + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
