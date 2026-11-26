//! Prints the 10 most frequent ASCII words read from standard input.

use std::io::{self, BufWriter, Write};
use std::process::ExitCode;

use wordfreq::{count_words, top_words};

const TOP_N: usize = 10;

fn run() -> io::Result<()> {
    let counts = count_words(io::stdin().lock())?;
    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in top_words(&counts, TOP_N) {
        write!(out, "{count} ")?;
        out.write_all(word)?;
        out.write_all(b"\n")?;
    }
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("wordfreq: {e}");
            ExitCode::FAILURE
        }
    }
}
