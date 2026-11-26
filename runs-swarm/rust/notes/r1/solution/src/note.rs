//! The note domain model and the validation rules for client input.
//!
//! Everything here is independent of HTTP and SQL so that it can be shared by every endpoint
//! (`POST /notes` and `PUT /notes/{id}` accept the same body) and unit-tested in isolation.

use std::collections::BTreeSet;
use std::fmt;

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
    /// Unique and sorted ascending.
    pub tags: Vec<String>,
}

/// The identifier of a note: always a positive integer.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct NoteId(i64);

impl NoteId {
    /// Parses a path segment such as `"42"`. Only plain decimal digits denoting a positive `i64`
    /// are accepted (no sign, no whitespace).
    pub fn parse(s: &str) -> Option<Self> {
        if s.is_empty() || !s.bytes().all(|b| b.is_ascii_digit()) {
            return None;
        }
        s.parse::<i64>().ok().and_then(Self::new)
    }

    /// Wraps a raw id, returning `None` unless it is positive.
    pub fn new(id: i64) -> Option<Self> {
        (id > 0).then_some(Self(id))
    }

    pub fn get(self) -> i64 {
        self.0
    }
}

impl fmt::Display for NoteId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.0.fmt(f)
    }
}

/// Why a request body was rejected. The `Display` text is sent to the client.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum InvalidNote {
    #[error("request body is not valid JSON")]
    NotJson,
    #[error("request body must be a JSON object")]
    NotObject,
    #[error("title is required")]
    MissingTitle,
    #[error("title must be a string of 1 to {TITLE_MAX_CHARS} characters")]
    InvalidTitle,
    #[error("body must be a string")]
    InvalidBody,
    #[error("tags must be an array of strings")]
    TagsNotArray,
    #[error("each tag must be 1 to {TAG_MAX_CHARS} characters from a-z, 0-9 and -")]
    InvalidTag,
}

/// A validated, normalized note body (`{title, body?, tags?}`), ready to be stored.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteInput {
    /// Trimmed of leading and trailing spaces.
    pub title: String,
    pub body: String,
    /// Deduplicated and sorted ascending.
    pub tags: Vec<String>,
}

impl NoteInput {
    /// Parses and validates a raw JSON request body. Unknown fields are ignored.
    pub fn from_json(bytes: &[u8]) -> Result<Self, InvalidNote> {
        match serde_json::from_slice::<Value>(bytes).map_err(|_| InvalidNote::NotJson)? {
            Value::Object(map) => Self::from_object(&map),
            _ => Err(InvalidNote::NotObject),
        }
    }

    fn from_object(map: &Map<String, Value>) -> Result<Self, InvalidNote> {
        let title = match map.get("title") {
            None => return Err(InvalidNote::MissingTitle),
            Some(Value::String(s)) => normalize_title(s)?,
            Some(_) => return Err(InvalidNote::InvalidTitle),
        };
        let body = match map.get("body") {
            None => String::new(),
            Some(Value::String(s)) => s.clone(),
            Some(_) => return Err(InvalidNote::InvalidBody),
        };
        let tags = match map.get("tags") {
            None => Vec::new(),
            Some(Value::Array(items)) => normalize_tags(items)?,
            Some(_) => return Err(InvalidNote::TagsNotArray),
        };
        Ok(Self { title, body, tags })
    }
}

fn normalize_title(raw: &str) -> Result<String, InvalidNote> {
    let title = raw.trim_matches(' ');
    let len = title.chars().count();
    if (1..=TITLE_MAX_CHARS).contains(&len) {
        Ok(title.to_owned())
    } else {
        Err(InvalidNote::InvalidTitle)
    }
}

fn normalize_tags(items: &[Value]) -> Result<Vec<String>, InvalidNote> {
    let mut tags = BTreeSet::new();
    for item in items {
        let Value::String(tag) = item else {
            return Err(InvalidNote::TagsNotArray);
        };
        if !is_valid_tag(tag) {
            return Err(InvalidNote::InvalidTag);
        }
        tags.insert(tag.as_str());
    }
    Ok(tags.into_iter().map(str::to_owned).collect())
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

    fn parse(json: &str) -> Result<NoteInput, InvalidNote> {
        NoteInput::from_json(json.as_bytes())
    }

    #[test]
    fn minimal_note_gets_defaults() {
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
    fn title_is_trimmed_and_tags_are_normalized() {
        let input =
            parse(r#"{"title":"  second  ","body":"text","tags":["work","b-2","work"]}"#).unwrap();
        assert_eq!(input.title, "second");
        assert_eq!(input.body, "text");
        assert_eq!(input.tags, ["b-2", "work"]);
    }

    #[test]
    fn rejects_malformed_bodies() {
        assert_eq!(parse(r#"{"title": "#), Err(InvalidNote::NotJson));
        assert_eq!(parse(""), Err(InvalidNote::NotJson));
        assert_eq!(parse("[]"), Err(InvalidNote::NotObject));
        assert_eq!(parse(r#""title""#), Err(InvalidNote::NotObject));
    }

    #[test]
    fn validates_title() {
        assert_eq!(parse("{}"), Err(InvalidNote::MissingTitle));
        assert_eq!(parse(r#"{"title":"   "}"#), Err(InvalidNote::InvalidTitle));
        assert_eq!(parse(r#"{"title":""}"#), Err(InvalidNote::InvalidTitle));
        assert_eq!(parse(r#"{"title":5}"#), Err(InvalidNote::InvalidTitle));
        assert_eq!(parse(r#"{"title":null}"#), Err(InvalidNote::InvalidTitle));

        let max = "é".repeat(TITLE_MAX_CHARS);
        assert!(parse(&format!(r#"{{"title":" {max} "}}"#)).is_ok());
        let too_long = "a".repeat(TITLE_MAX_CHARS + 1);
        assert_eq!(
            parse(&format!(r#"{{"title":"{too_long}"}}"#)),
            Err(InvalidNote::InvalidTitle)
        );
    }

    #[test]
    fn validates_body() {
        assert_eq!(
            parse(r#"{"title":"x","body":3}"#),
            Err(InvalidNote::InvalidBody)
        );
        assert_eq!(
            parse(r#"{"title":"x","body":null}"#),
            Err(InvalidNote::InvalidBody)
        );
    }

    #[test]
    fn validates_tags() {
        assert_eq!(
            parse(r#"{"title":"x","tags":"a"}"#),
            Err(InvalidNote::TagsNotArray)
        );
        assert_eq!(
            parse(r#"{"title":"x","tags":[1]}"#),
            Err(InvalidNote::TagsNotArray)
        );
        assert_eq!(
            parse(r#"{"title":"x","tags":["Bad"]}"#),
            Err(InvalidNote::InvalidTag)
        );
        assert_eq!(
            parse(r#"{"title":"x","tags":[""]}"#),
            Err(InvalidNote::InvalidTag)
        );
        assert_eq!(
            parse(r#"{"title":"x","tags":["a b"]}"#),
            Err(InvalidNote::InvalidTag)
        );
        assert!(is_valid_tag(&"a".repeat(TAG_MAX_CHARS)));
        assert!(!is_valid_tag(&"a".repeat(TAG_MAX_CHARS + 1)));
        assert!(is_valid_tag("a-0"));
    }

    #[test]
    fn parses_note_ids() {
        assert_eq!(NoteId::parse("7").map(NoteId::get), Some(7));
        assert_eq!(NoteId::parse("007").map(NoteId::get), Some(7));
        for bad in [
            "",
            "0",
            "-1",
            "+1",
            "abc",
            " 1",
            "1.0",
            "99999999999999999999",
        ] {
            assert_eq!(NoteId::parse(bad), None, "{bad:?}");
        }
    }
}
