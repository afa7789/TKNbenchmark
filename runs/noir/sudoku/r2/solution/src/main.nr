//! Proves knowledge of a solution to a public 4×4 Sudoku puzzle.
//!
//! Cells are stored in row-major order. In `puzzle`, `0` marks an empty cell
//! and `1`–`4` a clue.

global N: u32 = 4;
global BOX: u32 = 2;
global CELLS: u32 = N * N;

fn main(puzzle: pub [u8; CELLS], solution: [u8; CELLS]) {
    for i in 0..CELLS {
        let value = solution[i];
        // Rule 1: every cell holds a digit 1..=4.
        assert((1 <= value) & (value <= N as u8), "solution cell out of range");
        // Rule 2: the solution respects every clue.
        let clue = puzzle[i];
        assert((clue == 0) | (clue == value), "solution disagrees with puzzle clue");
    }

    // Rule 3: every row, column and box is a permutation of 1..=4.
    for r in 0..N {
        assert_distinct(row(solution, r));
    }
    for c in 0..N {
        assert_distinct(column(solution, c));
    }
    for b in 0..N {
        assert_distinct(sub_box(solution, b));
    }
}

fn row(grid: [u8; CELLS], r: u32) -> [u8; N] {
    let mut out = [0; N];
    for c in 0..N {
        out[c] = grid[r * N + c];
    }
    out
}

fn column(grid: [u8; CELLS], c: u32) -> [u8; N] {
    let mut out = [0; N];
    for r in 0..N {
        out[r] = grid[r * N + c];
    }
    out
}

/// Box `b` in row-major order of boxes: 0 = top-left, 3 = bottom-right.
fn sub_box(grid: [u8; CELLS], b: u32) -> [u8; N] {
    let top = (b / BOX) * BOX;
    let left = (b % BOX) * BOX;
    let mut out = [0; N];
    for i in 0..N {
        out[i] = grid[(top + i / BOX) * N + left + i % BOX];
    }
    out
}

/// With all values already constrained to 1..=N, N pairwise-distinct values
/// are exactly a permutation of 1..=N.
fn assert_distinct(group: [u8; N]) {
    for i in 0..N {
        for j in (i + 1)..N {
            assert(group[i] != group[j], "duplicate digit in row, column or box");
        }
    }
}

#[test]
fn accepts_valid_solution() {
    main(
        [1, 0, 0, 4, 0, 4, 1, 0, 2, 0, 0, 3, 0, 3, 2, 0],
        [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
    );
}

#[test]
fn accepts_empty_puzzle() {
    main([0; CELLS], [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "solution disagrees with puzzle clue")]
fn rejects_clue_mismatch() {
    main(
        [1, 3, 0, 4, 0, 4, 1, 0, 2, 0, 0, 3, 0, 3, 2, 0],
        [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
    );
}

#[test(should_fail_with = "solution cell out of range")]
fn rejects_zero_cell() {
    main([0; CELLS], [0, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "solution cell out of range")]
fn rejects_five() {
    main([0; CELLS], [5, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "duplicate digit in row, column or box")]
fn rejects_row_duplicate() {
    main([0; CELLS], [3, 2, 3, 4, 1, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "duplicate digit in row, column or box")]
fn rejects_box_duplicate() {
    // Rows and columns are Latin, but the 2×2 boxes are not.
    main([0; CELLS], [1, 2, 3, 4, 2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3]);
}
