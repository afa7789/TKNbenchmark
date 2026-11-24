//! Proves knowledge of a solution to a 4x4 Sudoku puzzle without revealing it.

global N: u32 = 4;
global BOX: u32 = 2;
global CELLS: u32 = N * N;

/// `puzzle`: public clues in row-major order, `0` marks an empty cell.
/// `solution`: private filled grid in row-major order.
fn main(puzzle: pub [u8; CELLS], solution: [u8; CELLS]) {
    for i in 0..CELLS {
        let value = solution[i];
        assert((1 <= value) & (value <= N as u8), "solution cell out of range");

        let clue = puzzle[i];
        assert((clue == 0) | (clue == value), "solution disagrees with clue");
    }

    for k in 0..N {
        let mut row = [0; N];
        let mut col = [0; N];
        let mut sub = [0; N];
        let box_row = (k / BOX) * BOX;
        let box_col = (k % BOX) * BOX;
        for j in 0..N {
            row[j] = solution[k * N + j];
            col[j] = solution[j * N + k];
            sub[j] = solution[(box_row + j / BOX) * N + box_col + j % BOX];
        }
        assert_distinct(row);
        assert_distinct(col);
        assert_distinct(sub);
    }
}

/// Given values already constrained to 1..=N, pairwise distinctness means the
/// group holds each of 1..=N exactly once.
fn assert_distinct(group: [u8; N]) {
    for i in 0..N {
        for j in (i + 1)..N {
            assert(group[i] != group[j], "duplicate value in row, column or box");
        }
    }
}

global PUZZLE: [u8; CELLS] = [1, 0, 0, 4, 0, 4, 1, 0, 2, 0, 0, 3, 0, 3, 2, 0];
global SOLUTION: [u8; CELLS] = [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1];

#[test]
fn test_valid_solution() {
    main(PUZZLE, SOLUTION);
}

#[test]
fn test_empty_puzzle() {
    main([0; CELLS], SOLUTION);
}

#[test(should_fail_with = "solution disagrees with clue")]
fn test_disagrees_with_clue() {
    let mut puzzle = PUZZLE;
    puzzle[1] = 3;
    main(puzzle, SOLUTION);
}

#[test(should_fail_with = "solution cell out of range")]
fn test_zero_cell() {
    let mut solution = SOLUTION;
    solution[5] = 0;
    main([0; CELLS], solution);
}

#[test(should_fail_with = "solution cell out of range")]
fn test_large_cell() {
    let mut solution = SOLUTION;
    solution[0] = 5;
    main([0; CELLS], solution);
}

#[test(should_fail_with = "duplicate value in row, column or box")]
fn test_row_duplicate() {
    let mut solution = SOLUTION;
    solution[0] = 3;
    main([0; CELLS], solution);
}

#[test(should_fail_with = "duplicate value in row, column or box")]
fn test_latin_square_with_bad_boxes() {
    // Rows and columns are permutations, but the 2x2 boxes are not.
    let solution = [1, 2, 3, 4, 2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3];
    main([0; CELLS], solution);
}
