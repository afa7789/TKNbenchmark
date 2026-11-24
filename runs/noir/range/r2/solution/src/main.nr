/// Proves that a private `age` is a byte-sized integer that is at least the
/// public byte-sized `threshold`.
///
/// Inputs are taken as `Field`s and range-checked in-circuit, so that the
/// constraints themselves (not ABI decoding) reject out-of-range values such as
/// 256 or arbitrary large field elements.
fn main(age: Field, threshold: pub Field) {
    let age = to_u8(age);
    let threshold = to_u8(threshold);
    assert(age >= threshold, "age is below threshold");
}

/// Constrains `x` to fit in 8 bits and returns it as a `u8`.
fn to_u8(x: Field) -> u8 {
    x.assert_max_bit_size::<8>();
    x as u8
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

#[test(should_fail)]
fn rejects_age_out_of_range() {
    main(256, 18);
}

#[test(should_fail)]
fn rejects_threshold_out_of_range() {
    main(255, 256);
}

#[test(should_fail)]
fn rejects_huge_field_element() {
    // p - 1, i.e. "-1" in the field.
    main(-1, 0);
}

#[test(should_fail)]
fn rejects_wrapped_age() {
    // 256 + 20 would truncate to 20 >= 18 without the range check.
    main(276, 18);
}
