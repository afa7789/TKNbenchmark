use std::net::{Ipv4Addr, SocketAddr};

use anyhow::{Context, bail};
use notes::{AppState, Store, router};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .with_writer(std::io::stderr)
        .init();

    let mut args = std::env::args().skip(1);
    let (Some(port), None) = (args.next(), args.next()) else {
        bail!("usage: app <port>");
    };
    let port: u16 = port
        .parse()
        .with_context(|| format!("invalid port {port:?}"))?;
    let db_path =
        std::env::var_os("NOTES_DB").context("the NOTES_DB environment variable is not set")?;

    let store = Store::open(&db_path)
        .with_context(|| format!("cannot open database {}", db_path.to_string_lossy()))?;
    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("cannot listen on {addr}"))?;
    tracing::info!(%addr, "listening");

    axum::serve(listener, router(AppState { store }))
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

async fn shutdown_signal() {
    if let Err(err) = tokio::signal::ctrl_c().await {
        tracing::error!(error = %err, "cannot listen for the shutdown signal");
        std::future::pending::<()>().await;
    }
}
