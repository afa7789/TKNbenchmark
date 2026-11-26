//! `GET /health`, `POST /notes` and `GET /notes/{id}`.

use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};

use super::{AppState, NoteId};
use crate::error::ApiError;
use crate::model::{Note, NoteInput};

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/health", get(health))
        .route("/notes", post(create_note))
        .route("/notes/{id}", get(get_note))
}

async fn health() -> &'static str {
    "ok"
}

async fn create_note(
    State(state): State<AppState>,
    body: Bytes,
) -> Result<(StatusCode, Json<Note>), ApiError> {
    let input = NoteInput::from_json(&body)?;
    let note = state.store.create_note(input).await?;
    Ok((StatusCode::CREATED, Json(note)))
}

async fn get_note(
    State(state): State<AppState>,
    NoteId(id): NoteId,
) -> Result<Json<Note>, ApiError> {
    state
        .store
        .get_note(id)
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}
