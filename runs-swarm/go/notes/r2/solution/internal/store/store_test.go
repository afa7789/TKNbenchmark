package store

import (
	"context"
	"errors"
	"path/filepath"
	"reflect"
	"sync"
	"testing"

	"notes/internal/note"
)

// openTestStore opens a store on a fresh database file removed after the test.
func openTestStore(t *testing.T) (*Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "notes.db")
	s, err := Open(context.Background(), path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s, path
}

func mustCreate(t *testing.T, s *Store, in note.Input) note.Note {
	t.Helper()
	if in.Tags == nil {
		in.Tags = []string{}
	}
	n, err := s.Create(context.Background(), in)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	return n
}

func TestCreateGet(t *testing.T) {
	s, _ := openTestStore(t)
	ctx := context.Background()

	a := mustCreate(t, s, note.Input{Title: "a"})
	b := mustCreate(t, s, note.Input{Title: "b", Body: "text", Tags: []string{"x", "y"}})
	if a.ID != 1 || b.ID != 2 {
		t.Fatalf("ids = %d, %d; want 1, 2", a.ID, b.ID)
	}

	for _, want := range []note.Note{
		{ID: 1, Title: "a", Body: "", Tags: []string{}},
		{ID: 2, Title: "b", Body: "text", Tags: []string{"x", "y"}},
	} {
		got, err := s.Get(ctx, want.ID)
		if err != nil {
			t.Fatalf("Get(%d): %v", want.ID, err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("Get(%d) = %#v, want %#v", want.ID, got, want)
		}
	}

	if _, err := s.Get(ctx, 3); !errors.Is(err, ErrNotFound) {
		t.Errorf("Get(3) error = %v, want ErrNotFound", err)
	}
}

func TestPersistsAcrossReopen(t *testing.T) {
	s, path := openTestStore(t)
	mustCreate(t, s, note.Input{Title: "kept", Tags: []string{"t"}})
	s.Close()

	s2, err := Open(context.Background(), path)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer s2.Close()
	got, err := s2.Get(context.Background(), 1)
	if err != nil {
		t.Fatalf("Get after reopen: %v", err)
	}
	if got.Title != "kept" || !reflect.DeepEqual(got.Tags, []string{"t"}) {
		t.Errorf("after reopen got %#v", got)
	}
	if n := mustCreate(t, s2, note.Input{Title: "next"}); n.ID != 2 {
		t.Errorf("id after reopen = %d, want 2", n.ID)
	}
}

func TestConcurrentCreate(t *testing.T) {
	s, _ := openTestStore(t)
	const workers, perWorker = 8, 25

	var wg sync.WaitGroup
	errs := make(chan error, workers*perWorker)
	for range workers {
		wg.Go(func() {
			for range perWorker {
				if _, err := s.Create(context.Background(), note.Input{Title: "c", Tags: []string{"t"}}); err != nil {
					errs <- err
				}
			}
		})
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatalf("concurrent Create: %v", err)
	}

	if _, err := s.Get(context.Background(), workers*perWorker); err != nil {
		t.Fatalf("Get last note: %v", err)
	}
}
