//! manzo-core — Rust audio/DSP core for MANZO
//! FFI surface: 11 C-callable functions, generated header via cbindgen
//! Phase 2: Real MP3 decode + CoreAudio output pipeline

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex};
use std::ffi::CStr;

/// Opaque handle returned by manzo_open and passed to all subsequent calls.
/// The real state lives behind a raw pointer cast to Arc<Mutex<InnerState>>.
#[repr(C)]
pub struct ManzoHandle {
    _private: [u8; 0],
}

/// Feed chunk size in bytes — validated pattern from spike 003; do not change.
const FEED_CHUNK_SIZE: usize = 4096;

/// Internal playback state, protected by Arc<Mutex<>> per D-02.
struct InnerState {
    mpg_handle: *mut mpg123_sys::mpg123_handle,
    file_data: Vec<u8>,
    file_offset: usize,
    stream: Option<cpal::Stream>,
    position_samples: u64,
    sample_rate: u32,
    channels: u16,
    is_playing: bool,
    // Phase 4 DSP fields — stored now, wired into DSP chain in Phase 4
    volume: f32,
    pan: f32,
    eq_gains: [f32; 10],
    eq_preamp: f32,
    // Phase 3 (D-02): playback state for manzo_get_state()
    //   1 = PLAYING, 2 = PAUSED, 3 = STOPPED, 4 = ENDED
    playback_state: i32,
    // Phase 3 (D-04): 529-sample mpg123 decoder startup delay trim.
    // Initialized to 529 in manzo_open; decremented in audio callback as samples are discarded.
    // manzo_seek does NOT reset this counter (D-04: trim fires only on manzo_open).
    startup_skip_remaining: u64,
    // Phase 3 (D-03): total track length in samples, computed at open time via a separate
    // file-API mpg123 handle + mpg123_scan().
    // -1 means unknown (e.g., CBR without LAME header that mpg123 cannot scan at open time).
    // The feed/push API does not support mpg123_scan(); a secondary handle with mpg123_open()
    // is used for duration probing while the primary handle keeps the feed API for streaming.
    total_samples: i64,
}

// SAFETY: mpg_handle is only accessed while holding the Mutex.
// cpal::Stream is Send. The raw pointer never escapes InnerState.
unsafe impl Send for InnerState {}
unsafe impl Sync for InnerState {}

impl Drop for InnerState {
    fn drop(&mut self) {
        // T-02-07: free mpg123 handle on drop to prevent resource leak
        if !self.mpg_handle.is_null() {
            unsafe {
                mpg123_sys::mpg123_delete(self.mpg_handle);
            }
            self.mpg_handle = std::ptr::null_mut();
        }
        // stream: Option<cpal::Stream> drops automatically, stopping CoreAudio
    }
}

/// Opens a file path for playback. Returns a non-null opaque handle on success,
/// or null on failure. Caller owns the handle; must call manzo_close to free.
#[no_mangle]
pub extern "C" fn manzo_open(path: *const std::os::raw::c_char) -> *mut ManzoHandle {
    // T-02-04: null-check MUST precede CStr::from_ptr — calling from_ptr(null) is UB
    if path.is_null() {
        return std::ptr::null_mut();
    }

    // T-02-03: validate the C string before any filesystem access
    let path_str = unsafe {
        match CStr::from_ptr(path).to_str() {
            Ok(s) => s,
            Err(_) => return std::ptr::null_mut(),
        }
    };

    // Read entire file into memory
    let file_data = match std::fs::read(path_str) {
        Ok(data) => data,
        Err(_) => return std::ptr::null_mut(),
    };

    // Initialise mpg123 library (idempotent after first call; safe to call per-open)
    unsafe { mpg123_sys::mpg123_init() };

    // Initialise mpg123 handle
    let mut err: libc::c_int = 0;
    let mh = unsafe { mpg123_sys::mpg123_new(std::ptr::null(), &mut err) };
    if mh.is_null() {
        return std::ptr::null_mut();
    }

    // CRITICAL: set MPG123_FORCE_FLOAT so output is always float32 — no int16 conversion
    let param_ret = unsafe {
        mpg123_sys::mpg123_param(
            mh,
            mpg123_sys::MPG123_FLAGS,
            mpg123_sys::MPG123_FORCE_FLOAT as libc::c_long,
            0.0,
        )
    };
    if param_ret != 0 {
        unsafe { mpg123_sys::mpg123_delete(mh); }
        return std::ptr::null_mut();
    }

    // Open in feed/streaming mode (feed API, not file API)
    let feed_ret = unsafe { mpg123_sys::mpg123_open_feed(mh) };
    if feed_ret != 0 {
        unsafe { mpg123_sys::mpg123_delete(mh); }
        return std::ptr::null_mut();
    }

    // Feed first chunk to bootstrap the primary (feed-API) decoder handle.
    let file_len = file_data.len();
    let first_chunk_len = FEED_CHUNK_SIZE.min(file_len);
    if first_chunk_len > 0 {
        unsafe {
            mpg123_sys::mpg123_feed(
                mh,
                file_data.as_ptr(),
                first_chunk_len,
            );
        }
    }

    // D-03: Probe total track length using a secondary mpg123 handle with the file API.
    // The feed/push API does not support mpg123_scan(); mpg123_scan() always returns
    // MPG123_ERR (-1) on feed handles. A secondary handle using mpg123_open() + mpg123_scan()
    // is the only reliable way to get duration for CBR files at open time.
    // The secondary handle is opened, scanned, and immediately closed — it is never stored.
    let total_samples: i64 = unsafe {
        let mut probe_err: libc::c_int = 0;
        let probe_mh = mpg123_sys::mpg123_new(std::ptr::null(), &mut probe_err);
        if !probe_mh.is_null() {
            mpg123_sys::mpg123_param(
                probe_mh,
                mpg123_sys::MPG123_FLAGS,
                mpg123_sys::MPG123_FORCE_FLOAT as libc::c_long,
                0.0,
            );
            let open_ret = mpg123_sys::mpg123_open(probe_mh, path);
            let result = if open_ret == 0 {
                mpg123_sys::mpg123_scan(probe_mh);
                let len = mpg123_sys::mpg123_length(probe_mh);
                if len > 0 { len as i64 } else { -1 }
            } else {
                -1
            };
            mpg123_sys::mpg123_close(probe_mh);
            mpg123_sys::mpg123_delete(probe_mh);
            result
        } else {
            -1
        }
    };

    let inner = InnerState {
        mpg_handle: mh,
        file_offset: first_chunk_len,
        file_data,
        stream: None,
        position_samples: 0,
        sample_rate: 44100,
        channels: 2,
        is_playing: false,
        volume: 1.0,
        pan: 0.0,
        eq_gains: [0.0; 10],
        eq_preamp: 0.0,
        playback_state: 3,           // STOPPED — D-02; no track playing on fresh open
        startup_skip_remaining: 529, // D-04: trim mpg123 decoder delay on first decode
        total_samples,               // D-03: cached at open time via secondary file-API probe
    };

    let arc = Arc::new(Mutex::new(inner));
    Box::into_raw(Box::new(arc)) as *mut ManzoHandle
}

/// Closes and frees the handle returned by manzo_open.
#[no_mangle]
pub extern "C" fn manzo_close(handle: *mut ManzoHandle) {
    // T-02-05: null guard
    if handle.is_null() {
        return;
    }
    // T-02-07: Box::from_raw takes ownership; drop frees Arc; InnerState::drop cleans mpg123
    unsafe {
        let arc = Box::from_raw(handle as *mut Arc<Mutex<InnerState>>);
        drop(arc);
    }
}

/// Starts or resumes playback. Returns 0 on success, non-zero on error.
#[no_mangle]
pub extern "C" fn manzo_play(handle: *mut ManzoHandle) -> i32 {
    // T-02-05 / D-04: null handle → -1
    if handle.is_null() {
        return -1;
    }

    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };

    // T-02-08: recover from poisoned mutex
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());

    // Idempotent: already playing
    if state.is_playing {
        return 0;
    }

    // Acquire cpal output device
    let host = cpal::default_host();
    let device = match host.default_output_device() {
        Some(d) => d,
        None => return -1,
    };

    let stream_config = cpal::StreamConfig {
        channels: state.channels,
        sample_rate: cpal::SampleRate(state.sample_rate),
        buffer_size: cpal::BufferSize::Default,
    };

    // Clone Arc for the audio callback closure
    let inner_clone = Arc::clone(arc);

    let stream = match device.build_output_stream(
        &stream_config,
        move |data: &mut [f32], _: &cpal::OutputCallbackInfo| {
            // T-02-08: recover from poisoned mutex; fill silence on failure
            //
            // KNOWN LIMITATION (WR-03): The mutex is held for the entire decode loop
            // below, including all mpg123_read and mpg123_feed calls. This means
            // manzo_pause and manzo_seek on the UI thread will block until the current
            // audio callback completes. On a slow path this can exceed the 8 ms frame
            // budget and produce a visible UI freeze or audio dropout.
            //
            // PHASE 5 FIX: Split InnerState into two structs:
            //   - ControlState { is_playing, file_offset, position_samples } — mutex-guarded
            //   - DecoderState { mpg_handle, file_data, ... } — audio-thread-only, no lock
            // The callback copies out control flags at entry, releases the lock, then
            // decodes without holding it. See spike 004 findings for the full pattern.
            let mut s = match inner_clone.lock() {
                Ok(s) => s,
                Err(e) => e.into_inner(),
            };

            if !s.is_playing {
                data.fill(0.0);
                return;
            }

            let mut written = 0usize;
            while written < data.len() {
                // D-04: discard startup_skip_remaining samples before writing to output.
                // Trims the 529-sample mpg123 decoder startup delay (spike-validated).
                // Only fires once per manzo_open call; manzo_seek does NOT reset this counter.
                if s.startup_skip_remaining > 0 {
                    // startup_skip_remaining counts mono-equivalent frames (529 frames = 529
                    // time-units, each frame being `channels` per-channel f32 values).
                    let remaining_frames = (data.len() - written) / s.channels as usize;
                    let skip_frames = (s.startup_skip_remaining as usize).min(remaining_frames);
                    let mut scratch = vec![0f32; skip_frames * s.channels as usize];
                    let mut discarded_bytes: libc::size_t = 0;
                    let _ret = unsafe {
                        mpg123_sys::mpg123_read(
                            s.mpg_handle,
                            scratch.as_mut_ptr() as *mut libc::c_uchar,
                            skip_frames * s.channels as usize * 4,
                            &mut discarded_bytes,
                        )
                    };
                    // Divide by bytes-per-frame (4 bytes/f32 × channels) to get frame count
                    let discarded_frames = discarded_bytes / (4 * s.channels as usize);
                    s.startup_skip_remaining = s
                        .startup_skip_remaining
                        .saturating_sub(discarded_frames as u64);
                    if discarded_frames == 0 {
                        // No progress (zero bytes decoded regardless of ret code) — feed more
                        // data to avoid infinite spin where mpg123_read returns OK with 0 bytes.
                        let start = s.file_offset;
                        let end = (start + FEED_CHUNK_SIZE).min(s.file_data.len());
                        if start < s.file_data.len() {
                            unsafe {
                                mpg123_sys::mpg123_feed(
                                    s.mpg_handle,
                                    s.file_data[start..end].as_ptr(),
                                    end - start,
                                );
                            }
                            s.file_offset = end;
                        } else {
                            // EOF during startup-skip — give up trimming, exit
                            break;
                        }
                    }
                    // Discarded frames are not added to `written` — they never reach output
                    continue;
                }

                let mut done: libc::size_t = 0;
                // f32 = 4 bytes per sample
                let buf_byte_len = (data.len() - written) * 4;

                // SAFETY: data[written..] is a valid f32 slice; cast to *mut u8 for mpg123_read.
                // MPG123_FORCE_FLOAT guarantees IEEE 754 float32 output.
                let ret = unsafe {
                    mpg123_sys::mpg123_read(
                        s.mpg_handle,
                        data[written..].as_mut_ptr() as *mut libc::c_uchar,
                        buf_byte_len,
                        &mut done,
                    )
                };

                let frames_written = done / 4; // bytes → f32 samples
                written += frames_written;
                // Track position in mono-equivalent frames
                s.position_samples += frames_written as u64 / s.channels as u64;

                if ret == mpg123_sys::MPG123_NEED_MORE as libc::c_int {
                    // Feed next chunk from file_data
                    let start = s.file_offset;
                    let end = (start + FEED_CHUNK_SIZE).min(s.file_data.len());
                    if start < s.file_data.len() {
                        unsafe {
                            mpg123_sys::mpg123_feed(
                                s.mpg_handle,
                                s.file_data[start..end].as_ptr(),
                                end - start,
                            );
                        }
                        s.file_offset = end;
                    } else if frames_written == 0 {
                        // EOF — fill remainder with silence; signal ENDED to Swift poller (D-02)
                        data[written..].fill(0.0);
                        s.is_playing = false;
                        s.playback_state = 4; // ENDED — distinct from STOPPED so Swift can auto-advance
                        break;
                    }
                } else if ret != 0 && frames_written == 0 {
                    // Unrecoverable error or EOF
                    data[written..].fill(0.0);
                    break;
                }
            }
        },
        |err| eprintln!("cpal stream error: {err}"),
        None,
    ) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("failed to build output stream: {e}");
            return -1;
        }
    };

    if let Err(e) = stream.play() {
        eprintln!("failed to start stream: {e}");
        return -1;
    }

    state.stream = Some(stream);
    state.is_playing = true;
    state.playback_state = 1; // PLAYING — D-02
    0
}

/// Pauses playback without resetting position.
#[no_mangle]
pub extern "C" fn manzo_pause(handle: *mut ManzoHandle) {
    // T-02-05: null guard
    if handle.is_null() {
        return;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());
    // Set flag — audio callback fills silence when is_playing is false.
    // Stream stays alive to allow resume without rebuilding the cpal pipeline.
    state.is_playing = false;
    state.playback_state = 2; // PAUSED — D-02
}

/// Stops playback and resets position to start.
#[no_mangle]
pub extern "C" fn manzo_stop(handle: *mut ManzoHandle) {
    // T-02-05: null guard
    if handle.is_null() {
        return;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());

    state.is_playing = false;
    state.playback_state = 3; // STOPPED — D-02
    state.position_samples = 0;

    // Drop stream to stop CoreAudio
    state.stream = None;

    // Reset decoder to beginning: re-open feed mode and re-feed first chunk
    let first_chunk_len = FEED_CHUNK_SIZE.min(state.file_data.len());
    if first_chunk_len > 0 {
        let feed_ret = unsafe { mpg123_sys::mpg123_open_feed(state.mpg_handle) };
        if feed_ret == 0 {
            unsafe {
                mpg123_sys::mpg123_feed(
                    state.mpg_handle,
                    state.file_data.as_ptr(),
                    first_chunk_len,
                );
            }
            state.file_offset = first_chunk_len;
        } else {
            // Open-feed reset failed; leave offset at 0 — next play will rebuild stream
            state.file_offset = 0;
            eprintln!("manzo_stop: mpg123_open_feed reset failed ({feed_ret})");
        }
    } else {
        state.file_offset = 0;
    }
}

/// Seeks to `position_ms` milliseconds from start. Returns 0 on success.
#[no_mangle]
pub extern "C" fn manzo_seek(handle: *mut ManzoHandle, position_ms: u64) -> i32 {
    // T-02-05 / D-04: null handle → -1
    if handle.is_null() {
        return -1;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());

    let sample_pos = (position_ms * state.sample_rate as u64) / 1000;
    let mut input_byte_offset: libc::off_t = 0;

    // mpg123_feedseek returns the new sample position (>= 0) on success, negative on error
    let result = unsafe {
        mpg123_sys::mpg123_feedseek(
            state.mpg_handle,
            sample_pos as libc::off_t,
            libc::SEEK_SET,
            &mut input_byte_offset,
        )
    };

    if result < 0 {
        return -1;
    }

    // Update file offset to byte position returned by feedseek.
    // Guard against a negative input_byte_offset: casting a negative i64 to usize
    // wraps to a huge value, and the subsequent .min() would silently clamp to EOF.
    let byte_offset = if input_byte_offset >= 0 {
        (input_byte_offset as usize).min(state.file_data.len())
    } else {
        eprintln!("manzo_seek: unexpected negative input_byte_offset {input_byte_offset}");
        0
    };
    state.file_offset = byte_offset;

    // Feed a chunk from the new position so the decoder has data
    let end = (state.file_offset + FEED_CHUNK_SIZE).min(state.file_data.len());
    if state.file_offset < state.file_data.len() {
        unsafe {
            mpg123_sys::mpg123_feed(
                state.mpg_handle,
                state.file_data[state.file_offset..end].as_ptr(),
                end - state.file_offset,
            );
        }
        state.file_offset = end;
    }

    state.position_samples = sample_pos;
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
    // T-02-05: null guard
    if handle.is_null() {
        return;
    }
    if gains.is_null() {
        return;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());
    // SAFETY: caller guarantees gains points to at least 10 f32 values per the API contract
    let gain_slice = unsafe { std::slice::from_raw_parts(gains, 10) };
    // Clamp to documented ±12.0 dB range; clamp also maps NaN to the boundary value,
    // preventing NaN/Inf from propagating into the Phase 4 biquad DSP chain.
    for (dst, &src) in state.eq_gains.iter_mut().zip(gain_slice.iter()) {
        *dst = src.clamp(-12.0_f32, 12.0_f32);
    }
    state.eq_preamp = preamp.clamp(-12.0_f32, 12.0_f32);
    // Phase 4 wires these into the DSP chain
}

/// Sets master volume. `volume` is in range [0.0, 1.0].
#[no_mangle]
pub extern "C" fn manzo_set_volume(handle: *mut ManzoHandle, volume: f32) {
    // T-02-05: null guard
    if handle.is_null() {
        return;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());
    state.volume = volume;
    // Phase 4 wires into the DSP chain
}

/// Sets stereo pan. `pan` is in range [-1.0, 1.0]; 0.0 = center.
#[no_mangle]
pub extern "C" fn manzo_set_pan(handle: *mut ManzoHandle, pan: f32) {
    // T-02-05: null guard
    if handle.is_null() {
        return;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());
    state.pan = pan;
    // Phase 4 wires into the DSP chain
}

/// Returns the current playback position in milliseconds.
#[no_mangle]
pub extern "C" fn manzo_get_position(handle: *mut ManzoHandle) -> u64 {
    // T-02-05: null guard → return 0
    if handle.is_null() {
        return 0;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let state = arc.lock().unwrap_or_else(|e| e.into_inner());
    if state.sample_rate == 0 {
        return 0;
    }
    // Convert samples to milliseconds
    (state.position_samples * 1000) / state.sample_rate as u64
}

/// Returns the current playback state as an i32 (D-02):
///   1 = PLAYING — audio callback actively writing PCM
///   2 = PAUSED  — manzo_pause was called; callback fills silence
///   3 = STOPPED — manzo_stop was called, or handle is fresh / never played
///   4 = ENDED   — natural EOF reached by audio callback (mpg123 returned DONE)
/// Returns 3 (STOPPED) when handle is null — safe sentinel.
#[no_mangle]
pub extern "C" fn manzo_get_state(handle: *mut ManzoHandle) -> i32 {
    // T-02-05 / D-02: null guard returns STOPPED sentinel
    if handle.is_null() {
        return 3;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let state = arc.lock().unwrap_or_else(|e| e.into_inner());
    state.playback_state
}

/// Returns total track duration in milliseconds (D-03), or 0 if unavailable.
/// Uses `total_samples` cached at open time via a secondary file-API mpg123 handle +
/// `mpg123_scan()`. The feed/push API used by the primary handle does not support
/// `mpg123_scan()`, so a secondary probe handle is used at open time (see manzo_open).
/// Returns 0 when: handle is null, sample_rate is 0, or total_samples == -1 (unknown).
#[no_mangle]
pub extern "C" fn manzo_get_duration(handle: *mut ManzoHandle) -> u64 {
    // T-02-05: null guard
    if handle.is_null() {
        return 0;
    }
    let arc = unsafe { &*(handle as *mut Arc<Mutex<InnerState>>) };
    let state = arc.lock().unwrap_or_else(|e| e.into_inner());
    if state.sample_rate == 0 {
        return 0;
    }
    // total_samples == -1 means unknown (CBR without LAME header mpg123 could not scan)
    if state.total_samples < 0 {
        return 0;
    }
    (state.total_samples as u64 * 1000) / state.sample_rate as u64
}

/// Fills `out_buf` with `count` float32 FFT magnitude values (range [0.0, 1.0]).
/// Returns number of values written. `out_buf` must be at least `count` elements.
#[no_mangle]
pub extern "C" fn manzo_get_spectrum(
    handle: *mut ManzoHandle,
    out_buf: *mut f32,
    count: usize,
) -> usize {
    // T-02-06: guard against null buffer and zero count — write exactly count f32 zeros
    if out_buf.is_null() || count == 0 {
        return 0;
    }
    // D-01: zero-fill the buffer. FFT pipeline is Phase 7; buffer must always be written.
    // write_bytes with val=0 on f32 produces 0.0 (IEEE 754: all-zero bytes = positive zero).
    unsafe {
        std::ptr::write_bytes(out_buf, 0, count);
    }
    let _ = handle; // unused until Phase 7 implements the FFT pipeline
    count
}

// ---------------------------------------------------------------------------
// Unit tests — cargo test must pass
// ---------------------------------------------------------------------------
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn play_null_returns_minus_one() {
        let result = manzo_play(std::ptr::null_mut());
        assert_eq!(result, -1, "manzo_play with null handle must return -1");
    }

    #[test]
    fn seek_null_returns_minus_one() {
        let result = manzo_seek(std::ptr::null_mut(), 1000);
        assert_eq!(result, -1, "manzo_seek with null handle must return -1");
    }

    #[test]
    fn stub_get_position_returns_zero() {
        let result = manzo_get_position(std::ptr::null_mut());
        assert_eq!(result, 0, "manzo_get_position with null handle must return 0");
    }

    #[test]
    fn spectrum_null_buf_returns_zero() {
        let result = manzo_get_spectrum(std::ptr::null_mut(), std::ptr::null_mut(), 512);
        assert_eq!(result, 0, "null out_buf must return 0");
    }

    #[test]
    fn spectrum_writes_zeros() {
        let mut buf = vec![f32::NAN; 16];
        let result = manzo_get_spectrum(std::ptr::null_mut(), buf.as_mut_ptr(), 16);
        assert_eq!(result, 16);
        assert!(
            buf.iter().all(|&v| v == 0.0_f32),
            "spectrum must zero-fill buffer"
        );
    }

    #[test]
    fn get_state_null_returns_stopped() {
        let result = manzo_get_state(std::ptr::null_mut());
        assert_eq!(
            result, 3,
            "manzo_get_state with null handle must return 3 (STOPPED) — D-02"
        );
    }

    #[test]
    fn get_duration_null_returns_zero() {
        let result = manzo_get_duration(std::ptr::null_mut());
        assert_eq!(
            result, 0,
            "manzo_get_duration with null handle must return 0"
        );
    }
}
