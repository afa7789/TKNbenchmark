//! `GET /notes` with the `tag`, `q`, `after` and `limit` query parameters.

use axum::extract::{Query, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::Serialize;

use crate::error::{ApiError, ApiResult};
use crate::note::Note;
use crate::store::list::ListFilter;
use crate::store::{self, Db};

/// Largest accepted (and default) `limit`.
pub const MAX_LIMIT: u32 = 100;

pub fn routes() -> Router<Db> {
    Router::new().route("/notes", get(list))
}

#[derive(Serialize)]
struct NoteList {
    notes: Vec<Note>,
}

async fn list(
    State(db): State<Db>,
    query: Result<Query<Vec<(String, String)>>, axum::extract::rejection::QueryRejection>,
) -> ApiResult<Json<NoteList>> {
    let Query(pairs) = query.map_err(|rejection| ApiError::bad_request(rejection.body_text()))?;
    let filter = parse_filter(pairs)?;
    let notes = db
        .call(move |conn| store::list::list(conn, &filter))
        .await?;
    Ok(Json(NoteList { notes }))
}

/// Builds a [`ListFilter`] from decoded query pairs. Unknown parameters are ignored; when a
/// parameter is repeated, the last value wins.
fn parse_filter(pairs: Vec<(String, String)>) -> ApiResult<ListFilter> {
    let mut filter = ListFilter {
        tag: None,
        q: None,
        after: None,
        limit: MAX_LIMIT,
    };
    for (key, value) in pairs {
        match key.as_str() {
            "tag" => filter.tag = Some(value),
            "q" => filter.q = Some(value),
            "after" => {
                filter.after = Some(
                    parse_after(&value)
                        .ok_or_else(|| ApiError::bad_request("after must be an integer"))?,
                );
            }
            "limit" => {
                filter.limit = parse_limit(&value).ok_or_else(|| {
                    ApiError::bad_request(format!("limit must be an integer from 1 to {MAX_LIMIT}"))
                })?;
            }
            _ => {}
        }
    }
    Ok(filter)
}

/// A decimal integer with an optional leading `-` (no `+`, no whitespace).
fn parse_after(s: &str) -> Option<i64> {
    let digits = s.strip_prefix('-').unwrap_or(s);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse().ok()
}

/// Plain decimal digits denoting an integer in `1..=MAX_LIMIT`.
fn parse_limit(s: &str) -> Option<u32> {
    if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    s.parse().ok().filter(|n| (1..=MAX_LIMIT).contains(n))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn pairs(items: &[(&str, &str)]) -> Vec<(String, String)> {
        items
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn defaults() {
        let filter = parse_filter(vec![]).unwrap();
        assert_eq!(
            filter,
            ListFilter {
                tag: None,
                q: None,
                after: None,
                limit: MAX_LIMIT
            }
        );
    }

    #[test]
    fn reads_every_parameter() {
        let filter = parse_filter(pairs(&[
            ("tag", "work"),
            ("q", "Hi there"),
            ("after", "3"),
            ("limit", "7"),
            ("other", "ignored"),
        ]))
        .unwrap();
        assert_eq!(
            filter,
            ListFilter {
                tag: Some("work".into()),
                q: Some("Hi there".into()),
                after: Some(3),
                limit: 7
            }
        );
    }

    #[test]
    fn parses_limit() {
        assert_eq!(parse_limit("1"), Some(1));
        assert_eq!(parse_limit("100"), Some(100));
        assert_eq!(parse_limit("010"), Some(10));
        for bad in [
            "",
            "0",
            "101",
            "-1",
            "+5",
            "1.5",
            "abc",
            " 5",
            "99999999999",
        ] {
            assert_eq!(parse_limit(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn parses_after() {
        assert_eq!(parse_after("0"), Some(0));
        assert_eq!(parse_after("42"), Some(42));
        assert_eq!(parse_after("-3"), Some(-3));
        for bad in ["", "-", "+1", "1.0", "abc", " 1", "99999999999999999999"] {
            assert_eq!(parse_after(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn rejects_invalid_numbers() {
        assert!(parse_filter(pairs(&[("limit", "0")])).is_err());
        assert!(parse_filter(pairs(&[("after", "x")])).is_err());
    }
}
