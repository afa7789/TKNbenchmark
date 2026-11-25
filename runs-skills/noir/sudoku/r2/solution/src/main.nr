//! Proves knowledge of a solution to a public 4x4 Sudoku puzzle.

global SIZE: u32 = 4;
global CELLS: u32 = 16;

/// Cell indices (row-major) of every row, column and 2x2 box.
global GROUPS: [[u32; SIZE]; 3 * SIZE] = [
    // rows
    [0, 1, 2, 3],
    [4, 5, 6, 7],
    [8, 9, 10, 11],
    [12, 13, 14, 15],
    // columns
    [0, 4, 8, 12],
    [1, 5, 9, 13],
    [2, 6, 10, 14],
    [3, 7, 11, 15],
    // boxes
    [0, 1, 4, 5],
    [2, 3, 6, 7],
    [8, 9, 12, 13],
    [10, 11, 14, 15],
];

/// `puzzle`: public clues, `0` for an empty cell.
/// `solution`: private filled grid.
fn main(puzzle: pub [u8; CELLS], solution: [u8; CELLS]) {
    for i in 0..CELLS {
        let cell = solution[i];
        assert((1 <= cell) & (cell <= SIZE as u8), "solution cell out of range");

        let clue = puzzle[i];
        assert((clue == 0) | (clue == cell), "solution disagrees with a clue");
    }

    // With every cell in 1..=4, four pairwise-distinct cells are exactly {1, 2, 3, 4}.
    for g in 0..GROUPS.len() {
        let group = GROUPS[g];
        for a in 0..SIZE {
            for b in (a + 1)..SIZE {
                assert(solution[group[a]] != solution[group[b]], "duplicate value in a group");
            }
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

#[test(should_fail_with = "disagrees with a clue")]
fn rejects_clue_mismatch() {
    main(
        [1, 3, 0, 4, 0, 4, 1, 0, 2, 0, 0, 3, 0, 3, 2, 0],
        [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
    );
}

#[test(should_fail_with = "out of range")]
fn rejects_zero_cell() {
    main([0; CELLS], [0, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "out of range")]
fn rejects_large_cell() {
    main([0; CELLS], [5, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "duplicate")]
fn rejects_row_duplicate() {
    main([0; CELLS], [3, 2, 3, 4, 1, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "duplicate")]
fn rejects_column_duplicate() {
    // Rows are permutations, but columns repeat.
    main([0; CELLS], [1, 2, 3, 4, 1, 2, 3, 4, 3, 4, 1, 2, 3, 4, 1, 2]);
}

#[test(should_fail_with = "duplicate")]
fn rejects_box_duplicate() {
    // Latin square (rows and columns valid) whose 2x2 boxes repeat.
    main([0; CELLS], [1, 2, 3, 4, 2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3]);
}
