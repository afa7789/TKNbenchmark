use std::net::{Ipv4Addr, SocketAddr};

use anyhow::{Context, bail};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let mut args = std::env::args().skip(1);
    let (Some(port), None) = (args.next(), args.next()) else {
        bail!("usage: app <port>");
    };
    let port: u16 = port
        .parse()
        .with_context(|| format!("invalid port: {port}"))?;

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("failed to bind {addr}"))?;

    axum::serve(listener, kvhttp::router())
        .with_graceful_shutdown(async {
            // If installing the handler fails, just run until killed.
            if tokio::signal::ctrl_c().await.is_err() {
                std::future::pending::<()>().await;
            }
        })
        .await
        .context("server error")
}
