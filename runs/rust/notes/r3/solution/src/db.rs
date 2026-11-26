//! SQLite-backed persistence for notes.

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
CREATE INDEX IF NOT EXISTS note_tags_tag ON note_tags(tag, note_id);
";

/// Thread-safe handle to the notes database.
///
/// A single connection serialised by a mutex keeps writes consistent; callers
/// are expected to invoke these methods from a blocking-capable thread.
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
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.pragma_update(None, "synchronous", "NORMAL")?;
        conn.pragma_update(None, "foreign_keys", true)?;
        conn.busy_timeout(std::time::Duration::from_secs(5))?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self { conn: Mutex::new(conn) })
    }

    fn conn(&self) -> MutexGuard<'_, Connection> {
        // A panic while holding the lock cannot leave SQLite in a torn state
        // (transactions roll back on drop), so recovering is safe.
        self.conn.lock().unwrap_or_else(|e| e.into_inner())
    }

    pub fn create(&self, input: NoteInput) -> rusqlite::Result<Note> {
        let mut conn = self.conn();
        let tx = conn.transaction()?;
        tx.execute(
            "INSERT INTO notes (title, body) VALUES (?1, ?2)",
            params![input.title, input.body],
        )?;
        let id = tx.last_insert_rowid();
        insert_tags(&tx, id, &input.tags)?;
        tx.commit()?;
        Ok(Note { id, title: input.title, body: input.body, tags: input.tags })
    }

    pub fn get(&self, id: i64) -> rusqlite::Result<Option<Note>> {
        let conn = self.conn();
        let row = conn
            .query_row("SELECT title, body FROM notes WHERE id = ?1", [id], |r| {
                Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?))
            })
            .optional()?;
        let Some((title, body)) = row else { return Ok(None) };
        let tags = conn
            .prepare_cached("SELECT tag FROM note_tags WHERE note_id = ?1 ORDER BY tag")?
            .query_map([id], |r| r.get(0))?
            .collect::<rusqlite::Result<Vec<String>>>()?;
        Ok(Some(Note { id, title, body, tags }))
    }

    /// Replaces a note's content; returns `None` if it does not exist.
    pub fn update(&self, id: i64, input: NoteInput) -> rusqlite::Result<Option<Note>> {
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
        Ok(Some(Note { id, title: input.title, body: input.body, tags: input.tags }))
    }

    /// Deletes a note; returns whether it existed.
    pub fn delete(&self, id: i64) -> rusqlite::Result<bool> {
        let conn = self.conn();
        Ok(conn.execute("DELETE FROM notes WHERE id = ?1", [id])? > 0)
    }

    pub fn list(&self, query: &ListQuery) -> rusqlite::Result<Vec<Note>> {
        let conn = self.conn();
        let mut stmt = conn.prepare_cached(
            "SELECT n.id, n.title, n.body,
                    (SELECT group_concat(t.tag, ',') FROM note_tags t WHERE t.note_id = n.id)
             FROM notes n
             WHERE n.id > ?1
               AND (?2 IS NULL OR EXISTS
                    (SELECT 1 FROM note_tags t WHERE t.note_id = n.id AND t.tag = ?2))
               AND (?3 IS NULL OR instr(lower(n.title), lower(?3)) > 0
                               OR instr(lower(n.body), lower(?3)) > 0)
             ORDER BY n.id
             LIMIT ?4",
        )?;
        let rows = stmt.query_map(
            params![query.after.unwrap_or(i64::MIN), query.tag, query.q, query.limit],
            |r| {
                // Tags never contain commas, so the concatenation splits cleanly.
                let joined: Option<String> = r.get(3)?;
                let mut tags: Vec<String> = joined
                    .map(|s| s.split(',').map(str::to_owned).collect())
                    .unwrap_or_default();
                tags.sort_unstable();
                Ok(Note { id: r.get(0)?, title: r.get(1)?, body: r.get(2)?, tags })
            },
        )?;
        rows.collect()
    }

    /// Number of notes per tag, ordered by count descending, then tag ascending.
    pub fn tag_counts(&self) -> rusqlite::Result<Vec<(String, i64)>> {
        let conn = self.conn();
        let mut stmt = conn.prepare_cached(
            "SELECT tag, count(*) AS c FROM note_tags GROUP BY tag ORDER BY c DESC, tag ASC",
        )?;
        let rows = stmt.query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?;
        rows.collect()
    }

    /// Note count and per-tag counts read in one consistent snapshot.
    pub fn stats(&self) -> rusqlite::Result<(i64, BTreeMap<String, i64>)> {
        let mut conn = self.conn();
        let tx = conn.transaction()?;
        let count = tx.query_row("SELECT count(*) FROM notes", [], |r| r.get(0))?;
        let tags = tx
            .prepare_cached("SELECT tag, count(*) FROM note_tags GROUP BY tag")?
            .query_map([], |r| Ok((r.get(0)?, r.get(1)?)))?
            .collect::<rusqlite::Result<_>>()?;
        Ok((count, tags))
    }
}

fn insert_tags(tx: &Transaction<'_>, id: i64, tags: &[String]) -> rusqlite::Result<()> {
    let mut stmt = tx.prepare_cached("INSERT INTO note_tags (note_id, tag) VALUES (?1, ?2)")?;
    for tag in tags {
        stmt.execute(params![id, tag])?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn input(title: &str, body: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: body.into(),
            tags: tags.iter().map(|s| s.to_string()).collect(),
        }
    }

    #[test]
    fn crud_and_ids_not_reused() {
        let s = Store::open_in_memory().unwrap();
        let a = s.create(input("a", "", &["x"])).unwrap();
        let b = s.create(input("b", "", &[])).unwrap();
        assert_eq!((a.id, b.id), (1, 2));
        assert!(s.delete(2).unwrap());
        assert!(!s.delete(2).unwrap());
        assert_eq!(s.create(input("c", "", &[])).unwrap().id, 3);
        let u = s.update(1, input("A", "body", &["y", "z"])).unwrap().unwrap();
        assert_eq!(s.get(1).unwrap().unwrap(), u);
        assert!(s.update(2, input("x", "", &[])).unwrap().is_none());
        assert!(s.get(2).unwrap().is_none());
    }

    #[test]
    fn list_filters_and_counts() {
        let s = Store::open_in_memory().unwrap();
        s.create(input("Hello", "", &["g"])).unwrap();
        s.create(input("other", "say HELLO 100%", &["g", "m"])).unwrap();
        s.create(input("none", "", &[])).unwrap();
        let ids = |q: ListQuery| s.list(&q).unwrap().iter().map(|n| n.id).collect::<Vec<_>>();
        assert_eq!(ids(ListQuery::default()), [1, 2, 3]);
        assert_eq!(ids(ListQuery { q: Some("hello".into()), ..Default::default() }), [1, 2]);
        assert_eq!(ids(ListQuery { q: Some("0%".into()), ..Default::default() }), [2]);
        assert_eq!(ids(ListQuery { tag: Some("m".into()), ..Default::default() }), [2]);
        assert_eq!(ids(ListQuery { after: Some(1), limit: 1, ..Default::default() }), [2]);
        assert_eq!(s.list(&ListQuery::default()).unwrap()[1].tags, ["g", "m"]);
        assert_eq!(s.tag_counts().unwrap(), [("g".into(), 2), ("m".into(), 1)]);
        s.delete(2).unwrap();
        let (count, tags) = s.stats().unwrap();
        assert_eq!(count, 2);
        assert_eq!(tags, BTreeMap::from([("g".into(), 1)]));
    }
}
