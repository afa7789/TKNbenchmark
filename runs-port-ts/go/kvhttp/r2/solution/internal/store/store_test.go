package store

import (
	"slices"
	"testing"
)

func TestStore(t *testing.T) {
	s := New()
	if got := s.Keys(); got == nil || len(got) != 0 {
		t.Fatalf("Keys on empty store = %#v, want empty non-nil", got)
	}
	if !s.Put("b", []byte("2")) {
		t.Fatal("first Put should report created")
	}
	if s.Put("b", []byte("3")) {
		t.Fatal("second Put should report replaced")
	}
	s.Put("a", []byte("1"))
	if v, ok := s.Get("b"); !ok || string(v) != "3" {
		t.Fatalf("Get(b) = %q, %v", v, ok)
	}
	if got := s.Keys(); !slices.Equal(got, []string{"a", "b"}) {
		t.Fatalf("Keys = %v", got)
	}
	if !s.Delete("a") || s.Delete("a") {
		t.Fatal("Delete should succeed once")
	}
	if _, ok := s.Get("a"); ok {
		t.Fatal("deleted key still present")
	}
}
