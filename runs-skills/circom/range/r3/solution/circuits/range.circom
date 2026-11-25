pragma circom 2.2.3;

include "circomlib/circuits/bitify.circom";
include "circomlib/circuits/comparators.circom";

// Proves 0 <= threshold < 2^n, 0 <= value < 2^n and value >= threshold.
template AtLeast(n) {
    assert(n > 0 && n <= 252);

    signal input value;
    signal input threshold;

    // Range checks: also rule out field elements >= 2^n (incl. "negative" values).
    _ <== Num2Bits(n)(value);
    _ <== Num2Bits(n)(threshold);

    signal ok <== GreaterEqThan(n)([value, threshold]);
    ok === 1;
}
