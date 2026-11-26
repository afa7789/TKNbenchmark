package store

import (
	"bytes"
	"errors"
	"os"
	"reflect"
	"sync"
	"testing"

	"notes/internal/note"
)

func TestCreateGet(t *testing.T) {
	s, _ := openTest(t)
	ctx := t.Context()

	first := mustCreate(t, s, "first")
	if want := (note.Note{ID: 1, Title: "first", Tags: []string{}}); !reflect.DeepEqual(first, want) {
		t.Errorf("Create = %+v, want %+v", first, want)
	}
	second, err := s.Create(ctx, note.Input{Title: "second", Body: "text", Tags: []string{"a", "b"}})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if second.ID != 2 {
		t.Errorf("second id = %d, want 2", second.ID)
	}

	for _, want := range []note.Note{first, second} {
		got, err := s.Get(ctx, want.ID)
		if err != nil {
			t.Fatalf("Get(%d): %v", want.ID, err)
		}
		if !reflect.DeepEqual(got, want) {
			t.Errorf("Get(%d) = %+v, want %+v", want.ID, got, want)
		}
	}
}

func TestGetNotFound(t *testing.T) {
	s, _ := openTest(t)
	if _, err := s.Get(t.Context(), 1); !errors.Is(err, ErrNotFound) {
		t.Errorf("Get on empty store: err = %v, want ErrNotFound", err)
	}
}

func TestPersistence(t *testing.T) {
	s, path := openTest(t)
	want := mustCreate(t, s, "kept", "x")
	if err := s.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	head, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.HasPrefix(head, []byte("SQLite format 3\x00")) {
		t.Errorf("%s is not a SQLite database", path)
	}

	s, err = Open(t.Context(), path)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer s.Close()
	got, err := s.Get(t.Context(), want.ID)
	if err != nil {
		t.Fatalf("Get after reopen: %v", err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Get after reopen = %+v, want %+v", got, want)
	}
	if n := mustCreate(t, s, "next"); n.ID != want.ID+1 {
		t.Errorf("id after reopen = %d, want %d", n.ID, want.ID+1)
	}
}

func TestConcurrentCreate(t *testing.T) {
	s, _ := openTest(t)
	const n = 50
	ids := make(chan int64, n)
	var wg sync.WaitGroup
	for range n {
		wg.Go(func() {
			created, err := s.Create(t.Context(), note.Input{Title: "c", Tags: []string{"t"}})
			if err != nil {
				t.Errorf("Create: %v", err)
				return
			}
			ids <- created.ID
		})
	}
	wg.Wait()
	close(ids)
	seen := make(map[int64]bool)
	for id := range ids {
		if seen[id] || id < 1 || id > n {
			t.Errorf("unexpected id %d", id)
		}
		seen[id] = true
	}
	if len(seen) != n {
		t.Errorf("got %d distinct ids, want %d", len(seen), n)
	}
}
