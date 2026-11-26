//! HTTP routes and handlers.

use std::sync::Arc;

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, RawQuery, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use serde_json::json;

use crate::db::Store;
use crate::model::{ListQuery, Note, NoteInput, ValidationError};

const MAX_BODY_BYTES: usize = 64 * 1024 * 1024;

type AppState = Arc<Store>;

/// Errors a handler can return, mapped to HTTP responses with JSON bodies.
#[derive(Debug)]
pub enum ApiError {
    BadRequest(String),
    NotFound,
    MethodNotAllowed,
    Internal(String),
}

impl From<ValidationError> for ApiError {
    fn from(e: ValidationError) -> Self {
        Self::BadRequest(e.0)
    }
}

impl From<rusqlite::Error> for ApiError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Internal(e.to_string())
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            Self::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            Self::NotFound => (StatusCode::NOT_FOUND, "not found".to_owned()),
            Self::MethodNotAllowed => {
                (StatusCode::METHOD_NOT_ALLOWED, "method not allowed".to_owned())
            }
            Self::Internal(msg) => {
                eprintln!("internal error: {msg}");
                (StatusCode::INTERNAL_SERVER_ERROR, "internal error".to_owned())
            }
        };
        (status, Json(json!({ "error": message }))).into_response()
    }
}

type ApiResult<T> = Result<T, ApiError>;

pub fn router(store: Arc<Store>) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/notes", get(list_notes).post(create_note))
        .route("/notes/{id}", get(get_note).put(update_note).delete(delete_note))
        .route("/stats", get(stats))
        .route("/tags", get(tags))
        .fallback(|| async { ApiError::NotFound })
        .method_not_allowed_fallback(|| async { ApiError::MethodNotAllowed })
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .with_state(store)
}

/// Runs a database operation on the blocking thread pool.
async fn run_db<T, F>(store: AppState, f: F) -> ApiResult<T>
where
    F: FnOnce(&Store) -> Result<T, ApiError> + Send + 'static,
    T: Send + 'static,
{
    tokio::task::spawn_blocking(move || f(&store))
        .await
        .map_err(|e| ApiError::Internal(e.to_string()))?
}

/// Note ids in paths must be positive integers; anything else is an unknown note.
fn parse_id(raw: &str) -> ApiResult<i64> {
    match raw.parse::<i64>() {
        Ok(id) if id > 0 && raw.bytes().all(|b| b.is_ascii_digit()) => Ok(id),
        _ => Err(ApiError::NotFound),
    }
}

async fn health() -> &'static str {
    "ok"
}

async fn create_note(State(store): State<AppState>, body: Bytes) -> ApiResult<impl IntoResponse> {
    let input = NoteInput::from_json(&body)?;
    let note = run_db(store, move |s| Ok(s.create(input)?)).await?;
    Ok((StatusCode::CREATED, Json(note)))
}

async fn get_note(State(store): State<AppState>, Path(id): Path<String>) -> ApiResult<Json<Note>> {
    let id = parse_id(&id)?;
    run_db(store, move |s| s.get(id)?.ok_or(ApiError::NotFound)).await.map(Json)
}

async fn update_note(
    State(store): State<AppState>,
    Path(id): Path<String>,
    body: Bytes,
) -> ApiResult<Json<Note>> {
    let id = parse_id(&id)?;
    let input = NoteInput::from_json(&body)?;
    run_db(store, move |s| s.update(id, input)?.ok_or(ApiError::NotFound)).await.map(Json)
}

async fn delete_note(State(store): State<AppState>, Path(id): Path<String>) -> ApiResult<StatusCode> {
    let id = parse_id(&id)?;
    run_db(store, move |s| match s.delete(id)? {
        true => Ok(StatusCode::NO_CONTENT),
        false => Err(ApiError::NotFound),
    })
    .await
}

async fn list_notes(
    State(store): State<AppState>,
    RawQuery(query): RawQuery,
) -> ApiResult<impl IntoResponse> {
    let query = ListQuery::from_query_string(query.as_deref().unwrap_or(""))?;
    let notes = run_db(store, move |s| Ok(s.list(&query)?)).await?;
    Ok(Json(json!({ "notes": notes })))
}

async fn stats(State(store): State<AppState>) -> ApiResult<impl IntoResponse> {
    let (count, tags) = run_db(store, |s| Ok(s.stats()?)).await?;
    Ok(Json(json!({ "notes": count, "tags": tags })))
}

async fn tags(State(store): State<AppState>) -> ApiResult<impl IntoResponse> {
    let counts = run_db(store, |s| Ok(s.tag_counts()?)).await?;
    let tags: Vec<_> = counts
        .into_iter()
        .map(|(tag, count)| json!({ "tag": tag, "count": count }))
        .collect();
    Ok(Json(json!({ "tags": tags })))
}
