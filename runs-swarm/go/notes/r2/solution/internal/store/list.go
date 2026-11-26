package store

import (
	"context"
	"fmt"
	"strings"

	"notes/internal/note"
)

// MaxListLimit is the largest number of notes List returns at once.
const MaxListLimit = 100

// ListFilter selects the notes returned by List. The zero value selects the
// first MaxListLimit notes.
type ListFilter struct {
	// Tag, if non-nil, keeps only notes that have exactly this tag.
	Tag *string
	// Query, if non-empty, keeps only notes whose title or body contains it,
	// ignoring ASCII case.
	Query string
	// After keeps only notes with an id greater than it.
	After int64
	// Limit caps the number of notes; values outside 1..MaxListLimit mean MaxListLimit.
	Limit int
}

// List returns the notes matching f, ordered by id ascending. It never returns
// a nil slice.
func (s *Store) List(ctx context.Context, f ListFilter) ([]note.Note, error) {
	var (
		where = []string{"n.id > ?"}
		args  = []any{f.After}
	)
	if f.Tag != nil {
		where = append(where, `EXISTS (SELECT 1 FROM note_tags t WHERE t.note_id = n.id AND t.tag = ?)`)
		args = append(args, *f.Tag)
	}
	if f.Query != "" {
		// SQLite's built-in lower() folds ASCII letters only, which is exactly
		// the case-insensitivity required; instr() avoids LIKE wildcard escaping.
		where = append(where, `(instr(lower(n.title), lower(?)) > 0 OR instr(lower(n.body), lower(?)) > 0)`)
		args = append(args, f.Query, f.Query)
	}
	limit := f.Limit
	if limit < 1 || limit > MaxListLimit {
		limit = MaxListLimit
	}
	args = append(args, limit)

	query := selectNotes + " WHERE " + strings.Join(where, " AND ") + " ORDER BY n.id LIMIT ?"
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	defer rows.Close()

	notes := []note.Note{}
	for rows.Next() {
		n, err := scanNote(rows)
		if err != nil {
			return nil, fmt.Errorf("list notes: %w", err)
		}
		notes = append(notes, n)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	return notes, nil
}
