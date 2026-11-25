pragma circom 2.2.3;

include "../range.circom";

// age is private; threshold is public. Both are bytes (0..255).
component main {public [threshold]} = AgeAtLeast(8);
