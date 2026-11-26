package store

import (
	"slices"
	"testing"
)

func TestStore(t *testing.T) {
	s := New()
	if got := s.Keys(); got == nil || len(got) != 0 {
		t.Fatalf("Keys on empty store = %#v, want empty non-nil slice", got)
	}
	if !s.Put("b", []byte("2")) {
		t.Fatal("first Put should create")
	}
	if s.Put("b", []byte("3")) {
		t.Fatal("second Put should replace")
	}
	s.Put("a", nil)
	if v, ok := s.Get("b"); !ok || string(v) != "3" {
		t.Fatalf("Get(b) = %q, %v", v, ok)
	}
	if got, want := s.Keys(), []string{"a", "b"}; !slices.Equal(got, want) {
		t.Fatalf("Keys = %v, want %v", got, want)
	}
	if !s.Delete("a") || s.Delete("a") {
		t.Fatal("Delete should succeed once")
	}
	if _, ok := s.Get("a"); ok {
		t.Fatal("deleted key still present")
	}
}
