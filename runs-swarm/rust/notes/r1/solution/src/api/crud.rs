//! `PUT /notes/{id}` and `DELETE /notes/{id}`.

use axum::extract::State;
use axum::http::StatusCode;
use axum::routing::put;
use axum::{Json, Router};

use crate::error::{ApiError, ApiResult};
use crate::note::{Note, NoteId, NoteInput};
use crate::store::{self, Db};

pub fn routes() -> Router<Db> {
    Router::new().route("/notes/{id}", put(replace).delete(remove))
}

/// Full replacement: an omitted `body` or `tags` becomes `""` or `[]`.
async fn replace(State(db): State<Db>, id: NoteId, input: NoteInput) -> ApiResult<Json<Note>> {
    db.call(move |conn| store::crud::update(conn, id, &input))
        .await?
        .map(Json)
        .ok_or(ApiError::NotFound)
}

async fn remove(State(db): State<Db>, id: NoteId) -> ApiResult<StatusCode> {
    if db.call(move |conn| store::crud::delete(conn, id)).await? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError::NotFound)
    }
}
