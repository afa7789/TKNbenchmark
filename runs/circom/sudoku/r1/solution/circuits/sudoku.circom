pragma circom 2.1.0;

// One-hot decomposition of a cell value restricted to {1, ..., n}.
// out[k] == 1 iff in == k + 1. Unsatisfiable for any other value of `in`.
template OneHot(n) {
    signal input in;
    signal output out[n];

    var count = 0;
    var weighted = 0;
    for (var k = 0; k < n; k++) {
        out[k] <-- in == k + 1 ? 1 : 0;
        out[k] * (out[k] - 1) === 0;
        count += out[k];
        weighted += (k + 1) * out[k];
    }
    // Exactly one bit set, and it encodes `in`.
    count === 1;
    weighted === in;
}

// Proves knowledge of a valid solution to a 4x4 Sudoku puzzle.
//   puzzle[i]   : public clue, 0 for empty, 1..4 otherwise (row-major)
//   solution[i] : private solution (row-major)
template Sudoku() {
    var N = 4;      // side length / number of digits
    var B = 2;      // box side length
    var CELLS = N * N;

    signal input puzzle[CELLS];
    signal input solution[CELLS];

    // Rule 1: every solution cell is in {1, 2, 3, 4}, via its one-hot encoding.
    component digit[CELLS];
    for (var i = 0; i < CELLS; i++) {
        digit[i] = OneHot(N);
        digit[i].in <== solution[i];
    }

    // Rule 2: solution agrees with every non-zero clue.
    // puzzle[i] * (solution[i] - puzzle[i]) == 0  <=>  puzzle[i] == 0 or solution[i] == puzzle[i].
    // A clue outside {1..4} can never match a valid solution cell, so it is rejected too.
    for (var i = 0; i < CELLS; i++) {
        puzzle[i] * (solution[i] - puzzle[i]) === 0;
    }

    // Rule 3: in every row, column and box, each digit appears exactly once.
    // With one-hot cells this is linear: for each digit, the group's bits sum to 1.
    for (var g = 0; g < N; g++) {
        for (var k = 0; k < N; k++) {
            var rowSum = 0;
            var colSum = 0;
            var boxSum = 0;
            for (var j = 0; j < N; j++) {
                rowSum += digit[g * N + j].out[k];
                colSum += digit[j * N + g].out[k];
                var r = (g \ B) * B + j \ B;
                var c = (g % B) * B + j % B;
                boxSum += digit[r * N + c].out[k];
            }
            rowSum === 1;
            colSum === 1;
            boxSum === 1;
        }
    }
}

component main {public [puzzle]} = Sudoku();
