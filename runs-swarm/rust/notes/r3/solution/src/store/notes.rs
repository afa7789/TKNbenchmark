//! Creating and reading single notes, plus row and tag helpers shared by the other store modules.

use rusqlite::{Connection, OptionalExtension, Row, TransactionBehavior, params};

use super::{Result, Store};
use crate::model::{Note, NoteInput};

impl Store {
    /// Inserts a note and returns it with its assigned id.
    pub async fn create_note(&self, input: NoteInput) -> Result<Note> {
        self.call(move |conn| {
            let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
            tx.execute(
                "INSERT INTO notes (title, body) VALUES (?1, ?2)",
                params![input.title, input.body],
            )?;
            let id = tx.last_insert_rowid();
            insert_tags(&tx, id, &input.tags)?;
            tx.commit()?;
            Ok(Note {
                id,
                title: input.title,
                body: input.body,
                tags: input.tags,
            })
        })
        .await
    }

    /// Returns the note with `id`, or `None` if it does not exist.
    pub async fn get_note(&self, id: i64) -> Result<Option<Note>> {
        self.call(move |conn| read_note(conn, id)).await
    }
}

/// Reads one note with its tags.
pub(super) fn read_note(conn: &Connection, id: i64) -> Result<Option<Note>> {
    let note = conn
        .query_row(
            "SELECT id, title, body FROM notes WHERE id = ?1",
            [id],
            note_from_row,
        )
        .optional()?;
    match note {
        Some(mut note) => {
            note.tags = read_tags(conn, id)?;
            Ok(Some(note))
        }
        None => Ok(None),
    }
}

/// Maps a row of `SELECT id, title, body` to a note with no tags; fill them with [`read_tags`].
pub(super) fn note_from_row(row: &Row<'_>) -> rusqlite::Result<Note> {
    Ok(Note {
        id: row.get(0)?,
        title: row.get(1)?,
        body: row.get(2)?,
        tags: Vec::new(),
    })
}

/// The tags of a note, sorted ascending.
pub(super) fn read_tags(conn: &Connection, note_id: i64) -> Result<Vec<String>> {
    let mut stmt =
        conn.prepare_cached("SELECT tag FROM note_tags WHERE note_id = ?1 ORDER BY tag")?;
    let tags = stmt
        .query_map([note_id], |row| row.get(0))?
        .collect::<rusqlite::Result<_>>()?;
    Ok(tags)
}

/// Adds `tags` to a note. The caller removes previous tags first when replacing them.
pub(super) fn insert_tags(conn: &Connection, note_id: i64, tags: &[String]) -> Result<()> {
    let mut stmt =
        conn.prepare_cached("INSERT OR IGNORE INTO note_tags (note_id, tag) VALUES (?1, ?2)")?;
    for tag in tags {
        stmt.execute(params![note_id, tag])?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use crate::model::NoteInput;
    use crate::store::Store;
    use crate::store::test_support::TempStore;

    fn input(title: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: format!("body of {title}"),
            tags: tags.iter().map(|t| t.to_string()).collect(),
        }
    }

    #[tokio::test]
    async fn create_then_get() {
        let db = TempStore::new();
        let a = db.store.create_note(input("a", &[])).await.unwrap();
        let b = db.store.create_note(input("b", &["x", "y"])).await.unwrap();
        assert_eq!((a.id, b.id), (1, 2));
        assert_eq!(db.store.get_note(2).await.unwrap(), Some(b));
        assert_eq!(db.store.get_note(1).await.unwrap(), Some(a));
        assert_eq!(db.store.get_note(3).await.unwrap(), None);
    }

    #[tokio::test]
    async fn data_survives_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("notes.db");
        let created = Store::open(&path)
            .unwrap()
            .create_note(input("a", &["t"]))
            .await
            .unwrap();
        let reopened = Store::open(&path).unwrap();
        assert_eq!(reopened.get_note(created.id).await.unwrap(), Some(created));
        assert_eq!(reopened.create_note(input("b", &[])).await.unwrap().id, 2);
    }
}
