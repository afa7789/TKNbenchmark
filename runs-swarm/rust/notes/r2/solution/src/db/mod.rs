//! SQLite storage: a connection pool, the schema, and data access split by feature.
//!
//! Data-access functions are plain synchronous functions over a [`rusqlite::Connection`]; handlers
//! run them on the blocking thread pool with [`Db::run`]:
//!
//! ```ignore
//! let note = state.db.run(move |conn| db::notes::get(conn, id)).await?;
//! ```

pub mod crud;
pub mod list;
pub mod notes;
mod schema;
pub mod stats;

use std::path::Path;
use std::time::Duration;

use r2d2_sqlite::SqliteConnectionManager;
use rusqlite::Connection;

/// How long a connection waits for a lock held by another connection before failing.
const BUSY_TIMEOUT: Duration = Duration::from_secs(5);
const MAX_CONNECTIONS: u32 = 8;

#[derive(Debug, thiserror::Error)]
pub enum DbError {
    #[error("connection pool: {0}")]
    Pool(#[from] r2d2::Error),
    #[error("sqlite: {0}")]
    Sqlite(#[from] rusqlite::Error),
    #[error("database task failed: {0}")]
    Task(#[from] tokio::task::JoinError),
}

/// A handle to the database; cheap to clone.
#[derive(Clone)]
pub struct Db {
    pool: r2d2::Pool<SqliteConnectionManager>,
}

impl Db {
    /// Opens (creating if needed) the database file at `path` and brings its schema up to date.
    pub fn open(path: impl AsRef<Path>) -> Result<Self, DbError> {
        let path = path.as_ref();
        // Prepare the file on a single connection before the pool opens several at once: switching
        // to WAL needs an exclusive lock, and the setting persists in the database file.
        {
            let mut conn = Connection::open(path)?;
            configure(&mut conn)?;
            conn.pragma_update(None, "journal_mode", "WAL")?;
            schema::migrate(&mut conn)?;
        }
        let manager = SqliteConnectionManager::file(path).with_init(configure);
        let pool = r2d2::Pool::builder()
            .max_size(MAX_CONNECTIONS)
            .build(manager)?;
        Ok(Self { pool })
    }

    /// Runs `f` with a pooled connection on the blocking thread pool.
    ///
    /// Use [`rusqlite::TransactionBehavior::Immediate`] transactions for read-then-write work so that
    /// concurrent writers queue on the busy timeout instead of failing with `SQLITE_BUSY`.
    pub async fn run<F, T>(&self, f: F) -> Result<T, DbError>
    where
        F: FnOnce(&mut Connection) -> rusqlite::Result<T> + Send + 'static,
        T: Send + 'static,
    {
        let pool = self.pool.clone();
        tokio::task::spawn_blocking(move || {
            let mut conn = pool.get()?;
            Ok(f(&mut conn)?)
        })
        .await?
    }
}

fn configure(conn: &mut Connection) -> rusqlite::Result<()> {
    conn.busy_timeout(BUSY_TIMEOUT)?;
    // In WAL mode (set in `Db::open`), NORMAL sync is durable across application crashes.
    conn.pragma_update(None, "synchronous", "NORMAL")?;
    conn.pragma_update(None, "foreign_keys", true)?;
    Ok(())
}

#[cfg(test)]
pub(crate) mod test_util {
    use super::*;

    /// A database in a fresh temporary directory, deleted when the returned guard is dropped.
    pub fn temp_db() -> (Db, tempfile::TempDir) {
        let dir = tempfile::tempdir().expect("create temp dir");
        let db = Db::open(dir.path().join("notes.db")).expect("open database");
        (db, dir)
    }

    pub fn conn(db: &Db) -> r2d2::PooledConnection<SqliteConnectionManager> {
        db.pool.get().expect("get connection")
    }
}
