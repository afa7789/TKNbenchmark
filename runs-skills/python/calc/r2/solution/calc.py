"""calc: evaluate 64-bit signed integer expressions, one per line of stdin.

Each line is parsed with an iterative shunting-yard parser (so arbitrarily
deep nesting cannot exhaust the Python stack) and evaluated with exact
64-bit overflow checks. Lines that fail print ``error``.
"""

import re
import sys

INT_MIN = -(2**63)
INT_MAX = 2**63 - 1

TOKEN_RE = re.compile(r"[ \t]*(?:([0-9]+)|([-+*/%()]))")
BLANK_RE = re.compile(r"[ \t]*")

UNARY_MINUS = "u-"
PRECEDENCE = {"+": 1, "-": 1, "*": 2, "/": 2, "%": 2, UNARY_MINUS: 3}


class CalcError(Exception):
    """Raised for any syntax, division-by-zero or overflow error."""


def checked(value: int) -> int:
    if not INT_MIN <= value <= INT_MAX:
        raise CalcError
    return value


def trunc_div(a: int, b: int) -> int:
    if b == 0:
        raise CalcError
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def apply_binary(op: str, a: int, b: int) -> int:
    match op:
        case "+":
            return checked(a + b)
        case "-":
            return checked(a - b)
        case "*":
            return checked(a * b)
        case "/":
            return checked(trunc_div(a, b))
        case "%":
            # Remainder of truncating division; always within range.
            return a - b * trunc_div(a, b)
    raise AssertionError(f"unknown operator {op!r}")


def reduce_top(ops: list[str], values: list[int]) -> None:
    """Pop one operator from ``ops`` and apply it to ``values``."""
    op = ops.pop()
    if op == UNARY_MINUS:
        values.append(checked(-values.pop()))
    else:
        b = values.pop()
        a = values.pop()
        values.append(apply_binary(op, a, b))


def evaluate(line: str) -> int:
    values: list[int] = []
    ops: list[str] = []
    expect_operand = True
    pos = 0
    end = len(line)

    while True:
        # Skip trailing whitespace; stop at end of line.
        pos = BLANK_RE.match(line, pos).end()
        if pos == end:
            break
        m = TOKEN_RE.match(line, pos)
        if m is None:
            raise CalcError
        pos = m.end()
        number, tok = m.groups()

        if expect_operand:
            if number is not None:
                values.append(checked(int(number)))
                expect_operand = False
            elif tok == "-":
                ops.append(UNARY_MINUS)
            elif tok == "(":
                ops.append(tok)
            else:
                raise CalcError
        elif tok == ")":
            while ops and ops[-1] != "(":
                reduce_top(ops, values)
            if not ops:
                raise CalcError
            ops.pop()
        elif tok is not None and tok in PRECEDENCE:
            prec = PRECEDENCE[tok]
            while ops and ops[-1] != "(" and PRECEDENCE[ops[-1]] >= prec:
                reduce_top(ops, values)
            ops.append(tok)
            expect_operand = True
        else:
            # A number or '(' directly after an operand.
            raise CalcError

    if expect_operand:
        raise CalcError
    while ops:
        if ops[-1] == "(":
            raise CalcError
        reduce_top(ops, values)
    return values[0]


def main() -> None:
    data = sys.stdin.buffer.read().decode("latin-1")
    out: list[str] = []
    for line in data.split("\n"):
        if BLANK_RE.fullmatch(line):
            continue
        try:
            out.append(str(evaluate(line)))
        except CalcError:
            out.append("error")
    if out:
        sys.stdout.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
