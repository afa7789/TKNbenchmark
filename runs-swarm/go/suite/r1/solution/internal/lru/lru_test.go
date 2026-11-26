package lru

import (
	"strings"
	"testing"
)

func TestRun(t *testing.T) {
	tests := []struct {
		name, in, want string
	}{
		{
			name: "spec example",
			in:   "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n",
			want: "1\nNULL\n2\n",
		},
		{
			name: "overwrite refreshes recency",
			in:   "2\nSET a 1\nSET b 2\nSET a 9\nSET c 3\nGET a\nGET b\nGET c\n",
			want: "9\nNULL\n3\n",
		},
		{
			name: "delete",
			in:   "3\nSET a 1\nDEL a\nDEL a\nGET a\nSIZE\n",
			want: "1\n0\nNULL\n0\n",
		},
		{
			name: "deleted slot is reused",
			in:   "2\nSET a 1\nSET b 2\nDEL a\nSET c 3\nSET d 4\nGET b\nGET c\nGET d\nSIZE\n",
			want: "1\nNULL\n3\n4\n2\n",
		},
		{
			name: "capacity one",
			in:   "1\nSET a 1\nSET b 2\nGET a\nGET b\nSIZE",
			want: "NULL\n2\n1\n",
		},
		{
			name: "missing final newline",
			in:   "5\nSET k v\nGET k",
			want: "v\n",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var out strings.Builder
			if err := Run(strings.NewReader(tt.in), &out); err != nil {
				t.Fatalf("Run: %v", err)
			}
			if got := out.String(); got != tt.want {
				t.Errorf("Run(%q) = %q, want %q", tt.in, got, tt.want)
			}
		})
	}
}

func TestRunInvalidCapacity(t *testing.T) {
	for _, in := range []string{"", "0\n", "1000001\n", "x\n"} {
		if err := Run(strings.NewReader(in), &strings.Builder{}); err == nil {
			t.Errorf("Run(%q): want error", in)
		}
	}
}

func TestCacheEvictsLeastRecentlyUsed(t *testing.T) {
	c := New(2)
	c.Set("a", "1")
	c.Set("b", "2")
	c.Get("a")
	c.Set("c", "3")
	if _, ok := c.Get("b"); ok {
		t.Error("b should have been evicted")
	}
	for _, k := range []string{"a", "c"} {
		if _, ok := c.Get(k); !ok {
			t.Errorf("%s should be present", k)
		}
	}
	if n := c.Len(); n != 2 {
		t.Errorf("Len = %d, want 2", n)
	}
}
