pragma circom 2.2.3;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";

// Proves that a private `age` and a public `threshold` are both n-bit
// unsigned integers (0 <= x < 2^n) and that age >= threshold.
template AgeAtLeast(n) {
    assert(n > 0 && n <= 252);

    signal input age;        // private
    signal input threshold;  // public

    // Range checks: rejects values >= 2^n, including large field elements
    // (Num2Bits(n) with n < 254 has no aliasing).
    _ <== Num2Bits(n)(age);
    _ <== Num2Bits(n)(threshold);

    // Comparison is sound only because both inputs are range-checked above.
    signal ok <== GreaterEqThan(n)([age, threshold]);
    ok === 1;
}
