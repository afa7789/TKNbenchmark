//! Note data types and validation of client input.

use serde::Serialize;
use serde_json::Value;

pub const TITLE_MAX_CHARS: usize = 200;
pub const TAG_MAX_CHARS: usize = 32;

/// A stored note as returned to clients.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Note {
    pub id: i64,
    pub title: String,
    pub body: String,
    pub tags: Vec<String>,
}

/// Validated contents of a note, as supplied by a create or replace request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteInput {
    pub title: String,
    pub body: String,
    /// Deduplicated and sorted ascending.
    pub tags: Vec<String>,
}

impl NoteInput {
    /// Parses and validates a raw request body.
    pub fn from_json(bytes: &[u8]) -> Result<Self, String> {
        let value: Value =
            serde_json::from_slice(bytes).map_err(|e| format!("invalid JSON: {e}"))?;
        let Value::Object(mut obj) = value else {
            return Err("request body must be a JSON object".into());
        };

        let title = match obj.remove("title") {
            Some(Value::String(s)) => s.trim().to_owned(),
            Some(_) => return Err("title must be a string".into()),
            None => return Err("title is required".into()),
        };
        let title_len = title.chars().count();
        if title_len == 0 || title_len > TITLE_MAX_CHARS {
            return Err(format!(
                "title must be 1-{TITLE_MAX_CHARS} characters after trimming"
            ));
        }

        let body = match obj.remove("body") {
            None => String::new(),
            Some(Value::String(s)) => s,
            Some(_) => return Err("body must be a string".into()),
        };

        let mut tags = match obj.remove("tags") {
            None => Vec::new(),
            Some(Value::Array(items)) => items
                .into_iter()
                .map(|item| match item {
                    Value::String(tag) if is_valid_tag(&tag) => Ok(tag),
                    _ => Err(format!(
                        "each tag must be 1-{TAG_MAX_CHARS} characters from a-z, 0-9 and -"
                    )),
                })
                .collect::<Result<Vec<_>, _>>()?,
            Some(_) => return Err("tags must be an array of strings".into()),
        };
        tags.sort_unstable();
        tags.dedup();

        Ok(Self { title, body, tags })
    }
}

pub fn is_valid_tag(tag: &str) -> bool {
    (1..=TAG_MAX_CHARS).contains(&tag.len())
        && tag
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

/// Filters for listing notes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ListQuery {
    pub tag: Option<String>,
    pub q: Option<String>,
    pub after: i64,
    pub limit: u32,
}

pub const LIST_LIMIT_MAX: u32 = 100;

impl Default for ListQuery {
    fn default() -> Self {
        Self {
            tag: None,
            q: None,
            after: 0,
            limit: LIST_LIMIT_MAX,
        }
    }
}

impl ListQuery {
    /// Parses a raw (still percent-encoded) query string.
    pub fn parse(raw: Option<&str>) -> Result<Self, String> {
        let mut query = Self::default();
        let Some(raw) = raw else {
            return Ok(query);
        };
        for (key, value) in form_urlencoded::parse(raw.as_bytes()) {
            match key.as_ref() {
                "tag" => query.tag = Some(value.into_owned()),
                "q" => query.q = Some(value.into_owned()),
                "after" => {
                    query.after = parse_integer(&value)
                        .ok_or_else(|| "after must be an integer".to_owned())?;
                }
                "limit" => {
                    query.limit = value
                        .parse::<u32>()
                        .ok()
                        .filter(|n| (1..=LIST_LIMIT_MAX).contains(n))
                        .ok_or_else(|| {
                            format!("limit must be an integer from 1 to {LIST_LIMIT_MAX}")
                        })?;
                }
                _ => {}
            }
        }
        Ok(query)
    }
}

/// Parses a decimal integer, saturating values outside the `i64` range.
fn parse_integer(s: &str) -> Option<i64> {
    let (negative, digits) = match s.as_bytes().first()? {
        b'-' => (true, &s[1..]),
        b'+' => (false, &s[1..]),
        _ => (false, s),
    };
    if digits.is_empty() || !digits.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    Some(s.parse::<i64>().unwrap_or(if negative { i64::MIN } else { i64::MAX }))
}

/// Parses a note id path segment; only positive decimal integers are ids.
pub fn parse_id(segment: &str) -> Option<i64> {
    if segment.is_empty() || !segment.bytes().all(|b| b.is_ascii_digit()) {
        return None;
    }
    segment.parse::<i64>().ok().filter(|&id| id > 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_defaults_and_normalization() {
        let input =
            NoteInput::from_json(br#"{"title":"  hi  ","tags":["b","a","b"]}"#).unwrap();
        assert_eq!(input.title, "hi");
        assert_eq!(input.body, "");
        assert_eq!(input.tags, ["a", "b"]);
    }

    #[test]
    fn input_rejections() {
        for body in [
            r#"{"title": "#,
            "[]",
            "{}",
            r#"{"title":"   "}"#,
            r#"{"title":5}"#,
            r#"{"title":"x","body":3}"#,
            r#"{"title":"x","body":null}"#,
            r#"{"title":"x","tags":"a"}"#,
            r#"{"title":"x","tags":["Bad"]}"#,
            r#"{"title":"x","tags":[""]}"#,
            r#"{"title":"x","tags":[1]}"#,
        ] {
            assert!(NoteInput::from_json(body.as_bytes()).is_err(), "{body}");
        }
        let long = format!(r#"{{"title":"{}"}}"#, "é".repeat(201));
        assert!(NoteInput::from_json(long.as_bytes()).is_err());
        let max = format!(r#"{{"title":"{}"}}"#, "é".repeat(200));
        assert!(NoteInput::from_json(max.as_bytes()).is_ok());
    }

    #[test]
    fn tag_rules() {
        assert!(is_valid_tag("a-1"));
        assert!(is_valid_tag(&"a".repeat(32)));
        assert!(!is_valid_tag(&"a".repeat(33)));
        assert!(!is_valid_tag("a_b"));
        assert!(!is_valid_tag(""));
    }

    #[test]
    fn list_query() {
        assert_eq!(ListQuery::parse(None).unwrap(), ListQuery::default());
        let q = ListQuery::parse(Some("tag=x&q=hello+world&after=3&limit=5")).unwrap();
        assert_eq!(q.tag.as_deref(), Some("x"));
        assert_eq!(q.q.as_deref(), Some("hello world"));
        assert_eq!((q.after, q.limit), (3, 5));
        for bad in ["limit=0", "limit=101", "limit=x", "limit=", "after=x", "after=", "after=1.5"] {
            assert!(ListQuery::parse(Some(bad)).is_err(), "{bad}");
        }
        assert_eq!(
            ListQuery::parse(Some("after=99999999999999999999")).unwrap().after,
            i64::MAX
        );
        assert_eq!(ListQuery::parse(Some("after=-4")).unwrap().after, -4);
    }

    #[test]
    fn ids() {
        assert_eq!(parse_id("12"), Some(12));
        for bad in ["0", "-1", "+1", "abc", "", "1.0", "99999999999999999999"] {
            assert_eq!(parse_id(bad), None, "{bad}");
        }
    }
}
