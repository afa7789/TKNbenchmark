package store

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
)

// ListFilter selects notes for List. Zero-valued Tag and Query do not filter.
type ListFilter struct {
	// Tag, if non-empty, keeps only notes that have this tag.
	Tag string
	// Query, if non-empty, keeps only notes whose title or body contains it,
	// ignoring ASCII case.
	Query string
	// After keeps only notes with an id greater than this.
	After int64
	// Limit is the maximum number of notes returned; it must be positive.
	Limit int
}

// List returns the notes matching f, ordered by id ascending. The result is
// never nil.
func (s *Store) List(ctx context.Context, f ListFilter) ([]Note, error) {
	where := []string{"n.id > ?"}
	args := []any{f.After}
	if f.Tag != "" {
		where = append(where, "EXISTS (SELECT 1 FROM note_tags t WHERE t.note_id = n.id AND t.tag = ?)")
		args = append(args, f.Tag)
	}
	if f.Query != "" {
		// SQLite's built-in lower() folds ASCII letters only, which is the
		// case-insensitivity the API promises; instr avoids the wildcard
		// escaping that LIKE would need.
		where = append(where, "(instr(lower(n.title), lower(?)) > 0 OR instr(lower(n.body), lower(?)) > 0)")
		args = append(args, f.Query, f.Query)
	}
	args = append(args, f.Limit)
	query := `SELECT n.id, n.title, n.body FROM notes n WHERE ` +
		strings.Join(where, " AND ") + ` ORDER BY n.id LIMIT ?`

	// Notes and their tags come from one snapshot, so tags always belong to
	// the listed notes.
	var notes []Note
	err := s.withReadTx(ctx, func(tx *sql.Tx) error {
		var err error
		if notes, err = queryNotes(ctx, tx, query, args...); err != nil {
			return err
		}
		return attachTags(ctx, tx, notes)
	})
	if err != nil {
		return nil, err
	}
	return notes, nil
}

// queryNotes runs a query selecting (id, title, body) and returns the notes
// without tags. The result is never nil.
func queryNotes(ctx context.Context, q querier, query string, args ...any) ([]Note, error) {
	rows, err := q.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	defer rows.Close()
	notes := []Note{}
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.ID, &n.Title, &n.Body); err != nil {
			return nil, fmt.Errorf("list notes: %w", err)
		}
		notes = append(notes, n)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	return notes, nil
}
