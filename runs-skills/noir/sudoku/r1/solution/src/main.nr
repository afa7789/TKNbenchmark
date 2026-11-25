//! Proves knowledge of a solution to a public 4x4 Sudoku puzzle.

global SIZE: u32 = 4;
global BOX: u32 = 2;
global CELLS: u32 = SIZE * SIZE;

/// `puzzle`: row-major cells, `0` for empty, `1..=4` for a clue.
/// `solution`: row-major cells, kept private.
fn main(puzzle: pub [Field; CELLS], solution: [Field; CELLS]) {
    for i in 0..CELLS {
        assert_is_digit(solution[i]);
        // Either the cell is empty (0) or the solution matches the clue.
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
        let mut group = [0; SIZE];
        for k in 0..SIZE {
            group[k] = solution[(top + k / BOX) * SIZE + left + k % BOX];
        }
        assert_distinct(group);
    }
}

/// Constrains `x` to be one of 1, 2, 3, 4.
fn assert_is_digit(x: Field) {
    assert_eq((x - 1) * (x - 2) * (x - 3) * (x - 4), 0, "cell is not a digit 1-4");
}

/// Constrains all elements of `group` to be pairwise distinct. Together with
/// `assert_is_digit`, this means the group holds each of 1..=4 exactly once.
fn assert_distinct(group: [Field; SIZE]) {
    for i in 0..SIZE {
        for j in i + 1..SIZE {
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

#[test(should_fail_with = "disagrees with a clue")]
fn rejects_clue_mismatch() {
    main(
        [1, 3, 0, 4, 0, 4, 1, 0, 2, 0, 0, 3, 0, 3, 2, 0],
        [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1],
    );
}

#[test(should_fail_with = "not a digit")]
fn rejects_out_of_range_digit() {
    main([0; CELLS], [1, 2, 3, 4, 3, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 0]);
}

#[test(should_fail_with = "duplicate digit")]
fn rejects_row_duplicate() {
    main([0; CELLS], [3, 2, 3, 4, 1, 4, 1, 2, 2, 1, 4, 3, 4, 3, 2, 1]);
}

#[test(should_fail_with = "duplicate digit")]
fn rejects_box_duplicate() {
    // Rows and columns are Latin, but the 2x2 boxes are not.
    main([0; CELLS], [1, 2, 3, 4, 2, 3, 4, 1, 3, 4, 1, 2, 4, 1, 2, 3]);
}
