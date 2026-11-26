//! `GET /notes` with its `tag`, `q`, `after` and `limit` query parameters.
//!
//! Invalid `after` or `limit` values are answered with [`ApiError::BadRequest`]. Unknown
//! parameters are ignored; when a parameter is repeated, its first value is used.

use std::num::IntErrorKind;

use axum::extract::rejection::QueryRejection;
use axum::extract::{Query, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::AppState;
use crate::db;
use crate::db::list::ListFilter;
use crate::error::{ApiError, ApiResult};
use crate::model::Note;

/// Largest accepted `limit`, also the default.
const MAX_LIMIT: u32 = 100;

pub fn routes() -> Router<AppState> {
    Router::new().route("/notes", get(list))
}

#[derive(Debug, Serialize)]
struct NoteList {
    notes: Vec<Note>,
}

async fn list(
    State(state): State<AppState>,
    query: Result<Query<Vec<(String, String)>>, QueryRejection>,
) -> ApiResult<Json<NoteList>> {
    let Query(pairs) = query.map_err(|err| ApiError::bad_request(err.body_text()))?;
    let filter = parse_filter(pairs)?;
    let notes = state
        .db
        .run(move |conn| db::list::list(conn, &filter))
        .await?;
    Ok(Json(NoteList { notes }))
}

/// Builds the filter from decoded query parameters.
fn parse_filter(pairs: Vec<(String, String)>) -> ApiResult<ListFilter> {
    let mut tag = None;
    let mut text = None;
    let mut after = None;
    let mut limit = None;
    for (key, value) in pairs {
        let slot = match key.as_str() {
            "tag" => &mut tag,
            "q" => &mut text,
            "after" => &mut after,
            "limit" => &mut limit,
            _ => continue,
        };
        slot.get_or_insert(value);
    }
    Ok(ListFilter {
        tag,
        text,
        after: after.as_deref().map(parse_after).transpose()?,
        limit: limit.as_deref().map_or(Ok(MAX_LIMIT), parse_limit)?,
    })
}

/// `after`: a decimal integer, optionally negative.
///
/// Integers beyond the id range are valid and saturate: no id is greater than a huge `after`.
fn parse_after(value: &str) -> ApiResult<i64> {
    let invalid = || ApiError::bad_request("after must be an integer");
    let digits = value.strip_prefix('-').unwrap_or(value);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return Err(invalid());
    }
    match value.parse::<i64>() {
        Ok(after) => Ok(after),
        Err(err) => match err.kind() {
            IntErrorKind::PosOverflow => Ok(i64::MAX),
            IntErrorKind::NegOverflow => Ok(i64::MIN),
            _ => Err(invalid()),
        },
    }
}

/// `limit`: a decimal integer from 1 to [`MAX_LIMIT`].
fn parse_limit(value: &str) -> ApiResult<u32> {
    let valid = !value.is_empty() && value.bytes().all(|b| b.is_ascii_digit());
    value
        .parse::<u32>()
        .ok()
        .filter(|limit| valid && (1..=MAX_LIMIT).contains(limit))
        .ok_or_else(|| {
            ApiError::bad_request(format!("limit must be an integer from 1 to {MAX_LIMIT}"))
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pairs(items: &[(&str, &str)]) -> Vec<(String, String)> {
        items
            .iter()
            .map(|&(k, v)| (k.to_owned(), v.to_owned()))
            .collect()
    }

    #[test]
    fn defaults() {
        assert_eq!(parse_filter(vec![]).unwrap(), ListFilter::default());
    }

    #[test]
    fn reads_all_parameters_and_ignores_unknown_ones() {
        let filter = parse_filter(pairs(&[
            ("tag", "work"),
            ("q", "Hi there"),
            ("after", "3"),
            ("limit", "7"),
            ("other", "x"),
            ("tag", "ignored"),
        ]))
        .unwrap();
        assert_eq!(
            filter,
            ListFilter {
                tag: Some("work".into()),
                text: Some("Hi there".into()),
                after: Some(3),
                limit: 7,
            }
        );
    }

    #[test]
    fn validates_limit() {
        assert_eq!(parse_limit("1").unwrap(), 1);
        assert_eq!(parse_limit("100").unwrap(), 100);
        assert_eq!(parse_limit("007").unwrap(), 7);
        for bad in [
            "",
            "0",
            "101",
            "-1",
            "+5",
            " 5",
            "1.0",
            "abc",
            "99999999999",
        ] {
            assert!(parse_limit(bad).is_err(), "{bad:?}");
        }
    }

    #[test]
    fn validates_after() {
        assert_eq!(parse_after("0").unwrap(), 0);
        assert_eq!(parse_after("42").unwrap(), 42);
        assert_eq!(parse_after("-3").unwrap(), -3);
        assert_eq!(parse_after("99999999999999999999").unwrap(), i64::MAX);
        assert_eq!(parse_after("-99999999999999999999").unwrap(), i64::MIN);
        for bad in ["", "-", "+1", "1.5", "abc", " 1", "1e3", "--1"] {
            assert!(parse_after(bad).is_err(), "{bad:?}");
        }
    }
}
