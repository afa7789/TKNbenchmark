//! Reads LRU cache commands from standard input and writes results to standard output.

mod cache;

use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use cache::LruCache;

type Cache = LruCache<Box<[u8]>, Box<[u8]>>;

fn main() -> ExitCode {
    let mut input = Vec::new();
    if let Err(err) = io::stdin().lock().read_to_end(&mut input) {
        eprintln!("lru: failed to read standard input: {err}");
        return ExitCode::FAILURE;
    }

    let stdout = io::stdout().lock();
    let mut out = BufWriter::with_capacity(1 << 16, stdout);
    match run(&input, &mut out).and_then(|()| out.flush().map_err(Error::Io)) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("lru: {err}");
            ExitCode::FAILURE
        }
    }
}

#[derive(Debug)]
enum Error {
    Io(io::Error),
    InvalidCapacity(String),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::Io(err) => write!(f, "write failed: {err}"),
            Error::InvalidCapacity(text) => write!(f, "invalid capacity: {text:?}"),
        }
    }
}

impl From<io::Error> for Error {
    fn from(err: io::Error) -> Self {
        Error::Io(err)
    }
}

/// Executes every command in `input`, writing results to `out`.
fn run(input: &[u8], out: &mut impl Write) -> Result<(), Error> {
    let mut lines = split_lines(input);
    let Some(first) = lines.by_ref().find(|line| !line.trim_ascii().is_empty()) else {
        return Ok(());
    };
    let capacity = parse_capacity(first.trim_ascii())?;
    let mut cache = Cache::new(capacity);

    for line in lines {
        execute(&mut cache, line, out)?;
    }
    Ok(())
}

fn parse_capacity(text: &[u8]) -> Result<usize, Error> {
    std::str::from_utf8(text)
        .ok()
        .and_then(|s| s.parse::<usize>().ok())
        .filter(|&c| c > 0)
        .ok_or_else(|| Error::InvalidCapacity(String::from_utf8_lossy(text).into_owned()))
}

fn execute(cache: &mut Cache, line: &[u8], out: &mut impl Write) -> io::Result<()> {
    let (command, rest) = match line.iter().position(|&b| b == b' ') {
        Some(i) => (&line[..i], Some(&line[i + 1..])),
        None => (line, None),
    };

    match (command, rest) {
        (b"SET", Some(args)) => {
            if let Some(i) = args.iter().position(|&b| b == b' ') {
                cache.set(args[..i].into(), args[i + 1..].into());
            }
        }
        (b"GET", Some(key)) => match cache.get(key) {
            Some(value) => write_line(out, value)?,
            None => write_line(out, b"NULL")?,
        },
        (b"DEL", Some(key)) => {
            let removed = cache.remove(key).is_some();
            write_line(out, if removed { b"1" } else { b"0" })?;
        }
        (b"SIZE", _) => writeln!(out, "{}", cache.len())?,
        // Blank, malformed or unrecognised lines produce no output.
        _ => {}
    }
    Ok(())
}

fn write_line(out: &mut impl Write, bytes: &[u8]) -> io::Result<()> {
    out.write_all(bytes)?;
    out.write_all(b"\n")
}

/// Splits `data` into lines, tolerating a trailing `\r` and a missing final newline.
fn split_lines(data: &[u8]) -> impl Iterator<Item = &[u8]> {
    let body = data.strip_suffix(b"\n").unwrap_or(data);
    let mut lines = (!data.is_empty()).then(|| body.split(|&b| b == b'\n'));
    std::iter::from_fn(move || lines.as_mut()?.next())
        .map(|line| line.strip_suffix(b"\r").unwrap_or(line))
}

#[cfg(test)]
mod tests {
    use super::run;

    fn output(input: &str) -> String {
        let mut out = Vec::new();
        run(input.as_bytes(), &mut out).unwrap();
        String::from_utf8(out).unwrap()
    }

    #[test]
    fn spec_example() {
        let input = "2\nSET a 1\nSET b 2\nGET a\nSET c 3\nGET b\nSIZE\n";
        assert_eq!(output(input), "1\nNULL\n2\n");
    }

    #[test]
    fn missing_final_newline_and_crlf() {
        assert_eq!(output("1\r\nSET a 1\r\nGET a"), "1\n");
    }

    #[test]
    fn ignores_malformed_lines() {
        assert_eq!(output("\n2\nSET a\nGET\n\nFOO x\nSIZE"), "0\n");
    }
}
