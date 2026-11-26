// Package store persists notes in a SQLite database.
//
// Each group of operations lives in its own file (notes.go for create/get,
// and further files for update/delete, listing and statistics) so that
// features can be added independently.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"

	_ "modernc.org/sqlite" // registers the "sqlite" database/sql driver
)

// ErrNotFound is returned when a note does not exist.
var ErrNotFound = errors.New("note not found")

// Note is a stored note. Tags are unique and sorted ascending.
type Note struct {
	ID    int64    `json:"id"`
	Title string   `json:"title"`
	Body  string   `json:"body"`
	Tags  []string `json:"tags"`
}

// NoteInput holds the user-supplied fields of a note, already validated and
// normalized (see the api package).
type NoteInput struct {
	Title string
	Body  string
	Tags  []string
}

// Store is a SQLite-backed note store. It is safe for concurrent use.
type Store struct {
	db *sql.DB
}

const schema = `
CREATE TABLE IF NOT EXISTS notes (
	id    INTEGER PRIMARY KEY AUTOINCREMENT, -- AUTOINCREMENT: ids are never reused
	title TEXT    NOT NULL,
	body  TEXT    NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS note_tags (
	note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
	tag     TEXT    NOT NULL,
	PRIMARY KEY (note_id, tag)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS note_tags_tag ON note_tags(tag, note_id);
`

// Open opens (creating if needed) the database at path and applies the schema.
func Open(ctx context.Context, path string) (*Store, error) {
	q := url.Values{}
	for _, p := range []string{
		"foreign_keys(1)",
		"journal_mode(WAL)",
		"synchronous(NORMAL)",
		"busy_timeout(5000)",
	} {
		q.Add("_pragma", p)
	}
	// Writers take the lock up front so concurrent read-then-write
	// transactions wait on busy_timeout instead of failing.
	q.Set("_txlock", "immediate")
	dsn := "file:" + (&url.URL{Path: path}).EscapedPath() + "?" + q.Encode()

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

// Close closes the database.
func (s *Store) Close() error {
	return s.db.Close()
}

// querier is implemented by *sql.DB and *sql.Tx.
type querier interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

// withTx runs fn in a transaction, committing if it returns nil.
func (s *Store) withTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit: %w", err)
	}
	return nil
}

// withReadTx runs fn in a read-only transaction. It is a plain deferred
// BEGIN (not IMMEDIATE), so fn sees a single consistent snapshot without
// taking the write lock.
func (s *Store) withReadTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return fmt.Errorf("begin transaction: %w", err)
	}
	defer tx.Rollback()
	return fn(tx)
}
