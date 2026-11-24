pragma circom 2.1.6;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";

// Proves that a private `age` and a public `threshold` are both 8-bit
// unsigned integers (0..255) and that age >= threshold.
template AgeAtLeast(n) {
    signal input age;        // private
    signal input threshold;  // public

    // Range-check both inputs to [0, 2^n). This is required for soundness:
    // GreaterEqThan(n) assumes its operands already fit in n bits.
    _ = Num2Bits(n)(age);
    _ = Num2Bits(n)(threshold);

    signal ok <== GreaterEqThan(n)([age, threshold]);
    ok === 1;
}

component main { public [threshold] } = AgeAtLeast(8);
