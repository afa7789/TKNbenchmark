//! Note types and input validation.

use serde::Serialize;
use serde_json::Value;

pub const MAX_TITLE_CHARS: usize = 200;
pub const MAX_TAG_CHARS: usize = 32;

/// A stored note.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Note {
    pub id: i64,
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
}

/// Validated contents of a note, as supplied by a create or update request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteInput {
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
}

/// Why a request body was rejected.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ValidationError {
    #[error("request body is not valid JSON")]
    InvalidJson,
    #[error("request body must be a JSON object")]
    NotAnObject,
    #[error("title is required")]
    MissingTitle,
    #[error("title must be a string")]
    TitleNotString,
    #[error("title must be 1-{MAX_TITLE_CHARS} characters")]
    TitleLength,
    #[error("body must be a string")]
    BodyNotString,
    #[error("tags must be an array of strings")]
    TagsNotArray,
    #[error("each tag must be 1-{MAX_TAG_CHARS} characters from a-z, 0-9 and -")]
    InvalidTag,
}

impl NoteInput {
    /// Parses and validates a raw JSON request body.
    pub fn from_json(bytes: &[u8]) -> Result<Self, ValidationError> {
        let value: Value =
            serde_json::from_slice(bytes).map_err(|_| ValidationError::InvalidJson)?;
        let Value::Object(mut obj) = value else {
            return Err(ValidationError::NotAnObject);
        };

        let title = match obj.remove("title") {
            None => return Err(ValidationError::MissingTitle),
            Some(Value::String(s)) => normalize_title(&s)?,
            Some(_) => return Err(ValidationError::TitleNotString),
        };

        let body = match obj.remove("body") {
            None => String::new(),
            Some(Value::String(s)) => s,
            Some(_) => return Err(ValidationError::BodyNotString),
        };

        let tags = match obj.remove("tags") {
            None => Vec::new(),
            Some(Value::Array(items)) => normalize_tags(items)?,
            Some(_) => return Err(ValidationError::TagsNotArray),
        };

        Ok(Self { title, body, tags })
    }
}

fn normalize_title(raw: &str) -> Result<String, ValidationError> {
    let title = raw.trim();
    let len = title.chars().count();
    if (1..=MAX_TITLE_CHARS).contains(&len) {
        Ok(title.to_owned())
    } else {
        Err(ValidationError::TitleLength)
    }
}

fn normalize_tags(items: Vec<Value>) -> Result<Vec<String>, ValidationError> {
    let mut tags = items
        .into_iter()
        .map(|item| match item {
            Value::String(tag) if is_valid_tag(&tag) => Ok(tag),
            Value::String(_) => Err(ValidationError::InvalidTag),
            _ => Err(ValidationError::TagsNotArray),
        })
        .collect::<Result<Vec<_>, _>>()?;
    tags.sort_unstable();
    tags.dedup();
    Ok(tags)
}

/// Whether `tag` is 1-32 characters from `a-z`, `0-9` and `-`.
pub fn is_valid_tag(tag: &str) -> bool {
    (1..=MAX_TAG_CHARS).contains(&tag.len())
        && tag
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse(s: &str) -> Result<NoteInput, ValidationError> {
        NoteInput::from_json(s.as_bytes())
    }

    #[test]
    fn defaults_and_normalization() {
        let n = parse(r#"{"title":"  hi  ","tags":["b","a","b"]}"#).unwrap();
        assert_eq!(n.title, "hi");
        assert_eq!(n.body, "");
        assert_eq!(n.tags, ["a", "b"]);
    }

    #[test]
    fn rejects_bad_shapes() {
        assert_eq!(parse("{"), Err(ValidationError::InvalidJson));
        assert_eq!(parse("[]"), Err(ValidationError::NotAnObject));
        assert_eq!(parse("{}"), Err(ValidationError::MissingTitle));
        assert_eq!(parse(r#"{"title":1}"#), Err(ValidationError::TitleNotString));
        assert_eq!(parse(r#"{"title":"   "}"#), Err(ValidationError::TitleLength));
        assert_eq!(parse(r#"{"title":"x","body":null}"#), Err(ValidationError::BodyNotString));
        assert_eq!(parse(r#"{"title":"x","tags":"a"}"#), Err(ValidationError::TagsNotArray));
        assert_eq!(parse(r#"{"title":"x","tags":[1]}"#), Err(ValidationError::TagsNotArray));
        assert_eq!(parse(r#"{"title":"x","tags":["Bad"]}"#), Err(ValidationError::InvalidTag));
        assert_eq!(parse(r#"{"title":"x","tags":[""]}"#), Err(ValidationError::InvalidTag));
    }

    #[test]
    fn title_length_counts_characters() {
        let ok = format!(r#"{{"title":"{}"}}"#, "é".repeat(200));
        assert!(parse(&ok).is_ok());
        let long = format!(r#"{{"title":"{}"}}"#, "a".repeat(201));
        assert_eq!(parse(&long), Err(ValidationError::TitleLength));
    }

    #[test]
    fn tag_rules() {
        assert!(is_valid_tag("a-1"));
        assert!(is_valid_tag(&"a".repeat(32)));
        assert!(!is_valid_tag(&"a".repeat(33)));
        assert!(!is_valid_tag("a_b"));
        assert!(!is_valid_tag("é"));
    }
}
