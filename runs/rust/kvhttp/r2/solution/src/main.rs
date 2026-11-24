//! kvhttp: an in-memory HTTP/1.1 key-value server.

use std::collections::BTreeMap;
use std::net::{Ipv4Addr, SocketAddr};
use std::process::ExitCode;
use std::sync::{Arc, RwLock};

use axum::Router;
use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, State};
use axum::http::{Method, StatusCode, Uri, header};
use axum::response::{IntoResponse, Response};

/// Largest accepted value, in bytes.
const MAX_VALUE_LEN: usize = 1024 * 1024;
const MAX_KEY_LEN: usize = 64;

/// Keys are kept in a `BTreeMap` so listing them yields ascending order for free.
type Store = Arc<RwLock<BTreeMap<String, Bytes>>>;

/// The resource a request path refers to.
enum Route<'a> {
    Health,
    List,
    Item(&'a str),
    InvalidKey,
    NotFound,
}

fn is_valid_key(key: &str) -> bool {
    (1..=MAX_KEY_LEN).contains(&key.len())
        && key
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn route(path: &str) -> Route<'_> {
    match path {
        "/health" => Route::Health,
        "/kv" => Route::List,
        _ => match path.strip_prefix("/kv/") {
            Some(key) if is_valid_key(key) => Route::Item(key),
            Some(_) => Route::InvalidKey,
            None => Route::NotFound,
        },
    }
}

async fn handle(State(store): State<Store>, method: Method, uri: Uri, body: Bytes) -> Response {
    match (route(uri.path()), method) {
        (Route::NotFound, _) => StatusCode::NOT_FOUND.into_response(),
        (Route::InvalidKey, _) => StatusCode::BAD_REQUEST.into_response(),

        (Route::Health, Method::GET) => "ok".into_response(),

        (Route::List, Method::GET) => {
            let keys: Vec<String> = store.read().unwrap().keys().cloned().collect();
            let json = serde_json::to_vec(&keys).expect("serializing strings cannot fail");
            ([(header::CONTENT_TYPE, "application/json")], json).into_response()
        }

        (Route::Item(key), Method::GET) => match store.read().unwrap().get(key) {
            Some(value) => value.clone().into_response(),
            None => StatusCode::NOT_FOUND.into_response(),
        },
        (Route::Item(key), Method::PUT) => {
            let previous = store.write().unwrap().insert(key.to_owned(), body);
            if previous.is_some() {
                StatusCode::OK.into_response()
            } else {
                StatusCode::CREATED.into_response()
            }
        }
        (Route::Item(key), Method::DELETE) => match store.write().unwrap().remove(key) {
            Some(_) => StatusCode::NO_CONTENT.into_response(),
            None => StatusCode::NOT_FOUND.into_response(),
        },

        (Route::Health | Route::List | Route::Item(_), _) => {
            StatusCode::METHOD_NOT_ALLOWED.into_response()
        }
    }
}

fn app() -> Router {
    Router::new()
        .fallback(handle)
        .layer(DefaultBodyLimit::max(MAX_VALUE_LEN))
        .with_state(Store::default())
}

#[tokio::main]
async fn main() -> ExitCode {
    let port = match std::env::args().nth(1).map(|arg| arg.parse::<u16>()) {
        Some(Ok(port)) => port,
        _ => {
            eprintln!("usage: app <port>");
            return ExitCode::from(2);
        }
    };

    let addr = SocketAddr::from((Ipv4Addr::LOCALHOST, port));
    let listener = match tokio::net::TcpListener::bind(addr).await {
        Ok(listener) => listener,
        Err(err) => {
            eprintln!("failed to bind {addr}: {err}");
            return ExitCode::FAILURE;
        }
    };

    if let Err(err) = axum::serve(listener, app()).await {
        eprintln!("server error: {err}");
        return ExitCode::FAILURE;
    }
    ExitCode::SUCCESS
}
