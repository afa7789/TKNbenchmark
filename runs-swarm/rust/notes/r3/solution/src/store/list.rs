//! Listing notes with filters (`GET /notes`).

use rusqlite::{Row, named_params};

use super::{Result, Store};
use crate::model::Note;

/// The most notes one listing returns, and the default page size.
pub const MAX_LIMIT: u32 = 100;

/// Which notes [`Store::list_notes`] returns. All criteria combine with AND.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ListFilter {
    /// Only notes that have this tag.
    pub tag: Option<String>,
    /// Only notes whose title or body contains this text, ignoring ASCII case.
    pub text: Option<String>,
    /// Only notes with an id greater than this.
    pub after: Option<i64>,
    /// At most this many notes.
    pub limit: u32,
}

impl Default for ListFilter {
    fn default() -> Self {
        Self {
            tag: None,
            text: None,
            after: None,
            limit: MAX_LIMIT,
        }
    }
}

// Tags never contain a comma (see `model::is_valid_tag`), so a comma-joined list splits back losslessly.
// SQLite's `lower` folds ASCII letters only, which matches the "ignoring ASCII case" rule; the needle is
// lowered the same way in Rust.
const LIST_SQL: &str = "
    SELECT n.id, n.title, n.body,
           (SELECT group_concat(t.tag, ',' ORDER BY t.tag) FROM note_tags t WHERE t.note_id = n.id)
    FROM notes n
    WHERE n.id > :after
      AND (:tag IS NULL OR EXISTS (SELECT 1 FROM note_tags t WHERE t.note_id = n.id AND t.tag = :tag))
      AND (:text IS NULL OR instr(lower(n.title), :text) > 0 OR instr(lower(n.body), :text) > 0)
    ORDER BY n.id
    LIMIT :limit
";

impl Store {
    /// Returns the notes matching `filter`, ordered by id ascending.
    pub async fn list_notes(&self, filter: ListFilter) -> Result<Vec<Note>> {
        self.call(move |conn| {
            let text = filter.text.map(|text| text.to_ascii_lowercase());
            let mut stmt = conn.prepare_cached(LIST_SQL)?;
            let notes = stmt
                .query_map(
                    named_params! {
                        ":after": filter.after.unwrap_or(i64::MIN),
                        ":tag": filter.tag,
                        ":text": text,
                        ":limit": filter.limit,
                    },
                    note_with_tags_from_row,
                )?
                .collect::<rusqlite::Result<_>>()?;
            Ok(notes)
        })
        .await
    }
}

fn note_with_tags_from_row(row: &Row<'_>) -> rusqlite::Result<Note> {
    let tags: Option<String> = row.get(3)?;
    Ok(Note {
        id: row.get(0)?,
        title: row.get(1)?,
        body: row.get(2)?,
        tags: tags
            .map(|tags| tags.split(',').map(str::to_owned).collect())
            .unwrap_or_default(),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::NoteInput;
    use crate::store::test_support::TempStore;

    async fn seed(store: &Store, notes: &[(&str, &str, &[&str])]) {
        for (title, body, tags) in notes {
            store
                .create_note(NoteInput {
                    title: (*title).into(),
                    body: (*body).into(),
                    tags: tags.iter().map(|t| t.to_string()).collect(),
                })
                .await
                .unwrap();
        }
    }

    async fn ids(store: &Store, filter: ListFilter) -> Vec<i64> {
        store
            .list_notes(filter)
            .await
            .unwrap()
            .into_iter()
            .map(|note| note.id)
            .collect()
    }

    #[tokio::test]
    async fn lists_all_with_tags() {
        let db = TempStore::new();
        seed(&db.store, &[("a", "", &[]), ("b", "x", &["t", "u-2"])]).await;
        let notes = db.store.list_notes(ListFilter::default()).await.unwrap();
        assert_eq!(notes.len(), 2);
        assert_eq!(notes[0].tags, Vec::<String>::new());
        assert_eq!(notes[1].tags, ["t", "u-2"]);
        assert_eq!(notes[1].body, "x");
    }

    #[tokio::test]
    async fn filters_combine() {
        let db = TempStore::new();
        seed(
            &db.store,
            &[
                ("Hello world", "", &["greet"]),
                ("other", "say HELLO", &["greet", "misc"]),
                ("nothing", "", &[]),
                ("50% off", "under_score", &["misc"]),
            ],
        )
        .await;
        let filter = |tag: Option<&str>, text: Option<&str>| ListFilter {
            tag: tag.map(Into::into),
            text: text.map(Into::into),
            ..ListFilter::default()
        };
        assert_eq!(ids(&db.store, filter(Some("misc"), None)).await, [2, 4]);
        assert_eq!(
            ids(&db.store, filter(Some("mis"), None)).await,
            [] as [i64; 0]
        );
        assert_eq!(ids(&db.store, filter(None, Some("hElLo"))).await, [1, 2]);
        assert_eq!(
            ids(&db.store, filter(Some("misc"), Some("hello"))).await,
            [2]
        );
        assert_eq!(ids(&db.store, filter(None, Some(""))).await, [1, 2, 3, 4]);
        // No LIKE wildcards: `%` and `_` match themselves only.
        assert_eq!(ids(&db.store, filter(None, Some("%"))).await, [4]);
        assert_eq!(
            ids(&db.store, filter(None, Some("d_r"))).await,
            [] as [i64; 0]
        );
    }

    #[tokio::test]
    async fn pages_by_id() {
        let db = TempStore::new();
        seed(
            &db.store,
            &[("n1", "", &[]), ("n2", "", &[]), ("n3", "", &[])],
        )
        .await;
        let page = |after: Option<i64>, limit: u32| ListFilter {
            after,
            limit,
            ..ListFilter::default()
        };
        assert_eq!(ids(&db.store, page(None, 2)).await, [1, 2]);
        assert_eq!(ids(&db.store, page(Some(2), 2)).await, [3]);
        assert_eq!(ids(&db.store, page(Some(-5), 100)).await, [1, 2, 3]);
        assert_eq!(
            ids(&db.store, page(Some(i64::MAX), 100)).await,
            [] as [i64; 0]
        );
    }
}
