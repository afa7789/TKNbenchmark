pragma circom 2.1.6;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";

// Proves that a private `age` lies in [0, 2^n) and is at least the public
// `threshold`, which itself must lie in [0, 2^n).
template RangeAtLeast(n) {
    // circomlib comparators are only sound for n <= 252.
    assert(n <= 252);

    signal input age;
    signal input threshold;

    // Range-check both inputs: Num2Bits(n) is satisfiable iff 0 <= x < 2^n,
    // which also excludes any large field element. This is required for
    // the soundness of the comparator below.
    _ <== Num2Bits(n)(age);
    _ <== Num2Bits(n)(threshold);

    // age >= threshold
    signal ok <== GreaterEqThan(n)([age, threshold]);
    ok === 1;
}

component main {public [threshold]} = RangeAtLeast(8);
