//! LRU cache simulator: reads a capacity and a stream of commands from stdin
//! and writes command results to stdout. See SPEC.md.

mod lru_cache;

use std::io::{self, Read, Write};

use lru_cache::LruCache;

/// Splits `text` into lines on `\n`, tolerating a missing final newline and a
/// stray `\r` before each newline.
fn lines(text: &[u8]) -> impl Iterator<Item = &[u8]> {
    let body = text.strip_suffix(b"\n").unwrap_or(text);
    let mut parts = body.split(|&b| b == b'\n');
    if text.is_empty() {
        // `split` on an empty slice yields one empty item; there are no lines.
        parts.next();
    }
    parts.map(|line| line.strip_suffix(b"\r").unwrap_or(line))
}

/// Yields the space-delimited tokens of `line`, ignoring repeated spaces.
fn tokens(line: &[u8]) -> impl Iterator<Item = &[u8]> {
    line.split(|&b| b == b' ').filter(|t| !t.is_empty())
}

/// Parses the leading decimal digits of the first token; anything unparsable
/// (or out of range) yields 0.
fn parse_capacity(line: &[u8]) -> usize {
    let token = tokens(line).next().unwrap_or_default();
    token
        .iter()
        .take_while(|b| b.is_ascii_digit())
        .try_fold(0usize, |acc, &d| {
            acc.checked_mul(10)?.checked_add(usize::from(d - b'0'))
        })
        .unwrap_or(0)
}

/// Executes one command line, appending any output to `out`.
/// Blank or unrecognised lines produce no output.
fn execute(cache: &mut LruCache, line: &[u8], out: &mut Vec<u8>) {
    let mut args = tokens(line);
    let Some(command) = args.next() else {
        return;
    };
    let mut arg = || args.next().unwrap_or_default();
    match command {
        b"SET" => {
            let (key, value) = (arg(), arg());
            if !key.is_empty() && !value.is_empty() {
                cache.set(key, value);
            }
        }
        b"GET" => {
            out.extend_from_slice(cache.get(arg()).unwrap_or(b"NULL"));
            out.push(b'\n');
        }
        b"DEL" => out.extend_from_slice(if cache.remove(arg()) { b"1\n" } else { b"0\n" }),
        b"SIZE" => {
            // Writing into a Vec cannot fail.
            let _ = writeln!(out, "{}", cache.len());
        }
        _ => {}
    }
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut lines = lines(&input);
    let Some(first) = lines.next() else {
        return Ok(());
    };
    let mut cache = LruCache::new(parse_capacity(first));

    let mut out = Vec::with_capacity(1 << 20);
    for line in lines {
        execute(&mut cache, line, &mut out);
    }

    let mut stdout = io::stdout().lock();
    stdout.write_all(&out)?;
    stdout.flush()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run(input: &str) -> String {
        let mut it = lines(input.as_bytes());
        let mut cache = LruCache::new(parse_capacity(it.next().unwrap()));
        let mut out = Vec::new();
        for line in it {
            execute(&mut cache, line, &mut out);
        }
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        assert_eq!(
            run("2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n"),
            "1\nNULL\n2\n"
        );
    }

    #[test]
    fn missing_final_newline_and_crlf() {
        assert_eq!(run("1\r\nSET a 1\r\nGET a"), "1\n");
    }

    #[test]
    fn capacity_parsing() {
        assert_eq!(parse_capacity(b"42"), 42);
        assert_eq!(parse_capacity(b" 7 "), 7);
        assert_eq!(parse_capacity(b"x"), 0);
        assert_eq!(parse_capacity(b"99999999999999999999999"), 0);
    }
}
