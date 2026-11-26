package lru

import "testing"

func TestEvictionOrder(t *testing.T) {
	c := New(2, 2)
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
	c := New(2, 0)
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
	c := New(3, 3)
	for range 10 {
		c.Set("x", "1")
		c.Set("y", "2")
		if !c.Delete("x") || c.Delete("x") {
			t.Fatal("Delete(x) should succeed exactly once")
		}
		if !c.Delete("y") {
			t.Fatal("Delete(y) should succeed")
		}
	}
	if c.Len() != 0 || len(c.nodes) != 2 {
		t.Fatalf("Len = %d, pool = %d; want 0, 2", c.Len(), len(c.nodes))
	}
}
