package lru

import "testing"

func TestCache(t *testing.T) {
	t.Parallel()
	c := New(2)
	c.Set("a", "1")
	c.Set("b", "2")
	if v, ok := c.Get("a"); !ok || v != "1" {
		t.Fatalf(`Get("a") = %q, %v; want "1", true`, v, ok)
	}
	c.Set("c", "3") // evicts b
	if _, ok := c.Get("b"); ok {
		t.Fatal(`Get("b") hit after eviction`)
	}
	if !c.Delete("a") || c.Delete("a") {
		t.Fatal("Delete results wrong")
	}
	if c.Len() != 1 {
		t.Fatalf("Len() = %d, want 1", c.Len())
	}
	c.Set("d", "4")
	c.Set("c", "33") // overwrite refreshes c
	c.Set("e", "5")  // evicts d
	if _, ok := c.Get("d"); ok {
		t.Fatal(`Get("d") hit after eviction`)
	}
	if v, _ := c.Get("c"); v != "33" {
		t.Fatalf(`Get("c") = %q, want "33"`, v)
	}
}

func TestCapacityOne(t *testing.T) {
	t.Parallel()
	c := New(1)
	c.Set("a", "1")
	c.Set("b", "2")
	if _, ok := c.Get("a"); ok || c.Len() != 1 {
		t.Fatal("capacity 1 not enforced")
	}
}

func BenchmarkSetGet(b *testing.B) {
	c := New(1000)
	keys := make([]string, 4096)
	for i := range keys {
		keys[i] = string(rune('a'+i%26)) + string(rune('A'+i/26%26)) + string(rune('0'+i/676))
	}
	i := 0
	for b.Loop() {
		k := keys[i&4095]
		c.Set(k, k)
		c.Get(keys[(i*7)&4095])
		i++
	}
}
