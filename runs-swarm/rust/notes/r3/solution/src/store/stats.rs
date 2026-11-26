//! Aggregates over tags (`GET /stats` and `GET /tags`).

use rusqlite::{Connection, TransactionBehavior};
use serde::Serialize;

use super::{Result, Store};

/// How many notes have a tag.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TagCount {
    pub tag: String,
    pub count: i64,
}

/// The number of notes and the per-tag counts, read from one snapshot of the database.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Stats {
    pub notes: i64,
    /// Ordered by count descending, then tag ascending.
    pub tags: Vec<TagCount>,
}

impl Store {
    /// The number of notes and how many notes have each tag.
    pub async fn stats(&self) -> Result<Stats> {
        self.call(|conn| {
            // A read transaction, so the note count and the tag counts agree with each other.
            let tx = conn.transaction_with_behavior(TransactionBehavior::Deferred)?;
            let notes = tx.query_row("SELECT COUNT(*) FROM notes", [], |row| row.get(0))?;
            let tags = read_tag_counts(&tx)?;
            tx.finish()?;
            Ok(Stats { notes, tags })
        })
        .await
    }

    /// How many notes have each tag, ordered by count descending, then tag ascending.
    pub async fn tag_counts(&self) -> Result<Vec<TagCount>> {
        self.call(|conn| read_tag_counts(conn)).await
    }
}

/// Tags of deleted notes are gone with them (`ON DELETE CASCADE`), so `note_tags` alone is enough.
fn read_tag_counts(conn: &Connection) -> Result<Vec<TagCount>> {
    let mut stmt = conn.prepare_cached(
        "SELECT tag, COUNT(*) AS n FROM note_tags GROUP BY tag ORDER BY n DESC, tag ASC",
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

#[cfg(test)]
mod tests {
    use super::{Stats, TagCount};
    use crate::model::NoteInput;
    use crate::store::test_support::TempStore;

    fn input(tags: &[&str]) -> NoteInput {
        NoteInput {
            title: "t".into(),
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
    async fn empty() {
        let db = TempStore::new();
        assert_eq!(
            db.store.stats().await.unwrap(),
            Stats {
                notes: 0,
                tags: vec![]
            }
        );
        assert_eq!(db.store.tag_counts().await.unwrap(), vec![]);
    }

    #[tokio::test]
    async fn ordered_by_count_then_tag() {
        let db = TempStore::new();
        for tags in [&["b", "c"][..], &["a", "c"], &["b", "z"], &[], &["c"]] {
            db.store.create_note(input(tags)).await.unwrap();
        }
        let expected = vec![count("c", 3), count("b", 2), count("a", 1), count("z", 1)];
        assert_eq!(db.store.tag_counts().await.unwrap(), expected);
        assert_eq!(
            db.store.stats().await.unwrap(),
            Stats {
                notes: 5,
                tags: expected
            }
        );
    }

    #[tokio::test]
    async fn deleted_notes_no_longer_count() {
        let db = TempStore::new();
        let a = db.store.create_note(input(&["x", "y"])).await.unwrap();
        db.store.create_note(input(&["x"])).await.unwrap();
        db.store
            .call(move |conn| {
                conn.execute("DELETE FROM notes WHERE id = ?1", [a.id])?;
                Ok(())
            })
            .await
            .unwrap();
        assert_eq!(
            db.store.stats().await.unwrap(),
            Stats {
                notes: 1,
                tags: vec![count("x", 1)]
            }
        );
    }
}
