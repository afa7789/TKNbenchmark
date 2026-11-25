use std::io::{self, BufWriter, Read, Write};
use std::process::ExitCode;

const TOP_N: usize = 10;

fn run() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let counts = wordfreq::count_words(&input);
    let top = wordfreq::top_words(counts, TOP_N);

    let mut out = BufWriter::new(io::stdout().lock());
    wordfreq::write_report(&mut out, &top)?;
    out.flush()
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        // A closed stdout (e.g. piped into `head`) is not an error worth reporting.
        Err(e) if e.kind() == io::ErrorKind::BrokenPipe => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("wordfreq: {e}");
            ExitCode::FAILURE
        }
    }
}
