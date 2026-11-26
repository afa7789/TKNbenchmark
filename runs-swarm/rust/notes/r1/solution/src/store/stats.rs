//! Tag and note counts (`stats` branch).
//!
//! Tags of deleted notes need no special handling: their `note_tags` rows go with the note
//! (`ON DELETE CASCADE`), so counting `note_tags` counts live notes only.

use rusqlite::Connection;
use serde::Serialize;

use super::Result;

/// How many notes have a tag.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TagCount {
    pub tag: String,
    pub count: i64,
}

/// The number of notes, and the per-tag counts from [`tag_counts`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Stats {
    pub notes: i64,
    pub tags: Vec<TagCount>,
}

/// Every tag in use with the number of notes that have it, ordered by count descending, then tag
/// ascending.
pub fn tag_counts(conn: &Connection) -> Result<Vec<TagCount>> {
    let mut stmt = conn.prepare_cached(
        "SELECT tag, COUNT(*) AS count FROM note_tags GROUP BY tag ORDER BY count DESC, tag ASC",
    )?;
    let counts = stmt
        .query_map([], |row| {
            Ok(TagCount {
                tag: row.get(0)?,
                count: row.get(1)?,
            })
        })?
        .collect::<rusqlite::Result<_>>()?;
    Ok(counts)
}

/// The note count and tag counts, read from a single snapshot so they agree with each other.
pub fn stats(conn: &mut Connection) -> Result<Stats> {
    let tx = conn.transaction()?;
    let notes = tx
        .prepare_cached("SELECT COUNT(*) FROM notes")?
        .query_row([], |row| row.get(0))?;
    let tags = tag_counts(&tx)?;
    tx.finish()?;
    Ok(Stats { notes, tags })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::note::NoteInput;
    use crate::store::{Db, notes};

    fn input(title: &str, tags: &[&str]) -> NoteInput {
        NoteInput {
            title: title.into(),
            body: String::new(),
            tags: tags.iter().map(|t| t.to_string()).collect(),
        }
    }

    fn count(tag: &str, count: i64) -> TagCount {
        TagCount {
            tag: tag.into(),
            count,
        }
    }

    #[tokio::test]
    async fn empty_database() {
        let dir = tempfile::tempdir().unwrap();
        let db = Db::open(dir.path().join("notes.db")).unwrap();
        let stats = db.call(stats).await.unwrap();
        assert_eq!(
            stats,
            Stats {
                notes: 0,
                tags: vec![]
            }
        );
    }

    #[tokio::test]
    async fn counts_are_ordered_and_skip_deleted_notes() {
        let dir = tempfile::tempdir().unwrap();
        let db = Db::open(dir.path().join("notes.db")).unwrap();
        let stats = db
            .call(|conn| {
                notes::insert(conn, &input("a", &["b", "c"]))?;
                notes::insert(conn, &input("b", &["a", "c"]))?;
                notes::insert(conn, &input("c", &["c", "z"]))?;
                let gone = notes::insert(conn, &input("d", &["a", "z", "gone"]))?;
                notes::insert(conn, &input("e", &[]))?;
                conn.execute("DELETE FROM notes WHERE id = ?1", [gone.id])?;
                stats(conn)
            })
            .await
            .unwrap();
        assert_eq!(stats.notes, 4);
        assert_eq!(
            stats.tags,
            vec![count("c", 3), count("a", 1), count("b", 1), count("z", 1)]
        );
    }
}
