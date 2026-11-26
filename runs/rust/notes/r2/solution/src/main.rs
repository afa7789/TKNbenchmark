//! A small notes store over HTTP, backed by SQLite.
//!
//! Usage: `NOTES_DB=/path/to/notes.db app <port>`

mod api;
mod db;
mod model;

use std::net::{Ipv4Addr, SocketAddr};
use std::sync::Arc;

use anyhow::{Context, bail};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let (Some(port), None) = (args.next(), args.next()) else {
        bail!("usage: app <port>");
    };
    let port: u16 = port.parse().with_context(|| format!("invalid port {port:?}"))?;
    let db_path = std::env::var_os("NOTES_DB").context("NOTES_DB must be set")?;

    let store = db::Store::open(&db_path)
        .with_context(|| format!("opening database {}", db_path.to_string_lossy()))?;

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("binding {addr}"))?;
    axum::serve(listener, api::router(Arc::new(store)))
        .await
        .context("serving HTTP")
}
