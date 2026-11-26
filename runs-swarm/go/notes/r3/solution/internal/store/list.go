package store

import (
	"context"
	"fmt"
	"strings"

	"notes/internal/note"
)

// MaxListLimit is the largest page List returns, and the page size when Filter.Limit is not positive.
const MaxListLimit = 100

// Filter selects the notes returned by List. Its zero value selects the first MaxListLimit notes.
type Filter struct {
	// Tag, if set, keeps only the notes that have this tag.
	Tag *string
	// Query, if set, keeps only the notes whose title or body contains it, ignoring ASCII case.
	Query *string
	// After keeps only the notes with an id greater than it.
	After int64
	// Limit is the maximum number of notes returned, at most MaxListLimit.
	Limit int
}

// List returns the notes selected by f, ordered by id ascending. The result is never nil.
func (s *Store) List(ctx context.Context, f Filter) ([]note.Note, error) {
	limit := f.Limit
	if limit <= 0 || limit > MaxListLimit {
		limit = MaxListLimit
	}

	where := []string{"n.id > ?"}
	args := []any{f.After}
	if f.Tag != nil {
		where = append(where, "EXISTS (SELECT 1 FROM note_tags t WHERE t.note_id = n.id AND t.tag = ?)")
		args = append(args, *f.Tag)
	}
	if f.Query != nil {
		// SQLite's lower() folds ASCII letters only, which is exactly the matching the API promises.
		// instr() rather than LIKE so that % and _ in the text need no escaping.
		where = append(where, "(instr(lower(n.title), lower(?)) > 0 OR instr(lower(n.body), lower(?)) > 0)")
		args = append(args, *f.Query, *f.Query)
	}
	args = append(args, limit)

	query := `SELECT n.id, n.title, n.body FROM notes n WHERE ` + strings.Join(where, " AND ") +
		` ORDER BY n.id LIMIT ?`
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	defer rows.Close()

	notes := make([]note.Note, 0, limit)
	for rows.Next() {
		var n note.Note
		if err := rows.Scan(&n.ID, &n.Title, &n.Body); err != nil {
			return nil, fmt.Errorf("list notes: %w", err)
		}
		notes = append(notes, n)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	if err := attachTags(ctx, s.db, notes); err != nil {
		return nil, err
	}
	return notes, nil
}
