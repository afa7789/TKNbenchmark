package wordfreq

import (
	"slices"
	"strings"
	"testing"
	"testing/iotest"
)

func count(t *testing.T, input string, chunked bool) []WordCount {
	t.Helper()
	c := NewCounter()
	r := strings.NewReader(input)
	var err error
	if chunked {
		_, err = c.ReadFrom(iotest.OneByteReader(r))
	} else {
		_, err = c.ReadFrom(r)
	}
	if err != nil {
		t.Fatalf("ReadFrom: %v", err)
	}
	return c.Top(10)
}

func TestTop(t *testing.T) {
	tests := []struct {
		name  string
		input string
		want  []WordCount
	}{
		{"empty", "", []WordCount{}},
		{"no words", "123 _' \xff\xc3(", []WordCount{}},
		{"simple", "The cat and the hat.", []WordCount{{"the", 2}, {"and", 1}, {"cat", 1}, {"hat", 1}}},
		{"folding", "Hello, hello! HELLO? world.\n", []WordCount{{"hello", 3}, {"world", 1}}},
		{"separators", "don't stop_me 4now, now-NOW", []WordCount{{"now", 3}, {"don", 1}, {"me", 1}, {"stop", 1}, {"t", 1}}},
		{"high bytes", "caf\xe9 caf", []WordCount{{"caf", 2}}},
		{"limit", "zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha",
			[]WordCount{{"alpha", 2}, {"beta", 1}, {"eta", 1}, {"iota", 1}, {"kappa", 1}, {"lambda", 1}, {"mu", 1}, {"nu", 1}, {"omicron", 1}, {"pi", 1}}},
		{"prefix order", "ab a abc", []WordCount{{"a", 1}, {"ab", 1}, {"abc", 1}}},
	}
	for _, tt := range tests {
		for _, chunked := range []bool{false, true} {
			got := count(t, tt.input, chunked)
			if !slices.Equal(got, tt.want) {
				t.Errorf("%s (chunked=%v): got %v, want %v", tt.name, chunked, got, tt.want)
			}
		}
	}
}

func TestLongWordAcrossChunks(t *testing.T) {
	w := strings.Repeat("Ab", readChunk)
	got := count(t, w+" "+w+" x", false)
	want := []WordCount{{strings.ToLower(w), 2}, {"x", 1}}
	if !slices.Equal(got, want) {
		t.Errorf("got %d entries, want long word counted twice", len(got))
	}
}
