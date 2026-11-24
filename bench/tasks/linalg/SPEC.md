# linalg

Command-line program `./app` (no arguments): dense linear algebra on a symmetric positive-definite
matrix.

Standard input:

- Line 1: `n`, with 1 ≤ n ≤ 300.
- Next `n` lines: the rows of a symmetric positive-definite matrix `A` (`n` numbers each).
- Last line: a vector `b` of `n` numbers.

Output four lines:

1. `ln(det A)`, the natural logarithm of the determinant of `A`;
2. the solution `x` of `A x = b`, as `n` numbers separated by spaces;
3. the eigenvalues of `A` in ascending order, as `n` numbers separated by spaces;
4. the Frobenius norm of `A`.

Print each number with at least 10 significant digits. Answers are compared with a relative tolerance
of 1e-6 (absolute below 1). Exit with status 0.

Example — input:

```
2
2 0
0 8
2 4
```

prints:

```
2.772588722
1 0.5
2 8
8.246211251
```
