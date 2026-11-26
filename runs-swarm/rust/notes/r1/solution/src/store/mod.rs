//! SQLite storage: connection pool, schema, and data access.
//!
//! Data access functions are plain synchronous functions over a [`rusqlite::Connection`], grouped by
//! feature (one submodule each). Handlers run them on the blocking thread pool through [`Db::call`].
//!
//! Schema:
//! - `notes(id, title, body)`: `id` is `AUTOINCREMENT`, so ids are never reused, even after a
//!   delete or a restart.
//! - `note_tags(note_id, tag)`: one row per tag of a note; rows are removed with their note
//!   (`ON DELETE CASCADE`, foreign keys are enabled on every connection).

pub mod crud;
pub mod list;
pub mod notes;
pub mod stats;

use std::path::Path;

use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::Connection;

/// Schema migrations, applied in order. `PRAGMA user_version` records how many have run, so a
/// migration must never be edited once released: append a new one instead.
const MIGRATIONS: &[&str] = &[r"
    CREATE TABLE notes (
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body  TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE note_tags (
        note_id INTEGER NOT NULL REFERENCES notes (id) ON DELETE CASCADE,
        tag     TEXT NOT NULL,
        PRIMARY KEY (note_id, tag)
    ) WITHOUT ROWID;
    CREATE INDEX note_tags_by_tag ON note_tags (tag, note_id);
"];

/// Settings applied to every pooled connection.
const CONNECTION_PRAGMAS: &str = "
    PRAGMA foreign_keys = ON;
    PRAGMA busy_timeout = 5000;
    PRAGMA synchronous = NORMAL;
";

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("database error: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("connection pool error: {0}")]
    Pool(#[from] r2d2::Error),
    #[error("database task failed: {0}")]
    Task(#[from] tokio::task::JoinError),
}

pub type Result<T, E = StoreError> = std::result::Result<T, E>;

/// A cheaply cloneable handle to the database.
#[derive(Clone)]
pub struct Db {
    pool: r2d2::Pool<SqliteConnectionManager>,
}

impl Db {
    /// Opens (creating if needed) the database file at `path` and brings its schema up to date.
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let manager = SqliteConnectionManager::file(path.as_ref())
            .with_init(|conn| conn.execute_batch(CONNECTION_PRAGMAS));
        let pool = r2d2::Pool::builder().build(manager)?;

        let mut conn = pool.get()?;
        // WAL lets readers proceed while a write is in progress; the mode is stored in the file.
        conn.pragma_update(None, "journal_mode", "WAL")?;
        migrate(&mut conn)?;
        drop(conn);

        Ok(Self { pool })
    }

    /// Runs `f` with a pooled connection on the blocking thread pool.
    ///
    /// Write operations should open their transaction with
    /// [`rusqlite::TransactionBehavior::Immediate`] so that concurrent writers wait on
    /// `busy_timeout` instead of failing with `SQLITE_BUSY` when upgrading a read lock.
    pub async fn call<T, F>(&self, f: F) -> Result<T>
    where
        F: FnOnce(&mut Connection) -> Result<T> + Send + 'static,
        T: Send + 'static,
    {
        let pool = self.pool.clone();
        tokio::task::spawn_blocking(move || f(&mut *pool.get()?)).await?
    }
}

fn migrate(conn: &mut Connection) -> Result<()> {
    let tx = conn.transaction_with_behavior(rusqlite::TransactionBehavior::Immediate)?;
    let applied: u32 = tx.pragma_query_value(None, "user_version", |row| row.get(0))?;
    for migration in MIGRATIONS.iter().skip(applied as usize) {
        tx.execute_batch(migration)?;
    }
    tx.pragma_update(None, "user_version", MIGRATIONS.len() as u32)?;
    tx.commit()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn open_is_idempotent() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("notes.db");
        Db::open(&path).unwrap();
        let db = Db::open(&path).unwrap();
        let version: u32 = db
            .call(|conn| Ok(conn.pragma_query_value(None, "user_version", |row| row.get(0))?))
            .await
            .unwrap();
        assert_eq!(version as usize, MIGRATIONS.len());
    }
}
