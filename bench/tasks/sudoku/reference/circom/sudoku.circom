pragma circom 2.1.0;

template InSet() {
    signal input v;
    signal a;
    signal b;
    a <== (v - 1) * (v - 2);
    b <== (v - 3) * (v - 4);
    a * b === 0;
}

// With every value in {1,2,3,4}, sum 10 and product 24 hold only for a permutation of 1..4.
template Group() {
    signal input c[4];
    signal p1;
    signal p2;
    p1 <== c[0] * c[1];
    p2 <== c[2] * c[3];
    p1 * p2 === 24;
    c[0] + c[1] + c[2] + c[3] === 10;
}

template Sudoku() {
    signal input puzzle[16];
    signal input solution[16];
    component inSet[16];
    for (var i = 0; i < 16; i++) {
        inSet[i] = InSet();
        inSet[i].v <== solution[i];
        puzzle[i] * (solution[i] - puzzle[i]) === 0;
    }
    component rows[4];
    component cols[4];
    component boxes[4];
    for (var k = 0; k < 4; k++) {
        rows[k] = Group();
        cols[k] = Group();
        boxes[k] = Group();
        for (var j = 0; j < 4; j++) {
            rows[k].c[j] <== solution[k * 4 + j];
            cols[k].c[j] <== solution[j * 4 + k];
            boxes[k].c[j] <== solution[((k \ 2) * 2 + j \ 2) * 4 + (k % 2) * 2 + j % 2];
        }
    }
}

component main {public [puzzle]} = Sudoku();
