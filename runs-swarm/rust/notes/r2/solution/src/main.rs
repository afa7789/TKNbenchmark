use std::error::Error;
use std::net::Ipv4Addr;
use std::process::ExitCode;

use notes::{AppState, Db};
use tokio::net::TcpListener;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> ExitCode {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()))
        .with_writer(std::io::stderr)
        .init();

    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            tracing::error!("{err}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<(), Box<dyn Error>> {
    let port: u16 = std::env::args()
        .nth(1)
        .ok_or("usage: app <port>")?
        .parse()
        .map_err(|err| format!("invalid port: {err}"))?;
    let db_path =
        std::env::var_os("NOTES_DB").ok_or("the NOTES_DB environment variable must be set")?;

    let db =
        Db::open(&db_path).map_err(|err| format!("cannot open database {db_path:?}: {err}"))?;
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, port)).await?;
    tracing::info!("listening on {}", listener.local_addr()?);

    axum::serve(listener, notes::router(AppState { db }))
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

/// Resolves on Ctrl-C or SIGTERM.
async fn shutdown_signal() {
    let ctrl_c = async {
        tokio::signal::ctrl_c().await.ok();
    };
    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(_) => std::future::pending().await,
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => {},
        () = terminate => {},
    }
}
