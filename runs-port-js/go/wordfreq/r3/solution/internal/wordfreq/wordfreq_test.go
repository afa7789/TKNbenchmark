package wordfreq

import (
	"reflect"
	"testing"
)

func TestCount(t *testing.T) {
	got := Count([]byte("Don't stop_me 4now, now-NOW\xffcaf\xc3\xa9"))
	want := map[string]int{"don": 1, "t": 1, "stop": 1, "me": 1, "now": 3, "caf": 1}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Count = %v, want %v", got, want)
	}
}

func TestTop(t *testing.T) {
	counts := Count([]byte("zeta eta theta iota kappa lambda mu nu xi omicron pi rho alpha beta alpha"))
	got := Top(counts, 10)
	want := []Entry{
		{"alpha", 2}, {"beta", 1}, {"eta", 1}, {"iota", 1}, {"kappa", 1},
		{"lambda", 1}, {"mu", 1}, {"nu", 1}, {"omicron", 1}, {"pi", 1},
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Top = %v, want %v", got, want)
	}
}

func TestTopEmpty(t *testing.T) {
	if got := Top(Count(nil), 10); len(got) != 0 {
		t.Errorf("Top(empty) = %v, want none", got)
	}
}
