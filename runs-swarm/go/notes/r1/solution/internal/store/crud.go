package store

import (
	"context"
	"database/sql"
	"fmt"
)

// Update replaces the title, body and tags of the note with the given id and
// returns the updated note, or ErrNotFound.
func (s *Store) Update(ctx context.Context, id int64, in NoteInput) (Note, error) {
	var n Note
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `UPDATE notes SET title = ?, body = ? WHERE id = ?`, in.Title, in.Body, id)
		if err != nil {
			return fmt.Errorf("update note %d: %w", id, err)
		}
		if err := requireOneRow(res); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM note_tags WHERE note_id = ?`, id); err != nil {
			return fmt.Errorf("clear tags of note %d: %w", id, err)
		}
		if err := insertTags(ctx, tx, id, in.Tags); err != nil {
			return err
		}
		n = newNote(id, in)
		return nil
	})
	return n, err
}

// Delete removes the note with the given id and its tags, or returns
// ErrNotFound.
func (s *Store) Delete(ctx context.Context, id int64) error {
	// note_tags rows are removed by ON DELETE CASCADE.
	res, err := s.db.ExecContext(ctx, `DELETE FROM notes WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("delete note %d: %w", id, err)
	}
	return requireOneRow(res)
}

// requireOneRow returns ErrNotFound if res affected no rows.
func requireOneRow(res sql.Result) error {
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("rows affected: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}
