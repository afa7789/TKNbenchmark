pragma circom 2.2.3;

include "../range.circom";

// age is private, threshold is public; both must fit in 8 bits (0..255).
template Range() {
    signal input age;
    signal input threshold;

    AtLeast(8)(age, threshold);
}

component main {public [threshold]} = Range();
