pragma circom 2.2.3;

// Decomposes `in` into a one-hot vector over the digits 1..n:
// out[k] == 1 iff in == k + 1. Unsatisfiable unless 1 <= in <= n.
template OneHotDigit(n) {
    signal input in;
    signal output out[n];

    var sum = 0;
    var value = 0;
    for (var k = 0; k < n; k++) {
        out[k] <-- in == k + 1 ? 1 : 0;
        out[k] * (out[k] - 1) === 0;
        sum += out[k];
        value += (k + 1) * out[k];
    }
    // Exactly one bit set, and it encodes `in`.
    sum === 1;
    in === value;
}

// Proves knowledge of a valid Sudoku solution for `puzzle`.
// Grid side is b*b, with b×b boxes; cells are row-major, 0 marks an empty puzzle cell.
template Sudoku(b) {
    var n = b * b;

    signal input puzzle[n * n];
    signal input solution[n * n];

    // 1. Every solution cell is a digit 1..n (enforced by the one-hot decomposition).
    signal digit[n * n][n];
    for (var i = 0; i < n * n; i++) {
        digit[i] <== OneHotDigit(n)(solution[i]);
    }

    // 2. Solution agrees with every clue: puzzle == 0 or puzzle == solution.
    for (var i = 0; i < n * n; i++) {
        puzzle[i] * (puzzle[i] - solution[i]) === 0;
    }

    // 3. Each row, column and box contains every digit exactly once.
    for (var g = 0; g < n; g++) {
        for (var k = 0; k < n; k++) {
            var inRow = 0;
            var inCol = 0;
            var inBox = 0;
            for (var j = 0; j < n; j++) {
                inRow += digit[g * n + j][k];
                inCol += digit[j * n + g][k];
                var r = (g \ b) * b + j \ b;
                var c = (g % b) * b + j % b;
                inBox += digit[r * n + c][k];
            }
            inRow === 1;
            inCol === 1;
            inBox === 1;
        }
    }
}
