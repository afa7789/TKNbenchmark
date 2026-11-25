pragma circom 2.2.3;

// One-hot decomposition of a digit in 1..n.
// Constrains `in` to {1, ..., n} and outputs bits with out[k] == 1 iff in == k + 1.
template OneHotDigit(n) {
    signal input in;
    signal output out[n];

    var count = 0;
    var value = 0;
    for (var k = 0; k < n; k++) {
        out[k] <-- in == k + 1 ? 1 : 0;
        out[k] * (out[k] - 1) === 0;
        count += out[k];
        value += (k + 1) * out[k];
    }
    // Exactly one bit set, and it encodes `in`: together these pin out[] uniquely.
    count === 1;
    value === in;
}

// Proves knowledge of a solution to a size x size Sudoku (size = box * box)
// that is consistent with the public clues in `puzzle` (0 = empty cell).
template Sudoku(box) {
    var size = box * box;
    var cells = size * size;

    signal input puzzle[cells];
    signal input solution[cells];

    // Rule 1: every solution cell is a digit 1..size (enforced by the one-hot decomposition).
    signal digit[cells][size];
    for (var i = 0; i < cells; i++) {
        digit[i] <== OneHotDigit(size)(solution[i]);
    }

    // Rule 2: the solution agrees with every non-zero clue.
    // Any clue outside 1..size cannot be matched, since solution cells are in 1..size.
    for (var i = 0; i < cells; i++) {
        puzzle[i] * (solution[i] - puzzle[i]) === 0;
    }

    // Rule 3: every row, column and box contains each digit exactly once.
    for (var g = 0; g < size; g++) {
        for (var d = 0; d < size; d++) {
            var inRow = 0;
            var inCol = 0;
            var inBox = 0;
            for (var j = 0; j < size; j++) {
                inRow += digit[g * size + j][d];
                inCol += digit[j * size + g][d];
                var r = (g \ box) * box + j \ box;
                var c = (g % box) * box + j % box;
                inBox += digit[r * size + c][d];
            }
            inRow === 1;
            inCol === 1;
            inBox === 1;
        }
    }
}
