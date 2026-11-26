//! Note data types and validation of client input.

use serde::Serialize;
use serde_json::{Map, Value};

pub const MAX_TITLE_CHARS: usize = 200;
pub const MAX_TAG_CHARS: usize = 32;
pub const MAX_LIMIT: i64 = 100;

/// A stored note as returned to clients.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Note {
    pub id: i64,
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
}

/// Validated content of a note, as accepted by create and update.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteInput {
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
}

/// Filters for listing notes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ListQuery {
    pub tag: Option<String>,
    pub q: Option<String>,
    pub after: Option<i64>,
    pub limit: i64,
}

impl Default for ListQuery {
    fn default() -> Self {
        Self { tag: None, q: None, after: None, limit: MAX_LIMIT }
    }
}

/// A client error with a human-readable message.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationError(pub String);

impl std::fmt::Display for ValidationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for ValidationError {}

fn invalid(msg: impl Into<String>) -> ValidationError {
    ValidationError(msg.into())
}

pub fn is_valid_tag(tag: &str) -> bool {
    (1..=MAX_TAG_CHARS).contains(&tag.len())
        && tag.bytes().all(|b| matches!(b, b'a'..=b'z' | b'0'..=b'9' | b'-'))
}

impl NoteInput {
    /// Parses and validates a raw request body.
    pub fn from_json(raw: &[u8]) -> Result<Self, ValidationError> {
        let value: Value =
            serde_json::from_slice(raw).map_err(|e| invalid(format!("invalid JSON: {e}")))?;
        match value {
            Value::Object(map) => Self::from_object(&map),
            _ => Err(invalid("request body must be a JSON object")),
        }
    }

    fn from_object(map: &Map<String, Value>) -> Result<Self, ValidationError> {
        let title = match map.get("title") {
            None => return Err(invalid("title is required")),
            Some(Value::String(s)) => s.trim_matches(' ').to_owned(),
            Some(_) => return Err(invalid("title must be a string")),
        };
        let len = title.chars().count();
        if len == 0 || len > MAX_TITLE_CHARS {
            return Err(invalid(format!(
                "title must be 1-{MAX_TITLE_CHARS} characters"
            )));
        }

        let body = match map.get("body") {
            None => String::new(),
            Some(Value::String(s)) => s.clone(),
            Some(_) => return Err(invalid("body must be a string")),
        };

        let tags = match map.get("tags") {
            None => Vec::new(),
            Some(Value::Array(items)) => {
                let mut tags = items
                    .iter()
                    .map(|item| match item {
                        Value::String(s) if is_valid_tag(s) => Ok(s.clone()),
                        _ => Err(invalid(format!(
                            "each tag must be 1-{MAX_TAG_CHARS} characters from a-z, 0-9 and -"
                        ))),
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                tags.sort_unstable();
                tags.dedup();
                tags
            }
            Some(_) => return Err(invalid("tags must be an array of strings")),
        };

        Ok(Self { title, body, tags })
    }
}

impl ListQuery {
    /// Parses a URL query string (without the leading `?`).
    pub fn from_query_string(query: &str) -> Result<Self, ValidationError> {
        let mut out = Self::default();
        for (key, value) in form_urlencoded::parse(query.as_bytes()) {
            match key.as_ref() {
                "tag" => out.tag = Some(value.into_owned()),
                "q" => out.q = Some(value.into_owned()),
                "after" => {
                    let after = value
                        .parse::<i64>()
                        .map_err(|_| invalid("after must be an integer"))?;
                    out.after = Some(after);
                }
                "limit" => {
                    out.limit = value
                        .parse::<i64>()
                        .ok()
                        .filter(|n| (1..=MAX_LIMIT).contains(n))
                        .ok_or_else(|| {
                            invalid(format!("limit must be an integer from 1 to {MAX_LIMIT}"))
                        })?;
                }
                _ => {}
            }
        }
        Ok(out)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(s: &str) -> Result<NoteInput, ValidationError> {
        NoteInput::from_json(s.as_bytes())
    }

    #[test]
    fn defaults_and_normalisation() {
        let n = parse(r#"{"title":"  hi  ","tags":["b","a","b"]}"#).unwrap();
        assert_eq!(n.title, "hi");
        assert_eq!(n.body, "");
        assert_eq!(n.tags, ["a", "b"]);
    }

    #[test]
    fn rejects_bad_input() {
        for body in [
            "",
            "{",
            "[]",
            "null",
            "{}",
            r#"{"title":5}"#,
            r#"{"title":"   "}"#,
            r#"{"title":"x","body":null}"#,
            r#"{"title":"x","body":3}"#,
            r#"{"title":"x","tags":"a"}"#,
            r#"{"title":"x","tags":[1]}"#,
            r#"{"title":"x","tags":[""]}"#,
            r#"{"title":"x","tags":["A"]}"#,
            r#"{"title":"x","tags":["a_b"]}"#,
        ] {
            assert!(parse(body).is_err(), "{body} should be rejected");
        }
    }

    #[test]
    fn title_length_counts_characters() {
        let ok = format!(r#"{{"title":"{}"}}"#, "é".repeat(200));
        assert!(parse(&ok).is_ok());
        let long = format!(r#"{{"title":"{}"}}"#, "a".repeat(201));
        assert!(parse(&long).is_err());
    }

    #[test]
    fn tag_length() {
        assert!(is_valid_tag(&"a".repeat(32)));
        assert!(!is_valid_tag(&"a".repeat(33)));
    }

    #[test]
    fn list_query() {
        let q = ListQuery::from_query_string("tag=x&q=a%20b&after=3&limit=5").unwrap();
        assert_eq!(
            q,
            ListQuery { tag: Some("x".into()), q: Some("a b".into()), after: Some(3), limit: 5 }
        );
        assert_eq!(ListQuery::from_query_string("").unwrap(), ListQuery::default());
        for bad in ["limit=0", "limit=101", "limit=x", "limit=", "after=x", "after=1.5"] {
            assert!(ListQuery::from_query_string(bad).is_err(), "{bad}");
        }
    }
}
