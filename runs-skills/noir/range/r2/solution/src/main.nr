/// Proves that a private `age` is at least the public `threshold`.
///
/// Both inputs are `u8`, so the circuit range-constrains each of them to
/// `0..=255`; any larger value (including field elements beyond 2^8) makes
/// the circuit unsatisfiable.
fn main(age: u8, threshold: pub u8) {
    assert(age >= threshold, "age is below threshold");
}

#[test]
fn accepts_above_threshold() {
    main(25, 18);
}

#[test]
fn accepts_equal_to_threshold() {
    main(18, 18);
}

#[test]
fn accepts_bounds() {
    main(0, 0);
    main(255, 0);
    main(255, 255);
}

#[test(should_fail_with = "age is below threshold")]
fn rejects_below_threshold() {
    main(17, 18);
}

#[test(should_fail_with = "age is below threshold")]
fn rejects_zero_age_with_max_threshold() {
    main(0, 255);
}
