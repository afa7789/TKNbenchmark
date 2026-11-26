//! `GET /stats` and `GET /tags`.

use std::collections::BTreeMap;

use axum::extract::State;
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::error::ApiResult;
use crate::store::stats::TagCount;
use crate::store::{self, Db};

pub fn routes() -> Router<Db> {
    Router::new()
        .route("/stats", get(stats))
        .route("/tags", get(tags))
}

/// `{"notes": <count>, "tags": {"<tag>": <count>, ...}}`, tags in ascending order.
#[derive(Debug, Serialize)]
struct StatsResponse {
    notes: i64,
    tags: BTreeMap<String, i64>,
}

/// `{"tags": [{"tag": "<tag>", "count": <n>}, ...]}`, by count descending, then tag ascending.
#[derive(Debug, Serialize)]
struct TagsResponse {
    tags: Vec<TagCount>,
}

async fn stats(State(db): State<Db>) -> ApiResult<Json<StatsResponse>> {
    let stats = db.call(store::stats::stats).await?;
    Ok(Json(StatsResponse {
        notes: stats.notes,
        tags: stats
            .tags
            .into_iter()
            .map(|TagCount { tag, count }| (tag, count))
            .collect(),
    }))
}

async fn tags(State(db): State<Db>) -> ApiResult<Json<TagsResponse>> {
    let tags = db.call(|conn| store::stats::tag_counts(conn)).await?;
    Ok(Json(TagsResponse { tags }))
}
