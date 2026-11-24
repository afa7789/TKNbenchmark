/// Proves that a private `age` is at least the public `threshold`.
///
/// Both inputs are `u8`, so the compiler range-constrains each of them to
/// `[0, 255]` in-circuit; any larger value (including huge field elements)
/// makes the circuit unsatisfiable.
fn main(age: u8, threshold: pub u8) {
    assert(age >= threshold, "age is below threshold");
}

#[test]
fn test_above_threshold() {
    main(25, 18);
}

#[test]
fn test_equal_to_threshold() {
    main(18, 18);
}

#[test]
fn test_bounds() {
    main(0, 0);
    main(255, 0);
    main(255, 255);
}

#[test(should_fail_with = "age is below threshold")]
fn test_below_threshold() {
    main(17, 18);
}

#[test(should_fail_with = "age is below threshold")]
fn test_max_threshold() {
    main(254, 255);
}
