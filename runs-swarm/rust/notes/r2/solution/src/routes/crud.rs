//! `PUT /notes/{id}` and `DELETE /notes/{id}`.

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::put;
use axum::{Json, Router};

use crate::AppState;
use crate::db;
use crate::error::{ApiError, ApiResult};
use crate::extract::NoteId;
use crate::model::{Note, NoteInput};

pub fn routes() -> Router<AppState> {
    Router::new().route("/notes/{id}", put(update).delete(remove))
}

/// Replaces a note entirely: an omitted `body` or `tags` becomes `""` or `[]`.
async fn update(
    State(state): State<AppState>,
    NoteId(id): NoteId,
    input: NoteInput,
) -> ApiResult<Json<Note>> {
    state
        .db
        .run(move |conn| db::crud::update(conn, id, input))
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}

async fn remove(State(state): State<AppState>, NoteId(id): NoteId) -> ApiResult<StatusCode> {
    if state.db.run(move |conn| db::crud::delete(conn, id)).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError::NotFound)
    }
}
