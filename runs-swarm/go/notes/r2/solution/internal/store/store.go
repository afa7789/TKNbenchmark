// Package store persists notes in a SQLite database.
//
// The store is split by feature: this file holds the connection, the schema and
// the shared helpers; each group of operations lives in its own file.
package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"

	_ "modernc.org/sqlite" // registers the "sqlite" database/sql driver

	"notes/internal/note"
)

// ErrNotFound is returned when the requested note does not exist.
var ErrNotFound = errors.New("note not found")

// schema is idempotent so it can run on every start.
//
// AUTOINCREMENT guarantees that ids are never reused, even after the note with
// the highest id is deleted. Tags live in their own table so they can be
// filtered and counted with indexes; ON DELETE CASCADE drops them with the note.
const schema = `
CREATE TABLE IF NOT EXISTS notes (
	id    INTEGER PRIMARY KEY AUTOINCREMENT,
	title TEXT NOT NULL,
	body  TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS note_tags (
	note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
	tag     TEXT    NOT NULL,
	PRIMARY KEY (note_id, tag)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS note_tags_by_tag ON note_tags (tag, note_id);
`

// Store is safe for concurrent use.
type Store struct {
	db *sql.DB
}

// Open opens (creating if needed) the SQLite database at path and applies the schema.
func Open(ctx context.Context, path string) (*Store, error) {
	// Per-connection settings, applied in order: busy_timeout comes first so
	// that the pragmas after it already wait for locks held by other
	// connections instead of failing with SQLITE_BUSY. WAL lets readers run
	// alongside a writer, and _txlock=immediate takes the write lock at BEGIN
	// so that transactions never fail on a read-to-write lock upgrade.
	q := url.Values{}
	q.Add("_pragma", "busy_timeout(10000)")
	q.Add("_pragma", "foreign_keys(1)")
	q.Add("_pragma", "journal_mode(WAL)")
	q.Add("_pragma", "synchronous(NORMAL)")
	q.Set("_txlock", "immediate")
	dsn := "file:" + path + "?" + q.Encode()

	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	if _, err := db.ExecContext(ctx, schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("apply schema: %w", err)
	}
	return &Store{db: db}, nil
}

// Close releases the database.
func (s *Store) Close() error {
	return s.db.Close()
}

// selectNotes selects the columns read by scanNote. Tags are aggregated in the
// same statement so that a note and its tags come from one consistent snapshot.
// Append WHERE / ORDER BY / LIMIT clauses using the alias n for notes.
const selectNotes = `
SELECT n.id, n.title, n.body,
       (SELECT json_group_array(t.tag ORDER BY t.tag) FROM note_tags t WHERE t.note_id = n.id)
FROM notes n`

// scanner is implemented by *sql.Row and *sql.Rows.
type scanner interface {
	Scan(dest ...any) error
}

// scanNote reads one row produced by selectNotes.
func scanNote(row scanner) (note.Note, error) {
	var (
		n    note.Note
		tags string
	)
	if err := row.Scan(&n.ID, &n.Title, &n.Body, &tags); err != nil {
		return note.Note{}, err
	}
	if err := json.Unmarshal([]byte(tags), &n.Tags); err != nil {
		return note.Note{}, fmt.Errorf("decode tags of note %d: %w", n.ID, err)
	}
	if n.Tags == nil {
		n.Tags = []string{}
	}
	return n, nil
}

// inTx runs fn in a write transaction, committing if fn returns nil.
func (s *Store) inTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck // no-op after Commit

	if err := fn(tx); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}

// insertTags stores tags for the note id. tags must already be normalized.
func insertTags(ctx context.Context, tx *sql.Tx, id int64, tags []string) error {
	if len(tags) == 0 {
		return nil
	}
	stmt, err := tx.PrepareContext(ctx, `INSERT INTO note_tags (note_id, tag) VALUES (?, ?)`)
	if err != nil {
		return fmt.Errorf("prepare tag insert: %w", err)
	}
	defer stmt.Close()
	for _, tag := range tags {
		if _, err := stmt.ExecContext(ctx, id, tag); err != nil {
			return fmt.Errorf("insert tag %q: %w", tag, err)
		}
	}
	return nil
}
