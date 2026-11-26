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
		t.Fatalf("get b = %q, %v", v, ok)
	}
	if v, ok := s.Get("a"); !ok || len(v) != 0 {
		t.Fatalf("get a = %q, %v", v, ok)
	}
	if got := s.Keys(); !slices.Equal(got, []string{"a", "b"}) {
		t.Fatalf("keys = %v", got)
	}
	if !s.Delete("a") || s.Delete("a") {
		t.Fatal("delete should succeed exactly once")
	}
	if _, ok := s.Get("a"); ok {
		t.Fatal("a should be gone")
	}
}
