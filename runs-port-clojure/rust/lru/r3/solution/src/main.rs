//! LRU cache simulator: reads a capacity and a stream of commands from stdin,
//! writes command results to stdout.

mod cache;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use cache::LruCache;

type Bytes = Box<[u8]>;

/// Strips leading and trailing ASCII control characters and spaces
/// (every byte `<= b' '`), matching Java's `String.trim`.
fn trim(line: &[u8]) -> &[u8] {
    let start = line.iter().position(|&b| b > b' ').unwrap_or(line.len());
    let end = line.iter().rposition(|&b| b > b' ').map_or(start, |i| i + 1);
    &line[start..end]
}

/// Splits `line` at the first space into the part before it and the rest.
fn split_once_space(line: &[u8]) -> Option<(&[u8], &[u8])> {
    let at = line.iter().position(|&b| b == b' ')?;
    Some((&line[..at], &line[at + 1..]))
}

/// Executes one (trimmed, non-empty) command line, writing any output.
fn run_command(cache: &mut LruCache<Bytes, Bytes>, out: &mut impl Write, line: &[u8]) -> io::Result<()> {
    let (op, args) = split_once_space(line).unwrap_or((line, line));
    match op {
        b"SET" => {
            if let Some((key, value)) = split_once_space(args) {
                cache.put(key.into(), value.into());
            }
        }
        b"GET" => {
            let value = cache.get(args).map_or(&b"NULL"[..], |v| &v[..]);
            out.write_all(value)?;
            out.write_all(b"\n")?;
        }
        b"DEL" => {
            let answer: &[u8] = if cache.remove(args).is_some() { b"1\n" } else { b"0\n" };
            out.write_all(answer)?;
        }
        b"SIZE" => writeln!(out, "{}", cache.len())?,
        _ => {}
    }
    Ok(())
}

/// Processes the whole input, writing results to `out`.
fn run(input: &[u8], out: &mut impl Write) -> Result<(), String> {
    if input.is_empty() {
        return Ok(());
    }
    let mut lines = input.split(|&b| b == b'\n');
    let first = trim(lines.next().unwrap_or_default());
    let capacity: usize = std::str::from_utf8(first)
        .ok()
        .and_then(|s| s.parse().ok())
        .ok_or_else(|| format!("invalid capacity: {:?}", String::from_utf8_lossy(first)))?;

    let mut cache = LruCache::new(capacity);
    let io_err = |e: io::Error| format!("write failed: {e}");
    for line in lines {
        let line = trim(line);
        if !line.is_empty() {
            run_command(&mut cache, out, line).map_err(io_err)?;
        }
    }
    out.flush().map_err(io_err)
}

fn main() -> ExitCode {
    let mut input = Vec::new();
    if let Err(e) = io::stdin().lock().read_to_end(&mut input) {
        eprintln!("lru: failed to read stdin: {e}");
        return ExitCode::FAILURE;
    }

    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    match run(&input, &mut out) {
        Ok(()) => ExitCode::SUCCESS,
        Err(msg) => {
            eprintln!("lru: {msg}");
            ExitCode::FAILURE
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn tolerates_crlf_blank_lines_and_missing_final_newline() {
        let input = "3\r\nSET x 1\r\n\r\nDEL x\nDEL x\nSIZE\nGET x";
        assert_eq!(run_str(input), "1\n0\n0\nNULL\n");
    }

    #[test]
    fn empty_input_prints_nothing() {
        assert_eq!(run_str(""), "");
    }

    #[test]
    fn trim_matches_java() {
        assert_eq!(trim(b" \t ab c\r"), b"ab c");
        assert_eq!(trim(b"\r\n "), b"");
    }
}
