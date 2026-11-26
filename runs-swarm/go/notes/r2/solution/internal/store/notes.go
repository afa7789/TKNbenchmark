package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"notes/internal/note"
)

// Create stores a new note and returns it with its assigned id.
func (s *Store) Create(ctx context.Context, in note.Input) (note.Note, error) {
	var id int64
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx,
			`INSERT INTO notes (title, body) VALUES (?, ?) RETURNING id`,
			in.Title, in.Body,
		).Scan(&id)
		if err != nil {
			return fmt.Errorf("insert note: %w", err)
		}
		return insertTags(ctx, tx, id, in.Tags)
	})
	if err != nil {
		return note.Note{}, err
	}
	return note.Note{ID: id, Title: in.Title, Body: in.Body, Tags: in.Tags}, nil
}

// Get returns the note with the given id, or ErrNotFound.
func (s *Store) Get(ctx context.Context, id int64) (note.Note, error) {
	n, err := scanNote(s.db.QueryRowContext(ctx, selectNotes+` WHERE n.id = ?`, id))
	if errors.Is(err, sql.ErrNoRows) {
		return note.Note{}, ErrNotFound
	}
	if err != nil {
		return note.Note{}, fmt.Errorf("get note %d: %w", id, err)
	}
	return n, nil
}
