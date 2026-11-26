//! Data access for `GET /stats` and `GET /tags`.
//!
//! Tag counts come from the `note_tags` table, which only holds tags
//! of existing notes.

use std::collections::BTreeMap;

use rusqlite::Connection;
use serde::Serialize;

/// The number of notes and, for each tag in use, the number of notes that have it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Stats {
    pub notes: i64,
    pub tags: BTreeMap<String, i64>,
}

/// A tag and the number of notes that have it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TagCount {
    pub tag: String,
    pub count: i64,
}

/// The note count and per-tag counts, read from a single consistent snapshot.
pub fn stats(conn: &mut Connection) -> rusqlite::Result<Stats> {
    // A (deferred) read transaction, so that the note count and the tag counts agree even while
    // other connections write.
    let tx = conn.transaction()?;
    let notes = tx
        .prepare_cached("SELECT COUNT(*) FROM notes")?
        .query_row([], |row| row.get(0))?;
    let tags = tx
        .prepare_cached("SELECT tag, COUNT(*) FROM note_tags GROUP BY tag")?
        .query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?
        .collect::<rusqlite::Result<_>>()?;
    tx.commit()?;
    Ok(Stats { notes, tags })
}

/// Every tag in use with its note count, ordered by count descending, then tag ascending.
pub fn tag_counts(conn: &Connection) -> rusqlite::Result<Vec<TagCount>> {
    conn.prepare_cached(
        "SELECT tag, COUNT(*) AS count FROM note_tags GROUP BY tag ORDER BY count DESC, tag ASC",
    )?
    .query_map([], |row| {
        Ok(TagCount {
            tag: row.get(0)?,
            count: row.get(1)?,
        })
    })?
    .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::notes::insert;
    use crate::db::test_util::{conn, temp_db};
    use crate::model::NoteInput;

    fn input(title: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: String::new(),
            tags: tags.iter().map(|&t| t.to_owned()).collect(),
        }
    }

    fn tag_count(tag: &str, count: i64) -> TagCount {
        TagCount {
            tag: tag.into(),
            count,
        }
    }

    #[test]
    fn empty_database() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        assert_eq!(
            stats(&mut conn).unwrap(),
            Stats {
                notes: 0,
                tags: BTreeMap::new()
            }
        );
        assert_eq!(tag_counts(&conn).unwrap(), []);
    }

    #[test]
    fn counts_notes_per_tag() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        insert(&mut conn, input("a", &["b", "x"])).unwrap();
        insert(&mut conn, input("b", &["a", "x"])).unwrap();
        insert(&mut conn, input("c", &["c", "x"])).unwrap();
        insert(&mut conn, input("d", &["c"])).unwrap();
        insert(&mut conn, input("e", &[])).unwrap();

        let expected = BTreeMap::from([
            ("a".to_owned(), 1),
            ("b".to_owned(), 1),
            ("c".to_owned(), 2),
            ("x".to_owned(), 3),
        ]);
        assert_eq!(
            stats(&mut conn).unwrap(),
            Stats {
                notes: 5,
                tags: expected
            }
        );
        assert_eq!(
            tag_counts(&conn).unwrap(),
            [
                tag_count("x", 3),
                tag_count("c", 2),
                tag_count("a", 1),
                tag_count("b", 1)
            ]
        );
    }

    #[test]
    fn deleted_notes_no_longer_count() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        let first = insert(&mut conn, input("a", &["x", "y"])).unwrap();
        insert(&mut conn, input("b", &["x"])).unwrap();
        conn.execute("DELETE FROM notes WHERE id = ?1", [first.id])
            .unwrap();

        assert_eq!(
            stats(&mut conn).unwrap(),
            Stats {
                notes: 1,
                tags: BTreeMap::from([("x".to_owned(), 1)])
            }
        );
        assert_eq!(tag_counts(&conn).unwrap(), [tag_count("x", 1)]);
    }
}
