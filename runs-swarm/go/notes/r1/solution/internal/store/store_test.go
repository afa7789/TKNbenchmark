package store

import (
	"context"
	"errors"
	"path/filepath"
	"slices"
	"sync"
	"testing"
)

func openTest(t *testing.T, path string) *Store {
	t.Helper()
	s, err := Open(context.Background(), path)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	return s
}

func TestCreateGetPersist(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "notes.db")
	s := openTest(t, path)

	n, err := s.Create(ctx, NoteInput{Title: "t", Body: "b", Tags: []string{"a", "b"}})
	if err != nil {
		t.Fatal(err)
	}
	if n.ID != 1 {
		t.Fatalf("id = %d, want 1", n.ID)
	}
	if _, err := s.Get(ctx, 2); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Get(2) err = %v, want ErrNotFound", err)
	}
	s.Close()

	s = openTest(t, path)
	got, err := s.Get(ctx, 1)
	if err != nil {
		t.Fatal(err)
	}
	if got.Title != "t" || got.Body != "b" || !slices.Equal(got.Tags, []string{"a", "b"}) {
		t.Fatalf("got %+v", got)
	}
	n, err = s.Create(ctx, NoteInput{Title: "u"})
	if err != nil {
		t.Fatal(err)
	}
	if n.ID != 2 || n.Tags == nil {
		t.Fatalf("second note %+v", n)
	}
}

func TestConcurrentCreate(t *testing.T) {
	ctx := context.Background()
	s := openTest(t, filepath.Join(t.TempDir(), "notes.db"))
	const n = 50
	var wg sync.WaitGroup
	errs := make(chan error, n)
	for range n {
		wg.Go(func() {
			if _, err := s.Create(ctx, NoteInput{Title: "x", Tags: []string{"t"}}); err != nil {
				errs <- err
			}
		})
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Error(err)
	}
	if _, err := s.Get(ctx, n); err != nil {
		t.Fatal(err)
	}
}
