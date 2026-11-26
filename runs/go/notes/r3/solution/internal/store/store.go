// Package store persists notes in a SQLite database.
package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"slices"
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
	Tag   string
	Query string
	After int64
	Limit int
}

// Store is a SQLite-backed notes store, safe for concurrent use.
type Store struct {
	db *sql.DB
}

const schema = `
CREATE TABLE IF NOT EXISTS notes (
	id    INTEGER PRIMARY KEY AUTOINCREMENT,
	title TEXT NOT NULL,
	body  TEXT NOT NULL
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
	dsn := "file:" + path + "?" + q.Encode()

	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
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
	var n Note
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `INSERT INTO notes (title, body) VALUES (?, ?)`, title, body)
		if err != nil {
			return err
		}
		id, err := res.LastInsertId()
		if err != nil {
			return err
		}
		if err := insertTags(ctx, tx, id, tags); err != nil {
			return err
		}
		n = Note{ID: id, Title: title, Body: body, Tags: tags}
		return nil
	})
	return n, err
}

// Update replaces the content of an existing note.
func (s *Store) Update(ctx context.Context, id int64, title, body string, tags []string) (Note, error) {
	var n Note
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `UPDATE notes SET title = ?, body = ? WHERE id = ?`, title, body, id)
		if err != nil {
			return err
		}
		if affected, err := res.RowsAffected(); err != nil {
			return err
		} else if affected == 0 {
			return ErrNotFound
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM note_tags WHERE note_id = ?`, id); err != nil {
			return err
		}
		if err := insertTags(ctx, tx, id, tags); err != nil {
			return err
		}
		n = Note{ID: id, Title: title, Body: body, Tags: tags}
		return nil
	})
	return n, err
}

// Delete removes a note and its tags.
func (s *Store) Delete(ctx context.Context, id int64) error {
	return s.inTx(ctx, func(tx *sql.Tx) error {
		if _, err := tx.ExecContext(ctx, `DELETE FROM note_tags WHERE note_id = ?`, id); err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx, `DELETE FROM notes WHERE id = ?`, id)
		if err != nil {
			return err
		}
		if affected, err := res.RowsAffected(); err != nil {
			return err
		} else if affected == 0 {
			return ErrNotFound
		}
		return nil
	})
}

// Get returns the note with the given id.
func (s *Store) Get(ctx context.Context, id int64) (Note, error) {
	notes, err := s.queryNotes(ctx, `SELECT id, title, body FROM notes WHERE id = ?`, id)
	if err != nil {
		return Note{}, err
	}
	if len(notes) == 0 {
		return Note{}, ErrNotFound
	}
	return notes[0], nil
}

// List returns notes matching f, ordered by id ascending.
func (s *Store) List(ctx context.Context, f ListFilter) ([]Note, error) {
	var (
		where []string
		args  []any
	)
	if f.After != 0 {
		where = append(where, "n.id > ?")
		args = append(args, f.After)
	}
	if f.Tag != "" {
		where = append(where, "EXISTS (SELECT 1 FROM note_tags t WHERE t.note_id = n.id AND t.tag = ?)")
		args = append(args, f.Tag)
	}
	if f.Query != "" {
		// SQLite's LIKE is case-insensitive for ASCII characters only, which is exactly what we want.
		where = append(where, `(n.title LIKE ? ESCAPE '\' OR n.body LIKE ? ESCAPE '\')`)
		pattern := "%" + escapeLike(f.Query) + "%"
		args = append(args, pattern, pattern)
	}
	query := "SELECT n.id, n.title, n.body FROM notes n"
	if len(where) > 0 {
		query += " WHERE " + strings.Join(where, " AND ")
	}
	query += " ORDER BY n.id"
	if f.Limit > 0 {
		query += " LIMIT ?"
		args = append(args, f.Limit)
	}
	return s.queryNotes(ctx, query, args...)
}

// TagCounts returns every tag in use with its note count, ordered by count
// descending, then tag ascending.
func (s *Store) TagCounts(ctx context.Context) ([]TagCount, error) {
	_, counts, err := s.stats(ctx)
	return counts, err
}

// Stats returns the number of notes and the per-tag note counts, taken from
// one consistent snapshot. Tags are ordered as in TagCounts.
func (s *Store) Stats(ctx context.Context) (int64, []TagCount, error) {
	return s.stats(ctx)
}

func (s *Store) stats(ctx context.Context) (int64, []TagCount, error) {
	// A single statement reads from a single snapshot, so the note count and
	// the tag counts always agree. The first row (NULL tag) is the note count.
	rows, err := s.db.QueryContext(ctx, `
		SELECT NULL, COUNT(*), 0 FROM notes
		UNION ALL
		SELECT * FROM (SELECT tag, COUNT(*) AS c, 1 FROM note_tags GROUP BY tag)
		ORDER BY 3, 2 DESC, 1 ASC`)
	if err != nil {
		return 0, nil, err
	}
	defer rows.Close()
	var (
		total  int64
		counts = []TagCount{}
	)
	for rows.Next() {
		var (
			tag   sql.NullString
			count int64
			kind  int
		)
		if err := rows.Scan(&tag, &count, &kind); err != nil {
			return 0, nil, err
		}
		if kind == 0 {
			total = count
			continue
		}
		counts = append(counts, TagCount{Tag: tag.String, Count: count})
	}
	return total, counts, rows.Err()
}

func (s *Store) queryNotes(ctx context.Context, query string, args ...any) ([]Note, error) {
	// Fetching notes and their tags in one statement keeps the result consistent
	// without an explicit transaction. Tags never contain commas, so group_concat is safe.
	full := `SELECT q.id, q.title, q.body,
		(SELECT group_concat(tag, ',') FROM note_tags WHERE note_id = q.id)
		FROM (` + query + `) q ORDER BY q.id`
	rows, err := s.db.QueryContext(ctx, full, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	notes := []Note{}
	for rows.Next() {
		var (
			n    Note
			tags sql.NullString
		)
		if err := rows.Scan(&n.ID, &n.Title, &n.Body, &tags); err != nil {
			return nil, err
		}
		n.Tags = []string{}
		if tags.Valid && tags.String != "" {
			n.Tags = strings.Split(tags.String, ",")
			slices.Sort(n.Tags)
		}
		notes = append(notes, n)
	}
	return notes, rows.Err()
}

func (s *Store) inTx(ctx context.Context, fn func(*sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	if err := fn(tx); err != nil {
		tx.Rollback()
		return err
	}
	return tx.Commit()
}

func insertTags(ctx context.Context, tx *sql.Tx, id int64, tags []string) error {
	if len(tags) == 0 {
		return nil
	}
	stmt, err := tx.PrepareContext(ctx, `INSERT OR IGNORE INTO note_tags (note_id, tag) VALUES (?, ?)`)
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

func escapeLike(s string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return r.Replace(s)
}
