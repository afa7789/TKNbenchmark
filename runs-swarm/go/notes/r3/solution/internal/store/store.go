// Package store persists notes in a SQLite database.
//
// The code is split by feature: store.go holds the connection and schema, notes.go the create/get queries
// and the helpers shared by every feature. Each further feature lives in its own file.
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

// schema is applied on every Open; every statement must be idempotent.
//
// AUTOINCREMENT guarantees that ids are never reused, even after the newest note is deleted.
const schema = `
CREATE TABLE IF NOT EXISTS notes (
	id    INTEGER PRIMARY KEY AUTOINCREMENT,
	title TEXT    NOT NULL,
	body  TEXT    NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS note_tags (
	note_id INTEGER NOT NULL REFERENCES notes (id) ON DELETE CASCADE,
	tag     TEXT    NOT NULL,
	PRIMARY KEY (note_id, tag)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS note_tags_by_tag ON note_tags (tag, note_id);
`

// Store is a SQLite-backed note store. It is safe for concurrent use.
type Store struct {
	db *sql.DB
}

// Open opens (creating if needed) the SQLite database at path and applies the schema.
func Open(ctx context.Context, path string) (*Store, error) {
	db, err := sql.Open("sqlite", dsn(path))
	if err != nil {
		return nil, fmt.Errorf("open %s: %w", path, err)
	}
	if _, err := db.ExecContext(ctx, schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("apply schema to %s: %w", path, err)
	}
	return &Store{db: db}, nil
}

// dsn builds the connection string. The pragmas apply to every pooled connection:
//   - WAL lets readers proceed while a write is in progress;
//   - busy_timeout makes writers wait for the lock instead of failing at once;
//   - foreign_keys enables ON DELETE CASCADE for tags;
//   - _txlock=immediate takes the write lock when a transaction begins, so a transaction that reads before
//     it writes cannot fail with SQLITE_BUSY halfway through.
func dsn(path string) string {
	q := url.Values{}
	q.Add("_pragma", "journal_mode(WAL)")
	q.Add("_pragma", "synchronous(NORMAL)")
	q.Add("_pragma", "busy_timeout(5000)")
	q.Add("_pragma", "foreign_keys(ON)")
	q.Set("_txlock", "immediate")
	return "file:" + path + "?" + q.Encode()
}

// Close closes the database.
func (s *Store) Close() error {
	return s.db.Close()
}

// Ping checks that the database is reachable.
func (s *Store) Ping(ctx context.Context) error {
	return s.db.PingContext(ctx)
}

// inTx runs fn in a transaction, committing if fn returns nil and rolling back otherwise.
func (s *Store) inTx(ctx context.Context, fn func(tx *sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin: %w", err)
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

// querier is implemented by both *sql.DB and *sql.Tx.
type querier interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}
