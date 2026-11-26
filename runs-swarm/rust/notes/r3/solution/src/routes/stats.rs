//! `GET /stats` and `GET /tags`.

use std::collections::BTreeMap;

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use super::AppState;
use crate::error::ApiError;
use crate::store::stats::TagCount;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/stats", get(stats))
        .route("/tags", get(tags))
}

#[derive(Serialize)]
struct StatsResponse {
    notes: i64,
    tags: BTreeMap<String, i64>,
}

#[derive(Serialize)]
struct TagsResponse {
    tags: Vec<TagCount>,
}

async fn stats(State(state): State<AppState>) -> Result<Json<StatsResponse>, ApiError> {
    let stats = state.store.stats().await?;
    Ok(Json(StatsResponse {
        notes: stats.notes,
        tags: stats.tags.into_iter().map(|t| (t.tag, t.count)).collect(),
    }))
}

async fn tags(State(state): State<AppState>) -> Result<Json<TagsResponse>, ApiError> {
    let tags = state.store.tag_counts().await?;
    Ok(Json(TagsResponse { tags }))
}
