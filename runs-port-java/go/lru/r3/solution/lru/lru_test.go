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
	if c.Len() != 2 {
		t.Fatalf("Len() = %d; want 2", c.Len())
	}
}

func TestOverwriteRefreshes(t *testing.T) {
	c := New[string, string](2)
	c.Set("a", "1")
	c.Set("b", "2")
	c.Set("a", "9")
	c.Set("c", "3")
	if v, _ := c.Get("a"); v != "9" {
		t.Fatalf("Get(a) = %q; want 9", v)
	}
	if _, ok := c.Get("b"); ok {
		t.Fatal("b should have been evicted")
	}
}

func TestDelete(t *testing.T) {
	c := New[string, int](1)
	c.Set("x", 1)
	if !c.Delete("x") {
		t.Fatal("first Delete should report presence")
	}
	if c.Delete("x") {
		t.Fatal("second Delete should report absence")
	}
	if c.Len() != 0 {
		t.Fatalf("Len() = %d; want 0", c.Len())
	}
	c.Set("y", 2)
	c.Set("z", 3)
	if _, ok := c.Get("y"); ok {
		t.Fatal("y should have been evicted")
	}
}
