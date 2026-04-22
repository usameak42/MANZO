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
    manzo_close, manzo_get_duration, manzo_get_position, manzo_get_spectrum,
    manzo_get_state, manzo_open, manzo_pause, manzo_play, manzo_stop,
};
use std::ffi::CString;

/// Path to the CC0 test fixture, resolved at compile time.
const FIXTURE_PATH: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/test.mp3");

/// Phase 3 short fixture (~1s) for ENDED-state polling test, resolved at compile time.
const FIXTURE_PATH_2: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/test2.mp3");

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

#[test]
fn get_state_returns_stopped_after_open() {
    // D-02: a freshly-opened handle that has not yet been played reports STOPPED (3).
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    let state = unsafe { manzo_get_state(handle) };
    assert_eq!(
        state, 3,
        "manzo_get_state must return 3 (STOPPED) immediately after open — D-02"
    );

    unsafe { manzo_close(handle) };
}

#[test]
fn get_duration_returns_nonzero_for_valid_mp3() {
    // D-03: mpg123_length must report > 0 ms for the Phase 2 sine-tone fixture
    // (sox-generated, so it has a valid Xing/LAME header for VBR length).
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    let duration = unsafe { manzo_get_duration(handle) };
    assert!(
        duration > 0,
        "manzo_get_duration must return > 0 ms for a valid MP3 with length metadata (got {})",
        duration
    );

    unsafe { manzo_close(handle) };
}

#[test]
#[ignore = "requires audio output hardware; not available in headless CI environments"]
fn state_transitions_play_pause_stop() {
    // D-02: full state-machine walk PLAY (1) → PAUSE (2) → STOP (3).
    let path = CString::new(FIXTURE_PATH).expect("FIXTURE_PATH contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(!handle.is_null(), "precondition: manzo_open must succeed");

    // Initial state after open: STOPPED (3)
    assert_eq!(
        unsafe { manzo_get_state(handle) },
        3,
        "state must be STOPPED (3) after open"
    );

    // PLAYING (1) after manzo_play
    let play_ret = unsafe { manzo_play(handle) };
    assert_eq!(play_ret, 0, "manzo_play must return 0 on success");
    assert_eq!(
        unsafe { manzo_get_state(handle) },
        1,
        "state must be PLAYING (1) after manzo_play"
    );

    // PAUSED (2) after manzo_pause
    unsafe { manzo_pause(handle) };
    assert_eq!(
        unsafe { manzo_get_state(handle) },
        2,
        "state must be PAUSED (2) after manzo_pause"
    );

    // STOPPED (3) after manzo_stop
    unsafe { manzo_stop(handle) };
    assert_eq!(
        unsafe { manzo_get_state(handle) },
        3,
        "state must be STOPPED (3) after manzo_stop"
    );

    unsafe { manzo_close(handle) };
}

#[test]
#[ignore = "requires audio output hardware; not available in headless CI environments"]
fn state_becomes_ended_after_short_track_completes() {
    // D-02 + AUDIO-05: ENDED (4) is the trigger Swift polls to drive auto-advance.
    // Uses test2.mp3 — a ~1-second clip so ENDED is reached well within the 3-second deadline.
    let path = CString::new(FIXTURE_PATH_2).expect("FIXTURE_PATH_2 contains no null byte");
    let handle = unsafe { manzo_open(path.as_ptr()) };
    assert!(
        !handle.is_null(),
        "precondition: manzo_open must succeed with test2.mp3 (Plan 03-02 generates this fixture)"
    );

    let play_ret = unsafe { manzo_play(handle) };
    assert_eq!(play_ret, 0, "manzo_play must return 0 on test2.mp3");

    // Poll until ENDED (4) or 3-second deadline
    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
    let mut final_state = 0i32;
    while std::time::Instant::now() < deadline {
        final_state = unsafe { manzo_get_state(handle) };
        if final_state == 4 {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(50));
    }
    assert_eq!(
        final_state, 4,
        "state must reach ENDED (4) within 3 s for a ~1 s track (got {}) — D-02 / AUDIO-05",
        final_state
    );

    unsafe { manzo_close(handle) };
}
