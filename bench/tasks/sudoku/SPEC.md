# sudoku — prove knowledge of a 4×4 Sudoku solution

Write a circuit with:

- a **public** input `puzzle`: 16 cells in row-major order, `0` for an empty cell, `1`–`4` for a clue;
- a **private** input `solution`: 16 cells in row-major order.

The circuit must be satisfiable exactly when:

1. every cell of `solution` is 1, 2, 3 or 4;
2. `solution` agrees with every non-zero cell of `puzzle`;
3. each row, each column and each of the four 2×2 boxes contains 1, 2, 3 and 4 exactly once.

`build.sh` compiles the circuit. `bash prove.sh input.json` reads a JSON object such as
`{"puzzle": ["1","0",...], "solution": ["1","2",...]}` (16 decimal strings each) and exits 0 if the
circuit is satisfied, non-zero otherwise.

The tests run `prove.sh` on accepted and rejected inputs. Constraints must enforce the rules; checks
done only outside the circuit (for example in `prove.sh`) do not count.
