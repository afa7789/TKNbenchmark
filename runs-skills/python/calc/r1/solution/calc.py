"""calc: a 64-bit signed integer expression evaluator.

Reads one expression per line from standard input and prints its value,
or ``error`` for syntax errors, division by zero, and 64-bit overflow.

Parsing uses an iterative shunting-yard algorithm, so arbitrarily deep
nesting cannot exhaust the Python call stack.
"""

import re
import sys

INT_MIN = -(1 << 63)
INT_MAX = (1 << 63) - 1
MAX_DIGITS = len(str(INT_MAX))

# One token per match: optional blanks, then a number or any single character.
TOKEN = re.compile(r"[ \t]*(?:([0-9]+)|(.))", re.DOTALL)
BLANK = re.compile(r"[ \t]*")

UNARY_MINUS = "neg"
PRECEDENCE = {"+": 1, "-": 1, "*": 2, "/": 2, "%": 2, UNARY_MINUS: 3}


class CalcError(Exception):
    """Raised for any syntax or arithmetic error in an expression."""


def checked(value: int) -> int:
    if not INT_MIN <= value <= INT_MAX:
        raise CalcError("overflow")
    return value


def truncdiv(a: int, b: int) -> int:
    """Integer division truncating toward zero."""
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def apply(op: str, values: list[int]) -> None:
    """Pop the operands of ``op`` from ``values`` and push the result."""
    if op == UNARY_MINUS:
        values.append(checked(-values.pop()))
        return
    b = values.pop()
    a = values.pop()
    match op:
        case "+":
            result = checked(a + b)
        case "-":
            result = checked(a - b)
        case "*":
            result = checked(a * b)
        case "/":
            if b == 0:
                raise CalcError("division by zero")
            result = checked(truncdiv(a, b))
        case "%":
            if b == 0:
                raise CalcError("division by zero")
            result = a - b * truncdiv(a, b)
        case _:
            raise AssertionError(f"unknown operator {op!r}")
    values.append(result)


def parse_number(digits: str) -> int:
    digits = digits.lstrip("0") or "0"
    if len(digits) > MAX_DIGITS:
        raise CalcError("literal too large")
    return checked(int(digits))


def evaluate(line: str) -> int:
    """Evaluate one expression; raise CalcError if it is invalid."""
    values: list[int] = []
    ops: list[str] = []
    expect_operand = True
    pos, end = 0, len(line)

    while (pos := BLANK.match(line, pos).end()) < end:
        match = TOKEN.match(line, pos)
        assert match is not None  # TOKEN matches any non-empty remainder
        pos = match.end()
        number, char = match.groups()

        if expect_operand:
            if number is not None:
                values.append(parse_number(number))
                expect_operand = False
            elif char == "-":
                ops.append(UNARY_MINUS)
            elif char == "(":
                ops.append("(")
            else:
                raise CalcError("expected operand")
        elif char in ("+", "-", "*", "/", "%"):
            prec = PRECEDENCE[char]
            while ops and ops[-1] != "(" and PRECEDENCE[ops[-1]] >= prec:
                apply(ops.pop(), values)
            ops.append(char)
            expect_operand = True
        elif char == ")":
            while ops and ops[-1] != "(":
                apply(ops.pop(), values)
            if not ops:
                raise CalcError("unbalanced ')'")
            ops.pop()
        else:
            raise CalcError("expected operator")

    if expect_operand:
        raise CalcError("missing operand")
    while ops:
        op = ops.pop()
        if op == "(":
            raise CalcError("unbalanced '('")
        apply(op, values)
    return values.pop()


def main() -> int:
    data = sys.stdin.buffer.read().decode("latin-1")
    out: list[str] = []
    for line in data.split("\n"):
        if not line.strip(" \t"):
            continue
        try:
            out.append(str(evaluate(line)))
        except CalcError:
            out.append("error")
    if out:
        sys.stdout.write("\n".join(out) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
