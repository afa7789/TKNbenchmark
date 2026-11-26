package store

import (
	"context"
	"errors"
	"path/filepath"
	"slices"
	"testing"
)

func TestUpdate(t *testing.T) {
	ctx := context.Background()
	s := openTest(t, filepath.Join(t.TempDir(), "notes.db"))

	if _, err := s.Create(ctx, NoteInput{Title: "old", Body: "text", Tags: []string{"x", "y"}}); err != nil {
		t.Fatal(err)
	}
	n, err := s.Update(ctx, 1, NoteInput{Title: "new", Tags: []string{"a", "y"}})
	if err != nil {
		t.Fatal(err)
	}
	want := Note{ID: 1, Title: "new", Body: "", Tags: []string{"a", "y"}}
	if n.ID != want.ID || n.Title != want.Title || n.Body != want.Body || !slices.Equal(n.Tags, want.Tags) {
		t.Fatalf("Update returned %+v, want %+v", n, want)
	}
	got, err := s.Get(ctx, 1)
	if err != nil {
		t.Fatal(err)
	}
	if got.Title != want.Title || got.Body != want.Body || !slices.Equal(got.Tags, want.Tags) {
		t.Fatalf("Get after Update = %+v, want %+v", got, want)
	}

	n, err = s.Update(ctx, 1, NoteInput{Title: "bare"})
	if err != nil {
		t.Fatal(err)
	}
	if n.Tags == nil || len(n.Tags) != 0 {
		t.Fatalf("tags = %#v, want empty non-nil", n.Tags)
	}

	if _, err := s.Update(ctx, 2, NoteInput{Title: "none"}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Update(2) err = %v, want ErrNotFound", err)
	}
}

func TestDelete(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "notes.db")
	s := openTest(t, path)

	for _, title := range []string{"a", "b"} {
		if _, err := s.Create(ctx, NoteInput{Title: title, Tags: []string{"t"}}); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.Delete(ctx, 2); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Get(ctx, 2); !errors.Is(err, ErrNotFound) {
		t.Fatalf("Get after Delete err = %v, want ErrNotFound", err)
	}
	if err := s.Delete(ctx, 2); !errors.Is(err, ErrNotFound) {
		t.Fatalf("second Delete err = %v, want ErrNotFound", err)
	}
	var tags int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM note_tags WHERE note_id = 2`).Scan(&tags); err != nil {
		t.Fatal(err)
	}
	if tags != 0 {
		t.Fatalf("%d tags left for deleted note", tags)
	}
	s.Close()

	// Ids are not reused after a delete, even across a restart.
	s = openTest(t, path)
	n, err := s.Create(ctx, NoteInput{Title: "c"})
	if err != nil {
		t.Fatal(err)
	}
	if n.ID != 3 {
		t.Fatalf("id = %d, want 3", n.ID)
	}
}
