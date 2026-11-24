pragma circom 2.1.6;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";

// Proves that a private `age` lies in [0, 255] and is at least the public
// `threshold`, which itself must lie in [0, 255].
template AgeAtLeast(BITS) {
    signal input age;
    signal input threshold;

    // Range-check both operands to BITS bits. This is required for soundness:
    // circomlib comparators assume their inputs already fit in BITS bits.
    component ageBits = Num2Bits(BITS);
    ageBits.in <== age;
    component thresholdBits = Num2Bits(BITS);
    thresholdBits.in <== threshold;

    component ge = GreaterEqThan(BITS);
    ge.in[0] <== age;
    ge.in[1] <== threshold;
    ge.out === 1;
}

component main {public [threshold]} = AgeAtLeast(8);
