pragma circom 2.2.3;

include "../sudoku.circom";

component main {public [puzzle]} = Sudoku4x4();
