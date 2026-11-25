use std::io::{self, BufWriter, Read};
use std::process::ExitCode;

fn main() -> ExitCode {
    let mut input = Vec::new();
    if let Err(e) = io::stdin().lock().read_to_end(&mut input) {
        eprintln!("error: failed to read stdin: {e}");
        return ExitCode::FAILURE;
    }
    let mut out = BufWriter::with_capacity(1 << 16, io::stdout().lock());
    match app::run(&input, &mut out) {
        Ok(()) => ExitCode::SUCCESS,
        Err(e) => {
            eprintln!("error: {e}");
            ExitCode::FAILURE
        }
    }
}
