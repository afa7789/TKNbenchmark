package calc

import "core:testing"

@(test)
test_values :: proc(t: ^testing.T) {
	ev: Evaluator
	evaluator_init(&ev)
	defer evaluator_destroy(&ev)

	Case :: struct {
		src:  string,
		want: i64,
	}
	for c in ([]Case{
		{"1 + 2 * 3", 7},
		{"-7 / 2", -3},
		{"-7 % 3", -1},
		{"7 % -3", 1},
		{"10 - 4 - 3", 3},
		{"--5", 5},
		{"-(2 + 3)", -5},
		{"(-9223372036854775807 - 1) % -1", 0},
		{"-9223372036854775807 - 1", min(i64)},
	}) {
		got, err := evaluate(&ev, c.src)
		testing.expectf(t, err == .None && got == c.want, "%q: got %v (%v), want %v", c.src, got, err, c.want)
	}
}

@(test)
test_errors :: proc(t: ^testing.T) {
	ev: Evaluator
	evaluator_init(&ev)
	defer evaluator_destroy(&ev)

	for src in ([]string{
		"(1 + 2", "1 +", "abc", "()", "1 2", "+1", ")(", "1\r",
		"1 / 0", "5 % 0",
		"9223372036854775808", "9223372036854775807 + 1",
		"(-9223372036854775807 - 1) / -1", "-(-9223372036854775807 - 1)",
	}) {
		_, err := evaluate(&ev, src)
		testing.expectf(t, err != .None, "%q: expected error", src)
	}
}
