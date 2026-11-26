//! SQLite-backed note storage.

use std::path::Path;
use std::sync::{Mutex, MutexGuard};

use rusqlite::{Connection, OptionalExtension, Transaction, params};

use crate::model::{Note, NoteInput};

const SCHEMA: &str = "
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
";

/// Filters for listing notes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ListFilter {
    pub tag: Option<String>,
    pub q: Option<String>,
    pub after: i64,
    pub limit: usize,
}

impl Default for ListFilter {
    fn default() -> Self {
        Self {
            tag: None,
            q: None,
            after: i64::MIN,
            limit: 100,
        }
    }
}

/// Thread-safe handle to the notes database.
///
/// A single connection serialises all access, which keeps id assignment and
/// multi-statement updates trivially consistent.
pub struct Store {
    conn: Mutex<Connection>,
}

impl Store {
    /// Opens (creating if needed) the database at `path` and ensures the schema exists.
    pub fn open(path: impl AsRef<Path>) -> rusqlite::Result<Self> {
        Self::init(Connection::open(path)?)
    }

    #[cfg(test)]
    pub fn open_in_memory() -> rusqlite::Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> rusqlite::Result<Self> {
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        conn.pragma_update(None, "foreign_keys", true)?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    fn conn(&self) -> MutexGuard<'_, Connection> {
        // A panic while holding the lock cannot leave SQLite in a torn state
        // (transactions roll back on drop), so recovering from poison is safe.
        self.conn.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn create(&self, input: &NoteInput) -> rusqlite::Result<Note> {
        let mut conn = self.conn();
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO notes (title, body) VALUES (?1, ?2)",
            params![input.title, input.body],
        )?;
        let id = tx.last_insert_rowid();
        insert_tags(&tx, id, &input.tags)?;
        tx.commit()?;
        Ok(note_from_input(id, input))
    }

    pub fn get(&self, id: i64) -> rusqlite::Result<Option<Note>> {
        let conn = self.conn();
        let row = conn
            .query_row(
                "SELECT title, body FROM notes WHERE id = ?1",
                [id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()?;
        row.map(|(title, body)| {
            Ok(Note {
                id,
                title,
                body,
                tags: load_tags(&conn, id)?,
            })
        })
        .transpose()
    }

    /// Replaces a note's contents; returns `None` if it does not exist.
    pub fn update(&self, id: i64, input: &NoteInput) -> rusqlite::Result<Option<Note>> {
        let mut conn = self.conn();
        let tx = conn.transaction()?;
        let changed = tx.execute(
            "UPDATE notes SET title = ?1, body = ?2 WHERE id = ?3",
            params![input.title, input.body, id],
        )?;
        if changed == 0 {
            return Ok(None);
        }
        tx.execute("DELETE FROM note_tags WHERE note_id = ?1", [id])?;
        insert_tags(&tx, id, &input.tags)?;
        tx.commit()?;
        Ok(Some(note_from_input(id, input)))
    }

    /// Deletes a note; returns whether it existed.
    pub fn delete(&self, id: i64) -> rusqlite::Result<bool> {
        let conn = self.conn();
        Ok(conn.execute("DELETE FROM notes WHERE id = ?1", [id])? > 0)
    }

    /// Lists notes matching `filter`, ordered by id ascending.
    pub fn list(&self, filter: &ListFilter) -> rusqlite::Result<Vec<Note>> {
        let conn = self.conn();
        let mut stmt = conn.prepare_cached(
            "SELECT id, title, body FROM notes
             WHERE id > ?1
               AND (?2 IS NULL OR EXISTS (
                    SELECT 1 FROM note_tags t WHERE t.note_id = notes.id AND t.tag = ?2))
             ORDER BY id",
        )?;
        let mut rows = stmt.query(params![filter.after, filter.tag])?;
        let mut notes = Vec::new();
        while notes.len() < filter.limit {
            let Some(row) = rows.next()? else { break };
            let title: String = row.get(1)?;
            let body: String = row.get(2)?;
            if let Some(q) = &filter.q
                && !contains_ignore_ascii_case(&title, q)
                && !contains_ignore_ascii_case(&body, q)
            {
                continue;
            }
            let id = row.get(0)?;
            notes.push(Note {
                id,
                title,
                body,
                tags: load_tags(&conn, id)?,
            });
        }
        Ok(notes)
    }

    /// Total number of notes.
    pub fn count(&self) -> rusqlite::Result<i64> {
        self.conn()
            .query_row("SELECT COUNT(*) FROM notes", [], |row| row.get(0))
    }

    /// Every tag in use with the number of notes carrying it, ordered by
    /// count descending, then tag ascending.
    pub fn tag_counts(&self) -> rusqlite::Result<Vec<(String, i64)>> {
        let conn = self.conn();
        let mut stmt = conn.prepare_cached(
            "SELECT tag, COUNT(*) AS n FROM note_tags GROUP BY tag ORDER BY n DESC, tag ASC",
        )?;
        stmt.query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
            .collect()
    }
}

fn note_from_input(id: i64, input: &NoteInput) -> Note {
    Note {
        id,
        title: input.title.clone(),
        body: input.body.clone(),
        tags: input.tags.clone(),
    }
}

fn insert_tags(tx: &Transaction<'_>, id: i64, tags: &[String]) -> rusqlite::Result<()> {
    let mut stmt = tx.prepare_cached("INSERT INTO note_tags (note_id, tag) VALUES (?1, ?2)")?;
    for tag in tags {
        stmt.execute(params![id, tag])?;
    }
    Ok(())
}

fn load_tags(conn: &Connection, id: i64) -> rusqlite::Result<Vec<String>> {
    let mut stmt = conn.prepare_cached("SELECT tag FROM note_tags WHERE note_id = ?1 ORDER BY tag")?;
    stmt.query_map([id], |row| row.get(0))?.collect()
}

/// Whether `haystack` contains `needle`, comparing ASCII letters case-insensitively.
fn contains_ignore_ascii_case(haystack: &str, needle: &str) -> bool {
    let (h, n) = (haystack.as_bytes(), needle.as_bytes());
    n.is_empty() || h.windows(n.len()).any(|w| w.eq_ignore_ascii_case(n))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input(title: &str, body: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: body.into(),
            tags: tags.iter().map(|t| t.to_string()).collect(),
        }
    }

    #[test]
    fn ids_are_never_reused() {
        let store = Store::open_in_memory().unwrap();
        assert_eq!(store.create(&input("a", "", &[])).unwrap().id, 1);
        assert_eq!(store.create(&input("b", "", &[])).unwrap().id, 2);
        assert!(store.delete(2).unwrap());
        assert!(!store.delete(2).unwrap());
        assert_eq!(store.create(&input("c", "", &[])).unwrap().id, 3);
    }

    #[test]
    fn persists_across_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("notes.db");
        {
            let store = Store::open(&path).unwrap();
            store.create(&input("a", "x", &["t"])).unwrap();
            store.create(&input("b", "", &[])).unwrap();
            store.delete(2).unwrap();
        }
        let store = Store::open(&path).unwrap();
        assert_eq!(store.get(1).unwrap().unwrap().tags, ["t"]);
        assert_eq!(store.create(&input("c", "", &[])).unwrap().id, 3);
    }

    #[test]
    fn update_replaces_tags() {
        let store = Store::open_in_memory().unwrap();
        store.create(&input("a", "x", &["old"])).unwrap();
        let note = store.update(1, &input("b", "", &["new"])).unwrap().unwrap();
        assert_eq!(store.get(1).unwrap().unwrap(), note);
        assert_eq!(store.tag_counts().unwrap(), [("new".to_string(), 1)]);
        assert!(store.update(9, &input("b", "", &[])).unwrap().is_none());
    }

    #[test]
    fn list_filters() {
        let store = Store::open_in_memory().unwrap();
        store.create(&input("Hello", "", &["g"])).unwrap();
        store.create(&input("other", "say HELLO", &["g", "m"])).unwrap();
        store.create(&input("none", "", &[])).unwrap();
        let ids = |f: ListFilter| -> Vec<i64> {
            store.list(&f).unwrap().iter().map(|n| n.id).collect()
        };
        assert_eq!(ids(ListFilter::default()), [1, 2, 3]);
        let q = Some("hello".to_string());
        assert_eq!(ids(ListFilter { q: q.clone(), ..Default::default() }), [1, 2]);
        let tag = Some("m".to_string());
        assert_eq!(ids(ListFilter { tag, q, ..Default::default() }), [2]);
        assert_eq!(ids(ListFilter { after: 1, limit: 1, ..Default::default() }), [2]);
    }

    #[test]
    fn tag_counts_ignore_deleted_notes() {
        let store = Store::open_in_memory().unwrap();
        store.create(&input("a", "", &["x", "y"])).unwrap();
        store.create(&input("b", "", &["y"])).unwrap();
        store.create(&input("c", "", &["z"])).unwrap();
        store.delete(3).unwrap();
        assert_eq!(
            store.tag_counts().unwrap(),
            [("y".to_string(), 2), ("x".to_string(), 1)]
        );
        assert_eq!(store.count().unwrap(), 2);
    }

    #[test]
    fn ascii_case_insensitive_contains() {
        assert!(contains_ignore_ascii_case("Say HELLO", "hello"));
        assert!(contains_ignore_ascii_case("abc", ""));
        assert!(!contains_ignore_ascii_case("ÉCOLE", "école"));
    }
}
