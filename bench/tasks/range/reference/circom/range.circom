pragma circom 2.1.0;

template Num2Bits(n) {
    signal input in;
    signal output out[n];
    var acc = 0;
    var e = 1;
    for (var i = 0; i < n; i++) {
        out[i] <-- (in >> i) & 1;
        out[i] * (out[i] - 1) === 0;
        acc += out[i] * e;
        e = e + e;
    }
    acc === in;
}

template Range() {
    signal input age;
    signal input threshold;
    component a = Num2Bits(8);
    a.in <== age;
    component t = Num2Bits(8);
    t.in <== threshold;
    // age - threshold + 256 is in [1, 511]; its bit 8 is set exactly when age >= threshold.
    component d = Num2Bits(9);
    d.in <== age - threshold + 256;
    d.out[8] === 1;
}

component main {public [threshold]} = Range();
