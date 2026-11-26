package lru

import "testing"

func TestEvictionOrder(t *testing.T) {
	c := New[string, string](2)
	c.Set("a", "1")
	c.Set("b", "2")
	if v, ok := c.Get("a"); !ok || v != "1" {
		t.Fatalf("Get(a) = %q, %v; want 1, true", v, ok)
	}
	c.Set("c", "3")
	if _, ok := c.Get("b"); ok {
		t.Fatal("b should have been evicted")
	}
	if got := c.Len(); got != 2 {
		t.Fatalf("Len() = %d; want 2", got)
	}
}

func TestOverwriteRefreshes(t *testing.T) {
	c := New[string, string](2)
	c.Set("a", "1")
	c.Set("b", "2")
	c.Set("a", "9")
	c.Set("c", "3")
	if v, ok := c.Get("a"); !ok || v != "9" {
		t.Fatalf("Get(a) = %q, %v; want 9, true", v, ok)
	}
	if _, ok := c.Get("b"); ok {
		t.Fatal("b should have been evicted")
	}
}

func TestDelete(t *testing.T) {
	c := New[string, string](3)
	c.Set("x", "1")
	if !c.Delete("x") {
		t.Fatal("first Delete(x) = false; want true")
	}
	if c.Delete("x") {
		t.Fatal("second Delete(x) = true; want false")
	}
	if c.Len() != 0 {
		t.Fatalf("Len() = %d; want 0", c.Len())
	}
}
