//! SQLite persistence for notes.

use std::collections::BTreeMap;
use std::path::Path;
use std::sync::{Mutex, MutexGuard};

use rusqlite::{Connection, OptionalExtension, Transaction, params};

use crate::model::{ListQuery, Note, NoteInput};

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
    CREATE INDEX IF NOT EXISTS note_tags_by_tag ON note_tags (tag, note_id);
";

/// Selects a note's columns plus its tags joined by commas (tags never contain commas).
const NOTE_COLUMNS: &str = "
    n.id, n.title, n.body,
    (SELECT group_concat(t.tag, ',' ORDER BY t.tag) FROM note_tags t WHERE t.note_id = n.id)
";

/// Thread-safe handle to the notes database.
///
/// A single connection serialises access; SQLite allows only one writer at a time anyway,
/// and this avoids `SQLITE_BUSY` handling entirely.
pub struct Store {
    conn: Mutex<Connection>,
}

impl Store {
    pub fn open(path: impl AsRef<Path>) -> rusqlite::Result<Self> {
        Self::init(Connection::open(path)?)
    }

    #[cfg(test)]
    pub fn open_in_memory() -> rusqlite::Result<Self> {
        Self::init(Connection::open_in_memory()?)
    }

    fn init(conn: Connection) -> rusqlite::Result<Self> {
        conn.pragma_update(None, "foreign_keys", true)?;
        // Create the schema before switching journal modes so the main file is written
        // (with its SQLite header) immediately.
        conn.execute_batch(SCHEMA)?;
        conn.pragma_update_and_check(None, "journal_mode", "wal", |_| Ok(()))?;
        conn.pragma_update(None, "synchronous", "normal")?;
        Ok(Self {
            conn: Mutex::new(conn),
        })
    }

    fn conn(&self) -> MutexGuard<'_, Connection> {
        // A panic while holding the lock cannot leave the connection in a bad state
        // (an open transaction is rolled back on drop), so recover from poisoning.
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
        let mut stmt =
            conn.prepare_cached(&format!("SELECT {NOTE_COLUMNS} FROM notes n WHERE n.id = ?1"))?;
        stmt.query_row([id], row_to_note).optional()
    }

    /// Replaces a note's contents; returns `None` if the note does not exist.
    pub fn replace(&self, id: i64, input: &NoteInput) -> rusqlite::Result<Option<Note>> {
        let mut conn = self.conn();
        let tx = conn.transaction()?;
        let updated = tx.execute(
            "UPDATE notes SET title = ?1, body = ?2 WHERE id = ?3",
            params![input.title, input.body, id],
        )?;
        if updated == 0 {
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

    pub fn list(&self, query: &ListQuery) -> rusqlite::Result<Vec<Note>> {
        let conn = self.conn();
        let mut stmt = conn.prepare_cached(&format!(
            "SELECT {NOTE_COLUMNS} FROM notes n
             WHERE n.id > ?1
               AND (?2 IS NULL OR EXISTS (
                     SELECT 1 FROM note_tags t WHERE t.note_id = n.id AND t.tag = ?2))
               AND (?3 IS NULL
                    OR instr(lower(n.title), lower(?3)) > 0
                    OR instr(lower(n.body), lower(?3)) > 0)
             ORDER BY n.id
             LIMIT ?4"
        ))?;
        let rows = stmt.query_map(
            params![query.after, query.tag, query.q, query.limit],
            row_to_note,
        )?;
        rows.collect()
    }

    pub fn count(&self) -> rusqlite::Result<i64> {
        self.conn()
            .query_row("SELECT count(*) FROM notes", [], |row| row.get(0))
    }

    /// Number of notes per tag, ordered by tag.
    pub fn tag_counts(&self) -> rusqlite::Result<BTreeMap<String, i64>> {
        let conn = self.conn();
        let mut stmt =
            conn.prepare_cached("SELECT tag, count(*) FROM note_tags GROUP BY tag")?;
        let rows = stmt.query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?;
        rows.collect()
    }
}

fn insert_tags(tx: &Transaction<'_>, id: i64, tags: &[String]) -> rusqlite::Result<()> {
    let mut stmt = tx.prepare_cached("INSERT INTO note_tags (note_id, tag) VALUES (?1, ?2)")?;
    for tag in tags {
        stmt.execute(params![id, tag])?;
    }
    Ok(())
}

fn note_from_input(id: i64, input: &NoteInput) -> Note {
    Note {
        id,
        title: input.title.clone(),
        body: input.body.clone(),
        tags: input.tags.clone(),
    }
}

fn row_to_note(row: &rusqlite::Row<'_>) -> rusqlite::Result<Note> {
    let tags: Option<String> = row.get(3)?;
    Ok(Note {
        id: row.get(0)?,
        title: row.get(1)?,
        body: row.get(2)?,
        tags: tags
            .map(|t| t.split(',').map(str::to_owned).collect())
            .unwrap_or_default(),
    })
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
    fn crud_and_id_never_reused() {
        let store = Store::open_in_memory().unwrap();
        let a = store.create(&input("a", "", &["x", "y"])).unwrap();
        let b = store.create(&input("b", "", &[])).unwrap();
        assert_eq!((a.id, b.id), (1, 2));
        assert_eq!(store.get(1).unwrap(), Some(a));
        assert!(store.delete(2).unwrap());
        assert!(!store.delete(2).unwrap());
        assert_eq!(store.create(&input("c", "", &[])).unwrap().id, 3);

        let replaced = store.replace(1, &input("A", "body", &["z"])).unwrap().unwrap();
        assert_eq!(store.get(1).unwrap(), Some(replaced));
        assert_eq!(store.replace(2, &input("x", "", &[])).unwrap(), None);
    }

    #[test]
    fn listing_and_stats() {
        let store = Store::open_in_memory().unwrap();
        store.create(&input("Hello", "", &["g"])).unwrap();
        store.create(&input("other", "say HELLO 100%", &["g", "m"])).unwrap();
        store.create(&input("none", "", &[])).unwrap();

        let ids = |q: ListQuery| -> Vec<i64> {
            store.list(&q).unwrap().into_iter().map(|n| n.id).collect()
        };
        assert_eq!(ids(ListQuery::default()), [1, 2, 3]);
        let q = |s: &str| ListQuery::parse(Some(s)).unwrap();
        assert_eq!(ids(q("q=hello")), [1, 2]);
        assert_eq!(ids(q("q=0%25")), [2]);
        assert_eq!(ids(q("q=_")), Vec::<i64>::new());
        assert_eq!(ids(q("tag=m&q=hello")), [2]);
        assert_eq!(ids(q("after=1&limit=1")), [2]);

        store.delete(2).unwrap();
        assert_eq!(store.count().unwrap(), 2);
        assert_eq!(
            store.tag_counts().unwrap(),
            BTreeMap::from([("g".to_owned(), 1)])
        );
    }
}
