//! Router assembly and the server loop.

use axum::Router;
use axum::routing::get;
use tokio::net::TcpListener;

use crate::api;
use crate::error::ApiError;
use crate::store::Db;

/// Builds the application: every feature's routes, plus JSON 404 and 405 fallbacks.
pub fn router(db: Db) -> Router {
    Router::new()
        .route("/health", get(health))
        .merge(api::notes::routes())
        .merge(api::crud::routes())
        .merge(api::list::routes())
        .merge(api::stats::routes())
        .fallback(async || ApiError::NotFound)
        .method_not_allowed_fallback(async || ApiError::MethodNotAllowed)
        .with_state(db)
}

async fn health() -> &'static str {
    "ok"
}

/// Serves `router` on `listener` until Ctrl-C or SIGTERM, then drains in-flight requests.
pub async fn serve(listener: TcpListener, router: Router) -> std::io::Result<()> {
    axum::serve(listener, router)
        .with_graceful_shutdown(shutdown_signal())
        .await
}

async fn shutdown_signal() {
    let ctrl_c = async {
        if let Err(err) = tokio::signal::ctrl_c().await {
            tracing::warn!(error = %err, "cannot listen for Ctrl-C");
            std::future::pending::<()>().await;
        }
    };

    #[cfg(unix)]
    let terminate = async {
        use tokio::signal::unix::{SignalKind, signal};
        match signal(SignalKind::terminate()) {
            Ok(mut sigterm) => {
                sigterm.recv().await;
            }
            Err(err) => {
                tracing::warn!(error = %err, "cannot listen for SIGTERM");
                std::future::pending::<()>().await;
            }
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => {}
        () = terminate => {}
    }
    tracing::info!("shutting down");
}
