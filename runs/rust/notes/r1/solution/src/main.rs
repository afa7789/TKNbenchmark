//! notes: a small HTTP notes store backed by SQLite.
//!
//! Usage: `NOTES_DB=<path> notes <port>`

mod api;
mod model;
mod store;

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::Arc;

use store::Store;

#[tokio::main]
async fn main() -> ExitCode {
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), Box<dyn std::error::Error>> {
    let port: u16 = std::env::args()
        .nth(1)
        .ok_or("usage: notes <port>")?
        .parse()
        .map_err(|e| format!("invalid port: {e}"))?;
    let db_path = std::env::var_os("NOTES_DB").ok_or("NOTES_DB is not set")?;

    let store = Store::open(&db_path)
        .map_err(|e| format!("cannot open database {}: {e}", db_path.display()))?;
    let app = api::router(Arc::new(store));

    let listener =
        tokio::net::TcpListener::bind(SocketAddr::from((Ipv4Addr::LOCALHOST, port))).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(async {
            let _ = tokio::signal::ctrl_c().await;
        })
        .await?;
    Ok(())
}
