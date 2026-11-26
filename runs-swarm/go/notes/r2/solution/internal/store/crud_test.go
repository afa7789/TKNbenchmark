package store

import (
	"context"
	"errors"
	"reflect"
	"testing"

	"notes/internal/note"
)

func TestUpdate(t *testing.T) {
	s, _ := openTestStore(t)
	ctx := context.Background()
	mustCreate(t, s, note.Input{Title: "old", Body: "text", Tags: []string{"x", "y"}})

	want := note.Note{ID: 1, Title: "new", Body: "", Tags: []string{"a", "y"}}
	got, err := s.Update(ctx, 1, note.Input{Title: "new", Tags: []string{"a", "y"}})
	if err != nil {
		t.Fatalf("Update: %v", err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Update = %#v, want %#v", got, want)
	}
	if got, err = s.Get(ctx, 1); err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("Get after Update = %#v, %v; want %#v", got, err, want)
	}

	if _, err := s.Update(ctx, 1, note.Input{Title: "bare", Tags: []string{}}); err != nil {
		t.Fatalf("Update clearing tags: %v", err)
	}
	if got, _ := s.Get(ctx, 1); len(got.Tags) != 0 {
		t.Errorf("tags after clearing = %v, want []", got.Tags)
	}

	if _, err := s.Update(ctx, 2, note.Input{Title: "none", Tags: []string{"t"}}); !errors.Is(err, ErrNotFound) {
		t.Errorf("Update(2) error = %v, want ErrNotFound", err)
	}
}

func TestDelete(t *testing.T) {
	s, path := openTestStore(t)
	ctx := context.Background()
	mustCreate(t, s, note.Input{Title: "a", Tags: []string{"t"}})
	mustCreate(t, s, note.Input{Title: "b"})

	if err := s.Delete(ctx, 2); err != nil {
		t.Fatalf("Delete(2): %v", err)
	}
	if err := s.Delete(ctx, 2); !errors.Is(err, ErrNotFound) {
		t.Errorf("second Delete(2) error = %v, want ErrNotFound", err)
	}
	if _, err := s.Get(ctx, 2); !errors.Is(err, ErrNotFound) {
		t.Errorf("Get(2) after Delete error = %v, want ErrNotFound", err)
	}

	if err := s.Delete(ctx, 1); err != nil {
		t.Fatalf("Delete(1): %v", err)
	}
	var tags int
	if err := s.db.QueryRowContext(ctx, `SELECT count(*) FROM note_tags`).Scan(&tags); err != nil {
		t.Fatal(err)
	}
	if tags != 0 {
		t.Errorf("%d tag rows left after deleting all notes, want 0", tags)
	}

	// Ids of deleted notes are not reused, also after reopening.
	s.Close()
	s2, err := Open(ctx, path)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer s2.Close()
	if n := mustCreate(t, s2, note.Input{Title: "c"}); n.ID != 3 {
		t.Errorf("id after deletes = %d, want 3", n.ID)
	}
}
