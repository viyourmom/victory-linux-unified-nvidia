//! The last word when the process ends by abort.
//!
//! A CRT `abort` (a failed assertion in a title DLL, Rust's `abort` on a
//! path it cannot continue from) ends the process at **exit code 3** on
//! Windows without an exception handler seeing it: the unhandled-exception
//! filter never runs, `crashes.log` stays empty, and the only line that says
//! why is the one the run most needs. Runs stopped that way four times at
//! the same frame before this file existed.
//!
//! Two things are written straight to `VICTORY_LOG_FILE`, flushed and synced
//! before the process ends, because nothing after them may run:
//!
//! - a panic, with its location, thread name and a captured backtrace (the
//!   runtime's own hook is still called, so nothing it did is lost);
//! - `SIGABRT`, which the CRT raises before terminating with status 3.
//!
//! The vector exception handler and the unhandled-exception filter in
//! `victory_loader::crash` keep doing their job for faults, which are a
//! different path (they carry the faulting address and a stack walk over
//! the title's code, and they append to `crashes.log`). This is the path
//! that leaves no trace at all.

use std::io::Write as _;

/// Appends to `VICTORY_LOG_FILE` (created if needed) and syncs it, or writes
/// to stderr when no file is set. Not async-signal-safe: it allocates and
/// takes the file system's locks. That is acceptable only because the caller
/// is ending the process either way, and the alternative is losing the line.
fn append(text: &str) {
    let path = std::env::var_os("VICTORY_LOG_FILE").filter(|p| !p.is_empty());
    let Some(path) = path else {
        eprint!("{text}");
        return;
    };
    match std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
    {
        Ok(mut file) => {
            let _ = file.write_all(text.as_bytes());
            let _ = file.flush();
            let _ = file.sync_all();
        }
        Err(_) => eprint!("{text}"),
    }
}

/// Installs the panic hook and, on Windows, the `SIGABRT` handler. Call once,
/// before any title code runs.
pub fn install() {
    let previous = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        append(&format!(
            "\nVIctory: panic on thread {:?} at {}\n{info}\n{}",
            std::thread::current().name().unwrap_or("?"),
            info.location().map_or_else(|| "?".into(), |l| l.to_string()),
            std::backtrace::Backtrace::force_capture()
        ));
        previous(info);
    }));
    #[cfg(windows)]
    // SAFETY: installing a handler for a signal whose default action ends
    // the process; the handler takes no arguments it could get wrong.
    unsafe {
        install_sigabrt()
    };
}

/// The CRT raises `SIGABRT` before it terminates with status 3, which is the
/// status a run that stops this way leaves behind. Writing from a handler is
/// not async-signal-safe; see [`append`] for why that is accepted here.
#[cfg(windows)]
unsafe fn install_sigabrt() {
    unsafe extern "C" {
        /// The CRT's `signal` (its handler takes the signal number).
        fn signal(signal: i32, handler: usize) -> usize;
        /// Ends the process without running exit handlers: the CRT's own
        /// abort path runs none, and one of ours could wait on a lock a
        /// crashed thread holds.
        fn _exit(code: i32) -> !;
    }
    /// `SIGABRT` in the MSVC CRT's numbering.
    const SIGABRT: i32 = 22;
    /// A panic from a handler would abort again; this one only writes.
    extern "C" fn on_abort(signal: i32) {
        append(&format!(
            "\nVIctory: the process aborted (signal {signal}); last thread {}\n{}",
            std::thread::current().name().unwrap_or("?"),
            std::backtrace::Backtrace::force_capture()
        ));
        // SAFETY: ending this process at the status an unhandled abort has.
        unsafe { _exit(3) }
    }
    // SAFETY: a plain CRT call; the handler is a plain `extern "C"` function.
    unsafe { signal(SIGABRT, on_abort as usize) };
}
