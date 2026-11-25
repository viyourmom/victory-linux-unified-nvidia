//! One tracing setup for every binary.
//!
//! Filter with `VICTORY_LOG` (falls back to `RUST_LOG`), e.g.
//! `VICTORY_LOG=victory_loader=trace,info`. Debug and trace output exist
//! only in builds with the `diagnostics` feature; a plain release build
//! logs info and above whatever the filter asks for.
//!
//! `VICTORY_LOG_FILE=<path>` appends to that file instead of writing to the
//! process's stderr. Under Proton a Windows PE's standard handles are not
//! the terminal that launched it: the first Linux boot showed vkd3d-proton's
//! lines but not one of ours, so the run left no trace of where it stopped.

use std::io::Write as _;
use std::sync::{Arc, Mutex};

use tracing_subscriber::EnvFilter;
use tracing_subscriber::filter::LevelFilter;
use tracing_subscriber::fmt::writer::{BoxMakeWriter, MakeWriter};
use tracing_subscriber::layer::SubscriberExt;
use tracing_subscriber::util::SubscriberInitExt;

/// The most verbose level this build can log.
const CAP: LevelFilter = if cfg!(feature = "diagnostics") {
    LevelFilter::TRACE
} else {
    LevelFilter::INFO
};

pub fn init(default_level: &str) {
    let filter = std::env::var("VICTORY_LOG")
        .or_else(|_| std::env::var("RUST_LOG"))
        .ok()
        .and_then(|v| EnvFilter::try_new(v).ok())
        .unwrap_or_else(|| EnvFilter::new(default_level));
    let _ = tracing_subscriber::registry()
        .with(CAP)
        .with(filter)
        .with(
            tracing_subscriber::fmt::layer()
                .with_target(true)
                .with_writer(writer()),
        )
        .try_init();
}

/// Where the log goes: the file `VICTORY_LOG_FILE` names (appended to), else
/// stderr. A file that cannot be opened is reported and stderr is used, so a
/// typo costs a line rather than the log.
fn writer() -> BoxMakeWriter {
    let path = match std::env::var_os("VICTORY_LOG_FILE") {
        Some(path) if !path.is_empty() => path,
        _ => return BoxMakeWriter::new(std::io::stderr),
    };
    // Append: a run that relaunches itself must not truncate the first
    // attempt's lines.
    match std::fs::OpenOptions::new().create(true).append(true).open(&path) {
        Ok(file) => BoxMakeWriter::new(SharedFile(Arc::new(Mutex::new(file)))),
        Err(e) => {
            eprintln!(
                "VICTORY_LOG_FILE={} cannot be opened ({e}); logging to stderr",
                path.to_string_lossy()
            );
            BoxMakeWriter::new(std::io::stderr)
        }
    }
}

/// The log file, shared by every thread that writes a line.
#[derive(Clone)]
struct SharedFile(Arc<Mutex<std::fs::File>>);

impl std::io::Write for SharedFile {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .write(buf)
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.0
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .flush()
    }
}

impl<'a> MakeWriter<'a> for SharedFile {
    type Writer = SharedFile;

    fn make_writer(&'a self) -> Self::Writer {
        self.clone()
    }
}
