//! Command-line LRU cache simulator (see SPEC.md).
//!
//! Input is treated as raw bytes so that any key or value round-trips exactly.

mod lru_cache;

use std::io::{self, BufWriter, Read, Write};

use lru_cache::LruCache;

const NULL_REPLY: &[u8] = b"NULL";

/// Runs the command script in `input`, writing one reply line per query.
fn run(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = input.split(|&b| b == b'\n');
    let Some(capacity) = lines.next().and_then(parse_capacity) else {
        return Ok(());
    };

    let mut cache: LruCache<Box<[u8]>, Box<[u8]>> = LruCache::new(capacity);

    for line in lines {
        let line = line.strip_suffix(b"\r").unwrap_or(line);
        if line.is_empty() {
            continue;
        }

        let (command, rest) = split_once_space(line).unwrap_or((line, b""));
        match command {
            b"SET" => {
                if let Some((key, value)) = split_once_space(rest) {
                    cache.set(key.into(), value.into());
                }
            }
            b"GET" => {
                out.write_all(cache.get(rest).map_or(NULL_REPLY, |v| v))?;
                out.write_all(b"\n")?;
            }
            b"DEL" => {
                out.write_all(if cache.remove(rest) { b"1\n" } else { b"0\n" })?;
            }
            b"SIZE" => writeln!(out, "{}", cache.len())?,
            // Unknown commands are ignored.
            _ => {}
        }
    }
    Ok(())
}

fn split_once_space(s: &[u8]) -> Option<(&[u8], &[u8])> {
    let at = s.iter().position(|&b| b == b' ')?;
    Some((&s[..at], &s[at + 1..]))
}

/// Parses the capacity line leniently: leading whitespace, an optional sign,
/// then a run of decimal digits; anything after the digits is ignored.
/// Returns `None` unless the result is a positive integer.
fn parse_capacity(line: &[u8]) -> Option<usize> {
    let is_space = |b: &u8| matches!(b, b'\t' | b'\n' | 0x0b | 0x0c | b'\r' | b' ' | 0xa0);
    let start = line.iter().position(|b| !is_space(b)).unwrap_or(line.len());
    let s = &line[start..];

    let digits = match s.first() {
        // Any negative value (or -0) is not a valid capacity.
        Some(b'-') => return None,
        Some(b'+') => &s[1..],
        _ => s,
    };
    parse_digits(digits).filter(|&n| n >= 1)
}

/// Parses leading decimal digits, saturating on overflow.
fn parse_digits(s: &[u8]) -> Option<usize> {
    let len = s.iter().take_while(|b| b.is_ascii_digit()).count();
    if len == 0 {
        return None;
    }
    let value = s[..len].iter().fold(0usize, |acc, &d| {
        acc.saturating_mul(10).saturating_add(usize::from(d - b'0'))
    });
    Some(value)
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    run(&input, &mut out)?;
    out.flush()
}

#[cfg(test)]
mod tests {
    use super::{parse_capacity, run};

    fn run_str(input: &str) -> String {
        let mut out = Vec::new();
        run(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n";
        assert_eq!(run_str(input), "1\nNULL\n2\n");
    }

    #[test]
    fn capacity_parsing() {
        assert_eq!(parse_capacity(b"3"), Some(3));
        assert_eq!(parse_capacity(b" +7x"), Some(7));
        assert_eq!(parse_capacity(b"2\r"), Some(2));
        assert_eq!(parse_capacity(b"0"), None);
        assert_eq!(parse_capacity(b"-4"), None);
        assert_eq!(parse_capacity(b"abc"), None);
        assert_eq!(parse_capacity(b""), None);
    }

    #[test]
    fn invalid_capacity_prints_nothing() {
        assert_eq!(run_str("0\nSET a 1\nSIZE\n"), "");
    }
}
