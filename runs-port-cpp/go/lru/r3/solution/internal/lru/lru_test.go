package lru

import "testing"

func get(t *testing.T, c *Cache, key, want string, wantOK bool) {
	t.Helper()
	got, ok := c.Get([]byte(key))
	if ok != wantOK || got != want {
		t.Fatalf("Get(%q) = %q, %v; want %q, %v", key, got, ok, want, wantOK)
	}
}

func TestEvictsLeastRecentlyUsed(t *testing.T) {
	c := New(2)
	c.Set([]byte("a"), []byte("1"))
	c.Set([]byte("b"), []byte("2"))
	get(t, c, "a", "1", true)
	c.Set([]byte("c"), []byte("3"))
	get(t, c, "b", "", false)
	get(t, c, "a", "1", true)
	get(t, c, "c", "3", true)
	if c.Len() != 2 {
		t.Fatalf("Len() = %d, want 2", c.Len())
	}
}

func TestOverwriteRefreshes(t *testing.T) {
	c := New(2)
	c.Set([]byte("a"), []byte("1"))
	c.Set([]byte("b"), []byte("2"))
	c.Set([]byte("a"), []byte("9"))
	c.Set([]byte("c"), []byte("3"))
	get(t, c, "a", "9", true)
	get(t, c, "b", "", false)
}

func TestDelete(t *testing.T) {
	c := New(3)
	c.Set([]byte("x"), []byte("1"))
	if !c.Delete([]byte("x")) {
		t.Fatal("first Delete returned false")
	}
	if c.Delete([]byte("x")) {
		t.Fatal("second Delete returned true")
	}
	if c.Len() != 0 {
		t.Fatalf("Len() = %d, want 0", c.Len())
	}
	c.Set([]byte("y"), []byte("2"))
	get(t, c, "y", "2", true)
}

func TestCapacityOne(t *testing.T) {
	c := New(1)
	c.Set([]byte("a"), []byte("1"))
	c.Set([]byte("b"), []byte("2"))
	get(t, c, "a", "", false)
	get(t, c, "b", "2", true)
}

func TestKeyNotAliasedToInput(t *testing.T) {
	c := New(2)
	buf := []byte("k")
	c.Set(buf, []byte("v"))
	buf[0] = 'z'
	get(t, c, "k", "v", true)
}
