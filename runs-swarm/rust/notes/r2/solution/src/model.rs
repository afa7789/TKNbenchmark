//! The note type and validation of client input.

use std::collections::BTreeSet;

use serde::Serialize;
use serde_json::{Map, Value};

/// Maximum length of a title, in characters, after trimming.
pub const TITLE_MAX_CHARS: usize = 200;
/// Maximum length of a tag, in characters.
pub const TAG_MAX_CHARS: usize = 32;

/// A stored note, as returned to clients.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Note {
    pub id: i64,
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
}

/// The validated content of a note: the body of `POST /notes` and `PUT /notes/{id}`.
///
/// `title` is trimmed, `tags` are deduplicated and sorted ascending.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteInput {
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
}

/// Why a request body was rejected; answered with 400.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ValidationError {
    #[error("the request body must be a JSON object")]
    NotAnObject,
    #[error("title is required")]
    MissingTitle,
    #[error("title must be a string")]
    TitleNotString,
    #[error("title must be 1 to {TITLE_MAX_CHARS} characters long")]
    TitleLength,
    #[error("body must be a string")]
    BodyNotString,
    #[error("tags must be an array of strings")]
    TagsNotArray,
    #[error("invalid tag {0:?}: tags are 1 to {TAG_MAX_CHARS} characters from a-z, 0-9 and -")]
    InvalidTag(String),
}

impl NoteInput {
    /// Validates a parsed JSON request body. Unknown fields are ignored.
    pub fn from_json(value: Value) -> Result<Self, ValidationError> {
        let Value::Object(mut object) = value else {
            return Err(ValidationError::NotAnObject);
        };
        Ok(Self {
            title: parse_title(&mut object)?,
            body: parse_body(&mut object)?,
            tags: parse_tags(&mut object)?,
        })
    }
}

fn parse_title(object: &mut Map<String, Value>) -> Result<String, ValidationError> {
    let title = match object.remove("title") {
        None => return Err(ValidationError::MissingTitle),
        Some(Value::String(title)) => title,
        Some(_) => return Err(ValidationError::TitleNotString),
    };
    let trimmed = title.trim();
    if !(1..=TITLE_MAX_CHARS).contains(&trimmed.chars().count()) {
        return Err(ValidationError::TitleLength);
    }
    Ok(if trimmed.len() == title.len() {
        title
    } else {
        trimmed.to_owned()
    })
}

fn parse_body(object: &mut Map<String, Value>) -> Result<String, ValidationError> {
    match object.remove("body") {
        None => Ok(String::new()),
        Some(Value::String(body)) => Ok(body),
        Some(_) => Err(ValidationError::BodyNotString),
    }
}

fn parse_tags(object: &mut Map<String, Value>) -> Result<Vec<String>, ValidationError> {
    let items = match object.remove("tags") {
        None => return Ok(Vec::new()),
        Some(Value::Array(items)) => items,
        Some(_) => return Err(ValidationError::TagsNotArray),
    };
    let mut tags = BTreeSet::new();
    for item in items {
        let Value::String(tag) = item else {
            return Err(ValidationError::TagsNotArray);
        };
        if !is_valid_tag(&tag) {
            return Err(ValidationError::InvalidTag(tag));
        }
        tags.insert(tag);
    }
    Ok(tags.into_iter().collect())
}

/// Whether `tag` is 1–32 characters from `a-z`, `0-9` and `-`.
pub fn is_valid_tag(tag: &str) -> bool {
    (1..=TAG_MAX_CHARS).contains(&tag.len())
        && tag
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn input(value: Value) -> Result<NoteInput, ValidationError> {
        NoteInput::from_json(value)
    }

    #[test]
    fn applies_defaults() {
        assert_eq!(
            input(json!({"title": "t"})),
            Ok(NoteInput {
                title: "t".into(),
                body: String::new(),
                tags: vec![]
            })
        );
    }

    #[test]
    fn trims_title_and_normalizes_tags() {
        let note =
            input(json!({"title": "  hi  ", "body": " b ", "tags": ["z", "a-1", "z"], "extra": 1}))
                .unwrap();
        assert_eq!(note.title, "hi");
        assert_eq!(note.body, " b ");
        assert_eq!(note.tags, ["a-1", "z"]);
    }

    #[test]
    fn rejects_non_objects() {
        for value in [json!([]), json!("x"), json!(1), json!(null)] {
            assert_eq!(input(value), Err(ValidationError::NotAnObject));
        }
    }

    #[test]
    fn validates_title() {
        assert_eq!(input(json!({})), Err(ValidationError::MissingTitle));
        assert_eq!(
            input(json!({"title": null})),
            Err(ValidationError::TitleNotString)
        );
        assert_eq!(
            input(json!({"title": 5})),
            Err(ValidationError::TitleNotString)
        );
        assert_eq!(
            input(json!({"title": "   "})),
            Err(ValidationError::TitleLength)
        );
        assert_eq!(
            input(json!({"title": "x".repeat(201)})),
            Err(ValidationError::TitleLength)
        );
        assert!(input(json!({"title": "é".repeat(200)})).is_ok());
        assert!(input(json!({"title": format!(" {} ", "x".repeat(200))})).is_ok());
    }

    #[test]
    fn validates_body() {
        assert_eq!(
            input(json!({"title": "t", "body": 3})),
            Err(ValidationError::BodyNotString)
        );
        assert_eq!(
            input(json!({"title": "t", "body": null})),
            Err(ValidationError::BodyNotString)
        );
    }

    #[test]
    fn validates_tags() {
        assert_eq!(
            input(json!({"title": "t", "tags": "a"})),
            Err(ValidationError::TagsNotArray)
        );
        assert_eq!(
            input(json!({"title": "t", "tags": [1]})),
            Err(ValidationError::TagsNotArray)
        );
        for bad in ["", "Bad", "a b", "a_b", "é", &"a".repeat(33)] {
            assert_eq!(
                input(json!({"title": "t", "tags": [bad]})),
                Err(ValidationError::InvalidTag(bad.to_owned())),
            );
        }
        assert!(input(json!({"title": "t", "tags": ["a".repeat(32), "0-9"]})).is_ok());
    }
}
