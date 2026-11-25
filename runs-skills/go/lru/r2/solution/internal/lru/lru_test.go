package lru

import "testing"

func TestEvictsLeastRecentlyUsed(t *testing.T) {
	t.Parallel()
	c := New(2)
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
	t.Parallel()
	c := New(2)
	c.Set("a", "1")
	c.Set("b", "2")
	c.Set("a", "9")
	c.Set("c", "3")
	for _, tt := range []struct {
		key, want string
		ok        bool
	}{{"a", "9", true}, {"b", "", false}, {"c", "3", true}} {
		if v, ok := c.Get(tt.key); v != tt.want || ok != tt.ok {
			t.Errorf("Get(%q) = %q, %v; want %q, %v", tt.key, v, ok, tt.want, tt.ok)
		}
	}
}

func TestDeleteReusesSlots(t *testing.T) {
	t.Parallel()
	c := New(3)
	c.Set("x", "1")
	if !c.Delete("x") {
		t.Fatal(`Delete("x") = false, want true`)
	}
	if c.Delete("x") {
		t.Fatal(`second Delete("x") = true, want false`)
	}
	if c.Len() != 0 {
		t.Fatalf("Len() = %d, want 0", c.Len())
	}
	for _, k := range []string{"p", "q", "r", "s"} {
		c.Set(k, k)
	}
	if _, ok := c.Get("p"); ok {
		t.Fatal(`Get("p") hit; want evicted`)
	}
	if len(c.entries) != 3 {
		t.Fatalf("len(entries) = %d, want 3", len(c.entries))
	}
}

func TestCapacityOne(t *testing.T) {
	t.Parallel()
	c := New(1)
	c.Set("a", "1")
	c.Set("b", "2")
	if _, ok := c.Get("a"); ok {
		t.Fatal(`Get("a") hit; want evicted`)
	}
	if v, ok := c.Get("b"); !ok || v != "2" {
		t.Fatalf(`Get("b") = %q, %v; want "2", true`, v, ok)
	}
	c.Delete("b")
	c.Set("c", "3")
	if v, ok := c.Get("c"); !ok || v != "3" || c.Len() != 1 {
		t.Fatalf(`Get("c") = %q, %v, Len %d; want "3", true, 1`, v, ok, c.Len())
	}
}
