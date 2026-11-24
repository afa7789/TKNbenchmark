# linreg

Command-line program `./app` (no arguments): ordinary least-squares regression.

Standard input:

- Line 1: `n k` — the number of rows and of features, with 1 ≤ k ≤ 20 and k + 1 ≤ n ≤ 1,000,000.
- Then `n` lines, each with the `k` feature values followed by the response `y`, separated by single
  spaces. The design matrix (a column of ones plus the features) has full column rank, and `y` is not
  constant.

Fit `y ≈ b0 + b1·x1 + … + bk·xk`, minimising the sum of squared residuals.

Output `k + 2` lines: `b0`, `b1`, …, `bk`, then the coefficient of determination
`R² = 1 − SS_res / SS_tot`. Print each number with at least 10 significant digits. Answers are compared
with a relative tolerance of 1e-6 (absolute below 1). Exit with status 0.

Example — input:

```
4 1
0 1
1 3
2 5
3 7
```

prints:

```
1
2
1
```
