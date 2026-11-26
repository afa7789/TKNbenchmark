package lru

import "testing"

func TestEvictionOrder(t *testing.T) {
	c := New(2)
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
		t.Fatalf("Len = %d; want 2", c.Len())
	}
}

func TestOverwriteRefreshes(t *testing.T) {
	c := New(2)
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

func TestDeleteReusesSlots(t *testing.T) {
	c := New(3)
	c.Set("x", "1")
	if !c.Delete("x") || c.Delete("x") {
		t.Fatal("Delete should report presence exactly once")
	}
	for i, k := range []string{"a", "b", "c", "d"} {
		c.Set(k, string(rune('0'+i)))
	}
	if c.Len() != 3 || len(c.entries) > 4 {
		t.Fatalf("Len = %d, slots = %d", c.Len(), len(c.entries))
	}
	if _, ok := c.Get("a"); ok {
		t.Fatal("a should have been evicted")
	}
}
