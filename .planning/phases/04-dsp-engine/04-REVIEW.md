---
phase: 04-dsp-engine
reviewed: 2026-04-23T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - manzo-core/src/eq10.rs
  - manzo-core/src/lib.rs
  - manzo-core/tests/integration_test.rs
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 4: Code Review Report

**Reviewed:** 2026-04-23
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Three files reviewed: the 10-band biquad EQ port (`eq10.rs`), the FFI/playback core (`lib.rs`), and the integration test suite (`integration_test.rs`). The EQ math itself is a faithful Rust port of `eq10dsp.cpp` — coefficient formulas, denormal fix, dual biquad sets, and limiter decay are all correct. No critical issues were found.

Three warnings concern correctness gaps in the playback state machine: gapless trim not re-armed after stop, and EQ/ramp sample-rate values hardcoded to 44100 Hz. Three info items address variable naming, IIR state reset, and a misleading comment about `frames_written`.

---

## Warnings

### WR-01: `manzo_stop` resets the mpg123 decoder but does not re-arm the 529-sample startup trim

**File:** `manzo-core/src/lib.rs:486`
**Issue:** `manzo_stop` calls `mpg123_open_feed` on the primary handle (line 486), which fully re-initializes the mpg123 decoder internal state. After re-initialization the decoder will again produce its 529-sample startup artifact on the next decode call. However, `startup_skip_remaining` is NOT reset to 529 — it stays at 0 after the first play. Every stop→play cycle after the initial open will output those 529 "glitch" samples (~12 ms) directly to CoreAudio, violating the D-04 gapless contract. The design comment on line 55 ("trim fires only on manzo_open") pre-dates the stop-path decoder reset and no longer accurately describes when the trim must fire.

**Fix:**
```rust
// In manzo_stop, after the successful mpg123_open_feed block:
if feed_ret == 0 {
    unsafe {
        mpg123_sys::mpg123_feed(
            state.mpg_handle,
            state.file_data.as_ptr(),
            first_chunk_len,
        );
    }
    state.file_offset = first_chunk_len;
    // Re-arm the startup trim — mpg123_open_feed resets decoder state,
    // so the 529-sample priming delay will reappear on the next decode.
    state.startup_skip_remaining = 529;
} else { ... }
```
Also update the comment on line 55 from "trim fires only on manzo_open" to "trim fires on manzo_open and after any mpg123_open_feed reset (i.e. manzo_stop)."

---

### WR-02: `Eq10State` biquad coefficients hardcoded to 44100 Hz regardless of actual file sample rate

**File:** `manzo-core/src/lib.rs:193-194`
**Issue:** `eq_l` and `eq_r` are always initialized with `Eq10State::new(44100.0)` at open time, before the actual file sample rate is known (mpg123 only reports format after decoding enough header data). For a 48000 Hz or 96000 Hz MP3, every biquad band's center frequency will be wrong — for example the 70 Hz band's angle becomes `2π × 70 / 44100` instead of `2π × 70 / 48000`, shifting it ~9% sharp. The `sample_rate` field on `InnerState` defaults to 44100 but is never updated after the decoder reports the real format.

**Fix:** Detect the real sample rate after the first successful `mpg123_read` (when the format becomes known via `mpg123_getformat`) and rebuild the EQ state if it differs:
```rust
// In the audio callback, after the first successful mpg123_read, call:
let mut rate: libc::c_long = 0;
let mut channels: libc::c_int = 0;
let mut enc: libc::c_int = 0;
mpg123_sys::mpg123_getformat(s.mpg_handle, &mut rate, &mut channels, &mut enc);
if rate as f64 != s.eq_l.rate {
    s.eq_l = Eq10State::new(rate as f64);
    s.eq_r = Eq10State::new(rate as f64);
    s.sample_rate = rate as u32;
}
```
Alternatively, use a separate format-probe step in `manzo_open` after feeding enough data to trigger format detection before constructing `InnerState`.

---

### WR-03: Volume/pan ramp duration hardcoded to 441 frames (assumes 44100 Hz only)

**File:** `manzo-core/src/lib.rs:605, 619`
**Issue:** Both `manzo_set_volume` and `manzo_set_pan` hard-set `vol_ramp_remaining = 441` and `pan_ramp_remaining = 441` respectively, designed for "~10 ms at 44.1 kHz" (D-03). For a 48000 Hz stream, 441 frames = ~9.2 ms (acceptable), but at 96000 Hz, 441 frames = ~4.6 ms, and at 22050 Hz, 441 frames = ~20 ms — audible overshoot. This compounds with WR-02 since `sample_rate` may never be updated from its 44100 default.

**Fix:** Compute the ramp frame count from the actual sample rate stored in state:
```rust
pub extern "C" fn manzo_set_volume(handle: *mut ManzoHandle, volume: f32) {
    ...
    let mut state = arc.lock().unwrap_or_else(|e| e.into_inner());
    state.target_volume = volume.clamp(0.0_f32, 1.0_f32);
    // 10 ms ramp in frames, derived from actual sample rate
    state.vol_ramp_remaining = (state.sample_rate / 100) as u32;
}
```
Same pattern for `manzo_set_pan`.

---

## Info

### IN-01: `frames_written` variable name is misleading — it counts f32 values (samples), not frames

**File:** `manzo-core/src/lib.rs:348`
**Issue:** The variable is computed as `done / 4` (bytes / bytes-per-f32) which yields the number of f32 elements written into `data` (a `&mut [f32]`). For stereo interleaved audio, a "frame" = 2 f32 values. The name `frames_written` implies a different unit than what it represents, which contradicts the comment on line 394 that correctly distinguishes `sz = FRAMES not samples`. The arithmetic itself is correct — `written += frames_written` advances the f32 slice index properly, and `frames_written / channels` recovers the actual frame count for `position_samples`. The misleading name risks future maintainers introducing a double-division bug.

**Fix:**
```rust
let samples_written = done / 4; // bytes → f32 elements (not frames)
written += samples_written;
s.position_samples += samples_written as u64 / s.channels as u64;
```

---

### IN-02: `manzo_stop` does not reset IIR filter delay-line state in `eq_l`/`eq_r`

**File:** `manzo-core/src/lib.rs:468-504`
**Issue:** After stop and replay, `eq_l.band[k].x1/x2/y1/y2` and `eq_r.band[k].x1/x2/y1/y2` retain values from the previous play session. The biquad IIR filter's history will produce a transient impulse response at the start of the next playback — brief but audible for high-gain bands. The limiter's `detect` accumulator similarly carries over.

**Fix:** After setting `state.stream = None`, reset the filter state on each band and the limiter detect:
```rust
for band in state.eq_l.band.iter_mut().chain(state.eq_r.band.iter_mut()) {
    band.x1 = 0.0; band.x2 = 0.0;
    band.y1 = 0.0; band.y2 = 0.0;
}
state.eq_l.detect = 0.0;
state.eq_r.detect = 0.0;
```

---

### IN-03: Integration test `eq_perf_under_100us` uses index 989 for p99 but comment says "index 989 = 99th percentile of 1000 samples"

**File:** `manzo-core/tests/integration_test.rs:265`
**Issue:** The comment is correct and the index is correct (0-based index 989 is the 990th value = 99.0th percentile of 1000 items). However the inline comment reads "99th percentile of 1000 samples" which might be misread as the 990th element being a 99.0% cutoff while actually 10 samples (990–999) exceed it, not 1. The intent is clear from context, but the off-by-one phrasing can confuse auditors. No code defect.

**Fix:** Clarify the comment:
```rust
// index 989 = 990th value (0-based) in a 1000-element sorted array.
// This excludes the top 10 samples (indices 990-999), i.e. the top 1%.
let p99_elapsed_us = timings[989];
```

---

_Reviewed: 2026-04-23_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
