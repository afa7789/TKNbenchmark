//! `PUT` and `DELETE /notes/{id}`.

use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::put;
use axum::{Json, Router};

use super::{AppState, NoteId};
use crate::error::ApiError;
use crate::model::{Note, NoteInput};

pub fn router() -> Router<AppState> {
    Router::new().route("/notes/{id}", put(update_note).delete(delete_note))
}

/// Full replacement: an omitted `body` or `tags` resets it to its default.
async fn update_note(
    State(state): State<AppState>,
    NoteId(id): NoteId,
    body: Bytes,
) -> Result<Json<Note>, ApiError> {
    let input = NoteInput::from_json(&body)?;
    state
        .store
        .update_note(id, input)
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}

async fn delete_note(
    State(state): State<AppState>,
    NoteId(id): NoteId,
) -> Result<StatusCode, ApiError> {
    if state.store.delete_note(id).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError::NotFound)
    }
}
