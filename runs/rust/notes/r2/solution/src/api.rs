//! HTTP routes and handlers.

use std::sync::Arc;

use axum::body::Bytes;
use axum::extract::{DefaultBodyLimit, Path, RawQuery, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::{Json, Router};
use serde_json::{Map, Value, json};

use crate::db::{ListFilter, Store};
use crate::model::{Note, NoteInput, ValidationError};

const MAX_BODY_BYTES: usize = 16 * 1024 * 1024;
const MAX_LIMIT: usize = 100;

type AppState = Arc<Store>;

pub fn router(store: Arc<Store>) -> Router {
    Router::new()
        .route("/health", get(health).fallback(method_not_allowed))
        .route(
            "/notes",
            get(list_notes).post(create_note).fallback(method_not_allowed),
        )
        .route(
            "/notes/{id}",
            get(get_note)
                .put(update_note)
                .delete(delete_note)
                .fallback(method_not_allowed),
        )
        .route("/stats", get(stats).fallback(method_not_allowed))
        .route("/tags", get(tags).fallback(method_not_allowed))
        .fallback(not_found)
        .layer(DefaultBodyLimit::max(MAX_BODY_BYTES))
        .with_state(store)
}

#[derive(Debug, thiserror::Error)]
pub enum ApiError {
    #[error(transparent)]
    BadRequest(#[from] ValidationError),
    #[error("{0}")]
    BadQuery(&'static str),
    #[error("not found")]
    NotFound,
    #[error("method not allowed")]
    MethodNotAllowed,
    #[error("internal error")]
    Internal(#[source] anyhow::Error),
}

impl From<rusqlite::Error> for ApiError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Internal(e.into())
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let status = match &self {
            Self::BadRequest(_) | Self::BadQuery(_) => StatusCode::BAD_REQUEST,
            Self::NotFound => StatusCode::NOT_FOUND,
            Self::MethodNotAllowed => StatusCode::METHOD_NOT_ALLOWED,
            Self::Internal(e) => {
                eprintln!("internal error: {e:#}");
                StatusCode::INTERNAL_SERVER_ERROR
            }
        };
        (status, Json(json!({ "error": self.to_string() }))).into_response()
    }
}

type ApiResult<T> = Result<T, ApiError>;

/// Runs a blocking database operation off the async executor.
async fn with_store<T, F>(store: AppState, op: F) -> ApiResult<T>
where
    T: Send + 'static,
    F: FnOnce(&Store) -> rusqlite::Result<T> + Send + 'static,
{
    tokio::task::spawn_blocking(move || op(&store))
        .await
        .map_err(|e| ApiError::Internal(e.into()))?
        .map_err(ApiError::from)
}

/// Parses a note id path segment; anything but a positive integer is a 404.
fn parse_id(raw: &str) -> ApiResult<i64> {
    if raw.is_empty() || !raw.bytes().all(|b| b.is_ascii_digit()) {
        return Err(ApiError::NotFound);
    }
    match raw.parse::<i64>() {
        Ok(id) if id > 0 => Ok(id),
        _ => Err(ApiError::NotFound),
    }
}

fn parse_list_query(raw: Option<&str>) -> ApiResult<ListFilter> {
    let mut filter = ListFilter::default();
    for (key, value) in form_urlencoded::parse(raw.unwrap_or_default().as_bytes()) {
        match &*key {
            "tag" => filter.tag = Some(value.into_owned()),
            "q" => filter.q = Some(value.into_owned()),
            "after" => {
                filter.after = value
                    .parse()
                    .map_err(|_| ApiError::BadQuery("after must be an integer"))?;
            }
            "limit" => {
                filter.limit = value
                    .parse()
                    .ok()
                    .filter(|n| (1..=MAX_LIMIT).contains(n))
                    .ok_or(ApiError::BadQuery("limit must be an integer from 1 to 100"))?;
            }
            _ => {}
        }
    }
    Ok(filter)
}

async fn health() -> &'static str {
    "ok"
}

async fn not_found() -> ApiError {
    ApiError::NotFound
}

async fn method_not_allowed() -> ApiError {
    ApiError::MethodNotAllowed
}

async fn create_note(State(store): State<AppState>, body: Bytes) -> ApiResult<impl IntoResponse> {
    let input = NoteInput::from_json(&body)?;
    let note = with_store(store, move |s| s.create(&input)).await?;
    Ok((StatusCode::CREATED, Json(note)))
}

async fn get_note(State(store): State<AppState>, Path(id): Path<String>) -> ApiResult<Json<Note>> {
    let id = parse_id(&id)?;
    with_store(store, move |s| s.get(id))
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}

async fn update_note(
    State(store): State<AppState>,
    Path(id): Path<String>,
    body: Bytes,
) -> ApiResult<Json<Note>> {
    let id = parse_id(&id)?;
    let input = NoteInput::from_json(&body)?;
    with_store(store, move |s| s.update(id, &input))
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}

async fn delete_note(State(store): State<AppState>, Path(id): Path<String>) -> ApiResult<StatusCode> {
    let id = parse_id(&id)?;
    if with_store(store, move |s| s.delete(id)).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError::NotFound)
    }
}

async fn list_notes(State(store): State<AppState>, RawQuery(query): RawQuery) -> ApiResult<Json<Value>> {
    let filter = parse_list_query(query.as_deref())?;
    let notes = with_store(store, move |s| s.list(&filter)).await?;
    Ok(Json(json!({ "notes": notes })))
}

async fn stats(State(store): State<AppState>) -> ApiResult<Json<Value>> {
    let (count, tags) = with_store(store, |s| Ok((s.count()?, s.tag_counts()?))).await?;
    let tags: Map<String, Value> = tags.into_iter().map(|(t, n)| (t, n.into())).collect();
    Ok(Json(json!({ "notes": count, "tags": tags })))
}

async fn tags(State(store): State<AppState>) -> ApiResult<Json<Value>> {
    let tags = with_store(store, |s| s.tag_counts()).await?;
    let tags: Vec<Value> = tags
        .into_iter()
        .map(|(tag, count)| json!({ "tag": tag, "count": count }))
        .collect();
    Ok(Json(json!({ "tags": tags })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids() {
        assert_eq!(parse_id("12").unwrap(), 12);
        for bad in ["0", "-1", "+1", "abc", "", "1.0", "99999999999999999999"] {
            assert!(matches!(parse_id(bad), Err(ApiError::NotFound)), "{bad}");
        }
    }

    #[test]
    fn list_query() {
        let f = parse_list_query(Some("tag=a&q=Hi+there&after=3&limit=5&x=1")).unwrap();
        assert_eq!(f.tag.as_deref(), Some("a"));
        assert_eq!(f.q.as_deref(), Some("Hi there"));
        assert_eq!((f.after, f.limit), (3, 5));
        assert_eq!(parse_list_query(None).unwrap(), ListFilter::default());
        for bad in ["limit=0", "limit=101", "limit=", "limit=x", "after=x", "after=1.5"] {
            assert!(parse_list_query(Some(bad)).is_err(), "{bad}");
        }
    }
}
