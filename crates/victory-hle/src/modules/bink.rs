//! Debugging aid (diagnostics builds, `VICTORY_SKIP_MOVIES=1`): the title's
//! Bink videos end after their first frame, to reach what follows them
//! sooner. The video library is the title's own DLL and does the work; only
//! the frame count the title reads from an opened video is changed. Without
//! the switch nothing here is used and the title binds the DLL's export
//! directly.
//!
//! (Ported from `JordanFromIT/CGBJ-VIctory`'s `world-test`, whose note says
//! removing `movies.rpf` instead does not work: the title stops at a
//! breakpoint during start-up.)

use std::ffi::c_void;

use windows_sys::Win32::Foundation::HMODULE;
use windows_sys::Win32::System::LibraryLoader::GetProcAddress;
use windows_sys::Win32::System::ProcessStatus::K32EnumProcessModules;
use windows_sys::Win32::System::Threading::GetCurrentProcess;

/// With the switch on: our stand-in for the one import it replaces. Not a
/// registry module: the DLL stays the title's, loaded as such.
pub(crate) fn replacement(dll: &str, name: &str) -> Option<usize> {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    let on =
        *ON.get_or_init(|| std::env::var_os("VICTORY_SKIP_MOVIES").is_some_and(|v| v != "0"));
    (on && dll.eq_ignore_ascii_case("bink2scarlett.dll") && name == "BinkOpenWithOptions")
        .then_some(BinkOpenWithOptions as *const () as usize)
}

type Open = unsafe extern "system" fn(*const c_void, *const c_void, u32) -> *mut u32;

/// The title DLL's own `BinkOpenWithOptions`: title DLLs are mapped under
/// other names, so the modules are searched for the export.
fn real() -> Option<Open> {
    static REAL: std::sync::OnceLock<Option<usize>> = std::sync::OnceLock::new();
    let address = *REAL.get_or_init(|| {
        let mut modules = [std::ptr::null_mut::<c_void>() as HMODULE; 1024];
        let mut needed = 0;
        // SAFETY: the buffer and its size in bytes; `needed` is written.
        let ok = unsafe {
            K32EnumProcessModules(
                GetCurrentProcess(),
                modules.as_mut_ptr(),
                size_of_val(&modules) as u32,
                &mut needed,
            )
        } != 0;
        let count = if ok {
            (needed as usize / size_of::<HMODULE>()).min(modules.len())
        } else {
            0
        };
        modules[..count].iter().find_map(|&m| {
            // SAFETY: a loaded module and a NUL-terminated name.
            unsafe { GetProcAddress(m, c"BinkOpenWithOptions".as_ptr().cast()) }.map(|f| f as usize)
        })
    });
    // SAFETY: the export's address; its signature is the library's.
    address.map(|a| unsafe { std::mem::transmute::<usize, Open>(a) })
}

/// Opens the video with the title's library, then says it has one frame.
/// A video handle starts with its width, height, frame count and current
/// frame (four dwords): the title plays until the current frame reaches the
/// count.
#[allow(non_snake_case)]
extern "system" fn BinkOpenWithOptions(
    name: *const c_void,
    options: *const c_void,
    flags: u32,
) -> *mut u32 {
    let Some(open) = real() else {
        tracing::warn!("VICTORY_SKIP_MOVIES: the video library's open was not found");
        return std::ptr::null_mut();
    };
    // SAFETY: the title's own arguments, passed on unchanged.
    let video = unsafe { open(name, options, flags) };
    if !video.is_null() {
        // SAFETY: an open video's header, as described above.
        let (width, height, frames) = unsafe { (*video, *video.add(1), *video.add(2)) };
        let plausible = (16..=8192).contains(&width) && (16..=8192).contains(&height) && frames > 1;
        tracing::info!(
            width,
            height,
            frames,
            cut = plausible,
            "VICTORY_SKIP_MOVIES: video opened"
        );
        if plausible {
            // SAFETY: as above; the field is the library's count of frames.
            unsafe { video.add(2).write(1) }
        }
    }
    video
}
