//! `GET /notes` with its query parameters.

use axum::extract::rejection::QueryRejection;
use axum::extract::{Query, State};
use axum::routing::get;
use axum::{Json, Router};
use serde::{Deserialize, Serialize};

use super::AppState;
use crate::error::ApiError;
use crate::model::Note;
use crate::store::list::{ListFilter, MAX_LIMIT};

pub fn router() -> Router<AppState> {
    Router::new().route("/notes", get(list_notes))
}

/// The raw query string of `GET /notes`. Values are kept as strings so that invalid numbers are reported
/// with our own messages; unknown parameters are ignored.
#[derive(Debug, Default, Deserialize)]
struct ListParams {
    tag: Option<String>,
    q: Option<String>,
    after: Option<String>,
    limit: Option<String>,
}

#[derive(Serialize)]
struct NoteList {
    notes: Vec<Note>,
}

async fn list_notes(
    State(state): State<AppState>,
    params: Result<Query<ListParams>, QueryRejection>,
) -> Result<Json<NoteList>, ApiError> {
    let Query(params) = params
        .map_err(|err| ApiError::bad_request(format!("invalid query: {}", err.body_text())))?;
    let filter = ListFilter::try_from(params)?;
    let notes = state.store.list_notes(filter).await?;
    Ok(Json(NoteList { notes }))
}

impl TryFrom<ListParams> for ListFilter {
    type Error = ApiError;

    fn try_from(params: ListParams) -> Result<Self, ApiError> {
        let after = params
            .after
            .map(|raw| {
                parse_integer(&raw).ok_or_else(|| ApiError::bad_request("after must be an integer"))
            })
            .transpose()?;
        let limit = params
            .limit
            .map(|raw| {
                parse_integer(&raw)
                    .and_then(|n| u32::try_from(n).ok())
                    .filter(|n| (1..=MAX_LIMIT).contains(n))
                    .ok_or_else(|| {
                        ApiError::bad_request(format!(
                            "limit must be an integer from 1 to {MAX_LIMIT}"
                        ))
                    })
            })
            .transpose()?
            .unwrap_or(MAX_LIMIT);
        Ok(Self {
            tag: params.tag,
            text: params.q,
            after,
            limit,
        })
    }
}

/// Parses a decimal integer with an optional leading `-`; rejects signs like `+`, spaces and overflow.
fn parse_integer(raw: &str) -> Option<i64> {
    let digits = raw.strip_prefix('-').unwrap_or(raw);
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    raw.parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn params(after: Option<&str>, limit: Option<&str>) -> ListParams {
        ListParams {
            after: after.map(Into::into),
            limit: limit.map(Into::into),
            ..ListParams::default()
        }
    }

    #[test]
    fn integers() {
        assert_eq!(parse_integer("0"), Some(0));
        assert_eq!(parse_integer("42"), Some(42));
        assert_eq!(parse_integer("-3"), Some(-3));
        for raw in [
            "",
            "-",
            "+1",
            " 1",
            "1 ",
            "1.0",
            "1e2",
            "abc",
            "99999999999999999999",
        ] {
            assert_eq!(parse_integer(raw), None, "{raw:?}");
        }
    }

    #[test]
    fn defaults() {
        let filter = ListFilter::try_from(ListParams::default()).unwrap();
        assert_eq!(filter, ListFilter::default());
        assert_eq!(filter.limit, MAX_LIMIT);
    }

    #[test]
    fn valid_paging() {
        let filter = ListFilter::try_from(params(Some("-1"), Some("1"))).unwrap();
        assert_eq!((filter.after, filter.limit), (Some(-1), 1));
        let filter = ListFilter::try_from(params(Some("0"), Some("100"))).unwrap();
        assert_eq!((filter.after, filter.limit), (Some(0), 100));
    }

    #[test]
    fn invalid_paging() {
        for (after, limit) in [
            (None, Some("0")),
            (None, Some("101")),
            (None, Some("-1")),
            (None, Some("")),
            (None, Some("ten")),
            (None, Some("1.5")),
            (None, Some("4294967297")),
            (Some(""), None),
            (Some("x"), None),
            (Some("1.5"), None),
        ] {
            assert!(
                matches!(
                    ListFilter::try_from(params(after, limit)),
                    Err(ApiError::BadRequest(_))
                ),
                "after={after:?} limit={limit:?}"
            );
        }
    }
}
