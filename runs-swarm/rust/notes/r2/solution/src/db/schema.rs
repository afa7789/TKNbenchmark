//! Schema creation and migrations, tracked with SQLite's `user_version`.

use rusqlite::{Connection, TransactionBehavior};

/// Migrations in order; migration `i` brings the schema from version `i` to `i + 1`.
const MIGRATIONS: &[&str] = &[
    // `AUTOINCREMENT` guarantees that ids are never reused, also after deleting the newest note.
    "CREATE TABLE notes (
         id    INTEGER PRIMARY KEY AUTOINCREMENT,
         title TEXT NOT NULL,
         body  TEXT NOT NULL DEFAULT ''
     );
     CREATE TABLE note_tags (
         note_id INTEGER NOT NULL REFERENCES notes (id) ON DELETE CASCADE,
         tag     TEXT NOT NULL,
         PRIMARY KEY (note_id, tag)
     ) WITHOUT ROWID;
     CREATE INDEX note_tags_by_tag ON note_tags (tag, note_id);",
];

pub fn migrate(conn: &mut Connection) -> rusqlite::Result<()> {
    let tx = conn.transaction_with_behavior(TransactionBehavior::Immediate)?;
    let version: u32 = tx.pragma_query_value(None, "user_version", |row| row.get(0))?;
    let latest = u32::try_from(MIGRATIONS.len()).expect("migration count fits in u32");
    for migration in MIGRATIONS.iter().skip(version as usize) {
        tx.execute_batch(migration)?;
    }
    if version < latest {
        tx.pragma_update(None, "user_version", latest)?;
    }
    tx.commit()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrate_is_idempotent() {
        let mut conn = Connection::open_in_memory().unwrap();
        migrate(&mut conn).unwrap();
        migrate(&mut conn).unwrap();
        let version: u32 = conn
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .unwrap();
        assert_eq!(version as usize, MIGRATIONS.len());
    }
}
