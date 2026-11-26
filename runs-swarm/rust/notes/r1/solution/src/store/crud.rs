//! Updating and deleting notes (`crud` branch).

use rusqlite::{Connection, TransactionBehavior, params};

use super::Result;
use super::notes::insert_tags;
use crate::note::{Note, NoteId, NoteInput};

/// Replaces the title, body and tags of a note. Returns the updated note, or `None` if no note
/// has this id.
pub fn update(conn: &mut Connection, id: NoteId, input: &NoteInput) -> Result<Option<Note>> {
    let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let updated = tx
        .prepare_cached("UPDATE notes SET title = ?2, body = ?3 WHERE id = ?1")?
        .execute(params![id.get(), input.title, input.body])?;
    if updated == 0 {
        // Nothing changed; dropping `tx` rolls back.
        return Ok(None);
    }
    tx.prepare_cached("DELETE FROM note_tags WHERE note_id = ?1")?
        .execute([id.get()])?;
    insert_tags(&tx, id.get(), &input.tags)?;
    tx.commit()?;

    Ok(Some(Note {
        id: id.get(),
        title: input.title.clone(),
        body: input.body.clone(),
        tags: input.tags.clone(),
    }))
}

/// Deletes a note and its tags. Returns whether a note with this id existed.
pub fn delete(conn: &Connection, id: NoteId) -> Result<bool> {
    // A single statement is atomic; `ON DELETE CASCADE` removes the note's tags with it.
    let deleted = conn
        .prepare_cached("DELETE FROM notes WHERE id = ?1")?
        .execute([id.get()])?;
    Ok(deleted > 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::store::Db;
    use crate::store::notes::{get, insert};

    fn input(title: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: format!("body of {title}"),
            tags: tags.iter().map(|t| t.to_string()).collect(),
        }
    }

    fn open() -> (tempfile::TempDir, Db) {
        let dir = tempfile::tempdir().unwrap();
        let db = Db::open(dir.path().join("notes.db")).unwrap();
        (dir, db)
    }

    #[tokio::test]
    async fn update_replaces_fields_and_tags() {
        let (_dir, db) = open();
        let created = db
            .call(|conn| insert(conn, &input("a", &["x", "y"])))
            .await
            .unwrap();
        let id = NoteId::new(created.id).unwrap();

        let updated = db
            .call(move |conn| update(conn, id, &input("b", &["y", "z"])))
            .await
            .unwrap()
            .expect("note exists");
        assert_eq!(
            updated,
            Note {
                id: created.id,
                title: "b".into(),
                body: "body of b".into(),
                tags: vec!["y".into(), "z".into()],
            }
        );
        let fetched = db.call(move |conn| get(conn, id)).await.unwrap();
        assert_eq!(fetched, Some(updated));
    }

    #[tokio::test]
    async fn update_of_missing_note_is_none() {
        let (_dir, db) = open();
        let id = NoteId::new(1).unwrap();
        let result = db
            .call(move |conn| update(conn, id, &input("a", &["x"])))
            .await
            .unwrap();
        assert_eq!(result, None);
        // No orphan tags were written.
        let tags: i64 = db
            .call(|conn| Ok(conn.query_row("SELECT COUNT(*) FROM note_tags", [], |r| r.get(0))?))
            .await
            .unwrap();
        assert_eq!(tags, 0);
    }

    #[tokio::test]
    async fn delete_removes_note_and_tags() {
        let (_dir, db) = open();
        let created = db
            .call(|conn| insert(conn, &input("a", &["x"])))
            .await
            .unwrap();
        let id = NoteId::new(created.id).unwrap();

        assert!(db.call(move |conn| delete(conn, id)).await.unwrap());
        assert!(!db.call(move |conn| delete(conn, id)).await.unwrap());
        assert_eq!(db.call(move |conn| get(conn, id)).await.unwrap(), None);
        let tags: i64 = db
            .call(|conn| Ok(conn.query_row("SELECT COUNT(*) FROM note_tags", [], |r| r.get(0))?))
            .await
            .unwrap();
        assert_eq!(tags, 0);
    }
}
