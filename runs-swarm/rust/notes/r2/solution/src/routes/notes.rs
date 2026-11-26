//! `POST /notes` and `GET /notes/{id}`.

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};

use crate::AppState;
use crate::db;
use crate::error::{ApiError, ApiResult};
use crate::extract::NoteId;
use crate::model::{Note, NoteInput};

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/notes", post(create))
        .route("/notes/{id}", get(show))
}

async fn create(
    State(state): State<AppState>,
    input: NoteInput,
) -> ApiResult<(StatusCode, Json<Note>)> {
    let note = state
        .db
        .run(move |conn| db::notes::insert(conn, input))
        .await?;
    Ok((StatusCode::CREATED, Json(note)))
}

async fn show(State(state): State<AppState>, NoteId(id): NoteId) -> ApiResult<Json<Note>> {
    state
        .db
        .run(move |conn| db::notes::get(conn, id))
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}
