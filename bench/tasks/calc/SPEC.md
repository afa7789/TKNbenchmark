# calc

Command-line program `./app` (no arguments): a 64-bit signed integer expression evaluator.

Each line of standard input is one expression. For each line print its value, or `error`.
A line that is empty or holds only spaces/tabs prints nothing. Lines end with `\n`.

Grammar (spaces and tabs may appear between any two tokens):

```
expr    := term    (('+' | '-') term)*
term    := unary   (('*' | '/' | '%') unary)*
unary   := '-' unary | primary
primary := NUMBER | '(' expr ')'
NUMBER  := [0-9]+
```

Operators are left-associative. There is no unary `+`.

Semantics — all values are signed 64-bit integers (−9223372036854775808 … 9223372036854775807):

- `/` truncates toward zero. `%` is the remainder of that division, so its sign follows the dividend
  (`-7 % 3` is `-1`, `7 % -3` is `1`).
- The line prints `error` when **any** of these happens:
  - syntax error (any character outside the grammar, unbalanced parentheses, missing operand…);
  - division or remainder by zero;
  - overflow: a literal greater than 9223372036854775807, or any `+ - * /` or unary `-` whose exact
    result is outside the 64-bit range. (`(-9223372036854775807 - 1) % -1` is `0`, not an error.)
- Exit with status 0.

Example — input:

```
1 + 2 * 3
-7 / 2
(1 + 2
9223372036854775807 + 1
```

prints:

```
7
-3
error
error
```
