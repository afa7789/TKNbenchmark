pragma circom 2.2.3;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";

// Constrains `age` and `threshold` to be n-bit unsigned integers with
// age >= threshold.
template AgeAtLeast(n) {
    // LessThan-family comparators are only sound for n <= 252.
    assert(n > 0 && n <= 252);

    signal input age;
    signal input threshold;

    // Range checks: both values must lie in [0, 2^n - 1]. These are also the
    // preconditions for GreaterEqThan(n) to be sound.
    _ <== Num2Bits(n)(age);
    _ <== Num2Bits(n)(threshold);

    signal ok <== GreaterEqThan(n)([age, threshold]);
    ok === 1;
}
