package lru

import "testing"

func TestEvictsLeastRecentlyUsed(t *testing.T) {
	c := New[string, string](2)
	c.Set("a", "1")
	c.Set("b", "2")
	if v, ok := c.Get("a"); !ok || v != "1" {
		t.Fatalf(`Get("a") = %q, %v; want "1", true`, v, ok)
	}
	c.Set("c", "3")
	if _, ok := c.Get("b"); ok {
		t.Fatal(`Get("b") hit; want evicted`)
	}
	if got := c.Len(); got != 2 {
		t.Fatalf("Len() = %d, want 2", got)
	}
}

func TestOverwriteRefreshes(t *testing.T) {
	c := New[string, string](2)
	c.Set("a", "1")
	c.Set("b", "2")
	c.Set("a", "9")
	c.Set("c", "3")
	if v, ok := c.Get("a"); !ok || v != "9" {
		t.Fatalf(`Get("a") = %q, %v; want "9", true`, v, ok)
	}
	if _, ok := c.Get("b"); ok {
		t.Fatal(`Get("b") hit; want evicted`)
	}
}

func TestDeleteReusesSlots(t *testing.T) {
	c := New[int, int](3)
	for i := range 3 {
		c.Set(i, i)
	}
	if !c.Delete(1) || c.Delete(1) {
		t.Fatal("Delete(1) should succeed once")
	}
	c.Set(3, 3)
	c.Set(4, 4) // evicts 0
	if _, ok := c.Get(0); ok {
		t.Fatal("Get(0) hit; want evicted")
	}
	for _, k := range []int{2, 3, 4} {
		if v, ok := c.Get(k); !ok || v != k {
			t.Fatalf("Get(%d) = %d, %v", k, v, ok)
		}
	}
	if len(c.entries) != 3 {
		t.Fatalf("entries grew to %d, want 3", len(c.entries))
	}
}

func TestCapacityOne(t *testing.T) {
	c := New[string, int](1)
	c.Set("a", 1)
	c.Set("b", 2)
	if _, ok := c.Get("a"); ok {
		t.Fatal(`Get("a") hit; want evicted`)
	}
	if !c.Delete("b") || c.Len() != 0 {
		t.Fatal("Delete(b) failed")
	}
	c.Set("c", 3)
	if v, _ := c.Get("c"); v != 3 {
		t.Fatalf(`Get("c") = %d, want 3`, v)
	}
}
