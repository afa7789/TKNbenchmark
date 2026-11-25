//! Proves knowledge of a solution to a public 4x4 Sudoku puzzle.

global SIZE: u32 = 4;
global BOX: u32 = 2;
global CELLS: u32 = SIZE * SIZE;

/// `puzzle`: row-major clues, `0` for an empty cell.
/// `solution`: row-major filled grid (private witness).
fn main(puzzle: pub [Field; CELLS], solution: [Field; CELLS]) {
    for i in 0..CELLS {
        assert_digit(solution[i]);
        // Either the cell is empty (clue == 0) or the clue matches the solution.
        assert_eq(puzzle[i] * (puzzle[i] - solution[i]), 0, "solution disagrees with a clue");
    }

    for r in 0..SIZE {
        let mut row = [0; SIZE];
        for c in 0..SIZE {
            row[c] = solution[r * SIZE + c];
        }
        assert_distinct(row);
    }

    for c in 0..SIZE {
        let mut col = [0; SIZE];
        for r in 0..SIZE {
            col[r] = solution[r * SIZE + c];
        }
        assert_distinct(col);
    }

    for b in 0..SIZE {
        let top = (b / BOX) * BOX;
        let left = (b % BOX) * BOX;
        let mut cells = [0; SIZE];
        for k in 0..SIZE {
            cells[k] = solution[(top + k / BOX) * SIZE + left + k % BOX];
        }
        assert_distinct(cells);
    }
}

/// Constrains `x` to be one of 1, 2, 3, 4.
fn assert_digit(x: Field) {
    assert_eq((x - 1) * (x - 2) * (x - 3) * (x - 4), 0, "cell is not a digit 1-4");
}

/// Constrains all values to be pairwise distinct. Given every value is a digit
/// in 1..=SIZE, a group of SIZE distinct digits contains each digit exactly once.
fn assert_distinct(group: [Field; SIZE]) {
    for i in 0..SIZE {
        for j in i + 1..SIZE {
            assert(group[i] != group[j], "duplicate digit in a row, column or box");
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

#[test(should_fail_with = "disagrees")]
fn rejects_clue_mismatch() {
    main(
        [1, 3, 0, 4, 0, 4, 1, 0, 2, 0, 0, 3, 0, 3, 2, 0],
        [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
    );
}

#[test(should_fail_with = "not a digit")]
fn rejects_out_of_range() {
    main([0; CELLS], [0, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "duplicate")]
fn rejects_row_duplicate() {
    main([0; CELLS], [3, 2, 3, 4, 1, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "duplicate")]
fn rejects_box_duplicate() {
    // Latin square (rows and columns valid) whose 2x2 boxes repeat digits.
    main([0; CELLS], [1, 2, 3, 4, 2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3]);
}
