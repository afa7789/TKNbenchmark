//! SQLite storage: connection pool, schema and data access.
//!
//! Data access is split by feature: each submodule adds an `impl Store` block with the queries its
//! endpoints need. Queries run on a blocking thread through [`Store::call`].

pub mod crud;
pub mod list;
mod notes;
pub mod stats;

use std::path::Path;
use std::time::Duration;

use r2d2::Pool;
use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::Connection;

const SCHEMA: &str = "
    CREATE TABLE IF NOT EXISTS notes (
        -- AUTOINCREMENT: ids are never reused, even after the highest one is deleted.
        id    INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        body  TEXT NOT NULL DEFAULT ''
    );
    CREATE TABLE IF NOT EXISTS note_tags (
        note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
        tag     TEXT NOT NULL,
        PRIMARY KEY (note_id, tag)
    ) WITHOUT ROWID;
    CREATE INDEX IF NOT EXISTS note_tags_by_tag ON note_tags(tag, note_id);
";

const POOL_SIZE: u32 = 8;
const BUSY_TIMEOUT: Duration = Duration::from_secs(5);

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

/// A handle to the notes database. Cheap to clone; clones share one connection pool.
#[derive(Clone)]
pub struct Store {
    pool: Pool<SqliteConnectionManager>,
}

impl Store {
    /// Opens (creating if needed) the database file at `path` and its schema.
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let manager = SqliteConnectionManager::file(path).with_init(configure_connection);
        let pool = Pool::builder().max_size(POOL_SIZE).build(manager)?;
        let conn = pool.get()?;
        conn.pragma_update(None, "journal_mode", "WAL")?;
        conn.execute_batch(SCHEMA)?;
        Ok(Self { pool })
    }

    /// Runs `f` with a pooled connection on a blocking thread.
    pub async fn call<T, F>(&self, f: F) -> Result<T>
    where
        F: FnOnce(&mut Connection) -> Result<T> + Send + 'static,
        T: Send + 'static,
    {
        let pool = self.pool.clone();
        tokio::task::spawn_blocking(move || {
            let mut conn = pool.get()?;
            f(&mut conn)
        })
        .await?
    }
}

fn configure_connection(conn: &mut Connection) -> rusqlite::Result<()> {
    conn.busy_timeout(BUSY_TIMEOUT)?;
    conn.pragma_update(None, "foreign_keys", "ON")?;
    conn.pragma_update(None, "synchronous", "NORMAL")
}

#[cfg(test)]
pub(crate) mod test_support {
    use super::Store;

    /// A store backed by a fresh database in a temporary directory, deleted on drop.
    pub struct TempStore {
        pub store: Store,
        _dir: tempfile::TempDir,
    }

    impl TempStore {
        pub fn new() -> Self {
            let dir = tempfile::tempdir().expect("create temp dir");
            let store = Store::open(dir.path().join("notes.db")).expect("open store");
            Self { store, _dir: dir }
        }
    }
}
