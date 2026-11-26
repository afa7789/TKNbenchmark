package notes

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func openTestStore(t *testing.T, path string) *Store {
	t.Helper()
	s, err := Open(context.Background(), path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestIDsNotReusedAcrossReopen(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "dir with space?", "notes.db")
	if err := mkdirAll(filepath.Dir(path)); err != nil {
		t.Fatal(err)
	}
	s := openTestStore(t, path)
	for range 2 {
		if _, err := s.Create(ctx, Input{Title: "t", Tags: []string{"a"}}); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.Delete(ctx, 2); err != nil {
		t.Fatal(err)
	}
	s.Close()

	s = openTestStore(t, path)
	n, err := s.Create(ctx, Input{Title: "again", Tags: []string{}})
	if err != nil {
		t.Fatal(err)
	}
	if n.ID != 3 {
		t.Fatalf("id = %d, want 3", n.ID)
	}
	if _, err := s.Get(ctx, 2); !errors.Is(err, ErrNotFound) {
		t.Fatalf("get deleted: %v", err)
	}
	counts, err := s.TagCounts(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(counts) != 1 || counts[0] != (TagCount{Tag: "a", Count: 1}) {
		t.Fatalf("counts = %+v", counts)
	}
}

func TestListFilters(t *testing.T) {
	ctx := context.Background()
	s := openTestStore(t, filepath.Join(t.TempDir(), "notes.db"))
	for _, in := range []Input{
		{Title: "Hello 100%", Tags: []string{"x"}},
		{Title: "other", Body: "say HeLLo_", Tags: []string{"x", "y"}},
		{Title: "Ünï", Body: "", Tags: []string{}},
	} {
		if _, err := s.Create(ctx, in); err != nil {
			t.Fatal(err)
		}
	}
	ids := func(f Filter) []int64 {
		t.Helper()
		if f.Limit == 0 {
			f.Limit = 100
		}
		list, err := s.List(ctx, f)
		if err != nil {
			t.Fatal(err)
		}
		var out []int64
		for _, n := range list {
			out = append(out, n.ID)
		}
		return out
	}
	check := func(name string, got []int64, want ...int64) {
		t.Helper()
		if len(got) != len(want) {
			t.Fatalf("%s: got %v, want %v", name, got, want)
		}
		for i := range got {
			if got[i] != want[i] {
				t.Fatalf("%s: got %v, want %v", name, got, want)
			}
		}
	}
	check("all", ids(Filter{}), 1, 2, 3)
	check("q", ids(Filter{Query: "hello"}), 1, 2)
	check("q percent literal", ids(Filter{Query: "0%"}), 1)
	check("q underscore literal", ids(Filter{Query: "o_"}), 2)
	check("q non-ascii case sensitive", ids(Filter{Query: "ü"}))
	check("tag", ids(Filter{Tag: "y"}), 2)
	check("tag and q", ids(Filter{Tag: "x", Query: "say"}), 2)
	check("after", ids(Filter{After: 1}), 2, 3)
	check("limit", ids(Filter{Limit: 1, After: 1}), 2)
}

func mkdirAll(dir string) error { return os.MkdirAll(dir, 0o755) }
