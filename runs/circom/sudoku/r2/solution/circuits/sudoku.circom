pragma circom 2.2.3;

// Proves knowledge of a solution to a 4x4 Sudoku puzzle.
//
// Each solution cell is decoded into a one-hot vector over the digits 1..4.
// The one-hot decoding alone enforces the digit range, and every row, column
// and 2x2 box is then checked by requiring each digit's indicator to sum to
// exactly 1 over the group's four cells.

// Constrains `in` to be one of 1..N and outputs its one-hot encoding:
// out[d] == 1 iff in == d + 1.
template OneHot(N) {
    signal input in;
    signal output out[N];

    var sum = 0;
    var weighted = 0;
    for (var d = 0; d < N; d++) {
        out[d] <-- in == d + 1 ? 1 : 0;
        out[d] * (out[d] - 1) === 0;
        sum += out[d];
        weighted += (d + 1) * out[d];
    }
    // Exactly one indicator is set, and it is the one at position `in - 1`.
    sum === 1;
    weighted === in;
}

// Constrains the N cells (given as one-hot vectors) to contain every digit
// exactly once.
template AllDigitsOnce(N) {
    signal input cells[N][N];

    for (var d = 0; d < N; d++) {
        var count = 0;
        for (var i = 0; i < N; i++) {
            count += cells[i][d];
        }
        count === 1;
    }
}

template Sudoku() {
    var BOX = 2;
    var N = BOX * BOX;
    var CELLS = N * N;

    signal input puzzle[CELLS];   // public: 0 = empty, 1..N = clue
    signal input solution[CELLS]; // private

    // Rule 1: every solution cell is a digit in 1..N.
    component digit[CELLS];
    for (var c = 0; c < CELLS; c++) {
        digit[c] = OneHot(N);
        digit[c].in <== solution[c];
    }

    // Rule 2: the solution agrees with every clue (puzzle[c] != 0).
    for (var c = 0; c < CELLS; c++) {
        puzzle[c] * (solution[c] - puzzle[c]) === 0;
    }

    // Rule 3: rows, columns and boxes each contain every digit exactly once.
    component rows[N];
    component cols[N];
    component boxes[N];
    for (var g = 0; g < N; g++) {
        rows[g] = AllDigitsOnce(N);
        cols[g] = AllDigitsOnce(N);
        boxes[g] = AllDigitsOnce(N);

        var boxRow = (g \ BOX) * BOX;
        var boxCol = (g % BOX) * BOX;
        for (var i = 0; i < N; i++) {
            var boxCell = (boxRow + i \ BOX) * N + boxCol + i % BOX;
            rows[g].cells[i] <== digit[g * N + i].out;
            cols[g].cells[i] <== digit[i * N + g].out;
            boxes[g].cells[i] <== digit[boxCell].out;
        }
    }
}

component main { public [puzzle] } = Sudoku();
