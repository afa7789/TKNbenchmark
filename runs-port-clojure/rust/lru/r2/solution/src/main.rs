//! LRU cache simulator: reads a capacity and a stream of commands from stdin
//! and writes the results of `GET`, `DEL` and `SIZE` commands to stdout.

mod cache;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use cache::LruCache;

type Cache = LruCache<Box<[u8]>, Box<[u8]>>;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout (e.g. piped into `head`) is not an error worth reporting.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("lru: {e}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    simulate(&input, &mut out)?;
    out.flush()
}

/// Processes the whole input, writing one output line per producing command.
fn simulate(input: &[u8], out: &mut impl Write) -> io::Result<()> {
    let mut lines = input
        .split(|&b| b == b'\n' || b == b'\r')
        .map(<[u8]>::trim_ascii)
        .filter(|line| !line.is_empty());

    let Some(first) = lines.next() else {
        return Ok(());
    };
    let capacity = parse_capacity(first).ok_or_else(|| {
        io::Error::new(io::ErrorKind::InvalidData, "first line must be a positive capacity")
    })?;

    let mut cache = Cache::new(capacity);
    for line in lines {
        execute(&mut cache, line, out)?;
    }
    Ok(())
}

fn parse_capacity(line: &[u8]) -> Option<usize> {
    std::str::from_utf8(line).ok()?.parse().ok()
}

/// Runs one (trimmed, non-empty) command line against the cache.
/// Unrecognised or malformed commands are ignored.
fn execute(cache: &mut Cache, line: &[u8], out: &mut impl Write) -> io::Result<()> {
    let (cmd, rest) = match line.iter().position(|&b| b == b' ') {
        Some(i) => (&line[..i], &line[i + 1..]),
        None => (line, line),
    };

    match cmd {
        b"SET" => {
            if let Some(i) = rest.iter().position(|&b| b == b' ') {
                cache.put(rest[..i].into(), rest[i + 1..].into());
            }
        }
        b"GET" => {
            let value = cache.get(rest).map_or(&b"NULL"[..], |v| v);
            emit(out, value)?;
        }
        b"DEL" => {
            let removed = cache.remove(rest).is_some();
            emit(out, if removed { b"1" } else { b"0" })?;
        }
        b"SIZE" => writeln!(out, "{}", cache.len())?,
        _ => {}
    }
    Ok(())
}

fn emit(out: &mut impl Write, bytes: &[u8]) -> io::Result<()> {
    out.write_all(bytes)?;
    out.write_all(b"\n")
}

#[cfg(test)]
mod tests {
    use super::simulate;

    fn run(input: &str) -> String {
        let mut out = Vec::new();
        simulate(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n";
        assert_eq!(run(input), "1\nNULL\n2\n");
    }

    #[test]
    fn crlf_and_missing_trailing_newline() {
        assert_eq!(run("1\r\nSET a 1\r\nGET a\r\nDEL a"), "1\n1\n");
    }

    #[test]
    fn empty_input() {
        assert_eq!(run(""), "");
    }
}
