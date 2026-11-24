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
	if got := c.Len(); got != 2 {
		t.Fatalf("Len = %d; want 2", got)
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

func TestDeleteAndReuse(t *testing.T) {
	c := New(3)
	c.Set("x", "1")
	if !c.Delete("x") {
		t.Fatal("Delete(x) = false; want true")
	}
	if c.Delete("x") {
		t.Fatal("second Delete(x) = true; want false")
	}
	if c.Len() != 0 {
		t.Fatalf("Len = %d; want 0", c.Len())
	}
	for _, k := range []string{"p", "q", "r", "s"} {
		c.Set(k, k)
	}
	if _, ok := c.Get("p"); ok {
		t.Fatal("p should have been evicted")
	}
	for _, k := range []string{"q", "r", "s"} {
		if v, ok := c.Get(k); !ok || v != k {
			t.Fatalf("Get(%s) = %q, %v", k, v, ok)
		}
	}
	if len(c.nodes) > 3 {
		t.Fatalf("arena grew to %d nodes; want <= 3", len(c.nodes))
	}
}

func TestCapacityOne(t *testing.T) {
	c := New(1)
	c.Set("a", "1")
	c.Set("b", "2")
	if _, ok := c.Get("a"); ok {
		t.Fatal("a should have been evicted")
	}
	if v, _ := c.Get("b"); v != "2" {
		t.Fatalf("Get(b) = %q; want 2", v)
	}
}
