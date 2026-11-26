//! Reads LRU cache commands from standard input and writes results to
//! standard output. See SPEC.md for the protocol.

mod lru_cache;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use lru_cache::LruCache;

type Cache = LruCache<Box<[u8]>, Box<[u8]>>;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("lru: {err}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    process(&input, &mut out)?;
    out.flush()
}

/// Executes every command in `input` against a cache sized by the header line.
fn process(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = Lines::new(input);
    let Some(header) = lines.next() else {
        return Ok(());
    };
    let capacity = parse_capacity(header)?;
    let mut cache = Cache::new(capacity);
    for line in lines {
        execute(&mut cache, line, out)?;
    }
    Ok(())
}

fn parse_capacity(header: &[u8]) -> io::Result<usize> {
    let invalid = || io::Error::new(io::ErrorKind::InvalidData, "invalid capacity");
    let text = std::str::from_utf8(header.trim_ascii()).map_err(|_| invalid())?;
    match text.parse::<i32>() {
        Ok(n) if n >= 1 => Ok(n as usize),
        _ => Err(invalid()),
    }
}

fn execute(cache: &mut Cache, line: &[u8], out: &mut impl Write) -> io::Result<()> {
    let (command, args) = match line.iter().position(|&b| b == b' ') {
        Some(i) => (&line[..i], Some(&line[i + 1..])),
        None => (line, None),
    };
    match (command, args) {
        (b"SET", Some(args)) => {
            if let Some(i) = args.iter().position(|&b| b == b' ') {
                cache.put(args[..i].into(), args[i + 1..].into());
            }
        }
        (b"GET", Some(key)) => {
            let value = cache.get(key).map_or(&b"NULL"[..], |v| v);
            write_line(out, value)?;
        }
        (b"DEL", Some(key)) => {
            write_line(out, if cache.remove(key) { b"1" } else { b"0" })?;
        }
        (b"SIZE", _) => writeln!(out, "{}", cache.len())?,
        // Blank, malformed or unrecognised lines are ignored.
        _ => {}
    }
    Ok(())
}

fn write_line(out: &mut impl Write, text: &[u8]) -> io::Result<()> {
    out.write_all(text)?;
    out.write_all(b"\n")
}

/// Splits input into lines terminated by `\n`, `\r` or `\r\n`; the final line
/// may lack a terminator.
struct Lines<'a> {
    rest: &'a [u8],
}

impl<'a> Lines<'a> {
    fn new(input: &'a [u8]) -> Self {
        Self { rest: input }
    }
}

impl<'a> Iterator for Lines<'a> {
    type Item = &'a [u8];

    fn next(&mut self) -> Option<&'a [u8]> {
        if self.rest.is_empty() {
            return None;
        }
        let Some(end) = self.rest.iter().position(|&b| b == b'\n' || b == b'\r') else {
            return Some(std::mem::take(&mut self.rest));
        };
        let line = &self.rest[..end];
        let skip = if self.rest[end..].starts_with(b"\r\n") { 2 } else { 1 };
        self.rest = &self.rest[end + skip..];
        Some(line)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn run_str(input: &str) -> String {
        let mut out = Vec::new();
        process(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n";
        assert_eq!(run_str(input), "1\nNULL\n2\n");
    }

    #[test]
    fn handles_crlf_and_missing_final_newline() {
        assert_eq!(run_str("1\r\nSET a 1\r\nGET a"), "1\n");
    }

    #[test]
    fn ignores_malformed_lines() {
        assert_eq!(run_str("2\n\nSET a\nGET\nDEL\nFOO\nSIZE\n"), "0\n");
    }
}
