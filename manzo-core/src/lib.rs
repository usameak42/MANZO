//! manzo-core — Rust audio/DSP core for MANZO
//! FFI surface: 11 C-callable functions, generated header via cbindgen
//! Phase 2: Real MP3 decode + CoreAudio output pipeline

pub mod eq10;
use eq10::{Eq10State, eq10_processf, eq10_db2gain};

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::sync::{Arc, Mutex, mpsc};
use std::ffi::CStr;
use rustfft::{FftPlanner, num_complex::Complex};
use std::sync::atomic::{AtomicUsize, AtomicBool, AtomicI32, Ordering};

/// Opaque handle returned by manzo_open and passed to all subsequent calls.
/// The real state lives behind a raw pointer cast to Arc<Mutex<InnerState>>.
#[repr(C)]
pub struct ManzoHandle {
    _private: [u8; 0],
}

/// Feed chunk size in bytes — validated pattern from spike 003; do not change.
const FEED_CHUNK_SIZE: usize = 4096;

enum StreamSource { File, Url }

/// Lock-free control flags shared between the UI thread and the audio callback.
/// Separated from InnerState so manzo_pause/manzo_stop never need to acquire
/// the decoder mutex — eliminating the WR-03 UI freeze on pause.
struct HandleInner {
    inner: Mutex<InnerState>,
    /// True while the audio callback should decode and output PCM.
    control_playing: AtomicBool,
    /// Current playback state: 1=PLAYING, 2=PAUSED, 3=STOPPED, 4=ENDED.
    control_state: AtomicI32,
}

/// Internal playback state, protected by Arc<Mutex<>> per D-02.
struct InnerState {
    mpg_handle: *mut mpg123_sys::mpg123_handle,
    file_data: Vec<u8>,
    file_offset: usize,
    stream: Option<cpal::Stream>,
    position_samples: u64,
    sample_rate: u32,
    channels: u16,
    // Phase 4 DSP fields
    eq_gains: [f32; 10],
    eq_preamp: f32,
    // Phase 4: pre-converted preamp scalar (avoids powf in audio callback hot path)
    preamp_gain_linear: f32,
    // Phase 4: per-channel biquad EQ state (one Eq10State per channel, per D-06)
    eq_l: Eq10State,
    eq_r: Eq10State,
    // Phase 4: dynamic limiter toggle; default true per D-04
    config_eq_limiter: bool,
    // Phase 7: FFT pipeline (D-07, D-10)
    // Circular sample buffer: stores the last 1024 decoded float32 mono-downmixed samples.
    // The audio callback fills this ring buffer; FFT reads the last 1024 samples every 512 new samples.
    fft_sample_buf: [f32; 1024],
    fft_sample_pos: usize,       // write position in fft_sample_buf (0..1023, wraps)
    fft_samples_since_last: usize, // count of new samples since last FFT run; FFT fires every 512

    // Double-buffer for 75 bar magnitudes (D-10).
    // Audio callback writes into fft_bufs[fft_write_idx]; then atomically publishes fft_read_idx.
    // manzo_get_spectrum reads fft_bufs[fft_read_idx.load(Relaxed)] via try_lock (Option A, D-10).
    fft_bufs: [[f32; 75]; 2],
    fft_write_idx: usize,        // which slot the callback is writing (0 or 1); not atomic — callback-only
    fft_read_idx: AtomicUsize, // atomically published after each FFT run
    // Phase 4: volume ramp state (D-03) — target written by manzo_set_volume
    target_volume: f32,
    current_volume: f32,
    vol_ramp_remaining: u32,
    // Phase 4: pan ramp state (D-03) — target written by manzo_set_pan
    target_pan: f32,
    current_pan: f32,
    pan_ramp_remaining: u32,
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
    // Phase 10.1: discriminates file vs URL stream — gates feed path and seek behavior
    stream_source: StreamSource,
    // Phase 10.1: URL stream receiver — chunks pushed by curl reader thread, consumed by audio callback
    stream_rx: Option<mpsc::Receiver<Vec<u8>>>,
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
        eq_gains: [0.0; 10],
        eq_preamp: 0.0,
        preamp_gain_linear: 1.0_f32,           // 0 dB = unity gain
        eq_l: Eq10State::new(44100.0),         // 44.1 kHz — matches sample_rate field above
        eq_r: Eq10State::new(44100.0),
        config_eq_limiter: true,               // dynamic limiter enabled by default (D-04)
        fft_sample_buf: [0.0f32; 1024],
        fft_sample_pos: 0,
        fft_samples_since_last: 0,
        fft_bufs: [[0.0f32; 75]; 2],
        fft_write_idx: 0,
        fft_read_idx: AtomicUsize::new(0),
        target_volume: 1.0,
        current_volume: 1.0,
        vol_ramp_remaining: 0,
        target_pan: 0.0,
        current_pan: 0.0,
        pan_ramp_remaining: 0,
        startup_skip_remaining: 529, // D-04: trim mpg123 decoder delay on first decode
        total_samples,               // D-03: cached at open time via secondary file-API probe
        stream_source: StreamSource::File,
        stream_rx: None,
    };

    let arc = Arc::new(HandleInner {
        inner: Mutex::new(inner),
        control_playing: AtomicBool::new(false),
        control_state: AtomicI32::new(3), // STOPPED on fresh open
    });
    Box::into_raw(Box::new(arc)) as *mut ManzoHandle
}

/// Opens a YouTube or streaming URL for playback via yt-dlp + ffmpeg.
/// Non-blocking: resolves the CDN URL synchronously (~1–2 s), then returns immediately.
/// A background thread transcodes via ffmpeg pipe:1 → MP3 → mpg123 feed buffer.
/// Seek is a no-op for URL handles. Duration returns 0 (unknown).
#[no_mangle]
pub extern "C" fn manzo_open_url(
    url: *const std::os::raw::c_char,
    ytdlp_path: *const std::os::raw::c_char,
    ffmpeg_path: *const std::os::raw::c_char,
) -> *mut ManzoHandle {
    if url.is_null() || ytdlp_path.is_null() || ffmpeg_path.is_null() {
        return std::ptr::null_mut();
    }
    let url_str = unsafe {
        match CStr::from_ptr(url).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => return std::ptr::null_mut(),
        }
    };
    let ytdlp_str = unsafe {
        match CStr::from_ptr(ytdlp_path).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => return std::ptr::null_mut(),
        }
    };
    let ffmpeg_str = unsafe {
        match CStr::from_ptr(ffmpeg_path).to_str() {
            Ok(s) => s.to_owned(),
            Err(_) => return std::ptr::null_mut(),
        }
    };

    // Resolve CDN audio URL via yt-dlp (synchronous, ~1–2 s)
    let output = match std::process::Command::new(&ytdlp_str)
        .args([
            "--get-url",
            "--format", "bestaudio[ext=mp3]/bestaudio[ext=m4a]/bestaudio",
            "--no-playlist",
            url_str.as_str(),
        ])
        .output()
    {
        Ok(o) => o,
        Err(_) => return std::ptr::null_mut(),
    };
    if !output.status.success() {
        eprintln!("manzo_open_url: yt-dlp exited with error: {}",
            String::from_utf8_lossy(&output.stderr).trim());
        return std::ptr::null_mut();
    }
    // Some formats return multiple lines (DASH manifests); take only the first CDN URL.
    let cdn_url = match std::str::from_utf8(&output.stdout) {
        Ok(s) => s.lines().next().unwrap_or("").trim().to_owned(),
        Err(_) => return std::ptr::null_mut(),
    };
    if cdn_url.is_empty() {
        return std::ptr::null_mut();
    }
    if cdn_url.contains("mime=audio/mp4") || cdn_url.ends_with(".m4a") {
        eprintln!("manzo_open_url: WARNING — CDN URL is m4a/mp4; mpg123 may struggle with this format");
    }
    eprintln!("manzo_open_url: resolved CDN URL (first 120 chars): {}", &cdn_url[..cdn_url.len().min(120)]);

    // Init mpg123 in feed mode — identical to manzo_open
    unsafe { mpg123_sys::mpg123_init() };
    let mut err: libc::c_int = 0;
    let mh = unsafe { mpg123_sys::mpg123_new(std::ptr::null(), &mut err) };
    if mh.is_null() {
        return std::ptr::null_mut();
    }
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
    if unsafe { mpg123_sys::mpg123_open_feed(mh) } != 0 {
        unsafe { mpg123_sys::mpg123_delete(mh); }
        return std::ptr::null_mut();
    }

    // Spawn reader thread: ffmpeg (transcode any format → MP3) → mpsc channel
    // curl alone can't transcode; m4a/webm from YouTube needs ffmpeg to produce
    // MP3 that mpg123 can decode.
    let (tx, rx) = mpsc::channel::<Vec<u8>>();
    std::thread::spawn(move || {
        let mut child = match std::process::Command::new(&ffmpeg_str)
            .args(["-v", "quiet", "-i", cdn_url.as_str(),
                   "-vn", "-f", "mp3", "-ab", "128k", "pipe:1"])
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::null())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => { eprintln!("manzo_open_url: ffmpeg spawn failed: {}", e); return; },
        };
        let mut stdout = match child.stdout.take() {
            Some(s) => s,
            None => return,
        };
        use std::io::Read;
        let mut buf = vec![0u8; FEED_CHUNK_SIZE];
        loop {
            match stdout.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    if tx.send(buf[..n].to_vec()).is_err() {
                        break;
                    }
                }
                Err(_) => break,
            }
        }
        let _ = child.wait();
    });

    let inner = InnerState {
        mpg_handle: mh,
        file_data: Vec::new(),
        file_offset: 0,
        stream: None,
        position_samples: 0,
        sample_rate: 44100,
        channels: 2,
        eq_gains: [0.0; 10],
        eq_preamp: 0.0,
        preamp_gain_linear: 1.0,
        eq_l: Eq10State::new(44100.0),
        eq_r: Eq10State::new(44100.0),
        config_eq_limiter: true,
        fft_sample_buf: [0.0f32; 1024],
        fft_sample_pos: 0,
        fft_samples_since_last: 0,
        fft_bufs: [[0.0f32; 75]; 2],
        fft_write_idx: 0,
        fft_read_idx: AtomicUsize::new(0),
        target_volume: 1.0,
        current_volume: 1.0,
        vol_ramp_remaining: 0,
        target_pan: 0.0,
        current_pan: 0.0,
        pan_ramp_remaining: 0,
        startup_skip_remaining: 0, // no decoder startup delay for URL streams
        total_samples: -1,         // duration unknown for streams
        stream_source: StreamSource::Url,
        stream_rx: Some(rx),
    };

    let arc = Arc::new(HandleInner {
        inner: Mutex::new(inner),
        control_playing: AtomicBool::new(false),
        control_state: AtomicI32::new(3),
    });
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
        let arc = Box::from_raw(handle as *mut Arc<HandleInner>);
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

    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };

    // Idempotent: already playing — check atomic without taking the decoder lock
    if arc.control_playing.load(Ordering::Relaxed) {
        return 0;
    }

    // T-02-08: recover from poisoned mutex
    let mut state = arc.inner.lock().unwrap_or_else(|e| e.into_inner());

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
            // WR-03 fix: check control_playing atomically BEFORE acquiring the decoder mutex.
            // manzo_pause stores false here without ever locking — no UI thread blocking.
            if !inner_clone.control_playing.load(Ordering::Relaxed) {
                data.fill(0.0);
                return;
            }

            // Acquire decoder mutex only on the decode path.
            let mut s = match inner_clone.inner.lock() {
                Ok(s) => s,
                Err(e) => e.into_inner(),
            };

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
                    match s.stream_source {
                        StreamSource::File => {
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
                                // EOF — fill remainder with silence; signal ENDED (D-02)
                                data[written..].fill(0.0);
                                inner_clone.control_playing.store(false, Ordering::Relaxed);
                                inner_clone.control_state.store(4, Ordering::Relaxed);
                                break;
                            }
                        }
                        StreamSource::Url => {
                            match s.stream_rx.as_ref().map(|rx| rx.try_recv()) {
                                Some(Ok(chunk)) => {
                                    unsafe {
                                        mpg123_sys::mpg123_feed(
                                            s.mpg_handle,
                                            chunk.as_ptr(),
                                            chunk.len(),
                                        );
                                    }
                                }
                                Some(Err(mpsc::TryRecvError::Empty)) => {
                                    // Network stall — output silence this callback cycle
                                    if frames_written == 0 {
                                        data[written..].fill(0.0);
                                        break;
                                    }
                                }
                                Some(Err(mpsc::TryRecvError::Disconnected)) | None => {
                                    // curl exited — stream ended
                                    data[written..].fill(0.0);
                                    inner_clone.control_playing.store(false, Ordering::Relaxed);
                                    inner_clone.control_state.store(4, Ordering::Relaxed);
                                    break;
                                }
                            }
                        }
                    }
                } else if ret != 0 && frames_written == 0 {
                    // Unrecoverable error or EOF
                    data[written..].fill(0.0);
                    break;
                }
            }

            // ── Phase 4 DSP chain (D-01) ─────────────────────────────────────────
            // Chain: preamp → EQ L (idx=0) → EQ R (idx=1) → vol/pan ramp
            // WR-03: mutex is held for this entire block (Phase 5 will restructure locking)

            // 1. Preamp: scalar multiply on entire interleaved buffer before EQ (D-01)
            //    Pre-converted in manzo_set_eq to avoid powf here (Pitfall 6 / RESEARCH.md)
            let preamp = s.preamp_gain_linear;
            if preamp != 1.0_f32 {
                for sample in data.iter_mut() {
                    *sample *= preamp;
                }
            }

            // 2 & 3. EQ per channel + dynamic limiter (D-06: called twice, L then R)
            //    sz = FRAMES not samples (Pitfall 5); channels is always 2 for stereo MP3
            //    Copy config_eq_limiter (bool: Copy) before mutable borrows of eq_l/eq_r
            let num_frames = data.len() / s.channels as usize;
            let limiter = s.config_eq_limiter;
            eq10_processf(&mut s.eq_l, data, num_frames, 0, 2, limiter);  // L
            eq10_processf(&mut s.eq_r, data, num_frames, 1, 2, limiter);  // R

            // 4. Volume/pan linear ramp per frame (D-03; ~10 ms ramp at 44.1 kHz)
            //    Linear pan law: L_gain = (1-pan).clamp(0,1), R_gain = (1+pan).clamp(0,1)
            //    Assumption A1: linear split (not constant-power); Phase 5 can upgrade.
            for frame in 0..num_frames {
                // Advance volume ramp
                if s.vol_ramp_remaining > 0 {
                    let step = (s.target_volume - s.current_volume) / s.vol_ramp_remaining as f32;
                    s.current_volume += step;
                    s.vol_ramp_remaining -= 1;
                } else {
                    s.current_volume = s.target_volume;
                }
                // Advance pan ramp
                if s.pan_ramp_remaining > 0 {
                    let step = (s.target_pan - s.current_pan) / s.pan_ramp_remaining as f32;
                    s.current_pan += step;
                    s.pan_ramp_remaining -= 1;
                } else {
                    s.current_pan = s.target_pan;
                }
                let l_gain = (1.0 - s.current_pan).clamp(0.0, 1.0);
                let r_gain = (1.0 + s.current_pan).clamp(0.0, 1.0);
                let l = frame * 2;
                let r = frame * 2 + 1;
                data[l] *= s.current_volume * l_gain;
                data[r] *= s.current_volume * r_gain;
            }
            // ── End Phase 4 DSP chain ─────────────────────────────────────────────

            // ── Phase 7: FFT pipeline (D-09) ─────────────────────────────────────
            // Accumulate mono-downmixed samples into circular buffer.
            // FFT fires every 512 new samples on the last 1024 (D-07: stride=512, window=1024).
            // No windowing applied (D-08: Winamp-faithful).
            {
                let num_frames_fft = data.len() / s.channels as usize;
                for frame_idx in 0..num_frames_fft {
                    // Mono downmix: average L+R (channels=2 always for stereo MP3)
                    let l = data[frame_idx * 2];
                    let r = data[frame_idx * 2 + 1];
                    let mono = (l + r) * 0.5;
                    let pos = s.fft_sample_pos;
                    s.fft_sample_buf[pos] = mono;
                    s.fft_sample_pos = (pos + 1) & 1023; // power-of-2 wrap
                    s.fft_samples_since_last += 1;
                }

                if s.fft_samples_since_last >= 512 {
                    s.fft_samples_since_last = 0;

                    // Copy the last 1024 samples from the circular buffer in time order.
                    // fft_sample_pos is the NEXT write position, so the oldest sample
                    // is at fft_sample_pos (the slot just overwritten is position-1, the
                    // oldest un-overwritten slot is fft_sample_pos).
                    let mut fft_input: Vec<Complex<f32>> = Vec::with_capacity(1024);
                    let start = s.fft_sample_pos; // oldest sample position
                    for i in 0..1024usize {
                        let idx = (start + i) & 1023;
                        fft_input.push(Complex { re: s.fft_sample_buf[idx], im: 0.0 });
                    }

                    // Run FFT (1024-point, no windowing — D-08)
                    let mut planner = FftPlanner::new();
                    let fft = planner.plan_fft_forward(1024);
                    fft.process(&mut fft_input);

                    // Compute 75 bar magnitudes (D-04): bar i averages FFT bins [i*4, i*4+3]
                    // Magnitude = sqrt(re² + im²). Normalize to [0.0, 1.0] then quantize to
                    // 16 levels (D-05): v = (mag_normalized * 15.0).clamp(0.0, 15.0) as u8;
                    // h = v as f32 / 15.0 — the Metal shader receives this normalized height.
                    //
                    // Normalization reference: peak magnitude for a full-scale 1.0 sine =
                    // 512.0 (FFT size / 2). We normalize against a slightly lower value (256.0)
                    // to allow overload to saturate at 1.0 for loud signals — log-like feel
                    // without log math. Claude's discretion (CONTEXT.md discretion section).
                    let write_slot = s.fft_write_idx;
                    for bar in 0..75usize {
                        let bin_start = bar * 4;
                        let bin_end = bin_start + 4;
                        let avg_mag: f32 = fft_input[bin_start..bin_end]
                            .iter()
                            .map(|c| (c.re * c.re + c.im * c.im).sqrt())
                            .sum::<f32>()
                            / 4.0;
                        // Normalize: 256.0 = half of FFT size — chosen so full-scale sine
                        // saturates at 1.0 but typical music content uses 0.3–0.8 of range.
                        let normalized = (avg_mag / 256.0).clamp(0.0, 1.0);
                        // Quantize to 16 levels (D-05) and re-normalize to [0.0, 1.0]
                        let level = (normalized * 15.0).round() as u8;
                        s.fft_bufs[write_slot][bar] = level as f32 / 15.0;
                    }

                    // Atomically publish: fft_read_idx points at the freshly written slot.
                    // Relaxed ordering is sufficient — Swift reads are observational only;
                    // a stale read causes one visual frame to show the previous buffer, which
                    // is imperceptible at 60fps. Acquire/Release would only be needed if the
                    // reader needed to observe the buffer writes themselves via the atomic,
                    // but since both sides hold the same mutex (or try_lock skips), this is safe.
                    s.fft_read_idx.store(write_slot, Ordering::Relaxed);

                    // Flip write slot for next FFT run (0 ↔ 1)
                    s.fft_write_idx = 1 - write_slot;
                }
            }
            // ── End Phase 7 FFT pipeline ──────────────────────────────────────────
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
    // Set atomics while still holding the decoder lock so the callback cannot observe
    // control_playing=true before state.stream is stored.
    arc.control_playing.store(true, Ordering::Relaxed);
    arc.control_state.store(1, Ordering::Relaxed); // PLAYING — D-02
    0
}

/// Pauses playback without resetting position.
/// WR-03 fix: stores to atomics only — never acquires the decoder mutex.
#[no_mangle]
pub extern "C" fn manzo_pause(handle: *mut ManzoHandle) {
    if handle.is_null() {
        return;
    }
    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };
    // Atomic store — callback sees false on next invocation and fills silence.
    // Stream stays alive so resume can restart without rebuilding the cpal pipeline.
    arc.control_playing.store(false, Ordering::Relaxed);
    arc.control_state.store(2, Ordering::Relaxed); // PAUSED — D-02
}

/// Stops playback and resets position to start.
#[no_mangle]
pub extern "C" fn manzo_stop(handle: *mut ManzoHandle) {
    // T-02-05: null guard
    if handle.is_null() {
        return;
    }
    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };
    // Signal the callback to stop without waiting for the decoder lock.
    arc.control_playing.store(false, Ordering::Relaxed);
    arc.control_state.store(3, Ordering::Relaxed); // STOPPED — D-02
    // Now acquire the decoder mutex to reset decoder position and drop the stream.
    let mut state = arc.inner.lock().unwrap_or_else(|e| e.into_inner());
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
    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };
    let mut state = arc.inner.lock().unwrap_or_else(|e| e.into_inner());

    if matches!(state.stream_source, StreamSource::Url) {
        return 0; // seek is meaningless on a live stream
    }

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
    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };
    let mut state = arc.inner.lock().unwrap_or_else(|e| e.into_inner());
    // SAFETY: caller guarantees gains points to at least 10 f32 values per the API contract
    let gain_slice = unsafe { std::slice::from_raw_parts(gains, 10) };
    // Collect clamped dB values first to avoid holding iter_mut borrow across eq_l/eq_r access
    let clamped: [f32; 10] = std::array::from_fn(|i| gain_slice[i].clamp(-12.0_f32, 12.0_f32));
    for (i, clamped_db) in clamped.iter().enumerate() {
        state.eq_gains[i] = *clamped_db;
        // D-05: shifted-linear gain; 0 dB → 0.0, +12 dB → ≈2.981, -12 dB → ≈-0.749
        let gain_linear = eq10_db2gain(*clamped_db as f64);
        state.eq_l.band[i].gain = gain_linear;
        state.eq_r.band[i].gain = gain_linear;
    }
    // D-03: preamp stored as dB for record; pre-converted to linear for hot path (Pitfall 6)
    state.eq_preamp = preamp.clamp(-12.0_f32, 12.0_f32);
    state.preamp_gain_linear = 10_f32.powf(state.eq_preamp / 20.0);
}

/// Sets master volume. `volume` is in range [0.0, 1.0].
#[no_mangle]
pub extern "C" fn manzo_set_volume(handle: *mut ManzoHandle, volume: f32) {
    // T-02-05: null guard
    if handle.is_null() {
        return;
    }
    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };
    let mut state = arc.inner.lock().unwrap_or_else(|e| e.into_inner());
    // D-03: write target and reset ramp counter; audio callback linearly interpolates
    state.target_volume = volume.clamp(0.0_f32, 1.0_f32);
    state.vol_ramp_remaining = 441;  // ~10 ms at 44.1 kHz (D-03)
}

/// Sets stereo pan. `pan` is in range [-1.0, 1.0]; 0.0 = center.
#[no_mangle]
pub extern "C" fn manzo_set_pan(handle: *mut ManzoHandle, pan: f32) {
    // T-02-05: null guard
    if handle.is_null() {
        return;
    }
    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };
    let mut state = arc.inner.lock().unwrap_or_else(|e| e.into_inner());
    // D-03: write target and reset ramp counter; audio callback linearly interpolates
    state.target_pan = pan.clamp(-1.0_f32, 1.0_f32);
    state.pan_ramp_remaining = 441;  // ~10 ms at 44.1 kHz (D-03)
}

/// Returns the current playback position in milliseconds.
#[no_mangle]
pub extern "C" fn manzo_get_position(handle: *mut ManzoHandle) -> u64 {
    // T-02-05: null guard → return 0
    if handle.is_null() {
        return 0;
    }
    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };
    let state = arc.inner.lock().unwrap_or_else(|e| e.into_inner());
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
    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };
    arc.control_state.load(Ordering::Relaxed)
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
    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };
    let state = arc.inner.lock().unwrap_or_else(|e| e.into_inner());
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
    // T-02-06: guard against null buffer and zero count
    if out_buf.is_null() || count == 0 {
        return 0;
    }
    if handle.is_null() {
        // Null handle: zero-fill (safe sentinel — no FFT data available)
        unsafe { std::ptr::write_bytes(out_buf, 0, count); }
        return count;
    }

    let arc = unsafe { &*(handle as *mut Arc<HandleInner>) };

    // Option A (D-10 implementation): try_lock to avoid blocking the Swift main thread.
    // The audio callback holds the mutex for ~0.3ms every ~11ms (512-sample callback at 44.1kHz).
    // On lock contention (rare), return stale data from the previously published read slot.
    // This is preferable to blocking the render thread for one frame.
    let n = count.min(75);
    match arc.inner.try_lock() {
        Ok(state) => {
            // Lock acquired: read the latest published read slot
            let read_slot = state.fft_read_idx.load(Ordering::Relaxed);
            let src = &state.fft_bufs[read_slot][..n];
            unsafe {
                std::ptr::copy_nonoverlapping(src.as_ptr(), out_buf, n);
                // Zero any remaining slots if count > 75
                if count > n {
                    std::ptr::write_bytes(out_buf.add(n), 0, count - n);
                }
            }
            count
        }
        Err(_) => {
            // Lock busy: zero-fill this frame (stale-data fallback)
            // Swift will read fresh data on the next CADisplayLink tick (16ms away)
            unsafe { std::ptr::write_bytes(out_buf, 0, count); }
            count
        }
    }
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
    fn spectrum_null_handle_writes_zeros() {
        // Null handle with valid buffer: zero-fill (safe sentinel, not a crash)
        let mut buf = vec![f32::NAN; 16];
        let result = manzo_get_spectrum(std::ptr::null_mut(), buf.as_mut_ptr(), 16);
        assert_eq!(result, 16, "null handle must return count");
        assert!(buf.iter().all(|&v| v == 0.0_f32), "null handle must zero-fill buffer");
    }

    #[test]
    fn spectrum_returns_75_values() {
        // InnerState default: fft_bufs all zeros, fft_read_idx = 0
        // manzo_get_spectrum with count=75 on a freshly opened handle should return 75 zeros.
        // We open with a fake path (will fail) — test the null-handle path only (no audio device needed).
        // Full live-FFT test requires an audio device; omit for CI safety (per Phase 4 pattern).
        let mut buf = vec![0.0f32; 75];
        let result = manzo_get_spectrum(std::ptr::null_mut(), buf.as_mut_ptr(), 75);
        assert_eq!(result, 75, "must return exactly 75 values for count=75");
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
