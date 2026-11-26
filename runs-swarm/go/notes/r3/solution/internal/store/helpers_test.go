package store

import (
	"path/filepath"
	"testing"

	"notes/internal/note"
)

// openTest opens a store on a fresh database file that is removed when the test ends.
func openTest(t *testing.T) (*Store, string) {
	t.Helper()
	path := filepath.Join(t.TempDir(), "notes.db")
	s, err := Open(t.Context(), path)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { s.Close() })
	return s, path
}

// mustCreate stores a note with the given title and tags (which must already be normalized).
func mustCreate(t *testing.T, s *Store, title string, tags ...string) note.Note {
	t.Helper()
	n, err := s.Create(t.Context(), note.Input{Title: title, Tags: tags})
	if err != nil {
		t.Fatalf("Create(%q): %v", title, err)
	}
	return n
}
