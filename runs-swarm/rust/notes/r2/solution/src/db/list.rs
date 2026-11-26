//! Data access for `GET /notes` and its filters.
//!
//! Tags live in the `note_tags` table (indexed by tag); see [`super::notes::tags_of`].

use rusqlite::{Connection, params};

use crate::model::Note;

/// Which notes `GET /notes` returns. Every filter is optional; they combine with AND.
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
            limit: 100,
        }
    }
}

/// The notes matching `filter`, ordered by id ascending.
///
/// A single statement reads notes and their tags, so the result is a consistent snapshot even
/// while other requests write.
pub fn list(conn: &Connection, filter: &ListFilter) -> rusqlite::Result<Vec<Note>> {
    // SQLite's `lower()` folds ASCII letters only (no ICU in the bundled build), which is exactly
    // the case-insensitivity the API promises. `instr` avoids LIKE's `%` and `_` wildcards.
    let mut statement = conn.prepare_cached(
        "SELECT n.id, n.title, n.body, t.tag
         FROM (
             SELECT id, title, body FROM notes
             WHERE (?1 IS NULL OR id > ?1)
               AND (?2 IS NULL OR id IN (SELECT note_id FROM note_tags WHERE tag = ?2))
               AND (?3 IS NULL OR instr(lower(title), ?3) > 0 OR instr(lower(body), ?3) > 0)
             ORDER BY id
             LIMIT ?4
         ) AS n
         LEFT JOIN note_tags AS t ON t.note_id = n.id
         ORDER BY n.id, t.tag",
    )?;
    let needle = filter.text.as_deref().map(str::to_ascii_lowercase);
    let mut rows = statement.query(params![filter.after, filter.tag, needle, filter.limit])?;

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
    use crate::db::notes::insert;
    use crate::db::test_util::{conn, temp_db};
    use crate::model::NoteInput;

    fn add(conn: &mut Connection, title: &str, body: &str, tags: &[&str]) -> Note {
        let input = NoteInput {
            title: title.into(),
            body: body.into(),
            tags: tags.iter().map(|&t| t.to_owned()).collect(),
        };
        insert(conn, input).unwrap()
    }

    fn ids(notes: &[Note]) -> Vec<i64> {
        notes.iter().map(|n| n.id).collect()
    }

    #[test]
    fn lists_all_with_tags_in_id_order() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        let a = add(&mut conn, "a", "", &["x", "y"]);
        let b = add(&mut conn, "b", "x", &[]);
        let c = add(&mut conn, "c", "", &["z"]);
        assert_eq!(list(&conn, &ListFilter::default()).unwrap(), [a, b, c]);
    }

    #[test]
    fn filters_combine() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        add(&mut conn, "Hello world", "", &["greet"]);
        add(&mut conn, "other", "say HELLO", &["greet", "misc"]);
        add(&mut conn, "nothing", "", &[]);
        add(&mut conn, "héllo", "100%_done", &["misc"]);

        let run = |filter: ListFilter| ids(&list(&conn, &filter).unwrap());
        let text = |t: &str| Some(t.to_owned());

        assert_eq!(
            run(ListFilter {
                tag: text("misc"),
                ..Default::default()
            }),
            [2, 4]
        );
        assert_eq!(
            run(ListFilter {
                tag: text("nope"),
                ..Default::default()
            }),
            [0; 0]
        );
        assert_eq!(
            run(ListFilter {
                text: text("hElLo"),
                ..Default::default()
            }),
            [1, 2]
        );
        assert_eq!(
            run(ListFilter {
                text: text("HÉLLO"),
                ..Default::default()
            }),
            [0; 0]
        );
        assert_eq!(
            run(ListFilter {
                text: text("%_"),
                ..Default::default()
            }),
            [4]
        );
        assert_eq!(
            run(ListFilter {
                text: text("_"),
                ..Default::default()
            }),
            [4]
        );
        assert_eq!(
            run(ListFilter {
                text: text(""),
                ..Default::default()
            }),
            [1, 2, 3, 4]
        );
        assert_eq!(
            run(ListFilter {
                tag: text("misc"),
                text: text("hello"),
                ..Default::default()
            }),
            [2]
        );
        assert_eq!(
            run(ListFilter {
                after: Some(2),
                ..Default::default()
            }),
            [3, 4]
        );
        assert_eq!(
            run(ListFilter {
                after: Some(-5),
                ..Default::default()
            }),
            [1, 2, 3, 4]
        );
        assert_eq!(
            run(ListFilter {
                limit: 2,
                ..Default::default()
            }),
            [1, 2]
        );
        assert_eq!(
            run(ListFilter {
                tag: text("greet"),
                after: Some(1),
                limit: 1,
                ..Default::default()
            }),
            [2]
        );
    }

    #[test]
    fn limit_counts_notes_not_tags() {
        let (db, _dir) = temp_db();
        let mut conn = conn(&db);
        let a = add(&mut conn, "a", "", &["p", "q", "r"]);
        add(&mut conn, "b", "", &["p"]);
        let filter = ListFilter {
            limit: 1,
            ..Default::default()
        };
        assert_eq!(list(&conn, &filter).unwrap(), [a]);
    }
}
