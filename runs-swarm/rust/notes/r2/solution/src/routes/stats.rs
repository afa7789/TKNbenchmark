//! `GET /stats` and `GET /tags`.

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::AppState;
use crate::db;
use crate::db::stats::{Stats, TagCount};
use crate::error::ApiResult;

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/stats", get(stats))
        .route("/tags", get(tags))
}

#[derive(Serialize)]
struct TagList {
    tags: Vec<TagCount>,
}

async fn stats(State(state): State<AppState>) -> ApiResult<Json<Stats>> {
    let stats = state.db.run(db::stats::stats).await?;
    Ok(Json(stats))
}

async fn tags(State(state): State<AppState>) -> ApiResult<Json<TagList>> {
    let tags = state.db.run(|conn| db::stats::tag_counts(conn)).await?;
    Ok(Json(TagList { tags }))
}
