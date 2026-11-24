//! Proves knowledge of a solution to a public 4x4 Sudoku puzzle.

global N: u32 = 4;
global CELLS: u32 = N * N;
global BOX: u32 = 2;

/// `puzzle` holds the clues in row-major order (0 = empty cell),
/// `solution` is the private, fully filled grid in row-major order.
fn main(puzzle: pub [u8; CELLS], solution: [u8; CELLS]) {
    for i in 0..CELLS {
        let v = solution[i];
        assert((1 <= v) & (v <= N as u8), "solution cell out of range");
        let clue = puzzle[i];
        assert((clue == 0) | (clue == v), "solution disagrees with puzzle");
    }

    for r in 0..N {
        assert_group(solution, |k| r * N + k);
    }
    for c in 0..N {
        assert_group(solution, |k| k * N + c);
    }
    for b in 0..N {
        let top = (b / BOX) * BOX;
        let left = (b % BOX) * BOX;
        assert_group(solution, |k| (top + k / BOX) * N + left + k % BOX);
    }
}

/// Asserts that the N cells selected by `index` are pairwise distinct.
/// Combined with the 1..=N range check, this means they hold each digit exactly once.
fn assert_group<Env>(grid: [u8; CELLS], index: fn[Env](u32) -> u32) {
    for i in 0..N {
        for j in (i + 1)..N {
            assert(grid[index(i)] != grid[index(j)], "duplicate digit in row, column or box");
        }
    }
}

fn is_valid(puzzle: [u8; CELLS], solution: [u8; CELLS]) {
    main(puzzle, solution);
}

global PUZZLE: [u8; CELLS] = [1, 0, 0, 4, 0, 4, 1, 0, 2, 0, 0, 3, 0, 3, 2, 0];
global SOLUTION: [u8; CELLS] = [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1];

#[test]
fn test_valid_solution() {
    is_valid(PUZZLE, SOLUTION);
}

#[test]
fn test_empty_puzzle() {
    is_valid([0; CELLS], SOLUTION);
}

#[test(should_fail_with = "solution disagrees with puzzle")]
fn test_disagrees_with_clue() {
    let mut puzzle = PUZZLE;
    puzzle[1] = 3;
    is_valid(puzzle, SOLUTION);
}

#[test(should_fail_with = "solution cell out of range")]
fn test_zero_cell() {
    let mut solution = SOLUTION;
    solution[1] = 0;
    is_valid([0; CELLS], solution);
}

#[test(should_fail_with = "solution cell out of range")]
fn test_cell_too_large() {
    let mut solution = SOLUTION;
    solution[1] = 5;
    is_valid([0; CELLS], solution);
}

#[test(should_fail_with = "duplicate digit")]
fn test_row_duplicate() {
    let mut solution = SOLUTION;
    solution[0] = 3;
    is_valid([0; CELLS], solution);
}

#[test(should_fail_with = "duplicate digit")]
fn test_box_duplicate() {
    // Every row and column is a permutation, but the boxes are not.
    let solution = [1, 2, 3, 4, 2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3];
    is_valid([0; CELLS], solution);
}
