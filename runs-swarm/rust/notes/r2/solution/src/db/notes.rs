//! Core data access: creating and reading notes, and the tag helpers shared by other features.

use rusqlite::{Connection, OptionalExtension, TransactionBehavior, params};

use crate::model::{Note, NoteInput};

/// Inserts a note and returns it with its new id.
pub fn insert(conn: &mut Connection, input: NoteInput) -> rusqlite::Result<Note> {
    let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
    tx.execute(
        "INSERT INTO notes (title, body) VALUES (?1, ?2)",
        params![input.title, input.body],
    )?;
    let id = tx.last_insert_rowid();
    replace_tags(&tx, id, &input.tags)?;
    tx.commit()?;
    let NoteInput { title, body, tags } = input;
    Ok(Note {
        id,
        title,
        body,
        tags,
    })
}

/// The note with this id, if it exists.
pub fn get(conn: &Connection, id: i64) -> rusqlite::Result<Option<Note>> {
    let Some((title, body)) = conn
        .prepare_cached("SELECT title, body FROM notes WHERE id = ?1")?
        .query_row([id], |row| Ok((row.get(0)?, row.get(1)?)))
        .optional()?
    else {
        return Ok(None);
    };
    let tags = tags_of(conn, id)?;
    Ok(Some(Note {
        id,
        title,
        body,
        tags,
    }))
}

/// The tags of a note, sorted ascending.
pub fn tags_of(conn: &Connection, note_id: i64) -> rusqlite::Result<Vec<String>> {
    conn.prepare_cached("SELECT tag FROM note_tags WHERE note_id = ?1 ORDER BY tag")?
        .query_map([note_id], |row| row.get(0))?
        .collect()
}

/// Sets the tags of a note to exactly `tags`. Call inside a transaction.
pub fn replace_tags(conn: &Connection, note_id: i64, tags: &[String]) -> rusqlite::Result<()> {
    conn.prepare_cached("DELETE FROM note_tags WHERE note_id = ?1")?
        .execute([note_id])?;
    let mut insert = conn.prepare_cached("INSERT INTO note_tags (note_id, tag) VALUES (?1, ?2)")?;
    for tag in tags {
        insert.execute(params![note_id, tag])?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::test_util::{conn, temp_db};

    fn input(title: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: format!("{title} body"),
            tags: tags.iter().map(|&t| t.to_owned()).collect(),
        }
    }

    #[test]
    fn insert_then_get() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        let first = insert(&mut conn, input("a", &["x", "y"])).unwrap();
        let second = insert(&mut conn, input("b", &[])).unwrap();
        assert_eq!((first.id, second.id), (1, 2));
        assert_eq!(get(&conn, 1).unwrap(), Some(first));
        assert_eq!(get(&conn, 2).unwrap(), Some(second));
        assert_eq!(get(&conn, 3).unwrap(), None);
    }

    #[test]
    fn replace_tags_overwrites() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        let note = insert(&mut conn, input("a", &["x", "y"])).unwrap();
        replace_tags(&conn, note.id, &["z".to_owned()]).unwrap();
        assert_eq!(tags_of(&conn, note.id).unwrap(), ["z"]);
    }

    #[test]
    fn ids_are_not_reused() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        let note = insert(&mut conn, input("a", &["x"])).unwrap();
        conn.execute("DELETE FROM notes WHERE id = ?1", [note.id])
            .unwrap();
        assert_eq!(
            tags_of(&conn, note.id).unwrap(),
            Vec::<String>::new(),
            "tags cascade"
        );
        assert_eq!(insert(&mut conn, input("b", &[])).unwrap().id, 2);
    }
}
