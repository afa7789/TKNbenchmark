//! `app <port>`: serves the notes API on `127.0.0.1:<port>`, storing data in the SQLite database
//! at `$NOTES_DB`.

use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;

use anyhow::{Context, bail};
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

use notes::app;
use notes::store::Db;

#[tokio::main]
async fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with_writer(std::io::stderr)
        .init();

    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            tracing::error!("{err:#}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let (Some(port), None) = (args.next(), args.next()) else {
        bail!("usage: app <port>");
    };
    let port: u16 = port
        .parse()
        .with_context(|| format!("invalid port {port:?}"))?;
    let db_path = std::env::var_os("NOTES_DB").context("NOTES_DB is not set")?;

    let db = Db::open(&db_path)
        .with_context(|| format!("cannot open database {}", db_path.to_string_lossy()))?;

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = TcpListener::bind(addr)
        .await
        .with_context(|| format!("cannot listen on {addr}"))?;
    tracing::info!(%addr, "listening");

    app::serve(listener, app::router(db)).await?;
    Ok(())
}
