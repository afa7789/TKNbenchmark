package store

import (
	"context"
	"database/sql"
	"fmt"

	"notes/internal/note"
)

// Replace overwrites the content of note id with the given (already normalized) content and returns the
// updated note, or ErrNotFound.
func (s *Store) Replace(ctx context.Context, id int64, in note.Input) (note.Note, error) {
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `UPDATE notes SET title = ?, body = ? WHERE id = ?`, in.Title, in.Body, id)
		if err != nil {
			return fmt.Errorf("update note %d: %w", id, err)
		}
		if err := requireAffected(res, id); err != nil {
			return err
		}
		return replaceTags(ctx, tx, id, in.Tags)
	})
	if err != nil {
		return note.Note{}, err
	}
	return newNote(id, in), nil
}

// Delete removes note id and its tags, or returns ErrNotFound.
func (s *Store) Delete(ctx context.Context, id int64) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM notes WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("delete note %d: %w", id, err)
	}
	return requireAffected(res, id)
}

// requireAffected returns ErrNotFound if the statement behind res matched no row.
func requireAffected(res sql.Result, id int64) error {
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("note %d: rows affected: %w", id, err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}
