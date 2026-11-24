fn group_ok(a: u8, b: u8, c: u8, d: u8) -> bool {
    let seen = (1 << (a - 1)) | (1 << (b - 1)) | (1 << (c - 1)) | (1 << (d - 1));
    seen == 15
}

fn main(puzzle: pub [u8; 16], solution: [u8; 16]) {
    for i in 0..16 {
        assert((solution[i] >= 1) & (solution[i] <= 4));
        if puzzle[i] != 0 {
            assert(solution[i] == puzzle[i]);
        }
    }
    for k in 0..4 {
        assert(group_ok(solution[k * 4], solution[k * 4 + 1], solution[k * 4 + 2], solution[k * 4 + 3]));
        assert(group_ok(solution[k], solution[4 + k], solution[8 + k], solution[12 + k]));
        let r = (k / 2) * 2;
        let c = (k % 2) * 2;
        assert(group_ok(solution[r * 4 + c], solution[r * 4 + c + 1], solution[(r + 1) * 4 + c], solution[(r + 1) * 4 + c + 1]));
    }
}
