pragma circom 2.2.3;

include "../sudoku.circom";

// 4×4 Sudoku (2×2 boxes).
component main {public [puzzle]} = Sudoku(2);
