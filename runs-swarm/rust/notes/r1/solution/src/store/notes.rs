//! Creating and reading single notes, plus the tag helpers shared by other features.

use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};

use super::Result;
use crate::note::{Note, NoteId, NoteInput};

/// Inserts a new note with its tags and returns it with its assigned id.
pub fn insert(conn: &mut Connection, input: &NoteInput) -> Result<Note> {
    let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
    tx.prepare_cached("INSERT INTO notes (title, body) VALUES (?1, ?2)")?
        .execute(params![input.title, input.body])?;
    let id = tx.last_insert_rowid();
    insert_tags(&tx, id, &input.tags)?;
    tx.commit()?;

    Ok(Note {
        id,
        title: input.title.clone(),
        body: input.body.clone(),
        tags: input.tags.clone(),
    })
}

/// Returns the note with this id, if it exists.
pub fn get(conn: &Connection, id: NoteId) -> Result<Option<Note>> {
    let found = conn
        .prepare_cached("SELECT title, body FROM notes WHERE id = ?1")?
        .query_row([id.get()], |row| Ok((row.get(0)?, row.get(1)?)))
        .optional()?;
    let Some((title, body)) = found else {
        return Ok(None);
    };
    Ok(Some(Note {
        id: id.get(),
        title,
        body,
        tags: tags_of(conn, id.get())?,
    }))
}

/// The tags of a note, sorted ascending.
pub fn tags_of(conn: &Connection, note_id: i64) -> Result<Vec<String>> {
    let mut stmt =
        conn.prepare_cached("SELECT tag FROM note_tags WHERE note_id = ?1 ORDER BY tag")?;
    let tags = stmt
        .query_map([note_id], |row| row.get(0))?
        .collect::<rusqlite::Result<_>>()?;
    Ok(tags)
}

/// Adds `tags` (already validated and deduplicated) to a note. Call within the caller's
/// transaction.
pub fn insert_tags(conn: &Connection, note_id: i64, tags: &[String]) -> Result<()> {
    let mut stmt = conn.prepare_cached("INSERT INTO note_tags (note_id, tag) VALUES (?1, ?2)")?;
    for tag in tags {
        stmt.execute(params![note_id, tag])?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::Db;

    fn input(title: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: format!("body of {title}"),
            tags: tags.iter().map(|t| t.to_string()).collect(),
        }
    }

    #[tokio::test]
    async fn insert_then_get_round_trips() {
        let dir = tempfile::tempdir().unwrap();
        let db = Db::open(dir.path().join("notes.db")).unwrap();

        let created = db
            .call(|conn| insert(conn, &input("a", &["x", "y"])))
            .await
            .unwrap();
        assert_eq!(created.id, 1);

        let id = NoteId::new(created.id).unwrap();
        let fetched = db.call(move |conn| get(conn, id)).await.unwrap();
        assert_eq!(fetched.as_ref(), Some(&created));

        let missing = db
            .call(|conn| get(conn, NoteId::new(99).unwrap()))
            .await
            .unwrap();
        assert_eq!(missing, None);
    }

    #[tokio::test]
    async fn ids_survive_reopen() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("notes.db");
        {
            let db = Db::open(&path).unwrap();
            db.call(|conn| insert(conn, &input("a", &[])))
                .await
                .unwrap();
        }
        let db = Db::open(&path).unwrap();
        let second = db
            .call(|conn| insert(conn, &input("b", &[])))
            .await
            .unwrap();
        assert_eq!(second.id, 2);
    }
}
