package notes

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"
	"strings"

	_ "modernc.org/sqlite" // registers the "sqlite" driver
)

// ErrNotFound is returned when a note does not exist.
var ErrNotFound = errors.New("note not found")

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
CREATE INDEX IF NOT EXISTS note_tags_by_tag ON note_tags(tag, note_id);
`

// Store persists notes in a SQLite database.
type Store struct {
	db *sql.DB
}

// Open opens (creating if needed) the SQLite database at path and ensures the schema exists.
func Open(ctx context.Context, path string) (*Store, error) {
	q := url.Values{}
	for _, p := range []string{"foreign_keys(1)", "busy_timeout(5000)", "journal_mode(WAL)", "synchronous(NORMAL)"} {
		q.Add("_pragma", p)
	}
	dsn := (&url.URL{Scheme: "file", OmitHost: true, Path: path, RawQuery: q.Encode()}).String()
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}
	// SQLite allows a single writer; one shared connection serializes access
	// without SQLITE_BUSY errors while database/sql queues concurrent callers.
	db.SetMaxOpenConns(1)
	if _, err := db.ExecContext(ctx, schema); err != nil {
		db.Close()
		return nil, fmt.Errorf("create schema: %w", err)
	}
	return &Store{db: db}, nil
}

// Close closes the underlying database.
func (s *Store) Close() error { return s.db.Close() }

// Create stores a new note and returns it.
func (s *Store) Create(ctx context.Context, in Input) (Note, error) {
	var id int64
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `INSERT INTO notes (title, body) VALUES (?, ?)`, in.Title, in.Body)
		if err != nil {
			return err
		}
		if id, err = res.LastInsertId(); err != nil {
			return err
		}
		return insertTags(ctx, tx, id, in.Tags)
	})
	if err != nil {
		return Note{}, fmt.Errorf("create note: %w", err)
	}
	return Note{ID: id, Title: in.Title, Body: in.Body, Tags: in.Tags}, nil
}

// Get returns the note with the given id or ErrNotFound.
func (s *Store) Get(ctx context.Context, id int64) (Note, error) {
	n := Note{ID: id}
	err := s.db.QueryRowContext(ctx, `SELECT title, body FROM notes WHERE id = ?`, id).Scan(&n.Title, &n.Body)
	if errors.Is(err, sql.ErrNoRows) {
		return Note{}, ErrNotFound
	}
	if err != nil {
		return Note{}, fmt.Errorf("get note: %w", err)
	}
	tags, err := s.tagsFor(ctx, []int64{id})
	if err != nil {
		return Note{}, err
	}
	n.Tags = tags[id]
	if n.Tags == nil {
		n.Tags = []string{}
	}
	return n, nil
}

// Update replaces the content of an existing note or returns ErrNotFound.
func (s *Store) Update(ctx context.Context, id int64, in Input) (Note, error) {
	err := s.inTx(ctx, func(tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx, `UPDATE notes SET title = ?, body = ? WHERE id = ?`, in.Title, in.Body, id)
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
		return insertTags(ctx, tx, id, in.Tags)
	})
	if errors.Is(err, ErrNotFound) {
		return Note{}, err
	}
	if err != nil {
		return Note{}, fmt.Errorf("update note: %w", err)
	}
	return Note{ID: id, Title: in.Title, Body: in.Body, Tags: in.Tags}, nil
}

// Delete removes a note or returns ErrNotFound.
func (s *Store) Delete(ctx context.Context, id int64) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM notes WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("delete note: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("delete note: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

// Filter selects notes in List. Zero values mean "no constraint", except Limit which must be positive.
type Filter struct {
	Tag   string
	Query string
	After int64
	Limit int
}

// List returns notes matching f, ordered by id ascending.
func (s *Store) List(ctx context.Context, f Filter) ([]Note, error) {
	var (
		where []string
		args  []any
	)
	if f.Tag != "" {
		where = append(where, `EXISTS (SELECT 1 FROM note_tags t WHERE t.note_id = n.id AND t.tag = ?)`)
		args = append(args, f.Tag)
	}
	if f.Query != "" {
		// SQLite's built-in lower() folds ASCII letters only, which is exactly the required matching.
		where = append(where, `(instr(lower(n.title), lower(?)) > 0 OR instr(lower(n.body), lower(?)) > 0)`)
		args = append(args, f.Query, f.Query)
	}
	where = append(where, `n.id > ?`)
	args = append(args, f.After)

	query := `SELECT n.id, n.title, n.body FROM notes n WHERE ` + strings.Join(where, " AND ") + ` ORDER BY n.id LIMIT ?`
	args = append(args, f.Limit)

	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	defer rows.Close()

	list := []Note{}
	var ids []int64
	for rows.Next() {
		var n Note
		if err := rows.Scan(&n.ID, &n.Title, &n.Body); err != nil {
			return nil, fmt.Errorf("list notes: %w", err)
		}
		list = append(list, n)
		ids = append(ids, n.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list notes: %w", err)
	}
	rows.Close()

	tags, err := s.tagsFor(ctx, ids)
	if err != nil {
		return nil, err
	}
	for i := range list {
		list[i].Tags = tags[list[i].ID]
		if list[i].Tags == nil {
			list[i].Tags = []string{}
		}
	}
	return list, nil
}

// TagCount is the number of notes carrying a tag.
type TagCount struct {
	Tag   string `json:"tag"`
	Count int64  `json:"count"`
}

// TagCounts returns every tag in use, ordered by count descending, then tag ascending.
func (s *Store) TagCounts(ctx context.Context) ([]TagCount, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT tag, COUNT(*) AS c FROM note_tags GROUP BY tag ORDER BY c DESC, tag ASC`)
	if err != nil {
		return nil, fmt.Errorf("count tags: %w", err)
	}
	defer rows.Close()
	counts := []TagCount{}
	for rows.Next() {
		var tc TagCount
		if err := rows.Scan(&tc.Tag, &tc.Count); err != nil {
			return nil, fmt.Errorf("count tags: %w", err)
		}
		counts = append(counts, tc)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("count tags: %w", err)
	}
	return counts, nil
}

// Count returns the number of stored notes.
func (s *Store) Count(ctx context.Context) (int64, error) {
	var n int64
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM notes`).Scan(&n); err != nil {
		return 0, fmt.Errorf("count notes: %w", err)
	}
	return n, nil
}

func (s *Store) tagsFor(ctx context.Context, ids []int64) (map[int64][]string, error) {
	out := make(map[int64][]string, len(ids))
	if len(ids) == 0 {
		return out, nil
	}
	args := make([]any, len(ids))
	for i, id := range ids {
		args[i] = id
	}
	placeholders := strings.TrimSuffix(strings.Repeat("?,", len(ids)), ",")
	rows, err := s.db.QueryContext(ctx,
		`SELECT note_id, tag FROM note_tags WHERE note_id IN (`+placeholders+`) ORDER BY note_id, tag`, args...)
	if err != nil {
		return nil, fmt.Errorf("load tags: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var (
			id  int64
			tag string
		)
		if err := rows.Scan(&id, &tag); err != nil {
			return nil, fmt.Errorf("load tags: %w", err)
		}
		out[id] = append(out[id], tag)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("load tags: %w", err)
	}
	return out, nil
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
	for _, tag := range tags {
		if _, err := stmt.ExecContext(ctx, id, tag); err != nil {
			return err
		}
	}
	return nil
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
