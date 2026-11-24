pragma circom 2.1.0;

include "sudoku.circom";

// 4×4 Sudoku: box size 2. The puzzle is public; the solution stays private.
component main {public [puzzle]} = Sudoku(2);
