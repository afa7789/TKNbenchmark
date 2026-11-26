package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
)

// Create inserts a new note and returns it with its assigned id.
func (s *Store) Create(ctx context.Context, in NoteInput) (Note, error) {
	var n Note
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `INSERT INTO notes (title, body) VALUES (?, ?)`, in.Title, in.Body)
		if err != nil {
			return fmt.Errorf("insert note: %w", err)
		}
		id, err := res.LastInsertId()
		if err != nil {
			return fmt.Errorf("insert note: %w", err)
		}
		if err := insertTags(ctx, tx, id, in.Tags); err != nil {
			return err
		}
		n = newNote(id, in)
		return nil
	})
	return n, err
}

// Get returns the note with the given id, or ErrNotFound. The note and its
// tags are read from one snapshot, so a concurrent Update is never half seen.
func (s *Store) Get(ctx context.Context, id int64) (Note, error) {
	notes := []Note{{ID: id}}
	err := s.withReadTx(ctx, func(tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx, `SELECT title, body FROM notes WHERE id = ?`, id).
			Scan(&notes[0].Title, &notes[0].Body)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return fmt.Errorf("get note %d: %w", id, err)
		}
		return attachTags(ctx, tx, notes)
	})
	if err != nil {
		return Note{}, err
	}
	return notes[0], nil
}

// newNote builds the Note for id from validated input.
func newNote(id int64, in NoteInput) Note {
	tags := in.Tags
	if tags == nil {
		tags = []string{}
	}
	return Note{ID: id, Title: in.Title, Body: in.Body, Tags: tags}
}

// insertTags stores tags for a note. Tags must already be unique.
func insertTags(ctx context.Context, q querier, noteID int64, tags []string) error {
	for _, t := range tags {
		if _, err := q.ExecContext(ctx, `INSERT INTO note_tags (note_id, tag) VALUES (?, ?)`, noteID, t); err != nil {
			return fmt.Errorf("insert tag: %w", err)
		}
	}
	return nil
}

// attachTags loads the tags of each note in notes, sorted ascending. Every
// note gets a non-nil Tags slice.
func attachTags(ctx context.Context, q querier, notes []Note) error {
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
		var (
			id  int64
			tag string
		)
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
