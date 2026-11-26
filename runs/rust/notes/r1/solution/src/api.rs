//! HTTP routes and handlers.

use std::collections::BTreeMap;
use std::sync::Arc;

use axum::Router;
use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, RawQuery, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Json, Response};
use axum::routing::{MethodRouter, get};
use serde::Serialize;
use serde_json::json;

use crate::model::{ListQuery, Note, NoteInput, parse_id};
use crate::store::Store;

const MAX_BODY_BYTES: usize = 16 * 1024 * 1024;

type AppState = Arc<Store>;

pub fn router(store: Arc<Store>) -> Router {
    Router::new()
        .route("/health", with_405(get(health)))
        .route("/notes", with_405(get(list_notes).post(create_note)))
        .route(
            "/notes/{id}",
            with_405(get(get_note).put(replace_note).delete(delete_note)),
        )
        .route("/stats", with_405(get(stats)))
        .route("/tags", with_405(get(tags)))
        .fallback(|| async { ApiError::NotFound })
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .with_state(store)
}

fn with_405(route: MethodRouter<AppState>) -> MethodRouter<AppState> {
    route.fallback(|| async { ApiError::MethodNotAllowed })
}

#[derive(Debug)]
pub enum ApiError {
    BadRequest(String),
    NotFound,
    MethodNotAllowed,
    Internal(String),
}

impl From<rusqlite::Error> for ApiError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Internal(e.to_string())
    }
}

impl From<tokio::task::JoinError> for ApiError {
    fn from(e: tokio::task::JoinError) -> Self {
        Self::Internal(e.to_string())
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, message) = match self {
            Self::BadRequest(msg) => (StatusCode::BAD_REQUEST, msg),
            Self::NotFound => (StatusCode::NOT_FOUND, "not found".into()),
            Self::MethodNotAllowed => {
                (StatusCode::METHOD_NOT_ALLOWED, "method not allowed".into())
            }
            Self::Internal(msg) => {
                eprintln!("internal error: {msg}");
                (StatusCode::INTERNAL_SERVER_ERROR, "internal error".into())
            }
        };
        (status, Json(json!({ "error": message }))).into_response()
    }
}

type ApiResult<T> = Result<T, ApiError>;

/// Runs a blocking database operation off the async executor.
async fn with_store<T, F>(store: AppState, op: F) -> ApiResult<T>
where
    T: Send + 'static,
    F: FnOnce(&Store) -> rusqlite::Result<T> + Send + 'static,
{
    Ok(tokio::task::spawn_blocking(move || op(&store)).await??)
}

fn note_id(segment: &str) -> ApiResult<i64> {
    parse_id(segment).ok_or(ApiError::NotFound)
}

fn note_input(body: &[u8]) -> ApiResult<NoteInput> {
    NoteInput::from_json(body).map_err(ApiError::BadRequest)
}

async fn health() -> &'static str {
    "ok"
}

async fn create_note(
    State(store): State<AppState>,
    body: Bytes,
) -> ApiResult<(StatusCode, Json<Note>)> {
    let input = note_input(&body)?;
    let note = with_store(store, move |s| s.create(&input)).await?;
    Ok((StatusCode::CREATED, Json(note)))
}

async fn get_note(State(store): State<AppState>, Path(id): Path<String>) -> ApiResult<Json<Note>> {
    let id = note_id(&id)?;
    with_store(store, move |s| s.get(id))
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}

async fn replace_note(
    State(store): State<AppState>,
    Path(id): Path<String>,
    body: Bytes,
) -> ApiResult<Json<Note>> {
    let id = note_id(&id)?;
    let input = note_input(&body)?;
    with_store(store, move |s| s.replace(id, &input))
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}

async fn delete_note(
    State(store): State<AppState>,
    Path(id): Path<String>,
) -> ApiResult<StatusCode> {
    let id = note_id(&id)?;
    if with_store(store, move |s| s.delete(id)).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError::NotFound)
    }
}

#[derive(Serialize)]
struct NoteList {
    notes: Vec<Note>,
}

async fn list_notes(
    State(store): State<AppState>,
    RawQuery(raw): RawQuery,
) -> ApiResult<Json<NoteList>> {
    let query = ListQuery::parse(raw.as_deref()).map_err(ApiError::BadRequest)?;
    let notes = with_store(store, move |s| s.list(&query)).await?;
    Ok(Json(NoteList { notes }))
}

#[derive(Serialize)]
struct Stats {
    notes: i64,
    tags: BTreeMap<String, i64>,
}

async fn stats(State(store): State<AppState>) -> ApiResult<Json<Stats>> {
    let (notes, tags) = with_store(store, |s| Ok((s.count()?, s.tag_counts()?))).await?;
    Ok(Json(Stats { notes, tags }))
}

#[derive(Serialize)]
struct TagCount {
    tag: String,
    count: i64,
}

#[derive(Serialize)]
struct TagList {
    tags: Vec<TagCount>,
}

async fn tags(State(store): State<AppState>) -> ApiResult<Json<TagList>> {
    let counts = with_store(store, |s| s.tag_counts()).await?;
    let mut tags: Vec<TagCount> = counts
        .into_iter()
        .map(|(tag, count)| TagCount { tag, count })
        .collect();
    // Counts arrive ordered by tag; a stable sort keeps that as the tie-breaker.
    tags.sort_by_key(|t| std::cmp::Reverse(t.count));
    Ok(Json(TagList { tags }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use serde_json::Value;
    use tower::ServiceExt;

    async fn call(app: &Router, method: &str, uri: &str, body: &str) -> (StatusCode, Value) {
        let req = Request::builder()
            .method(method)
            .uri(uri)
            .body(Body::from(body.to_owned()))
            .unwrap();
        let res = app.clone().oneshot(req).await.unwrap();
        let status = res.status();
        let bytes = res.into_body().collect().await.unwrap().to_bytes();
        let value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
        (status, value)
    }

    fn app() -> Router {
        router(Arc::new(Store::open_in_memory().unwrap()))
    }

    #[tokio::test]
    async fn status_codes() {
        let app = app();
        let (s, v) = call(&app, "POST", "/notes", r#"{"title":"a","tags":["b","a"]}"#).await;
        assert_eq!(s, StatusCode::CREATED);
        assert_eq!(v, json!({"id": 1, "title": "a", "body": "", "tags": ["a", "b"]}));

        assert_eq!(call(&app, "POST", "/notes", "nope").await.0, StatusCode::BAD_REQUEST);
        assert_eq!(call(&app, "DELETE", "/notes", "").await.0, StatusCode::METHOD_NOT_ALLOWED);
        assert_eq!(call(&app, "POST", "/notes/1", "").await.0, StatusCode::METHOD_NOT_ALLOWED);
        assert_eq!(call(&app, "GET", "/nope", "").await.0, StatusCode::NOT_FOUND);
        assert_eq!(call(&app, "GET", "/notes/-1", "").await.0, StatusCode::NOT_FOUND);
        assert_eq!(call(&app, "PUT", "/notes/x", "{}").await.0, StatusCode::NOT_FOUND);
        assert_eq!(call(&app, "GET", "/notes?limit=101", "").await.0, StatusCode::BAD_REQUEST);
        assert_eq!(call(&app, "DELETE", "/notes/1", "").await.0, StatusCode::NO_CONTENT);
        assert_eq!(call(&app, "DELETE", "/notes/1", "").await.0, StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn tags_ordering() {
        let app = app();
        for tags in [r#"["b"]"#, r#"["b","c"]"#, r#"["a"]"#] {
            let body = format!(r#"{{"title":"t","tags":{tags}}}"#);
            call(&app, "POST", "/notes", &body).await;
        }
        let (_, v) = call(&app, "GET", "/tags", "").await;
        assert_eq!(
            v,
            json!({"tags": [
                {"tag": "b", "count": 2}, {"tag": "a", "count": 1}, {"tag": "c", "count": 1}
            ]})
        );
        let (_, v) = call(&app, "GET", "/stats", "").await;
        assert_eq!(v, json!({"notes": 3, "tags": {"a": 1, "b": 2, "c": 1}}));
    }
}
