package store

import (
	"slices"
	"testing"
)

func TestStore(t *testing.T) {
	s := New()
	if !s.Put("b", []byte("1")) {
		t.Fatal("first put should create")
	}
	if s.Put("b", []byte("2")) {
		t.Fatal("second put should replace")
	}
	s.Put("a", nil)
	if v, ok := s.Get("b"); !ok || string(v) != "2" {
		t.Fatalf("Get(b) = %q, %v", v, ok)
	}
	if got := s.Keys(); !slices.Equal(got, []string{"a", "b"}) {
		t.Fatalf("Keys() = %v", got)
	}
	if !s.Delete("a") || s.Delete("a") {
		t.Fatal("delete semantics wrong")
	}
	if _, ok := s.Get("a"); ok {
		t.Fatal("deleted key still present")
	}
}
