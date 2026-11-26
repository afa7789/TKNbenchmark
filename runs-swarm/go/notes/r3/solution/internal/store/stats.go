package store

import (
	"context"
	"database/sql"
	"fmt"
)

// TagCount is a tag and the number of notes that have it.
type TagCount struct {
	Tag   string `json:"tag"`
	Count int64  `json:"count"`
}

// Stats summarizes the store: the number of notes and, for each tag in use, the number of notes that have
// it.
type Stats struct {
	Notes int64
	Tags  []TagCount
}

// Stats returns the note count and the tag counts, both read from the same snapshot of the database.
// Tags are ordered as by TagCounts.
func (s *Store) Stats(ctx context.Context) (Stats, error) {
	var st Stats
	err := s.inReadTx(ctx, func(tx *sql.Tx) error {
		if err := tx.QueryRowContext(ctx, `SELECT count(*) FROM notes`).Scan(&st.Notes); err != nil {
			return fmt.Errorf("count notes: %w", err)
		}
		var err error
		st.Tags, err = tagCounts(ctx, tx)
		return err
	})
	if err != nil {
		return Stats{}, err
	}
	return st, nil
}

// TagCounts returns every tag in use with the number of notes that have it, ordered by count descending,
// then tag ascending. The result is never nil.
func (s *Store) TagCounts(ctx context.Context) ([]TagCount, error) {
	return tagCounts(ctx, s.db)
}

func tagCounts(ctx context.Context, q querier) ([]TagCount, error) {
	// Tags are removed with their note (ON DELETE CASCADE), so every row belongs to an existing note.
	rows, err := q.QueryContext(ctx,
		`SELECT tag, count(*) AS n FROM note_tags GROUP BY tag ORDER BY n DESC, tag ASC`)
	if err != nil {
		return nil, fmt.Errorf("count tags: %w", err)
	}
	defer rows.Close()
	counts := []TagCount{}
	for rows.Next() {
		var tc TagCount
		if err := rows.Scan(&tc.Tag, &tc.Count); err != nil {
			return nil, fmt.Errorf("count tags: %w", err)
		}
		counts = append(counts, tc)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("count tags: %w", err)
	}
	return counts, nil
}

// inReadTx runs fn in a read-only transaction, which sees a single consistent snapshot of the database
// without taking the write lock.
func (s *Store) inReadTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return fmt.Errorf("begin read: %w", err)
	}
	defer tx.Rollback()
	return fn(tx)
}
