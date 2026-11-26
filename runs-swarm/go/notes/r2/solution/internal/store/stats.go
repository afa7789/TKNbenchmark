package store

import (
	"context"
	"database/sql"
	"fmt"
)

// TagCount is the number of notes that have a tag.
type TagCount struct {
	Tag   string
	Count int64
}

// Stats summarizes the store.
type Stats struct {
	Notes int64            // number of notes
	Tags  map[string]int64 // number of notes per tag; never nil
}

// Stats returns the number of notes and the number of notes per tag.
//
// Both figures come from one statement, so they are taken from the same
// snapshot even while other requests write: the first row carries the note
// count (with a NULL tag), each following row one tag.
func (s *Store) Stats(ctx context.Context) (Stats, error) {
	rows, err := s.db.QueryContext(ctx, `
SELECT NULL, COUNT(*) FROM notes
UNION ALL
SELECT tag, COUNT(*) FROM note_tags GROUP BY tag`)
	if err != nil {
		return Stats{}, fmt.Errorf("query stats: %w", err)
	}
	defer rows.Close()

	st := Stats{Tags: make(map[string]int64)}
	for rows.Next() {
		var (
			tag   sql.NullString
			count int64
		)
		if err := rows.Scan(&tag, &count); err != nil {
			return Stats{}, fmt.Errorf("scan stats: %w", err)
		}
		if tag.Valid {
			st.Tags[tag.String] = count
		} else {
			st.Notes = count
		}
	}
	if err := rows.Err(); err != nil {
		return Stats{}, fmt.Errorf("read stats: %w", err)
	}
	return st, nil
}

// TagCounts returns every tag in use with the number of notes that have it,
// ordered by count descending, then tag ascending.
func (s *Store) TagCounts(ctx context.Context) ([]TagCount, error) {
	rows, err := s.db.QueryContext(ctx, `
SELECT tag, COUNT(*) AS n FROM note_tags
GROUP BY tag
ORDER BY n DESC, tag ASC`)
	if err != nil {
		return nil, fmt.Errorf("query tag counts: %w", err)
	}
	defer rows.Close()

	counts := []TagCount{}
	for rows.Next() {
		var tc TagCount
		if err := rows.Scan(&tc.Tag, &tc.Count); err != nil {
			return nil, fmt.Errorf("scan tag count: %w", err)
		}
		counts = append(counts, tc)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("read tag counts: %w", err)
	}
	return counts, nil
}
