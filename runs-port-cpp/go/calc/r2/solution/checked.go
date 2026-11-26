package main

import "math"

// Checked 64-bit arithmetic: each function reports ok == false when the exact
// result is not representable or the operation is undefined.

func checkedAdd(a, b int64) (int64, bool) {
	s := a + b
	// Overflow iff both operands share a sign that the sum does not.
	return s, (a^s)&(b^s) >= 0
}

func checkedSub(a, b int64) (int64, bool) {
	d := a - b
	// Overflow iff the operands differ in sign and the result's sign differs from a.
	return d, (a^b)&(a^d) >= 0
}

func checkedMul(a, b int64) (int64, bool) {
	if a == 0 || b == 0 {
		return 0, true
	}
	p := a * b
	if (a == -1 && b == math.MinInt64) || (b == -1 && a == math.MinInt64) || p/b != a {
		return 0, false
	}
	return p, true
}

func checkedDiv(a, b int64) (int64, bool) {
	if b == 0 || (a == math.MinInt64 && b == -1) {
		return 0, false
	}
	return a / b, true
}

func checkedRem(a, b int64) (int64, bool) {
	if b == 0 {
		return 0, false
	}
	if b == -1 {
		return 0, true // MinInt64 % -1 is 0 mathematically.
	}
	return a % b, true
}

func checkedNeg(a int64) (int64, bool) {
	if a == math.MinInt64 {
		return 0, false
	}
	return -a, true
}
