// Package store persists notes in a SQLite database.
package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"strings"

	_ "modernc.org/sqlite" // registers the "sqlite" driver
)

// ErrNotFound is returned when a note does not exist.
var ErrNotFound = errors.New("note not found")

// Note is a stored note.
type Note struct {
	ID    int64    `json:"id"`
	Title string   `json:"title"`
	Body  string   `json:"body"`
	Tags  []string `json:"tags"`
}

// TagCount is the number of notes carrying a tag.
type TagCount struct {
	Tag   string `json:"tag"`
	Count int64  `json:"count"`
}

// ListFilter selects notes for List. Zero values mean "no filter".
type ListFilter struct {
	Tag      string
	HasTag   bool
	Query    string
	After    int64
	HasAfter bool
	Limit    int
}

// Store is a SQLite-backed note store. It is safe for concurrent use.
type Store struct {
	db *sql.DB
}

const schema = `
CREATE TABLE IF NOT EXISTS notes (
	id    INTEGER PRIMARY KEY AUTOINCREMENT,
	title TEXT NOT NULL,
	body  TEXT NOT NULL,
	tags  TEXT NOT NULL DEFAULT '[]'
);
CREATE TABLE IF NOT EXISTS note_tags (
	note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
	tag     TEXT NOT NULL,
	PRIMARY KEY (note_id, tag)
) WITHOUT ROWID;
CREATE INDEX IF NOT EXISTS note_tags_tag ON note_tags(tag, note_id);
`

// Open opens (creating if needed) the database at path and ensures the schema exists.
func Open(ctx context.Context, path string) (*Store, error) {
	q := url.Values{}
	q.Add("_pragma", "busy_timeout(10000)")
	q.Add("_pragma", "journal_mode(WAL)")
	q.Add("_pragma", "synchronous(NORMAL)")
	q.Add("_pragma", "foreign_keys(ON)")
	q.Set("_txlock", "immediate")
	dsn := "file:" + (&url.URL{Path: path}).EscapedPath() + "?" + q.Encode()

	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	db.SetMaxOpenConns(8)
	db.SetMaxIdleConns(8)
	if _, err := db.ExecContext(ctx, schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("create schema: %w", err)
	}
	return &Store{db: db}, nil
}

// Close closes the database.
func (s *Store) Close() error { return s.db.Close() }

// Create inserts a new note and returns it with its assigned id.
func (s *Store) Create(ctx context.Context, title, body string, tags []string) (Note, error) {
	n := Note{Title: title, Body: body, Tags: tags}
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		tagsJSON, err := json.Marshal(tags)
		if err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx, `INSERT INTO notes (title, body, tags) VALUES (?, ?, ?)`, title, body, string(tagsJSON))
		if err != nil {
			return err
		}
		if n.ID, err = res.LastInsertId(); err != nil {
			return err
		}
		return insertTags(ctx, tx, n.ID, tags)
	})
	if err != nil {
		return Note{}, fmt.Errorf("create note: %w", err)
	}
	return n, nil
}

// Update replaces the note with the given id.
func (s *Store) Update(ctx context.Context, id int64, title, body string, tags []string) (Note, error) {
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		tagsJSON, err := json.Marshal(tags)
		if err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx, `UPDATE notes SET title = ?, body = ?, tags = ? WHERE id = ?`, title, body, string(tagsJSON), id)
		if err != nil {
			return err
		}
		if n, err := res.RowsAffected(); err != nil {
			return err
		} else if n == 0 {
			return ErrNotFound
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM note_tags WHERE note_id = ?`, id); err != nil {
			return err
		}
		return insertTags(ctx, tx, id, tags)
	})
	if errors.Is(err, ErrNotFound) {
		return Note{}, err
	}
	if err != nil {
		return Note{}, fmt.Errorf("update note %d: %w", id, err)
	}
	return Note{ID: id, Title: title, Body: body, Tags: tags}, nil
}

// Delete removes the note with the given id.
func (s *Store) Delete(ctx context.Context, id int64) error {
	err := s.withTx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `DELETE FROM note_tags WHERE note_id = ?`, id); err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx, `DELETE FROM notes WHERE id = ?`, id)
		if err != nil {
			return err
		}
		if n, err := res.RowsAffected(); err != nil {
			return err
		} else if n == 0 {
			return ErrNotFound
		}
		return nil
	})
	if err != nil && !errors.Is(err, ErrNotFound) {
		return fmt.Errorf("delete note %d: %w", id, err)
	}
	return err
}

// Get returns the note with the given id.
func (s *Store) Get(ctx context.Context, id int64) (Note, error) {
	row := s.db.QueryRowContext(ctx, `SELECT id, title, body, tags FROM notes WHERE id = ?`, id)
	n, err := scanNote(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Note{}, ErrNotFound
	}
	if err != nil {
		return Note{}, fmt.Errorf("get note %d: %w", id, err)
	}
	return n, nil
}

// List returns notes matching f, ordered by id ascending.
func (s *Store) List(ctx context.Context, f ListFilter) ([]Note, error) {
	var (
		where []string
		args  []any
	)
	if f.HasTag {
		where = append(where, `id IN (SELECT note_id FROM note_tags WHERE tag = ?)`)
		args = append(args, f.Tag)
	}
	if f.Query != "" {
		// SQLite's built-in lower() folds ASCII letters only, which is exactly what we want.
		where = append(where, `(instr(lower(title), lower(?)) > 0 OR instr(lower(body), lower(?)) > 0)`)
		args = append(args, f.Query, f.Query)
	}
	if f.HasAfter {
		where = append(where, `id > ?`)
		args = append(args, f.After)
	}
	query := `SELECT id, title, body, tags FROM notes`
	if len(where) > 0 {
		query += ` WHERE ` + strings.Join(where, ` AND `)
	}
	query += ` ORDER BY id ASC LIMIT ?`
	args = append(args, f.Limit)

	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	defer rows.Close()
	notes := []Note{}
	for rows.Next() {
		n, err := scanNote(rows)
		if err != nil {
			return nil, fmt.Errorf("list notes: %w", err)
		}
		notes = append(notes, n)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	return notes, nil
}

// Stats returns the number of notes and the per-tag note counts, from one consistent snapshot.
func (s *Store) Stats(ctx context.Context) (int64, []TagCount, error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{ReadOnly: true})
	if err != nil {
		return 0, nil, fmt.Errorf("stats: %w", err)
	}
	defer tx.Rollback()

	var count int64
	if err := tx.QueryRowContext(ctx, `SELECT count(*) FROM notes`).Scan(&count); err != nil {
		return 0, nil, fmt.Errorf("stats: %w", err)
	}
	tags, err := tagCounts(ctx, tx)
	if err != nil {
		return 0, nil, fmt.Errorf("stats: %w", err)
	}
	return count, tags, nil
}

// Tags returns per-tag note counts ordered by count descending, then tag ascending.
func (s *Store) Tags(ctx context.Context) ([]TagCount, error) {
	tags, err := tagCounts(ctx, s.db)
	if err != nil {
		return nil, fmt.Errorf("tags: %w", err)
	}
	return tags, nil
}

type querier interface {
	QueryContext(ctx context.Context, query string, args ...any) (*sql.Rows, error)
}

func tagCounts(ctx context.Context, q querier) ([]TagCount, error) {
	rows, err := q.QueryContext(ctx,
		`SELECT tag, count(*) AS c FROM note_tags GROUP BY tag ORDER BY c DESC, tag ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := []TagCount{}
	for rows.Next() {
		var tc TagCount
		if err := rows.Scan(&tc.Tag, &tc.Count); err != nil {
			return nil, err
		}
		out = append(out, tc)
	}
	return out, rows.Err()
}

type scanner interface {
	Scan(dest ...any) error
}

func scanNote(sc scanner) (Note, error) {
	var (
		n        Note
		tagsJSON string
	)
	if err := sc.Scan(&n.ID, &n.Title, &n.Body, &tagsJSON); err != nil {
		return Note{}, err
	}
	if err := json.Unmarshal([]byte(tagsJSON), &n.Tags); err != nil {
		return Note{}, fmt.Errorf("decode tags of note %d: %w", n.ID, err)
	}
	if n.Tags == nil {
		n.Tags = []string{}
	}
	return n, nil
}

func insertTags(ctx context.Context, tx *sql.Tx, id int64, tags []string) error {
	if len(tags) == 0 {
		return nil
	}
	stmt, err := tx.PrepareContext(ctx, `INSERT INTO note_tags (note_id, tag) VALUES (?, ?)`)
	if err != nil {
		return err
	}
	defer stmt.Close()
	for _, t := range tags {
		if _, err := stmt.ExecContext(ctx, id, t); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) withTx(ctx context.Context, fn func(*sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		_ = tx.Rollback()
		return err
	}
	return tx.Commit()
}
