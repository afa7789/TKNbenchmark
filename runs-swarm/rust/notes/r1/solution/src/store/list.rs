//! Listing and filtering notes (`list` branch).

use rusqlite::{Connection, params};

use super::Result;
use crate::note::Note;

/// Which notes to list. Every filter is optional; they combine with AND.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ListFilter {
    /// Only notes that have this tag.
    pub tag: Option<String>,
    /// Only notes whose title or body contains this text, ignoring ASCII case.
    pub q: Option<String>,
    /// Only notes with an id greater than this.
    pub after: Option<i64>,
    /// At most this many notes.
    pub limit: u32,
}

/// Returns the notes matching `filter`, ordered by id ascending, each with its sorted tags.
///
/// The page of notes is selected first, then joined with its tags in the same statement, so the
/// result is a consistent snapshot without one query per note. Without ICU (the bundled SQLite
/// has none), `lower()` folds ASCII letters only, which is exactly the case-insensitivity the
/// spec asks for; `instr` avoids having to escape `LIKE` wildcards in `q`.
pub fn list(conn: &Connection, filter: &ListFilter) -> Result<Vec<Note>> {
    let mut stmt = conn.prepare_cached(
        "SELECT n.id, n.title, n.body, t.tag
         FROM (
             SELECT id, title, body FROM notes
             WHERE (?1 IS NULL OR id > ?1)
               AND (?2 IS NULL OR EXISTS (
                       SELECT 1 FROM note_tags WHERE note_id = notes.id AND tag = ?2))
               AND (?3 IS NULL
                    OR instr(lower(title), lower(?3)) > 0
                    OR instr(lower(body), lower(?3)) > 0)
             ORDER BY id
             LIMIT ?4
         ) AS n
         LEFT JOIN note_tags AS t ON t.note_id = n.id
         ORDER BY n.id, t.tag",
    )?;
    let mut rows = stmt.query(params![filter.after, filter.tag, filter.q, filter.limit])?;

    let mut notes: Vec<Note> = Vec::new();
    while let Some(row) = rows.next()? {
        let id: i64 = row.get(0)?;
        let tag: Option<String> = row.get(3)?;
        let note = match notes.last_mut() {
            Some(note) if note.id == id => note,
            _ => {
                notes.push(Note {
                    id,
                    title: row.get(1)?,
                    body: row.get(2)?,
                    tags: Vec::new(),
                });
                notes.last_mut().expect("just pushed")
            }
        };
        note.tags.extend(tag);
    }
    Ok(notes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::note::NoteInput;
    use crate::store::{Db, notes};

    fn all() -> ListFilter {
        ListFilter {
            tag: None,
            q: None,
            after: None,
            limit: 100,
        }
    }

    async fn seeded() -> (tempfile::TempDir, Db) {
        let dir = tempfile::tempdir().unwrap();
        let db = Db::open(dir.path().join("notes.db")).unwrap();
        db.call(|conn| {
            for (title, body, tags) in [
                ("Hello world", "", &["greet"][..]),
                ("other", "say HELLO", &["greet", "misc"][..]),
                ("nothing", "100%_done", &[][..]),
            ] {
                let input = NoteInput {
                    title: title.into(),
                    body: body.into(),
                    tags: tags.iter().map(|t| t.to_string()).collect(),
                };
                notes::insert(conn, &input)?;
            }
            Ok(())
        })
        .await
        .unwrap();
        (dir, db)
    }

    async fn ids(db: &Db, filter: ListFilter) -> Vec<i64> {
        db.call(move |conn| list(conn, &filter))
            .await
            .unwrap()
            .into_iter()
            .map(|n| n.id)
            .collect()
    }

    #[tokio::test]
    async fn lists_everything_with_tags() {
        let (_dir, db) = seeded().await;
        let notes = db.call(|conn| list(conn, &all())).await.unwrap();
        assert_eq!(notes.iter().map(|n| n.id).collect::<Vec<_>>(), [1, 2, 3]);
        assert_eq!(notes[1].tags, ["greet", "misc"]);
        assert_eq!(notes[1].body, "say HELLO");
        assert!(notes[2].tags.is_empty());
    }

    #[tokio::test]
    async fn filters_combine() {
        let (_dir, db) = seeded().await;
        let tag = |t: &str| ListFilter {
            tag: Some(t.into()),
            ..all()
        };
        let q = |q: &str| ListFilter {
            q: Some(q.into()),
            ..all()
        };
        assert_eq!(ids(&db, tag("greet")).await, [1, 2]);
        assert_eq!(ids(&db, tag("nope")).await, Vec::<i64>::new());
        assert_eq!(ids(&db, q("hElLo")).await, [1, 2]);
        assert_eq!(ids(&db, q("%")).await, [3]);
        assert_eq!(ids(&db, q("_")).await, [3]);
        assert_eq!(ids(&db, q("")).await, [1, 2, 3]);
        assert_eq!(
            ids(
                &db,
                ListFilter {
                    q: Some("hello".into()),
                    tag: Some("misc".into()),
                    ..all()
                }
            )
            .await,
            [2]
        );
    }

    #[tokio::test]
    async fn pages_with_after_and_limit() {
        let (_dir, db) = seeded().await;
        let page = |after, limit| ListFilter {
            after,
            limit,
            ..all()
        };
        assert_eq!(ids(&db, page(None, 2)).await, [1, 2]);
        assert_eq!(ids(&db, page(Some(1), 1)).await, [2]);
        assert_eq!(ids(&db, page(Some(2), 100)).await, [3]);
        assert_eq!(ids(&db, page(Some(3), 100)).await, Vec::<i64>::new());
        assert_eq!(ids(&db, page(Some(-5), 100)).await, [1, 2, 3]);
    }

    #[tokio::test]
    async fn case_folding_is_ascii_only() {
        let dir = tempfile::tempdir().unwrap();
        let db = Db::open(dir.path().join("notes.db")).unwrap();
        db.call(|conn| {
            let input = NoteInput {
                title: "Ébène".into(),
                body: String::new(),
                tags: vec![],
            };
            notes::insert(conn, &input).map(drop)
        })
        .await
        .unwrap();
        let q = |q: &str| ListFilter {
            q: Some(q.into()),
            ..all()
        };
        assert_eq!(ids(&db, q("ÉBÈNE")).await, Vec::<i64>::new());
        assert_eq!(ids(&db, q("éb")).await, Vec::<i64>::new());
        assert_eq!(ids(&db, q("ÉBène")).await, [1]);
    }
}
