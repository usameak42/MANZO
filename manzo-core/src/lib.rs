//! manzo-core — Rust audio/DSP core for MANZO
//! FFI surface: 11 C-callable functions, generated header via cbindgen
//! All functions are stubs; real implementations added in Phase 2+

/// Opaque handle returned by manzo_open and passed to all subsequent calls.
/// Phase 2 replaces this with a real AudioPlayer state.
#[repr(C)]
pub struct ManzoHandle {
    _private: [u8; 0],
}

/// Opens a file path for playback. Returns a non-null opaque handle on success,
/// or null on failure. Caller owns the handle; must call manzo_close to free.
#[no_mangle]
pub extern "C" fn manzo_open(path: *const std::os::raw::c_char) -> *mut ManzoHandle {
    let _ = path; // used in Phase 2
    std::ptr::null_mut()
}

/// Closes and frees the handle returned by manzo_open.
#[no_mangle]
pub extern "C" fn manzo_close(handle: *mut ManzoHandle) {
    let _ = handle; // real dealloc in Phase 2
}

/// Starts or resumes playback. Returns 0 on success, non-zero on error.
#[no_mangle]
pub extern "C" fn manzo_play(handle: *mut ManzoHandle) -> i32 {
    let _ = handle;
    0
}

/// Pauses playback without resetting position.
#[no_mangle]
pub extern "C" fn manzo_pause(handle: *mut ManzoHandle) {
    let _ = handle;
}

/// Stops playback and resets position to start.
#[no_mangle]
pub extern "C" fn manzo_stop(handle: *mut ManzoHandle) {
    let _ = handle;
}

/// Seeks to `position_ms` milliseconds from start. Returns 0 on success.
#[no_mangle]
pub extern "C" fn manzo_seek(handle: *mut ManzoHandle, position_ms: u64) -> i32 {
    let _ = (handle, position_ms);
    0
}

/// Sets the 10-band EQ gains. `gains` must point to an array of exactly 10 f32 values
/// in dB (range ±12.0). `preamp` is additional preamp gain in dB.
#[no_mangle]
pub extern "C" fn manzo_set_eq(
    handle: *mut ManzoHandle,
    gains: *const f32,
    preamp: f32,
) {
    let _ = (handle, gains, preamp);
}

/// Sets master volume. `volume` is in range [0.0, 1.0].
#[no_mangle]
pub extern "C" fn manzo_set_volume(handle: *mut ManzoHandle, volume: f32) {
    let _ = (handle, volume);
}

/// Sets stereo pan. `pan` is in range [-1.0, 1.0]; 0.0 = center.
#[no_mangle]
pub extern "C" fn manzo_set_pan(handle: *mut ManzoHandle, pan: f32) {
    let _ = (handle, pan);
}

/// Returns the current playback position in milliseconds.
#[no_mangle]
pub extern "C" fn manzo_get_position(handle: *mut ManzoHandle) -> u64 {
    let _ = handle;
    0
}

/// Fills `out_buf` with `count` float32 FFT magnitude values (range [0.0, 1.0]).
/// Returns number of values written. `out_buf` must be at least `count` elements.
#[no_mangle]
pub extern "C" fn manzo_get_spectrum(
    handle: *mut ManzoHandle,
    out_buf: *mut f32,
    count: usize,
) -> usize {
    let _ = (handle, out_buf);
    count // stub: return count — buffer is NOT written (Phase 2 will write f32 zeros)
}

// ---------------------------------------------------------------------------
// Unit tests — cargo test must pass
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stub_play_returns_zero() {
        let result = manzo_play(std::ptr::null_mut());
        assert_eq!(result, 0, "manzo_play stub must return 0");
    }

    #[test]
    fn stub_seek_returns_zero() {
        let result = manzo_seek(std::ptr::null_mut(), 1000);
        assert_eq!(result, 0, "manzo_seek stub must return 0");
    }

    #[test]
    fn stub_get_position_returns_zero() {
        let result = manzo_get_position(std::ptr::null_mut());
        assert_eq!(result, 0, "manzo_get_position stub must return 0");
    }

    #[test]
    fn stub_get_spectrum_returns_count() {
        // NOTE: null_mut() for out_buf is only safe here because the stub does NOT
        // dereference out_buf. Phase 2 must allocate a real f32 buffer before calling
        // the real implementation, or this will cause undefined behavior.
        let result = manzo_get_spectrum(std::ptr::null_mut(), std::ptr::null_mut(), 512);
        assert_eq!(result, 512, "manzo_get_spectrum stub must echo count");
    }
}
