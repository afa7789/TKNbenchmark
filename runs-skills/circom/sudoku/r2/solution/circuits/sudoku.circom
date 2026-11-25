pragma circom 2.2.3;

// 4x4 Sudoku verifier.
//
// Grid cells are in row-major order. A cell index is r*4 + c.
//
// Cost per cell: one square signal (sq = x*x), which is used for both the
// range check and the group checks. That gives 16 quadratic constraints for
// the squares, 16 for the range checks and 16 for the clue checks. The 24
// group constraints are linear.

// Enforces x ∈ {1, 2, 3, 4}, with sq = x*x supplied by the caller.
//   (x-1)(x-2)(x-3)(x-4) = (sq - 3x + 2) * (sq - 7x + 12) = 0
template AssertDigit4() {
    signal input x;
    signal input sq;
    sq === x * x;
    (sq - 3 * x + 2) * (sq - 7 * x + 12) === 0;
}

// Given four values that are already known to be in {1, 2, 3, 4} and their
// squares, enforces that they are a permutation of {1, 2, 3, 4}.
//
// The only multisets of four values from {1..4} that sum to 10 are
// {1,1,4,4}, {1,2,3,4}, {1,3,3,3}, {2,2,2,4} and {2,2,3,3}. Their sums of
// squares are 34, 30, 28, 28 and 26, so sum = 10 together with
// sum of squares = 30 holds only for {1,2,3,4}. Both constraints are linear.
template AssertPermutation4() {
    signal input x[4];
    signal input sq[4];
    var s = 0;
    var s2 = 0;
    for (var i = 0; i < 4; i++) {
        s += x[i];
        s2 += sq[i];
    }
    s === 10;
    s2 === 30;
}

template Sudoku4x4() {
    signal input puzzle[16];    // public: 0 = empty, 1..4 = clue
    signal input solution[16];  // private

    signal sq[16];
    component digit[16];
    for (var i = 0; i < 16; i++) {
        sq[i] <== solution[i] * solution[i];

        // Rule 1: every cell is 1, 2, 3 or 4.
        digit[i] = AssertDigit4();
        digit[i].x <== solution[i];
        digit[i].sq <== sq[i];

        // Rule 2: the solution matches every clue.
        //   puzzle = 0: no constraint; puzzle != 0: solution = puzzle.
        // A clue outside 1..4 can't be satisfied, because the solution
        // cell is already restricted to 1..4.
        puzzle[i] * (solution[i] - puzzle[i]) === 0;
    }

    // Rule 3: every row, column and 2x2 box is a permutation of 1..4.
    component row[4];
    component col[4];
    component box[4];
    for (var g = 0; g < 4; g++) {
        row[g] = AssertPermutation4();
        col[g] = AssertPermutation4();
        box[g] = AssertPermutation4();
        var br = (g \ 2) * 2;   // top row of box g
        var bc = (g % 2) * 2;   // left column of box g
        for (var k = 0; k < 4; k++) {
            var ri = g * 4 + k;                              // row g, column k
            var ci = k * 4 + g;                              // row k, column g
            var bi = (br + k \ 2) * 4 + (bc + k % 2);        // k-th cell of box g
            row[g].x[k] <== solution[ri];  row[g].sq[k] <== sq[ri];
            col[g].x[k] <== solution[ci];  col[g].sq[k] <== sq[ci];
            box[g].x[k] <== solution[bi];  box[g].sq[k] <== sq[bi];
        }
    }
}
