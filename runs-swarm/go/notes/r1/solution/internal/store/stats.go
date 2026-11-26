package store

import (
	"context"
	"database/sql"
	"fmt"
)

// TagCount is the number of notes that have a tag.
type TagCount struct {
	Tag   string `json:"tag"`
	Count int64  `json:"count"`
}

// Stats summarizes the store.
type Stats struct {
	// Notes is the number of notes.
	Notes int64
	// Tags holds every tag in use with the number of notes that have it,
	// ordered by count descending, then tag ascending.
	Tags []TagCount
}

// Stats returns the number of notes and the per-tag note counts. Both come
// from a single statement, so they are consistent with each other even while
// notes are being written concurrently.
func (s *Store) Stats(ctx context.Context) (Stats, error) {
	// The first row (tag NULL) carries the note count; the remaining rows are
	// the tag counts. Tags of deleted notes are gone via ON DELETE CASCADE.
	rows, err := s.db.QueryContext(ctx, `
		SELECT NULL, COUNT(*), 0 AS part FROM notes
		UNION ALL
		SELECT tag, COUNT(*), 1 AS part FROM note_tags GROUP BY tag
		ORDER BY part, 2 DESC, 1`)
	if err != nil {
		return Stats{}, fmt.Errorf("load stats: %w", err)
	}
	defer rows.Close()

	st := Stats{Tags: []TagCount{}}
	for rows.Next() {
		var (
			tag   sql.NullString
			count int64
			part  int
		)
		if err := rows.Scan(&tag, &count, &part); err != nil {
			return Stats{}, fmt.Errorf("load stats: %w", err)
		}
		if part == 0 {
			st.Notes = count
			continue
		}
		st.Tags = append(st.Tags, TagCount{Tag: tag.String, Count: count})
	}
	if err := rows.Err(); err != nil {
		return Stats{}, fmt.Errorf("load stats: %w", err)
	}
	return st, nil
}
