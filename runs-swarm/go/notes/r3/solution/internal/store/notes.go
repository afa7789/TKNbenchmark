package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"

	"notes/internal/note"
)

// Create stores a new note with the given (already normalized) content and returns it with its new id.
func (s *Store) Create(ctx context.Context, in note.Input) (note.Note, error) {
	var id int64
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `INSERT INTO notes (title, body) VALUES (?, ?)`, in.Title, in.Body)
		if err != nil {
			return fmt.Errorf("insert note: %w", err)
		}
		if id, err = res.LastInsertId(); err != nil {
			return fmt.Errorf("insert note: %w", err)
		}
		return replaceTags(ctx, tx, id, in.Tags)
	})
	if err != nil {
		return note.Note{}, err
	}
	return newNote(id, in), nil
}

// Get returns the note with the given id, or ErrNotFound.
func (s *Store) Get(ctx context.Context, id int64) (note.Note, error) {
	n := note.Note{ID: id}
	err := s.db.QueryRowContext(ctx, `SELECT title, body FROM notes WHERE id = ?`, id).Scan(&n.Title, &n.Body)
	if errors.Is(err, sql.ErrNoRows) {
		return note.Note{}, ErrNotFound
	}
	if err != nil {
		return note.Note{}, fmt.Errorf("get note %d: %w", id, err)
	}
	notes := []note.Note{n}
	if err := attachTags(ctx, s.db, notes); err != nil {
		return note.Note{}, err
	}
	return notes[0], nil
}

// newNote builds the note with the given id and normalized content.
func newNote(id int64, in note.Input) note.Note {
	tags := in.Tags
	if tags == nil {
		tags = []string{}
	}
	return note.Note{ID: id, Title: in.Title, Body: in.Body, Tags: tags}
}

// replaceTags sets the tags of note id to tags, which must be normalized.
func replaceTags(ctx context.Context, q querier, id int64, tags []string) error {
	if _, err := q.ExecContext(ctx, `DELETE FROM note_tags WHERE note_id = ?`, id); err != nil {
		return fmt.Errorf("clear tags of note %d: %w", id, err)
	}
	for _, t := range tags {
		if _, err := q.ExecContext(ctx, `INSERT INTO note_tags (note_id, tag) VALUES (?, ?)`, id, t); err != nil {
			return fmt.Errorf("add tag %q to note %d: %w", t, id, err)
		}
	}
	return nil
}

// attachTags loads the tags of every note in notes, in one query, and sets each note's Tags (sorted
// ascending, never nil).
func attachTags(ctx context.Context, q querier, notes []note.Note) error {
	if len(notes) == 0 {
		return nil
	}
	index := make(map[int64]int, len(notes))
	args := make([]any, len(notes))
	for i := range notes {
		notes[i].Tags = []string{}
		index[notes[i].ID] = i
		args[i] = notes[i].ID
	}
	placeholders := strings.TrimSuffix(strings.Repeat("?,", len(notes)), ",")
	rows, err := q.QueryContext(ctx,
		`SELECT note_id, tag FROM note_tags WHERE note_id IN (`+placeholders+`) ORDER BY note_id, tag`, args...)
	if err != nil {
		return fmt.Errorf("load tags: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var id int64
		var tag string
		if err := rows.Scan(&id, &tag); err != nil {
			return fmt.Errorf("load tags: %w", err)
		}
		if i, ok := index[id]; ok {
			notes[i].Tags = append(notes[i].Tags, tag)
		}
	}
	if err := rows.Err(); err != nil {
		return fmt.Errorf("load tags: %w", err)
	}
	return nil
}
