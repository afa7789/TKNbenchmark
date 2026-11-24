pragma circom 2.1.0;

// Decomposes `in` into a one-hot vector over the digits 1..n.
// Satisfiable only if `in` is one of 1, 2, ..., n; then out[d] == 1 iff in == d + 1.
template OneHotDigit(n) {
    signal input in;
    signal output out[n];

    var count = 0;
    var value = 0;
    for (var d = 0; d < n; d++) {
        out[d] <-- in == d + 1 ? 1 : 0;
        out[d] * (out[d] - 1) === 0;
        count += out[d];
        value += (d + 1) * out[d];
    }
    count === 1;
    value === in;
}

// Proves knowledge of a solution to a Sudoku of box size b (grid side n = b*b).
//   puzzle   : n*n cells, row-major, 0 = empty, otherwise the clue digit.
//   solution : n*n cells, row-major, each a digit in 1..n.
// Constraints:
//   1. every solution cell is a digit in 1..n;
//   2. the solution matches every non-zero puzzle cell;
//   3. each row, column and b×b box contains every digit exactly once.
template Sudoku(b) {
    var n = b * b;

    signal input puzzle[n * n];
    signal input solution[n * n];

    // (1) Range check via one-hot decomposition: digit[i][d] == 1 iff solution[i] == d + 1.
    component digit[n * n];
    for (var i = 0; i < n * n; i++) {
        digit[i] = OneHotDigit(n);
        digit[i].in <== solution[i];
    }

    // (2) Clue agreement: puzzle[i] == 0 or puzzle[i] == solution[i].
    for (var i = 0; i < n * n; i++) {
        puzzle[i] * (puzzle[i] - solution[i]) === 0;
    }

    // (3) Each group has n cells; every digit appearing exactly once is
    // equivalent to each digit's indicator summing to 1 over the group.
    for (var g = 0; g < n; g++) {
        var boxRow = (g \ b) * b;
        var boxCol = (g % b) * b;
        for (var d = 0; d < n; d++) {
            var inRow = 0;
            var inCol = 0;
            var inBox = 0;
            for (var k = 0; k < n; k++) {
                inRow += digit[g * n + k].out[d];
                inCol += digit[k * n + g].out[d];
                inBox += digit[(boxRow + k \ b) * n + boxCol + k % b].out[d];
            }
            inRow === 1;
            inCol === 1;
            inBox === 1;
        }
    }
}
