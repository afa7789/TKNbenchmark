//! Data access for `PUT /notes/{id}` and `DELETE /notes/{id}`.
//!
//! Updates reuse [`super::notes::replace_tags`]; deleting a note removes its tags through
//! `ON DELETE CASCADE`.

use rusqlite::{Connection, TransactionBehavior, params};

use super::notes::replace_tags;
use crate::model::{Note, NoteInput};

/// Replaces the content of the note with this id. Returns `None` if it does not exist.
pub fn update(conn: &mut Connection, id: i64, input: NoteInput) -> rusqlite::Result<Option<Note>> {
    let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let changed = tx
        .prepare_cached("UPDATE notes SET title = ?1, body = ?2 WHERE id = ?3")?
        .execute(params![input.title, input.body, id])?;
    if changed == 0 {
        return Ok(None);
    }
    replace_tags(&tx, id, &input.tags)?;
    tx.commit()?;
    let NoteInput { title, body, tags } = input;
    Ok(Some(Note {
        id,
        title,
        body,
        tags,
    }))
}

/// Deletes the note with this id and its tags. Returns whether it existed.
pub fn delete(conn: &Connection, id: i64) -> rusqlite::Result<bool> {
    let deleted = conn
        .prepare_cached("DELETE FROM notes WHERE id = ?1")?
        .execute([id])?;
    Ok(deleted > 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::notes::{get, insert, tags_of};
    use crate::db::test_util::{conn, temp_db};

    fn input(title: &str, body: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: body.into(),
            tags: tags.iter().map(|&t| t.to_owned()).collect(),
        }
    }

    #[test]
    fn update_replaces_content_and_tags() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        let note = insert(&mut conn, input("old", "text", &["x", "y"])).unwrap();
        let updated = update(&mut conn, note.id, input("new", "", &["a", "y"]))
            .unwrap()
            .expect("note exists");
        assert_eq!(
            updated,
            Note {
                id: note.id,
                title: "new".into(),
                body: String::new(),
                tags: vec!["a".into(), "y".into()],
            }
        );
        assert_eq!(get(&conn, note.id).unwrap(), Some(updated));
    }

    #[test]
    fn update_missing_note() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        assert_eq!(update(&mut conn, 1, input("t", "", &["a"])).unwrap(), None);
        assert_eq!(
            tags_of(&conn, 1).unwrap(),
            Vec::<String>::new(),
            "no orphan tags"
        );
    }

    #[test]
    fn delete_removes_note_and_tags() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        let note = insert(&mut conn, input("a", "", &["x"])).unwrap();
        assert!(delete(&conn, note.id).unwrap());
        assert_eq!(get(&conn, note.id).unwrap(), None);
        assert_eq!(tags_of(&conn, note.id).unwrap(), Vec::<String>::new());
        assert!(!delete(&conn, note.id).unwrap());
    }
}
