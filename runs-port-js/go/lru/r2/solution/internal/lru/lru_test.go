package lru

import "testing"

func TestEvictsLeastRecentlyUsed(t *testing.T) {
	c := New[string](2)
	c.Set("a", "1")
	c.Set("b", "2")
	if v, ok := c.Get("a"); !ok || v != "1" {
		t.Fatalf("Get(a) = %q, %v; want 1, true", v, ok)
	}
	c.Set("c", "3")
	if _, ok := c.Get("b"); ok {
		t.Fatal("b should have been evicted")
	}
	if n := c.Len(); n != 2 {
		t.Fatalf("Len() = %d; want 2", n)
	}
}

func TestOverwriteRefreshes(t *testing.T) {
	c := New[int](2)
	c.Set("a", 1)
	c.Set("b", 2)
	c.Set("a", 9)
	c.Set("c", 3)
	if v, ok := c.Get("a"); !ok || v != 9 {
		t.Fatalf("Get(a) = %d, %v; want 9, true", v, ok)
	}
	if _, ok := c.Get("b"); ok {
		t.Fatal("b should have been evicted")
	}
}

func TestDeleteReusesSlots(t *testing.T) {
	c := New[int](1)
	if c.Delete("x") {
		t.Fatal("Delete on empty cache reported true")
	}
	for i := range 100 {
		c.Set("x", i)
		if !c.Delete("x") {
			t.Fatal("Delete(x) = false; want true")
		}
	}
	if n := len(c.nodes); n != 2 {
		t.Fatalf("node storage grew to %d; want 2", n)
	}
	if c.Len() != 0 {
		t.Fatalf("Len() = %d; want 0", c.Len())
	}
}
