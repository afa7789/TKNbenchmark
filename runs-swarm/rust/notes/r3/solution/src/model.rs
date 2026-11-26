//! The note model and validation of client input.

use serde::Serialize;
use serde_json::{Map, Value};

use crate::error::ApiError;

pub const TITLE_MAX_CHARS: usize = 200;
pub const TAG_MAX_CHARS: usize = 32;

/// A stored note, as returned by the API.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Note {
    pub id: i64,
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
}

/// A validated note payload, as accepted by `POST /notes` and `PUT /notes/{id}`.
///
/// `title` is trimmed, `tags` are deduplicated and sorted ascending.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteInput {
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
}

impl NoteInput {
    /// Parses and validates a raw JSON request body.
    pub fn from_json(bytes: &[u8]) -> Result<Self, ApiError> {
        let value: Value = serde_json::from_slice(bytes)
            .map_err(|err| ApiError::bad_request(format!("invalid JSON: {err}")))?;
        match value {
            Value::Object(object) => Self::from_object(&object),
            _ => Err(ApiError::bad_request("request body must be a JSON object")),
        }
    }

    /// Validates a JSON object. Unknown fields are ignored; omitted `body` and `tags` take their defaults.
    pub fn from_object(object: &Map<String, Value>) -> Result<Self, ApiError> {
        let title = match object.get("title") {
            Some(Value::String(title)) => validate_title(title)?,
            Some(_) => return Err(ApiError::bad_request("title must be a string")),
            None => return Err(ApiError::bad_request("title is required")),
        };
        let body = match object.get("body") {
            Some(Value::String(body)) => body.clone(),
            Some(_) => return Err(ApiError::bad_request("body must be a string")),
            None => String::new(),
        };
        let tags = match object.get("tags") {
            Some(Value::Array(items)) => validate_tags(items)?,
            Some(_) => return Err(ApiError::bad_request("tags must be an array of strings")),
            None => Vec::new(),
        };
        Ok(Self { title, body, tags })
    }
}

/// Trims a title and checks its length; returns the trimmed title.
pub fn validate_title(title: &str) -> Result<String, ApiError> {
    let title = title.trim();
    let len = title.chars().count();
    if len == 0 || len > TITLE_MAX_CHARS {
        return Err(ApiError::bad_request(format!(
            "title must be 1-{TITLE_MAX_CHARS} characters"
        )));
    }
    Ok(title.to_owned())
}

/// Whether `tag` is 1–32 characters from `a-z`, `0-9` and `-`.
pub fn is_valid_tag(tag: &str) -> bool {
    (1..=TAG_MAX_CHARS).contains(&tag.len())
        && tag
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

/// Validates a list of tags; returns them deduplicated and sorted ascending.
pub fn validate_tags(items: &[Value]) -> Result<Vec<String>, ApiError> {
    let mut tags = items
        .iter()
        .map(|item| match item {
            Value::String(tag) if is_valid_tag(tag) => Ok(tag.clone()),
            _ => Err(ApiError::bad_request(format!(
                "each tag must be 1-{TAG_MAX_CHARS} characters from a-z, 0-9 and -"
            ))),
        })
        .collect::<Result<Vec<_>, _>>()?;
    tags.sort_unstable();
    tags.dedup();
    Ok(tags)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(json: &str) -> Result<NoteInput, ApiError> {
        NoteInput::from_json(json.as_bytes())
    }

    #[test]
    fn applies_defaults() {
        let input = parse(r#"{"title":"first"}"#).unwrap();
        assert_eq!(
            input,
            NoteInput {
                title: "first".into(),
                body: String::new(),
                tags: vec![]
            }
        );
    }

    #[test]
    fn trims_title_and_normalizes_tags() {
        let input = parse(r#"{"title":"  t  ","body":"b","tags":["work","b-2","work"]}"#).unwrap();
        assert_eq!(input.title, "t");
        assert_eq!(input.body, "b");
        assert_eq!(input.tags, ["b-2", "work"]);
    }

    #[test]
    fn title_length_counts_characters() {
        assert!(parse(&format!(r#"{{"title":"{}"}}"#, "é".repeat(200))).is_ok());
        assert!(parse(&format!(r#"{{"title":"{}"}}"#, "a".repeat(201))).is_err());
    }

    #[test]
    fn rejects_invalid_input() {
        for body in [
            r#"{"title": "#,
            "[]",
            "null",
            "{}",
            r#"{"title":"   "}"#,
            r#"{"title":3}"#,
            r#"{"title":"x","body":3}"#,
            r#"{"title":"x","body":null}"#,
            r#"{"title":"x","tags":"a"}"#,
            r#"{"title":"x","tags":["Bad"]}"#,
            r#"{"title":"x","tags":[""]}"#,
            r#"{"title":"x","tags":[1]}"#,
        ] {
            assert!(
                matches!(parse(body), Err(ApiError::BadRequest(_))),
                "accepted {body}"
            );
        }
    }

    #[test]
    fn tag_rules() {
        assert!(is_valid_tag("a-1"));
        assert!(is_valid_tag(&"a".repeat(32)));
        assert!(!is_valid_tag(&"a".repeat(33)));
        assert!(!is_valid_tag(""));
        assert!(!is_valid_tag("a_b"));
        assert!(!is_valid_tag("ü"));
    }
}
