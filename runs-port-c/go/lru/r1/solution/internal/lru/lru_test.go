package lru

import "testing"

func TestEvictsLeastRecentlyUsed(t *testing.T) {
	c := New(2, 0)
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
	c := New(2, 0)
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

func TestDeleteReusesSlots(t *testing.T) {
	c := New(3, 1)
	for round := 0; round < 3; round++ {
		c.Set("x", "1")
		c.Set("y", "2")
		if !c.Delete("x") || c.Delete("x") {
			t.Fatal("Delete(x) should succeed exactly once")
		}
		if !c.Delete("y") {
			t.Fatal("Delete(y) should succeed")
		}
		if c.Len() != 0 {
			t.Fatalf("Len() = %d; want 0", c.Len())
		}
	}
	if len(c.nodes) > 3 {
		t.Fatalf("pool grew to %d nodes; slots not reused", len(c.nodes))
	}
}
