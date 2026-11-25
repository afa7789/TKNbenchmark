use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

use wordfreq::{count_words, top_n};

const TOP: usize = 10;

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut out = BufWriter::new(io::stdout().lock());
    for (word, count) in top_n(count_words(&input), TOP) {
        write!(out, "{count} ")?;
        out.write_all(&word)?;
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
