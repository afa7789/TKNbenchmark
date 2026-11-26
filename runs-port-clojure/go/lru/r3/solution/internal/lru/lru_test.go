package lru

import "testing"

func TestEvictsLeastRecentlyUsed(t *testing.T) {
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
	if v, _ := c.Get("a"); v != "9" {
		t.Fatalf("Get(a) = %q; want 9", v)
	}
	if _, ok := c.Get("b"); ok {
		t.Fatal("b should have been evicted")
	}
}

func TestDeleteReusesSlots(t *testing.T) {
	c := New[string, int](3)
	for i := range 100 {
		c.Set("x", i)
		if !c.Delete("x") {
			t.Fatal("Delete(x) = false; want true")
		}
		if c.Delete("x") {
			t.Fatal("second Delete(x) = true; want false")
		}
	}
	if len(c.entries) != 1 {
		t.Fatalf("entries grew to %d; want 1", len(c.entries))
	}
}

func TestZeroCapacityHoldsNothing(t *testing.T) {
	c := New[string, string](0)
	c.Set("a", "1")
	if c.Len() != 0 {
		t.Fatalf("Len() = %d; want 0", c.Len())
	}
}
