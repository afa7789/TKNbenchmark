//! `POST /notes` and `GET /notes/{id}`.

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::{get, post};
use axum::{Json, Router};

use crate::error::{ApiError, ApiResult};
use crate::note::{Note, NoteId, NoteInput};
use crate::store::{self, Db};

pub fn routes() -> Router<Db> {
    Router::new()
        .route("/notes", post(create))
        .route("/notes/{id}", get(fetch))
}

async fn create(State(db): State<Db>, input: NoteInput) -> ApiResult<(StatusCode, Json<Note>)> {
    let note = db
        .call(move |conn| store::notes::insert(conn, &input))
        .await?;
    Ok((StatusCode::CREATED, Json(note)))
}

async fn fetch(State(db): State<Db>, id: NoteId) -> ApiResult<Json<Note>> {
    db.call(move |conn| store::notes::get(conn, id))
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}
