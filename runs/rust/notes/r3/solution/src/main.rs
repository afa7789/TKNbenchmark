//! `notes <port>`: a small JSON notes service backed by SQLite.

mod api;
mod db;
mod model;

use std::net::{Ipv4Addr, SocketAddr};
use std::sync::Arc;

use anyhow::{Context, Result};

#[tokio::main]
async fn main() -> Result<()> {
    let port: u16 = std::env::args()
        .nth(1)
        .context("usage: app <port>")?
        .parse()
        .context("port must be an integer from 0 to 65535")?;
    let db_path = std::env::var_os("NOTES_DB").context("NOTES_DB must be set")?;

    let store = db::Store::open(&db_path)
        .with_context(|| format!("opening database {}", db_path.to_string_lossy()))?;
    let app = api::router(Arc::new(store));

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("binding {addr}"))?;
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("server error")
}

/// Resolves on Ctrl-C or SIGTERM.
async fn shutdown_signal() {
    use tokio::signal::unix::{SignalKind, signal};
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    match signal(SignalKind::terminate()) {
        Ok(mut term) => tokio::select! {
            _ = ctrl_c => {}
            _ = term.recv() => {}
        },
        Err(_) => ctrl_c.await,
    }
}
