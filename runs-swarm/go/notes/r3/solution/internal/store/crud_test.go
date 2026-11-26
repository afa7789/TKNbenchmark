package store

import (
	"errors"
	"reflect"
	"testing"

	"notes/internal/note"
)

func TestReplace(t *testing.T) {
	s, _ := openTest(t)
	ctx := t.Context()
	orig := mustCreate(t, s, "old", "x", "y")

	want := note.Note{ID: orig.ID, Title: "new", Body: "text", Tags: []string{"a", "y"}}
	got, err := s.Replace(ctx, orig.ID, note.Input{Title: "new", Body: "text", Tags: []string{"a", "y"}})
	if err != nil {
		t.Fatalf("Replace: %v", err)
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("Replace = %+v, want %+v", got, want)
	}
	if got, err = s.Get(ctx, orig.ID); err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("Get after Replace = %+v, %v; want %+v", got, err, want)
	}

	// Replacing with no tags clears them.
	want = note.Note{ID: orig.ID, Title: "bare", Tags: []string{}}
	if got, err = s.Replace(ctx, orig.ID, note.Input{Title: "bare"}); err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("Replace without tags = %+v, %v; want %+v", got, err, want)
	}
	if got, err = s.Get(ctx, orig.ID); err != nil || !reflect.DeepEqual(got, want) {
		t.Errorf("Get after clearing tags = %+v, %v; want %+v", got, err, want)
	}
}

func TestReplaceNotFound(t *testing.T) {
	s, _ := openTest(t)
	if _, err := s.Replace(t.Context(), 1, note.Input{Title: "x", Tags: []string{"a"}}); !errors.Is(err, ErrNotFound) {
		t.Errorf("Replace on empty store: err = %v, want ErrNotFound", err)
	}
	// The failed replace must not have left orphan tags behind.
	var n int
	if err := s.db.QueryRowContext(t.Context(), `SELECT COUNT(*) FROM note_tags`).Scan(&n); err != nil || n != 0 {
		t.Errorf("note_tags rows = %d, %v; want 0", n, err)
	}
}

func TestDelete(t *testing.T) {
	s, _ := openTest(t)
	ctx := t.Context()
	gone := mustCreate(t, s, "gone", "a", "b")
	kept := mustCreate(t, s, "kept", "a")

	if err := s.Delete(ctx, gone.ID); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := s.Get(ctx, gone.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("Get deleted note: err = %v, want ErrNotFound", err)
	}
	if err := s.Delete(ctx, gone.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("second Delete: err = %v, want ErrNotFound", err)
	}
	if got, err := s.Get(ctx, kept.ID); err != nil || !reflect.DeepEqual(got, kept) {
		t.Errorf("Get other note = %+v, %v; want %+v", got, err, kept)
	}

	// The tags of the deleted note are gone with it.
	var n int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM note_tags WHERE note_id = ?`, gone.ID).Scan(&n); err != nil || n != 0 {
		t.Errorf("tags of deleted note = %d, %v; want 0", n, err)
	}

	// Ids are never reused, even when the newest note is deleted.
	if err := s.Delete(ctx, kept.ID); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if next := mustCreate(t, s, "next"); next.ID != kept.ID+1 {
		t.Errorf("id after deleting the newest note = %d, want %d", next.ID, kept.ID+1)
	}
}

func TestDeletedIDNotReusedAfterReopen(t *testing.T) {
	s, path := openTest(t)
	last := mustCreate(t, s, "last")
	if err := s.Delete(t.Context(), last.ID); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if err := s.Close(); err != nil {
		t.Fatalf("Close: %v", err)
	}

	s, err := Open(t.Context(), path)
	if err != nil {
		t.Fatalf("reopen: %v", err)
	}
	defer s.Close()
	if next := mustCreate(t, s, "next"); next.ID != last.ID+1 {
		t.Errorf("id after deleting the newest note and reopening = %d, want %d", next.ID, last.ID+1)
	}
}
