//! Integration tests for the manzo-core audio pipeline.
//! Requires tests/fixtures/test.mp3 (CC0 ~5s audio clip, generated in 02-01).
//!
//! Run with: cargo test --test integration_test
//! Note: play_advances_position requires audio output hardware; marked #[ignore] for headless CI.
//!
//! These tests call the pub extern "C" functions directly via the rlib link path.
//! The crate type includes "rlib" (alongside "staticlib") so integration tests can link.

use manzo_core::{
    ManzoHandle,
    manzo_close, manzo_get_position, manzo_get_spectrum, manzo_open, manzo_play,
};
use std::ffi::CString;

/// Path to the CC0 test fixture, resolved at compile time.
const FIXTURE_PATH: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/test.mp3");

#[test]
fn open_returns_non_null_for_valid_mp3() {
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(
        !handle.is_null(),
        "manzo_open must return non-null handle for a valid MP3 file"
    );
    // manzo_close must not crash on a valid handle
    unsafe { manzo_close(handle) };
}

#[test]
fn open_returns_null_for_invalid_path() {
    let bad_path = CString::new("/nonexistent/no_such_file.mp3").unwrap();
    let handle = unsafe { manzo_open(bad_path.as_ptr()) };
    assert!(
        handle.is_null(),
        "manzo_open must return null for a nonexistent file path"
    );
}

#[test]
#[ignore = "requires audio output hardware; not available in headless CI environments"]
fn play_advances_position() {
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    let play_result = unsafe { manzo_play(handle) };
    assert_eq!(play_result, 0, "manzo_play must return 0 on success");

    // Allow the audio thread to decode at least a few frames
    std::thread::sleep(std::time::Duration::from_millis(200));

    let pos = unsafe { manzo_get_position(handle) };
    assert!(
        pos > 0,
        "playback position must be > 0 ms after 200ms of playback (got {})",
        pos
    );

    unsafe { manzo_close(handle) };
}

#[test]
fn spectrum_buffer_is_zero_filled() {
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    // Pre-fill with NaN to detect any unwritten bytes (D-01: buffer must always be written)
    let mut buf = vec![f32::NAN; 512];
    let written = unsafe { manzo_get_spectrum(handle, buf.as_mut_ptr(), 512) };

    assert_eq!(
        written, 512,
        "manzo_get_spectrum must return count (512) when out_buf is valid"
    );
    assert!(
        buf.iter().all(|&v| v == 0.0_f32),
        "manzo_get_spectrum must zero-fill all {} elements — D-01 contract",
        512
    );

    unsafe { manzo_close(handle) };
}

#[test]
fn spectrum_null_buf_returns_zero() {
    // Null out_buf must return 0 without crashing (security: T-02-06)
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    let written = unsafe {
        manzo_get_spectrum(handle, std::ptr::null_mut::<f32>(), 512)
    };
    assert_eq!(
        written, 0,
        "manzo_get_spectrum with null out_buf must return 0"
    );

    unsafe { manzo_close(handle) };
}
